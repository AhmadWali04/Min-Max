# MinMax — System Architecture

**Version:** 0.1  
**Status:** Proposed; validate platform-specific assumptions with a working spike  
**Source of product truth:** [PRD.md](PRD.md)  
**Target:** macOS 14+, Swift 5.10+; adopt Swift 6 strict-concurrency checking incrementally

## 1. Purpose and boundaries

MinMax is a **local, opt-in network intelligence service** for diagnosing latency inflation during competing network workloads and coordinating mitigation with **cooperating applications**. It is not a kernel extension, global traffic interceptor, arbitrary game optimizer, or substitute for router-side Smart Queue Management.

The MVP must prove that independent macOS processes can report telemetry to a central daemon, that the daemon can make explainable, concurrency-safe decisions, and that a cooperating uploader can reduce its own offered load when a controlled bottleneck causes gaming RTT to rise.

### Architectural priorities
1. Correctness and verifiable measurements before optimization.
2. Independent processes with actual IPC, not simulated IPC in one process.
3. Least privilege, explicit opt-in, and privacy-conscious telemetry.
4. Bounded memory, task count, queue depth, and event retention.
5. Resilience to disconnects, restarts, malformed input, and overload.
6. Deterministic core logic that can be tested without network hardware.

## 2. Context and trust boundaries

```text
                 Controlled test network / endpoints
           +----------------+      +-------------------+
           | UDP Echo Server|      | Upload Test Server|
           +-------^--------+      +---------^---------+
                   |                         |
              UDP probes                 TCP/HTTP upload
                   |                         |
+------------------+-------------------------+------------------+
| macOS user session                                           |
|  +----------------+ +-----------------+ +------------------+ |
|  | Game Probe     | | Cooperating     | | Path Probe       | |
|  | Client         | | Uploader        | | NWPathMonitor    | |
|  +--------+-------+ +--------+--------+ +--------+---------+ |
|           |                  |                   |           |
|           +------------------+-------------------+           |
|                              | versioned XPC                 |
|                  +-----------v--------------------+          |
|                  | MinMax background agent     |          |
|                  |                                |          |
|                  | IPC adapter + validation       |          |
|                  | Client/session registry        |          |
|                  | Bounded telemetry ingestion    |          |
|                  | Actor-isolated metrics store   |          |
|                  | Congestion detector            |          |
|                  | Policy state machine           |          |
|                  | Decision/audit history         |          |
|                  +-----------+--------------------+          |
|                              | versioned XPC                 |
|                       +------v-------+                      |
|                       | MinMax CLI|                      |
|                       +--------------+                      |
+-------------------------------------------------------------+
```

**Trust boundaries:** (A) network endpoints and test traffic; (B) client-to-agent XPC boundary; (C) user-to-CLI control boundary; (D) on-disk diagnostics. Client-provided identifiers and metrics are untrusted even when the connection is local.

## 3. Runtime components

| Component | Executable / module | Responsibility | Explicitly not responsible for |
|---|---|---|---|
| Core domain | `MinMaxCore` library | Data contracts, metrics, detector, policy, testable clocks | Sockets, XPC, launchd |
| Agent | `MinMaxDaemon` | XPC endpoint, session registry, bounded ingestion, lifecycle, logs | Measuring all third-party traffic |
| Game probe | `MinMaxGameClient` | UDP request/reply measurement; report RTT/timeouts | Prioritizing arbitrary game packets |
| Echo server | `MinMaxEchoServer` | Controlled UDP echo workload | Production Internet service |
| Uploader | `MinMaxUploader` | Controlled load; application-level rate limiter; acknowledge policy | Modifying unrelated processes |
| Upload server | `MinMaxUploadServer` | Controlled upload sink | Capturing user traffic |
| Path probe | Within a client or separate executable | `NWPathMonitor` metadata | Treating path satisfaction as end-to-end health |
| CLI | `MinMaxCLI` | Query status, set mode, explain decisions, export reports | Mutating daemon internals directly |

The first iteration can build the portable components with Swift Package Manager. **XPC registration, signing, and launchd packaging are platform-dependent decisions to validate with a two-process proof of concept before committing to the final deployment design.** Do not assume a bundled XPC service is an always-on daemon.

## 4. Source layout

```text
MinMax/
├── PRD.md
├── ARCHITECTURE.md
├── AGENTS.md
├── CLAUDE.md                # optional pointer to AGENTS.md
├── TASKS.md
├── README.md
├── Package.swift
├── Sources/
│   ├── MinMaxCore/
│   ├── MinMaxDaemon/
│   ├── MinMaxCLI/
│   ├── MinMaxGameClient/
│   ├── MinMaxEchoServer/
│   ├── MinMaxUploader/
│   └── MinMaxUploadServer/
├── Tests/
│   ├── MinMaxCoreTests/
│   ├── MinMaxIPCTests/
│   └── MinMaxStressTests/
├── Config/launchd/
├── Scenarios/
├── Scripts/
├── Docs/adr/
├── Docs/metrics.md
├── Docs/security.md
├── Docs/benchmarking.md
└── Results/                 # generated, gitignored
```

