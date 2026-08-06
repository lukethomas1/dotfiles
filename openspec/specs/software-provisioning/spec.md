# Software Provisioning Specification

## Purpose

Define package-manager ownership, trusted artifacts, version policy, and
reconciliation behavior for host and user software.

## Requirements

### Requirement: Every software item has one owner
Each declared package, runtime, command, and global developer tool SHALL have
one authoritative owner among the platform package manifest, mise manifest and
lock, verified vendor manifest, verified 1Password declaration, or Bun manifest
and lock. Validation SHALL derive inventory from those native authorities and
SHALL require every versionless group/command entry in the required-command
catalog without duplicating version or ownership data.

#### Scenario: A command has multiple owners
- **WHEN** native manifests assign the same command to competing installation
  paths
- **THEN** validation fails before installation

#### Scenario: A manifest item has no inventory owner
- **WHEN** a declared package or tool cannot be mapped to one owner
- **THEN** completeness validation fails

#### Scenario: Native declarations disagree
- **WHEN** a manifest version, lock identity, command, or package-manager owner
  cannot be reconciled with its native lock or declaration
- **THEN** completeness validation fails with the conflicting sources

#### Scenario: A required command loses its owner
- **WHEN** a required APT, mise, vendor, Bun, or 1Password command is deleted
  from its native authority
- **THEN** completeness validation reports the missing command

### Requirement: Host profiles use their declared package managers
macOS SHALL use Homebrew, Fedora SHALL use Linuxbrew, Arch SHALL use Shelly for
official and AUR packages, and the container profile SHALL defer package
ownership to its image.

#### Scenario: A host package plan is rendered
- **WHEN** a host profile dry-run executes
- **THEN** every declared package is attributed to that profile's package
  manager

### Requirement: Debian headless system packages track trusted rolling security
Homelab SHALL own Debian APT sources, keyrings, and trust and SHALL attest its
current Debian 13 rolling stable, updates, and security state through the
root-owned developer-console APT trust interface. The Debian headless system
phase SHALL NOT write APT configuration; it SHALL validate that attestation,
perform a signed metadata refresh, verify that every declared package has a
candidate, and additively install the package-name set.

#### Scenario: Homelab APT configuration is ready
- **WHEN** `--system` runs as root on Debian 13 with candidates for every
  declared package
- **THEN** the package set is installed without creating or replacing an APT
  source or keyring

#### Scenario: APT trust is absent or stale
- **WHEN** the trust attestation is missing, malformed, has the wrong owner or
  mode, or its source/keyring identities no longer match
- **THEN** the system phase stops before refreshing metadata or installing
  packages

#### Scenario: A fixture attestation is inspected
- **WHEN** `--verify-apt-attestation <absolute-root>` is invoked
- **THEN** the selected Debian 13 root and attestation are validated without
  invoking `apt-get`, `apt-cache`, or package installation

#### Scenario: A fixture override reaches the live phase
- **WHEN** `--system` is invoked with an alternate APT root, OS-release path, or
  role manifest
- **THEN** it rejects the override before any package-manager command

#### Scenario: A package candidate is absent
- **WHEN** the refreshed APT metadata has no candidate for a declared package
- **THEN** installation stops with the missing package name before invoking the
  bulk install

#### Scenario: An engine or session manager is declared
- **WHEN** a future reviewed change assigns a container engine, tmux, or zellij
  to one native installation manifest
- **THEN** generic ownership and authentication rules apply without a
  console-specific prohibited-name policy

### Requirement: Shared Zsh dependencies are commit-pinned
Antidote and every repository-declared Zsh plugin SHALL use a committed
40-character Git revision for every profile. Shell startup SHALL reconcile only
to those revisions and SHALL remain usable when an initial network fetch is
unavailable.

#### Scenario: Pinned shell dependencies are available
- **WHEN** an interactive shell starts with network access
- **THEN** Antidote and all plugins load from their declared commits

#### Scenario: Initial fetch is unavailable
- **WHEN** a pinned dependency is absent and the network fetch fails
- **THEN** shell startup emits a warning, skips unavailable plugins, and leaves
  the interactive shell usable

