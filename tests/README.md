# Tests

Plain bash scripts, no framework. Each is standalone and exits non-zero if any
assertion fails.

```bash
./tests/test-plugin-structure.sh  # run one
for t in tests/test-*.sh; do "$t" || exit 1; done   # run all
```

## Conventions

- One file per area under test, named `test-<thing>.sh`.
- Everything happens inside a `mktemp -d` sandbox removed on exit. A test must
  never touch the developer's real `~/.claude` or `~/.oh-my-claudecode` — tests
  that install things do so against a throwaway `--target`.
- Tests exercise the **working tree**, not `HEAD`, so uncommitted changes are
  covered. `claude plugin validate . --strict` is the companion check and runs
  against the same tree.
- Derive fixtures from repo contents (agent names, skill dirs) rather than
  hardcoding them, so renames don't break the suite.
- Requires `git` and `jq`. The `--uninstall` test additionally needs `script`
  for a pty (it prompts on `/dev/tty`); it skips itself if unavailable.
