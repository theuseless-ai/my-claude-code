#!/usr/bin/env bash
# Tests for install.sh --prune (and the ownership ledger it relies on).
#
#   ./tests/test-install-prune.sh
#
# Runs entirely inside a temp dir: a throwaway "upstream" repo, a clone of it,
# and a throwaway install target. Your real ~/.claude and ~/.oh-my-claudecode
# are never touched. Exits non-zero if any assertion fails.
#
# The install.sh under test is the WORKING TREE copy, not HEAD, so the suite
# covers uncommitted changes.

set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SB="$(mktemp -d "${TMPDIR:-/tmp}/omc-prune-test.XXXXXX")"
trap 'rm -rf "$SB"' EXIT

CLONE="$SB/clone"
TGT="$SB/target"
UPSTREAM="$SB/upstream"

# ---------------------------------------------------------------------------
# Assertions
# ---------------------------------------------------------------------------
PASS=0; FAIL=0
hr()   { printf '\n\033[1m== %s\033[0m\n' "$*"; }
ok()   { printf '  \033[32mPASS\033[0m %s\n' "$*"; PASS=$((PASS+1)); }
bad()  { printf '  \033[31mFAIL\033[0m %s\n' "$*"; FAIL=$((FAIL+1)); }
check(){ if eval "$2"; then ok "$1"; else bad "$1"; fi; }

# git in a sandbox repo, with an identity so commits work on any machine
sbgit() { local d="$1"; shift; git -C "$d" -c user.email=test@example.invalid -c user.name=omc-test "$@"; }

# ---------------------------------------------------------------------------
# Fixture
# ---------------------------------------------------------------------------
# Stand up a local "upstream" carrying the working-tree install.sh, then clone
# from it so the installer's `git pull --ff-only` works offline.
git clone -q "$REPO_ROOT" "$UPSTREAM"
cp "$REPO_ROOT/install.sh" "$UPSTREAM/install.sh"
sbgit "$UPSTREAM" commit -qam "test fixture: install.sh under test" || true
git clone -q "$UPSTREAM" "$CLONE"
rm -f "$CLONE"/.manifest*
mkdir -p "$TGT"

export OMC_CLONE_DIR="$CLONE"
RUN=(bash "$CLONE/install.sh")

# Per-target manifest naming mirrors install.sh's own slug rule.
SLUG=$(printf '%s' "$TGT" | sed 's#[^A-Za-z0-9]#_#g')
MAN="$CLONE/.manifest.$SLUG"
OWNED="$MAN.owned"

