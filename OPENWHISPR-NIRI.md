# OpenWhispr on Niri: local integration notes

This documents the working OpenWhispr 1.10.2 setup on the Arch/Niri workstation,
including its local compatibility workarounds and the behaviors tested by hand.
The launcher, paste shim, desktop entry, and Niri rules are managed by Chezmoi.

## Environment

- Arch Linux with Niri 26.04, running the native Wayland backend.
- Ghostty, Firefox on Wayland, and the native Discord app are the tested targets.
- OpenWhispr AppImage: `~/.local/opt/openwhispr/OpenWhispr.AppImage`.
- Niri reports the floater as app ID `open-whispr`, title `Voice Recorder`.
- The local dictation model (Orukeet) and assistant model (Qwen3.5 9B via
  Vulkan) initialized successfully.

## Managed files

| Chezmoi source | Purpose |
| --- | --- |
| `private_dot_local/private_bin/executable_openwhispr-niri` | Launches the AppImage with scoped environment compatibility settings and native Wayland. |
| `private_dot_local/private_bin/executable_openwhispr-toggle` | Toggles dictation from the Niri keybinding. |
| `private_dot_local/private_libexec/openwhispr-niri/executable_wtype` | Selects a paste key based on the focused Niri app ID, then invokes system `wtype`. |
| `private_dot_local/private_share/applications/openwhispr.desktop.tmpl` | Adds OpenWhispr to the desktop application list and Noctalia launcher. |
| `dot_config/niri/cfg/autostart.kdl` | Starts OpenWhispr through the managed launcher on Niri startup. |
| `dot_config/niri/cfg/keybinds.kdl` | Binds F16 and Ctrl+Space to the managed OpenWhispr toggle helper. |
| `dot_config/niri/cfg/rules.kdl` | Keeps the recording floater floating, unfocused, borderless, and positioned bottom-left. |
| `.chezmoiignore.tmpl` | Keeps this runbook out of the deployed home directory and scopes the integration to Arch. |

`KEYBINDINGS.md` also records that the OpenWhispr shortcut is Arch/Niri-only.

## Launch and hotkey path

- `Mod` is Caps Lock (`Mod3`) on this Niri setup. `Mod+Space` opens the Noctalia
  command launcher. The OpenWhispr desktop entry invokes
  `~/.local/bin/openwhispr-niri`.
- Niri autostart invokes the same launcher. To start it manually, run
  `~/.local/bin/openwhispr-niri`.
- F16 and Ctrl+Space run `~/.local/bin/openwhispr-toggle`, which calls
  `com.openwhispr.App.Toggle` over the session D-Bus. This starts or stops
  dictation without relying on OpenWhispr's raw Linux keyboard listener.
- The launcher sets `XDG_CURRENT_DESKTOP=GNOME` for the OpenWhispr process so
  version 1.10.2 initializes the D-Bus toggle service. It exports a synthetic
  `SWAYSOCK` path to select OpenWhispr's wlroots/`wtype` paste path, and prepends
  the local shim directory to `PATH`.
- The launcher uses `--ozone-platform=wayland`. These environment changes are
  scoped to OpenWhispr; they do not change the desktop session environment.
- The in-app Linux key-listener warning about missing input-device permission
  can remain visible. The Niri binding still toggles dictation, and this setup
  does not add the user to the `input` group or grant `/dev/uinput` access.

## Clipboard and paste path

The shim handles the exact `wtype` argument sequence OpenWhispr 1.10.2 uses
when its native Wayland target-window detection fails:

1. It asks `niri msg --json focused-window` for the focused window's `app_id`.
2. For recognized terminal IDs, including Ghostty, it leaves OpenWhispr's
   original `Shift+Insert` sequence unchanged.
3. For a non-empty, non-terminal app ID, it invokes `/usr/bin/wtype` with
   `Ctrl+V`, which worked in Firefox and Discord.
4. If Niri cannot provide an app ID, it leaves the original
   `Shift+Insert` sequence unchanged.

OpenWhispr writes transcription text to the Wayland clipboard, then simulates
the selected paste key. `wl-clipboard` provides the Wayland clipboard tools;
`wtype` sends the key sequence. The shim does not use `ydotool`, a background
`ydotoold` service, or raw input-device access.

