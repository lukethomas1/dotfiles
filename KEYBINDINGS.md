# Keybindings — the cross-platform model

Arch (Niri) is the reference. macOS (AeroSpace) mirrors it. This document exists
because the mirroring is *not* a straight copy: macOS cannot represent Niri's
modifier model directly, and the workarounds are non-obvious enough that they
will look like mistakes to anyone who edits these files later.

## The three layers

| Layer | Arch | macOS | Modifier |
| --- | --- | --- | --- |
| Window manager | Niri | AeroSpace | **Caps Lock** |
| Multiplexer | herdr | herdr | **Cmd** |
| Terminal | Ghostty | Ghostty | Ctrl |

Alt belongs to the shell (readline word motion) and to herdr's `Alt+Space`
prefix. Nothing else may claim it.

## Why Caps Lock is spelled differently on each host

On Arch, `caps:hyper` in `dot_config/niri/cfg/input.kdl` turns Caps Lock into a
**real, fifth modifier bit** — XKB Mod3 — which Niri claims via
`mod-key "Mod3"`. Shift, Ctrl, Alt and Super remain four independent bits
alongside it. Nothing collides.

macOS has no fifth bit. AeroSpace understands only `cmd`, `alt`, `ctrl`, `shift`,
and cannot see Caps Lock at all. So on macOS, Caps Lock cannot *become* a
modifier — it can only **impersonate a combination of the four that already
exist**. Karabiner does that impersonation (`dot_config/karabiner/karabiner.json`).

Whichever modifiers are spent on the impersonation stop being independently
usable. That budget is what dictates the chord:

- Niri uses four chord families: `Mod`, `Mod+Shift`, `Mod+Ctrl`, `Mod+Ctrl+Shift`.
- So **Ctrl and Shift must both stay free**.
- Bare Alt is the shell's; bare Cmd is herdr's — so the chord needs both.

That leaves exactly one option: **Caps Lock → `Alt+Cmd`**.

    Caps            ->  alt-cmd-*
    Caps+Shift      ->  alt-cmd-shift-*
    Caps+Ctrl       ->  alt-ctrl-cmd-*
    Caps+Ctrl+Shift ->  alt-ctrl-cmd-shift-*

You press the same physical keys on both hosts. Only the wire format differs.

**Do not "simplify" this to the popular Hyper recipe** (`Cmd+Ctrl+Alt+Shift`).
Shift would then already be asserted inside the chord, making `Mod+H` and
`Mod+Shift+H` indistinguishable to AeroSpace — which silently destroys the
focus-vs-move distinction the whole config is built on. `Ctrl+Alt+Cmd` fails the
same way for `Mod+Ctrl`.

AeroSpace also requires one consistent modifier order (`alt-ctrl-cmd-shift`);
declaring the same chord in two orders is a config error, not a duplicate.

## Why Ghostty needs `unbind` lines on macOS but not Linux

Ghostty's defaults are platform-conditional: internally, `ctrlOrSuper()` maps
every "Cmd" shortcut to **Ctrl** on Linux and **Super** on macOS. So on Arch,
`super+t` is unbound and falls straight through to herdr. On macOS the same key
is `new_tab` and Ghostty eats it.

`dot_config/ghostty/config.ghostty.tmpl` therefore unbinds the six colliding
chords. Those lines are **silent no-ops on Linux** (unbinding an unbound key
cannot fail), which is why one shared, untemplated file serves both hosts.

Two traps, both load-bearing:

- **`super+-`, not `super+minus`.** Ghostty parses `minus` as a *physical* key
  trigger, but the default Cmd+− font-size binding is a *unicode* trigger, and
  unbinding is exact-match only. `super+minus=unbind` parses fine and does
  nothing at all.
- **`macos-option-as-alt = true` is not optional.** Option+Space produces a
  printable character (non-breaking space), so if the setting resolves to false,
  Ghostty consumes the Alt bit for text translation and sends the NBSP instead
  of the escape sequence — killing herdr's prefix.

The whole scheme depends on herdr enabling the **Kitty keyboard protocol**
(it does, automatically). Without it, Ghostty on macOS encodes *nothing* for
Cmd+key, and unbinding would leave the keys dead rather than forwarded.

## Why Cmd+H needs a `defaults write`

Cmd+H is the one key Ghostty cannot hand over. "Hide Ghostty" is hardcoded in
Ghostty's `MainMenu.xib` and is never synced from config, so it can be neither
`unbind`-ed nor `ignore`-d — and since 1.3.0 Ghostty consults the menu bar
*first* for ordinary bindings, which makes the widely-repeated
`keybind = super+h=ignore` advice stale.

`run_onchange_darwin-keyboard.sh.tmpl` retitles the menu shortcut instead.

## Accepted trade-offs

These were reviewed and accepted. They are not bugs.

**The `Mod+Alt` family cannot exist on macOS.** Alt is inside the Caps chord, so
Caps+Alt is indistinguishable from Caps alone. Cost: Niri's `Mod+Alt+1…9`
(reposition workspace at index — AeroSpace has no equivalent anyway) and
`Mod+Alt+L` (lock screen — use the native `Ctrl+Cmd+Q` on macOS).

**`Mod+Space` is deliberately unbound on macOS.** `⌥⌘Space` is a
WindowServer-level Spotlight hotkey and would likely beat AeroSpace. On macOS the
launcher is Spotlight on `Cmd+Space`, which is already the muscle memory.

