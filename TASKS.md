# MinMax — Implementation Task Board

**Version:** 0.1  
**Source of truth:** [PRD.md](PRD.md) and [ARCHITECTURE.md](ARCHITECTURE.md)  
**Workflow:** One ticket per branch/worktree; Codex implements by default, Claude reviews/designs by default. Human owns integration.

## 0. Task state conventions

- `[ ]` Backlog / not started
- `[~]` In progress (replace manually; Markdown checklist tooling may not treat this as checked)
- `[x]` Completed with test evidence and human acceptance
- `BLOCKED` requires a reason and next action in the task notes.

Each ticket must have an owner, branch, acceptance evidence, and a PR/commit reference before being marked complete. Do not check boxes merely because an agent generated code.

**Critical path:** PP-001 → PP-002 → PP-003 → PP-005 → PP-006 → PP-007 → PP-009 → PP-010 → PP-012 → PP-013 → PP-015. Some tasks below can proceed in parallel when interfaces are stable.

## Milestone 0 — Repository and feasibility (Week 1)

### [ ] PP-001 — Bootstrap Swift package and repository
- **Suggested owner:** Codex
- **Depends on:** none
- **Scope:** `Package.swift`, minimal `Sources/MinMaxCore`, `Sources/MinMaxGameClient`, `Sources/MinMaxEchoServer`, matching test target, `.gitignore`, README setup.
- **Acceptance:** `swift build` and `swift test` pass on macOS; two minimal executables launch; generated Results/build artifacts ignored.
- **Evidence:** build/test logs; repository tree; recorded Swift/Xcode versions.
- **Parallel:** Claude may independently review project structure, without editing shared files.

### [ ] PP-002 — UDP echo protocol and loopback probe
- **Suggested owner:** Codex
- **Depends on:** PP-001
- **Scope:** versioned probe message, sequence ID, matching reply, configurable cadence, timeout, clean socket shutdown.
- **Acceptance:** controlled localhost test measures RTT; late/duplicate replies handled; server exits cleanly; tests cover packet encoding/decoding and timeout behavior.
- **Evidence:** test output and example CLI invocation.

### [ ] PP-003 — Core metrics and deterministic time abstractions
- **Suggested owner:** Codex
- **Depends on:** PP-001; coordinate probe data contract with PP-002
- **Scope:** monotonic duration abstraction, RTT distribution, documented jitter, loss accounting, bounded rolling windows.
- **Acceptance:** tests cover empty windows, outliers, p50/p95/p99, lost/late packets, expiration and max capacity.
- **Evidence:** `swift test` output; metric definitions in `Docs/metrics.md`.
- **Parallel:** Can run alongside PP-004 once interfaces are agreed; avoid same-file edits.

### [ ] PP-004 — XPC feasibility and deployment ADR
- **Suggested owner:** Claude (research/design) + Codex (isolated spike), with human-assigned ownership
- **Depends on:** PP-001
- **Scope:** minimal **two-process** macOS XPC spike; verify `NSXPCListener`/`NSXPCConnection`, signing, service registration, per-user agent deployment feasibility.
- **Acceptance:** real client invokes real server; exact run/build/signing steps documented; ADR records selected arrangement and rejected alternatives.
- **Evidence:** reproducible commands, console logs, `Docs/adr/ADR-0001-xpc-packaging.md`.
- **Important:** This is an early technical risk gate. Do not scale IPC before the spike works.
- **Parallel:** Separate worktree; avoid changing production IPC contracts during PP-002/003.

## Milestone 1 — Core inference and real IPC (Weeks 2–3)

### [ ] PP-005 — Congestion detector and policy state machine
- **Suggested owner:** Codex
- **Depends on:** PP-003
- **Scope:** pure core evaluator; stable baseline, minimum samples, sustained windows, hysteresis, unknown/healthy/degraded/recovering states.
- **Acceptance:** deterministic tests for short spikes, sustained congestion, insufficient data, recovery, cooldown and false positives.
- **Evidence:** scenario test cases and pass logs.
- **Parallel:** Claude can author test scenario specifications read-only or in a separate nonconflicting path.

