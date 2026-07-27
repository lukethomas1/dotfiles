# Dotfiles test plan

This repository configures real machines, so tests are split into three
layers. The first two run without changing a developer's home directory; the
third applies only to an isolated temporary destination or disposable VM.

## Fast local checks

Run these before committing changes:

```zsh
cd ~/.local/share/chezmoi
git diff --check
bash -n bootstrap.sh scripts/debian-dev-headless-install.sh \
  scripts/test-debian-dev-headless.sh
./bootstrap.sh --dry-run
./scripts/debian-dev-headless-install.sh --verify-manifests
./scripts/test-debian-dev-headless.sh
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

The durable headless role has a single non-mutating harness that checks all
five roles, the exact headless CLI allowlist, apply-twice state, locked
mise/vendor/Bun identities, signing-key identity, negative manifest fixtures,
and pinned/offline Zsh startup:

```zsh
./scripts/test-debian-dev-headless.sh
```

The harness initializes an empty temporary home and applies the headless role
without `--exclude encrypted`. Role metadata must exclude encrypted content
before Chezmoi tries to resolve the Age identity. The harness does not install
packages, download artifacts, apply to the real home, or enroll any account.

## Debian 13 developer console

This workflow must run from a trusted local checkout. The curl-capable
`bootstrap.sh` deliberately does not select or install this role.

First inspect the non-mutating plan:

```bash
./scripts/debian-dev-headless-install.sh --dry-run
```

This first preview uses only Debian base `awk`/`grep` validation and reports
that full jq-dependent lock and ownership checks are deferred until
`--verify-manifests` or the post-system user phase.

Then run the system phase as root, the software phase as the unprivileged
console user, initialize role data from the checkout, and apply separately:

```bash
checkout="$HOME/.local/share/chezmoi"
sudo "$checkout/scripts/debian-dev-headless-install.sh" --system
"$checkout/scripts/debian-dev-headless-install.sh" --user
CHEZMOI_ROLE=debian-dev-headless \
  chezmoi init --source "$checkout" --no-tty
chezmoi apply
```

Homelab owns and validates the Debian 13/trixie stable, updates, and security
APT sources, keyring, DNS, network, SSH daemon, trust, mounts, and account. It
must issue `/etc/homelab/developer-console-apt-trust` for the current source
and keyring state. The system phase refuses stale or missing trust, then
refreshes signed metadata, checks every declared package has a candidate, and
additively installs package names from `packages.txt`.

User tools have exact identities: mise uses its committed strict lock, Bun
uses its frozen lock, vendor downloads use committed artifact and payload
SHA-256 digests, and 1Password requires its committed public key, exact valid
signer, release signature, and payload identity. Reconciliation owns only its declared targets under
`~/.local/bin` and leaves pre-existing container engines, tmux, zellij, and
unrelated user binaries in place. Removing a declaration does not uninstall a
package or delete retained credentials, instances, or volumes; cleanup is a
separate, explicit operator action. The workflow installs CLI software and
secretless configuration only—it never signs in to 1Password, GitHub,
Cloudflare, or another service and never creates credentials.

After software validation, manually create a unique SSH signing key for each
console and configure only the unmanaged local include:

```bash
ssh-keygen -t ed25519 -f "$HOME/.ssh/id_ed25519_signing" \
  -C "$(hostname)-git-signing"
git config --file "$HOME/.gitconfig-local" gpg.format ssh
git config --file "$HOME/.gitconfig-local" \
  user.signingkey "$HOME/.ssh/id_ed25519_signing.pub"
git config --file "$HOME/.gitconfig-local" commit.gpgsign true
chmod 0600 "$HOME/.gitconfig-local"
```

The signing key and `.gitconfig-local` stay on the replaceable root filesystem
and are neither managed by Chezmoi nor copied to retained storage.

## Continuous testing plan

1. Add a GitHub Actions pull-request workflow with a `macos-latest` job and a
   Linux job. Each runs `git diff --check`, `bash -n bootstrap.sh`, and the
   profile-appropriate `bootstrap.sh --dry-run` plus isolated apply-twice test.
2. Keep the Linux job focused on template rendering for the `container` role;
   also run the Debian headless isolated harness there. It cannot validate
   CachyOS/Shelly behavior because it is not CachyOS.
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

macOS and CachyOS are both required: initialized role data controls
platform-specific ignores, while Shelly and the Niri validation are
Arch/CachyOS-specific.
