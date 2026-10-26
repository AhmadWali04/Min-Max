import Foundation
import MinMaxCore
import MinMaxUDP
import XCTest

final class UDPSocketTests: XCTestCase {
    func testLoopbackRequestReplyAndMonotonicRTT() throws {
        let server = try UDPSocket()
        defer { server.close() }
        let client = try UDPSocket()
        defer { client.close() }
        try client.connect(host: "127.0.0.1", port: server.localPort)
        var tracker = try ProbeTracker(runID: 42, timeoutNanoseconds: 1_000_000_000)
        let packet = try tracker.issue(sequence: 0, now: DispatchTime.now().uptimeNanoseconds)
        try client.send(packet.encoded())
        XCTAssertTrue(try server.waitReadable(milliseconds: 1000))
        let request = try XCTUnwrap(server.receive())
        let decoded = try ProbePacket(decoding: request.data)
        XCTAssertEqual(decoded, packet)
        try server.reply(decoded.reply.encoded(), to: request)
        XCTAssertTrue(try client.waitReadable(milliseconds: 1000))
        let response = try XCTUnwrap(client.receive())
        let result = tracker.receive(try ProbePacket(decoding: response.data), now: DispatchTime.now().uptimeNanoseconds)
        guard case .received(let milliseconds) = result else { return XCTFail("Expected matching RTT: \(result)") }
        XCTAssertGreaterThanOrEqual(milliseconds, 0)
        XCTAssertLessThan(milliseconds, 1000)
        XCTAssertEqual(tracker.received, 1)
    }

    func testSilentBoundEndpointTimesOut() throws {
        let silentServer = try UDPSocket()
        let client = try UDPSocket()
        defer { silentServer.close(); client.close() }
        try client.connect(host: "127.0.0.1", port: silentServer.localPort)
        var tracker = try ProbeTracker(runID: 1, timeoutNanoseconds: 10_000_000)
        let start = DispatchTime.now().uptimeNanoseconds
        try client.send(tracker.issue(sequence: 0, now: start).encoded())
        XCTAssertFalse(try client.waitReadable(milliseconds: 30))
        XCTAssertEqual(tracker.expire(now: DispatchTime.now().uptimeNanoseconds), 1)
        XCTAssertEqual(tracker.timedOut, 1)
    }

    func testOversizedDatagramsAreNotAcceptedAsValidPrefixes() throws {
        let server = try UDPSocket()
        let client = try UDPSocket()
        defer { server.close(); client.close() }
        try client.connect(host: "127.0.0.1", port: server.localPort)
        let valid = ProbePacket(kind: .request, runID: 0, sequence: 0, sentAtNanoseconds: 0)
        try client.send(valid.encoded() + Data(repeating: 0, count: 100))
        XCTAssertTrue(try server.waitReadable(milliseconds: 1000))
        let received = try XCTUnwrap(server.receive())
        XCTAssertEqual(received.data.count, ProbePacket.byteCount + 1)
        XCTAssertThrowsError(try ProbePacket(decoding: received.data))
    }

    func testCloseIsIdempotentAndPortCanBeRebound() throws {
        let socket = try UDPSocket()
        let port = try socket.localPort
        socket.close()
        socket.close()
        XCTAssertThrowsError(try socket.localPort)
        XCTAssertThrowsError(try socket.receive())
        XCTAssertThrowsError(try socket.waitReadable(milliseconds: 1))
        let replacement = try UDPSocket(port: port)
        replacement.close()
    }

    func testInvalidAddressAndCLIOptions() throws {
        XCTAssertThrowsError(try UDPSocket(bindHost: "not-an-ip"))
        XCTAssertThrowsError(try WorkloadCLI.runEcho(arguments: ["--port", "-1"]))
        XCTAssertThrowsError(try WorkloadCLI.runEcho(arguments: ["--duration-seconds", "0"]))
        XCTAssertThrowsError(try WorkloadCLI.runProbe(arguments: ["--count", "0"]))
        XCTAssertThrowsError(try WorkloadCLI.runProbe(arguments: ["--interval-ms", "0"]))
        XCTAssertThrowsError(try WorkloadCLI.runProbe(arguments: ["--timeout-ms", "60001"]))
        XCTAssertThrowsError(try WorkloadCLI.runProbe(arguments: ["--port"]))
        XCTAssertThrowsError(try WorkloadCLI.runProbe(arguments: ["--unknown", "1"]))
        XCTAssertThrowsError(try WorkloadCLI.runProbe(arguments: ["--count", "1", "--count", "2"]))
    }
}
