# oh-my-claudecode

Multi-agent orchestration for Claude Code: a roster of 13 specialist agents behind an
intent-classification gate, plus a plan → review → execute pipeline. Inspired by
[oh-my-openagent](https://github.com/code-yeongyu/oh-my-openagent).

## Install

Two routes to the same result. Use the first if you are sitting in a Claude Code
session; use the second if you are scripting it, or if you are an agent doing this
on someone's behalf.

### In a Claude Code session

```
/plugin marketplace add theuseless-ai/my-claude-code
/plugin install oh-my-claudecode@oh-my-claudecode
```

Then clone the repo and run `./configure.sh` (see [Configure](#configure) below).

### From the shell — scripted, or for an agent

Every step is non-interactive. Copy the block as-is:

```bash
# 1. Register the marketplace and install the plugin
claude plugin marketplace add theuseless-ai/my-claude-code
claude plugin install oh-my-claudecode@oh-my-claudecode --yes

# 2. Apply the config the plugin cannot carry (see Configure below)
git clone https://github.com/theuseless-ai/my-claude-code
cd my-claude-code
./configure.sh --yes

# 3. Confirm
claude plugin list
```

`claude plugin list` should show `oh-my-claudecode@oh-my-claudecode` with
`Status: ✔ enabled`. `claude plugin details oh-my-claudecode` prints the component
inventory — expect 13 agents, 7 skills and 2 hook events.

Agents installing this for a user: run `./configure.sh --dry-run` first and show the
output. It reports every settings change before making it, and it writes to the
user's `settings.json`, so it deserves a look rather than a blind `--yes`.

To target a config directory other than `~/.claude`, set `CLAUDE_CONFIG_DIR` — both
`claude` and `configure.sh` honour it — or pass `./configure.sh --target DIR`.

### Trying it without installing

```bash
claude --plugin-dir /path/to/my-claude-code          # load the working tree
./tests/sandbox.sh --configure --agent sisyphus      # ...in a disposable config dir
```

`tests/sandbox.sh` points `CLAUDE_CONFIG_DIR` at a temp directory, so nothing in
your real `~/.claude` is read or written. That isolation matters if you have a 1.x
install still present — see below.

## Configure

Two pieces of config **cannot** travel inside a plugin, verified against Claude
Code 2.1.235 and not retested since:

| | Why a plugin can't ship it |
|---|---|
| Permission rules | A plugin's `settings.json` honours only `agent` and `subagentStatusLine`; a `permissions` block in it is silently ignored — confirmed both through `--plugin-dir` and after a real marketplace install |
| The status line | `statusLine` is not among the keys a plugin's `settings.json` honours |

A third gap, the output style, closed on 2.1.263: the plugin's copy registers on
its own because it sets `force-for-plugin: true`. `configure.sh` no longer copies
it, and removes a copy left by an earlier run once the installed plugin carries the
flag (a user-level copy shadows the plugin's).

`./configure.sh` fills exactly those two:

```bash
./configure.sh --dry-run        # show every change, write nothing
./configure.sh                  # apply (asks first)
./configure.sh --yes            # apply without prompting
./configure.sh --revert         # undo exactly what it added
```

It writes the recommended permissions into your `settings.json`, and copies the
output style and status line into your config directory. It does **not** install
agents, skills or hooks — the plugin owns those, and a second copy in `~/.claude`
would shadow it. That is exactly what the pre-2.0 installer got wrong.

Your existing settings are preserved: permissions are unioned rather than replaced,
the file is backed up first, and a second run changes nothing. A `statusLine` you
already point somewhere else is never taken over — the script warns and skips. Pass
`--no-statusline` to skip the status line.

### Upgrading from 1.x

1.x installed itself into `~/.claude` with `curl | bash`. Those files still load and
will shadow the plugin, so clear them out first:

```bash
./uninstall-legacy.sh --dry-run   # see what would go
./uninstall-legacy.sh             # remove it (asks first)
```

It only removes files the old installer recorded as its own, and never touches
`settings.json` — it prints the leftover entries there for you to clean up by hand.

### Updating

```
/plugin update
```

or `claude plugin update oh-my-claudecode` from the shell. Re-run `./configure.sh`
after a `git pull` if the permissions or status line have changed; it is a no-op
when they haven't.

## Turning the orchestration on

The plugin does not change how Claude behaves until you ask it to. The reliable way
is to run the orchestrator as the main agent:

```bash
claude --agent sisyphus
```

Sisyphus carries the intent-classification gate and the delegation table, so routing
happens from the first message.

### Output style

The plugin ships it, and on Claude Code 2.1.263 or later it registers on its own
(the style sets `force-for-plugin: true`). Pick **oh-my-claudecode** under
`/config` and Output style. A copy left in `~/.claude/output-styles/` by an earlier
`configure.sh` shadows the plugin's; re-running `./configure.sh` removes it once the
installed plugin carries the flag.

On releases before 2.1.263 plugin-shipped styles do not register, so copy it by
hand and remove that copy again after upgrading:

```bash
mkdir -p ~/.claude/output-styles
cp output-styles/oh-my-claudecode.md ~/.claude/output-styles/
```

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
concurrently. Teams are deliberately not used — a teammate's report does not come
back to the caller as a tool result, which would silently break every agent in this
roster whose value is the report it returns.

Every agent nonetheless carries `SendMessage` and `ListAgents`, so any agent can
report to `main` mid-run, discover sibling agents and other Claude Code sessions,
and message them by name.

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

Two lines, installed by `configure.sh`:

```
[oh-my-claudecode]:main · Opus 5 / high
ctx ━━━━━━━━━───────── 47% · 5h ━━────── 32% 4h36m · 7d ────── 18% 3d10h
```

Line 1 is where you are and what's running it: project directory, branch,
model, and the current effort level when the session has one. Line 2 is
three labelled bars — context usage, then the 5-hour and 7-day rate-limit
windows with their reset countdowns. `ctx` always shows; the quota segments
are each dropped independently when their window isn't in the payload, and
line 2 itself is omitted entirely when there's nothing to show.

Bars are drawn with two box-drawing characters — `━` filled, `─` empty — no
background paint, no powerline caps, no frames. Colour is shared across every
bar and every reading: green below 70%, orange 70-89%, red at 90% and above.
Labels (`ctx`, `5h`, `7d`) and the `·` separators sit in a dim neutral grey.

The model name is shortened from `Opus 5 (1M context)` to `Opus 5 (1M)`. The
word adds nothing beside a size and costs eight columns on the tightest line.

The directory is what tells two concurrent sessions apart. When the cwd sits
below the project root the leaf is appended (`oh-my-cl…/agents`) and kept whole
under truncation — the project name is shortened around it, because truncating
left to right would drop the leaf and leave two sessions in one repo looking
identical.

The script emits no leading whitespace, so `statusLine.padding` in your settings
is the only thing that positions it. It is wired to `0`, which sits flush left;
raise it to indent. A padding you have already chosen is never overwritten.

Both lines are hard-capped at 80 printable columns, since the payload carries
no terminal width. Line 1 spends most of that on the project path (16 columns)
and the branch (up to what's left of 28); line 2's three bars are fixed at 18
cells for context and 8 cells each for the two quota windows — sized so that
the worst case (three 100% readings with the widest reset countdowns each
window can produce) still fits. Raise `DIR_MAX` or the bar widths in
`scripts/statusline.sh` if you run wider.

The script is pure ASCII plus the two box-drawing characters above — no Nerd
Font, no glyph fallback to configure.

`rate_limits` is only present for Claude.ai Pro/Max accounts, and only after the
first API response of a session. Each window can be absent independently; the
section is dropped when neither is available.

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
