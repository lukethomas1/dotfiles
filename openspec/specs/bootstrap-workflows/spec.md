# Bootstrap Workflows Specification

## Purpose

Define safe first-install, update, dry-run, and privilege-separated workflows
for supported profiles.

## Requirements

### Requirement: Dry-run is behaviorally faithful
Every bootstrap or installer dry-run SHALL select the same platform and role
path as real execution while making no download, package, home, shell,
credential, or system change.

#### Scenario: A compatible dry-run runs
- **WHEN** the detected platform supports the selected role
- **THEN** the output lists the ordered actions real execution would take

#### Scenario: The role is incompatible
- **WHEN** a requested role cannot execute on the detected platform
- **THEN** dry-run fails with the same platform decision real execution uses

### Requirement: Desktop and container bootstrap remain platform-aware
The main bootstrap SHALL preserve the established macOS, Arch, Fedora, and
container installation paths and their package-manager ownership.

#### Scenario: Existing profile bootstrap runs
- **WHEN** an established non-headless profile is detected
- **THEN** bootstrap uses that profile's declared package and apply workflow

### Requirement: Debian headless installation separates privileges
The Debian headless workflow SHALL expose an authenticated root system phase
and an unprivileged user phase, SHALL reject the wrong effective user for each
phase, and SHALL NOT depend on `sudo` internally.

#### Scenario: Root runs the system phase
- **WHEN** `--system` runs as root on supported Debian
- **THEN** only declared system-package actions execute

#### Scenario: Root runs the user phase
- **WHEN** `--user` runs with effective user zero
- **THEN** it stops before writing user-owned software

#### Scenario: An unprivileged user runs the system phase
- **WHEN** `--system` runs without effective user zero
- **THEN** it stops before invoking the package manager

### Requirement: Chezmoi initialization precedes apply
A first installation SHALL initialize the Chezmoi configuration with the
selected role before applying templates.

#### Scenario: A clean home is configured
- **WHEN** the source checkout exists but no Chezmoi config exists
- **THEN** the documented workflow runs role-aware `chezmoi init` before
  `chezmoi apply`

#### Scenario: Apply is attempted without role data
- **WHEN** templates require role data that has not been initialized
- **THEN** the workflow fails with an actionable initialization instruction
