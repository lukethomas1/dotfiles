# Secret Handling Specification

## Purpose

Define encryption, identity, SSH, signing, and credential boundaries for each
profile.

## Requirements

### Requirement: Secret material remains encrypted at rest
The repository SHALL NOT contain decrypted secrets, private keys, credentials,
or the Chezmoi Age identity.

#### Scenario: Secret-bearing configuration is committed
- **WHEN** a managed secret is stored in the repository
- **THEN** its source form is encrypted for the committed Age recipient

#### Scenario: Plaintext secret material is detected
- **WHEN** validation identifies a decrypted secret, private key, credential,
  or Age identity
- **THEN** validation fails before commit or apply

### Requirement: Secretless roles do not require an Age identity
The `container` and `debian-dev-headless` roles SHALL render and apply without
an Age identity because all encrypted targets are excluded by role policy.

#### Scenario: A secretless role has no identity
- **WHEN** its destination lacks `.config/chezmoi/key.txt`
- **THEN** initialization and apply complete without decrypting personal files

#### Scenario: An exclusion regresses
- **WHEN** an encrypted or SSH target enters a secretless role's managed set
- **THEN** isolated managed-target validation fails without relying on a
  command-line encrypted-content exclusion

### Requirement: Secretless Git behavior requires no managed signing credential
The `container` Git configuration SHALL disable commit signing and SHALL NOT
declare a signing key or credential helper that requires personal
authentication material. The `debian-dev-headless` managed baseline SHALL also
disable signing and omit a signing key, but SHALL include unmanaged
`~/.gitconfig-local` after those defaults so manual enrollment can enable SSH
signing with a unique console-local key.

#### Scenario: Debian headless Git configuration is rendered
- **WHEN** the role is `debian-dev-headless` and enrollment has not occurred
- **THEN** `commit.gpgsign` is false, no managed signing key is emitted, and
  Git remains usable

#### Scenario: Console signing is manually enrolled
- **WHEN** the operator creates a unique SSH signing key and enables signing in
  `~/.gitconfig-local`
- **THEN** the effective Git configuration signs with that key while Chezmoi
  manages neither the local include contents nor credential material

### Requirement: Authentication is an explicit post-bootstrap action
Software installation SHALL NOT enroll an account, create a credential, or
persist an authentication session.

#### Scenario: User tooling installation completes
- **WHEN** the Debian headless user phase succeeds
- **THEN** tools are executable but 1Password, Codex, Git hosts, clusters, and
  cloud services remain unauthenticated
