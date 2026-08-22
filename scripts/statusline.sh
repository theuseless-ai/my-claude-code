#!/usr/bin/env bash
# oh-my-claudecode status line — Ayu Dark
# Reads Claude Code JSON session data from stdin, outputs a styled 2-line status bar.
#
# Pure ASCII labels plus two box-drawing characters (━ U+2501, ─ U+2500) — no
# Nerd Font dependency, no PUA glyphs, no fallback code path.

set -euo pipefail

ESC=$'\033'
R="${ESC}[0m"

# ---------------------------------------------------------------------------
# Ayu Dark palette, as "R;G;B"
#
# Segments are plain coloured runs separated by spacing — no caps, no frames,
# no background paint anywhere, including the bars.
# ---------------------------------------------------------------------------
RGB_MODEL='230;180;80'    # #E6B450
RGB_DIR='191;189;182'     # #BFBDB6
RGB_BRANCH='210;166;255'  # #D2A6FF
RGB_GREEN='170;217;76'    # #AAD94C
RGB_ORANGE='255;143;64'   # #FF8F40
RGB_RED='240;113;120'     # #F07178
RGB_PLAN='92;103;115'     # #5C6773  labels, separators, effort
RGB_TRACK='58;65;80'      # #3A4150  unfilled cell of a bar

