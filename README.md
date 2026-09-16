# nehir-wm-installer

A niri-like window management setup for macOS, built on **Nehir**
(`apphane-dev/nehir` — niri-style scrolling-strip tiler with a
live-reloading split-TOML config and native menu-bar workspace indicators),
**JankyBorders** (active/inactive focus border), **Hammerspoon +
`WarpMouse.spoon`** (continuous horizontal cursor wrap between displays),
and **Ghostty** (terminal). Driven by Cmd+Option-key shortcuts that don't
fight macOS defaults.

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
| `install-hammerspoon` | Install Hammerspoon + deploy `WarpMouse.spoon` (continuous horizontal cursor wrap between displays, on by default) |
| `install-borders` | Install JankyBorders + write `~/.config/borders/bordersrc` |
| `install-helpers` | Install the shortcut cheat-sheet helpers into `~/.config/mac-scrolling-wm/helpers/` and install the macOS cheat-sheet viewer app (fetches a pre-built release from GitHub at `iv-lite/mac-cheatsheet-viewer`, falls back to a local source build) |
| `grant-permissions` | Grant Accessibility via tccutil-rs (user → sudo → manual fallback) |
| `enable-services` | Launch Nehir + start JankyBorders |

### After install

1. **No logout required** — unlike this repo's previous Rift setup, Nehir
   doesn't depend on macOS's "Displays have separate Spaces" mode; it
   simulates virtual workspaces itself.
2. Nehir tiles in a **niri-style scrolling strip**; one persistent
   workspace per monitor (fixed, not dynamic rows).
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

### Workspaces (one per monitor, fixed)

| Shortcut | Action |
|---|---|
| `Ctrl` + `Option` + `↑` / `↓` | Previous/next workspace |
| `Option` + `Cmd` + `1..3` | Switch directly to a monitor's workspace (`1` main, `2` secondary, `3` tertiary) |
| `Option` + `Cmd` + `Shift` + `1..3` | Move window to a monitor's workspace |
| `Option` + `Cmd` + `Tab` | Jump to the last-focused workspace |
| 3-finger swipe (↑ / ↓) | Switch workspaces (trackpad) |

> **Behavior change from the earlier Rift-era 9-workspace setup.** Rift's
> fixed set was 9 numbered workspaces, all on the main display. Nehir's
> niri-style scrolling strip already handles many windows on a single
> workspace via horizontal scrolling, so this repo now ships just **one
> workspace per monitor** (`config/nehir/workspaces.toml`) instead —
> `"1"` on `main`, `"2"` on `secondary`, `"3"` on `tertiary` (only
> resolves if a 3rd display is connected).

### Displays (multi-monitor)

| Shortcut | Action |
|---|---|
| `Ctrl` + `Cmd` + Arrows | Focus a display (Left/Up = previous, Right/Down = next) |
| `Ctrl` + `Cmd` + `Shift` + Arrows | Move the focused window to a display |

