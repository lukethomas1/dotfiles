# Desktop shell test plan

## Runtime ownership and startup

- Before editing the manifest: run `bash -n bootstrap.sh`, `git diff --check`,
  and `pacman -Sp noctalia`. Use the current source as the baseline.
- Inspect the rendered Arch package plan: one native Noctalia declaration and no
  legacy shell/runtime declarations. Run no installation as part of validation.
- Confirm autostart has exactly one native shell command and no legacy command.

## Keyboard actions

- Compare all existing Noctalia bindings with `noctalia msg --help` and the native
  command argument help. Assert no legacy IPC command remains in active Niri.
- Validate the complete rendered Niri configuration with its native validator.
- Compare physical chords and non-Noctalia actions with the initial worktree,
  including the pre-existing OpenWhispr changes. Do not invoke lock, shutdown,
  suspend, or volume-changing commands during automated validation.

## Saved choices

- Run `noctalia config validate` against rendered TOML in isolated config/state
  roots. Require no unknown keys or warnings.
- Export its effective config and check every row of the design mapping.
- In the user-approved live preview, inspect compositor layers and native status:
  exactly one bar and wallpaper per active monitor, with no duplicate runtime.
- Safely toggle launcher and session panels, then close them. Validate destructive
  session actions by command vocabulary only. Ask the user to review the visible
  v5 layout before final activation.

## Persistence and profile boundaries

- Render each of the five roles into isolated Chezmoi destinations, with secrets
  and hooks disabled; confirm only Arch receives native Noctalia TOML.
- Apply twice in isolation and compare files, permissions, links, and directories.
- Confirm archived JSON, OpenSpec, and workflow metadata never enter managed
  destinations. Review any new top-level paths against the ignore policy.
- Preserve v4 JSON byte-for-byte in the archive. Preserve and document live native
  GUI overrides, and back up each targeted desktop file before activation.

## Delivery

- Run strict OpenSpec validation and the project workflow validator before Beads
  dispatch and before integration. Record tool compatibility failures explicitly.
- Commit the isolated implementation, obtain an independent review, and integrate
  only after the review and capability checks pass.
- After authorized targeted activation, repeat compositor-layer and native IPC
  checks. The operator's next normal login verifies reboot persistence; the agent
  does not trigger the reboot.
