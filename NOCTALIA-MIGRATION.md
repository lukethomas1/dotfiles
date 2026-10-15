# Noctalia v5 on Arch

The Arch profile uses the official `noctalia` package and native `noctalia msg`
commands. Niri starts the native shell once at login. Caps Lock remains the
window-manager modifier, and the physical launcher, lock, session, media, audio,
and brightness shortcuts retain their existing actions. Volume keys step by 5.

## Settings and GUI overrides

Chezmoi owns `~/.config/noctalia/config.toml`. Native Noctalia writes GUI changes
to `~/.local/state/noctalia/settings.toml`, which takes precedence over managed
TOML. Inspect that override file when a GUI change and the repository disagree.
To make new GUI choices reproducible, translate the desired values into the
managed TOML and remove only their redundant override entries after a backup.
Do not add the complete state directory to Chezmoi: it also contains app state.

The v4 JSON preferences are preserved at `archive/noctalia-v4/settings.json` and
excluded from deployment. The native shell does not read those preferences or
v4 plugins. Native Polkit support replaces the previous authentication plugin.

## Preserved choices and visible differences

The configuration keeps the floating top bar on all monitors, Catppuccin dark
palette, current cropped wallpaper, named workspace labels, disabled workspace
scrolling, inline tray, volume sounds, media visualizer, and CPU/temperature/RAM/
disk/network statistics. Clipboard history and telemetry remain disabled.

V5 has separate sysmon widgets for each statistic and a separate audio-visualizer
widget beside media. Their spacing and pill geometry differ from v4. UI sounds
use v5's global switch. The bottom dock uses v5's active-monitor filtering.
Session-menu shortcuts 1–7 retain lock, suspend, hibernate, reboot, logout,
shutdown, and firmware setup; hibernate and firmware setup use custom commands.
Power actions retain a ten-second countdown; locking is immediate.

The selected wallpaper is referenced under `~/Pictures/Wallpapers/`; the image
itself remains user-owned. If it is absent on another Arch host, select an image
there and update the managed path to reproduce that choice.

## Migration and recovery

Validate in isolated homes with `python3 scripts/test-desktop-shell.py` before
applying desktop changes. Back up current Noctalia and Niri files plus any native
GUI override file, then apply only the reviewed desktop targets. Check
`noctalia msg status` and `niri msg --json layers` after starting the shell.

Reverting startup alone cannot restore v4 on an upgraded Qt stack. A full v4
recovery requires the known-good system snapshot or a separately maintained
runtime repair. Keep the snapshot and user-file backups until a normal login
confirms the native desktop starts persistently.

Removing obsolete installed `noctalia-shell` and `noctalia-qs` packages is a
separate package-management decision. The manifest no longer requests them;
this migration does not automatically remove other packages or dependencies.
