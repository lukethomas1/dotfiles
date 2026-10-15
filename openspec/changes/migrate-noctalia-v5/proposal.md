# Proposal

## Why

The Arch desktop still launches Noctalia v4 through Quickshell. The October 14
upgrade installed native Noctalia v5 sources as `noctalia-shell` and upgraded Qt,
leaving that startup command unusable. The user selected migration to maintained
v5 with their saved desktop preferences carried over.

## What Changes

- **BREAKING:** Replace the Arch `noctalia-shell`/`noctalia-qs` declarations with
  the official `noctalia` package and native startup/IPC commands.
- Translate saved v4 preferences to v5 TOML, preserving the bar layout, named
  workspaces, system statistics, inline tray, media visualizer, palette, wallpaper,
  fonts, dock, and existing physical shortcuts.
- Keep the v4 settings in the repository archive as a recovery reference.
- Document v5 GUI override precedence and any preference without an exact match.
- Preserve existing OpenSpec configuration while adding the missing workflow
  manifest/templates before executable Beads work is created.

## Capabilities

### New Capabilities

- `desktop-shell`: Arch Noctalia runtime ownership, startup, native IPC, saved
  preferences, profile boundaries, and migration recovery.

### Modified Capabilities

None. Existing managed-content and software-provisioning requirements already
cover package-manager ownership and desktop role exclusions.

## Impact

Arch changes affect the package manifest, Niri autostart/Noctalia command strings,
Noctalia configuration, archive exclusions, and desktop documentation. macOS,
Fedora, container, and debian-dev-headless retain their current managed targets;
they do not receive Noctalia TOML. Existing unrelated working-tree edits are
preserved. No kernel, bootloader, networking, secret, or homelab changes are in
scope. No root package removal or full system upgrade is required to preview
v5 because the native runtime is already installed.

## Non-goals

Maintain a fork of archived v4, pin or downgrade Qt, redesign window management,
change the Caps Lock modifier, replace the login manager, or broaden the host
package baseline. Acceptance of this proposal does not authorize broad bootstrap
or Chezmoi apply operations.
