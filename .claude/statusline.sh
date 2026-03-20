#!/usr/bin/env bash
# oh-my-claudecode status line — Ayu Dark theme
# Reads Claude Code JSON session data from stdin, outputs a styled 2-line status bar.

set -euo pipefail

# ---------------------------------------------------------------------------
# Ayu Dark color palette (truecolor)
# ---------------------------------------------------------------------------
C_MODEL='\033[38;2;230;180;80m'      # #E6B450
C_BAR_GREEN='\033[38;2;170;217;76m'  # #AAD94C
C_BAR_ORANGE='\033[38;2;255;143;64m' # #FF8F40
C_BAR_RED='\033[38;2;240;113;120m'   # #F07178
C_BRANCH='\033[38;2;210;166;255m'    # #D2A6FF
C_AGENT='\033[38;2;89;194;255m'      # #59C2FF
C_TASKS='\033[38;2;149;230;203m'     # #95E6CB
C_PLAN='\033[38;2;191;189;182m'      # #BFBDB6
C_PR_PASS='\033[38;2;170;217;76m'    # #AAD94C
C_PR_FAIL='\033[38;2;240;113;120m'   # #F07178
C_PR_PEND='\033[38;2;230;180;80m'    # #E6B450
C_SEP='\033[38;2;86;91;102m'         # #565B66
C_RESET='\033[0m'

SEP="${C_SEP}│${C_RESET}"

# ---------------------------------------------------------------------------
# Read JSON from stdin
# ---------------------------------------------------------------------------
JSON=$(cat)

# ---------------------------------------------------------------------------
# Parse JSON — require jq
# ---------------------------------------------------------------------------
if ! command -v jq &>/dev/null; then
    echo "statusline: jq required but not found" >&2
    exit 1
fi

MODEL=$(echo "$JSON" | jq -r '.model.display_name // "unknown"' 2>/dev/null || echo "unknown")
AGENT_NAME=$(echo "$JSON" | jq -r '.agent.name // empty' 2>/dev/null || true)

# Calculate context % ourselves to work around CC bug with 1M context sessions
# CC sometimes reports used_percentage against 200K even when using 1M extended context
CTX_SIZE=$(echo "$JSON" | jq -r '.context_window.context_window_size // 0' 2>/dev/null || echo "0")
CTX_INPUT=$(echo "$JSON" | jq -r '.context_window.current_usage.input_tokens // 0' 2>/dev/null || echo "0")
CTX_CACHE_CREATE=$(echo "$JSON" | jq -r '.context_window.current_usage.cache_creation_input_tokens // 0' 2>/dev/null || echo "0")
CTX_CACHE_READ=$(echo "$JSON" | jq -r '.context_window.current_usage.cache_read_input_tokens // 0' 2>/dev/null || echo "0")

if [[ "$CTX_SIZE" -gt 0 && "$CTX_INPUT" != "null" ]]; then
    # Self-calculate: (input + cache_creation + cache_read) / context_window_size * 100
    CTX_USED=$(( CTX_INPUT + CTX_CACHE_CREATE + CTX_CACHE_READ ))
    USED_PCT=$(( CTX_USED * 100 / CTX_SIZE ))
else
    # Fallback to CC's reported percentage
    USED_PCT=$(echo "$JSON" | jq -r '.context_window.used_percentage // 0' 2>/dev/null || echo "0")
fi

# Ensure USED_PCT is an integer
USED_PCT=${USED_PCT%%.*}
USED_PCT=${USED_PCT:-0}
if ! [[ "$USED_PCT" =~ ^[0-9]+$ ]]; then
    USED_PCT=0
fi
if (( USED_PCT > 100 )); then USED_PCT=100; fi

# ---------------------------------------------------------------------------
# Git branch
# ---------------------------------------------------------------------------
BRANCH=$(git branch --show-current 2>/dev/null || echo "detached")
BRANCH=${BRANCH:-detached}

# ---------------------------------------------------------------------------
# Progress bar — 10 chars wide
# ---------------------------------------------------------------------------
build_bar() {
    local pct=$1
    local filled=$(( pct / 10 ))
    if (( pct > 0 && filled == 0 )); then filled=1; fi
    if (( filled > 10 )); then filled=10; fi

    # Pick color based on percentage
    local color
    if (( pct >= 90 )); then
        color="$C_BAR_RED"
    elif (( pct >= 70 )); then
        color="$C_BAR_ORANGE"
    else
        color="$C_BAR_GREEN"
    fi

    local bar=""
    for (( i=0; i<filled; i++ )); do bar+="="; done
    local rest=""
    for (( i=filled; i<10; i++ )); do rest+=" "; done

    printf '%b[%b%s%b%s]%b %d%%' "$C_SEP" "$color" "$bar" "$C_RESET" "$rest" "$C_RESET" "$pct"
}

# ---------------------------------------------------------------------------
# Tasks — count background claude subprocesses (best-effort)
# ---------------------------------------------------------------------------
TASK_COUNT=0
if command -v pgrep &>/dev/null; then
    TASK_COUNT=$(pgrep -f 'claude' 2>/dev/null | wc -l || echo "0")
    # Subtract 1 for the main process if count > 0, and subtract self
    # This is inherently imprecise; treat as rough indicator
    if (( TASK_COUNT > 1 )); then
        TASK_COUNT=$(( TASK_COUNT - 1 ))
    else
        TASK_COUNT=0
    fi
