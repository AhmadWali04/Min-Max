/// Pure, single-owner state with injected monotonic nanoseconds. Storage is
/// bounded by maxInFlight plus twice that many recent completion identities.
public struct ProbeTracker: Sendable {
    public enum ReplyResult: Equatable, Sendable {
        case received(milliseconds: Double), duplicate, late, unmatched
    }
    private enum Completion: Sendable { case received, timedOut }
    public let runID: UInt64
    public let timeoutNanoseconds: UInt64
    public let maxInFlight: Int
    private var pending: [UInt64: UInt64] = [:]
    private var recent: [UInt64: (UInt64, Completion)] = [:]
    private var completionOrder: [UInt64] = []
    private var lastSequence: UInt64?
    public private(set) var sent = 0
    public private(set) var received = 0
    public private(set) var timedOut = 0
    public var inFlight: Int { pending.count }

    public init(runID: UInt64, timeoutNanoseconds: UInt64, maxInFlight: Int = 128) throws {
        guard timeoutNanoseconds > 0, timeoutNanoseconds <= 60_000_000_000,
              (1...4096).contains(maxInFlight) else { throw ProbeError.invalidConfiguration }
        self.runID = runID
        self.timeoutNanoseconds = timeoutNanoseconds
        self.maxInFlight = maxInFlight
    }

    public mutating func issue(sequence: UInt64, now: UInt64) throws -> ProbePacket {
        guard lastSequence.map({ sequence > $0 }) ?? true else { throw ProbeError.invalidSequence }
        guard inFlight < maxInFlight else { throw ProbeError.capacityReached }
        lastSequence = sequence
        pending[sequence] = now
        sent += 1
        return ProbePacket(kind: .request, runID: runID, sequence: sequence, sentAtNanoseconds: now)
    }

    @discardableResult
    public mutating func expire(now: UInt64) -> Int {
        let expired = pending.filter { now >= $0.value && now - $0.value >= timeoutNanoseconds }
        for (sequence, start) in expired {
            pending.removeValue(forKey: sequence)
            remember(sequence, start, .timedOut)
        }
        timedOut += expired.count
        return expired.count
    }

    public mutating func receive(_ packet: ProbePacket, now: UInt64) -> ReplyResult {
        guard packet.kind == .reply, packet.runID == runID else { return .unmatched }
        if let start = pending[packet.sequence] {
            guard packet.sentAtNanoseconds == start, now >= start else { return .unmatched }
            pending.removeValue(forKey: packet.sequence)
            if now - start >= timeoutNanoseconds {
                timedOut += 1
                remember(packet.sequence, start, .timedOut)
                return .late
            }
            received += 1
            remember(packet.sequence, start, .received)
            return .received(milliseconds: Double(now - start) / 1_000_000)
        }
        guard let (start, completion) = recent[packet.sequence],
              start == packet.sentAtNanoseconds else { return .unmatched }
        return completion == .received ? .duplicate : .late
    }

    private mutating func remember(_ sequence: UInt64, _ start: UInt64, _ completion: Completion) {
        recent[sequence] = (start, completion)
        completionOrder.append(sequence)
        if completionOrder.count > maxInFlight * 2 {
            recent.removeValue(forKey: completionOrder.removeFirst())
        }
    }
}