### [ ] PP-006 — Versioned XPC contract and independent clients
- **Suggested owner:** Codex
- **Depends on:** PP-004; PP-003 data model stable
- **Scope:** registration, telemetry batches, immutable snapshots, version negotiation, reject responses, session identity.
- **Acceptance:** three **separate processes** connect and submit telemetry; invalid version and oversized payload rejected; documented authorization mechanism.
- **Evidence:** macOS integration test logs; process IDs; `Docs/security.md`.
- **Gate:** Contract changes require human approval before parallel client implementation.

### [ ] PP-007 — Actor-isolated bounded telemetry store
- **Suggested owner:** Codex
- **Depends on:** PP-003, PP-006 interface
- **Scope:** client/session registry, per-session limits, bounded ingestion, stale expiration, immutable snapshots, dropped-event counters.
- **Acceptance:** concurrent stress tests; no known races; overload behavior visible; bounded growth under repeated input.
- **Evidence:** stress harness and measured RSS/event counts.

### [ ] PP-008 — CLI status and explanation commands
- **Suggested owner:** Claude or Codex (dedicated worktree)
- **Depends on:** PP-006 stable snapshot contract
- **Scope:** `MinMax status`, `clients`, `explain`, useful failure messages.
- **Acceptance:** queries real agent; clear output when agent unavailable; no direct access to daemon memory.
- **Evidence:** CLI transcript and smoke test.
- **Parallel:** Safe with PP-007 only if snapshot contract is frozen and file ownership is separate.

## Milestone 2 — Daemon lifecycle and mitigation (Weeks 4–6)

### [ ] PP-009 — launchd lifecycle and reconnect behavior
- **Suggested owner:** Codex
- **Depends on:** PP-006, PP-007
- **Scope:** per-user LaunchAgent, install/uninstall scripts, graceful termination, client exponential backoff and re-registration.
- **Acceptance:** real macOS agent starts/stops; kill/restart daemon and client; no stale duplicate sessions; uninstall leaves no MinMax-owned agent artifacts.
- **Evidence:** lifecycle script and OSLog/CLI transcript.

### [ ] PP-010 — Controlled uploader and upload server
- **Suggested owner:** Codex
- **Depends on:** PP-001; contract coordination with PP-006
- **Scope:** TCP/HTTP upload workload, configurable offered load, application-level rate limiter, throughput metrics.
- **Acceptance:** reproducible upload scenario; limits demonstrably affect offered traffic; clean shutdown; test endpoint is controlled.
- **Evidence:** throughput test results and example command.
- **Parallel:** Can begin before PP-009 in a separate worktree if interfaces are agreed.

### [ ] PP-011 — Path observation and additional evidence
- **Suggested owner:** Claude or Codex (dedicated worktree)
- **Depends on:** PP-006
- **Scope:** `NWPathMonitor` adapter, interface/path state reports, explicit distinction between path satisfaction and end-to-end connectivity.
- **Acceptance:** path changes reach daemon; unavailable-path and reconnect scenarios handled; unit tests with injected path events.
- **Evidence:** integration transcript and documentation.
- **Parallel:** Safe with uploader implementation in separate paths.

### [ ] PP-012 — Opt-in policy control and uploader acknowledgement
- **Suggested owner:** Codex
- **Depends on:** PP-005, PP-007, PP-010
- **Scope:** `observe|protect`, expiring decisions, bounded rate adjustments, cooldown, acknowledgements, manual emergency disable.
- **Acceptance:** observe mode never throttles; protect mode changes only cooperating uploader; stale decisions ignored; disconnect and recovery restore safe behavior.
- **Evidence:** deterministic policy tests and real multi-process demo.

## Milestone 3 — Evidence, reliability, and presentation (Weeks 7–8)

