---
name: gh-release
description: "Git tag and release management for GitHub repos: create/delete tags, cut release candidates (RC), promote RC to stable, read VERSION manifests.\nTRIGGER when: agent needs to create or delete git tags, promote an RC to stable, manage release candidates, read VERSION files for component version mapping, or execute any part of a release workflow.\nDO NOT TRIGGER when: agent is only querying CI status (use gh-ci), only reading project board data (use gh-project), or discussing releases without executing them."
allowed-tools:
  - Bash
  - Read
  - Grep
  - Glob
---

# gh-release — Git Tag & Release Management

## Safety Rules

- **ALWAYS confirm with the user before creating or deleting tags.** These are hard-to-reverse actions.
- **ALWAYS read the VERSION file first** before any release operation — it maps project versions to per-repo component versions.
- **NEVER create tags on the wrong commit** — verify the SHA before tagging.

## Reading the VERSION Manifest

The VERSION file maps the project-level version to per-repo component versions. Always start here.

```bash
# Using pm.sh (preferred — handles auto-discovery)
$HOME/.claude/scripts/pm.sh versions

# Direct file read (if in the correct repo)
cat VERSION
```

## Cutting a Release Candidate (RC)

Follow this sequence exactly:

### 1. Read the VERSION manifest

```bash
$HOME/.claude/scripts/pm.sh versions
```

### 2. Confirm versions with the user

Present the component versions and ask the user to confirm before proceeding. Example:
> "Based on VERSION, I'll tag these RCs:
> - repo-a: v0.4.0-rc.1
> - repo-b: v0.2.0-rc.1
> - project: v0.5.0-rc.1
> Proceed?"

### 3. Tag each component repo

For each component that changed since the last release:

```bash
# Get the HEAD commit SHA for the default branch
SHA=$(gh api repos/<org>/<repo>/commits/HEAD --jq '.sha')

# Create the RC tag
gh api repos/<org>/<repo>/git/refs \
  -f ref="refs/tags/v<version>-rc.1" \
  -f sha="$SHA"
```

### 4. Tag the project-level RC

```bash
# Tag the orchestration/project repo with the project version
gh api repos/<org>/<orchestration-repo>/git/refs \
  -f ref="refs/tags/v<project_version>-rc.1" \
  -f sha="<commit_sha>"
```

### 5. Monitor the release workflow

The release workflow typically triggers automatically on tag push. Hand off to CI monitoring (see gh-ci skill) or:

```bash
gh run list --repo <org>/<orchestration-repo> --limit 5
```

## Promoting RC to Stable

After the RC passes e2e tests:

### 1. Get the RC tag's commit SHA

```bash
SHA=$(gh api repos/<org>/<repo>/git/refs/tags/v<version>-rc.1 --jq '.object.sha')
```

### 2. Create the stable tag on the same commit

```bash
gh api repos/<org>/<repo>/git/refs \
  -f ref="refs/tags/v<version>" \
  -f sha="$SHA"
```

### 3. Clean up the RC tag (optional)

```bash
gh api repos/<org>/<repo>/git/refs/tags/v<version>-rc.1 -X DELETE
```

**Repeat for each component repo and the project repo.**

## Deleting a Tag

If an RC needs to be abandoned:

```bash
gh api repos/<org>/<repo>/git/refs/tags/v<version>-rc.1 -X DELETE
```

## Listing Tags

```bash
gh api repos/<org>/<repo>/tags --jq '.[].name'
```

## Key Concepts

- **RC tags** use the format `v<version>-rc.<N>` (e.g., `v0.5.0-rc.1`)
- **Stable tags** use the format `v<version>` (e.g., `v0.5.0`)
- **Promoting** means creating a stable tag on the exact same commit as the RC — no rebuild, no re-test
- **VERSION file** is the source of truth for which component version maps to which project version
