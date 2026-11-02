# Autonomous Codex/Claude ticket loop

Lets Codex and Claude Code work the `TASKS.md` backlog continuously and
unattended, each in its own worktree, and merge their own PRs to `main`
when it's safe to do so automatically. The policy this operates under —
including exactly what "safe" means and how to revoke it — is documented
in `AGENTS.md` §3, "Autonomous dual-agent loop." Read that first; this
file is just the how-to-run-it companion.

## Setup (once)

```bash
gh auth login        # interactive; this repo's loop can't do this for you
codex login          # if not already logged in
Scripts/agent-loop/install.sh
```

`install.sh` creates `../MinMax-loop-codex` and `../MinMax-loop-claude` as
dedicated git worktrees (never reuses your interactive worktree — see
AGENTS.md's mandatory parallel-work isolation rule) and installs two
LaunchAgents that each fire `run-once.sh` every 20 minutes.

## How one cycle works (`run-once.sh <codex|claude> <worktree>`)

1. Fetch/reset the worktree to `origin/main`.
2. Claim the next eligible ticket from `tickets.json` (owner matches,
   dependencies all `done`, not `blocked`, no live lock) under a short
   file lock so the two loops never claim the same ticket.
3. Check out (or resume) that ticket's branch.
4. Feed the ticket to `codex exec` or `claude -p`, non-interactively, via
   the prompt `build-prompt.sh` generates from `TASKS.md` + the hard
   rules in `AGENTS.md`.
5. Run `swift build && swift test` plus any `Scripts/test-*`/`smoke-*`
   script the diff touches. This is the baseline merge gate.
6. `gate.py` decides auto-merge vs. human review: reserved files
   (`Package.swift`, `AGENTS.md`, `ARCHITECTURE.md`, `PRD.md`) or a
   `human_gate: true` ticket always forces a human merge; everything
   else that's green auto-merges (squash, branch deleted).
7. Push, open/update the PR, merge or label `needs-human-merge`.

Logs land in `~/.minmax-agent-loop/logs/`; locks in
`~/.minmax-agent-loop/locks/` (delete a stuck lock dir by hand if a cycle
ever dies mid-run without cleaning up).

## Operating it

```bash
# Run one cycle right now instead of waiting for the timer:
launchctl kickstart -k gui/$(id -u)/com.minmax.agentloop.codex
launchctl kickstart -k gui/$(id -u)/com.minmax.agentloop.claude

# Watch it work:
tail -f ~/.minmax-agent-loop/logs/codex.log
tail -f ~/.minmax-agent-loop/logs/claude.log

# Stop both (revokes the merge delegation in practice, since nothing
# fires anymore):
launchctl bootout gui/$(id -u)/com.minmax.agentloop.codex
launchctl bootout gui/$(id -u)/com.minmax.agentloop.claude
```

## `tickets.json`

Machine-readable mirror of `TASKS.md`. Keep both in sync — the loop only
reads `tickets.json`, humans mostly read `TASKS.md`. Each ticket has:

- `owner`: `"codex"` or `"claude"` — must match the loop invoking it.
- `depends_on`: ticket IDs that must be `"done"` first.
- `status`: `"pending"` (not started) → `"branch_exists"` (resume a WIP
  branch) → `"done"`. `"blocked"` is never auto-picked — only a human
  flips it back to `"pending"` once the blocker is actually resolved.
- `human_gate`: `true` forces every PR for that ticket to wait for a
  human merge, regardless of how green the build is.

## Known limits (read before trusting a green run)

- The merge gate is `swift build && swift test` (+ smoke scripts), not
  the full acceptance criteria in `TASKS.md`. For tickets whose
  acceptance needs real multi-process XPC, launchd, or benchmark
  evidence on hardware, passing this gate is necessary, not sufficient —
  that's exactly why those tickets are on the `human_gate` list.
- `gate.py`'s check that a `TASKS.md`/`tickets.json` edit stays inside
  one ticket's own entry is a line-level heuristic (any `PP-###` token
  touched in the diff), not a structural parser. Good enough to catch an
  agent editing someone else's row; not a substitute for actually reading
  the squash-merge commit occasionally.
- One ticket per cycle, one cycle at a time per agent. This is
  deliberately not trying to parallelize within an agent.
