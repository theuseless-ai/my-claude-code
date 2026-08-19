#!/bin/bash
# SessionStart: tell a fresh or resumed session what plan state already exists.
#
# This used to run on PreCompact, which cannot inject context — PreCompact has
# no additionalContext in its output contract, so the hook was a no-op for its
# entire life. SessionStart fires on startup, resume, clear and compact, which
# covers the case it was written for.

cat > /dev/null   # drain stdin; nothing here depends on it

collect() {
    [ -d "$1" ] || return
    find "$1" -maxdepth 1 -name '*.md' -type f 2>/dev/null | sort | sed 's/^/  - /'
}

PLANS=$(collect ".sisyphus/plans")
NOTEPADS=$(collect ".sisyphus/notepads")

[ -n "$PLANS$NOTEPADS" ] || exit 0

CTX="This project has existing oh-my-claudecode working state."
[ -n "$PLANS" ]    && CTX="${CTX}"$'\nActive plans (read before resuming plan-based work):\n'"${PLANS}"
[ -n "$NOTEPADS" ] && CTX="${CTX}"$'\nActive notepads (shared task context):\n'"${NOTEPADS}"

jq -n --arg ctx "$CTX" '{
    hookSpecificOutput: {
        hookEventName: "SessionStart",
        additionalContext: $ctx
    }
}'

exit 0
