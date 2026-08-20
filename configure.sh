#!/usr/bin/env bash
#
# oh-my-claudecode — configure the things a plugin cannot ship
#
# The plugin delivers agents, skills, hooks and scripts. Three pieces of config
# cannot travel with it, verified against Claude Code 2.1.235:
#
#   1. Permission rules. A plugin's settings.json only honours `agent` and
#      `subagentStatusLine`; a `permissions` block in it is silently ignored,
#      both via --plugin-dir and after a real marketplace install.
#   2. The output style. A plugin's output-styles/ directory does not register,
#      with or without force-for-plugin, while the identical file at user level
#      loads fine.
#   3. The status line. `statusLine` is not among the keys a plugin's
#      settings.json honours, so it has to be wired into yours.
#
# This script writes all three into your own config directory. It does NOT install
# agents, skills or hooks — the plugin owns those, and a second copy in
# ~/.claude would shadow it. That is what the pre-2.0 installer got wrong.
#
#   ./configure.sh                 # permissions + output style + status line
#   ./configure.sh --dry-run       # show the diff, write nothing
#   ./configure.sh --revert        # remove exactly what this script added
#   ./configure.sh --yes           # no confirmation prompt
#   ./configure.sh --target DIR    # a non-default config directory
#   ./configure.sh --no-style      # skip the output style
#   ./configure.sh --no-statusline # skip the status line
#
# Existing entries are preserved: permissions are unioned, never replaced, so
# running it twice changes nothing the second time.

set -euo pipefail

GREEN='\033[32m'; YELLOW='\033[33m'; RED='\033[31m'; CYAN='\033[36m'
BOLD='\033[1m'; RESET='\033[0m'
info()    { printf "  ${CYAN}[info]${RESET} %s\n" "$*"; }
success() { printf "  ${GREEN}[ok]${RESET}   %s\n" "$*"; }
warn()    { printf "  ${YELLOW}[warn]${RESET} %s\n" "$*"; }
error()   { printf "  ${RED}[err]${RESET}  %s\n" "$*" >&2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
DRY_RUN=0; ASSUME_YES=0; REVERT=0; WITH_STYLE=1; WITH_STATUSLINE=1

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)  DRY_RUN=1; shift ;;
        --revert)   REVERT=1; shift ;;
        --yes|-y)   ASSUME_YES=1; shift ;;
        --no-style)      WITH_STYLE=0; shift ;;
        --no-statusline) WITH_STATUSLINE=0; shift ;;
        --target)   TARGET_DIR="${2:?--target needs a directory}"; shift 2 ;;
        -h|--help)  sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) error "Unknown option: $1"; exit 2 ;;
    esac
done
TARGET_DIR="${TARGET_DIR%/}"
SETTINGS="$TARGET_DIR/settings.json"

command -v jq > /dev/null || { error "jq is required."; exit 1; }

# The rules this script owns. --revert removes exactly these and nothing else.
read -r -d '' OURS <<'JSON' || true
{
  "allow": [
    "Read", "Edit", "Write", "Glob", "Grep",
    "Bash(git *)", "Bash(gh *)", "Bash(jq *)", "Bash(rg *)",
    "Bash(ls *)", "Bash(cat *)", "Bash(find *)", "Bash(grep *)",
    "Bash(sed *)", "Bash(awk *)", "Bash(head *)", "Bash(tail *)",
    "Bash(npm *)", "Bash(npx *)", "Bash(node *)", "Bash(pnpm *)", "Bash(yarn *)",
    "Bash(pytest *)", "Bash(python3 *)", "Bash(go *)", "Bash(cargo *)", "Bash(make *)"
  ],
  "deny": [
    "Bash(git push --force *)",
    "Bash(git push -f *)",
    "Bash(rm -rf /:*)",
    "Bash(rm -rf ~:*)",
    "Bash(chmod 777 *)"
  ]
}
JSON

printf "\n${BOLD}oh-my-claudecode — configure${RESET}\n\n"
info "Config directory: $TARGET_DIR"
[[ $REVERT -eq 1 ]] && info "Mode: revert"

mkdir -p "$TARGET_DIR"
[[ -f "$SETTINGS" ]] || echo '{}' > "$SETTINGS"
jq empty "$SETTINGS" 2>/dev/null || { error "$SETTINGS is not valid JSON — fix it first."; exit 1; }

# Checked before any early exit: this must be reported even when there is
# nothing else to change.
if [[ $REVERT -eq 0 ]] && [[ "$(jq -r '.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS // empty' "$SETTINGS")" == "1" ]]; then
    warn "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS is 1 in your settings."
    warn "With teams on, a named subagent launches as a teammate and its report does not"
    warn "return to the caller as a tool result. This roster orchestrates by subagent"
    warn "dispatch, so set it to \"0\" unless you specifically want teams. Every agent"
    warn "carries SendMessage/ListAgents either way, so agents can still message each other."
fi

STATUSLINE_SRC="$SCRIPT_DIR/scripts/statusline.sh"
STATUSLINE_DST="$TARGET_DIR/statusline.sh"

# padding defaults to 2 so the bar lines up with the footer beneath it: the
# script emits no leading whitespace of its own, so this is the only thing
# positioning it. An existing padding is kept — it is a user preference, and
# re-running this script must not silently undo it.

# Never take over a status line the user already points somewhere else.
EXISTING_SL=$(jq -r '.statusLine.command // empty' "$SETTINGS")
SL_IS_FOREIGN=0
if [[ -n "$EXISTING_SL" && "$EXISTING_SL" != "$STATUSLINE_DST" ]]; then
    SL_IS_FOREIGN=1
fi

