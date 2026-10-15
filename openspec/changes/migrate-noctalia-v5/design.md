# Design

## Context

See proposal.md for the incident and requested scope. Commit `d6613a8` preserves
the user's current v4 settings. The host is now on a matching kernel/module set
and has working networking; the remaining failure is desktop startup. The
native `noctalia` executable is already installed.

### Technology baseline

Observed October 14, 2026: Noctalia 5.2.1 (`5.2.1-1.1` in the synchronized
CachyOS repository), Niri 26.04, Chezmoi 2.73.1, OpenSpec 1.14.0, Beads 1.2.2,
and agentic-workflow kit 0.1.0. The installed v5 source/documentation and native
CLI were used to validate the configuration and command vocabulary.

References: [v5 installation](https://docs.noctalia.dev/noctalia/getting-started/installation/),
[Niri integration](https://docs.noctalia.dev/noctalia/compositor-settings/niri/),
and [configuration precedence](https://docs.noctalia.dev/noctalia/configuration/).

## Goals / Non-Goals

Deliver a reproducible native v5 desktop with the user's saved preferences and
physical shortcuts. Keep platform boundaries and existing window management.
The proposal lists exclusions; root package removal, a full upgrade, and broad
bootstrap execution are not deployment prerequisites.

## Decisions

### Runtime and ownership

Declare `noctalia` in the Arch host manifest. Shelly continues to own official
packages. Remove the legacy runtime declarations from the manifest without
automatically uninstalling packages that may have other dependents. Use native
startup and `noctalia msg` directly. Do not install the experimental v4 build or
compatibility patches prepared under `/tmp`.

Track the distribution's rolling native package rather than pinning Qt or
maintaining a fork. Validate the managed TOML and command vocabulary when the
runtime changes. A failing boot-generation hook remains an independent incident.

### Configuration and saved choices

Manage v5 `config.toml` under `.config/noctalia/`. Use a template for home-relative
wallpaper/avatar paths. Archive v4 `settings.json` under the already excluded
archive tree so the previous preferences remain recoverable without active
legacy configuration. Keep the native GUI override file in
`~/.local/state/noctalia/settings.toml` app-owned and untracked.

| Saved preference | v5 mapping |
| --- | --- |
| Floating top bar on all screens | `bar.default`, four-pixel margins, 0.93 opacity |
| Named, always-visible workspace labels | `label_source=name`, labels enabled, empty workspaces visible |
| Workspace scroll disabled | All four scroll actions set to `none` |
| Workspace pill size 1 | Pill scale and minimum pill sizes 1; v5 geometry may differ |
| Expanded system statistics | Six sysmon widgets: CPU use, temperature, RAM %, disk %, RX, TX |
| System-monitor padding and monospace values | Per-widget padding and monospace font |
| Media visualizer on | Adjacent `audio_visualizer` widget, mirrored spectrum |
| Inline tray, including passive items | `drawer=false`, `hide_passive=false` |
| Volume feedback on | `audio.enable_sounds=true`; v5 exposes a global UI-sound switch |
| Catppuccin dark palette | Builtin Catppuccin, dark mode |
| Current wallpaper | Existing selected image from the v4 wallpaper cache, crop mode |
| Dock and launcher | Bottom auto-hide dock; rocket launcher, list mode and usage ordering |
| Clipboard history off and telemetry off | Explicitly disable both |
| Polkit agent plugin | Native built-in agent; v4 plugins are not loaded |

v5 splits the old combined SystemMonitor and MediaMini widgets into individual
widgets. Preserve their functions and left/center/right placement; exact pixel
identity is not promised. Record visible differences during the preview review.
Preserve volume step 5 through explicit native shortcut arguments. Preserve the
physical Caps Lock modifier and all non-Noctalia shortcut semantics.

### Shortcut mapping

Launcher becomes `panel-toggle launcher`, lock becomes `session lock`, session
menu becomes `panel-toggle session`, speaker keys become `volume-up 5`,
`volume-down 5`, and `volume-mute`, microphone mute becomes `mic-mute`, media
becomes `media next`, `media previous`, or `media toggle`, and brightness becomes
`brightness-up` or `brightness-down`. All commands use `noctalia msg`.

### Workflow state and isolation

The repository has existing OpenSpec content and AGENTS.md, but lacks the kit
manifest and Beads database. The kit's initializer correctly refuses to replace
that state. Migrate the missing manifest/schema/templates additively, preserving
the current OpenSpec context and specs; validate before creating Beads work.
The kit doctor also fails to parse installed OpenSpec 1.14.0, although direct
OpenSpec commands work. Resolve or document the compatibility check before
dispatch; do not install or downgrade unrelated tools implicitly.

After explicit acceptance, create a local Beads epic and isolated worktree.
Preserve all pre-existing main-worktree changes, especially the current
OpenWhispr edits in keybindings and the package manifest. Integration must retain
those edits. Obtain independent review after committing the implementation.

## Risks / Trade-offs

- v5 defaults differ from v4: validate the TOML, show the preview, and document
  approximations in the mapping above.
- GUI overrides win over managed TOML: inspect and back them up before activation;
  never silently discard existing overrides. None existed at preview creation.
- Preview files under `/tmp` disappear on reboot: label this session temporary;
  persistent startup changes happen only after acceptance and validation.
- Upstream widget/CLI changes: use installed-version validation and official docs.

## Migration Plan

1. Accept this contract, migrate missing workflow metadata without overwriting
   existing state, and create its Beads graph.
2. Implement source configuration, manifest, Niri command changes, archive policy,
   and user documentation in an isolated worktree.
3. Run the capability test plan, commit, independently review, and integrate.
4. Back up the live desktop files. Apply only the reviewed Noctalia and Niri
   targets, restart the preview as a normal native session, and verify surfaces
   and safe IPC actions. Contract acceptance authorizes this targeted host
   activation; it does not authorize a global apply, bootstrap, or package removal.
5. Keep backups and the known-good snapshot until a subsequent normal login
   confirms persistence. Do not trigger a reboot automatically.

Rollback restores the backed-up user files and stops the native process. The
upgraded Qt stack cannot run unmodified v4; returning to v4 requires a known-good
snapshot or a separately accepted runtime repair, not just reverting startup.
