# rift-wm-installer

A niri-like window management setup for macOS, built on **Rift** (niri-style
scrolling-strip tiler with hot-reloadable TOML config and virtual workspaces),
**JankyBorders** (window focus borders), and **Ghostty** (terminal).
Driven by Option-key shortcuts that don't fight macOS defaults.

## Requirements

- macOS 14+ (Rift)
- Apple Silicon (notch recommended; Rift's menu-bar indicators are notch-safe)
- Homebrew installed or auto-installed
- Apple Command Line Tools (or Xcode) — the installer compiles the
  `rift-swipe` helper with `cc`
- "Displays have separate Spaces" enabled (Rift-recommended; the installer sets it)
- No Karabiner, no disable of System Integrity Protection

## Quick start

```sh
./install
```

`./install --HEAD` additionally builds **Rift from git main** (source build;
needs Rust, takes a few minutes) — required until the next release for the
PR #320 multi-monitor fix (see [Multi-monitor](#multi-monitor)).

Re-running `./install` **upgrades** an existing setup: Homebrew components
(Rift, JankyBorders, Ghostty, tccutil-rs) are updated (no-op when current),
configs are refreshed from
this repo (previous copies kept as `*.bak`), and the services are restarted so
the new binaries/config apply immediately.

The installer runs these steps from `scripts/`:

| Script | Purpose |
|---|---|
| `install-deps` | Install Homebrew if missing, tccutil-rs |
| `configure-system` | Enable "Displays have separate Spaces"; show the native menu bar (Rift draws its indicators in it) |
| `install-ghostty` | Install Ghostty + write `~/.config/ghostty/config` (frameless title bar) |
| `install-rift` | Install Rift + write `~/.config/rift/config.toml` + install its launchd service |
| `install-rift-swipe` | Compile the `rift-swipe` helper (3-finger swipe → window paging) + install its LaunchAgent |
| `install-borders` | Install JankyBorders + write `~/.config/borders/bordersrc` |
| `grant-permissions` | Grant Accessibility via tccutil-rs (user → sudo → manual fallback) |
| `enable-services` | Start Rift, start `borders` |

### After install

1. **Log out and back in** (Cmd+Shift+Q) — applies the enabled
   separate-Spaces setting.
2. Rift tiles in a **niri-style scrolling strip**; workspaces `1..9` are
   persistent. `Option+Shift+R` reloads the config (hot reload is also on).
3. **Rift** draws its workspace indicators in the native macOS menu bar
   (click a badge to switch). The menu bar auto-hides in Rift's fullscreen
   Spaces — move the cursor to the top edge to reveal it.
4. If Accessibility grants failed, grant them manually:
   System Settings → Privacy & Security → Accessibility (enable Rift, Borders,
   and `rift-swipe` if you want the 3-finger window paging).
5. Ghostty opens **frameless** (`macos-titlebar-style = hidden` in
   `~/.config/ghostty/config`) — drag its window edge with `Option+Click`.

## Keybindings

Rift modifiers: **Option** (Alt), **Shift**, **Ctrl**, **Cmd** (Meta).

### Navigation & layout

| Shortcut | Action |
|---|---|
| `Option` + Arrows | Move focus between windows |
| 3-finger horizontal scroll (← / →) | Page through windows — one maximized window per swipe (`rift-swipe`) |
| `Option` + `Shift` + Arrows | Move window in the tree |
| `Option` + `Ctrl` + Arrows | Resize (left/right width, up/down height) |
| `Option` + `Tab` | Jump to last workspace |
| `Option` + `[` / `]` | Scroll the strip by half a column |
| `Option` + `Shift` + `[` / `]` | Snap the strip to a column boundary |

### Workspaces (1-9)

| Shortcut | Action |
|---|---|
| `Option` + `1..9` | Switch Rift workspace |
| `Option` + `Shift` + `1..9` | Move window to workspace |
| `Option` + `Z` | Toggle tiling on the current macOS Space |
| 3-finger swipe | Switch workspaces (trackpad; distinct from the 3-finger *scroll* that pages windows) |

### Displays (multi-monitor)

| Shortcut | Action |
|---|---|
| `Cmd` + `Option` + Arrows | Move focus to a display |
| `Cmd` + `Option` + `Shift` + Arrows | Move window to a display |

> Rift workspaces are **not** 1:1 with macOS Spaces — each macOS Space has its
> own set of virtual workspaces. With "Displays have separate Spaces" on, each
> display is fully isolated.

### Window state

| Shortcut | Action |
|---|---|
| `Option` + `F` | Toggle fullscreen |
| `Option` + `Shift` + `F` | Toggle fullscreen (keeping outer gaps) |
| `Option` + `M` | Maximize a window (fullscreen within outer gaps) |
| `Option` + `V` | Toggle floating/tiling |
| `Option` + `Q` | Close window |
| `Option` + `O` | Stack windows in the column |
| `Option` + `W` | Cycle the focused column width (0.3 / 0.5 / 1) |
| `Option` + `/` | Toggle orientation |
| `Option` + `Ctrl` + `E` | Un-join the layout tree |
| `Option` + `Space` | Center the focused column |

### Apps & misc

| Shortcut | Action |
|---|---|
| `Ctrl` + `Cmd` + `T` | Open Ghostty |
| `Option` + `Shift` + `R` | Reload Rift config (hot reload also on) |

> **Moved/removed vs. the AeroSpace setup:** the scrollable strip is back
> (`Option+[`/`]`), per-Space tiling toggles are `Option+Z`, and workspace
> switching is `Option+1..9`. The SketchyBar cheat sheet (`Cmd+Option+K`) is
> gone — Rift draws workspace indicators in the (native) menu bar instead.

### The infinite horizontal canvas

The niri-style scrolling strip behaves like a canvas **wider than the monitor**:
unfocused columns park off-screen beyond the frame edge and glide in/out of the
screen edges as focus moves, instead of being clamped or squeezed into the
visible bounds.

There's no secret trick in the config — this is what Rift's scrolling layout
does natively:

- `[settings.layout] mode = "scrolling"` + `focus_navigation_style = "niri"`
  reveal columns on navigation, keeping neighbours staged beyond the edges.
- `alignment = "center"` keeps the focused column centered, so the next/prev
  columns visibly peek in from the left/right.
- `column_width_ratio = 1` makes every column **full-screen**: each window is
  maximized (a "page"), so a swipe pans exactly one window with zero mid-window
  rest. `Option+W` still cycles 0.3 / 0.5 / 1 on demand, and a single lone
  window fills the screen by design.
- `animate = true` plus the global `animate` / `animation_duration` /
  `animation_fps` settings produce the smooth slide.
- `scroll_strip` (`Alt+[`/`]`) half-steps, `snap_strip` (`Alt+Shift+[`/`]`)
  settles on a column boundary, `center_selection` (`Alt+Space`) re-centers.

### Swiping between windows (`rift-swipe`)

Rift's built-in scroll gesture only *pans* the strip — it doesn't change focus
and leaves you mid-window at release, so the config disables it
(`[settings.layout.scrolling.gestures] enabled = false`) and a small helper,
`scripts/rift-swipe/rift-swipe.c`, takes over:

- It watches the same low-level HID gesture events Rift decodes (a CGEvent
  type-29 tap + the multi-touch digitizer), and a deliberate **3-finger
  horizontal swipe** becomes `rift-cli window next/prev`.
- Rift then reveals + focuses the next maximized window, **centered** and
  animated at `animation_duration` — one window per swipe, exactly like paging.
- Finger count is decoded from the event's `IOHIDEvent` (paths marked
  touching), so 2-finger scrolling in apps is untouched; the tap is
  listen-only (never consumes), so Rift's own 3-finger *swipe* → workspace
  switching still works.

