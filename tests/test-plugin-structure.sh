#!/usr/bin/env bash
#
# Validates the plugin layout: manifests parse, every component sits where
# Claude Code looks for it, frontmatter uses the fields the harness reads, and
# the hooks emit the current JSON contract.
#
# Plain bash, no framework. Touches nothing outside a temp sandbox.

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
ROOT=$(pwd)

PASS=0; FAIL=0
check() {
    if eval "$2" > /dev/null 2>&1; then
        printf '  \033[32mPASS\033[0m %s\n' "$1"; PASS=$((PASS+1))
    else
        printf '  \033[31mFAIL\033[0m %s\n' "$1"; FAIL=$((FAIL+1))
    fi
}
hr() { printf '\n\033[1m== %s\033[0m\n' "$1"; }

command -v jq > /dev/null || { echo "jq required"; exit 1; }

hr "plugin manifests"
check "plugin.json exists"                "[[ -f .claude-plugin/plugin.json ]]"
check "plugin.json is valid JSON"         "jq empty .claude-plugin/plugin.json"
check "plugin.json declares a name"       "[[ -n \$(jq -r '.name // empty' .claude-plugin/plugin.json) ]]"
check "plugin.json declares a version"    "[[ -n \$(jq -r '.version // empty' .claude-plugin/plugin.json) ]]"
check "marketplace.json is valid JSON"    "jq empty .claude-plugin/marketplace.json"
check "marketplace lists the plugin"      "[[ \$(jq -r '.plugins[0].name' .claude-plugin/marketplace.json) == 'oh-my-claudecode' ]]"

hr "component directories are at the plugin root"
for d in agents skills hooks output-styles scripts; do
    check "$d/ at root"                   "[[ -d '$d' ]]"
done
check "nothing shipped under .claude-plugin/ but the manifests" \
      "[[ \$(find .claude-plugin -type f | wc -l) -eq 2 ]]"
check "no legacy .claude/ component dirs" \
      "[[ ! -d .claude/agents && ! -d .claude/skills && ! -d .claude/hooks ]]"

hr "agent frontmatter"
AGENTS=$(find agents -name '*.md' | sort)
check "agents present"                    "[[ -n '$AGENTS' ]]"
for f in $AGENTS; do
    n=$(basename "$f" .md)
    check "$n: uses tools: not allowed-tools:" "! grep -q '^allowed-tools:' '$f'"
    check "$n: declares name"                  "grep -q '^name: ' '$f'"
    check "$n: declares description"           "grep -q '^description: ' '$f'"
    check "$n: declares model"                 "grep -q '^model: ' '$f'"
done

hr "skill frontmatter"
for f in $(find skills -name 'SKILL.md' | sort); do
    n=$(basename "$(dirname "$f")")
    check "$n: declares name"                  "grep -q '^name: ' '$f'"
    check "$n: declares description"           "grep -q '^description: ' '$f'"
    # allowed-tools GRANTS permission, so a bare tool name is a blanket grant.
    check "$n: no blanket Bash grant"          "! grep -qE '^allowed-tools:.*(^| )Bash( |$)' '$f'"
    check "$n: no hardcoded \$HOME paths"      "! grep -q '\\\$HOME/\\.claude' '$f'"
done

hr "hooks"
check "hooks.json is valid JSON"          "jq empty hooks/hooks.json"
check "no PreCompact context injection"   "! jq -e '.hooks.PreCompact' hooks/hooks.json"
check "context-preserver runs on SessionStart" \
      "jq -e '.hooks.SessionStart[0].hooks[0].command | test(\"context-preserver\")' hooks/hooks.json"
check "hook commands use CLAUDE_PLUGIN_ROOT" \
      "[[ \$(jq -r '[.hooks[][] .hooks[].command] | map(select(test(\"CLAUDE_PLUGIN_ROOT\"))) | length' hooks/hooks.json) -eq \$(jq -r '[.hooks[][] .hooks[].command] | length' hooks/hooks.json) ]]"
