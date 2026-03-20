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

# Uninstall (preserves your settings.json)
curl -fsSL https://raw.githubusercontent.com/theuseless-ai/my-claude-code/main/install.sh | bash -s -- --uninstall

# Clean install (wipes ~/.claude/ entirely, backs up first)
curl -fsSL https://raw.githubusercontent.com/theuseless-ai/my-claude-code/main/install.sh | bash -s -- --clean
```

## What This Is

A set of Claude Code native configurations (agents, skills, hooks, MCP servers) that replicate the multi-agent orchestration workflow from oh-my-openagent — adapted for Claude Code's primitives.

## Agent Roster

| Agent | Role | Model | Mode |
|---|---|---|---|
| **Sisyphus** | Main orchestrator — classifies intent, delegates to specialists | opus | Orchestrator |
| **Hephaestus** | Autonomous deep implementation — complex multi-file work | opus | Worker |
| **Oracle** | Architecture advisor, debugging expert | opus | Read-only |
| **Librarian** | Documentation & library research via Context7 | sonnet | Read-only |
| **Explore** | Fast codebase search specialist | haiku | Read-only |
| **Atlas** | Plan executor — dispatches tasks wave-by-wave | opus | Orchestrator |
| **Prometheus** | Strategic planner — creates dependency-aware work plans | opus | Planner |
| **Metis** | Pre-planning consultant — classifies intent, finds ambiguities | sonnet | Analyst |
| **Momus** | Plan reviewer — verifies executability, catches blockers | sonnet | Reviewer |
| **Multimodal Looker** | PDF/image/diagram analysis | sonnet | Reader |
| **Sisyphus Junior** | Focused implementation worker for scoped tasks | sonnet | Worker |
| **Argus** | Autonomous PR review fixer — triages AI reviews, fixes CI, loops until clean | sonnet | Worker |

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
