Ticket: PP-002
Branch/worktree: codex/PP-002-review-fixes / .worktrees/PP-002
Files changed: UDPSocket.swift, WorkloadCLI.swift, ProbeTracker.swift, test-udp-loopback.py, udp-protocol.md, this handoff.
Behavior implemented: Addressed Claude's high-severity closed-port failure and transient send failure finding. Recoverable receive errors leave timeout accounting intact; recoverable sends increment sendFailures. Documented duplicate semantics and attempted-send loss limitations. Fatal local socket failures still throw.
Tests run: swift build PASS; swift test PASS (15 tests); python3 Scripts/test-udp-loopback.py PASS (6 tests); git diff --check PASS. Initial sandbox build/cache and socket failures required approved unsandboxed reruns.
Tests not run: deterministic ENOBUFS injection, remote-network tests (not authorized or needed for localhost regression).
Known risks / platform assumptions: macOS Darwin sockets; closed-port selection has a small ephemeral-port reuse race. Original branch predates current main; integration belongs to the maintainer. Review fix has been self-reviewed, not independently reviewed.
Docs or ADR updates needed: No architecture change. Protocol notes updated.
Recommended next task: PP-003 metrics; PP-004 signing and PP-006 approval remain blocking production IPC.