WIRE_SL=0
if [[ $WITH_STATUSLINE -eq 1 && -f "$STATUSLINE_SRC" && $SL_IS_FOREIGN -eq 0 ]]; then
    WIRE_SL=1
fi

if [[ $REVERT -eq 1 ]]; then
    NEW=$(jq --argjson ours "$OURS" --arg sl "$STATUSLINE_DST" '
        .permissions.allow = ((.permissions.allow // []) - $ours.allow) |
        .permissions.deny  = ((.permissions.deny  // []) - $ours.deny)  |
        if (.permissions.allow | length) == 0 then del(.permissions.allow) else . end |
        if (.permissions.deny  | length) == 0 then del(.permissions.deny)  else . end |
        if (.permissions | length) == 0 then del(.permissions) else . end |
        # Only unwire a status line that points at the file this script installed.
        if (.statusLine.command // "") == $sl then del(.statusLine) else . end
    ' "$SETTINGS")
else
    NEW=$(jq --argjson ours "$OURS" --arg sl "$STATUSLINE_DST" --argjson wire "$WIRE_SL" '
        .permissions.allow = ((.permissions.allow // []) + $ours.allow | unique) |
        .permissions.deny  = ((.permissions.deny  // []) + $ours.deny  | unique) |
        if $wire == 1
        then .statusLine = { type: "command", command: $sl,
                             padding: (.statusLine.padding // 2) }
        else . end
    ' "$SETTINGS")
fi

if [[ "$NEW" == "$(cat "$SETTINGS")" ]] || diff -q <(jq -S . "$SETTINGS") <(jq -S . <<< "$NEW") > /dev/null 2>&1; then
    success "settings.json already up to date."
    SETTINGS_CHANGED=0
else
    SETTINGS_CHANGED=1
    printf "\n  settings.json changes:\n\n" 
    diff <(jq -S '{permissions, statusLine}' "$SETTINGS") <(jq -S '{permissions, statusLine}' <<< "$NEW") \
        | sed 's/^/    /' || true
    printf "\n"
fi

STYLE_SRC="$SCRIPT_DIR/output-styles/oh-my-claudecode.md"
STYLE_DST="$TARGET_DIR/output-styles/oh-my-claudecode.md"
STYLE_ACTION="none"
if [[ $WITH_STYLE -eq 1 && -f "$STYLE_SRC" ]]; then
    if [[ $REVERT -eq 1 ]]; then
        [[ -f "$STYLE_DST" ]] && STYLE_ACTION="remove"
    elif [[ ! -f "$STYLE_DST" ]] || ! cmp -s "$STYLE_SRC" "$STYLE_DST"; then
        STYLE_ACTION="install"
    fi
fi
[[ "$STYLE_ACTION" == "install" ]] && info "Output style will be written to $STYLE_DST"
[[ "$STYLE_ACTION" == "remove"  ]] && info "Output style will be removed from $STYLE_DST"

SL_ACTION="none"
if [[ $WITH_STATUSLINE -eq 1 && -f "$STATUSLINE_SRC" ]]; then
    if [[ $REVERT -eq 1 ]]; then
        [[ -f "$STATUSLINE_DST" ]] && SL_ACTION="remove"
    elif [[ $SL_IS_FOREIGN -eq 1 ]]; then
        warn "settings.json already has a statusLine pointing at:"
        warn "  $EXISTING_SL"
        warn "Leaving it alone. Remove that setting first if you want ours."
    elif [[ ! -f "$STATUSLINE_DST" ]] || ! cmp -s "$STATUSLINE_SRC" "$STATUSLINE_DST"; then
        SL_ACTION="install"
    fi
fi
[[ "$SL_ACTION" == "install" ]] && info "Status line will be written to $STATUSLINE_DST"
[[ "$SL_ACTION" == "remove"  ]] && info "Status line will be removed from $STATUSLINE_DST"

if [[ $SETTINGS_CHANGED -eq 0 && "$STYLE_ACTION" == "none" && "$SL_ACTION" == "none" ]]; then
    printf "\n"; success "Nothing to do."; exit 0
fi

if [[ $DRY_RUN -eq 1 ]]; then
    info "Dry run — nothing was written."
    exit 0
fi

if [[ $ASSUME_YES -eq 0 ]]; then
    printf "  Apply? (y/N) "
    read -r confirm < /dev/tty
    [[ "$confirm" =~ ^[Yy]$ ]] || { info "Aborted."; exit 0; }
fi

if [[ $SETTINGS_CHANGED -eq 1 ]]; then
    BACKUP="${SETTINGS}.bak.$(date +%Y%m%d%H%M%S)"
    cp "$SETTINGS" "$BACKUP"
    printf '%s\n' "$NEW" > "$SETTINGS"
    success "Updated settings.json (backup: $(basename "$BACKUP"))"
fi

case "$STYLE_ACTION" in
    install) mkdir -p "$(dirname "$STYLE_DST")"; cp "$STYLE_SRC" "$STYLE_DST"
             success "Installed output style" ;;
    remove)  rm -f "$STYLE_DST"; success "Removed output style" ;;
esac

case "$SL_ACTION" in
    install) cp "$STATUSLINE_SRC" "$STATUSLINE_DST"; chmod +x "$STATUSLINE_DST"
             success "Installed status line" ;;
    remove)  rm -f "$STATUSLINE_DST"; success "Removed status line" ;;
esac

if [[ $REVERT -eq 0 ]]; then
    printf "\n  Next: select the style with ${CYAN}/config${RESET} -> Output style,\n"
    printf "  or run ${CYAN}claude --agent sisyphus${RESET}.\n\n"
fi
