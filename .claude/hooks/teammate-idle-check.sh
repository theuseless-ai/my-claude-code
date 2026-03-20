#!/bin/bash
# TeammateIdle hook: Detects idle teammates and logs for orchestrator awareness.
# Allows atlas/momus to reassign or terminate idle teammates.

INPUT=$(cat)

TEAMMATE_ID=$(echo "$INPUT" | jq -r '.teammate_id // empty')
IDLE_DURATION=$(echo "$INPUT" | jq -r '.idle_duration_seconds // 0')

# Log idle event
echo "[teammate-idle] Teammate ${TEAMMATE_ID} idle for ${IDLE_DURATION}s at $(date -Iseconds)" >> .sisyphus/team-audit.log 2>/dev/null

exit 0
