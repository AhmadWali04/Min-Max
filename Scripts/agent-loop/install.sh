#!/usr/bin/env bash
# One-time setup for the autonomous Codex/Claude ticket loop:
#   - creates a dedicated git worktree per agent (AGENTS.md mandatory
#     parallel-work isolation: one agent = one working directory)
#   - installs two per-user LaunchAgents that each run run-once.sh on an
#     interval, independent of any open terminal or chat session
#
# Usage: Scripts/agent-loop/install.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PARENT_DIR="$(dirname "$REPO_ROOT")"
CODEX_WORKTREE="$PARENT_DIR/MinMax-loop-codex"
CLAUDE_WORKTREE="$PARENT_DIR/MinMax-loop-claude"
PLIST_DIR="$HOME/Library/LaunchAgents"
LOOP_HOME="${MINMAX_LOOP_HOME:-$HOME/.minmax-agent-loop}"
UID_NUM="$(id -u)"

echo "== Checking prerequisites =="
command -v gh >/dev/null || { echo "gh CLI not found. brew install gh first." >&2; exit 1; }
command -v codex >/dev/null || { echo "codex CLI not found." >&2; exit 1; }
command -v claude >/dev/null || { echo "claude CLI not found." >&2; exit 1; }
if ! gh auth status >/dev/null 2>&1; then
  echo "gh is not authenticated. Run 'gh auth login' yourself first (this script" >&2
  echo "cannot do that for you), then re-run install.sh." >&2
  exit 1
fi
if ! codex login status >/dev/null 2>&1; then
  echo "codex CLI is not logged in. Run 'codex login' yourself first." >&2
  exit 1
fi

mkdir -p "$LOOP_HOME/locks" "$LOOP_HOME/logs" "$PLIST_DIR"

echo "== Setting up dedicated worktrees =="
cd "$REPO_ROOT"
git fetch origin --quiet
for pair in "codex:$CODEX_WORKTREE" "claude:$CLAUDE_WORKTREE"; do
  dir="${pair#*:}"
  if [[ -d "$dir/.git" ]]; then
    echo "  $dir already exists, leaving it."
  else
    echo "  creating $dir"
    git worktree add "$dir" main
  fi
done

echo "== Installing LaunchAgents (interval: 1200s / 20min) =="
SCRIPT_DIR="$REPO_ROOT/Scripts/agent-loop"

write_plist() {
  local agent="$1" worktree="$2" label="com.minmax.agentloop.$agent" plist="$PLIST_DIR/$label.plist"
  cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key>
  <array>
    <string>$SCRIPT_DIR/run-once.sh</string>
    <string>$agent</string>
    <string>$worktree</string>
  </array>
  <key>StartInterval</key><integer>1200</integer>
  <key>RunAtLoad</key><false/>
  <key>StandardOutPath</key><string>$LOOP_HOME/logs/$agent.launchd.out.log</string>
  <key>StandardErrorPath</key><string>$LOOP_HOME/logs/$agent.launchd.err.log</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key><string>/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    <key>MINMAX_LOOP_HOME</key><string>$LOOP_HOME</string>
  </dict>
</dict>
</plist>
PLIST
  echo "  wrote $plist"
  launchctl bootout "gui/$UID_NUM/$label" 2>/dev/null || true
  launchctl bootstrap "gui/$UID_NUM" "$plist"
  echo "  bootstrapped $label"
}

write_plist codex "$CODEX_WORKTREE"
write_plist claude "$CLAUDE_WORKTREE"

cat <<DONE

Installed. Each loop fires every 20 minutes independent of any open
terminal/chat. To check in on it:

  launchctl print gui/$UID_NUM/com.minmax.agentloop.codex
  launchctl print gui/$UID_NUM/com.minmax.agentloop.claude
  tail -f $LOOP_HOME/logs/codex.log
  tail -f $LOOP_HOME/logs/claude.log

To run one cycle right now instead of waiting for the timer:
  launchctl kickstart -k gui/$UID_NUM/com.minmax.agentloop.codex
  launchctl kickstart -k gui/$UID_NUM/com.minmax.agentloop.claude

To stop both:
  launchctl bootout gui/$UID_NUM/com.minmax.agentloop.codex
  launchctl bootout gui/$UID_NUM/com.minmax.agentloop.claude
DONE
