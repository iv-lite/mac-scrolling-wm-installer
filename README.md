# nehir-wm-installer

A niri-like window management setup for macOS, built on **Nehir**
(`apphane-dev/nehir` — niri-style scrolling-strip tiler with a
live-reloading split-TOML config, native menu-bar workspace indicators,
and a native mouse edge-warp between displays), **JankyBorders**
(active/inactive focus border), and **Ghostty** (terminal). Driven by
Cmd+Option-key shortcuts that don't fight macOS defaults.

## Requirements

- macOS 15+ (Nehir's own minimum — higher than the Rift-era setup this
  replaced, which supported macOS 13+)
- Apple Silicon or Intel; Homebrew installed or auto-installed
- No Karabiner, no disable of System Integrity Protection

## Quick start

```sh
./install
```

Re-running `./install` **upgrades** an existing setup: Homebrew components
(Nehir, JankyBorders, Ghostty, tccutil-rs) are updated (no-op when current),
configs are refreshed from this repo (previous copies kept as `*.bak`), and
Nehir/JankyBorders are restarted so the new binaries/configs apply
immediately.

The installer runs these steps from `scripts/`:

| Script | Purpose |
|---|---|
| `install-deps` | Install Homebrew if missing, tccutil-rs |
| `configure-system` | Show the native menu bar (Nehir draws its workspace indicators in it) |
| `install-ghostty` | Install Ghostty + write `~/.config/ghostty/config` (frameless title bar) |
| `install-nehir` | Install Nehir (`guria/tap`) + write `~/.config/nehir/{settings,hotkeys,workspaces}.toml` + app-rule samples |
| `install-borders` | Install JankyBorders + write `~/.config/borders/bordersrc` |
| `install-helpers` | Install the shortcut cheat-sheet helpers into `~/.config/mac-scrolling-wm/helpers/` and install the macOS cheat-sheet viewer app (fetches a pre-built release from GitHub at `iv-lite/mac-cheatsheet-viewer`, falls back to a local source build) |
| `grant-permissions` | Grant Accessibility via tccutil-rs (user → sudo → manual fallback) |
| `enable-services` | Launch Nehir + start JankyBorders |

### After install

1. **No logout required** — unlike this repo's previous Rift setup, Nehir
   doesn't depend on macOS's "Displays have separate Spaces" mode; it
   simulates virtual workspaces itself.
2. Nehir tiles in a **niri-style scrolling strip**; workspaces `1..9` are
   persistent (fixed, not dynamic rows).
3. Nehir draws **workspace badges in the native menu bar** — click a badge
   to switch. JankyBorders draws a border around the focused window.
4. If the Accessibility grant failed, grant it manually: System Settings →
   Privacy & Security → Accessibility (enable `Nehir`).
5. Nehir has **no "start at login" setting of its own** — add it once via
   System Settings → General → Login Items & Extensions → `+` → Nehir.
6. Ghostty opens **frameless** (`macos-titlebar-style = hidden` in
   `~/.config/ghostty/config`) — drag its window edge with `Option+Click`.

## Keybindings

Nehir modifiers: **Option+Cmd** (window focus/state/columns),
**Ctrl+Option** (workspace prev/next), **Ctrl+Cmd** (display focus). Shift
in the Option+Cmd lane **moves** the focused window instead of just
navigating.

> This re-encodes this repo's Rift-era Cmd+Option/Cmd+Ctrl/Ctrl+Option
> muscle memory onto **Nehir's fixed action catalog** in
> `config/nehir/hotkeys.toml`. Nehir's hotkeys can only trigger its own
> built-in actions — unlike Rift's `{ exec = [...] }` bindings, there is no
> generic "run a shell command" binding — so a few things that used to be
> hotkeys are gone or changed. Every gap below is intentional, not an
> oversight; see the comment block at the top of `hotkeys.toml` for the
> same list inline with the config.

### Navigation & layout

