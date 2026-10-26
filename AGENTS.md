# MinMax — Shared AI Agent Instructions

**Applies to:** Codex, Claude Code, and other repository-aware coding agents.  
**Human owner:** Project maintainer.  
**Read before acting:** `PRD.md` → `ARCHITECTURE.md` → `TASKS.md` → this file.

## 1. Mission

Build MinMax: a macOS Swift network intelligence daemon that aggregates telemetry from independent processes over XPC, detects latency inflation during controlled congestion, and coordinates opt-in rate limiting for a cooperating uploader. The project is an engineering portfolio piece emphasizing correctness, concurrency, IPC, failure handling, security, and reproducible measurements.

Do not substitute a UI-heavy gaming app, web backend, VPN, privileged traffic inspector, or arbitrary-game traffic optimizer for the specified MVP.

## 2. Sources of truth and precedence

1. Explicit human instruction in the current task.
2. `PRD.md` for product requirements and MVP scope.
3. `ARCHITECTURE.md` for technical boundaries and contracts.
4. `TASKS.md` for work order, dependencies, and acceptance criteria.
5. This file for engineering workflow and safety rules.
6. Relevant ADRs for approved decisions.

If documents conflict, **do not silently choose**: describe the conflict and request a decision. Do not alter the PRD or architecture to justify an implementation shortcut without human approval.

## 3. Agent roles and collaboration

**Default roles:**
- **Codex:** primary implementer of approved, scoped tickets; adds tests and runs available checks.
- **Claude Code:** architecture planning, independent code/concurrency/security review, and documentation; may implement a separately assigned ticket.
- **Human:** task allocation, architectural approval, merge ownership, platform verification, final acceptance.

Roles are conventions, not exclusive capabilities. Either agent may implement or review when explicitly assigned. **Never have two agents edit the same files concurrently.**

### Mandatory parallel-work isolation

- One task = one branch = one Git worktree = one primary agent owner.
- Worktrees must use separate working directories, e.g. `../MinMax-codex` and `../MinMax-claude`.
- Prefix branches `codex/PP-###-slug` and `claude/PP-###-slug`.
- Reserve shared files (`Package.swift`, `AGENTS.md`, `ARCHITECTURE.md`, `PRD.md`, `TASKS.md`, XPC protocol contracts) for one designated owner per integration window.
- Before coding, state owned paths, expected interfaces, dependencies, and the exact verification commands.
- If another agent's changes are needed, request an interface agreement or wait for its branch to merge; do not guess the API.
- Do not merge, rebase, cherry-pick, force-push, reset, or discard another agent's work without explicit human instruction.
- Cross-review is read-only by default. Submit findings instead of rewriting the other agent's branch.
- The human integrates branches serially and resolves conflicts.

### Handoff format

At the end of every task, provide:

```text
Ticket: PP-###
Branch/worktree:
Files changed:
Behavior implemented:
Tests run (exact commands + pass/fail):
Tests not run (reason):
Known risks / platform assumptions:
Docs or ADR updates needed:
Recommended next task:
```

Never claim a build, test, benchmark, or API verification occurred unless it actually ran.

## 4. Implementation rules

- Target macOS 14+; primary language Swift 5.10+ with stricter Swift 6 concurrency checks when feasible.
- Prefer Swift Package Manager for core logic and test executables; use Xcode project/target configuration when required for XPC, signing, or service deployment.
- Prefer Foundation, Network.framework, XPC, OSLog, and native Apple tooling over unnecessary dependencies.
- Separate domain logic from transport, persistence, and OS-specific adapters.
- Use actor isolation or documented synchronization for mutable state. Model cancellation, timeouts, reconnection, and backpressure explicitly.
- Keep event queues, retention, message sizes, session counts, retries, and spawned tasks bounded.
- Avoid force unwraps, unexplained `try!`, silent error swallowing, blocking waits on actor paths, and speculative APIs.
- Define transport DTOs separately from domain types where Objective-C XPC bridging requires it.
- Document API availability, entitlements, signing, and service registration assumptions before implementing them.
- Use monotonic time for RTT and elapsed durations; wall clock is for human-readable timestamps.
- Explain metric formulas, sample counts, and measurement limitations.
- Do not claim optimization for arbitrary third-party games. Only control cooperating workloads for MVP.
- Observe-only is default; active mitigation requires opt-in and a one-command disable.
- Never run uncontrolled load tests against public services or third-party networks.

## 5. Security and privacy

