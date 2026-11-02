#!/usr/bin/env bash
# Builds the non-interactive prompt for one ticket cycle. Run from inside
# the worktree (run-once.sh already `cd`s there) so relative paths resolve.
# Usage: build-prompt.sh <ticket-id>
set -euo pipefail
TICKET_ID="${1:?usage: build-prompt.sh <ticket-id>}"

# Pull just this ticket's section out of TASKS.md: from its "### " heading
# up to (not including) the next "### " or "## " heading.
TICKET_SECTION="$(awk -v id="$TICKET_ID" '
  $0 ~ "^### .*" id { found=1; print; next }
  found && /^(### |## )/ { exit }
  found { print }
' TASKS.md)"

cat <<PROMPT
You are an autonomous worker in the MinMax multi-agent build loop. This
invocation is non-interactive and unattended -- there is no human to ask
mid-task. Work within the rules below and stop cleanly if you hit a real
blocker; do not guess past one.

Read, in this order, before changing anything: AGENTS.md, PRD.md,
ARCHITECTURE.md, and the ticket below from TASKS.md. If anything here
conflicts with those files, those files win except for the ticket-specific
instructions below, which narrow (never widen) your scope for this run.

=== Ticket ===
$TICKET_SECTION
=== End ticket ===

Hard rules for this run:
1. You own exactly this ticket. Touch only the files its Scope implies.
   Do not edit Package.swift, AGENTS.md, ARCHITECTURE.md, or PRD.md.
2. You MAY edit TASKS.md and Scripts/agent-loop/tickets.json, but ONLY the
   entry for $TICKET_ID -- do not change any other ticket's line/JSON
   block. If acceptance criteria are fully met with real evidence, set
   this ticket's TASKS.md checkbox to [x] and its tickets.json "status" to
   "done" (or leave status as "pr_open_needs_human" and the checkbox as
   [~] if tickets.json already marks this ticket human_gate: true for
   this ticket), and add a short evidence note (exact commands you ran and
   their results). Never claim a test, build, or benchmark ran if it did
   not actually run in this session.
3. Add or update tests alongside behavior per AGENTS.md section 8. Run
   \`swift build\` and \`swift test\` yourself before finishing and fix
   failures you caused.
4. Make a small number of reviewable commits on the current branch
   (already checked out for you). Do not create or switch branches, force
   push, rebase other branches, or touch git history outside this branch.
5. If you get genuinely blocked (missing platform capability, ambiguous
   requirement, dependency not actually ready despite what tickets.json
   says), stop, leave the branch in a clean, buildable state, write what
   blocked you into your final commit message and into a short note under
   this ticket's entry in TASKS.md (do not mark it [x]), and end the
   session. Do not fabricate a workaround to force a green build.
6. End by stating, in plain text, the exact verification commands you ran
   and their pass/fail results -- this is parsed by the loop as part of
   the merge decision.
PROMPT
