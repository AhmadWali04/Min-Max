import Darwin
import Dispatch
import Foundation
import MinMaxCore

/// Signal callbacks share only this locked flag. All socket/probe state stays
/// on the foreground thread; there are no per-packet tasks or user-space queues.
private final class StopFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    func stop() { lock.lock(); stopped = true; lock.unlock() }
    var isStopped: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
}

private final class SignalScope {
    let flag = StopFlag()
    private var sources: [DispatchSourceSignal] = []
    // SIG_DFL is represented as a nil C function pointer on Darwin.
    private let previousInterrupt: sig_t?
    private let previousTermination: sig_t?
    init() {
        previousInterrupt = signal(SIGINT, SIG_IGN)
        previousTermination = signal(SIGTERM, SIG_IGN)
        let queue = DispatchQueue(label: "MinMax.workload.signals")
        for number in [SIGINT, SIGTERM] {
            let source = DispatchSource.makeSignalSource(signal: number, queue: queue)
            let flag = flag
            source.setEventHandler { flag.stop() }
            source.activate()
            sources.append(source)
        }
    }
    deinit {
        for source in sources { source.cancel() }
        signal(SIGINT, previousInterrupt)
        signal(SIGTERM, previousTermination)
    }
}

private struct Options {
    var values: [String: String] = [:]
    init(_ arguments: [String], allowed: Set<String>) throws {
        var index = 0
        while index < arguments.count {
            let key = arguments[index]
            guard allowed.contains(key), values[key] == nil, index + 1 < arguments.count else {
                throw UDPError(message: "unknown, repeated, or incomplete option: \(key); use --help")
            }
            values[key] = arguments[index + 1]
            index += 2
        }
    }
    func integer(_ key: String, default fallback: Int, range: ClosedRange<Int>) throws -> Int {
        guard let raw = values[key] else { return fallback }
        guard let value = Int(raw), range.contains(value) else {
            throw UDPError(message: "\(key) must be an integer in \(range)")
        }
        return value
    }
}

public enum WorkloadCLI {
    public static func runEcho(arguments: [String]) throws {
        if arguments == ["--help"] {
            print("MinMaxEchoServer [--host 127.0.0.1] [--port 9999] [--duration-seconds 60]")
            print("Controlled IPv4 UDP echo endpoint; defaults to loopback. SIGINT/SIGTERM stop cleanly.")
            return
        }
        let options = try Options(arguments, allowed: ["--host", "--port", "--duration-seconds"])
        let host = options.values["--host"] ?? "127.0.0.1"
        let port = try options.integer("--port", default: 9999, range: 0...65535)
        let duration = try options.integer("--duration-seconds", default: 60, range: 1...86400)
        let socket = try UDPSocket(bindHost: host, port: UInt16(port))
        defer { socket.close() }
        let signals = SignalScope()
        let start = DispatchTime.now().uptimeNanoseconds
        print("listening host=\(host) port=\(try socket.localPort)")
        fflush(stdout)
        var echoed = 0
        var rejected = 0
        while !signals.flag.isStopped && DispatchTime.now().uptimeNanoseconds - start < UInt64(duration) * 1_000_000_000 {
            guard try socket.waitReadable(milliseconds: 50), let datagram = try socket.receive() else { continue }
            guard let packet = try? ProbePacket(decoding: datagram.data), packet.kind == .request else {
                rejected += 1
                continue
            }
            try socket.reply(packet.reply.encoded(), to: datagram)
            echoed += 1
        }
        print("stopped echoed=\(echoed) rejected=\(rejected)")
    }

    public static func runProbe(arguments: [String]) throws {
        if arguments == ["--help"] {
            print("MinMaxGameClient [--host 127.0.0.1] [--port 9999] [--count 20] [--interval-ms 50] [--timeout-ms 1000]")
            print("Use only endpoints you control or have permission to test. Prints RTT and a JSON summary.")
            return
        }
        let options = try Options(arguments, allowed: ["--host", "--port", "--count", "--interval-ms", "--timeout-ms"])
        let host = options.values["--host"] ?? "127.0.0.1"
        let port = try options.integer("--port", default: 9999, range: 1...65535)
        let count = try options.integer("--count", default: 20, range: 1...100_000)
        let interval = UInt64(try options.integer("--interval-ms", default: 50, range: 1...60_000)) * 1_000_000
        let timeout = UInt64(try options.integer("--timeout-ms", default: 1000, range: 1...60_000)) * 1_000_000
        let socket = try UDPSocket(bindHost: "0.0.0.0")
        defer { socket.close() }
        try socket.connect(host: host, port: UInt16(port))
        let signals = SignalScope()
        var tracker = try ProbeTracker(runID: UInt64.random(in: .min ... .max), timeoutNanoseconds: timeout)
        var nextSend = DispatchTime.now().uptimeNanoseconds
        var duplicates = 0, late = 0, unmatched = 0, malformed = 0
        while !signals.flag.isStopped && (tracker.sent < count || tracker.inFlight > 0) {
            let now = DispatchTime.now().uptimeNanoseconds
            tracker.expire(now: now)
            if tracker.sent < count && now >= nextSend && tracker.inFlight < tracker.maxInFlight {
                let packet = try tracker.issue(sequence: UInt64(tracker.sent), now: now)
                try socket.send(packet.encoded())
                // No catch-up burst after scheduler delays or capacity stalls.
                nextSend = DispatchTime.now().uptimeNanoseconds + interval
            }
            let current = DispatchTime.now().uptimeNanoseconds
            let untilSend = nextSend > current ? nextSend - current : 0
            let wait: Int32 = tracker.sent < count && tracker.inFlight < tracker.maxInFlight
                ? Int32(min(50, (untilSend + 999_999) / 1_000_000)) : 50
            guard try socket.waitReadable(milliseconds: wait), let datagram = try socket.receive() else { continue }
            guard let packet = try? ProbePacket(decoding: datagram.data) else { malformed += 1; continue }
            switch tracker.receive(packet, now: DispatchTime.now().uptimeNanoseconds) {
            case .received(let milliseconds): print("rtt sequence=\(packet.sequence) milliseconds=\(milliseconds)")
            case .duplicate: duplicates += 1
            case .late: late += 1
            case .unmatched: unmatched += 1
            }
        }
        tracker.expire(now: DispatchTime.now().uptimeNanoseconds)
        let completed = tracker.received + tracker.timedOut
        let summary = Summary(sent: tracker.sent, received: tracker.received, timedOut: tracker.timedOut,
                              cancelled: tracker.inFlight, duplicates: duplicates, late: late,
                              unmatched: unmatched, malformed: malformed,
                              timeoutMilliseconds: timeout / 1_000_000,
                              lossPercent: completed > 0 ? Double(tracker.timedOut) / Double(completed) * 100 : nil)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        print(String(decoding: try encoder.encode(summary), as: UTF8.self))
    }

    private struct Summary: Encodable {
        let sent: Int, received: Int, timedOut: Int, cancelled: Int
        let duplicates: Int, late: Int, unmatched: Int, malformed: Int
        let timeoutMilliseconds: UInt64
        let lossPercent: Double?
    }
}
