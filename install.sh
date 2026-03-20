#!/usr/bin/env bash
# oh-my-claudecode installer
# Multi-Agent Orchestration System for Claude Code
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/theuseless-ai/my-claude-code/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/theuseless-ai/my-claude-code/main/install.sh | bash -s -- --update
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
CLONE_DIR="$HOME/.oh-my-claudecode"
TARGET_DIR="$HOME/.claude"
MANIFEST_FILE="$CLONE_DIR/.manifest"
SOURCE_CLAUDE_DIR="$CLONE_DIR/.claude"

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
# Copy files from source to target, recording in manifest
# ---------------------------------------------------------------------------
copy_files() {
    local manifest_entries=()

    # --- Agents ---
    if [[ -d "$SOURCE_CLAUDE_DIR/agents" ]]; then
        mkdir -p "$TARGET_DIR/agents"
        local agent_count=0
        for f in "$SOURCE_CLAUDE_DIR/agents/"*.md; do
            [[ -f "$f" ]] || continue
            local name
            name=$(basename "$f")
            cp "$f" "$TARGET_DIR/agents/$name"
            manifest_entries+=("$TARGET_DIR/agents/$name")
            agent_count=$((agent_count + 1))
        done
        success "Installed $agent_count agent(s)"
    fi

    # --- Hooks ---
    if [[ -d "$SOURCE_CLAUDE_DIR/hooks" ]]; then
        mkdir -p "$TARGET_DIR/hooks"
        local hook_count=0
        for f in "$SOURCE_CLAUDE_DIR/hooks/"*.sh; do
            [[ -f "$f" ]] || continue
            local name
            name=$(basename "$f")
            cp "$f" "$TARGET_DIR/hooks/$name"
            chmod +x "$TARGET_DIR/hooks/$name"
            manifest_entries+=("$TARGET_DIR/hooks/$name")
            hook_count=$((hook_count + 1))
        done
        success "Installed $hook_count hook(s)"
    fi

    # --- Skills (directory trees) ---
    if [[ -d "$SOURCE_CLAUDE_DIR/skills" ]]; then
        mkdir -p "$TARGET_DIR/skills"
        local skill_count=0
        for skill_dir in "$SOURCE_CLAUDE_DIR/skills/"*/; do
            [[ -d "$skill_dir" ]] || continue
            local skill_name
            skill_name=$(basename "$skill_dir")
            mkdir -p "$TARGET_DIR/skills/$skill_name"
            # Copy all files within the skill directory
            while IFS= read -r -d '' src_file; do
                local rel_path="${src_file#"$skill_dir"}"
                local dest_path="$TARGET_DIR/skills/$skill_name/$rel_path"
                mkdir -p "$(dirname "$dest_path")"
                cp "$src_file" "$dest_path"
                manifest_entries+=("$dest_path")
            done < <(find "$skill_dir" -type f -print0 2>/dev/null)
            skill_count=$((skill_count + 1))
        done
        success "Installed $skill_count skill(s)"
    fi

    # --- Output styles ---
    if [[ -d "$SOURCE_CLAUDE_DIR/output-styles" ]]; then
        mkdir -p "$TARGET_DIR/output-styles"
        local style_count=0
        for f in "$SOURCE_CLAUDE_DIR/output-styles/"*.md; do
            [[ -f "$f" ]] || continue
            local name
            name=$(basename "$f")
            cp "$f" "$TARGET_DIR/output-styles/$name"
            manifest_entries+=("$TARGET_DIR/output-styles/$name")
            style_count=$((style_count + 1))
        done
        success "Installed $style_count output style(s)"
    fi

    # --- statusline.sh ---
    if [[ -f "$SOURCE_CLAUDE_DIR/statusline.sh" ]]; then
        cp "$SOURCE_CLAUDE_DIR/statusline.sh" "$TARGET_DIR/statusline.sh"
        chmod +x "$TARGET_DIR/statusline.sh"
        manifest_entries+=("$TARGET_DIR/statusline.sh")
        success "Installed statusline.sh"
    fi

    # --- CLAUDE.md ---
    if [[ -f "$CLONE_DIR/CLAUDE.md" ]]; then
        cp "$CLONE_DIR/CLAUDE.md" "$TARGET_DIR/CLAUDE.md"
        manifest_entries+=("$TARGET_DIR/CLAUDE.md")
        success "Installed CLAUDE.md (global orchestration protocol)"
    fi

    # --- .mcp.json (global MCP servers) ---
    if [[ -f "$CLONE_DIR/.mcp.json" ]]; then
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
        manifest_entries+=("$TARGET_DIR/.mcp.json")
    fi

    # Write manifest
    printf '%s\n' "${manifest_entries[@]}" > "$MANIFEST_FILE"
    success "Wrote manifest (${#manifest_entries[@]} entries)"
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

    # Summary
    local file_count
    file_count=$(wc -l < "$MANIFEST_FILE" | tr -d ' ')
    printf "\n"
    printf "  ${GREEN}${BOLD}Update complete!${RESET}\n"
    printf "  ${GREEN}$file_count files updated.${RESET}\n"

    print_notes
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

    # Remove files listed in manifest
    if [[ -f "$MANIFEST_FILE" ]]; then
        info "Removing installed files..."
        while IFS= read -r filepath; do
            if [[ -f "$filepath" ]]; then
                rm "$filepath"
                removed=$((removed + 1))
            fi
        done < "$MANIFEST_FILE"

        # Remove empty directories left behind
        for dir in \
            "$TARGET_DIR/agents" \
            "$TARGET_DIR/hooks" \
            "$TARGET_DIR/output-styles"; do
            if [[ -d "$dir" ]] && [[ -z "$(ls -A "$dir" 2>/dev/null)" ]]; then
                rmdir "$dir" 2>/dev/null || true
            fi
        done

        # Clean up empty skill subdirectories, then skills dir itself
        if [[ -d "$TARGET_DIR/skills" ]]; then
            find "$TARGET_DIR/skills" -type d -empty -delete 2>/dev/null || true
        fi

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
    printf "      Edit ~/.claude/settings.json manually if needed.\n"
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
    cat <<'WARNING'

  !!!  DESTRUCTIVE OPERATION  !!!

  This will DELETE your entire ~/.claude/ directory including:
    - All settings (settings.json, settings.local.json)
    - All custom agents, hooks, skills
    - All output styles and status lines
    - Everything in ~/.claude/

  A backup will be saved to ~/.claude.bak.{timestamp}/

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
        backup_dir="$HOME/.claude.bak.${ts}"
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
        success "Installed settings.json (clean copy)"
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
    local mode="${1:-}"

    case "$mode" in
        --update)    do_update ;;
        --uninstall) do_uninstall ;;
        --clean)     do_clean ;;
        --help|-h)
            printf "Usage: install.sh [--update|--uninstall|--clean|--help]\n\n"
            printf "  (no flag)     Install oh-my-claudecode (smart merge with existing config)\n"
            printf "  --update      Pull latest, re-copy files, re-merge settings\n"
            printf "  --uninstall   Remove only oh-my-claudecode files (preserves settings.json)\n"
            printf "  --clean       NUKE entire ~/.claude/, backup, then fresh install\n"
            printf "  --help        Show this help\n"
            ;;
        "")          do_install ;;
        *)
            error "Unknown option: $mode"
            printf "  Use --help for usage.\n"
            exit 1
            ;;
    esac
}

main "$@"
