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
C_PLAN='\033[38;2;191;189;182m'      # #BFBDB6
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

# Cap the branch so a long name cannot wrap line 1. The statusline payload does
# not carry terminal width, so this is a fixed budget rather than adaptive:
# 18 chars keeps line 1 within 80 columns in the worst case: longest agent
# name (multimodal-looker) in the agent slot and the bar reading 100%.
BRANCH_MAX=18
if (( ${#BRANCH} > BRANCH_MAX )); then
    BRANCH="${BRANCH:0:$(( BRANCH_MAX - 1 ))}…"
fi

# ---------------------------------------------------------------------------
# Progress bar
# ---------------------------------------------------------------------------
# 20 shaded cells, no brackets: the block glyphs already read as a bar, and the
# empty track is drawn in the separator colour so position stays legible.
BAR_WIDTH=20

build_bar() {
    local pct=$1
    local filled=$(( pct * BAR_WIDTH / 100 ))

    # Never round a non-zero reading down to an empty bar, or a sub-100 one up
    # to a full bar — either would misreport the state at the edges.
    if (( pct > 0 && filled == 0 )); then filled=1; fi
    if (( pct < 100 && filled >= BAR_WIDTH )); then filled=$(( BAR_WIDTH - 1 )); fi
    if (( filled > BAR_WIDTH )); then filled=$BAR_WIDTH; fi

    # Pick color based on percentage
    local color
    if (( pct >= 90 )); then
        color="$C_BAR_RED"
    elif (( pct >= 70 )); then
        color="$C_BAR_ORANGE"
    else
        color="$C_BAR_GREEN"
    fi

    local bar="" rest="" i
    for (( i=0; i<filled; i++ )); do bar+="▓"; done
    for (( i=filled; i<BAR_WIDTH; i++ )); do rest+="░"; done

    printf '%b%s%b%s%b %d%%' "$color" "$bar" "$C_SEP" "$rest" "$C_RESET" "$pct"
}

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
# Rate limits — 5-hour (session) and 7-day (weekly) windows
#
# Present only for Claude.ai Pro/Max, and only after the first API response of a
# session. Either window can be absent on its own, so they are read separately
# and the whole section is dropped when neither is available.
#
# Helpers emit *literal* escape sequences (printf '%s'); the final output stage
# interprets them once with printf '%b'.
# ---------------------------------------------------------------------------
NOW=$(date +%s)

# epoch -> "2h13m" / "47m"; nothing if the timestamp is absent or already past
fmt_reset() {
    local at="$1" delta
    [[ "$at" =~ ^[0-9]+$ ]] || return 0
    delta=$(( at - NOW ))
    (( delta > 0 )) || return 0
    # The 7-day window is often days out; "144h26m" is unreadable at that scale.
    if (( delta >= 86400 )); then
        printf '%dd%dh' $(( delta / 86400 )) $(( (delta % 86400) / 3600 ))
    elif (( delta >= 3600 )); then
        printf '%dh%02dm' $(( delta / 3600 )) $(( (delta % 3600) / 60 ))
    else
        printf '%dm' $(( delta / 60 ))
    fi
}

# Same thresholds as the context bar, so the colours mean one thing throughout.
limit_color() {
    if   (( $1 >= 90 )); then printf '%s' "$C_BAR_RED"
    elif (( $1 >= 70 )); then printf '%s' "$C_BAR_ORANGE"
    else                      printf '%s' "$C_BAR_GREEN"
    fi
}

# label, json key -> "5h 19% (1h13m)"; the countdown is always shown
limit_seg() {
    local label="$1" window="$2" raw pct at reset
    raw=$(jq -r ".rate_limits.${window}.used_percentage // empty" <<< "$JSON" 2>/dev/null) || return 0
    [[ -n "$raw" ]] || return 0
    pct=$(printf '%.0f' "$raw" 2>/dev/null) || return 0

    printf '%s' "$(limit_color "$pct")${label} ${pct}%${C_RESET}"

    at=$(jq -r ".rate_limits.${window}.resets_at // empty" <<< "$JSON" 2>/dev/null) || return 0
    reset=$(fmt_reset "$at")
    [[ -n "$reset" ]] && printf '%s' " ${C_SEP}(${reset})${C_RESET}"
}

LIMIT_5H=$(limit_seg "5h" five_hour)
LIMIT_7D=$(limit_seg "7d" seven_day)

if [[ -n "$LIMIT_5H" && -n "$LIMIT_7D" ]]; then
    LIMITS="${LIMIT_5H} ${C_SEP}·${C_RESET} ${LIMIT_7D}"
else
    LIMITS="${LIMIT_5H}${LIMIT_7D}"
fi

# ---------------------------------------------------------------------------
# Build Line 1
# ---------------------------------------------------------------------------
LINE1="${C_MODEL}${MODEL}${C_RESET} ${SEP} $(build_bar "$USED_PCT")"
LINE1+=" ${SEP} ${C_BRANCH}${BRANCH}${C_RESET}"

# Agent section — only if agent is active
if [[ -n "$AGENT_NAME" ]]; then
    LINE1+=" ${SEP} ${C_AGENT}${AGENT_NAME}${C_RESET}"
fi


# ---------------------------------------------------------------------------
# Build Line 2 (conditional)
#
# Quota lives here rather than on line 1: a 20-cell bar plus always-on reset
# countdowns plus a branch name came to 97 columns, which wraps an 80-column
# terminal. Both parts are optional, so line 2 is emitted only when one exists.
# ---------------------------------------------------------------------------
LINE2=""
if [[ -n "$LIMITS" && -n "$PLAN_STR" ]]; then
    LINE2="${LIMITS} ${SEP} ${PLAN_STR}"
else
    LINE2="${LIMITS}${PLAN_STR}"
fi

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
printf '%b\n' "$LINE1"
if [[ -n "$LINE2" ]]; then
    printf '%b\n' "$LINE2"
fi