> **Behavior change from Rift.** Rift had native 4-directional display
> commands (`focus_display`/`move_window_to_display` with left/right/up/down
> selectors). Nehir's monitor-focus model is next/previous/last, not
> spatial — approximated here by pairing Left/Up to "previous" and
> Right/Down to "next" (for the common 2-monitor case these are
> equivalent anyway). "Move window to a display" has no generic Nehir
> action either; it's approximated via `windowToWorkspaceOnMonitor`,
> which moves the window to workspace `"2"` (the secondary monitor's
> workspace, from `workspaces.toml`) regardless of arrow direction, since
> with 2 monitors there's only one possible destination. Neither
> approximation is verified against a real Nehir install — see the
> comments in `config/nehir/hotkeys.toml`. "Warp just the mouse to a
> display" (Rift's `Cmd+Ctrl+Option+Arrows`) still has nothing to bind to
> and is gone — moving the mouse to a screen edge warps it automatically
> via Hammerspoon's `WarpMouse.spoon` instead (see Multi-monitor below).

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
- **Hidden on the built-in display.** `config/nehir/monitors.d/builtin.toml`
  overrides `[workspaceBar] enabled = false` for a display matched by
  `name = "Built-in Retina Display"` (macOS's standard name for a
  MacBook's internal screen on most current models — adjust the `name`
  if yours reports differently), so the bar only shows on external
  monitors.
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
- **Physically moving the mouse to a screen edge only auto-crosses to the
  next monitor natively if that edge matches the System Settings
  arrangement** — with the required vertical arrangement, that's only the
  top/bottom edges. **`WarpMouse.spoon`** (installed and enabled by
  default, `scripts/install-hammerspoon`) closes this gap for the
  left/right edges: it watches the cursor and, when it hits a display's
  left or right edge, warps it to the far edge of the next display in a
  logical left-to-right cycle (wrapping past either end), carrying the
  cursor's captured velocity across the boundary for a brief momentum
  glide instead of a flat teleport — no hotkey needed, it feels like one
  continuous horizontal desktop. It only ever moves the cursor — a window
  being **dragged** across that same virtual boundary is not carried
  along. Tunables live on the Spoon object in `~/.hammerspoon/init.lua`
  (before `:start()`): `edgePx`, `landingInset`, `continueAfterWarp`.

  This runs as a [Hammerspoon](https://www.hammerspoon.org) Spoon because
  Nehir has **no built-in cross-display mouse warp at all** — unlike
  JankyBorders (kept over Nehir's own single-color border for its
  two-tone colors), `WarpMouse.spoon` isn't a preference over a native
  alternative, it's the only mechanism for this behavior.
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
  neighbors stay vertical on the same monitor. This repo ships one
  default override, `monitors.d/builtin.toml` (see "The menu bar &
  notch" above), and otherwise leaves orientation at `"horizontal"`
  everywhere; add a file like the one above only if you want a specific
  monitor's scroll axis flipped.

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

**WarpMouse.spoon is installed but the cursor never crosses at a screen
edge.** First confirm Hammerspoon itself is running (menu bar icon) and
has Accessibility: System Settings → Privacy & Security → Accessibility →
Hammerspoon enabled. If you just granted it, reload Hammerspoon's config
(menu bar icon → Reload Config, or `killall Hammerspoon && open -a
Hammerspoon`) — a grant made while it was already running doesn't always
take effect until it restarts. If it's still not working, open
Hammerspoon's Console (menu bar icon → Console) and check for Lua errors
from `WarpMouse`, or add temporary logging inside
`~/.hammerspoon/Spoons/WarpMouse.spoon/init.lua` (e.g. a `print()` at the
top of the `hs.eventtap.new` callback) and watch the Console live while
moving the mouse to an edge — empty output means the event tap isn't
receiving events (an Accessibility problem), while output that never
reaches the warp call means the edge-detection math isn't triggering for
your actual display arrangement (`hs.screen.allScreens()` in the Console
shows each screen's frame to compare against — check it matches the
System Settings arrangement described in Multi-monitor above).

## Uninstall

```sh
./uninstall
```

Quits Nehir and stops JankyBorders, removes `WarpMouse.spoon` and its
entry from `~/.hammerspoon/init.lua` (leaving Hammerspoon itself
installed — it's offered separately in the brew keep/remove menu below,
same as any other package), cleans up any **legacy** residue from this
repo's earlier setups (Rift launchd service, Paneru, `rift-swipe`,
AeroSpace, AeroSpaceBar, Aegis — services, LaunchAgents, apps), moves
configs (from `~/.config/nehir`, `~/.config/borders`, `~/.config/ghostty`,
plus any legacy `~/.config/rift`, `~/.config/paneru`,
`~/.config/mac-scrolling-wm`, `~/.config/aerospace`, `~/.config/aegis`) to
`~/.config/backups/uninstall-<timestamp>/`, then asks you which
formulae/casks to **keep** (interactive numbered menu). Untaps `guria/tap`,
`FelixKratz/formulae`, `uinaf/tap` (and legacy `acsandmann/tap`,
`nikitabobko/tap`, `rdrkr/tap` only when nothing kept depends on them), and
restores the native menu bar.

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
config/hammerspoon/       WarpMouse.spoon (continuous horizontal cursor
                          wrap), deployed to ~/.hammerspoon/Spoons/ by
                          install-hammerspoon
helpers/                  shortcut cheat-sheet: generate-shortcuts-json,
                          display-shortcuts (mac-cheatsheet-viewer app lives
                          in its own repo at iv-lite/mac-cheatsheet-viewer)
tests/                    VM test workflow (tests/preview + lib/ backends)
```

Configs are installed to `~/.config/{nehir,borders,ghostty}` (plus shortcut
helpers under `~/.config/mac-scrolling-wm/` and `WarpMouse.spoon` under
`~/.hammerspoon/Spoons/`); existing files are backed up (`.bak`) before
overwriting. Every file under `~/.config/nehir/` live-reloads on save —
there's no restart or reload hotkey to remember.

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
> niri-style scrolling-strip model, with native column-width presets built
> in, so the hand-rolled `cycle-column-width` script is gone; JankyBorders
> and the Hammerspoon `WarpMouse.spoon` both stay, since Nehir's own
> single-color border and flat (no-glide) native mouse warp are each a
> step down from what this repo already had.
