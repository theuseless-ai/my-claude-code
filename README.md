# oh-my-claudecode

Multi-agent orchestration for Claude Code: a roster of 13 specialist agents behind an
intent-classification gate, plus a plan → review → execute pipeline. Inspired by
[oh-my-openagent](https://github.com/code-yeongyu/oh-my-openagent).

## Install

```
/plugin marketplace add theuseless-ai/oh-my-claudecode
/plugin install oh-my-claudecode@oh-my-claudecode
```

That's it — agents, skills and hooks load on the next session. Update with
`/plugin update`, and manage everything from `/plugin`.

To try the working tree without installing:

```bash
claude --plugin-dir /path/to/oh-my-claudecode
```

### Upgrading from 1.x

1.x installed itself into `~/.claude` with `curl | bash`. Those files still load
and will shadow the plugin, so clear them out first:

```bash
git clone https://github.com/theuseless-ai/oh-my-claudecode
cd oh-my-claudecode
./uninstall-legacy.sh --dry-run   # see what would go
./uninstall-legacy.sh             # remove it (asks first)
```

It only removes files the old installer recorded as its own, and never touches
`settings.json`. It will print the leftover `settings.json` entries to clean up by
hand — the old hook wiring and `statusLine`.

## Turning the orchestration on

The plugin does not change how Claude behaves until you ask it to. The reliable way
is to run the orchestrator as the main agent:

```bash
claude --agent sisyphus
```

Sisyphus carries the intent-classification gate and the delegation table, so routing
happens from the first message.

### Output style (manual step)

The same protocol is also packaged as an output style at
`output-styles/oh-my-claudecode.md`. **Plugin-shipped output styles do not currently
register** — verified on Claude Code 2.1.235, where an installed and enabled plugin's
style never reaches the system prompt, with or without `force-for-plugin`. Until that
changes, copy it to your own config to use it:

```bash
mkdir -p ~/.claude/output-styles
curl -fsSL https://raw.githubusercontent.com/theuseless-ai/oh-my-claudecode/main/output-styles/oh-my-claudecode.md \
  -o ~/.claude/output-styles/oh-my-claudecode.md
```

Then pick **oh-my-claudecode** under `/config` → Output style.

Without either step you still get every agent, skill and hook — you just invoke the
agents yourself rather than having Claude route to them.

## Agent Roster

| Agent | Role | Model | Mode |
|---|---|---|---|
| **Sisyphus** | Main orchestrator — classifies intent, delegates to specialists | opus | Orchestrator |
| **Hephaestus** | Autonomous deep implementation — complex multi-file work | fable | Worker |
| **Oracle** | Architecture advisor, debugging expert | fable | Read-only |
| **Librarian** | Documentation & library research via web fetch/search | sonnet | Read-only |
| **Explore** | Fast codebase search specialist | haiku | Read-only |
| **Atlas** | Plan executor — dispatches waves of parallel subagents | opus | Orchestrator |
| **Prometheus** | Strategic planner — creates dependency-aware work plans | fable | Planner |
| **Metis** | Pre-planning consultant — classifies intent, finds ambiguities | sonnet | Analyst |
| **Momus** | Plan reviewer — verifies executability, catches blockers | sonnet | Reviewer |
| **Multimodal Looker** | PDF/image/diagram analysis | sonnet | Reader |
| **Sisyphus Junior** | Focused implementation worker for scoped tasks | sonnet | Worker |
| **Argus** | Autonomous PR review fixer — triages AI reviews, fixes CI | sonnet | Worker |
| **Hermes** | Project manager — milestones, release readiness, cutting releases | sonnet | Manager |

## Architecture

```
User Message
    │
    ▼
Sisyphus (intent classification)
    │
    ├─► Research → explore + librarian (parallel)
    ├─► Complex Task → metis → prometheus → momus → atlas → workers
    ├─► Simple Task → sisyphus-junior
    ├─► Architecture → oracle (read-only)
    └─► Media → multimodal-looker
```

Parallel work is done with **subagent dispatch**, not agent teams: several Agent
calls in one message, plus `isolation: worktree` when workers write files
concurrently. Teams are deliberately not used — a teammate reports only an idle
notification, never its output, which would silently break every agent in this
roster whose value is the report it returns.

## Skills

Plugin skills are namespaced, so invoke them as `/oh-my-claudecode:<name>`.

| Skill | Purpose |
|---|---|
| `git-master` | Atomic commits, rebase, history search, conflict resolution |
| `playwright` | Browser automation and E2E testing |
| `frontend-ui-ux` | Design-first UI development with accessibility |
| `gh-ci` | Monitor GitHub Actions, read failure logs |
| `gh-project` | Project boards, milestones, gap analysis |
| `gh-release` | Tags, release candidates, RC → stable promotion |
| `gh-activity` | Recent commit history, roadmap correlation |

The `gh-*` skills auto-trigger; `git-master` and `playwright` are invoke-only.

## Hooks

| Hook | Event | Effect |
|---|---|---|
| `write-existing-file-guard` | `PreToolUse(Write)` | Blocks Write on an existing file, forcing Edit |
| `non-interactive-env` | `PreToolUse(Bash)` | Blocks TUI commands that would hang the session |
| `context-preserver` | `SessionStart` | Injects active `.sisyphus/` plan and notepad state |

## Recommended permissions

A plugin cannot ship permission rules, so add these to your own `settings.json` if
you want the roster to run without constant prompting:

```json
{
  "permissions": {
    "allow": [
      "Read", "Edit", "Write", "Glob", "Grep",
      "Bash(git *)", "Bash(gh *)", "Bash(jq *)", "Bash(rg *)",
      "Bash(npm *)", "Bash(npx *)", "Bash(node *)", "Bash(pytest *)",
      "Bash(go *)", "Bash(cargo *)", "Bash(make *)", "Bash(python3 *)"
    ],
    "deny": [
      "Bash(git push --force *)",
      "Bash(git push -f *)",
      "Bash(rm -rf /:*)",
      "Bash(rm -rf ~:*)",
      "Bash(chmod 777 *)"
    ]
  }
}
```

Note the deny syntax: `Bash(cmd *)` and `Bash(cmd:*)` both match, but `Bash(cmd)*`
— with the star outside the parentheses — silently matches nothing.

## Status line

Not shipped. The ecosystem does this better than we did — `claude-hud`, `cc-usage`,
`claude-gauge` and `claude-telemetry` all read rate limits and track agents, which
our old statusline never did.

## Development

See [CLAUDE.md](CLAUDE.md) for layout and the frontmatter rules that are easy to get
wrong. To verify a change:

```bash
claude plugin validate . --strict
bash tests/test-plugin-structure.sh
```

Tests are plain bash, no framework, and run entirely in a temp sandbox.

## Credits

Inspired by [oh-my-openagent](https://github.com/code-yeongyu/oh-my-openagent) by
[@code-yeongyu](https://github.com/code-yeongyu).
