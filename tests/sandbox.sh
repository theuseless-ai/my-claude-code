#!/usr/bin/env bash
#
# Launch a throwaway Claude Code session with this working tree loaded as a
# plugin, using a disposable config directory.
#
# Nothing in your real ~/.claude is read or written: CLAUDE_CONFIG_DIR points
# elsewhere for the whole session. That matters here because a pre-2.0 install
# in ~/.claude would shadow the plugin and give you a misleading result.
#
#   ./tests/sandbox.sh                  # interactive session
#   ./tests/sandbox.sh --configure      # also run configure.sh against the sandbox
#   ./tests/sandbox.sh --agent sisyphus # start with the orchestrator active
#   ./tests/sandbox.sh -p "some prompt" # one-shot, non-interactive
#   ./tests/sandbox.sh --keep           # do not delete the sandbox on exit
#
# Anything after the recognised flags is passed straight through to `claude`.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/omc-sandbox.XXXXXX")"
KEEP=0
RUN_CONFIGURE=0
PASSTHRU=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --keep)      KEEP=1; shift ;;
        --configure) RUN_CONFIGURE=1; shift ;;
        *)           PASSTHRU+=("$1"); shift ;;
    esac
done

cleanup() {
    if [[ $KEEP -eq 1 ]]; then
        printf '\n  Sandbox kept at: %s\n' "$SANDBOX"
    else
        rm -rf "$SANDBOX"
    fi
}
trap cleanup EXIT

mkdir -p "$SANDBOX/wd"
printf '%s\n' '{}' > "$SANDBOX/settings.json"

# Reuse your existing login without exposing the rest of your config.
if [[ -f "$HOME/.claude/.credentials.json" ]]; then
    cp "$HOME/.claude/.credentials.json" "$SANDBOX/.credentials.json"
    chmod 600 "$SANDBOX/.credentials.json"
else
    printf '  [warn] No ~/.claude/.credentials.json found; you may be asked to log in.\n' >&2
fi

if [[ $RUN_CONFIGURE -eq 1 ]]; then
    "$REPO/configure.sh" --yes --target "$SANDBOX"
    # The plugin ships the output style (loaded via --plugin-dir); select it here.
    tmp=$(mktemp)
    jq '.outputStyle = "oh-my-claudecode"' "$SANDBOX/settings.json" > "$tmp"
    mv "$tmp" "$SANDBOX/settings.json"
fi

cat <<BANNER

  Sandbox config : $SANDBOX
  Working dir    : $SANDBOX/wd
  Plugin         : $REPO (loaded via --plugin-dir)
  Real ~/.claude : untouched

  Try inside the session:
    /plugin                     plugin loaded, no errors
    /context                    13 custom agents, hooks registered
    /config                     Output style lists oh-my-claudecode
    @oracle summarise this repo agent answers, cannot write
    /oh-my-claudecode:git-master  a namespaced skill

BANNER

cd "$SANDBOX/wd"
# Not `exec`: that replaces this shell and the EXIT trap never runs, leaking the
# sandbox directory. Run claude as a child and preserve its exit status.
set +e
CLAUDE_CONFIG_DIR="$SANDBOX" claude --plugin-dir "$REPO" "${PASSTHRU[@]}"
rc=$?
set -e
exit $rc