# Pick victims from the actual repo contents so the suite survives renames.
mapfile -t AGENTS < <(cd "$CLONE/.claude/agents" && ls ./*.md | sed 's#^\./##; s#\.md$##' | sort)
if [[ ${#AGENTS[@]} -lt 5 ]]; then
    echo "need at least 5 agents to run this suite, found ${#AGENTS[@]}" >&2
    exit 1
fi
V1="${AGENTS[0]}"; V2="${AGENTS[1]}"; V3="${AGENTS[2]}"; V4="${AGENTS[3]}"
KEEP="${AGENTS[${#AGENTS[@]}-1]}"
SKILL=$(cd "$CLONE/.claude/skills" && ls -d ./*/ | head -1 | sed 's#^\./##; s#/$##')
AGENT_TOTAL=${#AGENTS[@]}

printf 'repo:    %s\nsandbox: %s\nvictims: %s, %s, %s, %s (keeping %s), skill: %s\n' \
    "$REPO_ROOT" "$SB" "$V1" "$V2" "$V3" "$V4" "$KEEP" "$SKILL"

# ---------------------------------------------------------------------------
hr "prune refuses when there is no install record"
"${RUN[@]}" --prune --target "$TGT" > "$SB/o1" 2>&1; rc=$?
check "exits non-zero" "[[ $rc -ne 0 ]]"
check "explains why" "grep -q 'No install record at' '$SB/o1'"

hr "dry-run on a pre-ledger install writes nothing"
# Simulate an install made before the ledger existed: manifest only.
mkdir -p "$TGT/agents"; cp "$CLONE/.claude/agents/$KEEP.md" "$TGT/agents/$KEEP.md"
printf '%s\n' "$TGT/agents/$KEEP.md" "$TGT/agents/long-gone.md" > "$MAN"
"${RUN[@]}" --prune --dry-run --target "$TGT" > "$SB/o1b" 2>&1
check "no ledger file created by dry-run" "[[ ! -f '$OWNED' ]]"
check "manifest untouched by dry-run" "[[ \$(wc -l < '$MAN') -eq 2 ]]"
rm -rf "$TGT" "$MAN"; mkdir -p "$TGT"

hr "install populates manifest and ledger"
: > "$MAN"
"${RUN[@]}" --prune --yes --target "$TGT" > "$SB/o2" 2>&1
check "nothing to prune on an in-sync target" "grep -q 'Nothing to prune' '$SB/o2'"
check "prune did not rewrite the manifest" "[[ ! -s '$MAN' ]]"
"${RUN[@]}" --update --target "$TGT" > "$SB/o2b" 2>&1
check "update installed every agent" "[[ \$(ls '$TGT/agents' | wc -l) -eq $AGENT_TOTAL ]]"
check "manifest is non-empty" "[[ -s '$MAN' ]]"
check "ledger was created" "[[ -s '$OWNED' ]]"
cp "$TGT/agents/$V1.md" "$SB/$V1.orig"

hr "dry-run lists orphans, removes nothing, mutates nothing"
sbgit "$CLONE" rm -q ".claude/agents/$V1.md"
sbgit "$CLONE" rm -rq ".claude/skills/$SKILL"
sbgit "$CLONE" rm -q ".mcp.json"                  # protected: must NOT be pruned
sbgit "$CLONE" commit -qm "simulate upstream deletions"
echo "/etc/passwd" >> "$MAN"                      # outside target: must be ignored
echo "$TGT/agents/never-existed.md" >> "$MAN"     # already gone: must be ignored
MAN_SUM=$(md5sum < "$MAN"); OWNED_SUM=$(md5sum < "$OWNED")
"${RUN[@]}" --prune --dry-run --target "$TGT" > "$SB/o4" 2>&1
check "reports the orphaned agent" "grep -q 'agents/$V1.md' '$SB/o4'"
check "reports the orphaned skill" "grep -q 'skills/$SKILL' '$SB/o4'"
check "orphaned agent still on disk" "[[ -f '$TGT/agents/$V1.md' ]]"
check "orphaned skill still on disk" "[[ -d '$TGT/skills/$SKILL' ]]"
check "manifest byte-identical" "[[ \"\$(md5sum < '$MAN')\" == '$MAN_SUM' ]]"
check "ledger byte-identical" "[[ \"\$(md5sum < '$OWNED')\" == '$OWNED_SUM' ]]"
check "no backup dir created" "! compgen -G '$CLONE/.pruned.*' > /dev/null"

hr "prune removes orphans and backs them up"
"${RUN[@]}" --prune --yes --target "$TGT" > "$SB/o5" 2>&1
check "orphaned agent removed" "[[ ! -f '$TGT/agents/$V1.md' ]]"
check "emptied skill dir collapsed" "[[ ! -d '$TGT/skills/$SKILL' ]]"
check ".mcp.json preserved (protected)" "[[ -f '$TGT/.mcp.json' ]]"
check "path outside target ignored" "[[ -f /etc/passwd ]]"
check "missing path ignored without error" "! grep -q 'Could not remove' '$SB/o5'"
BK=$(compgen -G "$CLONE/.pruned.*" | head -1)
check "backup holds the pruned agent" "[[ -f '$BK/agents/$V1.md' ]]"
check "backup content matches original" "cmp -s '$BK/agents/$V1.md' '$SB/$V1.orig'"
check "manifest no longer lists it" "! grep -q 'agents/$V1.md' '$MAN'"
check "ledger no longer lists it" "! grep -q 'agents/$V1.md' '$OWNED'"
check "manifest still lists a kept agent" "grep -q 'agents/$KEEP.md' '$MAN'"

hr "prune is idempotent"
"${RUN[@]}" --prune --yes --target "$TGT" > "$SB/o6" 2>&1
check "second run finds nothing" "grep -q 'Nothing to prune' '$SB/o6'"

hr "plain update warns but never deletes"
sbgit "$CLONE" rm -q ".claude/agents/$V2.md"
sbgit "$CLONE" commit -qm "drop $V2"
"${RUN[@]}" --update --target "$TGT" > "$SB/o7" 2>&1
check "warns about unshipped files" "grep -q 'no longer shipped by the repo' '$SB/o7'"
check "did not delete anything" "[[ -f '$TGT/agents/$V2.md' ]]"

hr "update --prune removes in one pass"
"${RUN[@]}" --update --prune --yes --target "$TGT" > "$SB/o8" 2>&1
check "pruned during update" "grep -q 'Pruned 1 file' '$SB/o8'"
check "orphan removed" "[[ ! -f '$TGT/agents/$V2.md' ]]"
check "settings.json intact" "[[ -s '$TGT/settings.json' ]]"

hr "orphan record survives repeated updates (ledger, not manifest diff)"
sbgit "$CLONE" rm -q ".claude/agents/$V3.md"
sbgit "$CLONE" commit -qm "drop $V3"
for _ in 1 2 3; do "${RUN[@]}" --update --target "$TGT" > "$SB/o9" 2>&1; done
check "still warns on the 3rd consecutive update" "grep -q 'no longer shipped' '$SB/o9'"
check "orphan never auto-deleted" "[[ -f '$TGT/agents/$V3.md' ]]"
"${RUN[@]}" --prune --yes --target "$TGT" > "$SB/o9b" 2>&1
check "prune still finds it after 3 updates" "grep -q 'Pruned 1 file' '$SB/o9b'"
check "orphan finally removed" "[[ ! -f '$TGT/agents/$V3.md' ]]"

hr "user's own files are never pruned"
cp "$TGT/agents/$KEEP.md" "$TGT/agents/my-custom-agent.md"
"${RUN[@]}" --prune --yes --target "$TGT" > "$SB/o10" 2>&1
check "user agent survives" "[[ -f '$TGT/agents/my-custom-agent.md' ]]"
check "reports nothing to prune" "grep -q 'Nothing to prune' '$SB/o10'"

hr "invalid flag combinations are rejected"
for combo in "--dry-run" "--clean --prune" "--uninstall --prune"; do
    # shellcheck disable=SC2086
    "${RUN[@]}" $combo --target "$TGT" > "$SB/o11" 2>&1; rc=$?
    check "'$combo' rejected" "[[ $rc -ne 0 ]]"
done

hr "help documents the mode"
"${RUN[@]}" --help --target "$TGT" > "$SB/o12" 2>&1
check "--help lists --prune" "grep -q '\\-\\-prune ' '$SB/o12'"
check "--help lists --dry-run" "grep -q 'dry-run' '$SB/o12'"

hr "no temp files leaked"
check "no scratch lists left behind" "! compgen -G '${TMPDIR:-/tmp}/omc-owned.*' > /dev/null && ! compgen -G '${TMPDIR:-/tmp}/omc-expected.*' > /dev/null"

# Runs last: --uninstall deletes the clone, taking install.sh with it.
hr "uninstall clears previously-orphaned files too"
sbgit "$CLONE" rm -q ".claude/agents/$V4.md"
sbgit "$CLONE" commit -qm "drop $V4"
"${RUN[@]}" --update --target "$TGT" > "$SB/o13" 2>&1
check "orphan present before uninstall" "[[ -f '$TGT/agents/$V4.md' ]]"
if command -v script > /dev/null; then
    # --uninstall confirms via /dev/tty, so give it a pty.
    script -qec "bash $CLONE/install.sh --uninstall --target $TGT" /dev/null <<< "y" > "$SB/o14" 2>&1 || true
    check "orphan removed by uninstall" "[[ ! -f '$TGT/agents/$V4.md' ]]"
    check "normal installed agent removed" "[[ ! -f '$TGT/agents/$KEEP.md' ]]"
    check "user's own agent left alone" "[[ -f '$TGT/agents/my-custom-agent.md' ]]"
    check "settings.json preserved" "[[ -s '$TGT/settings.json' ]]"
else
    printf '  \033[33mSKIP\033[0m uninstall test (no `script` available for a pty)\n'
fi

# ---------------------------------------------------------------------------
printf '\n\033[1m%s passed, %s failed\033[0m\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