**Canonical naming:** This uppercase `ARCHITECTURE.md` is authoritative. Avoid maintaining a separate divergent `Docs/architecture.md`.

## 5. Core data model and wire protocol

Keep domain models separate from XPC transport objects. The following are **conceptual** types, not a promise that Swift enums can cross an Objective-C XPC boundary unchanged.

```swift
struct TelemetryEnvelope: Codable, Sendable {
    let protocolVersion: Int
    let sessionID: UUID
    let sequenceNumber: UInt64
    let observedAt: Date
    let kind: TelemetryKind
}

enum TelemetryKind: Codable, Sendable {
    case rttSample(milliseconds: Double)
    case probeTimeout
    case transfer(bytesSent: UInt64, intervalMs: UInt64)
    case pathChanged(interface: String, isSatisfied: Bool)
}

enum NetworkHealth: String, Codable, Sendable {
    case unknown, healthy, degraded, recovering
}
```

### IPC operations (v1 proposal)

| Operation | Direction | Semantics |
|---|---|---|
| `register(clientInfo)` | Client → agent | Returns server-assigned session ID, protocol version, limits |
| `submitTelemetry(batch)` | Client → agent | Validates batch; returns accepted/rejected counts and reason codes |
| `getSnapshot()` | CLI/client → agent | Returns immutable current status |
| `getExplanation()` | CLI → agent | Returns recent evidence, policy state, uncertainty |
| `setMode(mode)` | authorized CLI → agent | Switches observe/protect; requires user opt-in |
| `pollPolicy()` or callback | Agent ↔ uploader | Returns expiring, versioned recommendation |
| `ackPolicy(decisionID, result)` | Uploader → agent | Confirms or rejects application of limit |

**Delivery semantics:** Telemetry is best-effort and may be dropped under overload. Control messages are idempotent by `decisionID`; clients must not apply stale/expired instructions. Choose polling or callbacks only after verifying actual XPC lifecycle behavior.

**Validation:** Cap payload bytes, batch size, sessions, and requests per interval. Reject unsupported protocol versions, nonfinite/negative RTT, invalid intervals, impossible timestamps, duplicate/out-of-order sequences according to an explicit rule, and unauthorized control calls. Use server-assigned session IDs and verify connection identity using mechanisms supported by the chosen packaging/signing arrangement. Do not treat a claimed `clientID` as authentication.

**Time:** Use monotonic clocks for durations and event windows; use wall-clock timestamps only for presentation and coarse cross-process correlation. Sequence numbers and daemon receive timestamps help with ordering. No packet contents, browsing URLs, or game payloads are required.

## 6. Concurrency and data ownership

### Model
- **XPC adapter:** parses and validates messages at the boundary; does not hold locks while invoking callbacks.
- **`TelemetryStore` actor:** owns bounded event buffers, rolling counters, sessions, and immutable snapshot creation.
- **`HealthEvaluator` (pure core):** consumes immutable windows and produces evidence-based health assessments.
- **`PolicyController` actor:** owns policy mode, cooldowns, in-flight decisions, acknowledgements, and expiration.
- **Network clients:** use structured task ownership, bounded retries, explicit cancellation, and isolated connection state.

### Invariants
1. Mutable state has one clear owner.
2. No unbounded `Task` creation, channels, or per-client buffers.
3. XPC callbacks return promptly; CPU-heavy aggregation happens outside the callback path.
4. A slow or crashed client cannot stall the daemon or all other clients.
5. Snapshots are value objects; callers never receive mutable actor-owned storage.
6. No blocking synchronous waits on an actor's hot path.

### Backpressure
Start with a fixed maximum batch size, bounded in-memory event capacity, and per-session rate limit. On overflow, reject or drop telemetry with explicit counters and structured logs. Never silently accumulate memory. Tune limits after load tests; do not invent benchmark targets as achieved results.

## 7. Measurements and health inference

### Measurement definitions
- **RTT:** elapsed monotonic time between sending a sequenced UDP probe and receiving its matching reply; includes application scheduling overhead.
- **Loss:** percentage of sequenced probes without a matching reply by a documented timeout; distinguish late replies from permanent loss.
- **Jitter:** define explicitly (e.g., mean absolute change in successive valid RTT samples); do not present it as RFC 3550 jitter unless implementing that algorithm.
- **p50/p95/p99:** nearest-rank or documented interpolation method; use consistent method in tests/reports.
- **Latency inflation:** rolling p95 RTT minus stable baseline p50 RTT; report sample counts and window boundaries.
- **Throughput:** acknowledged application bytes over measured interval, not inferred link capacity.

Record all metric definitions and exclusions in `Docs/metrics.md` before publishing benchmark claims.