**Cmd sits inside the WM chord, so a dead AeroSpace is not a no-op.** If
AeroSpace crashes or loses its Accessibility permission, Caps+W degrades to
`⌥⌘W` = *Close All Windows*, and Caps+H to *Hide Others*. The
`run_onchange_darwin-keyboard.sh.tmpl` script neutralizes both globally via
`NSUserKeyEquivalents` precisely to defuse this.

**AeroSpace wins these app shortcuts; they are gone on macOS.** `⌥⌘←`/`⌥⌘→`
(previous/next tab in Safari & Chrome — the one most likely to sting), `⌥⌘B`
(bookmarks), `⌥⌘L` (downloads), `⌥⌘T` (toolbar), `⌥⌘F` (find & replace),
`⌥⌘H` (hide others), `⌥⌘W` (close all windows).

**Test these three after any macOS update**, because Cmd is inside the chord and
they brush against system-level handlers: `alt-cmd-tab` (Dock app switcher),
`alt-cmd-q` (Quit), and anything on `alt-cmd-space`.

**No overview on macOS.** AeroSpace has no equivalent of Niri's `Mod+O`. It is
mapped to Mission Control as an approximation.

**Niri's column operations have no macOS counterpart** — AeroSpace is a BSP tree,
not a scrollable column strip. `Mod+C` (center column), `Mod+Ctrl+F` (expand
column), and `Mod+Home`/`Mod+End` (first/last column) are Arch-only.

**Ghostty's `ctrl+h` / `ctrl+w` / `ctrl+l` were removed on both hosts.** They
drove Ghostty's own splits, which herdr replaced, while costing three standard
terminal keys: Ctrl+H (Backspace), Ctrl+W (kill-word) and Ctrl+L (clear-screen).
Clear-screen mattered: Cmd+K now belongs to herdr, so Ctrl+L was the only one
left.

**herdr `[keys]` values are arrays, on purpose.** A bare string *replaces*
herdr's default binding rather than adding to it. The arrays keep the `prefix+…`
chords alive alongside the Cmd chords — which is the fallback for exactly the
situations where the OS claims a Cmd key.

## Bootstrap ordering (macOS)

**If these configs are applied to a Mac without Karabiner running, the window
manager answers no key at all.** Every AeroSpace binding is on `alt-cmd-*`, and
nothing emits that chord until Karabiner is remapping Caps Lock. That is the
expected failure, not a bug — but it is a miserable state to land in, because
nothing about it points at the cause.

`bootstrap.sh` is therefore ordered to make it unreachable:

    fetch source (chezmoi init, NO apply)
      -> install packages (brew bundle: Karabiner, AeroSpace, …)
      -> launch Karabiner + AeroSpace to raise their permission prompts
      -> PREFLIGHT GATE  ── aborts here if anything is unapproved
      -> chezmoi apply

Configuration is never written to a machine that cannot yet honour it. The gate
(`preflight_macos()`) is a hard stop, not a warning, and checks:

| Check | How |
| --- | --- |
| Karabiner installed | `/Applications/Karabiner-Elements.app` exists |
| Driver extension approved | `systemextensionsctl list` reports `activated enabled` (an unapproved one reports `activated waiting for user`) |
| Karabiner services running | any process under the `org.pqrs` install prefix |
| Karabiner responsive | `karabiner_cli --show-current-profile-name` succeeds |
| AeroSpace Accessibility granted | `aerospace list-monitors` succeeds; the CLI can only reach a server that has the grant |

None of these can be approved from a script. On failure the script prints the
exact System Settings path for each and exits non-zero. Grant them and re-run —
bootstrap is idempotent and picks up where it left off.

**Do not look for Karabiner in System Settings → Privacy & Security → Input
Monitoring.** It is normally not listed there at all: granting Accessibility
covers input monitoring for it, per pqrs.org's own installation guide. Hunting
for the missing entry is a dead end.

The service check is matched on the `org.pqrs` install prefix rather than a
process name, on purpose. Those names churn across major versions — v13/v14 ran a
`karabiner_grabber` binary, which 16.x replaced with a root
`Karabiner-Core-Service`. A check pinned to a name that no longer exists fails
*closed*, blocking a bootstrap whose permissions are actually fine. (That is not
hypothetical; the first version of this gate did exactly that.)

It also warns if System Settings → Keyboard → Modifier Keys holds a custom
mapping: a second Caps Lock remap there silently fights Karabiner, and is the
usual cause of "Karabiner isn't working".

Karabiner may rewrite `~/.config/karabiner/karabiner.json` (reformatting it, or
adding fields on version upgrades), which will show up as chezmoi drift. Re-add
intentional changes to the source file rather than to the deployed one.

## Files

| File | Role |
| --- | --- |
| `dot_config/niri/cfg/keybinds.kdl` | Arch WM — the reference |
| `dot_config/niri/cfg/input.kdl` | `caps:hyper` → Mod3 |
| `dot_config/aerospace/aerospace.toml` | macOS WM — mirrors Niri |
| `dot_config/karabiner/karabiner.json` | macOS: Caps Lock → Alt+Cmd |
| `dot_config/herdr/config.toml` | Multiplexer — shared, identical on both |
| `dot_config/ghostty/config.ghostty.tmpl` | Terminal — shared; unbinds are no-ops on Linux |
| `run_onchange_darwin-keyboard.sh.tmpl` | macOS menu-shortcut + screenshot overrides |