The Arch package manifest `pkg/arch/pacman-desktop.txt` includes `fuse2`,
`wl-clipboard`, `wtype`, and `xdotool`; the Arch bootstrap installs official and
AUR packages through Shelly. `fuse2` supports the AppImage runtime. `xdotool`
remains an OpenWhispr/X11 fallback; the tested Niri paste path uses the local
shim and `wtype`.

## Floater behavior

The Niri rule matching `app-id="open-whispr"` and title `Voice Recorder`:

- opens the floater as floating and does not focus it on initial open;
- disables its focus ring and border and prevents the colored focus-ring fill
  from showing through the transparent window;
- places it 64 logical pixels from the bottom and left edges.

The bottom-left position and no-focus behavior were applied through Chezmoi.
Auto-hide works with this rule: the floater can appear during dictation without
taking focus from the target application, so auto-paste still lands there.

The floater reports a fixed size of `208×120`. Niri resize requests to
`320×180` did not change its reported dimensions. The right-click menu inside
the floater was observed to clip; the taskbar item's context menu provides a
way to start Medium recording, so no further change to the floater menu was
pursued.

## Validation record

### Confirmed

- F16 and Ctrl+Space start and stop dictation while OpenWhispr is not focused.
- OpenWhispr's local Orukeet model and Qwen3.5 9B Vulkan assistant model both
  initialized successfully.
- A direct `wl-copy` clipboard check pasted into the Firefox ChatGPT field and
  Ghostty.
- Key injection tests showed `Shift+Insert` did not paste in Firefox, while
  `Ctrl+V` did. This motivated the Niri app-ID shim.
- After adding the shim, automatic insertion was reported working in Firefox,
  Ghostty, and the native Discord app.
- Auto-hide initially caused focus to move to the floater and broke paste.
  After adding `open-focused false` to the matching Niri window rule, auto-hide
  and paste both worked.
- `niri validate` reported `config is valid` after removing the unsupported
  `on-xdg-activate` property. Niri 26.04 rejects that property.
- The floater's live Niri window ID changed during restarts; use the app ID and
  title to find it rather than relying on a saved window ID.

### Not confirmed in the recorded testing

- Preservation of long, multiline formatting and confirmation that multiline
  text never submits the prompt automatically.
- Behavior in applications other than Ghostty, Firefox, and Discord.
- Whether OpenWhispr's `set-main-window-input-region` helper errors persist
  after the final configuration. Those errors were seen in earlier logs; the
  focus-ring appearance and focus-stealing behavior were addressed separately
  by Niri rules.

## Known workaround boundaries

- `XDG_CURRENT_DESKTOP=GNOME` and the synthetic `SWAYSOCK` are compatibility
  hints for OpenWhispr 1.10.2, not native Niri support. An app update may change
  its D-Bus registration, compositor detection, or `wtype` arguments.
- The `wtype` shim assumes the Niri IPC JSON contains an `app_id` field and
  maintains a terminal app-ID allowlist. A new terminal may need to be added.
- The custom Niri binding is currently the global hotkey integration. The
  app's own raw-input listener warning is not evidence that this compositor
  binding failed.
- Niri 26.04 does not accept `on-xdg-activate "ignore"`; do not add it unless
  the installed Niri version's validator supports it.
- The floater remains tied to the workspace where it is open. No follow-focus
  workspace watcher or all-workspaces behavior is configured.

## Applying the managed files

From the Chezmoi source checkout, apply the relevant targets with:

```bash
chezmoi apply --parent-dirs \
  ~/.config/niri/cfg/autostart.kdl \
  ~/.config/niri/cfg/keybinds.kdl \
  ~/.config/niri/cfg/rules.kdl \
  ~/.local/bin/openwhispr-niri \
  ~/.local/libexec/openwhispr-niri/wtype \
  ~/.local/share/applications/openwhispr.desktop
```

The `--parent-dirs` option is needed if the local libexec directory does not
exist yet. After changing Niri rules, validate and reload them:

```bash
niri validate
niri msg action load-config-file
```