### [ ] PP-013 — Controlled congestion scenario and benchmark harness
- **Suggested owner:** Codex
- **Depends on:** PP-002, PP-010, PP-012
- **Scope:** controlled bottleneck, baseline/mitigation paired trials, randomized ordering, machine-readable JSON/CSV, scenario metadata.
- **Acceptance:** at least 10 paired trials per PRD; p50/p95/p99 RTT, jitter, loss, throughput and dispersion reported; no fabricated improvements.
- **Evidence:** raw Results artifacts (not necessarily committed), scripts, `Docs/benchmarking.md`.
- **Important:** Loopback alone is insufficient to prove router-bufferbloat mitigation.

### [ ] PP-014 — Failure injection and resilience audit
- **Suggested owner:** Claude (independent review) + Codex (fixes)
- **Depends on:** PP-009, PP-012
- **Scope:** malformed IPC, flood/overload, process crashes, daemon restart, dropped policy ack, timeout and cancellation.
- **Acceptance:** repeatable fault scenarios; findings triaged; no unbounded queues or known high-severity race/authorization defects.
- **Evidence:** review report, stress/fault scripts, exact commands.

### [ ] PP-015 — Final demo, docs, and interview package
- **Suggested owner:** Human + Claude documentation review + Codex reproducibility fixes
- **Depends on:** PP-013, PP-014
- **Scope:** README, setup, architecture/ADRs, security and metrics notes, 3-minute demo script/video, benchmark summary, limitations.
- **Acceptance:** fresh macOS setup follows docs; live demo shows independent processes, congestion, opt-in mitigation, measured tradeoff, restart recovery; project claims match evidence.
- **Evidence:** final tagged release, video, reproduction checklist.

## Stretch backlog — Not part of MVP

### [ ] PP-016 — Incident flight recorder and replay
Bounded incident history and `MinMax replay <id>` timeline; redact sensitive data and document retention.

### [ ] PP-017 — Objective-C interoperability client
Separate Objective-C XPC client communicating with the Swift agent; prove protocol compatibility and document bridging.

### [ ] PP-018 — Router SQM experiment
Explicitly approved OpenWrt integration with backup, rollback, supported-device testing, and before/after queueing benchmarks. Never automatically modify a router in the MVP.

### [ ] PP-019 — Cross-device telemetry
Authenticated multi-Mac coordinator, clock-skew handling, and device-scoped privacy controls.

## Safe parallel-work pairings

| Codex worktree | Claude worktree | Why safe |
|---|---|---|
| PP-002 UDP probe | PP-004 XPC design/spike | Different files and bounded interfaces |
| PP-005 detector | PP-004 ADR/review | Core algorithm vs deployment design |
| PP-007 telemetry store | PP-008 CLI | Only after snapshot interface frozen |
| PP-010 uploader | PP-011 path probe | Separate clients and files |
| PP-013 benchmark harness | PP-014 read-only review | Benchmark implementation vs independent audit |

**Unsafe pairings:** two agents editing `Package.swift`; both changing XPC DTOs; both changing the same actor; one agent rebasing while the other edits shared worktree; simultaneous conflicting `TASKS.md` updates.

## First two-week execution plan

**Days 1–2:** PP-001. Human initializes Git, creates two worktrees, confirms Swift/Xcode toolchain and build commands.  
**Days 3–5:** Codex PP-002; Claude PP-004 architecture research/spike in its own worktree.  
**Days 6–8:** Codex PP-003; human reviews/merges PP-002 and decides XPC packaging from PP-004 evidence.  
**Days 9–12:** Codex PP-005; Claude writes independent detector edge-case review/test ideas.  
**Days 13–14:** Merge, run all available tests, update ADRs and task statuses; only then start production XPC PP-006.

## PR / handoff template

```text
Ticket: PP-###
Owner:
Branch:
Files owned:
PRD requirements addressed:
Summary of changes:
Tests run (commands/results):
Unverified assumptions:
Performance or security implications:
Screenshots/logs/benchmark artifacts:
Review findings resolved:
Human acceptance:
```

## Completion rule

No ticket is `[x]` until acceptance criteria have evidence and the human approves it. Do not mark the entire project done until the PRD §11 checklist is met on real macOS hardware.
