# MinMax — Product Requirements Document

**Version:** 0.1 (implementation-ready MVP)  
**Status:** Draft  
**Target platform:** macOS 14+  
**Primary language:** Swift 5.10+ (Swift 6 concurrency checks where practical)  
**Secondary language (stretch):** Objective-C XPC client  
**Product type:** Local network intelligence daemon + developer CLI + controlled test clients

## 1. Product vision

**MinMax protects latency-sensitive traffic from avoidable local congestion.** It is a macOS background service that aggregates telemetry from independent processes, diagnoses elevated latency under load, and coordinates opt-in mitigation for applications it controls. A reproducible gaming-traffic simulator makes improvements measurable.

**Tagline:** *Keep the game responsive, even when the network is busy.*

### The story
A gamer experiences 25 ms round-trip latency until a large background upload starts. Latency rises dramatically despite Wi-Fi remaining connected. MinMax correlates reports from the game simulator, upload client, and network probes, detects likely queueing congestion, and asks the cooperating uploader to reduce its sending rate. The demo compares latency and throughput before and after mitigation.

### Why a daemon?
A centralized, long-lived service maintains a common view of network health across independent processes, retains recent history, applies consistent policy, and allows clients to subscribe to status changes. Ordinary apps have only their own observations unless they explicitly share them. MinMax is **not** a privileged systemwide packet inspector.

## 2. Audience and goals

**Primary user:** Developer or technically inclined gamer who wants to understand and mitigate latency spikes during competing transfers.  
**Secondary audience:** OS/networking engineers reviewing the implementation and benchmark evidence.

### Product goals
1. Detect elevated latency during controlled network load with explainable, reproducible evidence.
2. Collect telemetry concurrently from at least three separate client processes through IPC.
3. Reduce observed game-simulator latency by adjusting **cooperating** background traffic, when congestion is controllable.
4. Run reliably as a `launchd`-managed macOS background service with bounded resource usage.
5. Produce transparent before/after measurements, including tradeoffs in background throughput.
6. Demonstrate Swift concurrency, IPC, networking, failure recovery, testing, and systems-level observability.

### Non-goals for MVP
- Guaranteeing lower ping for arbitrary commercial games.
- Inspecting all traffic or collecting other apps' private network telemetry.
- Changing global QoS priorities, cellular routing, or ISP behavior.
- Kernel extensions, packet interception, VPN tunneling, or unapproved privileged access.
- A polished graphical interface, ML-based optimization, or cloud accounts.
- Automatic router configuration without explicit authorization and rollback.

## 3. Success criteria

| Area | MVP acceptance criterion |
|---|---|
| IPC | Three independent executables connect, submit telemetry, and request state over XPC. |
| Concurrency | No known data races under stress tests; bounded ingestion with documented overload policy. |
| Monitoring | Report p50/p95/p99 RTT, jitter definition, loss rate, and measurement window for the controlled UDP simulator. |
| Detection | Correctly identify at least 90% of predefined *synthetic* congestion scenarios, with false-positive rate reported separately; thresholds tuned only on development scenarios. |
| Mitigation | Under at least one reproducible bottleneck scenario, show lower p95 RTT with mitigation than without; disclose throughput cost and trials where no benefit occurs. |
| Reliability | Client reconnects after daemon restart; stale clients expire; no unbounded event growth. |
| Performance | Report measured idle CPU, RSS memory, ingest throughput, and p95 event-processing delay; no invented targets presented as achieved. |
| Reproducibility | One documented script starts the test server, daemon, clients, and benchmark; outputs machine-readable results. |
| Security | Only intended local clients may submit/control reports; malformed or oversized messages are rejected. |

**Benchmark protocol:** Warm up, run at least 10 paired baseline/mitigation trials in randomized order, fix test duration and offered load, report median and dispersion, and preserve raw CSV/JSON data. Run on the same Mac, network, and bottleneck configuration. Do not claim a percentage improvement until measured.

## 4. Core user journeys

### Journey A — Diagnose lag
1. User runs `MinMax status`.
2. CLI queries the daemon and shows active clients, path status, baseline RTT, rolling RTT, jitter, loss, and current health state.
3. User runs `MinMax explain` to see the evidence and confidence/limitations behind the diagnosis.

### Journey B — Demonstrate congestion and mitigation
1. User launches `MinMax demo start` (or the documented individual processes).
2. A UDP game simulator measures RTT against a test server.
3. A cooperating bulk uploader saturates a controlled bottleneck.
4. Daemon detects sustained latency inflation and confirms that multiple observations support local congestion.
5. Policy engine sends an opt-in rate-limit instruction to the uploader.
6. Uploader acknowledges the new limit; CLI displays the RTT and throughput tradeoff.
7. User runs `MinMax report --format json` to export trial results.

