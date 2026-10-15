# Spec Delta

## Purpose

Provide a reproducible Arch desktop shell whose runtime, saved preferences,
startup, and keyboard actions remain consistent across installation and login.

## ADDED Requirements

### Requirement: Native runtime ownership and startup
The Arch profile SHALL declare the maintained native Noctalia package and SHALL
start one native shell per desktop session without a legacy Quickshell command.

#### Scenario: Normal Arch login
- **WHEN** Niri starts with the managed configuration and native package installed
- **THEN** Noctalia supplies a bar and wallpaper on every configured display

#### Scenario: Bootstrap reconciles the host
- **WHEN** the Arch package manifest is installed through Shelly
- **THEN** the manifest requests the native package and does not request the
  archived shell or its Quickshell runtime

### Requirement: Preserve keyboard actions
The desktop SHALL retain the existing physical launcher, lock, session, audio,
media, and brightness shortcuts using native Noctalia commands. The migration
SHALL NOT change the Caps Lock modifier or unrelated Niri actions.

#### Scenario: Launcher and session shortcuts are used
- **WHEN** the existing launcher or session-menu chord is pressed
- **THEN** the corresponding native panel toggles

#### Scenario: Media and system keys are used
- **WHEN** an existing audio, media, microphone, or brightness key is pressed
- **THEN** its native command performs the corresponding action

#### Scenario: Unrelated keybindings contain local edits
- **WHEN** the migration is integrated
- **THEN** existing non-Noctalia keybinding edits and window-management semantics
  are preserved

### Requirement: Preserve saved desktop choices
The v5 configuration SHALL preserve the preferences in the design's mapping,
including named workspace labels, disabled workspace scrolling, expanded system
statistics, an inline tray, a media visualizer, volume feedback, palette, and
wallpaper. Differences imposed by v5 SHALL be documented before activation.

#### Scenario: The migrated config is loaded
- **WHEN** the native shell loads the managed TOML
- **THEN** the preference mapping is represented in its effective configuration
  and visible desktop

#### Scenario: A preference has no exact native equivalent
- **WHEN** v5 cannot reproduce an existing preference exactly
- **THEN** the nearest supported behavior and its difference are documented in
  the migration design and preview review

### Requirement: Safe and persistent user configuration
The migration SHALL retain the previous v4 settings as an excluded recovery
reference, keep v5 GUI overrides app-owned, and activate only reviewed desktop
targets after backing up existing files. Repeated application SHALL be idempotent.

#### Scenario: GUI overrides already exist
- **WHEN** activation finds a native GUI override file
- **THEN** it is inspected and backed up without silent deletion or replacement

#### Scenario: The user applies the desktop configuration twice
- **WHEN** the same source is applied twice in an isolated destination
- **THEN** the managed state is identical after both applications

#### Scenario: Desktop validation runs
- **WHEN** the migration test plan is executed before host activation
- **THEN** validation does not install packages, run global bootstrap, remove
  packages, or write the real home

### Requirement: Preserve profile boundaries
The repository SHALL deploy native Noctalia configuration only for Arch and
SHALL exclude archived settings and workflow metadata from every profile.

#### Scenario: Arch is rendered
- **WHEN** Chezmoi enumerates the Arch managed targets
- **THEN** native Noctalia TOML and its Niri startup are eligible for deployment

#### Scenario: Another supported role is rendered
- **WHEN** macos, fedora, container, or debian-dev-headless is selected
- **THEN** native Noctalia configuration and archived v4 files are excluded
