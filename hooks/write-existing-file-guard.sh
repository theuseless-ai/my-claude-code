#!/bin/bash
# PreToolUse(Write): block Write on a file that already exists, forcing Edit.
#
# Claude Code already refuses Write on a file it has not Read. This is the
# stricter rule: an existing file is edited, never rewritten wholesale, even
# after a Read.

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

[ "$(jq -r '.tool_name // empty' <<< "$INPUT")" = "Write" ] || exit 0

FILE_PATH=$(jq -r '.tool_input.file_path // empty' <<< "$INPUT")
[ -n "$FILE_PATH" ] || exit 0

if [ -f "$FILE_PATH" ]; then
    deny "File already exists. Use Edit to modify an existing file; Write is for creating new files."
fi

exit 0