#### Scenario: Concurrent shells reconcile Antidote
- **WHEN** two shells start while Antidote is absent or mismatched
- **THEN** one portable lock owner performs reconciliation while the other
  waits or safely continues without nesting or corrupting the checkout

#### Scenario: Lock ownership is being published
- **WHEN** a contender observes the lock directory before its owner publishes
  a readable PID
- **THEN** it waits for the bounded initialization grace and does not remove
  the active owner's lock

#### Scenario: Lock ownership changes before release
- **WHEN** the PID recorded by a held lock no longer identifies the releasing
  shell
- **THEN** the shell warns and preserves the lock instead of removing another
  owner's state

#### Scenario: A plugin pin is missing
- **WHEN** a plugin declaration lacks a full commit identity
- **THEN** static validation fails before Chezmoi apply

### Requirement: User tools are pinned and authenticated
Mise tools SHALL use a strict lockfile, Bun dependencies SHALL use a frozen
lockfile, vendor artifacts SHALL use exact versions and artifact/payload
SHA-256 digests, and 1Password SHALL verify its safely selected release
members against a committed public key, exact valid signer, and authenticated
payload digest. Every validator SHALL declare its command dependencies and
SHALL fail closed when one is unavailable.

#### Scenario: A pinned artifact differs
- **WHEN** an artifact checksum, lock identity, signature, or signing-key
  fingerprint differs from the committed declaration
- **THEN** installation stops before replacing the command

#### Scenario: A validator dependency is unavailable
- **WHEN** a required validation command cannot be executed
- **THEN** validation returns nonzero and does not claim that manifests passed

#### Scenario: User tool installation succeeds
- **WHEN** all verification passes
- **THEN** every declared command reports its expected version from the
  unprivileged managed path

#### Scenario: Homelab infrastructure clients are installed
- **WHEN** Mise reconciles Pulumi, Talos, kubectl, and Cilium CLI
- **THEN** their exact versions are `3.253.0`, `1.13.6`, `1.36.2`, and
  `0.19.2`, matching the homelab execution gates

#### Scenario: An existing command lies about its identity
- **WHEN** a link, non-regular file, or wrong payload reports the expected
  version at a profile-owned direct-command path
- **THEN** it is not trusted and is either safely repaired from authenticated
  inputs or rejected before use

### Requirement: JavaScript global ownership is explicit
Bun SHALL own JavaScript package installation for Debian headless, while Node
remains a compatibility runtime and established non-headless profile behavior
remains unchanged.

#### Scenario: Debian JavaScript tools are installed
- **WHEN** the Debian headless user phase runs
- **THEN** Bun installs the locked OpenSpec and Wrangler packages without npm,
  pnpm, or Yarn

### Requirement: Reconciliation is safe to repeat
Repeated provisioning SHALL check the exact profile-owned command paths,
preserve declared versions and ownership, clean all temporary artifacts on
success or failure, and operate additively without uninstalling packages or
deleting unrelated user binaries.

#### Scenario: Provisioning runs twice
- **WHEN** managed commands already match their declarations
- **THEN** the second run performs no unnecessary replacement

#### Scenario: Another owner provides the same command
- **WHEN** PATH contains a matching command outside the profile-owned location
- **THEN** the installer still reconciles and verifies its own declared target

#### Scenario: Debian compatibility commands are linked
- **WHEN** the user phase reconciles `fd` and `bat`
- **THEN** it uses only `/usr/bin/fdfind` and `/usr/bin/batcat`, retains correct
  links, and atomically repairs incorrect links

#### Scenario: A compatibility destination contains user data
- **WHEN** `~/.local/bin/fd` or `bat` is a regular file, directory, or another
  unexpected non-link object
- **THEN** reconciliation fails and preserves that object unchanged

#### Scenario: Installation fails midway
- **WHEN** a download, hash, extraction, signature, or post-install version
  check fails
- **THEN** temporary files are removed and the prior managed command remains
  intact
