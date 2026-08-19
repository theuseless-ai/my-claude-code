#!/usr/bin/env bash
#
# oh-my-claudecode — legacy uninstaller
#
# Versions before 2.0.0 shipped via `curl | bash`, copying agents, skills, hooks,
# a statusline and a CLAUDE.md into ~/.claude and merging entries into your
# settings.json. 2.0.0 is a Claude Code plugin, so none of that is needed any
# more — but the old files are still sitting in your config directory, and
# Claude Code will keep loading them alongside the plugin.
#
# This script removes only what the old installer put there. It reads the
# manifest and ownership ledger the old installer wrote, so files you added
# yourself are never touched.
#
#   ./uninstall-legacy.sh              # remove legacy files (asks first)
#   ./uninstall-legacy.sh --dry-run    # list what would go, remove nothing
#   ./uninstall-legacy.sh --yes        # skip the confirmation prompt
#   ./uninstall-legacy.sh --target DIR # a non-default config dir
#
# Then install the plugin:
#   /plugin marketplace add theuseless-ai/my-claude-code
#   /plugin install oh-my-claudecode@oh-my-claudecode

set -euo pipefail

GREEN='\033[32m'; YELLOW='\033[33m'; RED='\033[31m'; CYAN='\033[36m'
BOLD='\033[1m'; RESET='\033[0m'

info()    { printf "  ${CYAN}[info]${RESET} %s\n" "$*"; }
success() { printf "  ${GREEN}[ok]${RESET}   %s\n" "$*"; }
warn()    { printf "  ${YELLOW}[warn]${RESET} %s\n" "$*"; }
error()   { printf "  ${RED}[err]${RESET}  %s\n" "$*" >&2; }

CLONE_DIR="${OMC_CLONE_DIR:-$HOME/.oh-my-claudecode}"
TARGET_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

# Never delete files the old installer merged into rather than owned outright.
PROTECTED_BASENAMES=".mcp.json settings.json settings.local.json"

DRY_RUN=0
ASSUME_YES=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --yes|-y)  ASSUME_YES=1; shift ;;
        --target)  TARGET_DIR="${2:?--target needs a directory}"; shift 2 ;;
        -h|--help) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) error "Unknown option: $1"; exit 2 ;;
    esac
done

TARGET_DIR="${TARGET_DIR%/}"

# The old installer kept one manifest per non-default target.
slug() { printf '%s' "$1" | sed 's#[^A-Za-z0-9]#_#g'; }
if [[ "$TARGET_DIR" == "$HOME/.claude" ]]; then
    MANIFEST_FILE="$CLONE_DIR/.manifest"
else
    MANIFEST_FILE="$CLONE_DIR/.manifest.$(slug "$TARGET_DIR")"
fi
OWNED_FILE="${MANIFEST_FILE}.owned"

printf "\n${BOLD}oh-my-claudecode — legacy uninstall${RESET}\n\n"
info "Config directory: $TARGET_DIR"

if [[ ! -f "$MANIFEST_FILE" && ! -f "$OWNED_FILE" ]]; then
    success "No legacy install found — nothing to remove."
    printf "\n  Install the plugin with:\n"
    printf "    ${CYAN}/plugin marketplace add theuseless-ai/my-claude-code${RESET}\n"
    printf "    ${CYAN}/plugin install oh-my-claudecode@oh-my-claudecode${RESET}\n\n"
    exit 0
fi

# Build the candidate list: manifest + ledger, inside the target, still present,
# and not a protected basename.
CANDIDATES=$(mktemp "${TMPDIR:-/tmp}/omc-legacy.XXXXXX")
trap 'rm -f "$CANDIDATES"' EXIT

{
    # A missing file must not fail the pipeline: `[[ -f ]] && cat` would return 1
    # as the last command, and with `set -e -o pipefail` that kills the script.
    [[ -f "$MANIFEST_FILE" ]] && cat "$MANIFEST_FILE"
    [[ -f "$OWNED_FILE" ]] && cat "$OWNED_FILE"
    :
} | LC_ALL=C sort -u | while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    [[ "$path" == "$TARGET_DIR"/* ]] || continue
    [[ -f "$path" ]] || continue
    base=$(basename "$path")
    case " $PROTECTED_BASENAMES " in
        *" $base "*) continue ;;
    esac
    printf '%s\n' "$path"
done > "$CANDIDATES"

COUNT=$(wc -l < "$CANDIDATES" | tr -d ' ')

if [[ "$COUNT" -eq 0 ]]; then
    success "Nothing left to remove."
    exit 0
fi

printf "\n  These %s file(s) were installed by the legacy installer:\n\n" "$COUNT"
sed 's|^|    |' "$CANDIDATES"
printf "\n"

if [[ $DRY_RUN -eq 1 ]]; then
    info "Dry run — nothing was removed."
    exit 0
fi

if [[ $ASSUME_YES -eq 0 ]]; then
    printf "  Remove them? Your settings.json is left untouched. (y/N) "
    read -r confirm < /dev/tty
    [[ "$confirm" =~ ^[Yy]$ ]] || { info "Aborted."; exit 0; }
fi

REMOVED=0
while IFS= read -r path; do
    rm -f "$path" && REMOVED=$((REMOVED + 1))
done < "$CANDIDATES"

# Collapse directories the removals emptied out.
for d in "$TARGET_DIR/agents" "$TARGET_DIR/hooks" "$TARGET_DIR/scripts" \
         "$TARGET_DIR/output-styles" "$TARGET_DIR/skills"; do
    [[ -d "$d" ]] || continue
    find "$d" -type d -empty -delete 2>/dev/null || true
done

rm -f "$MANIFEST_FILE" "$OWNED_FILE"
success "Removed $REMOVED file(s)."

printf "\n  ${YELLOW}settings.json was left intact${RESET} — the legacy installer merged into it.\n"
printf "  You may want to remove its oh-my-claudecode entries by hand:\n"
printf "    - hooks pointing at %s/hooks/\n" "$TARGET_DIR"
printf "    - \"statusLine\" pointing at %s/statusline.sh\n" "$TARGET_DIR"
printf "    - \"outputStyle\": \"oh-my-claudecode\" (keep this if you still want the style)\n"
printf "\n  Then install the plugin:\n"
printf "    ${CYAN}/plugin marketplace add theuseless-ai/my-claude-code${RESET}\n"
printf "    ${CYAN}/plugin install oh-my-claudecode@oh-my-claudecode${RESET}\n\n"
