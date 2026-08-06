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
The `container` role SHALL receive the shared developer user configuration
except for personal secrets, authentication, and SSH material. The
`debian-dev-headless` role SHALL instead receive only `.bashrc`, `.zshrc`,
`.zsh_plugins.txt`, `.gitconfig`, pinned Zsh metadata, Neovim, Starship, Atuin,
and Herdr configuration.

#### Scenario: Debian headless is rendered
- **WHEN** `debian-dev-headless` is initialized
- **THEN** its managed targets contain the exact CLI allowlist and exclude
  AeroSpace, Niri, Noctalia, Ghostty, Obsidian, and repository metadata

#### Scenario: Container is rendered
- **WHEN** the `container` role is initialized
- **THEN** its established shared secretless developer configuration remains
  eligible for deployment

#### Scenario: Secret-bearing content is encountered
- **WHEN** shared content contains a personal secret, authentication artifact,
  Age identity, or SSH target
- **THEN** it is excluded from both secretless Debian roles

#### Scenario: An unclassified target enters headless output
- **WHEN** a new source target is added without an explicit headless inclusion
- **THEN** the rendered ignore policy excludes it and isolated managed-target
  validation confirms that it cannot enter apply

#### Scenario: A headless Bash entry invokes managed tools
- **WHEN** an interactive session starts or a non-interactive remote command
  sources the managed `.bashrc`
- **THEN** `~/.local/bin` and the locked Mise shims are available before the
  interactive-only shell configuration boundary

### Requirement: Console Git signing is enrolled outside managed content
The managed Debian headless Git configuration SHALL include
`~/.gitconfig-local` after its secretless unsigned defaults. Chezmoi SHALL NOT
manage that local file or any SSH key, and manual enrollment SHALL enable SSH
signing with a unique per-console key through the local include.

#### Scenario: A console has not been enrolled
- **WHEN** the headless role is first applied without a local include
- **THEN** Git remains usable with commit signing disabled

#### Scenario: A signing key is enrolled
- **WHEN** the operator writes the local include with the console's SSH signing
  public key and enables signing
- **THEN** Git's effective configuration uses SSH signing without modifying the
  Chezmoi-managed file

### Requirement: Managed output is idempotent
Applying a profile repeatedly to an unchanged source SHALL produce the same
files, links, permissions, and directories.

#### Scenario: A profile is applied twice
- **WHEN** an isolated destination receives two consecutive applies
- **THEN** the complete managed state after both applies is identical
