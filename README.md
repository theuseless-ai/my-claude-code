# oh-my-claudecode

Multi-agent orchestration for Claude Code: a roster of 13 specialist agents behind an
intent-classification gate, plus a plan → review → execute pipeline. Inspired by
[oh-my-openagent](https://github.com/code-yeongyu/oh-my-openagent).

## Install

```
/plugin marketplace add theuseless-ai/oh-my-claudecode
/plugin install oh-my-claudecode@oh-my-claudecode
```

Agents, skills and hooks load on the next session. Update with `/plugin update`.

Then run the configure script once. Two pieces of config **cannot** travel in a
plugin, verified against Claude Code 2.1.235 both through `--plugin-dir` and after
a real marketplace install:

| | Why a plugin can't ship it |
|---|---|
| Permission rules | A plugin's `settings.json` honours only `agent` and `subagentStatusLine`; a `permissions` block in it is silently ignored |
| The output style | A plugin's `output-styles/` never registers, with or without `force-for-plugin` |

```bash
git clone https://github.com/theuseless-ai/oh-my-claudecode
cd oh-my-claudecode
./configure.sh --dry-run   # show exactly what would change
./configure.sh             # apply (asks first)
```

It writes the recommended permissions into your `settings.json` and copies the
output style into your config directory. It does **not** install agents, skills or
hooks — the plugin owns those, and a second copy in `~/.claude` would shadow it.
That is exactly what the pre-2.0 installer got wrong.

Your existing settings are preserved: permissions are unioned rather than replaced,
the file is backed up first, and a second run changes nothing. `./configure.sh
--revert` removes exactly what it added and leaves your own rules alone. Pass
`--no-style` for permissions only.

To try the working tree without installing:

```bash
claude --plugin-dir /path/to/oh-my-claudecode
```

### Upgrading from 1.x

1.x installed itself into `~/.claude` with `curl | bash`. Those files still load
and will shadow the plugin, so clear them out first:

```bash
./uninstall-legacy.sh --dry-run   # see what would go
./uninstall-legacy.sh             # remove it (asks first)
```

It only removes files the old installer recorded as its own, and never touches
`settings.json`.

## Turning the orchestration on

The plugin does not change how Claude behaves until you ask it to. The reliable way
is to run the orchestrator as the main agent:

```bash
claude --agent sisyphus
```

Sisyphus carries the intent-classification gate and the delegation table, so routing
happens from the first message.

### Output style

`configure.sh` installs it. If you skipped that or used `--no-style`, copy it by
hand — plugin-shipped output styles do not register:

```bash
mkdir -p ~/.claude/output-styles
cp output-styles/oh-my-claudecode.md ~/.claude/output-styles/
```

Then pick **oh-my-claudecode** under `/config` and Output style.

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

## Permissions

`configure.sh` writes these. The deny syntax is worth knowing if you edit them:
`Bash(cmd *)` and `Bash(cmd:*)` both match, but `Bash(cmd)*` — with the star outside
the parentheses — silently matches nothing.

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