fi

# ---------------------------------------------------------------------------
# Plan detection — newest .md in .sisyphus/plans/
# ---------------------------------------------------------------------------
PLAN_STR=""
PLANS_DIR=".sisyphus/plans"
if [[ -d "$PLANS_DIR" ]]; then
    LATEST_PLAN=$(ls -t "$PLANS_DIR"/*.md 2>/dev/null | head -1 || true)
    if [[ -n "$LATEST_PLAN" ]]; then
        PLAN_NAME=$(basename "$LATEST_PLAN" .md)
        WAVE_COUNT=$(grep -c '^### Wave' "$LATEST_PLAN" 2>/dev/null || echo "0")
        if (( WAVE_COUNT > 0 )); then
            PLAN_STR="${C_PLAN}Plan: ${PLAN_NAME} [${WAVE_COUNT} waves]${C_RESET}"
        else
            PLAN_STR="${C_PLAN}Plan: ${PLAN_NAME}${C_RESET}"
        fi
    fi
fi

# ---------------------------------------------------------------------------
# GH PR checks — cached for 30 seconds
# ---------------------------------------------------------------------------
PR_STR=""
BRANCH_SAFE=$(echo "$BRANCH" | tr '/' '-')
CACHE_FILE="/tmp/cc-statusline-pr-cache-${BRANCH_SAFE}"
CACHE_TTL=30

fetch_pr_checks() {
    if ! command -v gh &>/dev/null; then
        echo ""
        return
    fi
    gh pr checks --json name,state 2>/dev/null || echo ""
}

PR_JSON=""
if [[ -f "$CACHE_FILE" ]]; then
    CACHE_AGE=$(( $(date +%s) - $(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0) ))
    if (( CACHE_AGE < CACHE_TTL )); then
        PR_JSON=$(cat "$CACHE_FILE")
    fi
fi

if [[ -z "$PR_JSON" ]]; then
    PR_JSON=$(fetch_pr_checks)
    if [[ -n "$PR_JSON" ]]; then
        echo "$PR_JSON" > "$CACHE_FILE"
    fi
fi

if [[ -n "$PR_JSON" && "$PR_JSON" != "null" && "$PR_JSON" != "[]" && "$PR_JSON" != "" ]]; then
    PASS=$(echo "$PR_JSON" | jq '[.[] | select(.state == "SUCCESS")] | length' 2>/dev/null || echo 0)
    FAIL=$(echo "$PR_JSON" | jq '[.[] | select(.state == "FAILURE")] | length' 2>/dev/null || echo 0)
    PEND=$(echo "$PR_JSON" | jq '[.[] | select(.state != "SUCCESS" and .state != "FAILURE")] | length' 2>/dev/null || echo 0)
    # Detect if gh pr checks returned data vs "no PR" error
    if (( PASS + FAIL + PEND > 0 )); then
        PR_NUM=$(gh pr view --json number -q '.number' 2>/dev/null || echo "")
        if [[ -n "$PR_NUM" ]]; then
            PR_STR="PR #${PR_NUM}: ${C_PR_PASS}✓${PASS}${C_RESET} ${C_PR_FAIL}✗${FAIL}${C_RESET} ${C_PR_PEND}●${PEND}${C_RESET}"
        else
            PR_STR="PR: ${C_PR_PASS}✓${PASS}${C_RESET} ${C_PR_FAIL}✗${FAIL}${C_RESET} ${C_PR_PEND}●${PEND}${C_RESET}"
        fi
    else
        PR_STR="${C_PLAN}No PR${C_RESET}"
    fi
else
    PR_STR="${C_PLAN}No PR${C_RESET}"
fi

# ---------------------------------------------------------------------------
# Build Line 1
# ---------------------------------------------------------------------------
LINE1="${C_MODEL}${MODEL}${C_RESET} ${SEP} $(build_bar "$USED_PCT") ${SEP} ${C_BRANCH}${BRANCH}${C_RESET}"

# Agent section — only if agent is active
if [[ -n "$AGENT_NAME" ]]; then
    LINE1+=" ${SEP} ${C_AGENT}${AGENT_NAME}${C_RESET}"
fi

LINE1+=" ${SEP} ${C_TASKS}${TASK_COUNT} tasks${C_RESET}"

# ---------------------------------------------------------------------------
# Build Line 2 (conditional)
# ---------------------------------------------------------------------------
LINE2=""
if [[ -n "$PLAN_STR" && -n "$PR_STR" ]]; then
    LINE2="${PLAN_STR} ${SEP} ${PR_STR}"
elif [[ -n "$PLAN_STR" ]]; then
    LINE2="${PLAN_STR} ${SEP} ${PR_STR}"
elif [[ -n "$PR_STR" ]]; then
    LINE2="$PR_STR"
fi

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
printf '%b\n' "$LINE1"
if [[ -n "$LINE2" ]]; then
    printf '%b\n' "$LINE2"
fi
