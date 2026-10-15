#!/bin/bash
# Drives the running Claudenotchi app through the mascot states using the real hook helper,
# without needing a Claude Code session.
#
#   scripts/fake-session.sh                 # about 2s per step
#   PAUSE=0.5 scripts/fake-session.sh       # faster
#   ON_STEP=./check.sh scripts/fake-session.sh   # runs ./check.sh "<step name>" after each pause
#   CLAUDENOTCHI_SOCKET=/tmp/x.sock ...     # talk to an app listening on another socket
#
# The idle rotation (30-90s) and sleep (5 min) are timer driven; run the app and wait to see them.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
package="$root/Packages/ClaudenotchiCore"
helper="${CLAUDENOTCHI_HOOK:-$package/.build/release/claudenotchi-hook}"
pause="${PAUSE:-2}"
session="fake-$$"

if [ ! -x "$helper" ]; then
  echo "building claudenotchi-hook..." >&2
  (cd "$package" && swift build -c release --product claudenotchi-hook >&2)
fi

args=()
[ -n "${CLAUDENOTCHI_SOCKET:-}" ] && args=(--socket "$CLAUDENOTCHI_SOCKET")

# step <label> <hook event> [tool] [message] [hold seconds]
step() {
  local label="$1" event="$2" tool="${3:-}" message="${4:-}" hold="${5:-$pause}"
  printf '{"session_id":"%s","cwd":"%s","hook_event_name":"%s","tool_name":"%s","message":"%s"}' \
    "$session" "$PWD" "$event" "$tool" "$message" | "$helper" ${args[@]+"${args[@]}"}
  printf '%-34s %s %s\n' "$label" "$event" "$tool"
  sleep "$hold"
  if [ -n "${ON_STEP:-}" ]; then "$ON_STEP" "$label"; fi
}

step "waiting"                  SessionStart
step "thinking"                 UserPromptSubmit
step "coding"                   PreToolUse   Edit
step "thinking (tool finished)" PostToolUse  Edit
step "reading"                  PreToolUse   Read
step "bash"                     PreToolUse   Bash
step "web search"               PreToolUse   WebSearch
step "needs input"              PermissionRequest Bash "Claude needs your permission to use Bash"
step "thinking (approved)"      PostToolUse  Bash
step "error"                    PostToolUseFailure Bash "" 1
step "thinking (error expired)" PreToolUse   Task "" 3
step "done"                     Stop "" "" 1
step "waiting (done expired)"   SessionEnd "" "" 5
echo "done."