### Journey C — Survive failures
1. Kill a client while it is sending events; daemon continues.
2. Restart client; it reconnects with a fresh session identity.
3. Restart daemon; clients retry with bounded exponential backoff and re-register.
4. CLI shows recovery events without duplicating stale sessions.

## 5. Functional requirements

### P0 — Required for MVP

**FR-01: Daemon lifecycle**  
A per-user `launchd` LaunchAgent runs the background service. Support start/stop/status, clean signal handling, log collection, and documented installation/uninstallation. A LaunchAgent is sufficient for the MVP; a privileged LaunchDaemon is not required.

**FR-02: XPC communication**  
Define a versioned request/response protocol for client registration, telemetry submission, snapshot queries, and policy acknowledgements. Prefer Foundation `NSXPCConnection` / `NSXPCListener` for a Swift macOS executable; verify the exact listener/service arrangement for the selected packaging model before implementation. Use `Codable` payloads encoded into an explicitly validated transport envelope where appropriate. Authenticate/restrict connections using the selected deployment model and code-signing/audit-token capabilities where available; never trust client-provided IDs alone.

**FR-03: Telemetry collection**  
Each client reports timestamp, session ID, workload type, request/packet counts, successful RTT samples, failures, and path metadata it can legitimately observe. Record monotonic timing for durations; use wall-clock time only for presentation/correlation. Avoid storing packet payloads or user browsing destinations.

**FR-04: Network-path monitoring**  
Use `NWPathMonitor` to record interface/path availability and expensive/constrained status where supported. Do not equate a satisfied path with end-to-end connectivity or treat path status as RTT.

**FR-05: Central state aggregation**  
Use Swift actors or other explicit synchronization for state. Maintain rolling windows (e.g., 10 s and 60 s), cap memory, expire stale clients, and keep a bounded ring buffer of recent events.

**FR-06: Congestion detection**  
Track latency inflation against a baseline: `inflation = rolling_p95_RTT - baseline_p50_RTT`. Combine with evidence of offered load and affected clients. Require a minimum sample count and sustained violation over multiple windows; use separate enter/exit thresholds (hysteresis). Report `unknown` when evidence is insufficient. Avoid claiming to identify router bufferbloat conclusively from application timing alone.

**FR-07: Mitigation policy**  
Send rate-limit recommendations only to cooperating test uploader(s). Require explicit opt-in to auto-apply; otherwise run in observe-only mode. Bound the minimum and maximum rates, add cooldowns, restore rates on recovery, and provide a one-command emergency disable. Preserve a policy decision log.

**FR-08: CLI**  
Implement `MinMax status`, `MinMax clients`, `MinMax explain`, `MinMax mode observe|protect`, `MinMax demo`, and `MinMax report`. CLI must work without a GUI.

**FR-09: Controlled simulator**  
Build a UDP echo server and a UDP game-traffic client with sequence numbers, timestamps, timeout handling, and configurable send cadence. Loss is defined by missing replies within a declared timeout; jitter calculation must be documented. Provide a bulk TCP/HTTP uploader with a configurable application-level rate limiter and a test server. All traffic must target endpoints the developer controls or has permission to test.

**FR-10: Logs and export**  
Use `OSLog` for structured daemon events. Export anonymized benchmark metrics to JSON/CSV with scenario configuration and software/hardware version metadata.

**FR-11: Tests**  
Unit-test window aggregation, percentile calculation, baseline tracking, policy transitions, cooldowns, expiration, malformed inputs, and retry behavior. Integration-test XPC with real separate processes. Add stress tests and a deterministic simulation mode with injected clock/events.

### P1 — Valuable after MVP
- Incident replay (`MinMax replay <id>`) with a timeline of observations, decisions, and acknowledgements.
- Objective-C sample client demonstrating interoperability with Swift daemon interfaces.
- Fault injection for delay, loss, DNS failures, and connection resets inside a controlled proxy/harness.
- Anomaly classification: distinguish likely local contention from remote-server or DNS-specific failures, including explicit uncertainty.
- Local history persistence with size and retention controls.

### P2 — Stretch
- OpenWrt router integration to measure and optionally configure SQM (CAKE/fq_codel) with explicit user approval, backups, safe rollback, and a tested supported-device matrix.
- Optional minimal macOS menu-bar status display.
- Multiple test machines reporting to one coordinator, with authenticated communications and clock-skew handling.

## 6. Architecture

