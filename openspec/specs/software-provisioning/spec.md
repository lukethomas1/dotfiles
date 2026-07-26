# Software Provisioning Specification

## Purpose

Define package-manager ownership, trusted artifacts, version policy, and
reconciliation behavior for host and user software.

## Requirements

### Requirement: Every software item has one owner
Each declared package, runtime, command, and global developer tool SHALL have
one authoritative owner among the platform package manager, mise, a verified
vendor artifact, or Bun.

#### Scenario: A command has multiple owners
- **WHEN** manifests assign the same command to competing installation paths
- **THEN** validation fails before installation

#### Scenario: A manifest item has no inventory owner
- **WHEN** a declared package or tool cannot be mapped to one owner
- **THEN** completeness validation fails

### Requirement: Host profiles use their declared package managers
macOS SHALL use Homebrew, Fedora SHALL use Linuxbrew, Arch SHALL use Shelly for
official and AUR packages, and the container profile SHALL defer package
ownership to its image.

#### Scenario: A host package plan is rendered
- **WHEN** a host profile dry-run executes
- **THEN** every declared package is attributed to that profile's package
  manager

### Requirement: Debian headless system packages use a signed snapshot
The Debian headless system phase SHALL configure and consume the declared
signed Debian 13 snapshot and SHALL install the exact declared package set
without adding a container engine or competing terminal session manager.

#### Scenario: Snapshot package installation runs
- **WHEN** the authenticated system phase executes on Debian 13
- **THEN** APT consumes the declared Debian and security snapshot timestamp
  before installing the package manifest

#### Scenario: A prohibited package is declared
- **WHEN** a container engine, tmux, or zellij enters a Debian headless
  installation manifest
- **THEN** validation fails before package installation

### Requirement: User tools are pinned and authenticated
Mise tools SHALL use a strict lockfile, Bun dependencies SHALL use a frozen
lockfile, vendor artifacts SHALL use exact versions and SHA-256 digests, and
1Password SHALL use its release signature.

#### Scenario: A pinned artifact differs
- **WHEN** an artifact checksum, lock identity, or signature differs from the
  committed declaration
- **THEN** installation stops before replacing the command

#### Scenario: User tool installation succeeds
- **WHEN** all verification passes
- **THEN** every declared command reports its expected version from the
  unprivileged user environment

### Requirement: JavaScript global ownership is explicit
Bun SHALL own JavaScript package installation for Debian headless, while Node
remains a compatibility runtime and established non-headless profile behavior
remains unchanged.

#### Scenario: Debian JavaScript tools are installed
- **WHEN** the Debian headless user phase runs
- **THEN** Bun installs the locked OpenSpec and Wrangler packages without npm,
  pnpm, or Yarn

### Requirement: Reconciliation is safe to repeat
Repeated provisioning SHALL preserve declared versions and ownership without
corrupting unrelated system or user software.

#### Scenario: Provisioning runs twice
- **WHEN** installed commands already match their declarations
- **THEN** the second run performs no unnecessary replacement
