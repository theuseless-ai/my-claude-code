#!/usr/bin/env bash
# oh-my-claudecode installer
# Multi-Agent Orchestration System for Claude Code
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/theuseless-ai/my-claude-code/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/theuseless-ai/my-claude-code/main/install.sh | bash -s -- --update
#   curl -fsSL https://raw.githubusercontent.com/theuseless-ai/my-claude-code/main/install.sh | bash -s -- --prune
#   curl -fsSL https://raw.githubusercontent.com/theuseless-ai/my-claude-code/main/install.sh | bash -s -- --uninstall
#   curl -fsSL https://raw.githubusercontent.com/theuseless-ai/my-claude-code/main/install.sh | bash -s -- --clean

set -euo pipefail

# ---------------------------------------------------------------------------
# Colors (basic ANSI for max compatibility)
# ---------------------------------------------------------------------------
BOLD_YELLOW='\033[1;33m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
CYAN='\033[36m'
BOLD='\033[1m'
RESET='\033[0m'

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
REPO_URL="https://github.com/theuseless-ai/my-claude-code.git"
CLONE_DIR="${OMC_CLONE_DIR:-$HOME/.oh-my-claudecode}"
# Where agents/hooks/skills/etc. get installed. Precedence (low -> high):
#   ~/.claude  <  $CLAUDE_CONFIG_DIR  <  --target <dir>
# The --target flag is applied later in main(); CLAUDE_CONFIG_DIR is the same
# env var Claude Code itself honours, so alias'd configs "just work".
DEFAULT_TARGET_DIR="$HOME/.claude"
TARGET_DIR="${CLAUDE_CONFIG_DIR:-$DEFAULT_TARGET_DIR}"
# MANIFEST_FILE is recomputed per-target in main() when the target is non-default,
# so installs to different dirs don't clobber each other's manifest.
MANIFEST_FILE="$CLONE_DIR/.manifest"
# Cumulative ledger of every path we have EVER installed for this target.
# The manifest only describes the latest install, and copy_files() overwrites
# it — so it cannot answer "what did we install that the repo has since
# dropped?". The ledger can, and it survives any number of updates.
OWNED_FILE="${MANIFEST_FILE}.owned"
SOURCE_CLAUDE_DIR="$CLONE_DIR/.claude"

# ---------------------------------------------------------------------------
# Mode flags (set in main())
# ---------------------------------------------------------------------------
PRUNE=0
DRY_RUN=0
ASSUME_YES=0
# Scratch list of what an install would currently produce (--prune).
EXPECTED_LIST=""
# Scratch ledger seed, used only so --dry-run writes nothing at all.
SEED_LIST=""
# Files we install but never prune: they are merged with (or wholly owned by)
# the user's own config, so deleting them would take user data with them.
PROTECTED_BASENAMES=".mcp.json settings.json settings.local.json"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
info()    { printf "  ${CYAN}[info]${RESET} %s\n" "$*"; }
success() { printf "  ${GREEN}[ok]${RESET}   %s\n" "$*"; }
warn()    { printf "  ${YELLOW}[warn]${RESET} %s\n" "$*"; }
error()   { printf "  ${RED}[err]${RESET}  %s\n" "$*" >&2; }

banner() {
    printf "${BOLD_YELLOW}"
    cat <<'BANNER'
 ╔═══════════════════════════════════════════╗
 ║         oh-my-claudecode                  ║
 ║   Multi-Agent Orchestration System        ║
 ╚═══════════════════════════════════════════╝
BANNER
    printf "${RESET}\n"
}

get_timestamp() {
    date +%s
}

# Cleanup trap — report failure on non-zero exit
cleanup() {
    local exit_code=$?
    [[ -n "$EXPECTED_LIST" ]] && rm -f "$EXPECTED_LIST"
    [[ -n "$SEED_LIST" ]] && rm -f "$SEED_LIST"
    if [[ $exit_code -ne 0 && $exit_code -ne 130 ]]; then
        error "Installation failed (exit code $exit_code)."
    fi
}
trap cleanup EXIT

# Handle interrupt
on_interrupt() {
    printf "\n"
    error "Interrupted."
    exit 130
}
trap on_interrupt INT TERM