```text
+-------------------+  +--------------------+  +-------------------+
| UDP Game Client   |  | Cooperating Upload |  | Path/Probe Client |
| RTT/jitter/loss   |  | throughput + limits|  | NWPathMonitor     |
+---------+---------+  +----------+---------+  +---------+---------+
          |                       |                      |
          +-----------------------+----------------------+
                                  |
                           XPC (versioned)
                                  |
                     +------------v-------------+
                     | MinMax Agent (Swift)   |
                     |--------------------------|
                     | Client Registry          |
                     | Ingestion / Validation   |
                     | Actor-isolated State     |
                     | Rolling Metrics          |
                     | Congestion Detector      |
                     | Policy State Machine     |
                     | OSLog + Bounded History  |
                     +------------+-------------+
                                  |
                           XPC queries/events
                                  |
                     +------------v-------------+
                     | CLI + JSON/CSV Reports    |
                     +--------------------------+
```

### Design principles
- **Separate processes:** client isolation is essential, not a set of classes in one executable.
- **Observe before control:** no mitigation until baseline measurements and evidence are available.
- **Least privilege:** no root requirement in MVP.
- **Bounded work:** cap queue length, event size, client count, retention, and concurrent tasks.
- **Explainability:** every policy transition records the evidence and threshold that triggered it.
- **Graceful degradation:** if daemon/XPC is unavailable, clients continue operating without optimization.

## 7. Data contracts (conceptual)

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

