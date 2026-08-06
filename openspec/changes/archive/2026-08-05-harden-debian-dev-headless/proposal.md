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
- **BREAKING**: stop writing a Debian snapshot source; require a current
  homelab-issued Debian 13 APT trust attestation and install the declared
  package set from rolling signed stable/security candidates.
- **BREAKING**: remove `debian-snapshot.env` and `tool-catalog.tsv`; treat the
  APT, mise, vendor, 1Password, and Bun-native manifests as authoritative and
  derive inventory during validation.
- Keep the dedicated root and user installer phases, document a local-checkout
  initialization sequence that works in an empty home, and remove the
  unreachable headless orchestration path from the curl-capable main bootstrap.
- Make manifest checks fail closed, independently enforce the required command
  groups, authenticate the exact 1Password signer and installed payload,
  reconcile user commands by digest, and clean temporary files on every exit.
- Permit reviewed container-engine and session-manager declarations without
  installing any as part of this change.
- Keep Git unsigned until manual per-console SSH signing enrollment through an
  unmanaged local include.
- Make the Chezmoi headless render itself ignore-all/allow-specific and make
  Antidote reconciliation safe under concurrent shell startup.
- Match Pulumi, Talos, kubectl, and Cilium CLI to the exact client versions
  accepted by the homelab repository instead of independently selecting newer
  patch releases.
- Separate fixture-root APT attestation verification from live `--system`
  mutation, publish Antidote lock ownership safely, and reconcile Debian
  `fd`/`bat` compatibility links without PATH trust or destructive collisions.
- Pin Antidote and every shared Zsh plugin to the currently working full commit
  identity across all profiles.
- Revert the unrelated macOS npm-to-Bun behavior change; other established
  profile package-manager behavior remains unchanged.

## Non-Goals

- Changing homelab-owned account, mount, network, DNS, SSH daemon, access, or
  retained-volume configuration, or mutating APT trust on a live host during
  repository validation.
- Uninstalling packages or deleting unrelated user binaries that disappear from
  this repository's manifests.
- Enrolling 1Password, Codex, Git, cluster, cloud, or other credentials.
- Running the system or real-home apply phases in normal repository validation.
- Upgrading homelab's exact infrastructure-client compatibility gates.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `managed-content`: replace broad secretless shared deployment for
  `debian-dev-headless` with an exact fail-closed CLI allowlist, add an
  unmanaged local Git enrollment boundary, and enforce repository-metadata
  exclusions.
- `secret-handling`: retain a credential-free unsigned Git baseline while
  allowing manual per-console SSH signing through an unmanaged local include.
- `bootstrap-workflows`: make the headless local-checkout, split-privilege,
  role-aware initialization flow canonical and keep dry-run behavior reachable.
- `software-provisioning`: replace snapshot ownership and duplicated inventory
  with homelab-attested rolling APT candidates, native manifest authorities, a
  versionless required-command floor, signer and payload verification,
  additive reconciliation, and concurrency-safe shared shell pins.

## Impact

- Affects Chezmoi role data and ignores, the Debian installer and tests, shared
  Zsh startup/plugin declarations, bootstrap documentation, and Debian package
  manifests.
- Existing Debian headless hosts must have a current homelab-provided Debian 13
  stable/security trust attestation before running `--system`.
- macOS returns to its pre-change npm-based `@devcontainers/cli` installation;
  Arch, Fedora, and container package ownership remain unchanged.
- All profiles receive pinned shell plugins and may replace a floating local
  Antidote checkout with the committed revision.
- This repository intentionally moves Debian packages to rolling signed
  stable/security versions. Homelab remains responsible for exact image/root
  reproducibility, and its specifications may need a follow-up clarification
  where they currently describe pinned OpenSSH or Mosh packages.
