# oh-my-claudecode

Multi-agent orchestration system for Claude Code, inspired by [oh-my-openagent](https://github.com/code-yeongyu/oh-my-openagent).

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/theuseless-ai/my-claude-code/main/install.sh | bash
```

That's it. Agents, hooks, skills, status line, and Context7 MCP — all installed globally.

```bash
# Update to latest
curl -fsSL https://raw.githubusercontent.com/theuseless-ai/my-claude-code/main/install.sh | bash -s -- --update

# Remove files this repo no longer ships (see "Pruning" below)
curl -fsSL https://raw.githubusercontent.com/theuseless-ai/my-claude-code/main/install.sh | bash -s -- --prune

# Uninstall (preserves your settings.json)
curl -fsSL https://raw.githubusercontent.com/theuseless-ai/my-claude-code/main/install.sh | bash -s -- --uninstall

# Clean install (wipes the target dir entirely, backs up first)
curl -fsSL https://raw.githubusercontent.com/theuseless-ai/my-claude-code/main/install.sh | bash -s -- --clean
```

### Pruning

`--update` only ever adds and overwrites files. When an agent or skill is deleted
from this repo, the copy already installed in `~/.claude` stays there — Claude Code
keeps loading a stale agent long after it was removed upstream. `--prune` cleans
those up:

```bash
./install.sh --prune --dry-run   # list what would go, remove nothing
./install.sh --prune             # remove them (asks first)
./install.sh --update --prune    # pull and prune in one pass
```

A plain `--update` never deletes anything; it just tells you how many orphans it
found so you can decide.

Prune is deliberately conservative:

- Only files the installer itself put there are candidates. It tracks these in a
  `.manifest.owned` ledger next to the manifest, so your own agents and skills in
  `~/.claude` are never touched.
- `.mcp.json`, `settings.json`, and `settings.local.json` are never pruned — they
  are merged with your own config, so deleting them would take your data with them.
- Everything removed is copied to `~/.oh-my-claudecode/.pruned.<timestamp>/` first.
- `--dry-run` changes nothing at all, so the preview and the real run agree.

`--yes` skips the confirmation prompt (needed for non-interactive use).

### Custom install location

By default everything installs to `~/.claude`. To install into a different config
directory — handy when you run multiple Claude Code profiles behind shell aliases —
point the installer at it. Target precedence is `--target <dir>` > `$CLAUDE_CONFIG_DIR` > `~/.claude`:

```bash
# Explicit target (clone the repo first, or run your local ~/.oh-my-claudecode/install.sh)
./install.sh --update --target ~/.claude_work

# Or via the same env var Claude Code itself honours — no flag needed
CLAUDE_CONFIG_DIR=~/.claude_work ./install.sh --update
```

Each non-default target gets its own manifest, so installs to different directories
never clobber each other's uninstall records. This pairs naturally with an alias like:

```bash
alias claude_work="CLAUDE_CONFIG_DIR=~/.claude_work claude --agent sisyphus"
```

## What This Is

A set of Claude Code native configurations (agents, skills, hooks, MCP servers) that replicate the multi-agent orchestration workflow from oh-my-openagent — adapted for Claude Code's primitives.

## Agent Roster

| Agent | Role | Model | Mode |
|---|---|---|---|
| **Sisyphus** | Main orchestrator — classifies intent, delegates to specialists | opus | Orchestrator |
| **Hephaestus** | Autonomous deep implementation — complex multi-file work | fable | Worker |
| **Oracle** | Architecture advisor, debugging expert | fable | Read-only |
| **Librarian** | Documentation & library research via Context7 | sonnet | Read-only |
| **Explore** | Fast codebase search specialist | haiku | Read-only |
| **Atlas** | Plan executor — dispatches tasks wave-by-wave | opus | Orchestrator |
| **Prometheus** | Strategic planner — creates dependency-aware work plans | fable | Planner |
| **Metis** | Pre-planning consultant — classifies intent, finds ambiguities | sonnet | Analyst |
| **Momus** | Plan reviewer — verifies executability, catches blockers | sonnet | Reviewer |
| **Multimodal Looker** | PDF/image/diagram analysis | sonnet | Reader |
| **Sisyphus Junior** | Focused implementation worker for scoped tasks | sonnet | Worker |
| **Argus** | Autonomous PR review fixer — triages AI reviews, fixes CI, loops until clean | sonnet | Worker |
| **Hermes** | Project manager — milestones, priorities, release readiness, cutting releases | sonnet | Manager |

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

## Skills

- `/playwright` — Browser automation and E2E testing
- `/git-master` — Advanced git workflows (atomic commits, rebase, bisect)
- `/frontend-ui-ux` — Design-first UI development with accessibility

## Hooks

- **write-existing-file-guard** — Blocks Write on existing files, forces Edit
- **non-interactive-env** — Blocks interactive TUI commands (vim, less, etc.)
- **context-preserver** — Preserves active plan state during context compaction

## MCP Servers

- **Context7** — Official documentation lookup for libraries/frameworks

## Usage

### As Default Orchestrator

Run Claude Code with Sisyphus as the default agent:
```bash
claude --agent sisyphus
```

### Invoke Specific Agents

Use agent names in conversation:
```
> Use explore to find all authentication-related files
> Ask oracle about the tradeoffs of this database design
> Have prometheus create a plan for the new feature
```

### Use the Planning Pipeline

For complex work:
```
> Plan the implementation of [feature]
```
This triggers: metis → prometheus → momus → atlas

## Directory Structure

```
.claude/
├── agents/          # 12 agent definitions
├── skills/          # 3 skill definitions
├── hooks/           # Hook scripts
└── settings.json    # Hook wiring
.mcp.json            # MCP server config
.sisyphus/
├── plans/           # Work plans (created by prometheus)
├── drafts/          # Draft plans
└── notepads/        # Shared context between tasks
CLAUDE.md            # Orchestration protocol
```

## Credits

Inspired by [oh-my-openagent](https://github.com/code-yeongyu/oh-my-openagent) by [@code-yeongyu](https://github.com/code-yeongyu).
