# oh-my-claudecode — repo instructions

This repository **is** a Claude Code plugin. It ships an agent roster, skills,
hooks and an output style. These notes are for working *on* the plugin; the
orchestration protocol the plugin delivers to its users lives in
`output-styles/oh-my-claudecode.md`.

## Layout

Everything is at the plugin root — never inside `.claude-plugin/`, which holds
only the two manifests.

```
.claude-plugin/plugin.json       # identity + version
.claude-plugin/marketplace.json  # so this repo is its own marketplace
agents/                          # 13 subagent definitions
skills/<name>/SKILL.md           # 7 skills
hooks/hooks.json                 # event wiring
hooks/*.sh                       # hook scripts
output-styles/                   # the orchestration protocol
scripts/pm.sh                    # project-board CLI used by the gh-* skills
```

## Rules that keep breaking if you forget them

- **Agents use `tools:`**, not `allowed-tools:`. `allowed-tools:` is silently
  ignored on a subagent, so the agent quietly gets every tool.
- **Skills use `allowed-tools:`, and it GRANTS rather than restricts.** A bare
  `Bash` entry pre-approves every shell command for that turn. Always narrow to
  patterns, e.g. `Bash(gh *)`.
- **`outputStyle` in settings takes a style *name*, never a path.**
- **Reference bundled files with `${CLAUDE_PLUGIN_ROOT}`**, never `$HOME/.claude`.
  It is substituted in skill bodies and hook commands, but *not* in agent bodies —
  have the agent defer to a skill instead.
- **Do not reintroduce agent teams.** Teammates return an idle notification rather
  than their output, so every consultative agent in this roster loses its result.
  Teammates cannot spawn teammates and only the main session can lead, so atlas —
  a subagent — can never be a lead. Parallelism here means several Agent calls in
  one message, plus `isolation: worktree` when workers write concurrently.
- **Hooks emit `hookSpecificOutput`**, not the legacy `{"decision": "block"}`.
- **A plugin's `output-styles/` does not register.** Verified on 2.1.235: an
  installed, enabled plugin's style never reaches the system prompt, even with
  `force-for-plugin: true`. `output-styles/oh-my-claudecode.md` is the canonical
  copy, but users must copy it into `~/.claude/output-styles/` themselves. Retest
  this on Claude Code upgrades — if it starts working, drop the manual step from
  the README.

## Agent capability fields

- **Read-only consultants carry `permissionMode: plan`**, not just a `tools:` list
  without Write. Verified: reports still return normally, writes are refused, and
  read-only Bash search still works. `prometheus` is the exception — it writes plans.
- **`skills:` preloads into the subagent's context** and is verified working, but a
  skill with `disable-model-invocation: true` cannot be preloaded. The test suite
  enforces both.
- **Autonomous loops get `maxTurns`.** `argus` loops until a PR is clean; without a
  bound that is unbounded spend.
- `effort` is set only where it earns it: `low` for explore, `high` for the deep
  reasoners. Everything else inherits the session.

## Verify before committing

```bash
claude plugin validate . --strict     # manifests + component schemas
bash tests/test-plugin-structure.sh   # layout, frontmatter, hook behaviour
```

Load the working tree in a real session without installing it:

```bash
claude --plugin-dir . 
```

## Drift checking

`claude plugin validate . --strict` plus `tests/test-plugin-structure.sh` are the
drift guard. The `cc-native` plugin was evaluated for this and **rejected**: its
`refresh-refs.py` runs on every SessionStart and, in its own words, is "POC scope
only — no TTL, no version compare, no atomic writes, no opt-out flag", silently
re-downloading nine files from GitHub each start. At 1 star and same-day commits
that is not something to wire into a global config. Re-evaluate if it matures.

## What the plugin cannot ship

Two gaps, both verified rather than assumed: a `permissions` block in a plugin's
`settings.json` is ignored, and a plugin's `output-styles/` never registers. Tested
through `--plugin-dir` and after a real marketplace install, on 2.1.235.

`configure.sh` fills exactly those two and nothing else. Do not let it grow back
into an installer: if it ever copies agents, skills or hooks into the config
directory, those copies shadow the plugin, which is the bug that made 1.x rot. The
suite asserts it creates no such directories.

Retest both gaps on Claude Code upgrades; if either closes, delete that half of the
script.

## Legacy

Pre-2.0 installed via `curl | bash` into `~/.claude`. `uninstall-legacy.sh`
removes what that installer put there; it never touches `settings.json`.
