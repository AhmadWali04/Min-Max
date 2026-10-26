# Claude status update

Companion to `Docs/coordination.md` (Codex's note). Written here instead of
editing that file directly, since Codex owns it and no live Codex session
was reachable to hand this off interactively. Read this and the merged PRs
below for current state; the human maintainer is relaying between sessions
in the meantime.

## What's done and merged into `main`

- **PP-004** (`claude/PP-004-xpc`, merged via PR #1): ADR-0001
  (`Docs/adr/ADR-0001-xpc-packaging.md`) and an isolated spike
  (`Spike/xpc-feasibility/`, its own `Package.swift`, never touched the root
  manifest). Verified finding: a named Mach service via a per-user
  LaunchAgent is the only arrangement that fits independent client
  processes; registration works, but the ad-hoc-signed SPM binary is
  rejected by `amfid` once launchd trampolines it. **Zero code-signing
  identities exist in this machine's keychain** — this blocks a fully
  verified round trip and should block PP-006 production IPC work until
  resolved (see ADR-0001 "Open blocker"). This needs a human to add a free
  Apple ID under Xcode → Settings → Accounts; I can't do that step myself.
- **PP-001 review**: read-only review of the bootstrap you merged — no
  blocking findings, `swift build`/`swift test` pass. Written up at
  `Docs/reviews/PP-001-review.md`.
- Fixed a pre-existing repo bug (human-approved): `AGENTS.md`/
  `ARCHITECTURE.md`/`PRD.md`/`TASKS.md` were gitignored and never
  committed, so a fresh worktree would have been missing them. Committed
  to `main` directly, ahead of any ticket branch.

## Open now (branch pushed, PR not yet opened — `gh` isn't available here)

- **PP-005 scenario specs** (`claude/PP-005-scenarios`): `Scenarios/*.json`
  (idle, short-spike, upload-congestion, client-restart) plus
  `Docs/detector-test-scenarios.md`. These are fixtures for your PP-005
  deterministic clock-driven tests, not an implementation — no detector
  code exists. One fixture (`client-restart.json`) flags an explicit open
  design question (whether a session gap reuses the pre-gap baseline or
  re-forms it from scratch) for you to settle when you implement PP-005,
  not something I decided unilaterally.

## What I need from you / next steps per TASKS.md's critical path

- Nothing blocks PP-002 (your ticket) — it only depended on PP-001, which
  is merged.
- Nothing blocks PP-003 either, but please coordinate the probe data
  contract with PP-002 before freezing it, per TASKS.md.
- Before PP-006 (production XPC contract) starts, resolve the ADR-0001
  signing blocker above — otherwise we'd be scaling IPC before "the spike
  works," which TASKS.md PP-004 explicitly says not to do.
- I'll keep taking review/architecture/documentation work and tickets
  explicitly marked safe for Claude in TASKS.md (PP-008 CLI, PP-011 path
  probe, PP-014 fault-injection review) as their dependencies land — not
  touching `Package.swift` or anything in your active worktrees.
