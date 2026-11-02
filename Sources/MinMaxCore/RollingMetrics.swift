import Foundation

public enum MetricsError: Error, Equatable {
    case invalidConfiguration, invalidRTT, timeMovedBackward
}

/// Completion-order observations. A late reply is diagnostic only: its probe
/// must already have contributed one timeout, and must not contribute another.
public enum ProbeObservation: Sendable {
    case reply(milliseconds: Double)
    case timeout
    case lateReply
}

public struct MetricsSnapshot: Sendable {
    public let windowStartNanoseconds: UInt64
    public let windowEndNanoseconds: UInt64
    public let sampleCount: Int
    public let timeoutCount: Int
    public let lateReplyCount: Int
    public let p50Milliseconds: Double?
    public let p95Milliseconds: Double?
    public let p99Milliseconds: Double?
    public let jitterMilliseconds: Double?
    public let lossPercent: Double?
    /// Lifetime capacity evictions, separate from normal time expiration.
    public let capacityEvictions: UInt64
}

/// Single-owner value state; timestamps are supplied by the caller's monotonic
/// clock. Retains at most capacity observations in the interval (now-window, now].
/// No transport, wall clock, pending-probe tracking, or per-event tasks.
public struct RollingMetrics: Sendable {
    private struct Entry: Sendable {
        let time: UInt64
        let observation: ProbeObservation
    }
    public let windowNanoseconds: UInt64
    public let capacity: Int
    private var entries: [Entry?]
    private var head = 0
    private var count = 0
    private var latestTime: UInt64?
    private var capacityEvictions: UInt64 = 0
    public var retainedCount: Int { count }

    public init(windowNanoseconds: UInt64, capacity: Int) throws {
        guard windowNanoseconds > 0, (1...1_000_000).contains(capacity) else {
            throw MetricsError.invalidConfiguration
        }
        self.windowNanoseconds = windowNanoseconds
        self.capacity = capacity
        entries = Array(repeating: nil, count: capacity)
    }

    public mutating func record(_ observation: ProbeObservation, at now: UInt64) throws {
        if case .reply(let value) = observation {
            guard value.isFinite, value >= 0 else { throw MetricsError.invalidRTT }
        }
        try advance(to: now)
        if count == capacity {
            removeOldest()
            if capacityEvictions < UInt64.max { capacityEvictions += 1 }
        }
        entries[(head + count) % capacity] = Entry(time: now, observation: observation)
        count += 1
    }

    public mutating func snapshot(at now: UInt64) throws -> MetricsSnapshot {
        try advance(to: now)
        var samples: [Double] = []
        var timeouts = 0, late = 0
        for offset in 0..<count {
            guard let entry = entries[(head + offset) % capacity] else { continue }
            switch entry.observation {
            case .reply(let value): samples.append(value)
            case .timeout: timeouts += 1
            case .lateReply: late += 1
            }
        }
        // Divide each term before summing to avoid overflow for finite RTTs.
        var jitter: Double?
        if samples.count >= 2 {
            let divisor = Double(samples.count - 1)
            jitter = zip(samples.dropFirst(), samples).reduce(0) { $0 + abs($1.0 - $1.1) / divisor }
        }
        let sorted = samples.sorted()
        func percentile(_ percent: Int) -> Double? {
            guard !sorted.isEmpty else { return nil }
            let rank = (sorted.count * percent + 99) / 100
            return sorted[rank - 1]
        }
        let completed = samples.count + timeouts
        return MetricsSnapshot(
            windowStartNanoseconds: now >= windowNanoseconds ? now - windowNanoseconds : 0,
            windowEndNanoseconds: now, sampleCount: samples.count, timeoutCount: timeouts,
            lateReplyCount: late, p50Milliseconds: percentile(50),
            p95Milliseconds: percentile(95), p99Milliseconds: percentile(99),
            jitterMilliseconds: jitter,
            lossPercent: completed > 0 ? Double(timeouts) / Double(completed) * 100 : nil,
            capacityEvictions: capacityEvictions)
    }

    private mutating func advance(to now: UInt64) throws {
        guard latestTime.map({ now >= $0 }) ?? true else { throw MetricsError.timeMovedBackward }
        latestTime = now
        while count > 0, let first = entries[head], now - first.time >= windowNanoseconds {
            removeOldest()
        }
    }

    private mutating func removeOldest() {
        entries[head] = nil
        head = (head + 1) % capacity
        count -= 1
    }
}