| Shortcut | Action |
|---|---|
| `Option` + `Cmd` + Arrows | Move focus between windows |
| `Option` + `Cmd` + `Shift` + Arrows | Move window (swap) |
| 3-finger swipe (← / →) | Switch columns |
| `Option` + `Cmd` + `W` | Cycle the focused column width forward through 0.3 / 0.5 / 1.0 |
| `Option` + `Cmd` + `Shift` + `W` | Cycle the focused column width backward through the same presets |
| `Option` + `Cmd` + `M` | Jump the focused column straight to full width (stays tiled) |

> **Native now, no more helper script.** Rift had no numeric width-preset
> primitive, so this repo shipped `scripts/cycle-column-width`, a
> bash+python script that computed exact resize deltas via `rift-cli query
> layout`. Nehir has a built-in preset array
> (`[niri] columnWidthPresets = [0.3, 0.5, 1.0]` in `settings.toml`) and
> native "cycle column width"/"toggle column full width" actions — the
> script is gone entirely.
>
> **Dropped, no equivalent action exists:** "center the focused column"
> (Rift's `Cmd+Option+Space`) and "toggle orientation" (Rift's
> `Cmd+Option+/`) — orientation is now a static per-monitor config value,
> not a runtime toggle (see Multi-monitor below).

### Workspaces (1-9, fixed)

| Shortcut | Action |
|---|---|
| `Ctrl` + `Option` + `↑` / `↓` | Previous/next workspace |
| `Option` + `Cmd` + `1..9` | Switch directly to workspace 1-9 |
| `Option` + `Cmd` + `Shift` + `1..9` | Move window to workspace 1-9 |
| `Option` + `Cmd` + `Tab` | Jump to the last-focused workspace |
| 3-finger swipe (↑ / ↓) | Switch workspaces (trackpad) |

### Displays (multi-monitor)

| Shortcut | Action |
|---|---|
| `Ctrl` + `Cmd` + `→` | Focus the next display |
| `Ctrl` + `Cmd` + `←` | Focus the previous display |

> **Behavior change from Rift.** Rift had native 4-directional display
> commands (`focus_display`/`move_window_to_display` with
> left/right/up/down selectors). Nehir's monitor-focus model is
> next/previous/last, not directional, and it has **no action at all** for
> "move a window to a display in a direction" or "warp just the mouse to a
> display in a direction" — those two Rift hotkeys (`Cmd+Ctrl+Shift+Arrows`,
> `Cmd+Ctrl+Option+Arrows`) have nothing to bind to and are gone. Moving the
> mouse to a screen edge now warps it automatically (see Multi-monitor
> below), so the explicit mouse-warp hotkey isn't needed anyway.

### Window state

| Shortcut | Action |
|---|---|
| `Option` + `Cmd` + `V` | Toggle floating/tiled |
| `Option` + `Cmd` + `O` | Stack / unstack the focused column |
| `Option` + `Ctrl` + `Cmd` + `E` | Expel the focused window from its column |
| `Option` + `Shift` + `Cmd` + `D` | Toggle debug trace capture (Developer Mode) |

> Mapped to the closest available Nehir action: "stack/unstack" ≈ Nehir's
> stacked/tabbed column display; "un-join windows" ≈ Nehir's "expel window
> from column"; "debug" ≈ Nehir's trace-capture toggle (gated behind
> Developer Mode in Settings → Diagnostics — the actual behavior differs
> from Rift's plain debug dump).

### Apps & misc

Rift bound `Cmd+Ctrl+T` (open Ghostty), `Cmd+Shift+?` (cheat sheet), and
`Cmd+Option+Shift+R` (reload config) as `exec`/native actions. None of
these have a Nehir equivalent:

- **Open Ghostty:** use Spotlight (`Cmd+Space`) or the Dock — no generic
  "launch app" hotkey action exists in Nehir.
- **Cheat sheet:** run `~/.config/mac-scrolling-wm/helpers/display-shortcuts`
  manually (see below), or bind your own shortcut to it with a tool of your
  choice (Raycast, a Shortcuts.app quick action, etc.) — out of scope for
  this installer.
- **Reload config:** unnecessary — every file under `~/.config/nehir/` is
  watched and applied live, always.

### Shortcut cheat sheet

