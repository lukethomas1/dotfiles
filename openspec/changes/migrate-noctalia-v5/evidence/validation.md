# Pre-activation validation

- Baseline: `d6613a8`; implementation isolated in `feat/dotfiles-3nj.2-noctalia-v5`.
- `python3 scripts/test-desktop-shell.py`: passed native effective-preference,
  Niri, IPC vocabulary, package ownership, all five role boundaries, metadata
  exclusions, and full apply-twice state checks using temporary homes.
- `python3 scripts/validate-agentic-workflow.py`: installed kit passed all active
  acceptance/graph/spec/test-plan gates with the archive-discovery adapter.
- `openspec validate --all --strict`: six items passed, zero failures.
- `bash -n bootstrap.sh`, `git diff --check`, and official package-name resolution
  with `pacman -Sp noctalia`: passed.
- V4 JSON archive is byte-identical to the saved preferences in the baseline.
- Physical Niri binding declarations are identical before and after migration;
  only the Noctalia command strings and their reference comment change.
- Native v5 preview has one bar and wallpaper on each of DP-2, DP-3, HDMI-A-1.
  Its config validates without warnings and responds to native status IPC.
- No packages were installed or removed during implementation/validation.

## Workflow compatibility

Kit 0.1.0 counts `openspec/changes/archive/` as an active change; the project
adapter stages only active change metadata before invoking the unchanged kit.
The kit doctor sees empty OpenSpec version output through its Node subprocess
runner. Direct `openspec --version` reports 1.14.0 and strict validation passes;
no global tool was replaced or downgraded.

## Isolation location

The implementation worktree is inside the repository's ignored `.worktrees/`
directory to stay within this session's writable workspace. It remains a
separate Git branch/index; main's pre-existing user changes are untouched.
