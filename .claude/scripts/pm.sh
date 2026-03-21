#!/usr/bin/env bash
# pm.sh — Generic GitHub Project CLI wrapper
# Provides preset commands for querying GitHub Projects v2,
# repo milestones, and cross-repo gap analysis.
#
# Usage: pm.sh <command> [args]
#
# Context discovery:
#   --org <org>         Override org (default: from current repo remote)
#   --project <number>  Override project number (default: first open project)
#   --repo <owner/repo> Override repo (default: from current directory)

set -euo pipefail

# ─── Colors ───────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ─── Context Discovery ───────────────────────────────────────────────

ORG=""
PROJECT_NUMBER=""
REPO=""

discover_context() {
  # Parse global flags first
  local args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --org) ORG="$2"; shift 2 ;;
      --project) PROJECT_NUMBER="$2"; shift 2 ;;
      --repo) REPO="$2"; shift 2 ;;
      *) args+=("$1"); shift ;;
    esac
  done

  # Auto-discover org from current repo if not set
  if [[ -z "$ORG" ]]; then
    local remote_url
    remote_url=$(git remote get-url origin 2>/dev/null || echo "")
    if [[ -n "$remote_url" ]]; then
      # Extract org from git@github.com:org/repo.git or https://github.com/org/repo
      ORG=$(echo "$remote_url" | sed -E 's#(git@github\.com:|https://github\.com/)##; s#\.git$##' | cut -d'/' -f1)
    fi
  fi

  # Auto-discover repo from current directory
  if [[ -z "$REPO" ]]; then
    REPO=$(gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null || echo "")
  fi

  # Auto-discover first open project for the org
  if [[ -z "$PROJECT_NUMBER" && -n "$ORG" ]]; then
    PROJECT_NUMBER=$(gh project list --owner "$ORG" --format json 2>/dev/null \
      | jq -r '.projects[] | select(.closed == false) | .number' \
      | head -1)
  fi

  # Set positional args to remaining (non-flag) arguments
  REMAINING_ARGS=("${args[@]}")
}

require_org() {
  if [[ -z "$ORG" ]]; then
    echo -e "${RED}Error: Could not discover org. Use --org <org> or run from a repo directory.${NC}" >&2
    exit 1
  fi
}

require_project() {
  require_org
  if [[ -z "$PROJECT_NUMBER" ]]; then
    echo -e "${RED}Error: No open project found for org '$ORG'. Use --project <number>.${NC}" >&2
    exit 1
  fi
}

# ─── Data Fetchers ────────────────────────────────────────────────────

fetch_project_items() {
  gh project item-list "$PROJECT_NUMBER" --owner "$ORG" --format json --limit 500 2>/dev/null
}

fetch_project_meta() {
  gh project list --owner "$ORG" --format json 2>/dev/null \
    | jq -r ".projects[] | select(.number == $PROJECT_NUMBER)"
}

# ─── Commands ─────────────────────────────────────────────────────────