- Treat all IPC payloads as untrusted. Validate sizes, protocol versions, numeric ranges, session identities, and authorization.
- Do not use client-provided IDs as proof of identity.
- Do not collect packet payloads, browsing histories, credentials, or unnecessary network destinations.
- Never commit secrets, signing certificates, API tokens, local user paths, or private diagnostic logs.
- Ask before installing persistent services, changing firewall/router settings, using privileged commands, or contacting external endpoints.
- Explain any new network listener, entitlement, filesystem write, or persistent launchd registration.

## 6. Task execution protocol

### Before coding
1. Read the ticket and its prerequisites in `TASKS.md`.
2. Inspect existing implementation and tests; do not assume files or APIs exist.
3. Give a concise plan with changed paths, interface impact, and failure cases.
4. Flag decisions that need an ADR or human approval.
5. Work only within assigned scope.

### During coding
1. Make small, reviewable commits where authorized.
2. Add or update tests alongside behavior.
3. Keep public contracts stable unless the ticket explicitly changes them.
4. Prefer deterministic fake clocks and injected dependencies for core logic.
5. Document any deviation from the plan.

### After coding
1. Run the relevant verification commands that the environment supports.
2. If on macOS, run appropriate `swift build`, `swift test`, and targeted Xcode build/tests when configured.
3. Run lint/format tools only if installed and configured; do not silently reformat unrelated files.
4. Review diff for scope creep, accidental secrets, and generated artifacts.
5. Report exact results and handoff notes.
6. Do not mark a ticket complete without evidence for each acceptance criterion.

## 7. Standard commands (adjust after workspace exists)

```bash
swift --version
swift build
swift test
# Once an Xcode project/scheme exists:
# xcodebuild -list -project MinMax.xcodeproj
# xcodebuild -project MinMax.xcodeproj -scheme MinMax build
```

Do not fabricate a scheme, path, simulator destination, or signing setup. Discover actual project targets first. XPC/launchd integration must be verified on macOS; portable tests elsewhere do not establish macOS deployment correctness.

## 8. Code review checklist

- **Correctness:** valid inputs, malformed inputs, empty windows, late packets, duplicate sequences.
- **Concurrency:** ownership, actor boundaries, Sendable, cancellation, task lifetime, deadlocks, races.
- **Networking:** socket lifecycle, retries, timeouts, endpoint ownership, meaningful RTT/loss definitions.
- **IPC:** protocol versioning, transport compatibility, caller validation, disconnected peers, idempotency.
- **Reliability:** bounded memory, backpressure, stale sessions, daemon restart, manual disable.
- **Security/privacy:** least privilege, local client authorization, minimal telemetry, safe logging.
- **Performance:** measured overhead, no invented gains, benchmark reproducibility.
- **Documentation:** user-visible behavior, ADRs, acceptance evidence, limitations.

Reviews should report **severity, file/line, concrete failure mode, reproduction or test suggestion, and recommended fix**. Avoid vague style-only feedback.

## 9. Definition of done

A task is complete only when: (1) implementation meets its acceptance criteria; (2) appropriate tests are added and run or explicitly documented as blocked; (3) the code is reviewed; (4) required docs/contracts are updated; (5) the human accepts the branch. A green unit-test suite does not substitute for real separate-process XPC or controlled network benchmarks.

## 10. Claude Code compatibility

Codex should use this root `AGENTS.md`. Claude Code typically uses `CLAUDE.md` for repository instructions. To avoid duplicating policies, create a short `CLAUDE.md` that points to this file, for example:

```markdown
# MinMax — Claude Code
Read and follow [AGENTS.md](AGENTS.md) before modifying this repository.
Also read PRD.md, ARCHITECTURE.md, and the assigned ticket in TASKS.md.
Do not edit files assigned to another agent or worktree.
```

If your installed Claude Code version does not follow Markdown links automatically, configure its supported instruction import mechanism or paste the shared instructions into the session; verify it actually loaded them. Keep one canonical policy file.

## 11. Recommended prompt templates

**Implement:** “Read AGENTS.md and ticket PP-### in TASKS.md. You own branch `<branch>` and paths `<paths>`. Propose a brief plan, then implement only this ticket with tests. Do not edit shared contracts. Report exact verification results.”

**Review:** “Review branch `<branch>` against PRD.md, ARCHITECTURE.md, AGENTS.md and PP-###. Read-only review. Prioritize correctness, races, IPC safety, and failure handling. Return severity-ranked findings with file/line and reproduction steps.”

**Architecture:** “Before implementation, compare two or three viable approaches, verify macOS API assumptions, recommend one, and draft an ADR. Do not change code until approved.”
