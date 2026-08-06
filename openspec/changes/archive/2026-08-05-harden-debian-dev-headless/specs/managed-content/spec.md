## MODIFIED Requirements

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
