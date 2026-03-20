---
name: git-master
description: "Advanced git workflows: atomic commits, interactive rebase, history search, conflict resolution, cherry-pick, and branch management."
disable-model-invocation: true
allowed-tools:
  - Bash
  - Read
  - Grep
  - Glob
---

# Git Master — Advanced Git Workflows

## Atomic Commits

Each commit should represent ONE logical change:
- Separate refactoring from feature additions
- Separate formatting from behavior changes
- Each commit should compile and pass tests independently

```bash
# Stage specific hunks for atomic commits
git add -p file.ts
# Commit with descriptive message
git commit -m "feat(auth): add JWT refresh token rotation"
```

## Commit Message Format

```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

Types: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `perf`, `ci`

## History Search

```bash
# Search commit messages
git log --all --grep="keyword"

# Search code changes (pickaxe)
git log -S "function_name" --oneline

# Search with regex in diffs
git log -G "pattern" --oneline

# Find when a line was added/changed
git log -L :function_name:file.ts

# Blame with ignore whitespace
git blame -w file.ts
```

## Rebase Workflows

```bash
# Rebase onto latest main
git fetch origin && git rebase origin/main

# Squash last N commits
git rebase -i HEAD~N

# Rebase preserving merges
git rebase --rebase-merges origin/main
```

## Conflict Resolution

1. Identify conflicted files: `git status`
2. Read the conflict markers in each file
3. Understand BOTH sides before resolving
4. After resolving: `git add <file>` then `git rebase --continue`
5. Run tests after resolution

## Cherry-Pick

```bash
# Pick a specific commit
git cherry-pick <commit-hash>

# Pick without committing (stage only)
git cherry-pick --no-commit <commit-hash>

# Pick a range
git cherry-pick <start>..<end>
```

## Branch Management

```bash
# Clean up merged branches
git branch --merged main | grep -v main | xargs git branch -d

# Find branches containing a commit
git branch --contains <commit-hash>

# Compare branches
git log main..feature --oneline
```

## Bisect (Find Bug Introduction)

```bash
git bisect start
git bisect bad          # current commit is bad
git bisect good v1.0    # known good point
# Git checks out middle commits — test each one
git bisect good         # or git bisect bad
git bisect reset        # when done
```
