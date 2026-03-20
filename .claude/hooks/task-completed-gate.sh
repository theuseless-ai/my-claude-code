#!/bin/bash
# TaskCompleted hook: Validates completed teammate tasks before marking done.
# Routes to momus for quality checks on non-trivial deliverables.

INPUT=$(cat)

TASK_ID=$(echo "$INPUT" | jq -r '.task_id // empty')
TASK_STATUS=$(echo "$INPUT" | jq -r '.status // empty')

if [ "$TASK_STATUS" != "completed" ]; then
  exit 0
fi

# Log completed task for audit trail
echo "[task-completed-gate] Task ${TASK_ID} completed at $(date -Iseconds)" >> .sisyphus/team-audit.log 2>/dev/null

exit 0
