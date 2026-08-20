#!/usr/bin/env bash
# oh-my-claudecode status line — Ayu Dark, rounded powerline pills
# Reads Claude Code JSON session data from stdin, outputs a styled 2-line status bar.
#
# Needs a Nerd Font for the rounded caps and the segment icons. Set
# OMCC_STATUSLINE_ASCII=1 for a bracketed, icon-free fallback.

set -euo pipefail

ESC=$'\033'
R="${ESC}[0m"

# ---------------------------------------------------------------------------
# Ayu Dark palette, as "R;G;B" so one table serves both fg and bg escapes.
# ---------------------------------------------------------------------------
RGB_PANEL='28;32;40'      # #1C2028  pill background
RGB_INK='11;14;20'        # #0B0E14  text on a saturated pill
RGB_MODEL='230;180;80'    # #E6B450
RGB_GREEN='170;217;76'    # #AAD94C
RGB_ORANGE='255;143;64'   # #FF8F40
RGB_RED='240;113;120'     # #F07178
RGB_BRANCH='210;166;255'  # #D2A6FF
RGB_AGENT='89;194;255'    # #59C2FF
RGB_FG='191;189;182'      # #BFBDB6
RGB_MUTED='86;91;102'     # #565B66
RGB_TRACK='51;56;68'      # #333844  unfilled half of the bar

# ---------------------------------------------------------------------------
# Glyphs
# ---------------------------------------------------------------------------
if [[ "${OMCC_STATUSLINE_ASCII:-0}" == "1" ]]; then
    CAP_L='['; CAP_R=']'
    I_VIM=''; I_MODEL=''; I_DIR=''; I_BRANCH=''
    I_AGENT=''; I_5H='5h '; I_7D='7d '; I_PLAN=''
else
    CAP_L=''; CAP_R=''
    I_VIM=' '; I_MODEL=' '; I_DIR=' '; I_BRANCH=' '
    I_AGENT=' '; I_5H=' '; I_7D=' '; I_PLAN=' '
fi

# pill <bg-rgb> <fg-rgb> <text> — text supplies its own padding
pill() {
    printf '%s' \
        "${ESC}[38;2;${1}m${CAP_L}${R}" \
        "${ESC}[48;2;${1}m${ESC}[38;2;${2}m${3}${R}" \
        "${ESC}[38;2;${1}m${CAP_R}${R}"
}

# ---------------------------------------------------------------------------
# Read JSON from stdin
# ---------------------------------------------------------------------------
JSON=$(cat)

if ! command -v jq &>/dev/null; then
    echo "statusline: jq required but not found" >&2
    exit 1
fi

jqv() { jq -r "$1 // empty" <<< "$JSON" 2>/dev/null || true; }

MODEL=$(jqv '.model.display_name'); MODEL=${MODEL:-unknown}
AGENT_NAME=$(jqv '.agent.name')
VIM_MODE=$(jqv '.vim.mode')

# ---------------------------------------------------------------------------
# Context percentage
#
# Self-calculated rather than read from .used_percentage: Claude Code has
# reported that field against 200K even in a 1M-context session.
# ---------------------------------------------------------------------------
CTX_SIZE=$(jq -r '.context_window.context_window_size // 0' <<< "$JSON" 2>/dev/null || echo 0)
CTX_INPUT=$(jq -r '.context_window.current_usage.input_tokens // 0' <<< "$JSON" 2>/dev/null || echo 0)
CTX_CACHE_CREATE=$(jq -r '.context_window.current_usage.cache_creation_input_tokens // 0' <<< "$JSON" 2>/dev/null || echo 0)
CTX_CACHE_READ=$(jq -r '.context_window.current_usage.cache_read_input_tokens // 0' <<< "$JSON" 2>/dev/null || echo 0)

if [[ "$CTX_SIZE" =~ ^[0-9]+$ ]] && (( CTX_SIZE > 0 )) && [[ "$CTX_INPUT" =~ ^[0-9]+$ ]]; then
    USED_PCT=$(( (CTX_INPUT + CTX_CACHE_CREATE + CTX_CACHE_READ) * 100 / CTX_SIZE ))
else
    USED_PCT=$(jq -r '.context_window.used_percentage // 0' <<< "$JSON" 2>/dev/null || echo 0)
fi

USED_PCT=${USED_PCT%%.*}
USED_PCT=${USED_PCT:-0}
if ! [[ "$USED_PCT" =~ ^[0-9]+$ ]]; then USED_PCT=0; fi
if (( USED_PCT > 100 )); then USED_PCT=100; fi