struct PolicyRecommendation: Codable, Sendable {
    let decisionID: UUID
    let targetSessionID: UUID
    let maxUploadBytesPerSecond: UInt64
    let expiresAt: Date
    let reason: String
}
```

**Contract rules:** Version every envelope; reject unsupported versions, invalid numerical values (NaN/infinity/negative RTT), impossible timestamps, replayed/out-of-order sequences according to documented policy, and oversized messages. Treat client reports as untrusted. XPC's Objective-C interface boundaries may require transport DTOs instead of exposing Swift enums directly; the types above represent the logical domain model, not a promised drop-in XPC ABI.

## 8. Policy state machine

```text
UNKNOWN --enough samples--> HEALTHY
HEALTHY --sustained inflation + load--> DEGRADED
DEGRADED --opt-in + controllable uploader--> MITIGATING
MITIGATING --sustained recovery--> RECOVERING
RECOVERING --stable cooldown--> HEALTHY
any state --insufficient data--> UNKNOWN
any state --manual disable--> OBSERVE_ONLY
```

Initial thresholds are **configuration values to calibrate**, not claims of optimality. Example prototype values: baseline from the last stable 60 s; degrade if p95 RTT exceeds baseline by 50 ms for three consecutive 10 s windows with sufficient samples; recover only after two windows below a lower 25 ms inflation threshold. Tests must include short spikes that should not trigger mitigation, and persistent failures that should.

## 9. Repository structure

```text
MinMax/
├── PRD.md
├── README.md
├── Package.swift
├── Sources/
│   ├── MinMaxCore/           # models, metrics, state machine
│   ├── MinMaxDaemon/         # XPC listener, lifecycle, logging
│   ├── MinMaxCLI/            # commands and report rendering
│   ├── MinMaxGameClient/     # UDP RTT workload
│   ├── MinMaxEchoServer/     # UDP echo endpoint
│   ├── MinMaxUploader/       # cooperating load generator
│   └── MinMaxUploadServer/   # controlled upload endpoint
├── Tests/
│   ├── MinMaxCoreTests/
│   ├── MinMaxIPCTests/
│   └── MinMaxStressTests/
├── Config/
│   └── launchd/                # LaunchAgent plist template
├── Scripts/
│   ├── install-agent.sh
│   ├── uninstall-agent.sh
│   ├── run-demo.sh
│   └── benchmark.sh
├── Scenarios/
│   ├── idle.json
│   ├── upload-congestion.json
│   └── client-restart.json
├── Docs/
│   ├── architecture.md
│   ├── security.md
│   ├── metrics.md
│   └── benchmarking.md
└── Results/                    # generated data, gitignored
```

**Build note:** Swift Package Manager can build most executables and shared logic. The daemon's actual XPC packaging, signing, and `launchd` registration may require a small Xcode project or deployment-specific configuration; validate this early rather than assuming SPM alone solves service registration.

## 10. Delivery milestones

| Week | Deliverable | Exit criteria |
|---|---|---|
| 1 | UDP simulator + echo server | CLI prints RTT distribution, jitter, loss with known-good local tests. |
| 2 | Core metrics + deterministic tests | Rolling windows, percentiles, health-state transitions unit-tested. |
| 3 | Real XPC between independent executables | Three clients register, send events, query daemon. |
| 4 | `launchd` integration + resilience | Agent starts reliably; reconnect/restart scenarios pass. |
| 5 | Congestion detection | Controlled load triggers explainable state changes without reacting to short spikes. |
| 6 | Cooperating upload mitigation | Rate limiter follows daemon decisions; manual disable works. |
| 7 | Benchmarks + fault tests | Repeated trials, raw data, failure recovery and resource measurements. |
| 8 | Demo + documentation | Reproducible demo, clear limitations, architecture/security notes, measured results. |

## 11. MVP definition of done

- [ ] A macOS LaunchAgent runs the Swift daemon without a GUI.
- [ ] Three independent clients communicate over authenticated/restricted XPC.
- [ ] The game simulator measures RTT, jitter, and packet loss against a controlled server.
- [ ] The daemon aggregates recent events without data races or unbounded memory growth.
- [ ] The congestion detector uses sustained evidence, minimum samples, and hysteresis.
- [ ] An opt-in policy throttles a cooperating upload client, not arbitrary applications.
- [ ] CLI explains network status and policy decisions.
- [ ] Recovery after client/daemon restart is demonstrated.
- [ ] A benchmark compares unmitigated and mitigated conditions with throughput tradeoffs.
- [ ] README includes setup, permissions, limitations, tests, demo video, and real measured results.

## 12. Risks and mitigations

| Risk | Mitigation |
|---|---|
| macOS APIs cannot control arbitrary game traffic | Optimize only cooperating test traffic for MVP; label limitations clearly. |
| Network tests are noisy | Use a controlled bottleneck, repeat trials, and report variance. |
| XPC deployment is complex | Prove a minimal signed two-process XPC spike in week 3 before scaling. |
| Probe traffic itself affects network | Use configurable low probe rates and measure probe overhead. |
| False congestion diagnoses | Use multiple signals, minimum sample counts, hysteresis, and an `unknown` state. |
| Optimization sacrifices throughput | Report both latency and throughput; cap policy aggressiveness and support manual override. |
| Security/privacy concerns | Restrict clients, validate inputs, collect only necessary aggregates, document retention. |
| Scope creep | Keep GUI, arbitrary-game integration, and router configuration out of MVP. |

## 13. Demo script (3 minutes)

1. **0:00–0:30:** Explain the user problem: latency rises during background uploads despite a connected network.
2. **0:30–1:00:** Show three independent processes, XPC connections, and daemon status.
3. **1:00–1:30:** Introduce controlled upload congestion; show rising p95 RTT and daemon diagnosis.
4. **1:30–2:00:** Enable protection; show the uploader acknowledging the new rate and the measured effect.
5. **2:00–2:30:** Display before/after RTT and throughput distributions, not a cherry-picked single sample.
6. **2:30–3:00:** Kill/restart a client or daemon; show recovery and briefly explain architecture tradeoffs.

## 14. First engineering tickets

1. **PP-001:** Initialize SPM workspace with `MinMaxCore`, `MinMaxGameClient`, and `MinMaxEchoServer`.
2. **PP-002:** Implement UDP echo protocol (sequence number, send time, reply, timeout) and loopback test.
3. **PP-003:** Implement sliding-window percentiles, jitter, and loss metrics with unit tests.
4. **PP-004:** Implement congestion state machine and deterministic clock-driven tests.
5. **PP-005:** Create a minimal standalone daemon + XPC client spike and document signing/registration requirements.
6. **PP-006:** Add bounded actor-isolated telemetry store and session expiration.
7. **PP-007:** Add rate-limited uploader and controlled bottleneck scenario.
8. **PP-008:** Add CLI snapshots and benchmark export.

**Start here:** Complete PP-001 and PP-002 first. Validate the basic network measurement loop before building the daemon, then prove real XPC connectivity early enough to expose macOS packaging issues.

## 15. Future extensions

- **Game-aware modes:** User-selected workload profiles rather than unreliable automatic detection of arbitrary games.
- **Incident flight recorder:** Bounded replay of latency spikes, path changes, and policy actions.
- **Router-aware SQM:** Optional integration with a supported OpenWrt router; test safe rollback and explicit consent.
- **Cross-device telemetry:** Multiple Macs coordinate network health measurements with authentication.
- **Energy efficiency study:** Compare independent polling clients against shared daemon monitoring.

---

### Positioning for Apple interviews

**Technical pitch:** “I built a macOS Swift network intelligence agent that collects telemetry from independent processes over XPC, aggregates it with actor-isolated state, detects sustained latency inflation, and coordinates opt-in traffic shaping for cooperating applications. I validated the design with controlled network faults, repeatable latency/throughput benchmarks, and process-restart tests.”

**Integrity note:** This is an independent educational/developer project inspired by common OS networking architecture. It does not claim access to Apple's private telemetry, Wi-Fi Assist algorithms, or unrestricted system traffic control.
