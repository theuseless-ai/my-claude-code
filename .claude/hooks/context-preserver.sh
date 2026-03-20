#!/bin/bash
# PreCompact hook: Preserves critical context before compaction.
# Injects active plan references and working state so they survive context compression.

INPUT=$(cat)

ADDITIONAL_CONTEXT=""

# Check for active plans
if [ -d ".sisyphus/plans" ]; then
  PLANS=$(find .sisyphus/plans -name "*.md" -type f 2>/dev/null)
  if [ -n "$PLANS" ]; then
    PLAN_LIST=$(echo "$PLANS" | tr '\n' ', ')
    ADDITIONAL_CONTEXT="Active plans: ${PLAN_LIST}. Read these files to resume plan-based work."
  fi
fi

# Check for active notepads
if [ -d ".sisyphus/notepads" ]; then
  NOTEPADS=$(find .sisyphus/notepads -name "*.md" -type f 2>/dev/null)
  if [ -n "$NOTEPADS" ]; then
    NOTEPAD_LIST=$(echo "$NOTEPADS" | tr '\n' ', ')
    ADDITIONAL_CONTEXT="${ADDITIONAL_CONTEXT} Active notepads: ${NOTEPAD_LIST}."
  fi
fi

if [ -n "$ADDITIONAL_CONTEXT" ]; then
  jq -n --arg ctx "$ADDITIONAL_CONTEXT" '{"additionalContext": $ctx}'
fi

exit 0
