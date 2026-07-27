## MODIFIED Requirements

### Requirement: Debian headless installation separates privileges
The Debian headless workflow SHALL run from a local repository checkout, SHALL
expose a root `--system` phase and an unprivileged `--user` phase through the
dedicated installer, SHALL reject the wrong effective user for each phase, and
SHALL NOT depend on `sudo` internally. The curl-capable main bootstrap SHALL
NOT claim to orchestrate this split workflow.

#### Scenario: Root runs the system phase
- **WHEN** `--system` runs as root on supported Debian from a local checkout
- **THEN** only declared system-package actions execute

#### Scenario: Root runs the user phase
- **WHEN** `--user` runs with effective user zero
- **THEN** it stops before writing user-owned software

#### Scenario: An unprivileged user runs the system phase
- **WHEN** `--system` runs without effective user zero
- **THEN** it stops before invoking the package manager

#### Scenario: Main bootstrap is piped remotely
- **WHEN** the curl-capable bootstrap runs without the repository manifests and
  companion installer
- **THEN** it does not advertise or enter the Debian headless workflow

### Requirement: Chezmoi initialization precedes apply
A first Debian headless installation SHALL initialize the local checkout with
`CHEZMOI_ROLE=debian-dev-headless` before a separate apply, and the documented
commands SHALL work when neither Chezmoi config nor state exists.

#### Scenario: A clean home is configured
- **WHEN** system and user provisioning have completed from a local checkout
- **THEN** the workflow runs role-aware `chezmoi init --source <checkout>
  --no-tty` before `chezmoi apply`

#### Scenario: The checkout uses the default source path
- **WHEN** the repository already exists at Chezmoi's default source path but
  no config exists
- **THEN** initialization creates role data instead of treating the checkout as
  an already configured installation

#### Scenario: Apply is attempted without role data
- **WHEN** templates require role data that has not been initialized
- **THEN** the workflow fails with an actionable initialization instruction
