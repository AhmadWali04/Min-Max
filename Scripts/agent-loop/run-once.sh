#!/usr/bin/env bash
# One ticket-cycle for the autonomous Codex/Claude collaboration loop.
# Invoked repeatedly by launchd (see Scripts/agent-loop/launchd/*.plist) --
# does nothing and exits 0 if no ticket is currently eligible.
#
# Usage: run-once.sh <codex|claude> <worktree-dir>
set -euo pipefail

AGENT="${1:?usage: run-once.sh <codex|claude> <worktree-dir>}"
WORKTREE_DIR="${2:?usage: run-once.sh <codex|claude> <worktree-dir>}"
LOOP_HOME="${MINMAX_LOOP_HOME:-$HOME/.minmax-agent-loop}"
LOCKS_DIR="$LOOP_HOME/locks"
LOG_DIR="$LOOP_HOME/logs"
mkdir -p "$LOCKS_DIR" "$LOG_DIR"

LOG="$LOG_DIR/$AGENT.log"
log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [$AGENT] $*" | tee -a "$LOG" >&2; }

if [[ "$AGENT" != "codex" && "$AGENT" != "claude" ]]; then
  echo "AGENT must be 'codex' or 'claude', got '$AGENT'" >&2
  exit 2
fi
if [[ ! -e "$WORKTREE_DIR/.git" ]]; then
  echo "$WORKTREE_DIR is not a git worktree. Run install.sh first." >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Single combined cleanup: bash traps do not stack, so every resource
#     this script might need to release on exit is tracked in one place. ---
CLAIM_LOCK=""
TICKET_LOCK=""
TMP_FILES=()
cleanup() {
  local f
  for f in "${TMP_FILES[@]:-}"; do [[ -n "$f" ]] && rm -f "$f"; done
  [[ -n "$TICKET_LOCK" ]] && rmdir "$TICKET_LOCK" 2>/dev/null || true
  [[ -n "$CLAIM_LOCK" ]] && rmdir "$CLAIM_LOCK" 2>/dev/null || true
}
trap cleanup EXIT

mktmp() { local f; f="$(mktemp "${TMPDIR:-/tmp}/minmax-loop.XXXXXX")"; TMP_FILES+=("$f"); echo "$f"; }

cd "$WORKTREE_DIR"
git fetch origin --quiet
git checkout -q main
git reset -q --hard origin/main

TICKETS_JSON="$WORKTREE_DIR/Scripts/agent-loop/tickets.json"

# --- 1. Claim a ticket under a short global lock -----------------------
CLAIM_LOCK="$LOCKS_DIR/claim.lock"
claimed=0
for _ in $(seq 1 60); do
  if mkdir "$CLAIM_LOCK" 2>/dev/null; then claimed=1; break; fi
  sleep 1
done
if [[ "$claimed" -ne 1 ]]; then
  CLAIM_LOCK=""  # never actually held it; don't try to rmdir someone else's lock
  log "could not acquire claim lock within 60s; another cycle is mid-claim. Skipping this run."
  exit 0
fi

PICK_OUT="$(python3 "$SCRIPT_DIR/pick_ticket.py" "$AGENT" "$TICKETS_JSON" "$LOCKS_DIR" || true)"
if [[ -z "$PICK_OUT" ]]; then
  log "no eligible ticket for $AGENT right now. Exiting."
  exit 0
fi
TICKET_ID="$(echo "$PICK_OUT" | sed -n 1p)"
TICKET_JSON="$(echo "$PICK_OUT" | sed -n 2p)"
BRANCH="$(echo "$TICKET_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["branch"])')"
STATUS="$(echo "$TICKET_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])')"
TITLE="$(echo "$TICKET_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["title"])')"

mkdir "$LOCKS_DIR/$TICKET_ID"
TICKET_LOCK="$LOCKS_DIR/$TICKET_ID"
rmdir "$CLAIM_LOCK"   # release the claim lock now that the per-ticket lock exists
CLAIM_LOCK=""

log "claimed $TICKET_ID (branch=$BRANCH, status=$STATUS)"

# --- 2. Check out the ticket branch -------------------------------------
if [[ "$STATUS" == "branch_exists" ]] && git ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1; then
  git checkout -q -B "$BRANCH" "origin/$BRANCH"
  if ! git merge -q origin/main -m "Merge main into $BRANCH before resuming"; then
    log "$TICKET_ID: merge conflict bringing $BRANCH up to date with main; needs a human."
    git merge --abort || true
    exit 0
  fi
else
  git checkout -q -B "$BRANCH" origin/main
fi

# --- 3. Build the prompt and run the agent on this ticket ---------------
PROMPT_FILE="$(mktmp)"
"$SCRIPT_DIR/build-prompt.sh" "$TICKET_ID" > "$PROMPT_FILE"

AGENT_LOG="$LOG_DIR/$AGENT-$TICKET_ID-$(date -u +%Y%m%dT%H%M%SZ).log"
log "$TICKET_ID: invoking $AGENT, transcript -> $AGENT_LOG"

set +e
if [[ "$AGENT" == "codex" ]]; then
  codex exec \
    --sandbox workspace-write \
    --approve-for-me \
    -c sandbox_workspace_write.network_access=true \
    -C "$WORKTREE_DIR" \
    - < "$PROMPT_FILE" > "$AGENT_LOG" 2>&1
