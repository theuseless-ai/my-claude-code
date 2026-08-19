#!/bin/bash
# PreToolUse(Bash): block interactive TUI commands that would hang the session.

INPUT=$(cat)

deny() {
    jq -n --arg reason "$1" '{
        hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "deny",
            permissionDecisionReason: $reason
        }
    }'
    exit 0
}

[ "$(jq -r '.tool_name // empty' <<< "$INPUT")" = "Bash" ] || exit 0

COMMAND=$(jq -r '.tool_input.command // empty' <<< "$INPUT")

BLOCKED='^(vim|nvim|vi|nano|emacs|less|more|htop|top|ssh|telnet|ftp|mysql|psql|mongosh|redis-cli|irb|pry|ipython|python3?[[:space:]]*$)'

if grep -qE "$BLOCKED" <<< "$COMMAND"; then
    deny "Interactive/TUI command blocked — this environment has no terminal to drive it. Use a non-interactive form instead (cat rather than less, mysql -e rather than the mysql shell)."
fi

exit 0
