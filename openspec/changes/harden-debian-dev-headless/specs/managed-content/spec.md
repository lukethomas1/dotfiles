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
- **WHEN** the Debian headless managed set contains a target outside the CLI
  allowlist
- **THEN** isolated managed-target validation fails before apply
