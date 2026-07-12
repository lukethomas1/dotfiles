# Dotfiles test plan

This repository configures real machines, so tests are split into three
layers. The first two run without changing a developer's home directory; the
third applies only to an isolated temporary destination or disposable VM.

## Fast local checks

Run these before committing changes:

```zsh
cd ~/.local/share/chezmoi
git diff --check
bash -n bootstrap.sh
./bootstrap.sh --dry-run
CHEZMOI_ROLE=arch chezmoi apply --dry-run --no-tty \
  --refresh-externals=never --exclude encrypted --exclude scripts
```

`bootstrap.sh --dry-run` detects the local platform and prints every planned
bootstrap and package-management operation without installing packages,
downloading anything, changing the login shell, or applying dotfiles.

The Chezmoi dry-run renders the Arch profile without touching the destination
directory. Encrypted entries are deliberately excluded: CI and temporary test
homes must never receive the personal Age identity or decrypted secrets.

On macOS, additionally use:

```zsh
CHEZMOI_ROLE=macos chezmoi apply --dry-run --no-tty \
  --refresh-externals=never --exclude encrypted --exclude scripts
brew bundle check --file=pkg/macos/Brewfile --verbose
```

`brew bundle check` is a read-only assertion that a fully provisioned Mac
matches the Brewfile. It is expected to report missing dependencies on a clean
CI runner; use it there only to display the planned set, not as a passing
assertion.

## Isolated apply-twice test

This is the idempotence test. It writes only to a temporary directory and
excludes secrets and scripts:

```zsh
repo="$HOME/.local/share/chezmoi"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

CHEZMOI_ROLE=arch chezmoi init --source "$repo" --config-path "$tmp/chezmoi.toml"
CHEZMOI_ROLE=arch chezmoi --config "$tmp/chezmoi.toml" --source "$repo" \
  --destination "$tmp/home" --cache "$tmp/cache" --persistent-state "$tmp/state" \
  apply --force --no-tty --refresh-externals=never --exclude encrypted --exclude scripts
CHEZMOI_ROLE=arch chezmoi --config "$tmp/chezmoi.toml" --source "$repo" \
  --destination "$tmp/home" --cache "$tmp/cache" --persistent-state "$tmp/state" \
  verify --no-tty --refresh-externals=never --exclude encrypted --exclude scripts
```

Run the same sequence with `CHEZMOI_ROLE=macos` on a Mac. This catches invalid
templates, role-specific ignores, and non-idempotent file output while keeping
the real home directory untouched.

## Continuous testing plan

1. Add a GitHub Actions pull-request workflow with a `macos-latest` job and a
   Linux job. Each runs `git diff --check`, `bash -n bootstrap.sh`, and the
   profile-appropriate `bootstrap.sh --dry-run` plus isolated apply-twice test.
2. Keep the Linux job focused on template rendering for the `container` role;
   it cannot validate CachyOS/Shelly behavior because it is not CachyOS.
3. Add a manually triggered or nightly CachyOS VM job for the Arch host
   profile. Begin from a snapshot, run `./bootstrap.sh --dry-run`, run the
   isolated Chezmoi test as an unprivileged user, and validate Niri with
   `niri validate --config <rendered-config>`. Do not run the full bootstrap
   in CI: it upgrades the OS, installs desktop packages, and requires the
   private Age identity for secrets.
4. Optionally maintain a separate, explicitly approved full-install smoke VM
   with a disposable Age test key and test-only encrypted fixture. This is the
   only place to exercise Shelly, Flatpak, Firefox policy installation, and
   login-shell changes end-to-end. Snapshot before each run and discard it
   afterward.

macOS and CachyOS are both required: `.chezmoi.os` controls macOS-specific
ignores, while Shelly and the Niri validation are Arch/CachyOS-specific.
