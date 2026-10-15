# Permanent desktop activation

Activated 2026-10-15 UTC after independent review of `b71b0d5` and integration
through `93675b9`.

## Backup and scope

Persistent backup:
`/home/bytewalker/.local/state/chezmoi-backups/noctalia-v5-20261015T035541Z/`.
Its `manifest.json` records original presence and SHA-256 hashes. It contains the
original Niri files, v4 preferences, copied preview GUI settings/state, and the
native activation log. Native config and state did not previously exist at their
normal home paths.

Applied only these targets with scripts and encrypted entries excluded:

- `~/.config/noctalia/config.toml`
- `~/.config/niri/cfg/autostart.kdl`
- `~/.config/niri/cfg/keybinds.kdl`

The temporary native preview was terminated by its verified PID. Its two small
GUI settings/state files were preserved in `~/.local/state/noctalia/`; caches,
history, and downloaded templates were not copied. The replacement native
daemon uses normal home paths, without temporary config/state/cache overrides.
No packages, reboot, bootstrap, global apply, or remote push were performed.

## Results

- Applied TOML validates without warnings; complete live Niri config validates.
- Chezmoi verification passes for all three targeted files.
- Exactly one native daemon runs (PID 35170 at activation); no legacy `qs` runs.
- Exactly one native bar and wallpaper exists on each of DP-2, DP-3, HDMI-A-1.
- Effective live config passes the saved-preference assertions from the desktop
  harness, including Catppuccin, workspace choices, tray, audio, privacy, and
  disabled setup wizard.
- Launcher and session panels each open and close through native IPC. Final
  status reports visible bar, no open panel, and unlocked session. No lock,
  volume-changing, suspend, or power action was invoked.
- The initial environment assertion also rejected Noctalia's own daemon pipe
  bookkeeping variable; checking only path overrides passes. The initial panel
  close assertion ran before animation completion; bounded transition polling
  passes. Neither required a desktop configuration change.

## Preserved local work

Main retains the pre-existing uncommitted changes: `KEYBINDINGS.md` (4/3 lines),
`OPENWHISPR-NIRI.md` (7/5), Niri keybinds (2/1), desktop package manifest (1/0),
and the untracked OpenWhispr toggle wrapper. They are excluded from migration
commits. Nothing under `~/Projects/opengrill` was changed by this migration.

## Operator follow-up

The next normal login must confirm automatic startup persists. No reboot was
triggered to perform that check. Keep the recovery snapshot and backup until
that login succeeds. The OpenSpec change remains active pending that feedback;
Beads delivery includes recording this follow-up rather than forcing a reboot.
