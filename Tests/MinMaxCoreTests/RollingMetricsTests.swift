import XCTest
@testable import MinMaxCore

final class RollingMetricsTests: XCTestCase {
    func testEmptyAndSingleSample() throws {
        var metrics = try RollingMetrics(windowNanoseconds: 100, capacity: 20)
        let empty = try metrics.snapshot(at: 0)
        XCTAssertNil(empty.p50Milliseconds)
        XCTAssertNil(empty.jitterMilliseconds)
        XCTAssertNil(empty.lossPercent)
        try metrics.record(.reply(milliseconds: 7), at: 0)
        let single = try metrics.snapshot(at: 0)
        XCTAssertEqual(single.p99Milliseconds, 7)
        XCTAssertNil(single.jitterMilliseconds)
        XCTAssertEqual(single.lossPercent, 0)
    }

    func testClaudePercentileAndJitterVectors() throws {
        var metrics = try RollingMetrics(windowNanoseconds: 100, capacity: 20)
        for value in 1...20 { try metrics.record(.reply(milliseconds: Double(value)), at: UInt64(value)) }
        let result = try metrics.snapshot(at: 20)
        XCTAssertEqual(result.sampleCount, 20)
        XCTAssertEqual(result.p50Milliseconds, 10)
        XCTAssertEqual(result.p95Milliseconds, 19)
        XCTAssertEqual(result.p99Milliseconds, 20)
        var jitter = try RollingMetrics(windowNanoseconds: 100, capacity: 20)
        for value in [20.0, 22, 19, 25, 18, 21] { try jitter.record(.reply(milliseconds: value), at: 0) }
        XCTAssertEqual(try XCTUnwrap(jitter.snapshot(at: 0).jitterMilliseconds), 4.2, accuracy: 0.000001)
    }

    func testOutlierAndCompletionOrder() throws {
        var metrics = try RollingMetrics(windowNanoseconds: 100, capacity: 10)
        for value in [70.0, 10, 60, 20, 50, 30, 40] { try metrics.record(.reply(milliseconds: value), at: 0) }
        let result = try metrics.snapshot(at: 0)
        XCTAssertEqual(result.p50Milliseconds, 40)
        XCTAssertEqual(result.p95Milliseconds, 70)
        XCTAssertEqual(result.p99Milliseconds, 70)
        XCTAssertEqual(try XCTUnwrap(result.jitterMilliseconds), 35, accuracy: 0.000001)
    }

    func testLateRepliesNeverUndoTimeoutLoss() throws {
        var metrics = try RollingMetrics(windowNanoseconds: 100, capacity: 30)
        for _ in 0..<18 { try metrics.record(.reply(milliseconds: 10), at: 0) }
        try metrics.record(.timeout, at: 0)
        try metrics.record(.timeout, at: 0)
        try metrics.record(.lateReply, at: 1)
        let result = try metrics.snapshot(at: 1)
        XCTAssertEqual(result.lossPercent, 10)
        XCTAssertEqual(result.sampleCount, 18)
        XCTAssertEqual(result.timeoutCount, 2)
        XCTAssertEqual(result.lateReplyCount, 1)
    }

    func testExpirationBoundaryAndRingWraparound() throws {
        var metrics = try RollingMetrics(windowNanoseconds: 10, capacity: 2)
        for time in 0..<100 { try metrics.record(.reply(milliseconds: Double(time)), at: UInt64(time)) }
        XCTAssertEqual(metrics.retainedCount, 2)
        let full = try metrics.snapshot(at: 99)
        XCTAssertEqual(full.capacityEvictions, 98)
        XCTAssertEqual(full.p50Milliseconds, 98)
        XCTAssertEqual(try metrics.snapshot(at: 108).sampleCount, 1)
        let expired = try metrics.snapshot(at: 109)
        XCTAssertEqual(expired.sampleCount, 0)
        XCTAssertNil(expired.jitterMilliseconds)
        XCTAssertEqual(expired.windowStartNanoseconds, 99)
        XCTAssertEqual(expired.windowEndNanoseconds, 109)
    }

    func testValidationDoesNotMutateState() throws {
        XCTAssertThrowsError(try RollingMetrics(windowNanoseconds: 0, capacity: 1))
        XCTAssertThrowsError(try RollingMetrics(windowNanoseconds: 10, capacity: 0))
        var metrics = try RollingMetrics(windowNanoseconds: 10, capacity: 2)
        try metrics.record(.timeout, at: 20)
        for invalid in [-1.0, .nan, .infinity] {
            XCTAssertThrowsError(try metrics.record(.reply(milliseconds: invalid), at: 100))
        }
        XCTAssertThrowsError(try metrics.record(.timeout, at: 19))
        XCTAssertEqual(try metrics.snapshot(at: 20).timeoutCount, 1)
    }
}
