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
# Every skill named in an agent's `skills:` list must exist and must be
# model-invocable — disable-model-invocation blocks subagent preloading.
preloaded_skills_resolve() {
    local f sk
    for f in agents/*.md; do
        while read -r sk; do
            [[ -n "$sk" ]] || continue
            [[ -f "skills/$sk/SKILL.md" ]] || return 1
            grep -q '^disable-model-invocation: true' "skills/$sk/SKILL.md" && return 1
        done < <(awk '/^skills:/{p=1;next} /^[a-zA-Z]/{p=0} p&&/^  - /{print $2}' "$f")
    done
    return 0
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

hr "agent capability fields"
# Read-only consultants declare no Write/Edit AND run in plan mode, so the
# restriction is enforced by the harness rather than only by prose.
for n in oracle momus metis explore librarian multimodal-looker; do
    f="agents/$n.md"
    check "$n: permissionMode plan"        "grep -q '^permissionMode: plan$' '$f'"
    check "$n: no Write in tools"          "! grep -qE '^  - (Write|Edit)\$' <<< \"\$(awk '/^---\$/{k++;next} k==1' '$f')\""
done
# prometheus writes plans, so it must NOT be in plan mode.
check "prometheus not in plan mode"        "! grep -q '^permissionMode: plan$' agents/prometheus.md"
check "prometheus can write"               "grep -q '^  - Write\$' <<< \"\$(awk '/^---\$/{k++;next} k==1' agents/prometheus.md)\""

# argus runs an autonomous loop; it must stay bounded.
check "argus declares maxTurns"            "grep -qE '^maxTurns: [0-9]+$' agents/argus.md"

# Preloaded skills must exist and must be model-invocable — a skill marked
# disable-model-invocation cannot be preloaded into a subagent.
check "every preloaded skill resolves" "preloaded_skills_resolve"

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
out=$(echo '{"tool_name":"Bash","tool_input":{"command":"python3"}}' | bash hooks/non-interactive-env.sh)
check "non-interactive denies a bare REPL"   "jq -e '$DENY' <<< '$out'"
# Regression: an unbounded alternation made `vi` match "via", `top` match
# "topic", `more` match "moreover" — ordinary prose in a heredoc tripped the guard.
for word in "via the plugin dir" "topic: something" "moreover this is fine" \
            "vital-check --run" "topology list" "python3 script.py"; do
    out=$(echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$word\"}}" \
          | bash hooks/non-interactive-env.sh)
    check "non-interactive allows '$word'"   "[[ -z '$out' ]]"
done

mkdir -p "$SB/proj/.sisyphus/plans" && touch "$SB/proj/.sisyphus/plans/p.md"
out=$(cd "$SB/proj" && echo '{}' | bash "$ROOT/hooks/context-preserver.sh")
check "context-preserver reports a plan" \
      "jq -e '.hookSpecificOutput.additionalContext | test(\"p.md\")' <<< '$out'"
out=$(cd "$SB" && echo '{}' | bash "$ROOT/hooks/context-preserver.sh")
check "context-preserver silent with no state" "[[ -z '$out' ]]"

hr "configure.sh — the two things a plugin cannot ship"
CFG="$SB/cfg"; mkdir -p "$CFG"
check "configure.sh parses"       "bash -n configure.sh"
check "configure.sh executable"   "[[ -x configure.sh ]]"

# Must never install plugin-owned components — a second copy in ~/.claude
# shadows the plugin. That was the pre-2.0 bug.
check "does not copy agents/skills/hooks" "
  ./configure.sh --yes --target '$CFG' > /dev/null &&
  [[ ! -d '$CFG/agents' && ! -d '$CFG/skills' && ! -d '$CFG/hooks' ]]"
check "writes permissions"        "jq -e '.permissions.allow | index(\"Bash(gh *)\")' '$CFG/settings.json'"
check "writes the output style"   "[[ -f '$CFG/output-styles/oh-my-claudecode.md' ]]"
check "style matches the repo copy" \
      "cmp -s output-styles/oh-my-claudecode.md '$CFG/output-styles/oh-my-claudecode.md'"

check "idempotent" "
  a=\$(md5sum < '$CFG/settings.json') &&
  ./configure.sh --yes --target '$CFG' > /dev/null &&
  b=\$(md5sum < '$CFG/settings.json') &&
  [[ \"\$a\" == \"\$b\" ]]"

# Pre-existing user config must survive both apply and revert.
CFG2="$SB/cfg2"; mkdir -p "$CFG2"
printf '%s' '{"theme":"dark","permissions":{"allow":["Bash(terraform *)"]}}' > "$CFG2/settings.json"
check "preserves the user's own rules" "
  ./configure.sh --yes --target '$CFG2' > /dev/null &&
  jq -e '.permissions.allow | index(\"Bash(terraform *)\")' '$CFG2/settings.json' &&
  [[ \$(jq -r .theme '$CFG2/settings.json') == dark ]]"
check "revert removes only ours" "
  ./configure.sh --revert --yes --target '$CFG2' > /dev/null &&
  jq -e '.permissions.allow | index(\"Bash(terraform *)\")' '$CFG2/settings.json' &&
  [[ \$(jq -r '.permissions.allow | index(\"Bash(gh *)\") // \"gone\"' '$CFG2/settings.json') == gone ]] &&
  [[ \$(jq -r .theme '$CFG2/settings.json') == dark ]]"

# The teams warning must fire even when there is nothing else to change.
CFG3="$SB/cfg3"; mkdir -p "$CFG3"
printf '%s' '{"env":{"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS":"1"}}' > "$CFG3/settings.json"
check "warns about agent teams on a no-op run" "
  ./configure.sh --yes --target '$CFG3' > /dev/null 2>&1 &&
  out=\$(./configure.sh --yes --target '$CFG3' 2>&1) &&
  grep -q 'EXPERIMENTAL_AGENT_TEAMS' <<< \"\$out\""

check "dry-run writes nothing" "
  rm -rf '$SB/cfg4' && mkdir -p '$SB/cfg4' &&
  ./configure.sh --dry-run --target '$SB/cfg4' > /dev/null &&
  ! jq -e '.permissions' '$SB/cfg4/settings.json' > /dev/null 2>&1 &&
  [[ ! -d '$SB/cfg4/output-styles' ]]"

hr "legacy uninstaller"
check "uninstall-legacy.sh parses"        "bash -n uninstall-legacy.sh"
check "uninstall-legacy.sh executable"    "[[ -x uninstall-legacy.sh ]]"
check "no-op when no legacy install"      "out=\$(OMC_CLONE_DIR='$SB/absent' bash uninstall-legacy.sh --yes) && grep -q 'No legacy install' <<< \"\$out\""
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