Built by the installer with `cc` (Command Line Tools only, no Xcode needed) to
`~/.config/rift/bin/rift-swipe`, run by the `io.rift-swipe` LaunchAgent, and
granted Accessibility via `grant-permissions`. Tuning (only if needed):
`RIFT_SWIPE_THRESHOLD` (default 0.45 of a full sweep), `RIFT_SWIPE_INVERT`
(default 1, matches `invert_horizontal`), `RIFT_SWIPE_QUIET_MS` (default 150),
`RIFT_SWIPE_CLI`. Direction: fingers **left** → next window, **right** →
previous (the same feel the pan had).

> **Why not "negative struts"?** macOS/Rift has no `_NET_WM_STRUT` /
> negative-strut API — that's an X11/i3/sway concept. And Rift `app_rules`
> only control floating/workspace/size/position/manage, not canvas size. The
> wide-canvas feel comes purely from the scrolling layout + niri focus
> navigation + animations.

## The menu bar

- The **native macOS menu bar** is kept — Rift draws its workspace indicators
  in it (`[settings.ui.menu_bar] enabled = true`). In Rift's fullscreen
  Spaces the menu bar auto-hides; move the cursor to the top edge to reveal it,
  or it stays visible on the desktop Space.
- **Workspace indicators**: click a badge in the menu bar to switch
  workspaces; the currently focused workspace is highlighted.
- **Top gap:** the outer top gap defaults to 15px (matching the other edges) —
  since the menu bar auto-hides in fullscreen Spaces, no menu-bar clearance is
  needed. Tune `[settings.layout.gaps.outer]` in `~/.config/rift/config.toml`
  for more/less breathing room.

