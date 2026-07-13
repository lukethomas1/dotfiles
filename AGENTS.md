# Dotfiles repository guidance

This repository is a Chezmoi source for a reproducible personal development
environment. Preserve that goal: host configuration should be small,
intentional, and safe to apply repeatedly.

## Profiles

- `macos`: macOS desktop profile, installed with Homebrew.
- `fedora`: Fedora COSMIC Atomic profile, with CLI tools installed through
  Linuxbrew.
- `arch`: CachyOS Niri/Noctalia host profile, installed through Shelly.
- `container`: Debian development-container profile. Never deploy secrets or
  SSH configuration to this profile.
- `debian-dev-headless`: durable Debian 13 developer-console profile. It owns
  secretless developer software and user configuration; homelab owns account,
  mount, network, DNS, SSH daemon, and trust configuration.

Chezmoi role and distro data are set in `.chezmoi.toml.tmpl`. Keep role-specific
template conditions consistent with bootstrap's exported `CHEZMOI_ROLE`.

## CachyOS host policy

`pkg/arch/pacman-desktop.txt` is an intentionally small host baseline: shell,
editor, Git, authentication, terminal UX, and Niri/Noctalia. Do not add
language runtimes, SDKs, container engines, project dependencies, kernels,
bootloaders, or unrelated desktop stacks without an explicit decision.

Use Shelly in `bootstrap.sh` for official packages and AUR packages. Keep AUR
dependencies minimal and declare them in `pkg/arch/aur-desktop.txt`.

## Desktop configuration

The active Arch desktop is Niri/Noctalia. The previous Hyprland configuration
is retained in `archive/cachyos-hyprland/` for reference and must remain
excluded from Chezmoi by `.chezmoiignore.tmpl`.

## Keybindings

**Read `KEYBINDINGS.md` before touching any keybinding file.** Niri (Arch) and
AeroSpace (macOS) are deliberately kept in sync, and the macOS side is full of
choices that look wrong until you know why:

- Caps Lock is the window-manager modifier on both hosts. On Arch it is a real
  modifier bit (XKB Mod3). macOS has no spare bit, so Karabiner makes Caps Lock
  impersonate **Alt+Cmd**. Ctrl and Shift are kept OUT of that chord on purpose —
  the popular "Hyper" recipe (`cmd-ctrl-alt-shift`) would collapse `Mod+Shift`
  into `Mod` and silently break the config.
- Ghostty's defaults are platform-conditional (Cmd on macOS, Ctrl on Linux), so
  the `super+…=unbind` lines are load-bearing on macOS and silent no-ops on
  Linux. One shared file, deliberately untemplated.
- `super+-` must use the literal character. `super+minus` parses as a
  physical-key trigger and unbinds nothing.

Do not "simplify" any of the above without reading the rationale first. Also
prefer checking processes and files over macOS status tools (`systemextensionsctl`,
`defaults read`) — see the troubleshooting section; they have each reported
confident falsehoods here.

## Secrets and safety

- Never commit decrypted secrets, private keys, or the Chezmoi Age identity.
- Keep encrypted files encrypted and retain the container and
  `debian-dev-headless` profile exclusions.
- Do not run `chezmoi apply`, install packages, or make system changes unless
  the user explicitly asks.
- Before changing bootstrap or package manifests, run `bash -n bootstrap.sh`,
  `git diff --check`, and resolve official Arch package names with `pacman -Sp`.