# ---------------------------------------------------------------------------
# Prerequisite checks
# ---------------------------------------------------------------------------
check_prerequisites() {
    local missing=0

    if ! command -v git &>/dev/null; then
        error "'git' is required but not installed."
        printf "    Install git from: https://git-scm.com/downloads\n"
        missing=1
    fi

    if ! command -v jq &>/dev/null; then
        error "'jq' is required but not installed."
        printf "\n"
        printf "    Install jq:\n"
        printf "      macOS:    brew install jq\n"
        printf "      Ubuntu:   sudo apt install jq\n"
        printf "      Arch:     sudo pacman -S jq\n"
        printf "      Fedora:   sudo dnf install jq\n"
        printf "\n"
        missing=1
    fi

    if [[ $missing -ne 0 ]]; then
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# settings.json deep merge
# ---------------------------------------------------------------------------
merge_settings() {
    local source_file="$1"
    local target_file="$2"

    if [[ ! -f "$source_file" ]]; then
        warn "No settings.json in source repo, skipping."
        return
    fi

    # No existing settings — just copy
    if [[ ! -f "$target_file" ]]; then
        mkdir -p "$(dirname "$target_file")"
        cp "$source_file" "$target_file"
        success "Installed settings.json (no existing file found)"
        return
    fi

    # Backup existing settings
    local ts
    ts=$(get_timestamp)
    local backup_file="${target_file}.bak.${ts}"
    cp "$target_file" "$backup_file"
    success "Backed up settings.json to $(basename "$backup_file")"

    # Deep merge with jq
    local merged
    if merged=$(jq -n '
        # Read both files
        (input) as $existing |
        (input) as $ours |

        # Union two arrays, removing duplicates
        def union_arrays: (.[0] + .[1]) | unique;

        # Merge hook event arrays: append entries whose command does not already exist
        def merge_hook_event($base_entries; $new_entries):
            ($base_entries | [.[] | .hooks[]?.command // ""] | map(select(. != ""))) as $existing_cmds |
            reduce ($new_entries | .[]) as $entry ($base_entries;
                ($entry | .hooks[]?.command // "") as $cmd |
                if ($cmd != "" and ($existing_cmds | index($cmd) != null)) then
                    .
                else
                    . + [$entry]
                end
            );

        # Merge all hooks objects
        def merge_hooks($base; $overlay):
            (($base | keys // []) + ($overlay | keys // []) | unique) as $all_keys |
            reduce $all_keys[] as $key ({};
                . + {
                    ($key): merge_hook_event(
                        ($base[$key] // []);
                        ($overlay[$key] // [])
                    )
                }
            );

        $existing |

        # permissions.allow — union of arrays
        .permissions.allow = ([
            ($existing.permissions.allow // []),
            ($ours.permissions.allow // [])
        ] | union_arrays) |

        # permissions.deny — union of arrays
        .permissions.deny = ([
            ($existing.permissions.deny // []),
            ($ours.permissions.deny // [])
        ] | union_arrays) |

        # hooks — merge objects, append new hook entries by command
        .hooks = merge_hooks(
            ($existing.hooks // {});
            ($ours.hooks // {})
        ) |

        # outputStyle — ours wins
        .outputStyle = $ours.outputStyle |

        # statusLine — ours wins
        .statusLine = $ours.statusLine |

        # env — merge objects, ours wins on conflict
        .env = (($existing.env // {}) + ($ours.env // {}))

    ' "$target_file" "$source_file" 2>&1); then
        printf '%s\n' "$merged" > "$target_file"
        success "Merged settings.json (permissions, hooks, env, outputStyle, statusLine)"
    else
        warn "jq merge failed; copying our settings.json instead (backup preserved)"
        warn "jq output: $merged"
        cp "$source_file" "$target_file"
    fi
}

# ---------------------------------------------------------------------------
# Fix relative paths in settings.json for global install
# ---------------------------------------------------------------------------
fix_paths() {
    local settings_file="$1"
    [[ -f "$settings_file" ]] || return

    local fixed
    if fixed=$(jq --arg home "$HOME" '
        # Fix statusLine command path
        (if .statusLine.command then
            .statusLine.command = ($home + "/.claude/statusline.sh")
        else . end) |

        # Fix outputStyle path
        (if .outputStyle then
            .outputStyle = ($home + "/.claude/output-styles/oh-my-claudecode.md")
        else . end) |

        # Fix hook command paths: replace "bash .claude/hooks/" with absolute path
        (if .hooks then
            .hooks |= with_entries(
                .value |= [.[] |
                    .hooks |= [.[] |
                        if (.command | test("bash \\.claude/hooks/")) then
                            .command |= sub("bash \\.claude/hooks/"; "bash " + $home + "/.claude/hooks/")
                        else . end
                    ]
                ]
            )
        else . end)
    ' "$settings_file" 2>&1); then
        printf '%s\n' "$fixed" > "$settings_file"
        success "Fixed paths in settings.json for global install"
    else
        warn "Path fix failed: $fixed"
    fi
}

# ---------------------------------------------------------------------------
# Copy files from source to target, recording in manifest
#
#   copy_files                       install for real, write $MANIFEST_FILE
#   copy_files --list-only <file>    touch nothing; just write the list of
#                                    paths an install would produce
#
# --list-only exists so --prune can learn the current install set without
# mutating anything (a dry run must not rewrite the manifest it diffs against).
# One traversal serves both modes, so the two can never drift apart.
# ---------------------------------------------------------------------------
copy_files() {
    local list_only=0
    local out="$MANIFEST_FILE"
    if [[ "${1:-}" == "--list-only" ]]; then
        list_only=1
        out="$2"
    fi

    # Capture the ownership ledger as it stands before we overwrite the
    # manifest. An install predating the ledger seeds it from the manifest.
    local prev_owned=""
    if [[ $list_only -eq 0 ]]; then
        prev_owned=$(mktemp "${TMPDIR:-/tmp}/omc-owned.XXXXXX")
        if [[ -f "$OWNED_FILE" ]]; then
            cat "$OWNED_FILE" >> "$prev_owned"
        fi
        if [[ -f "$MANIFEST_FILE" ]]; then
            cat "$MANIFEST_FILE" >> "$prev_owned"
        fi
    fi

    local manifest_entries=()

    # --- Agents ---
    if [[ -d "$SOURCE_CLAUDE_DIR/agents" ]]; then
        [[ $list_only -eq 1 ]] || mkdir -p "$TARGET_DIR/agents"
        local agent_count=0
        for f in "$SOURCE_CLAUDE_DIR/agents/"*.md; do
            [[ -f "$f" ]] || continue
            local name
            name=$(basename "$f")
            [[ $list_only -eq 1 ]] || cp "$f" "$TARGET_DIR/agents/$name"
            manifest_entries+=("$TARGET_DIR/agents/$name")
            agent_count=$((agent_count + 1))
        done
        [[ $list_only -eq 1 ]] || success "Installed $agent_count agent(s)"
    fi

    # --- Hooks ---
    if [[ -d "$SOURCE_CLAUDE_DIR/hooks" ]]; then
        [[ $list_only -eq 1 ]] || mkdir -p "$TARGET_DIR/hooks"
        local hook_count=0
        for f in "$SOURCE_CLAUDE_DIR/hooks/"*.sh; do
            [[ -f "$f" ]] || continue
            local name
            name=$(basename "$f")
            if [[ $list_only -eq 0 ]]; then
                cp "$f" "$TARGET_DIR/hooks/$name"
                chmod +x "$TARGET_DIR/hooks/$name"
            fi
            manifest_entries+=("$TARGET_DIR/hooks/$name")
            hook_count=$((hook_count + 1))
        done
        [[ $list_only -eq 1 ]] || success "Installed $hook_count hook(s)"
    fi

    # --- Skills (directory trees) ---
    if [[ -d "$SOURCE_CLAUDE_DIR/skills" ]]; then
        [[ $list_only -eq 1 ]] || mkdir -p "$TARGET_DIR/skills"
        local skill_count=0
        for skill_dir in "$SOURCE_CLAUDE_DIR/skills/"*/; do
            [[ -d "$skill_dir" ]] || continue
            local skill_name
            skill_name=$(basename "$skill_dir")
            [[ $list_only -eq 1 ]] || mkdir -p "$TARGET_DIR/skills/$skill_name"
            # Copy all files within the skill directory
            while IFS= read -r -d '' src_file; do
                local rel_path="${src_file#"$skill_dir"}"
                local dest_path="$TARGET_DIR/skills/$skill_name/$rel_path"
                if [[ $list_only -eq 0 ]]; then
                    mkdir -p "$(dirname "$dest_path")"
                    cp "$src_file" "$dest_path"
                fi
                manifest_entries+=("$dest_path")
            done < <(find "$skill_dir" -type f -print0 2>/dev/null)
            skill_count=$((skill_count + 1))
        done
        [[ $list_only -eq 1 ]] || success "Installed $skill_count skill(s)"
    fi

    # --- Scripts ---
    if [[ -d "$SOURCE_CLAUDE_DIR/scripts" ]]; then
        [[ $list_only -eq 1 ]] || mkdir -p "$TARGET_DIR/scripts"
        local script_count=0
        for f in "$SOURCE_CLAUDE_DIR/scripts/"*.sh; do
            [[ -f "$f" ]] || continue
            local name
            name=$(basename "$f")
            if [[ $list_only -eq 0 ]]; then
                cp "$f" "$TARGET_DIR/scripts/$name"
                chmod +x "$TARGET_DIR/scripts/$name"
            fi
            manifest_entries+=("$TARGET_DIR/scripts/$name")
            script_count=$((script_count + 1))
        done
        [[ $list_only -eq 1 ]] || success "Installed $script_count script(s)"
    fi

    # --- Output styles ---
    if [[ -d "$SOURCE_CLAUDE_DIR/output-styles" ]]; then
        [[ $list_only -eq 1 ]] || mkdir -p "$TARGET_DIR/output-styles"
        local style_count=0
        for f in "$SOURCE_CLAUDE_DIR/output-styles/"*.md; do
            [[ -f "$f" ]] || continue
            local name
            name=$(basename "$f")
            [[ $list_only -eq 1 ]] || cp "$f" "$TARGET_DIR/output-styles/$name"
            manifest_entries+=("$TARGET_DIR/output-styles/$name")
            style_count=$((style_count + 1))
        done
        [[ $list_only -eq 1 ]] || success "Installed $style_count output style(s)"
    fi

    # --- statusline.sh ---
    if [[ -f "$SOURCE_CLAUDE_DIR/statusline.sh" ]]; then
        if [[ $list_only -eq 0 ]]; then
            cp "$SOURCE_CLAUDE_DIR/statusline.sh" "$TARGET_DIR/statusline.sh"
            chmod +x "$TARGET_DIR/statusline.sh"
            success "Installed statusline.sh"
        fi
        manifest_entries+=("$TARGET_DIR/statusline.sh")
    fi

    # --- CLAUDE.md ---
    if [[ -f "$CLONE_DIR/CLAUDE.md" ]]; then
        if [[ $list_only -eq 0 ]]; then
            cp "$CLONE_DIR/CLAUDE.md" "$TARGET_DIR/CLAUDE.md"
            success "Installed CLAUDE.md (global orchestration protocol)"
        fi
        manifest_entries+=("$TARGET_DIR/CLAUDE.md")
    fi

    # --- .mcp.json (global MCP servers) ---
    if [[ -f "$CLONE_DIR/.mcp.json" ]]; then
        if [[ $list_only -eq 0 ]]; then
            if [[ -f "$TARGET_DIR/.mcp.json" ]]; then
                # Merge: add our servers to existing, don't overwrite
                local ts
                ts=$(get_timestamp)
                cp "$TARGET_DIR/.mcp.json" "$TARGET_DIR/.mcp.json.bak.${ts}"
                if merged_mcp=$(jq -n '
                    (input) as $existing |
                    (input) as $ours |
                    $existing * { mcpServers: (($existing.mcpServers // {}) + ($ours.mcpServers // {})) }
                ' "$TARGET_DIR/.mcp.json" "$CLONE_DIR/.mcp.json" 2>&1); then
                    printf '%s\n' "$merged_mcp" > "$TARGET_DIR/.mcp.json"
                    success "Merged .mcp.json (added MCP servers, backed up original)"
                else
                    warn "MCP merge failed; copying ours (backup preserved)"
                    cp "$CLONE_DIR/.mcp.json" "$TARGET_DIR/.mcp.json"
                fi
            else
                cp "$CLONE_DIR/.mcp.json" "$TARGET_DIR/.mcp.json"
                success "Installed .mcp.json (Context7 MCP server)"
            fi
        fi
        manifest_entries+=("$TARGET_DIR/.mcp.json")
    fi

    # Write manifest (or, in --list-only mode, the would-install list)
    printf '%s\n' "${manifest_entries[@]}" > "$out"

    if [[ $list_only -eq 0 ]]; then
        # Fold this install into the cumulative ledger.
        {
            cat "$prev_owned"
            printf '%s\n' "${manifest_entries[@]}"
        } | grep -v '^[[:space:]]*$' | LC_ALL=C sort -u > "$OWNED_FILE"
        rm -f "$prev_owned"
        success "Wrote manifest (${#manifest_entries[@]} entries)"
    fi
}

# ---------------------------------------------------------------------------
# Remove directories we own that are now empty
# ---------------------------------------------------------------------------
remove_empty_dirs() {
    for dir in \
        "$TARGET_DIR/agents" \
        "$TARGET_DIR/hooks" \
        "$TARGET_DIR/scripts" \
        "$TARGET_DIR/output-styles"; do
        if [[ -d "$dir" ]] && [[ -z "$(ls -A "$dir" 2>/dev/null)" ]]; then
            rmdir "$dir" 2>/dev/null || true
        fi
    done

    # Skills are directory trees; collapse any that were emptied out.
    if [[ -d "$TARGET_DIR/skills" ]]; then
        find "$TARGET_DIR/skills" -type d -empty -delete 2>/dev/null || true
    fi
}

# ---------------------------------------------------------------------------
# Prune: remove files we installed previously that the repo no longer ships
#
# copy_files() is purely additive — a file deleted upstream lingers in the
# target dir forever (and drops out of the manifest, so even --uninstall
# misses it). Pruning diffs the pre-copy manifest against the post-copy one.
# ---------------------------------------------------------------------------

# orphan_list <old_list> <new_list>
# Print orphans, one per line: listed in <old_list>, absent from <new_list>,
# still present on disk, inside TARGET_DIR, and not user-owned.
orphan_list() {
    local old_list="$1" new_list="$2"
    [[ -f "$old_list" && -f "$new_list" ]] || return 0

    local path base
    while IFS= read -r path; do
        [[ -n "$path" ]] || continue
        [[ -f "$path" ]] || continue                    # already gone
        [[ "$path" == "$TARGET_DIR"/* ]] || continue     # never step outside the target
        base=$(basename "$path")
        case " $PROTECTED_BASENAMES " in
            *" $base "*) continue ;;
        esac
        printf '%s\n' "$path"
    done < <(LC_ALL=C comm -23 \
        <(LC_ALL=C sort -u "$old_list") \
        <(LC_ALL=C sort -u "$new_list"))
}

confirm_prune() {
    local count="$1"
    [[ $ASSUME_YES -eq 1 ]] && return 0
    if [[ ! -r /dev/tty ]]; then
        warn "No terminal available to confirm; re-run with --yes to prune non-interactively."
        return 1
    fi
    printf "  Remove these %s file(s)? A backup is kept. (y/N) " "$count"
    local reply
    read -r reply < /dev/tty
    [[ "$reply" == "y" || "$reply" == "Y" ]]
}

# prune_orphans <old_list> <new_list>
prune_orphans() {
    local old_list="$1" new_list="$2"
    local orphans=()
    while IFS= read -r line; do
        orphans+=("$line")
    done < <(orphan_list "$old_list" "$new_list")

    if [[ ${#orphans[@]} -eq 0 ]]; then
        success "Nothing to prune — $TARGET_DIR matches the repo."
        return
    fi

    printf "\n"
    info "${#orphans[@]} orphaned file(s) no longer shipped by the repo:"
    local p
    for p in "${orphans[@]}"; do
        printf "         ${YELLOW}%s${RESET}\n" "${p#"$TARGET_DIR"/}"
    done
    printf "\n"

    if [[ $DRY_RUN -eq 1 ]]; then
        info "--dry-run: nothing was removed."
        return
    fi

    if ! confirm_prune "${#orphans[@]}"; then
        info "Aborted; nothing was removed."
        return
    fi

    local ts backup_root rel dest removed=0
    ts=$(get_timestamp)
    backup_root="$CLONE_DIR/.pruned.${ts}"
    local pruned=()
    for p in "${orphans[@]}"; do
        rel="${p#"$TARGET_DIR"/}"
        dest="$backup_root/$rel"
        mkdir -p "$(dirname "$dest")"
        if cp "$p" "$dest" 2>/dev/null && rm -f "$p"; then
            removed=$((removed + 1))
            pruned+=("$p")
        else
            warn "Could not remove $p"
        fi
    done

    # Drop pruned paths from the manifest and the ledger, so neither claims a
    # file that is no longer on disk.
    if [[ ${#pruned[@]} -gt 0 ]]; then
        local list tmp_list keep skip
        for list in "$MANIFEST_FILE" "$OWNED_FILE"; do
            [[ -f "$list" ]] || continue
            tmp_list=$(mktemp "${TMPDIR:-/tmp}/omc-filter.XXXXXX")
            while IFS= read -r keep; do
                skip=0
                for p in "${pruned[@]}"; do
                    [[ "$keep" == "$p" ]] && { skip=1; break; }
                done
                [[ $skip -eq 1 ]] || printf '%s\n' "$keep"
            done < "$list" > "$tmp_list"
            mv "$tmp_list" "$list"
        done
    fi

    success "Pruned $removed file(s)"
    info "Backup kept at $backup_root"
    remove_empty_dirs
}

# Nudge after a plain --update so orphans don't accumulate silently.
# report_prunable <old_list> <new_list>
report_prunable() {
    local count
    count=$(orphan_list "$1" "$2" | wc -l | tr -d ' ')
    if [[ "$count" -gt 0 ]]; then
        printf "\n"
        warn "$count file(s) in $TARGET_DIR are no longer shipped by the repo."
        warn "Run with --prune to remove them (a backup is kept), or --prune --dry-run to preview."
    fi
}

# ---------------------------------------------------------------------------
# Post-install notes
# ---------------------------------------------------------------------------
print_notes() {
    printf "\n"
    printf "  ${CYAN}Notes:${RESET}\n"
    printf "    - ${GREEN}.mcp.json${RESET} installed globally — Context7 is available in all projects.\n"
    printf "\n"
    printf "    - ${YELLOW}.sisyphus/${RESET} directory is per-project (plans, audit logs).\n"
    printf "      It will be created automatically when using prometheus/atlas.\n"
    printf "\n"
}

# ===========================================================================
# Mode: Install (default, no flag)
# ===========================================================================
do_install() {
    banner
    check_prerequisites

    # Guard against overwriting existing install
    if [[ -d "$CLONE_DIR" ]]; then
        warn "oh-my-claudecode is already installed at $CLONE_DIR"
        warn "Use --update to pull latest changes, or --clean for a fresh install."
        exit 1
    fi

    # Clone
    info "Cloning oh-my-claudecode..."
    if ! git clone "$REPO_URL" "$CLONE_DIR" 2>/dev/null; then
        error "Failed to clone repository from $REPO_URL"
        exit 1
    fi
    success "Cloned to $CLONE_DIR"

    # Create target
    mkdir -p "$TARGET_DIR"

    # Copy all files
    info "Installing files to $TARGET_DIR..."
    copy_files

    # Merge settings.json
    info "Merging settings.json..."
    merge_settings "$SOURCE_CLAUDE_DIR/settings.json" "$TARGET_DIR/settings.json"
    fix_paths "$TARGET_DIR/settings.json"

    # Summary
    local file_count
    file_count=$(wc -l < "$MANIFEST_FILE" | tr -d ' ')
    printf "\n"
    printf "  ${GREEN}${BOLD}Installation complete!${RESET}\n"
    printf "  ${GREEN}$file_count files installed.${RESET}\n"
    printf "\n"
    printf "  Installed to:  ${CYAN}$TARGET_DIR${RESET}\n"
    printf "  Source repo:   ${CYAN}$CLONE_DIR${RESET}\n"
    printf "  Manifest:      ${CYAN}$MANIFEST_FILE${RESET}\n"

    print_notes

    printf "  To update later:\n"
    printf "    ${YELLOW}curl -fsSL https://raw.githubusercontent.com/theuseless-ai/my-claude-code/main/install.sh | bash -s -- --update${RESET}\n"
    printf "  To uninstall:\n"
    printf "    ${YELLOW}curl -fsSL https://raw.githubusercontent.com/theuseless-ai/my-claude-code/main/install.sh | bash -s -- --uninstall${RESET}\n"
    printf "\n"
}

# ===========================================================================
# Mode: --update
# ===========================================================================
do_update() {
    banner
    check_prerequisites

    if [[ ! -d "$CLONE_DIR" ]]; then
        error "oh-my-claudecode is not installed. Run without flags to install first."
        exit 1
    fi

    # Pull latest
    info "Pulling latest changes..."
    if ! git -C "$CLONE_DIR" pull --ff-only 2>/dev/null; then
        error "Failed to pull updates (ff-only). You may need to resolve conflicts in $CLONE_DIR"
        exit 1
    fi
    success "Repository updated"

    # Re-copy all files
    mkdir -p "$TARGET_DIR"
    info "Re-installing files to $TARGET_DIR..."
    copy_files

    # Re-merge settings
    info "Re-merging settings.json..."
    merge_settings "$SOURCE_CLAUDE_DIR/settings.json" "$TARGET_DIR/settings.json"
    fix_paths "$TARGET_DIR/settings.json"

    # Summary
    local file_count
    file_count=$(wc -l < "$MANIFEST_FILE" | tr -d ' ')
    printf "\n"
    printf "  ${GREEN}${BOLD}Update complete!${RESET}\n"
    printf "  ${GREEN}$file_count files updated.${RESET}\n"

    # copy_files just refreshed both lists, so the manifest is the current
    # install set and the ledger holds everything we ever installed.
    if [[ $PRUNE -eq 1 ]]; then
        prune_orphans "$OWNED_FILE" "$MANIFEST_FILE"
    else
        report_prunable "$OWNED_FILE" "$MANIFEST_FILE"
    fi

    print_notes
}

# ===========================================================================
# Mode: --prune
#
# Removes files from earlier installs that the repo no longer ships. Pure
# removal: it does not pull, does not copy, and does not touch settings.json.
# The install set is computed with copy_files --list-only, so a --dry-run
# leaves the manifest it diffs against intact.
# ===========================================================================
do_prune() {
    banner
    check_prerequisites

    if [[ ! -d "$CLONE_DIR" ]]; then
        error "oh-my-claudecode is not installed. Run without flags to install first."
        exit 1
    fi
    if [[ ! -f "$OWNED_FILE" && ! -f "$MANIFEST_FILE" ]]; then
        error "No install record at $MANIFEST_FILE — cannot tell which files we installed."
        warn "Run --update first to generate one, then prune."
        exit 1
    fi
    # An install predating the ledger: seed it from the manifest so this run
    # has something to compare against. Under --dry-run the seed goes to a
    # temp file instead, keeping the dry run a true no-op.
    local owned_src="$OWNED_FILE"
    if [[ ! -f "$OWNED_FILE" ]]; then
        if [[ $DRY_RUN -eq 1 ]]; then
            SEED_LIST=$(mktemp "${TMPDIR:-/tmp}/omc-seed.XXXXXX")
            owned_src="$SEED_LIST"
        fi
        LC_ALL=C sort -u "$MANIFEST_FILE" | grep -v '^[[:space:]]*$' > "$owned_src" || true
    fi

    info "Comparing $TARGET_DIR against $CLONE_DIR..."
    EXPECTED_LIST=$(mktemp "${TMPDIR:-/tmp}/omc-expected.XXXXXX")
    copy_files --list-only "$EXPECTED_LIST"
    prune_orphans "$owned_src" "$EXPECTED_LIST"

    printf "\n"
    if [[ $DRY_RUN -eq 1 ]]; then
        printf "  ${GREEN}${BOLD}Dry run complete.${RESET}\n"
    else
        printf "  ${GREEN}${BOLD}Prune complete!${RESET}\n"
    fi
    printf "\n"
}

# ===========================================================================
# Mode: --uninstall
# ===========================================================================
do_uninstall() {
    banner

    if [[ ! -d "$CLONE_DIR" ]]; then
        error "oh-my-claudecode is not installed (no $CLONE_DIR found)."
        exit 1
    fi

    # Confirm
    printf "  Remove oh-my-claudecode? Your other Claude Code settings will be preserved. (y/N) "
    read -r confirm < /dev/tty
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        info "Aborted."
        exit 0
    fi

    local removed=0

    # Remove every file we ever installed: the current manifest plus the
    # ownership ledger, so files dropped upstream don't survive an uninstall.
    if [[ -f "$MANIFEST_FILE" || -f "$OWNED_FILE" ]]; then
        info "Removing installed files..."
        local all_owned
        all_owned=$(mktemp "${TMPDIR:-/tmp}/omc-uninstall.XXXXXX")
        for list in "$MANIFEST_FILE" "$OWNED_FILE"; do
            [[ -f "$list" ]] && cat "$list" >> "$all_owned"
        done
        while IFS= read -r filepath; do
            [[ -n "$filepath" ]] || continue
            [[ "$filepath" == "$TARGET_DIR"/* ]] || continue
            if [[ -f "$filepath" ]]; then
                rm "$filepath"
                removed=$((removed + 1))
            fi
        done < <(LC_ALL=C sort -u "$all_owned")
        rm -f "$all_owned"

        # Remove empty directories left behind
        remove_empty_dirs

        success "Removed $removed file(s)"
    else
        warn "No manifest found; cannot determine which files to remove."
        warn "You may need to manually clean up $TARGET_DIR"
    fi

    # Remove the cloned repo
    info "Removing $CLONE_DIR..."
    rm -rf "$CLONE_DIR"
    success "Removed $CLONE_DIR"

    printf "\n"
    printf "  ${GREEN}${BOLD}Uninstall complete!${RESET}\n"
    printf "\n"
    printf "  ${CYAN}Notes:${RESET}\n"
    printf "    - ${YELLOW}settings.json${RESET} was left intact (too risky to un-merge).\n"
    printf "      Edit $TARGET_DIR/settings.json manually if needed.\n"
    printf "\n"
}

# ===========================================================================
# Mode: --clean
# ===========================================================================
do_clean() {
    banner
    check_prerequisites

    # Big destructive warning
    printf "${RED}${BOLD}"
    cat <<WARNING

  !!!  DESTRUCTIVE OPERATION  !!!

  This will DELETE your entire ${TARGET_DIR}/ directory including:
    - All settings (settings.json, settings.local.json)
    - All custom agents, hooks, skills
    - All output styles and status lines
    - Everything in ${TARGET_DIR}/

  A backup will be saved to ${TARGET_DIR}.bak.{timestamp}/

WARNING
    printf "${RESET}"

    # Require typing 'yes'
    printf "  Type 'yes' to confirm (not just y): "
    read -r confirm < /dev/tty
    if [[ "$confirm" != "yes" ]]; then
        info "Aborted."
        exit 0
    fi

    local ts
    ts=$(get_timestamp)
    local backup_dir=""

    # Backup existing ~/.claude/
    if [[ -d "$TARGET_DIR" ]]; then
        backup_dir="${TARGET_DIR}.bak.${ts}"
        info "Backing up $TARGET_DIR to $backup_dir..."
        cp -r "$TARGET_DIR" "$backup_dir"
        success "Backup saved to $backup_dir"

        info "Removing $TARGET_DIR..."
        rm -rf "$TARGET_DIR"
        success "Removed $TARGET_DIR"
    fi

    # Remove old clone if present
    if [[ -d "$CLONE_DIR" ]]; then
        info "Removing old installation at $CLONE_DIR..."
        rm -rf "$CLONE_DIR"
        success "Removed $CLONE_DIR"
    fi

    # Fresh clone
    info "Cloning oh-my-claudecode..."
    if ! git clone "$REPO_URL" "$CLONE_DIR" 2>/dev/null; then
        error "Failed to clone repository from $REPO_URL"
        exit 1
    fi
    success "Cloned to $CLONE_DIR"

    # Fresh install — no merge, just copy everything
    mkdir -p "$TARGET_DIR"
    info "Installing files to $TARGET_DIR..."
    copy_files

    # Direct copy of settings.json (clean slate, no merge)
    if [[ -f "$SOURCE_CLAUDE_DIR/settings.json" ]]; then
        cp "$SOURCE_CLAUDE_DIR/settings.json" "$TARGET_DIR/settings.json"
        fix_paths "$TARGET_DIR/settings.json"
        success "Installed settings.json (clean copy, paths fixed)"
    fi

    # Summary
    local file_count
    file_count=$(wc -l < "$MANIFEST_FILE" | tr -d ' ')
    printf "\n"
    printf "  ${GREEN}${BOLD}Clean installation complete!${RESET}\n"
    printf "  ${GREEN}$file_count files installed.${RESET}\n"
    if [[ -n "$backup_dir" ]]; then
        printf "  ${CYAN}Backup location:${RESET} $backup_dir\n"
    fi

    print_notes
}

# ===========================================================================
# Main
# ===========================================================================
main() {
    local mode=""
    local target_override=""

    # Parse args: a single mode flag plus an optional --target <dir> (any order).
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --update|--uninstall|--clean|--help|-h)
                mode="$1"; shift ;;
            --prune)
                PRUNE=1; shift ;;
            --dry-run)
                DRY_RUN=1; shift ;;
            --yes|-y)
                ASSUME_YES=1; shift ;;
            --target)
                target_override="${2:-}"
                if [[ -z "$target_override" ]]; then
                    error "--target requires a directory argument"
                    exit 1
                fi
                shift 2 ;;
            --target=*)
                target_override="${1#*=}"
                if [[ -z "$target_override" ]]; then
                    error "--target requires a directory argument"
                    exit 1
                fi
                shift ;;
            "")
                shift ;;
            *)
                error "Unknown option: $1"
                printf "  Use --help for usage.\n"
                exit 1 ;;
        esac
    done

    # Apply the target override (expanding a leading ~), then derive a per-target
    # manifest name for non-default targets so parallel installs stay isolated.
    if [[ -n "$target_override" ]]; then
        TARGET_DIR="${target_override/#\~/$HOME}"
    fi
    if [[ "$TARGET_DIR" != "$DEFAULT_TARGET_DIR" ]]; then
        local slug
        slug="$(printf '%s' "$TARGET_DIR" | sed 's#[^A-Za-z0-9]#_#g')"
        MANIFEST_FILE="$CLONE_DIR/.manifest.${slug}"
    fi
    # Keep the ledger beside whichever manifest we settled on, so parallel
    # installs to different targets stay isolated from each other.
    OWNED_FILE="${MANIFEST_FILE}.owned"

    # Reject flag combinations that cannot mean anything
    if [[ $PRUNE -eq 1 && ( "$mode" == "--uninstall" || "$mode" == "--clean" ) ]]; then
        error "--prune cannot be combined with $mode"
        printf "  %s already removes files; --prune is for reconciling an existing install.\n" "$mode"
        exit 1
    fi
    if [[ $DRY_RUN -eq 1 && $PRUNE -ne 1 ]]; then
        error "--dry-run only applies to --prune"
        exit 1
    fi

    # --prune on its own is a mode; alongside --update it's a post-copy step.
    if [[ -z "$mode" && $PRUNE -eq 1 ]]; then
        do_prune
        return
    fi

    case "$mode" in
        --update)    do_update ;;
        --uninstall) do_uninstall ;;
        --clean)     do_clean ;;
        --help|-h)
            printf "Usage: install.sh [--update|--prune|--uninstall|--clean|--help] [--target <dir>]\n\n"
            printf "  (no flag)      Install oh-my-claudecode (smart merge with existing config)\n"
            printf "  --update       Pull latest, re-copy files, re-merge settings\n"
            printf "  --prune        Remove files from earlier installs the repo no longer ships\n"
            printf "  --uninstall    Remove only oh-my-claudecode files (preserves settings.json)\n"
            printf "  --clean        NUKE entire target dir, backup, then fresh install\n"
            printf "  --target <dir> Install to <dir> instead of the default\n"
            printf "  --help         Show this help\n\n"
            printf "  Prune options (also valid as '--update --prune'):\n"
            printf "    --dry-run    List what would be pruned, remove nothing\n"
            printf "    --yes, -y    Skip the confirmation prompt\n\n"
            printf "  Pruned files are copied to %s/.pruned.<timestamp>/ first.\n" "$CLONE_DIR"
            printf "  Never pruned: %s\n\n" "$PROTECTED_BASENAMES"
            printf "  Target precedence: --target > \$CLAUDE_CONFIG_DIR > ~/.claude\n"
            printf "  Current target:    %s\n" "$TARGET_DIR"
            ;;
        "")          do_install ;;
    esac
}

main "$@"