### Congestion detector

```text
UNKNOWN --sufficient samples--> HEALTHY
HEALTHY --sustained inflation + load evidence--> DEGRADED
DEGRADED --opt-in + cooperating uploader--> MITIGATING
MITIGATING --sustained recovery--> RECOVERING
RECOVERING --cooldown complete--> HEALTHY
any state --insufficient evidence--> UNKNOWN
manual disable --> OBSERVE_ONLY (no new mitigation)
```

The PRD's threshold examples (three 10-second windows above +50 ms; recovery below +25 ms) are **starting configuration values**, not validated universal defaults. Require a minimum sample count and corroborating load evidence; single-client spikes should not automatically imply shared congestion. Report uncertainty when attribution is inconclusive.

## 8. Mitigation policy

MVP mitigation affects **only a cooperating uploader**. The policy controller issues an expiring maximum send rate. The uploader applies an application-level token bucket or equivalent pacing mechanism and acknowledges the result. Include lower/upper bounds, cooldown, recovery restoration, manual emergency disable, and safe default behavior if the agent disappears.

**Observe-only is the default.** `protect` must be explicitly enabled. If the daemon or XPC is unavailable, the uploader continues under its own safe default; MinMax must not hold unrelated networking hostage.

Avoid uncontrolled oscillation: use hysteresis, bounded adjustment steps, minimum dwell time, and policy TTLs. Track the cost in upload throughput alongside any latency benefit.

## 9. Lifecycle and deployment

1. Start as foreground CLI processes for rapid development.
2. Prove a minimal signed two-process XPC connection with actual macOS tooling.
3. Choose a compatible listener, registration, code-signing, and per-user launchd arrangement; record the decision in an ADR.
4. Package a **per-user LaunchAgent**; no root privileges for MVP.
5. Implement install/uninstall scripts that show changes and clean up only MinMax-owned files.
6. Test daemon termination, client reconnect, session re-registration, stale session expiry, and cancellation.

Do not assume an Xcode build is sufficient to verify a background service. Verify launchd lifecycle and actual separate-process IPC on macOS.

## 10. Observability, security, and privacy

- Structured `OSLog` events for registration, rejects, health transitions, policy decisions, and reconnects.
- Bounded in-memory history for MVP; local export to JSON/CSV only on user request.
- Scrub secrets, payload content, unnecessary destinations, and personally identifying data.
- Keep diagnostic export metadata: OS version, Swift/build revision, hardware class, scenario config, and test duration.
- Require explicit permission for any test endpoint not owned by the developer.
- No privileged operations, packet capture, or router configuration in MVP.
- Document client identity checks and control-plane authorization in `Docs/security.md`.

## 11. Verification strategy

| Layer | Tests | Gate |
|---|---|---|
| Pure core | Percentiles, windows, clock injection, detector transitions, policy cooldown | Deterministic automated tests |
| UDP loopback | Echo correctness, sequence matching, timeout, late/duplicate replies | Local integration tests |
| IPC | Independent signed processes, malformed payloads, disconnects, authorization | Real macOS integration tests |
| Lifecycle | LaunchAgent start/stop, daemon restart, reconnect | Manual + scripted macOS checks |
| Stress | Concurrent clients, overload, bounded memory, dropped-event accounting | Repeatable stress harness |
| Optimization | Randomized paired trials with and without rate limiting | Raw data + reproducible scripts |

For performance, capture p50/p95/p99 RTT, jitter, loss, upload throughput, idle CPU, RSS, ingest throughput, and event-processing delay. Benchmark against the same controlled bottleneck and disclose variance and tradeoffs. See PRD §3.

## 12. Architecture decisions to record

Create `Docs/adr/ADR-0001-xpc-packaging.md` after the real XPC spike, then record decisions on: actor boundaries, UDP probe protocol, metric formulas, congestion policy thresholds, mitigation pacing algorithm, and benchmark topology. Each ADR: **context → options → decision → consequences → verification**.

## 13. Risks and open questions

1. **XPC packaging:** exact macOS listener/service topology and signing approach must be proven; avoid speculative production code.
2. **Network topology:** loopback alone cannot reproduce router bufferbloat. Use a controlled bottleneck, separate test machine/router, or reproducible network emulator for meaningful claims.
3. **Attribution:** observed latency inflation does not uniquely identify bufferbloat; retain uncertainty.
4. **Optimization scope:** app-level throttling cannot fix ISP latency or uncontrolled third-party traffic.
5. **Agent collaboration:** parallel branches must preserve API contracts and avoid concurrent edits to shared files.

## 14. MVP exit checklist

See [TASKS.md](TASKS.md) for implementation order and [PRD.md](PRD.md) §11 for product-level acceptance criteria. An MVP is complete only when actual macOS builds, separate-process IPC, recovery tests, reproducible benchmarks, and documentation have been verified—not merely generated by an AI agent.
