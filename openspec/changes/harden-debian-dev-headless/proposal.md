## Why

The initial `debian-dev-headless` implementation establishes the right
secretless, split-privilege direction but its first-install path, deployment
scope, APT ownership, validation claims, and duplicated manifests do not yet
meet the repository's reproducibility and safety contract. The profile should
be hardened before it becomes the durable developer-console baseline.

## What Changes

- Limit `debian-dev-headless` to an explicit CLI configuration allowlist and
  exclude desktop, Obsidian, repository-planning, SSH, secret, and identity
  content.
- Make role selection strict and expose derived `secretless` and `headless`
  template data instead of repeating compound role expressions.
- **BREAKING**: stop writing a Debian snapshot source; require homelab-provided
  Debian 13 APT trust and install the declared package set from rolling signed
  stable/security candidates.
- **BREAKING**: remove `debian-snapshot.env` and `tool-catalog.tsv`; treat the
  APT, mise, vendor, 1Password, and Bun-native manifests as authoritative and
  derive inventory during validation.
- Keep the dedicated root and user installer phases, document a local-checkout
  initialization sequence that works in an empty home, and remove the
  unreachable headless orchestration path from the curl-capable main bootstrap.
- Make manifest checks fail closed, authenticate the expected 1Password signing
  key, reconcile user commands deterministically, and clean temporary files on
  every exit.
- Keep prohibited engines and alternate session managers out of this profile's
  manifests without rejecting software already owned by homelab or the user.
- Pin Antidote and every shared Zsh plugin to the currently working full commit
  identity across all profiles.
- Revert the unrelated macOS npm-to-Bun behavior change; other established
  profile package-manager behavior remains unchanged.

## Non-Goals

- Changing homelab-owned account, mount, network, DNS, SSH daemon, APT trust,
  access, or retained-volume configuration.
- Uninstalling packages or deleting unrelated user binaries that disappear from
  this repository's manifests.
- Enrolling 1Password, Codex, Git, cluster, cloud, or other credentials.
- Running the system or real-home apply phases in normal repository validation.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `managed-content`: replace broad secretless shared deployment for
  `debian-dev-headless` with an exact CLI allowlist and enforce
  repository-metadata exclusions.
- `bootstrap-workflows`: make the headless local-checkout, split-privilege,
  role-aware initialization flow canonical and keep dry-run behavior reachable.
- `software-provisioning`: replace snapshot ownership and duplicated inventory
  with homelab-trusted rolling APT candidates, native manifest authorities,
  fail-closed verification, additive reconciliation, and shared shell pins.

## Impact

- Affects Chezmoi role data and ignores, the Debian installer and tests, shared
  Zsh startup/plugin declarations, bootstrap documentation, and Debian package
  manifests.
- Existing Debian headless hosts must have working homelab-provided Debian 13
  stable/security sources before running `--system`.
- macOS returns to its pre-change npm-based `@devcontainers/cli` installation;
  Arch, Fedora, and container package ownership remain unchanged.
- All profiles receive pinned shell plugins and may replace a floating local
  Antidote checkout with the committed revision.
- This repository intentionally moves Debian packages to rolling signed
  stable/security versions. Homelab remains responsible for exact image/root
  reproducibility, and its specifications may need a follow-up clarification
  where they currently describe pinned OpenSSH or Mosh packages.