else
  claude -p \
    --permission-mode acceptEdits \
    --allowedTools "Bash(git *) Bash(swift *) Bash(python3 *) Edit Write Read Glob Grep" \
    --add-dir "$WORKTREE_DIR" \
    "$(cat "$PROMPT_FILE")" > "$AGENT_LOG" 2>&1
fi
AGENT_EXIT=$?
set -e
log "$TICKET_ID: agent run exited $AGENT_EXIT"

# --- 4. Baseline merge gate: build + test + any ticket smoke scripts ---
GATE_LOG="$LOG_DIR/$AGENT-$TICKET_ID-gate-$(date -u +%Y%m%dT%H%M%SZ).log"
GATE_OK=1
{
  echo "== swift build =="
  swift build || GATE_OK=0
  echo "== swift test =="
  swift test || GATE_OK=0
} > "$GATE_LOG" 2>&1

if [[ "$GATE_OK" -eq 1 ]]; then
  while IFS= read -r smoke; do
    [[ -z "$smoke" ]] && continue
    {
      echo "== $smoke =="
      if [[ "$smoke" == *.py ]]; then
        python3 "$smoke" || GATE_OK=0
      else
        bash "$smoke" || GATE_OK=0
      fi
    } >> "$GATE_LOG" 2>&1
  done < <(git diff --name-only --diff-filter=AM main...HEAD -- 'Scripts/*' | grep -E '/(test|smoke)-' || true)
fi

log "$TICKET_ID: gate $( [[ $GATE_OK -eq 1 ]] && echo PASSED || echo FAILED ), log -> $GATE_LOG"

CHANGED_FILES_FILE="$(mktmp)"
git diff --name-only main...HEAD > "$CHANGED_FILES_FILE"
SCOPED_DIFF_FILE="$(mktmp)"
git diff main...HEAD -- TASKS.md Scripts/agent-loop/tickets.json > "$SCOPED_DIFF_FILE"

if [[ ! -s "$CHANGED_FILES_FILE" ]]; then
  log "$TICKET_ID: no changes were made (agent exit $AGENT_EXIT). Nothing to push."
  exit 0
fi

# --- 5. Decide auto-merge vs human-gate ---------------------------------
if [[ "$GATE_OK" -ne 1 ]]; then
  AUTO_MERGE=0
  AUTO_MERGE_REASON="build/test gate failed"
elif AUTO_MERGE_REASON="$(python3 "$SCRIPT_DIR/gate.py" "$TICKET_ID" "$TICKETS_JSON" "$CHANGED_FILES_FILE" "$SCOPED_DIFF_FILE")"; then
  AUTO_MERGE=1
else
  AUTO_MERGE=0
fi
log "$TICKET_ID: auto-merge=$AUTO_MERGE ($AUTO_MERGE_REASON)"

# --- 6. Commit (if the agent left uncommitted changes), push, PR -------
if ! git diff --quiet || ! git diff --cached --quiet; then
  git add -A
  git commit -q -m "$TICKET_ID: WIP commit by $AGENT loop (agent did not commit cleanly)"
fi

if git rev-parse "origin/$BRANCH" >/dev/null 2>&1; then
  git push -q origin "$BRANCH"
else
  git push -q -u origin "$BRANCH"
fi

PR_URL="$(gh pr view "$BRANCH" --json url -q .url 2>/dev/null || true)"
if [[ -z "$PR_URL" ]]; then
  PR_BODY="Ticket: $TICKET_ID
Owner: $AGENT (autonomous loop)
Branch: $BRANCH
Gate: $( [[ $GATE_OK -eq 1 ]] && echo PASSED || echo FAILED ) -- see $GATE_LOG on the host that ran it
Auto-merge: $AUTO_MERGE ($AUTO_MERGE_REASON)

Opened automatically by Scripts/agent-loop/run-once.sh under the policy in
AGENTS.md section 'Autonomous dual-agent loop'."
  PR_URL="$(gh pr create --title "$TICKET_ID: $TITLE" --body "$PR_BODY" --base main --head "$BRANCH" 2>&1 | tail -1 || true)"
fi
log "$TICKET_ID: PR -> $PR_URL"

if [[ "$AUTO_MERGE" -eq 1 ]]; then
  git fetch origin --quiet
  if git merge-base --is-ancestor origin/main HEAD; then
    if gh pr merge "$BRANCH" --squash --delete-branch 2>>"$LOG"; then
      log "$TICKET_ID: auto-merged and branch deleted."
    else
      log "$TICKET_ID: gh pr merge failed; leaving PR open for a human. See $LOG."
      gh pr edit "$BRANCH" --add-label "needs-human-merge" 2>>"$LOG" || true
    fi
  else
    log "$TICKET_ID: main moved since fetch; not merging this cycle, next cycle rebases and retries."
    gh pr edit "$BRANCH" --add-label "needs-human-merge" 2>>"$LOG" || true
  fi
else
  gh pr edit "$BRANCH" --add-label "needs-human-merge" 2>>"$LOG" || true
  log "$TICKET_ID: left for human merge ($AUTO_MERGE_REASON): $PR_URL"
fi
