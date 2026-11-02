# Agent ownership and handoff

## Current iteration: PP-002

The human confirmed **MinMax** naming. PP-001 was integrated into `main`
at `9d98982` before this iteration started.

Codex owns branch `codex/PP-002-udp-probe` in `.worktrees/PP-002`.
Owned paths: `Package.swift`, `Sources/MinMaxCore/Probe*`, `Sources/MinMaxUDP/`,
the game/echo executable entrypoints, `Tests/MinMaxCoreTests/Probe*`,
`Tests/MinMaxUDPTests/`, `Scripts/test-udp-loopback.py`, `README.md`,
`Docs/udp-protocol.md`, the naming-only correction in `TASKS.md`, and this note. The package manifest is reserved for
Codex during this iteration.

No telemetry or XPC contract is exposed. The new UDP listener defaults to
loopback and a finite runtime; tests use ephemeral loopback ports. No persistent
services, entitlements, or external test endpoints are introduced.

## Claude involvement

Claude's existing `claude/PP-004-xpc` branch is reserved for PP-004. Start with
read-only feasibility research and an ADR draft in `Docs/adr/` in that branch.
Read the local PRD, architecture, task board, and agent instructions first.
Do not edit the shared package manifest or invent production IPC contracts.
Document any isolated spike's build/signing requirements; ask the maintainer
before persistent registration or privileged operations. Packaging selection
remains subject to human approval and actual separate-process evidence.

Please independently review the PP-002 PR for packet validation, timeouts, socket
lifecycle, bounded state, macOS availability, and concurrency settings. Report findings with severity,
file/line, failure mode, and suggested verification; keep the review read-only.

## Integration order

The maintainer accepts and merges PP-002 before PP-003 implementation.
PP-003 can consume the packet tracker's validated RTT results and final
received/timeout/cancelled counters; window/metric contracts are not yet frozen.
Each ticket gets its own branch, worktree, and PR to `main`.

## Communication

Use this note and the PR discussion for ownership and review handoffs.
Codex sent a coordination message through Claude CLI on 2026-10-25. Claude
acknowledged the PP-002 owned paths and agreed to keep PP-004 isolated and
production IPC gated on a real round trip. Claude also agreed to treat the
ADR's signing diagnosis as unconfirmed until supported by further evidence.

Claude completed a read-only review of the PP-002 implementation and tests via
CLI. Result: no material defects found. Claude noted the bounded array's O(n)
history eviction and timing dependence in the cancellation smoke test. The
history holds at most 256 entries by default; no performance claims are made.
The cancellation test now uses a 60-second timeout and a 1-second cadence to
give the signal test more scheduling margin without delaying successful runs.
Claude did not execute tests during this review; the results below are Codex's.

## PP-002 handoff

Ticket: PP-002 (ready for human review; not marked accepted).
Branch/worktree: `codex/PP-002-udp-probe`, `.worktrees/PP-002`.
Files changed: the owned paths above, including the new packet/tracker files,
socket adapter, command runners, core/socket tests and process smoke script.
Behavior implemented: versioned request/reply, bounded matching and recent
history, monotonic RTT, configurable cadence/timeouts, loss/cancellation
accounting, strict input validation, signal/duration shutdown and socket close.

Tests run (macOS arm64, Swift 6.4, Xcode 27.0):

- `swift build -Xswiftc -strict-concurrency=complete` — pass.
- `swift test -Xswiftc -strict-concurrency=complete` — pass, 15 tests.
- `python3 Scripts/test-udp-loopback.py` — pass, 5 separate-process tests.
- `git diff --check` — pass.

Tests not run: Xcode target tests (no Xcode project), macOS 14 runtime tests
(host runs a newer OS), external-network or congestion benchmarks (outside
PP-002 scope), XPC integration (PP-004 gate remains unresolved).
Known risks/platform assumptions: macOS Darwin sockets, numeric IPv4 only,
scheduling/stdout overhead included in measurements; controlled plaintext UDP
is not authenticated. Loopback proves exchange and lifecycle, not mitigation.
Docs or ADR updates needed: protocol and README updated here; PP-004 ADR still
requires actual independent-process round-trip evidence and human approval.
Recommended next task: PP-003 after human integration, with Claude continuing
PP-004 feasibility validation and independent reviews in its own worktree.