# seg <rgb> <text> — one segment in a single colour, no padding of its own.
# Segments are joined with $GAP below; a leading space here would indent the
# whole line away from the footer beneath it.
GAP=' · '
seg() {
    printf '%s' "${ESC}[38;2;${1}m${2}${R}"
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
# "Opus 5 (1M context)" -> "Opus 5 (1M)". The word adds nothing next to a size
# and costs eight columns on the one line that is tightest.
MODEL=${MODEL/ context)/)}
EFFORT=$(jqv '.effort.level')

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
        LEAF="${LEAF:0:$(( LEAF_MAX - 1 ))}"$'…'
    fi
    PROJ_MAX=$(( DIR_MAX - ${#LEAF} - 1 ))
    if (( PROJ_MAX < 4 )); then PROJ_MAX=4; fi
    if (( ${#PROJ} > PROJ_MAX )); then
        PROJ="${PROJ:0:$(( PROJ_MAX - 1 ))}"$'…'
    fi
    DIR_STR="${PROJ}/${LEAF}"
else
    DIR_STR="$PROJ"
    if (( ${#DIR_STR} > DIR_MAX )); then
        DIR_STR="${DIR_STR:0:$(( DIR_MAX - 1 ))}"$'…'
    fi
fi

BRANCH_MAX=$(( 28 - ${#DIR_STR} ))
if (( BRANCH_MAX < 8 )); then BRANCH_MAX=8; fi
if (( ${#BRANCH} > BRANCH_MAX )); then
    BRANCH="${BRANCH:0:$(( BRANCH_MAX - 1 ))}"$'…'
fi

# ---------------------------------------------------------------------------
# Bars — a filled run of ━ and an empty run of ─, no background paint
# ---------------------------------------------------------------------------
threshold_color() {
    if   (( $1 >= 90 )); then printf '%s' "$RGB_RED"
    elif (( $1 >= 70 )); then printf '%s' "$RGB_ORANGE"
    else                      printf '%s' "$RGB_GREEN"
    fi
}

# build_bar <pct> <width> — a coloured run of filled/empty cells
build_bar() {
    local pct=$1 w=$2
    local filled=$(( pct * w / 100 ))

    # Never round a non-zero reading down to an empty bar, or a sub-100 one up
    # to a full bar — either would misreport the state at the edges.
    if (( pct > 0 && filled == 0 )); then filled=1; fi
    if (( pct < 100 && filled >= w )); then filled=$(( w - 1 )); fi
    if (( filled > w )); then filled=$w; fi

    local color; color=$(threshold_color "$pct")
    local empty=$(( w - filled ))
    local out=""
    (( filled > 0 )) && out+="${ESC}[38;2;${color}m$(printf '━%.0s' $(seq 1 "$filled"))"
    (( empty > 0 )) && out+="${ESC}[38;2;${RGB_TRACK}m$(printf '─%.0s' $(seq 1 "$empty"))"
    out+="$R"
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

# label, json key, bar width -> a finished "label bar pct% reset" segment, or
# nothing when the window is absent from the payload
quota_seg() {
    local label="$1" window="$2" width="$3" raw pct at reset color text
    raw=$(jqv ".rate_limits.${window}.used_percentage")
    [[ -n "$raw" ]] || return 0
    pct=$(printf '%.0f' "$raw" 2>/dev/null) || return 0
    if (( pct > 100 )); then pct=100; fi
    if (( pct < 0 )); then pct=0; fi

    color=$(threshold_color "$pct")
    text="$(seg "$RGB_PLAN" "${label} ")$(build_bar "$pct" "$width") $(seg "$color" "${pct}%")"

    at=$(jqv ".rate_limits.${window}.resets_at")
    reset=$(fmt_reset "$at")
    [[ -n "$reset" ]] && text+=" $(seg "$color" "$reset")"

    printf '%s' "$text"
}

# ---------------------------------------------------------------------------
# Line 1 — [project]:branch · model / effort · plan, hard-capped at 80
# printable columns since the payload carries no terminal width.
# ---------------------------------------------------------------------------
LINE1=""
LINE1_LEN=0
LINE1_BUDGET=80

add1() {
    local color="$1" text="$2"
    (( LINE1_LEN >= LINE1_BUDGET )) && return 0
    local remaining=$(( LINE1_BUDGET - LINE1_LEN ))
    if (( ${#text} > remaining )); then
        if (( remaining <= 1 )); then
            text=""
        else
            text="${text:0:$(( remaining - 1 ))}"$'…'
        fi
    fi
    [[ -z "$text" ]] && return 0
    LINE1+="$(seg "$color" "$text")"
    LINE1_LEN=$(( LINE1_LEN + ${#text} ))
}

# The brackets frame the project name, so they are skipped along with it when
# the payload carries no directory at all — an empty "[]" frames nothing.
if [[ -n "$DIR_STR" ]]; then
    add1 "$RGB_PLAN" "["
    add1 "$RGB_DIR" "$DIR_STR"
    add1 "$RGB_PLAN" "]:"
fi
add1 "$RGB_BRANCH" "$BRANCH"
add1 "$RGB_PLAN" " · "
add1 "$RGB_MODEL" "$MODEL"
[[ -n "$EFFORT" ]] && add1 "$RGB_PLAN" " / ${EFFORT}"
[[ -n "$PLAN_STR" ]] && add1 "$RGB_PLAN" " · ${PLAN_STR}"

# ---------------------------------------------------------------------------
# Line 2 — ctx bar · 5h quota · 7d quota. Always shows ctx; a quota segment is
# omitted entirely when that window is absent from the payload.
# ---------------------------------------------------------------------------
PARTS=()
PARTS+=("$(seg "$RGB_PLAN" "ctx ")$(build_bar "$USED_PCT" 18) $(seg "$(threshold_color "$USED_PCT")" "${USED_PCT}%")")

L5=$(quota_seg "5h" five_hour 8); [[ -n "$L5" ]] && PARTS+=("$L5")
L7=$(quota_seg "7d" seven_day 8); [[ -n "$L7" ]] && PARTS+=("$L7")

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
printf '%s\n' "$LINE1"
if (( ${#PARTS[@]} > 0 )); then
    OLD_IFS=$IFS; IFS=''
    printf '%s\n' "$( { local_first=1; for part in "${PARTS[@]}"; do
        if (( local_first )); then printf '%s' "$part"; local_first=0
        else printf '%s%s' "$GAP" "$part"; fi
    done; } )"
    IFS=$OLD_IFS
fi
