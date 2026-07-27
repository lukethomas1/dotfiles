## MODIFIED Requirements

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