## No title bars (the macOS reality)

macOS tiling window managers (Rift included — same as yabai/AeroSpace) cannot
hide a window's title bar or toolbar: each app draws its own chrome, so removal
has to happen per app. This installer does what's safely possible:

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

**Rift won't start / instantly exits.** Rift hard-exits unless two conditions hold:

- **"Displays have separate Spaces" is ON.** Rift probes the private windowserver
  mode, not the legacy `defaults write com.apple.spaces spans-displays` knob —
  on modern macOS (26) that knob no longer changes the live state. The installer's
  `scripts/ensure-separate-spaces` enables it via the private SkyLight API and
  persists it, then verifies. If it still fails, enable it manually in
  System Settings → Desktop & Dock → "Displays have separate Spaces", then re-run
  `bash scripts/ensure-separate-spaces set`. **On macOS 26, leaving this OFF risks
  a WindowServer crash at next login (Apple bug 153570422).**
- **`rift` has Accessibility.** Check System Settings → Privacy & Security →
  Accessibility. Because `rift` is a CLI binary it's invisible there by default;
  the installer grants it (and Borders) via `tccutil-rs`. If grants failed,
  the terminal running the installer needs **Full Disk Access** first, then
  `bash scripts/grant-permissions`.

Rift's own debug trail: `launchctl list | grep rift`, logs at `/tmp/rift_iv.out.log`
and `/tmp/rift_iv.err.log`, and `sudo launchctl stop com.apple.tccd` after any
grant. A quick health check of the whole stack:

```sh
bash scripts/ensure-separate-spaces check   # must print "enabled (mode 1)"
rift-cli query workspaces                   # must print [] (Mach service up)
```

## Multi-monitor

- Rift's recommended "Displays have separate Spaces" = **on** gives each display
  its own independent tiling layout and workspace set.
- The scrolling strip works best when displays are arranged **vertically**
  (System Settings → Displays); side-by-side layouts can cause windows to leak
  between strips.
- Releases before PR #320 (currently `v0.5.8.1`) have two known multi-monitor
  bugs in the scrolling layout on side-by-side displays:
  1. `Alt+Arrow` at the strip's first/last column **jumps focus** to the
     adjacent display's workspace instead of stopping at the boundary.
  2. Fully off-screen (parked) full-width columns sit far outside the visible
     strip and can **spill onto the adjacent monitor** — the "windows keep
     switching / scroll to the monitor" symptom.
  The fix is merged into `main`. Until the next release ships it, install Rift
  from git main with **`./install --HEAD`** (source build; needs Rust, takes a
  few minutes). The installer prints a warning when it detects a pre-#320 build.
- Per-display gap overrides are supported in the config (commented template).
  Get your display UUIDs with `rift-cli query displays`.

## Uninstall

```sh
./uninstall
```

Stops and removes Rift (launchd service) and borders, cleans up any **legacy**
Aegis residue (LaunchAgent, `/Applications/Aegis.app`, preferences), moves
configs (from `~/.config/rift`, `~/.config/borders`, plus any legacy
`~/.config/aegis`, `~/.config/aerospace`) to `~/.config/backups/uninstall-<timestamp>/`, then asks
you which formulae to **keep** (interactive numbered menu). Untaps
`acsandmann/tap`, `FelixKratz/formulae`, `uinaf/tap` (and legacy
`nikitabobko/tap`, `rdrkr/tap` only when nothing kept depends on them), and
restores the native menu bar (`_HIHideMenuBar` off).

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
./tests/preview check        # query Rift workspaces + installed formulae
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
tested), Accessibility may need one manual grant inside the guest.

## Project layout

```
install                   Main installer (runs scripts/*)
uninstall                 Full uninstaller with interactive keep menu
scripts/                  Per-component install/system/accessibility steps
scripts/rift-swipe/       rift-swipe.c helper + io.rift-swipe.plist template
config/rift/              Rift config (scrolling strip, bindings, gaps)
config/ghostty/           Ghostty config (frameless title bar)
config/borders/bordersrc  JankyBorders focus-border config
tests/                    VM test workflow (tests/preview + lib/ backends)
```

Configs are installed to `~/.config/{rift,ghostty,borders}`;
existing files are backed up (`.bak`) before overwriting, and Rift has
`hot_reload`, so editing `~/.config/rift/config.toml` applies live.

> **Note on AeroSpace:** an intermediate version of this installer targeted
> AeroSpace (i3-style tree tiler) with AeroSpaceBar in the menu bar. A later
> version used **Aegis** (a notch-safe menu bar replacement). This version is
> back on Rift (niri-style scrolling strip) with the native macOS menu bar,
> where Rift's own `[settings.ui.menu_bar]` draws the workspace indicators.