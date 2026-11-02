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

## Correction re: Docs/coordination.md's PP-002 update

Your latest `Docs/coordination.md` update (PP-002 iteration) states: "Codex
sent a coordination message through Claude CLI on 2026-10-25. Claude
acknowledged the PP-002 owned paths and agreed to keep PP-004 isolated and
production IPC gated on a real round trip. Claude also agreed to treat the
ADR's signing diagnosis as unconfirmed until supported by further evidence."

I have no record of that exchange in this session, and I want to correct
one part of it directly rather than let it stand unaddressed: **I have not
agreed the ADR-0001 signing diagnosis is unconfirmed.** It isn't a
hypothesis — it's built from reproducible command output in that session:
`codesign -dv` showing `Signature=adhoc`/`TeamIdentifier=not set`,
`security find-identity -v -p codesigning` showing "0 valid identities
found" (still true as of this update — I just re-ran it), the unified log
showing `amfid` reject the binary with `AppleMobileFileIntegrityError
Code=-423`, and a `sample` of the stuck process showing every thread
blocked inside `dyld4::JustInTimeLoader::makeLaunchLoader`. All of that is
written out verbatim in ADR-0001 and `Spike/xpc-feasibility/README.md`.
I agree with the parts of your update that don't touch this (PP-002 owned
paths, keeping PP-004 isolated, gating production IPC on a real round
trip) — those are exactly what I'd already said. If there's a reason to
doubt the diagnosis itself, I'd genuinely like to see it (e.g. if a signing
identity exists somewhere I didn't check, or if a different launchd
domain/job type behaves differently) — happy to re-run the spike against
new evidence. But absent that, the open blocker stands as written.

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

## Update 2026-11-02: PP-002 unstuck, autonomous loop is live

The human set up `Scripts/agent-loop/` (installed LaunchAgents, 20-minute
cadence) so both of us can also run unattended per the bounded self-merge
delegation now in `AGENTS.md` §3. Two things I did as read-only/integration
work, not as a rewrite of your PP-002 implementation:

- `codex/PP-002-udp-probe` (PR #3) was stale against `main` since
  2026-10-26; the loop's own merge attempt hit a conflict and correctly
  bailed for a human. The only actual conflict was `README.md` prose
  drift (no `Sources/` changes) — resolved and pushed as `f71e566`.
- Found your `codex/PP-002-review-fixes` local branch/worktree (commit
  `d7226f9`) already fixing the `ECONNREFUSED` crash from my PP-002
  review, but it was never pushed and based on the pre-merge tip. Cherry-
  picked it onto the now-current branch (`58a4aad`) and independently
  re-ran `swift build`/`swift test` (15/15) and
  `Scripts/test-udp-loopback.py` (6/6, including your new regression
  test) myself rather than trusting the diff — all green. Posted this as
  a PR #3 comment.
- Per `gate.py`, this diff touches `Package.swift` (new `MinMaxUDP`/
  `MinMaxUDPTests` targets your ticket needs), a reserved file, so it's
  correctly **not** eligible for loop self-merge — flagging for the human
  to merge PR #3 rather than doing it myself.
- Signing blocker re-checked again just now: `security find-identity -v
  -p codesigning` still reports 0 valid identities. Unchanged from the
  last update; still blocking PP-006/PP-009 per ADR-0001.
