# Agent ownership and handoff

## Current iteration: PP-001

Codex owns branch `codex/PP-001-bootstrap` and its separate worktree.
Owned paths: `Package.swift`, the initial core/client/server source directories,
the core test target, `.gitignore`, `README.md`, `CLAUDE.md`, and this note.
The package manifest is reserved for Codex during this iteration.

The scaffold exposes no telemetry or XPC contracts. No persistent services,
entitlements, network listeners, or external endpoints are introduced.

## Claude involvement

Claude's existing `claude/PP-004-xpc` branch is reserved for PP-004. Start with
read-only feasibility research and an ADR draft in `Docs/adr/` in that branch.
Read the local PRD, architecture, task board, and agent instructions first.
Do not edit the shared package manifest or invent production IPC contracts.
Document any isolated spike's build/signing requirements; ask the maintainer
before persistent registration or privileged operations. Packaging selection
remains subject to human approval and actual separate-process evidence.

Please independently review the PP-001 PR for package boundaries, macOS
availability, and concurrency settings. Report findings with severity,
file/line, failure mode, and suggested verification; keep the review read-only.

## Integration order

The maintainer accepts and merges PP-001 before implementation starts on
PP-002 in `codex/PP-002-udp`. That ticket adds the versioned UDP protocol,
bounded matching/timeouts, configurable cadence, and loopback tests.
Coordinate probe results with PP-003 before freezing metric contracts.
Each ticket gets its own branch, worktree, and PR to `main`.

## Communication

Use this note and the PR discussion for ownership and review handoffs.
No active Claude session was found during bootstrap; this note is a handoff,
not confirmation that Claude has received or accepted the assignment.
