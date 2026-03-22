---
name: gh-activity
description: "Review recent commit history across GitHub repos, correlate commits against roadmaps, classify work as on-roadmap/related/off-roadmap.\nTRIGGER when: agent needs recent commit history across repos, needs to correlate commits against a roadmap, needs to classify recent work, or user asks 'what happened recently' / 'catch me up'.\nDO NOT TRIGGER when: agent is only checking CI status (use gh-ci), only reading project board data (use gh-project), or looking at a single commit diff."
allowed-tools:
  - Bash
  - Read
  - Grep
  - Glob
  - Agent
---

# gh-activity — Recent Activity Review & Commit Classification

## Purpose

Review recent work across repos in a GitHub organization, classify each commit against the project roadmap, and identify what's next.

## Full Procedure

### Step 1: Discover repos in the project

```bash
$HOME/.claude/scripts/pm.sh repos
```

This returns all repos that have items on the project board.

### Step 2: Pull recent commits for each repo

For each repo discovered in step 1, get the last 5 commits on the default branch:

```bash
gh api repos/<org>/<repo>/commits?per_page=5 \
  --jq '.[] | "- " + .sha[0:7] + " " + (.commit.message | split("\n")[0])'
```

### Step 3: Load the roadmap

Read `ROADMAP.md` from each repo (if it exists) to get planned work items and their milestone assignments:

```bash
gh api repos/<org>/<repo>/contents/ROADMAP.md --jq '.content' 2>/dev/null | base64 -d
```

Also load the project board state for cross-referencing:

```bash
$HOME/.claude/scripts/pm.sh status
```

### Step 4: Classify each commit

Assign each commit to one of three categories:

| Category | Symbol | Criteria |
|---|---|---|
| **On roadmap** | `+` | Directly implements or closes a roadmap item. Look for issue refs like `#123` in commit messages, then match against roadmap items. |
| **Related** | `~` | Touches code in the same area as a roadmap item but doesn't close it. Examples: prep work, refactoring, dependency updates. |
| **Off roadmap** | `o` | Unrelated to any roadmap item. Examples: bug fixes, chores, ad-hoc work. |

### Step 5: Report

Present a table per repo:

```
<repo> (last 5 commits)
+ abc1234 feat: add API client gen (#17)        -> On roadmap (v0.5.0 -- item #17)
~ def5678 refactor: extract HTTP layer           -> Related (prep for item #17)
o 789abcd fix: typo in README                    -> Off roadmap
```

### Step 6: Suggest next step

Based on what was just completed, look at the roadmap for what is now unblocked or next in priority. Recommend the single most impactful next action with reasoning.

Example:
> "Now that #17 (API client gen) is merged, #18 (CLI integration) is unblocked. This is the last P0 item in v0.5.0 -- recommend starting it next."

## Fetching Commits with Date Filters

To get commits from a specific time range:

```bash
# Commits from the last 7 days
gh api "repos/<org>/<repo>/commits?since=$(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%SZ)&per_page=20" \
  --jq '.[] | "- " + .sha[0:7] + " " + (.commit.message | split("\n")[0])'
```

## Tips

- Use `explore` sub-agent to search codebases when you need to verify whether a commit is related to a roadmap item based on the files it touches.
- If a repo has no ROADMAP.md, fall back to the project board milestone data from `pm.sh milestone <version>`.
- When classifying, err on the side of "related" rather than "off roadmap" if there is any plausible connection.