cmd_status() {
  require_project
  local meta items
  meta=$(fetch_project_meta)
  items=$(fetch_project_items)

  local title description
  title=$(echo "$meta" | jq -r '.title')
  description=$(echo "$meta" | jq -r '.shortDescription // "No description"')

  echo -e "${BOLD}Project: ${CYAN}$title${NC} ${DIM}(#$PROJECT_NUMBER on $ORG)${NC}"
  echo -e "${DIM}$description${NC}"
  echo ""

  # Status breakdown
  echo -e "${BOLD}Status Breakdown${NC}"
  echo "$items" | jq -r '
    .items | group_by(.status) | map({status: .[0].status, count: length})
    | sort_by(-.count)[] | "  \(.status): \(.count)"'

  echo ""

  # Milestone breakdown
  echo -e "${BOLD}Milestones${NC}"
  echo "$items" | jq -r '
    .items | map(. + {ms: ((.milestone.title) // "No milestone")})
    | group_by(.ms)
    | map({
        milestone: .[0].ms,
        total: length,
        done: [.[] | select(.status == "Done")] | length,
        remaining: [.[] | select(.status != "Done")] | length
      })
    | sort_by(.milestone)[]
    | "  \(.milestone): \(.done)/\(.total) done (\(.remaining) remaining)"'

  echo ""

  # Repo breakdown
  echo -e "${BOLD}Repositories${NC}"
  echo "$items" | jq -r '
    .items | map(. + {repo_url: (.repository // "unknown")})
    | group_by(.repo_url)
    | map({repo: (.[0].repo_url | split("/") | .[-1]), count: length})
    | sort_by(-.count)[] | "  \(.repo): \(.count) items"'
}

cmd_milestone() {
  require_project
  local version="${1:-}"
  if [[ -z "$version" ]]; then
    echo -e "${RED}Usage: pm.sh milestone <version>${NC}" >&2
    exit 1
  fi

  local items
  items=$(fetch_project_items)

  echo -e "${BOLD}Milestone: ${CYAN}$version${NC}"
  echo ""

  # Items in this milestone
  echo "$items" | jq -r --arg v "$version" '
    .items
    | map(select(.milestone.title == $v))
    | if length == 0 then "  No items found for milestone \($v)"
      else
        group_by(.status) | map(
          "  \(.[0].status) (\(length)):",
          (.[] | "    - [\(.content.repository // .repository | split("/") | .[-1])] \(.title)" +
            if .content.number then " (#\(.content.number))" else "" end)
        ) | .[]
      end'

  echo ""

  # Due date if available
  echo "$items" | jq -r --arg v "$version" '
    .items
    | map(select(.milestone.title == $v))
    | .[0].milestone.dueOn // empty
    | "Due: \(.)"'
}

cmd_repos() {
  require_project
  local items
  items=$(fetch_project_items)

  echo -e "${BOLD}Items by Repository${NC}"
  echo ""

  echo "$items" | jq -r '
    .items | group_by(.repository)
    | map({
        repo: (.[0].repository | split("/") | .[-1]),
        full: .[0].repository,
        items: .,
        done: [.[] | select(.status == "Done")] | length,
        total: length
      })
    | sort_by(.repo)[]
    | "\(.repo) (\(.done)/\(.total) done):",
      (.items | sort_by(.status) | reverse[] |
        "  [\(.status)] \(.title)" +
        if .content.number then " (#\(.content.number))" else "" end)'
}

cmd_versions() {
  # Find and read VERSION file — check current repo, then search org repos
  local version_content=""

  # Try current directory first
  if [[ -f "VERSION" ]]; then
    version_content=$(cat VERSION)
    echo -e "${BOLD}VERSION${NC} ${DIM}(from current directory)${NC}"
  else
    # Search org repos for VERSION file
    require_org
    local repos
    repos=$(gh repo list "$ORG" --json name -q '.[].name' 2>/dev/null)
    for repo in $repos; do
      version_content=$(gh api "repos/$ORG/$repo/contents/VERSION" --jq '.content' 2>/dev/null \
        | base64 -d 2>/dev/null || echo "")
      if [[ -n "$version_content" ]]; then
        echo -e "${BOLD}VERSION${NC} ${DIM}(from $ORG/$repo)${NC}"
        break
      fi
    done
  fi

  if [[ -z "$version_content" ]]; then
    echo -e "${YELLOW}No VERSION file found in current directory or org repos.${NC}"
    return
  fi

  echo "$version_content"
}

cmd_ready() {
  require_project
  local version="${1:-}"
  if [[ -z "$version" ]]; then
    echo -e "${RED}Usage: pm.sh ready <version>${NC}" >&2
    exit 1
  fi

  local items
  items=$(fetch_project_items)

  local total done remaining
  total=$(echo "$items" | jq -r --arg v "$version" '[.items[] | select(.milestone.title == $v)] | length')
  done=$(echo "$items" | jq -r --arg v "$version" '[.items[] | select(.milestone.title == $v and .status == "Done")] | length')
  remaining=$((total - done))

  echo -e "${BOLD}Release Readiness: ${CYAN}$version${NC}"
  echo ""
  echo -e "  Total items:     $total"
  echo -e "  Done:            ${GREEN}$done${NC}"
  echo -e "  Remaining:       ${RED}$remaining${NC}"
  echo ""

  if [[ "$remaining" -eq 0 && "$total" -gt 0 ]]; then
    echo -e "  ${GREEN}${BOLD}✓ READY TO SHIP${NC}"
  else
    echo -e "  ${YELLOW}${BOLD}✗ NOT READY${NC}"
    echo ""
    echo -e "  ${BOLD}Remaining items:${NC}"
    echo "$items" | jq -r --arg v "$version" '
      .items
      | map(select(.milestone.title == $v and .status != "Done"))
      | .[]
      | "    - [\(.content.repository // .repository | split("/") | .[-1])] \(.title)" +
        if .content.number then " (#\(.content.number))" else "" end'
  fi
}

cmd_stale() {
  require_org

  echo -e "${BOLD}Stale Work Scanner${NC} ${DIM}($ORG)${NC}"
  echo ""

  # Get all org repos
  local repos
  repos=$(gh repo list "$ORG" --json name -q '.[].name' --limit 100 2>/dev/null)

  for repo in $repos; do
    local full_repo="$ORG/$repo"

    # Open PRs with no activity in 7+ days
    local stale_prs
    stale_prs=$(gh pr list --repo "$full_repo" --state open --json number,title,updatedAt,author,headRefName \
      --jq "[.[] | select(.updatedAt < \"$(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-7d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)\")] | .[]" 2>/dev/null || echo "")

    if [[ -n "$stale_prs" ]]; then
      echo -e "  ${CYAN}$repo${NC} — Stale PRs (no activity 7+ days):"
      echo "$stale_prs" | jq -r '"    PR #\(.number): \(.title) (branch: \(.headRefName), last: \(.updatedAt[:10]))"' 2>/dev/null
    fi

    # Branches with no PR
    local branches
    branches=$(gh api "repos/$full_repo/branches" --jq '.[].name' --paginate 2>/dev/null || echo "")
    for branch in $branches; do
      if [[ "$branch" == "main" || "$branch" == "master" || "$branch" == "develop" ]]; then
        continue
      fi
      local has_pr
      has_pr=$(gh pr list --repo "$full_repo" --head "$branch" --state all --json number --jq 'length' 2>/dev/null || echo "0")
      if [[ "$has_pr" == "0" ]]; then
        echo -e "  ${CYAN}$repo${NC} — Orphan branch: ${YELLOW}$branch${NC} (no PR)"
      fi
    done
  done
}

cmd_gaps() {
  require_project

  echo -e "${BOLD}Gap Analysis: Board vs Reality${NC} ${DIM}($ORG, project #$PROJECT_NUMBER)${NC}"
  echo ""

  local items
  items=$(fetch_project_items)

  # Extract all issues from the project board
  local issues
  issues=$(echo "$items" | jq -c '
    .items[]
    | select(.content.type == "Issue")
    | {
        number: .content.number,
        title: .title,
        status: .status,
        repo: (.content.repository // .repository | split("/") | .[-1]),
        full_repo: (.content.repository // .repository | ltrimstr("https://github.com/")),
        milestone: (.milestone.title // "none"),
        url: .content.url
      }')

  local found_gap=false

  # Check each issue
  while IFS= read -r issue; do
    [[ -z "$issue" ]] && continue

    local number repo full_repo status title milestone
    number=$(echo "$issue" | jq -r '.number')
    repo=$(echo "$issue" | jq -r '.repo')
    full_repo=$(echo "$issue" | jq -r '.full_repo')
    status=$(echo "$issue" | jq -r '.status')
    title=$(echo "$issue" | jq -r '.title')
    milestone=$(echo "$issue" | jq -r '.milestone')

    # Find linked PRs for this issue
    local linked_prs
    linked_prs=$(gh pr list --repo "$full_repo" --state all --search "$number" \
      --json number,state,mergedAt,title,headRefName \
      --jq "[.[] | select(.title | test(\"#?${number}[^0-9]\") or test(\"#?${number}$\"))]" 2>/dev/null || echo "[]")

    local pr_count
    pr_count=$(echo "$linked_prs" | jq 'length' 2>/dev/null || echo "0")

    # GAP: Issue marked Done but no merged PR
    if [[ "$status" == "Done" && "$pr_count" -gt 0 ]]; then
      local merged_count
      merged_count=$(echo "$linked_prs" | jq '[.[] | select(.state == "MERGED")] | length' 2>/dev/null || echo "0")
      if [[ "$merged_count" == "0" ]]; then
        echo -e "  ${RED}DRIFT${NC} [$repo] #$number: \"$title\" — marked Done but no merged PR"
        found_gap=true
      fi
    fi

    # GAP: Issue in Backlog but has a merged PR
    if [[ "$status" == "Backlog" && "$pr_count" -gt 0 ]]; then
      local merged_count
      merged_count=$(echo "$linked_prs" | jq '[.[] | select(.state == "MERGED")] | length' 2>/dev/null || echo "0")
      if [[ "$merged_count" -gt 0 ]]; then
        echo -e "  ${YELLOW}STALE${NC} [$repo] #$number: \"$title\" — still in Backlog but has merged PR"
        found_gap=true
      fi
    fi

    # GAP: Issue has open PR with no recent activity (abandoned work)
    if [[ "$pr_count" -gt 0 ]]; then
      local open_stale
      open_stale=$(echo "$linked_prs" | jq -r --arg cutoff "$(date -u -d '14 days ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-14d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" \
        '[.[] | select(.state == "OPEN")] | .[] | .number' 2>/dev/null || echo "")
      if [[ -n "$open_stale" ]]; then
        for pr_num in $open_stale; do
          echo -e "  ${YELLOW}ABANDONED?${NC} [$repo] #$number: \"$title\" — has open PR #$pr_num"
          found_gap=true
        done
      fi
    fi

    # GAP: Issue has no PR and no branch at all
    if [[ "$pr_count" == "0" && "$status" != "Done" && "$status" != "Backlog" ]]; then
      echo -e "  ${DIM}NO WORK${NC} [$repo] #$number: \"$title\" ($milestone) — no PR or branch found"
      found_gap=true
    fi

  done <<< "$issues"

  # Also find PRs that reference no project issue (orphan PRs)
  echo ""
  echo -e "${BOLD}Orphan PRs (not linked to project issues)${NC}"

  local issue_numbers
  issue_numbers=$(echo "$items" | jq -r '.items[] | select(.content.type == "Issue") | .content.number' | sort -u)

  local org_repos
  org_repos=$(echo "$items" | jq -r '.items[].content.repository // .items[].repository' | sort -u | sed 's|https://github.com/||')

  for full_repo in $org_repos; do
    [[ -z "$full_repo" ]] && continue
    local repo_name
    repo_name=$(echo "$full_repo" | cut -d'/' -f2)

    local open_prs
    open_prs=$(gh pr list --repo "$full_repo" --state open --json number,title,headRefName 2>/dev/null || echo "[]")

    echo "$open_prs" | jq -c '.[]' 2>/dev/null | while IFS= read -r pr; do
      local pr_title pr_num pr_branch
      pr_title=$(echo "$pr" | jq -r '.title')
      pr_num=$(echo "$pr" | jq -r '.number')
      pr_branch=$(echo "$pr" | jq -r '.headRefName')

      # Check if this PR references any known issue
      local linked=false
      for inum in $issue_numbers; do
        if echo "$pr_title $pr_branch" | grep -qE "(#|^)${inum}([^0-9]|$)"; then
          linked=true
          break
        fi
      done

      if [[ "$linked" == "false" ]]; then
        echo -e "  ${YELLOW}ORPHAN${NC} [$repo_name] PR #$pr_num: \"$pr_title\" (branch: $pr_branch)"
      fi
    done
  done

  if [[ "$found_gap" == "false" ]]; then
    echo ""
    echo -e "  ${GREEN}No gaps detected — board matches reality.${NC}"
  fi
}

cmd_help() {
  cat <<'HELP'
pm.sh — GitHub Project Management CLI

Usage: pm.sh [--org <org>] [--project <num>] [--repo <owner/repo>] <command> [args]

Commands:
  status              Overall project status (milestones, repos, progress)
  milestone <version> Items in a specific milestone with progress
  repos               Breakdown of all items by repository
  versions            Read VERSION file (current dir or org repos)
  ready <version>     Check if a milestone is ready to ship
  stale               Find stale PRs and orphan branches across org
  gaps                Reconcile board state vs actual repo state
  help                Show this help

Context:
  Automatically discovers org and project from the current git repo.
  Override with --org, --project, or --repo flags.

Examples:
  pm.sh status
  pm.sh milestone v0.5.0
  pm.sh ready v0.4.0
  pm.sh gaps --org myorg --project 1
  pm.sh stale --org myorg
HELP
}

# ─── Main ─────────────────────────────────────────────────────────────

main() {
  REMAINING_ARGS=()
  discover_context "$@"
  set -- "${REMAINING_ARGS[@]}"

  local command="${1:-help}"
  shift || true

  case "$command" in
    status)    cmd_status "$@" ;;
    milestone) cmd_milestone "$@" ;;
    repos)     cmd_repos "$@" ;;
    versions)  cmd_versions "$@" ;;
    ready)     cmd_ready "$@" ;;
    stale)     cmd_stale "$@" ;;
    gaps)      cmd_gaps "$@" ;;
    help|--help|-h) cmd_help ;;
    *)
      echo -e "${RED}Unknown command: $command${NC}" >&2
      echo "Run 'pm.sh help' for usage." >&2
      exit 1
      ;;
  esac
}

main "$@"
