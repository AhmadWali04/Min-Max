import Foundation
import XCTest
@testable import MinMaxCore

final class ProbeTests: XCTestCase {
    func testWireLayoutAndRoundTrip() throws {
        let packet = ProbePacket(kind: .request, runID: 1, sequence: 0x0102030405060708,
                                 sentAtNanoseconds: UInt64.max)
        let bytes = Array(packet.encoded())
        XCTAssertEqual(bytes.count, 32)
        XCTAssertEqual(Array(bytes.prefix(8)), [0x4d, 0x4d, 0x58, 0x50, 1, 0, 0, 0])
        XCTAssertEqual(Array(bytes[16..<24]), [1, 2, 3, 4, 5, 6, 7, 8])
        XCTAssertEqual(try ProbePacket(decoding: packet.encoded()), packet)
        XCTAssertEqual(try ProbePacket(decoding: packet.reply.encoded()), packet.reply)
    }

    func testRejectsBadLengthsMagicVersionKindAndReservedBits() {
        let bytes = Array(ProbePacket(kind: .request, runID: 0, sequence: 0, sentAtNanoseconds: 0).encoded())
        for count in 0..<32 { XCTAssertThrowsError(try ProbePacket(decoding: Data(bytes.prefix(count)))) }
        XCTAssertThrowsError(try ProbePacket(decoding: Data(bytes + [0])))
        for index in [0, 1, 2, 3, 4, 5, 6, 7] {
            var malformed = bytes
            malformed[index] = 255
            XCTAssertThrowsError(try ProbePacket(decoding: Data(malformed)))
        }
        // Non-zero-based Data slices must also decode safely.
        let prefixed = Data([255] + bytes)
        XCTAssertNoThrow(try ProbePacket(decoding: prefixed.dropFirst()))
    }

    func testMatchRTTAndDuplicate() throws {
        var tracker = try ProbeTracker(runID: 42, timeoutNanoseconds: 10_000_000)
        let packet = try tracker.issue(sequence: 0, now: 100)
        XCTAssertEqual(tracker.receive(packet.reply, now: 2_000_100), .received(milliseconds: 2))
        XCTAssertEqual(tracker.receive(packet.reply, now: 3_000_100), .duplicate)
        XCTAssertEqual(tracker.sent, 1)
        XCTAssertEqual(tracker.received, 1)
        XCTAssertEqual(tracker.timedOut, 0)
        XCTAssertEqual(tracker.inFlight, 0)
    }

    func testUntrustedRepliesCannotConsumePendingProbe() throws {
        var tracker = try ProbeTracker(runID: 42, timeoutNanoseconds: 100)
        let packet = try tracker.issue(sequence: 7, now: 10)
        let wrongRun = ProbePacket(kind: .reply, runID: 43, sequence: 7, sentAtNanoseconds: 10)
        let wrongTime = ProbePacket(kind: .reply, runID: 42, sequence: 7, sentAtNanoseconds: 11)
        let wrongSequence = ProbePacket(kind: .reply, runID: 42, sequence: 8, sentAtNanoseconds: 10)
        for invalid in [packet, wrongRun, wrongTime, wrongSequence] {
            XCTAssertEqual(tracker.receive(invalid, now: 20), .unmatched)
        }
        XCTAssertEqual(tracker.receive(packet.reply, now: 9), .unmatched)
        XCTAssertEqual(tracker.inFlight, 1)
        XCTAssertEqual(tracker.receive(packet.reply, now: 20), .received(milliseconds: 0.00001))
    }

    func testExpiryBoundaryLateReplyAndNoDoubleCounting() throws {
        var tracker = try ProbeTracker(runID: 1, timeoutNanoseconds: 100)
        let packet = try tracker.issue(sequence: 0, now: 1000)
        XCTAssertEqual(tracker.expire(now: 999), 0)
        XCTAssertEqual(tracker.expire(now: 1099), 0)
        XCTAssertEqual(tracker.expire(now: 1100), 1)
        XCTAssertEqual(tracker.expire(now: 1200), 0)
        XCTAssertEqual(tracker.receive(packet.reply, now: 1200), .late)
        XCTAssertEqual(tracker.receive(packet.reply, now: 1300), .late)
        XCTAssertEqual(tracker.timedOut, 1)
        XCTAssertEqual(tracker.received, 0)
    }

    func testReplyAtDeadlineIsLateEvenBeforeExpirySweep() throws {
        var tracker = try ProbeTracker(runID: 1, timeoutNanoseconds: 100)
        let packet = try tracker.issue(sequence: 0, now: 0)
        XCTAssertEqual(tracker.receive(packet.reply, now: 100), .late)
        XCTAssertEqual(tracker.expire(now: 200), 0)
        XCTAssertEqual(tracker.timedOut, 1)
    }

    func testCapacityMonotonicSequenceAndBoundedHistory() throws {
        var tracker = try ProbeTracker(runID: 1, timeoutNanoseconds: 100, maxInFlight: 1)
        let first = try tracker.issue(sequence: 1, now: 0)
        XCTAssertThrowsError(try tracker.issue(sequence: 2, now: 1))
        XCTAssertEqual(tracker.receive(first.reply, now: 1), .received(milliseconds: 0.000001))
        XCTAssertThrowsError(try tracker.issue(sequence: 1, now: 1))
        for sequence in 2...1000 {
            let packet = try tracker.issue(sequence: UInt64(sequence), now: UInt64(sequence))
            XCTAssertEqual(tracker.receive(packet.reply, now: UInt64(sequence)), .received(milliseconds: 0))
        }
        XCTAssertEqual(tracker.receive(first.reply, now: 2000), .unmatched)
        XCTAssertEqual(tracker.received, 1000)
        XCTAssertEqual(tracker.inFlight, 0)
    }

    func testRepliesCanArriveOutOfOrder() throws {
        var tracker = try ProbeTracker(runID: 1, timeoutNanoseconds: 100)
        let first = try tracker.issue(sequence: 0, now: 0)
        let second = try tracker.issue(sequence: 1, now: 10)
        XCTAssertEqual(tracker.receive(second.reply, now: 20), .received(milliseconds: 0.00001))
        XCTAssertEqual(tracker.receive(first.reply, now: 30), .received(milliseconds: 0.00003))
        XCTAssertEqual(tracker.received, 2)
    }

    func testConfigurationBounds() {
        for timeout: UInt64 in [0, 60_000_000_001] {
            XCTAssertThrowsError(try ProbeTracker(runID: 1, timeoutNanoseconds: timeout))
        }
        for capacity in [0, 4097] {
            XCTAssertThrowsError(try ProbeTracker(runID: 1, timeoutNanoseconds: 100, maxInFlight: capacity))
        }
    }
}
