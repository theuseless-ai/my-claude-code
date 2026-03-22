---
name: gh-ci
description: "Monitor GitHub Actions workflows, check CI/CD status, read failure logs, wait for CI to pass.\nTRIGGER when: agent needs to check workflow run status, monitor a CI pipeline, read CI failure logs, wait for a workflow to complete, or diagnose a GitHub Actions failure.\nDO NOT TRIGGER when: agent is creating/deleting tags (use gh-release), querying project boards (use gh-project), or working with local test runners."
allowed-tools:
  - Bash
  - Read
  - Grep
  - Glob
---

# gh-ci — GitHub Actions Workflow Monitoring

## Listing Recent Workflow Runs

```bash
# List the 5 most recent runs for a repo
gh run list --repo <org>/<repo> --limit 5

# Structured output for programmatic use
gh run list --repo <org>/<repo> --limit 5 \
  --json status,conclusion,name,databaseId,headBranch,createdAt
```

## Checking a Specific Run

```bash
# View run details (status, jobs, duration)
gh run view <run_id> --repo <org>/<repo>

# View with job-level detail
gh run view <run_id> --repo <org>/<repo> --json status,conclusion,jobs
```

## Reading Failure Logs

When a run fails, get the failed job logs:

```bash
gh run view <run_id> --repo <org>/<repo> --log-failed
```

This outputs only the logs from failed steps, which is far more useful than the full log.

## Watching a Run in Real-Time

Block until a run completes:

```bash
gh run watch <run_id> --repo <org>/<repo>
```

This will stream status updates and exit when the run finishes. Useful after tagging an RC to wait for e2e results.

## Filtering Runs

```bash
# By workflow name
gh run list --repo <org>/<repo> --workflow "e2e-tests.yml" --limit 5

# By branch
gh run list --repo <org>/<repo> --branch main --limit 5

# By status
gh run list --repo <org>/<repo> --status failure --limit 5
```

## Interpreting Results

| Status | Meaning | Action |
|---|---|---|
| `completed` + `success` | All jobs passed | Safe to proceed (e.g., promote RC) |
| `completed` + `failure` | One or more jobs failed | Read logs with `--log-failed`, diagnose |
| `in_progress` | Still running | Wait with `gh run watch` or check back later |
| `queued` | Waiting for a runner | Normal — wait for it to start |
| `completed` + `cancelled` | Manually or automatically cancelled | Investigate why; may need re-trigger |

## Re-Running a Failed Workflow

```bash
# Re-run all failed jobs
gh run rerun <run_id> --repo <org>/<repo> --failed

# Re-run entirely
gh run rerun <run_id> --repo <org>/<repo>
```

## Common Patterns

### Wait for RC e2e then report

```bash
# Find the latest run triggered by the tag
RUN_ID=$(gh run list --repo <org>/<repo> --limit 1 \
  --json databaseId -q '.[0].databaseId')

# Watch it
gh run watch "$RUN_ID" --repo <org>/<repo>

# If it failed, get the logs
gh run view "$RUN_ID" --repo <org>/<repo> --log-failed
```

### Check if a branch is green

```bash
gh run list --repo <org>/<repo> --branch main --limit 1 \
  --json conclusion -q '.[0].conclusion'
```