for f in hooks/*.sh; do
    check "$(basename "$f"): parses"      "bash -n '$f'"
    check "$(basename "$f"): executable"  "[[ -x '$f' ]]"
    check "$(basename "$f"): no legacy decision:block" \
          "! grep -q '\"decision\"' '$f'"
done
check "every hooks.json command exists on disk" \
      "jq -r '[.hooks[][] .hooks[].command] | .[]' hooks/hooks.json | sed 's|.*/hooks/||; s|\\\"$||' | while read -r s; do [[ -f \"hooks/\$s\" ]] || exit 1; done"

hr "hook behaviour"
SB=$(mktemp -d); trap 'rm -rf "$SB"' EXIT
DENY='.hookSpecificOutput.permissionDecision == "deny"'

out=$(echo '{"tool_name":"Write","tool_input":{"file_path":"'"$ROOT"'/README.md"}}' | bash hooks/write-existing-file-guard.sh)
check "write-guard denies an existing file"  "jq -e '$DENY' <<< '$out'"
out=$(echo '{"tool_name":"Write","tool_input":{"file_path":"'"$SB"'/new.txt"}}' | bash hooks/write-existing-file-guard.sh)
check "write-guard allows a new file"        "[[ -z '$out' ]]"
out=$(echo '{"tool_name":"Edit","tool_input":{"file_path":"'"$ROOT"'/README.md"}}' | bash hooks/write-existing-file-guard.sh)
check "write-guard ignores Edit"             "[[ -z '$out' ]]"

out=$(echo '{"tool_name":"Bash","tool_input":{"command":"vim x"}}' | bash hooks/non-interactive-env.sh)
check "non-interactive denies vim"           "jq -e '$DENY' <<< '$out'"
out=$(echo '{"tool_name":"Bash","tool_input":{"command":"git log --oneline"}}' | bash hooks/non-interactive-env.sh)
check "non-interactive allows git log"       "[[ -z '$out' ]]"

mkdir -p "$SB/proj/.sisyphus/plans" && touch "$SB/proj/.sisyphus/plans/p.md"
out=$(cd "$SB/proj" && echo '{}' | bash "$ROOT/hooks/context-preserver.sh")
check "context-preserver reports a plan" \
      "jq -e '.hookSpecificOutput.additionalContext | test(\"p.md\")' <<< '$out'"
out=$(cd "$SB" && echo '{}' | bash "$ROOT/hooks/context-preserver.sh")
check "context-preserver silent with no state" "[[ -z '$out' ]]"

hr "legacy uninstaller"
check "uninstall-legacy.sh parses"        "bash -n uninstall-legacy.sh"
check "uninstall-legacy.sh executable"    "[[ -x uninstall-legacy.sh ]]"
check "no-op when no legacy install"      "OMC_CLONE_DIR='$SB/absent' bash uninstall-legacy.sh --yes | grep -q 'No legacy install'"
check "dry-run removes nothing" "
  mkdir -p '$SB/tgt/agents' '$SB/clone' &&
  touch '$SB/tgt/agents/x.md' '$SB/tgt/settings.json' &&
  printf '%s\n' '$SB/tgt/agents/x.md' '$SB/tgt/settings.json' > '$SB/clone/.manifest.$(printf '%s' "$SB/tgt" | sed 's#[^A-Za-z0-9]#_#g')' &&
  OMC_CLONE_DIR='$SB/clone' bash uninstall-legacy.sh --dry-run --target '$SB/tgt' > /dev/null &&
  [[ -f '$SB/tgt/agents/x.md' ]]"
check "removes owned files but keeps settings.json" "
  OMC_CLONE_DIR='$SB/clone' bash uninstall-legacy.sh --yes --target '$SB/tgt' > /dev/null &&
  [[ ! -f '$SB/tgt/agents/x.md' ]] && [[ -f '$SB/tgt/settings.json' ]]"

printf '\n\033[1m%s passed, %s failed\033[0m\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
