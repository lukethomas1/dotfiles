# Managed Content Specification

## Purpose

Define which repository content is deployable and how profiles limit managed
user configuration.

## Requirements

### Requirement: Repository metadata is never deployed
The repository SHALL exclude documentation, package manifests, bootstrap and
test scripts, OpenSpec artifacts, agent instructions, archived configuration,
and supporting assets from every Chezmoi destination.

#### Scenario: A profile is rendered
- **WHEN** Chezmoi enumerates managed targets for any supported role
- **THEN** no repository-control file or directory appears in the destination

#### Scenario: New repository tooling is added
- **WHEN** a top-level tool or planning directory is introduced
- **THEN** validation fails until it is explicitly classified as deployable or
  globally ignored

### Requirement: Desktop configuration is profile-specific
The repository SHALL deploy each desktop configuration only to a role that
owns the corresponding desktop environment.

#### Scenario: Arch is rendered
- **WHEN** the `arch` role is selected
- **THEN** Niri and Noctalia configuration is managed and AeroSpace
  configuration is excluded

#### Scenario: macOS is rendered
- **WHEN** the `macos` role is selected
- **THEN** AeroSpace configuration is managed and Linux desktop configuration
  is excluded

#### Scenario: A non-owning role is rendered
- **WHEN** a role does not own a desktop application or compositor
- **THEN** that application's configuration is absent from its managed targets

### Requirement: Secretless Debian roles receive shared user configuration
The `container` and `debian-dev-headless` roles SHALL receive the shared
developer user configuration except for personal secrets, authentication, and
SSH material.

#### Scenario: Debian headless is rendered
- **WHEN** `debian-dev-headless` is initialized
- **THEN** shared shell, Git, editor, terminal, and developer application
  configuration is eligible for deployment

#### Scenario: Secret-bearing content is encountered
- **WHEN** shared content contains a personal secret, authentication artifact,
  or SSH target
- **THEN** it is excluded from both secretless Debian roles

### Requirement: Managed output is idempotent
Applying a profile repeatedly to an unchanged source SHALL produce the same
files, links, permissions, and directories.

#### Scenario: A profile is applied twice
- **WHEN** an isolated destination receives two consecutive applies
- **THEN** the complete managed state after both applies is identical
