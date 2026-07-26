# Profile Selection Specification

## Purpose

Define the supported Chezmoi roles, their distro mapping, and the shared role
data consumed by templates and bootstrap workflows.

## Requirements

### Requirement: Supported roles are explicit
The repository SHALL support exactly the `macos`, `fedora`, `arch`,
`container`, and `debian-dev-headless` roles.

#### Scenario: A supported role is selected
- **WHEN** initialization receives one of the five supported role names
- **THEN** Chezmoi records that exact role for subsequent template rendering

#### Scenario: An unknown role is supplied
- **WHEN** initialization receives a role outside the supported set
- **THEN** initialization stops before rendering or applying managed content

### Requirement: Role-to-distro mapping is deterministic
The repository SHALL map `macos` to `macos`, `fedora` to `fedora`, `arch` to
`arch`, and both `container` and `debian-dev-headless` to `debian`.

#### Scenario: Debian headless data is rendered
- **WHEN** the selected role is `debian-dev-headless`
- **THEN** templates receive role `debian-dev-headless` and distro `debian`

#### Scenario: Interactive initialization occurs
- **WHEN** no role is supplied through the environment
- **THEN** the user selects from the supported roles and the distro is derived
  without a contradictory second choice

### Requirement: Bootstrap and templates share one role contract
Bootstrap entrypoints and Chezmoi templates SHALL use the same role names and
SHALL NOT silently reinterpret an explicit role as another profile.

#### Scenario: A role-specific dry-run is requested
- **WHEN** an entrypoint accepts an explicit role for a dry-run
- **THEN** it validates that role against the detected platform using the same
  rules as real execution

#### Scenario: Dry-run and execution would diverge
- **WHEN** an explicit role is incompatible with the detected platform
- **THEN** the dry-run fails instead of printing an unreachable execution plan