`~/.config/mac-scrolling-wm/helpers/display-shortcuts` regenerates the
cheat-sheet JSON from the live Nehir config and opens it in
`mac-cheatsheet-viewer`, a borderless always-on-top overlay (Esc / Cmd+W to
close). It has no global hotkey bound to it anymore (see above) — run it
directly, or from Spotlight/a Raycast script. The pieces:

- `helpers/generate-shortcuts-json` — parses `~/.config/nehir/hotkeys.toml`
  (Nehir's `[section]` / `key = "Modifier+Combo"` format), humanizes the
  chords, and emits `~/.config/nehir/cheatsheet.json` (curated action
  labels; unknown bindings fall back to a title-cased guess from the key
  name).
- `helpers/display-shortcuts` — runs the generator and opens the viewer.
- `mac-cheatsheet-viewer` — a separate repo (`iv-lite/mac-cheatsheet-viewer`)
  holding the Tauri app whose CLI arg is the JSON path. `install-helpers`
  fetches the `.app.zip` of the newest GitHub release and overwrites the
  installed bundle on every run. `MAC_WM_VIEWER_REPO` changes the repo,
  `MAC_WM_VIEWER_TAG` pins an exact tag; falls back to a local source build
  at `../mac-cheatsheet-viewer` if the fetch fails.

Installed helpers live in `~/.config/mac-scrolling-wm/helpers/` (copied on
`install`, removed by `uninstall`).

## The menu bar & notch

- **Workspace indicators** live in the **native menu bar**
  (`[workspaceBar]` in `config/nehir/settings.toml`): badges for every
  workspace, click to switch. macOS already lays the menu bar around the
  notch, so no notch configuration is needed.
- **Focus cues** come from **JankyBorders** (`config/borders/bordersrc`).
  Nehir does have a native `[borders]` setting, but it's a single color for
  the focused window only — no distinct inactive-window color — so it's
  kept off (`enabled = false`) in favor of JankyBorders' two-tone borders.
- Tune the gap around the menu bar/notch via `[gaps.outer]` in
  `~/.config/nehir/settings.toml`.

## Multi-monitor

- Nehir gives each display its own tiling layout and workspace assignment
  (`config/nehir/workspaces.toml`).
- Arrange displays **vertically** in System Settings → Displays, even if
  they sit physically side-by-side. Nehir's own docs give the same
  rationale Rift's did: Nehir parks transient offscreen tiled windows near
  the horizontal screen edge, and with side-by-side monitors those parked
  windows can bleed onto the neighboring display (macOS doesn't allow fully
  hiding an external app window by position alone). If you need a fixed
  side Dock as well, Nehir's experimental **Dock Shield**
  (Settings → Diagnostics, off by default) masks that leaked strip.
- **Mouse edge-warp between displays is native to Nehir** — no separate
  process needed. `[mouseWarp]` in `settings.toml` (`enabled`, `axis`,
  `margin`, `monitorOrder`) makes the cursor cycle to the next monitor when
  it hits a display's edge, in a continuous logical order (wrapping past
  either end). This replaces this repo's earlier
  [Hammerspoon](https://www.hammerspoon.org)-based `WarpMouse.spoon` Spoon
  entirely — Hammerspoon is no longer a dependency of this installer at
  all.
- **Horizontal window stacking, if you want it.** Nehir's columns stack
  multiple windows **vertically** by default (same as niri/Rift). Each
  monitor can flip that with a per-monitor override —
  `config/nehir/monitors.d/<name>.toml`:
  ```toml
  [match]
  name = "Your Display Name"

  [orientation]
  orientation = "vertical"
  ```
  This rotates that monitor's *entire* scroll axis: the workspace then
  scrolls top-to-bottom instead of left-to-right, and windows that would
  have been a vertical column now stack **horizontally** (side by side)
  instead. It's a per-monitor axis flip, not an independent per-column
  toggle — there's no way to make one column stack horizontally while its
  neighbors stay vertical on the same monitor. This repo ships
  `monitors.d/` empty (default `"horizontal"` orientation everywhere); add
  a file like the one above only if you want that specific monitor
  flipped.

## No title bars (the macOS reality)

macOS tiling window managers (Nehir included — same as yabai/AeroSpace/the
Rift-era setup) cannot hide a window's title bar or toolbar: each app draws
its own chrome, so removal has to happen per app. This installer does what's
safely possible:

- **Ghostty is frameless by default** — `~/.config/ghostty/config` sets
  `macos-titlebar-style = hidden` and `macos-window-buttons = hidden` (keeps
  rounded corners and borders). Drag the window by its edge with `Option+Click`.
- **Other apps:** use each app's native toggle:
  | App | How |
  |---|---|
  | Finder, Mail, Notes, Safari, Chrome, Slack | `View → Hide Toolbar` (often `Cmd+Option+T`) |
  | Safari fullscreen | `View → Always Show Toolbar in Full Screen` off |
  | Ghostty | handled for you above |
  | VS Code | no clean path since 1.94 (hair-line third-party extensions only — not shipped) |

> Global tools that strip titlebars everywhere (e.g. `Brutalium`, `winBuddy`)
> inject code into running apps and require disabling SIP — out of scope here,
> the same reason this project never disables SIP.

## Troubleshooting

**Nehir won't start / no menu bar indicators.** Nehir requires
Accessibility. If the grant failed, give the terminal **Full Disk Access**
first, then:

```sh
bash scripts/grant-permissions
killall Nehir; open -a Nehir
```

A quick health check of the whole stack (requires `ipcEnabled = true` in
`~/.config/nehir/settings.toml`, which this repo's config ships with):

```sh
/Applications/Nehir.app/Contents/MacOS/nehirctl query workspaces
/Applications/Nehir.app/Contents/MacOS/nehirctl query displays
```

**Config changes aren't applying.** Every file under `~/.config/nehir/`
(`settings.toml`, `hotkeys.toml`, `workspaces.toml`, `apprules.d/*.toml`,
`monitors.d/*.toml`) is watched via `DispatchSource` and applied
immediately — no reload key, no restart. If an edit doesn't take, check
Settings → Diagnostics for a parse warning (Nehir never silently rewrites
your file; a bad key is reported there, not applied).

**Mouse doesn't warp at a display edge.** Confirm `[mouseWarp] enabled =
true` in `settings.toml`, and that `monitorOrder` is empty or lists all of
your displays. This is a Nehir built-in, not a separate process — there's
no Hammerspoon/Spoon involved to debug anymore.

## Uninstall

```sh
./uninstall
```

Quits Nehir and stops JankyBorders, cleans up any **legacy** residue from
this repo's earlier setups (Rift launchd service, `WarpMouse.spoon` +
its `~/.hammerspoon/init.lua` entry, Paneru, `rift-swipe`, AeroSpace,
AeroSpaceBar, Aegis — services, LaunchAgents, apps), moves configs (from
`~/.config/nehir`, `~/.config/borders`, `~/.config/ghostty`, plus any
legacy `~/.config/rift`, `~/.config/paneru`, `~/.config/mac-scrolling-wm`,
`~/.config/aerospace`, `~/.config/aegis`) to
`~/.config/backups/uninstall-<timestamp>/`, then asks you which
formulae/casks to **keep** (interactive numbered menu). Untaps `guria/tap`,
`FelixKratz/formulae`, `uinaf/tap` (and legacy `acsandmann/tap`,
`nikitabobko/tap`, `rdrkr/tap` only when nothing kept depends on them), and
restores the native menu bar. Hammerspoon itself (if a legacy install left
it) is offered separately in the keep/remove menu, same as any other
package — this installer never force-removes a general-purpose tool it
doesn't own.

## Testing in a macOS VM

The `tests/preview` workflow runs `./install` inside a real macOS guest VM.
The host OS is auto-detected and a matching hypervisor backend is used:

| Host | Backend | Requirements |
| --- | --- | --- |
| macOS (Apple Silicon) | Tart (`tests/lib/backend_tart.sh`) | macOS 15+, Homebrew; `tart`/`sshpass` auto-installed |
| Linux x86_64 | QEMU/KVM + OpenCore (`tests/lib/backend_qemu.sh`) | `/dev/kvm`, `qemu-system-x86`, `sshpass`, `rsync`, a macOS Sequoia disk |

macOS host:

```sh
./tests/preview setup        # installs tart/sshpass (auto), clones host-matched base image
./tests/preview up           # boot guest, live-mount the repo, wait for SSH
./tests/preview install      # run ./install in the guest (asks to clean up afterwards)
./tests/preview check        # query Nehir state + installed formulae
./tests/preview shot         # screenshot the tiling into tests/screenshots/
./tests/preview clean        # interactively remove VM, tart, sshpass, base image
```

Linux x86_64 host:

```sh
export TESTS_MACOS_DISK=/path/to/macos-sequoia.qcow2   # required (installed guest, admin/admin)
./tests/preview setup        # validates the disk, fetches OpenCore, creates qcow2 overlays
./tests/preview up           # boot the guest (watch the first boot once to confirm login)
./tests/preview install      # rsyncs the repo into the guest, then runs ./install
./tests/preview check
./tests/preview shot
./tests/preview clean
```

On Linux the provided `TESTS_MACOS_DISK` is never written to — the VM boots
writable qcow2 overlays (`tests/.preview-qemu/bare.qcow2`,
`provisioned.qcow2`). Bare/provisioned snapshots follow the same semantics as
Tart: `snapshot` captures the current state into `provisioned`, `restore bare`
resets to the golden baseline. Extra tunables are documented in
`tests/lib/backend_qemu.sh` (`TESTS_OPENCORE`, `TESTS_OVMF_CODE`,
`TESTS_OVMF_VARS`, `TESTS_SSH_PORT`, default 22222).

On macOS, dependencies (`tart`, `sshpass`) are installed automatically on
demand and can be removed with `clean`; on Linux, failing-check hints print
the distro package install commands. See `./tests/preview help` for the full
command list. Limitations: single virtual display (multi-monitor can't be
tested), Accessibility may need one manual grant inside the guest. The test
VM is named `nehir-test`.

## Project layout

```
install                   Main installer (runs scripts/*)
uninstall                 Full uninstaller with interactive keep menu
scripts/                  Per-component install/system/accessibility steps
config/nehir/             Nehir config: settings.toml, hotkeys.toml,
                          workspaces.toml, apprules.d/, monitors.d/
config/borders/           JankyBorders focus-border config — bordersrc
config/ghostty/           Ghostty config (frameless title bar)
helpers/                  shortcut cheat-sheet: generate-shortcuts-json,
                          display-shortcuts (mac-cheatsheet-viewer app lives
                          in its own repo at iv-lite/mac-cheatsheet-viewer)
tests/                    VM test workflow (tests/preview + lib/ backends)
```

Configs are installed to `~/.config/{nehir,borders,ghostty}` (plus shortcut
helpers under `~/.config/mac-scrolling-wm/`); existing files are backed up
(`.bak`) before overwriting. Every file under `~/.config/nehir/` live-reloads
on save — there's no restart or reload hotkey to remember.

> **Note on the history:** an early version of this installer targeted
> AeroSpace (i3-style tree tiler) with AeroSpaceBar in the menu bar; a
> subsequent version used Rift (niri-style scrolling tiler) with the
> plain-Option keybinding scheme from its upstream defaults; that was then
> replaced by **Paneru** (a different niri-style sliding-strip tiler with a
> Lua config) for its native infinite-strip paging; a later version
> returned to **Rift**, with a Cmd+Option keybinding scheme carried over
> from the Paneru era, JankyBorders for the focus border Rift didn't draw
> natively, and a Hammerspoon Spoon (`WarpMouse.spoon`) for the mouse
> edge-warp Rift didn't have. This version switches to **Nehir** — the same
> niri-style scrolling-strip model, but with a native mouse edge-warp and
> native column-width presets built in, so the Hammerspoon Spoon and the
> hand-rolled `cycle-column-width` script are both gone; JankyBorders stays,
> since Nehir's own border can't do the two-tone active/inactive colors
> JankyBorders can.
