## ADDED Requirements

### Requirement: Debian headless system packages track trusted rolling security
Homelab SHALL own Debian APT sources, keyrings, and trust. The Debian headless
system phase SHALL NOT write APT configuration; it SHALL require Debian 13,
perform a signed metadata refresh, verify that every declared package has a
candidate, and additively install the package-name set from the configured
stable/security sources.

#### Scenario: Homelab APT configuration is ready
- **WHEN** `--system` runs as root on Debian 13 with candidates for every
  declared package
- **THEN** the package set is installed without creating or replacing an APT
  source or keyring

#### Scenario: A package candidate is absent
- **WHEN** the refreshed APT metadata has no candidate for a declared package
- **THEN** installation stops with the missing package name before invoking the
  bulk install

#### Scenario: A prohibited package is declared
- **WHEN** a container engine, tmux, or zellij enters a Debian headless
  installation manifest
- **THEN** source validation fails before package installation

#### Scenario: A prohibited command already exists
- **WHEN** homelab or the user already owns a container engine, tmux, or zellij
- **THEN** this profile neither removes it nor fails solely because it exists

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

#### Scenario: A plugin pin is missing
- **WHEN** a plugin declaration lacks a full commit identity
- **THEN** static validation fails before Chezmoi apply

## MODIFIED Requirements

### Requirement: Every software item has one owner
Each declared package, runtime, command, and global developer tool SHALL have
one authoritative owner among the platform package manifest, mise manifest and
lock, verified vendor manifest, verified 1Password declaration, or Bun manifest
and lock. Validation SHALL derive inventory from those native authorities and
SHALL NOT require a duplicate hand-maintained catalog.

#### Scenario: A command has multiple owners
- **WHEN** native manifests assign the same command to competing installation
  paths
- **THEN** validation fails before installation

#### Scenario: Native declarations disagree
- **WHEN** a manifest version, lock identity, command, or package-manager owner
  cannot be reconciled with its native lock or declaration
- **THEN** completeness validation fails with the conflicting sources

### Requirement: User tools are pinned and authenticated
Mise tools SHALL use a strict lockfile, Bun dependencies SHALL use a frozen
lockfile, vendor artifacts SHALL use exact versions and SHA-256 digests, and
1Password SHALL verify its release signature only after the imported key
matches the committed expected fingerprint. Every validator SHALL declare its
command dependencies and SHALL fail closed when one is unavailable.

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

### Requirement: Reconciliation is safe to repeat
Repeated provisioning SHALL check the exact profile-owned command paths,
preserve declared versions and ownership, clean all temporary artifacts on
success or failure, and operate additively without uninstalling packages or
deleting unrelated user binaries.

#### Scenario: Provisioning runs twice
- **WHEN** managed commands already match their declarations
- **THEN** the second run performs no unnecessary download or replacement

#### Scenario: Another owner provides the same command
- **WHEN** PATH contains a matching command outside the profile-owned location
- **THEN** the installer still reconciles and verifies its own declared target

#### Scenario: Installation fails midway
- **WHEN** a download, hash, extraction, signature, or post-install version
  check fails
- **THEN** temporary files are removed and the prior managed command remains
  intact

## REMOVED Requirements

### Requirement: Debian headless system packages use a signed snapshot

**Reason**: The selected operating model prioritizes rolling Debian 13
stable/security updates while leaving APT trust and exact root-image
reproducibility with homelab.

**Migration**: Remove the snapshot environment and generated source file.
Require homelab-provided signed Debian 13 sources, retain package names as the
native manifest, and validate candidates before additive installation.
