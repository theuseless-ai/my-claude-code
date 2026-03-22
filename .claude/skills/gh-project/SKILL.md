---
name: gh-project
description: "Query GitHub Project boards, milestone status, gap analysis, stale work detection, and VERSION manifests using the pm.sh CLI.\nTRIGGER when: agent needs GitHub Project board data, milestone progress, release readiness checks, gap analysis, stale PR detection, or any project-level query.\nDO NOT TRIGGER when: agent is creating/deleting tags (use gh-release), monitoring CI runs (use gh-ci), or reviewing recent commit history (use gh-activity)."
allowed-tools:
  - Bash
  - Read
  - Grep
  - Glob
---

# gh-project — GitHub Project Board Queries

## Primary Tool: pm.sh

**ALWAYS prefer `$HOME/.claude/scripts/pm.sh` over raw `gh project` commands.** It is faster, cheaper, and handles context discovery automatically.

### Commands

| Command | Purpose | Example |
|---|---|---|
| `pm.sh status` | Overall project status: milestones, repos, progress | `$HOME/.claude/scripts/pm.sh status` |
| `pm.sh milestone <version>` | Items in a specific milestone with progress | `$HOME/.claude/scripts/pm.sh milestone v0.5.0` |
| `pm.sh repos` | Breakdown of all items by repository | `$HOME/.claude/scripts/pm.sh repos` |
| `pm.sh versions` | Read VERSION file (current dir or org repos) | `$HOME/.claude/scripts/pm.sh versions` |
| `pm.sh ready <version>` | Check if a milestone is ready to ship | `$HOME/.claude/scripts/pm.sh ready v0.4.0` |
| `pm.sh stale` | Find stale PRs and orphan branches across org | `$HOME/.claude/scripts/pm.sh stale` |
| `pm.sh gaps` | Reconcile board state vs actual repo state | `$HOME/.claude/scripts/pm.sh gaps` |

### Context Flags

pm.sh auto-discovers org and project from the current git repo. Override when needed:

```bash
$HOME/.claude/scripts/pm.sh --org <org> --project <num> status
$HOME/.claude/scripts/pm.sh --repo <owner/repo> versions
```

## When pm.sh Is Not Enough

For queries pm.sh does not cover, fall back to raw `gh` commands:

### Specific issue details

```bash
gh issue view <number> --repo <owner/repo>
```

### PR status for a specific issue

```bash
gh pr list --repo <owner/repo> --search "<issue number>" --state all
```

### Recent commits on a branch

```bash
gh api repos/<owner>/<repo>/commits --jq '.[0:5] | .[].commit.message'
```

### Tag listing

```bash
gh api repos/<owner>/<repo>/tags --jq '.[].name'
```

### Direct project item queries (advanced)

```bash
gh project item-list <project_number> --owner <org> --format json --limit 500
```

## Key Concepts

### Project milestones vs repo milestones

These are two independent scoping systems:
- **Repo milestone** (e.g., pipelit v0.4.0) tracks that repo's own release cycle
- **Project milestone** (e.g., project v0.5.0) tracks a cross-repo Program Increment

The same issue can correctly belong to repo milestone v0.4.0 AND project milestone v0.5.0. This is NOT a conflict. When reporting, always specify which milestone level you are referring to. Never merge or compare version numbers across these two levels.

### Issue state filtering

When building roadmaps, milestone summaries, or progress reports, **only count open issues**. Closed issues must not appear as remaining work. Use `--state open` (or equivalent filter) in all queries that feed into roadmap or status views.

### Board vs reality

When the project board and actual git history disagree, **trust reality** (git history) over the board. Use `pm.sh gaps` to detect discrepancies, then recommend specific board updates to fix them.