# ---------------------------------------------------------------------------
# Project and branch
#
# The directory is what tells two concurrent sessions apart, so it leads; the
# leaf is appended only when the cwd sits below the project root.
# ---------------------------------------------------------------------------
PROJECT_DIR=$(jqv '.workspace.project_dir'); PROJECT_DIR=${PROJECT_DIR:-$(jqv '.cwd')}
CURRENT_DIR=$(jqv '.workspace.current_dir'); CURRENT_DIR=${CURRENT_DIR:-$PROJECT_DIR}

PROJ=""
LEAF=""
if [[ -n "$PROJECT_DIR" ]]; then
    PROJ=$(basename "$PROJECT_DIR")
    if [[ -n "$CURRENT_DIR" && "$CURRENT_DIR" != "$PROJECT_DIR" ]]; then
        LEAF=$(basename "$CURRENT_DIR")
    fi
fi

BRANCH=$(git branch --show-current 2>/dev/null || echo "detached")
BRANCH=${BRANCH:-detached}

# The payload carries no terminal width, so line 1 runs on a fixed budget: the
# path gets 16 columns and the branch takes what is left of 28.
#
# When the cwd sits below the project root the leaf is the part that says where
# you actually are, so it is kept whole and the project name is shortened around
# it — truncating left to right would drop the leaf entirely and leave two
# sessions in the same repo looking identical.
DIR_MAX=16
LEAF_MAX=10
if [[ -n "$LEAF" ]]; then
    if (( ${#LEAF} > LEAF_MAX )); then
        LEAF="${LEAF:0:$(( LEAF_MAX - 1 ))}…"
    fi
    PROJ_MAX=$(( DIR_MAX - ${#LEAF} - 1 ))
    if (( PROJ_MAX < 4 )); then PROJ_MAX=4; fi
    if (( ${#PROJ} > PROJ_MAX )); then
        PROJ="${PROJ:0:$(( PROJ_MAX - 1 ))}…"
    fi
    DIR_STR="${PROJ}/${LEAF}"
else
    DIR_STR="$PROJ"
    if (( ${#DIR_STR} > DIR_MAX )); then
        DIR_STR="${DIR_STR:0:$(( DIR_MAX - 1 ))}…"
    fi
fi

BRANCH_MAX=$(( 28 - ${#DIR_STR} ))
if (( BRANCH_MAX < 8 )); then BRANCH_MAX=8; fi
if (( ${#BRANCH} > BRANCH_MAX )); then
    BRANCH="${BRANCH:0:$(( BRANCH_MAX - 1 ))}…"
fi

# ---------------------------------------------------------------------------
# Progress bar — a rounded pill with the reading centred inside it
# ---------------------------------------------------------------------------
BAR_WIDTH=18

build_bar() {
    local pct=$1 w=$BAR_WIDTH
    local filled=$(( pct * w / 100 ))

    # Never round a non-zero reading down to an empty bar, or a sub-100 one up
    # to a full bar — either would misreport the state at the edges.
    if (( pct > 0 && filled == 0 )); then filled=1; fi
    if (( pct < 100 && filled >= w )); then filled=$(( w - 1 )); fi
    if (( filled > w )); then filled=$w; fi

    local color
    if   (( pct >= 90 )); then color="$RGB_RED"
    elif (( pct >= 70 )); then color="$RGB_ORANGE"
    else                       color="$RGB_GREEN"
    fi

    # Centre the reading across the whole track and colour it per cell, so the
    # label straddles the fill boundary with each half in its own contrast.
    local label=" ${pct}% " pad text
    pad=$(( (w - ${#label}) / 2 ))
    printf -v text '%*s%s%*s' "$pad" '' "$label" "$(( w - pad - ${#label} ))" ''
    text="${text:0:w}"

    # Precomputed so the per-cell loop spawns nothing.
    local on="${ESC}[48;2;${color}m${ESC}[38;2;${RGB_INK}m"
    local off="${ESC}[48;2;${RGB_TRACK}m${ESC}[38;2;${RGB_FG}m"

    local lcap="$color" rcap="$RGB_TRACK"
    if (( filled == 0 )); then lcap="$RGB_TRACK"; fi
    if (( filled >= w )); then rcap="$color"; fi

    local out="${ESC}[38;2;${lcap}m${CAP_L}${R}"
    local i
    for (( i = 0; i < w; i++ )); do
        if (( i < filled )); then out+="${on}${text:i:1}"
        else                      out+="${off}${text:i:1}"
        fi
    done
    out+="${R}${ESC}[38;2;${rcap}m${CAP_R}${R}"
    printf '%s' "$out"
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
            PLAN_STR="${PLAN_NAME} [${WAVE_COUNT}w]"
        else
            PLAN_STR="${PLAN_NAME}"
        fi
    fi
fi

# ---------------------------------------------------------------------------
# Rate limits — 5-hour (session) and 7-day (weekly) windows
#
# Present only for Claude.ai Pro/Max, and only after the first API response of
# a session. Either window can be absent on its own.
# ---------------------------------------------------------------------------
NOW=$(date +%s)

# epoch -> "2h13m" / "47m"; nothing if the timestamp is absent or already past
fmt_reset() {
    local at="$1" delta
    [[ "$at" =~ ^[0-9]+$ ]] || return 0
    delta=$(( at - NOW ))
    (( delta > 0 )) || return 0
    # The 7-day window is often days out; "144h26m" is unreadable at that scale.
    if   (( delta >= 86400 )); then printf '%dd%dh' $(( delta / 86400 )) $(( (delta % 86400) / 3600 ))
    elif (( delta >= 3600 ));  then printf '%dh%02dm' $(( delta / 3600 )) $(( (delta % 3600) / 60 ))
    else                            printf '%dm' $(( delta / 60 ))
    fi
}

# Same thresholds as the context bar, so the colours mean one thing throughout.
limit_color() {
    if   (( $1 >= 90 )); then printf '%s' "$RGB_RED"
    elif (( $1 >= 70 )); then printf '%s' "$RGB_ORANGE"
    else                      printf '%s' "$RGB_GREEN"
    fi
}

# icon, json key -> a finished pill, or nothing when the window is absent
limit_pill() {
    local icon="$1" window="$2" raw pct at reset text
    raw=$(jqv ".rate_limits.${window}.used_percentage")
    [[ -n "$raw" ]] || return 0
    pct=$(printf '%.0f' "$raw" 2>/dev/null) || return 0

    text="${icon}${pct}%"
    at=$(jqv ".rate_limits.${window}.resets_at")
    reset=$(fmt_reset "$at")
    [[ -n "$reset" ]] && text+=" ${reset}"

    pill "$RGB_PANEL" "$(limit_color "$pct")" " ${text} "
}

# ---------------------------------------------------------------------------
# Line 1 — vim mode, model, context, where you are
# ---------------------------------------------------------------------------
LINE1=""

if [[ -n "$VIM_MODE" ]]; then
    case "$VIM_MODE" in
        NORMAL)  VIM_RGB="$RGB_GREEN"  ;;
        INSERT)  VIM_RGB="$RGB_ORANGE" ;;
        VISUAL*) VIM_RGB="$RGB_BRANCH" ;;
        *)       VIM_RGB="$RGB_MUTED"  ;;
    esac
    LINE1+="$(pill "$VIM_RGB" "$RGB_INK" " ${I_VIM}${VIM_MODE} ") "
fi

LINE1+="$(pill "$RGB_PANEL" "$RGB_MODEL" " ${I_MODEL}${MODEL} ") "
LINE1+="$(build_bar "$USED_PCT")"

if [[ -n "$DIR_STR" ]]; then
    LINE1+=" $(pill "$RGB_PANEL" "$RGB_FG" \
        " ${I_DIR}${DIR_STR} ${ESC}[38;2;${RGB_BRANCH}m${I_BRANCH}${BRANCH} ")"
else
    LINE1+=" $(pill "$RGB_PANEL" "$RGB_BRANCH" " ${I_BRANCH}${BRANCH} ")"
fi

# ---------------------------------------------------------------------------
# Line 2 — agent, quota, plan
#
# These sit below the fold because line 1 already spends its 80-column budget
# on the model name, a full-width bar and the project path. Every part here is
# optional, so line 2 is emitted only when something lands on it.
# ---------------------------------------------------------------------------
PARTS=()
[[ -n "$AGENT_NAME" ]] && PARTS+=("$(pill "$RGB_PANEL" "$RGB_AGENT" " ${I_AGENT}${AGENT_NAME} ")")

L5=$(limit_pill "$I_5H" five_hour); [[ -n "$L5" ]] && PARTS+=("$L5")
L7=$(limit_pill "$I_7D" seven_day); [[ -n "$L7" ]] && PARTS+=("$L7")

[[ -n "$PLAN_STR" ]] && PARTS+=("$(pill "$RGB_PANEL" "$RGB_MUTED" " ${I_PLAN}${PLAN_STR} ")")

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
printf '%s\n' "$LINE1"
if (( ${#PARTS[@]} > 0 )); then
    printf '%s\n' "${PARTS[*]}"
fi
