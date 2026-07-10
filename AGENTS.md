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

## Secrets and safety

- Never commit decrypted secrets, private keys, or the Chezmoi Age identity.
- Keep encrypted files encrypted and retain the container profile exclusions.
- Do not run `chezmoi apply`, install packages, or make system changes unless
  the user explicitly asks.
- Before changing bootstrap or package manifests, run `bash -n bootstrap.sh`,
  `git diff --check`, and resolve official Arch package names with `pacman -Sp`.
