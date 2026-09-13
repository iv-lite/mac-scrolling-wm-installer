# rift-wm-installer

A niri-like window management setup for macOS, built on **Rift** (niri-style
scrolling-strip tiler with hot-reloadable TOML config and virtual workspaces),
**Aegis** (notch-safe menu-bar replacement with workspace indicators and a
notch HUD), **JankyBorders** (window focus borders), and **Ghostty** (terminal).
Driven by Option-key shortcuts that don't fight macOS defaults.

## Requirements

- macOS 14+ (Rift; Aegis requires Sonoma or later)
- Apple Silicon (notch recommended; Aegis's bar + Notch HUD are notch-designed)
- Homebrew installed or auto-installed
- "Displays have separate Spaces" enabled (Rift-recommended; the installer sets it)
- No Karabiner, no disable of System Integrity Protection

## Quick start

```sh
./install
```

The installer runs these steps from `scripts/`:

| Script | Purpose |
|---|---|
| `install-deps` | Install Homebrew if missing, tccutil-rs |
| `configure-system` | Enable "Displays have separate Spaces"; hide the native menu bar (Aegis replaces it) |
| `install-ghostty` | Install Ghostty + write `~/.config/ghostty/config` (frameless title bar) |
| `install-rift` | Install Rift + write `~/.config/rift/config.toml` + install its launchd service |
| `install-borders` | Install JankyBorders + write `~/.config/borders/bordersrc` |
| `install-aegis` | Download latest Aegis from GitHub Releases → `/Applications/Aegis.app` |
| `grant-permissions` | Grant Accessibility via tccutil-rs (user → sudo → manual fallback) |
| `enable-services` | Start Rift, install the Aegis LaunchAgent, start `borders` |

### After install

1. **Log out and back in** (Cmd+Shift+Q) — applies the enabled
   separate-Spaces setting and hides the native menu bar.
2. Rift tiles in a **niri-style scrolling strip**; workspaces `1..9` are
   persistent. `Option+Shift+R` reloads the config (hot reload is also on).
3. **Aegis** draws the menu bar: clickable workspace indicators (1-9) with
   window icons, drag-to-move-between-workspaces, plus a notch HUD for
   volume/brightness/media/notifications. It connects to Rift automatically.
4. If Accessibility grants failed, grant them manually:
   System Settings → Privacy & Security → Accessibility (enable Rift, Borders, Aegis).
5. Ghostty opens **frameless** (`macos-titlebar-style = hidden` in
   `~/.config/ghostty/config`) — drag its window edge with `Option+Click`.

## Keybindings

Rift modifiers: **Option** (Alt), **Shift**, **Ctrl**, **Cmd** (Meta).

### Navigation & layout

| Shortcut | Action |
|---|---|
| `Option` + Arrows | Move focus between windows |
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
| 3-finger swipe | Switch workspaces (trackpad) |

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
| `Option` + `V` | Toggle floating/tiling |
| `Option` + `Q` | Close window |
| `Option` + `W` | Stack windows in the column |
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
> gone — Aegis replaces the menu bar entirely.

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
- `column_width_ratio = 0.7` gives the "big focus + sliver peek" look: the
  canvas starts overflowing as soon as column widths exceed the monitor —
  with 0.7 that's already at **2+ windows**, so the scroll doesn't hide
  behind a static 50/50 tiling (0.5 did exactly that). A single lone window
  still fills the screen (Rift gives a one-column strip full width); open a
  second or third window to see the strip spill past the edges.
- `animate = true` plus the global `animate` / `animation_duration` /
  `animation_fps` settings produce the smooth slide.
- `scroll_strip` (`Alt+[`/`]`) half-steps, `snap_strip` (`Alt+Shift+[`/`]`)
  settles on a column boundary, `center_selection` (`Alt+Space`) re-centers.

> **Why not "negative struts"?** macOS/Rift has no `_NET_WM_STRUT` /
> negative-strut API — that's an X11/i3/sway concept. And Rift `app_rules`
> only control floating/workspace/size/position/manage, not canvas size. The
> wide-canvas feel comes purely from the scrolling layout + niri focus
> navigation + animations.

## The menu bar & notch

- The native macOS menu bar is **hidden** — Aegis (notch-safe) replaces it.
- **Workspace indicators** live in Aegis's bar: click a badge to switch
  workspaces, drag a window icon onto another workspace, right-click for
  layout/workspace/window commands.
- The **notch HUD** shows volume/brightness changes, now-playing media,
  notifications, and Bluetooth device events in the notch area — no more
  overflowing menu bar items.
- Aegis auto-detects Rift on launch (Mach subscription) and needs no setup.
- Tune the top gap if you want more breathing room below Aegis's bar — see
  `~/.config/rift/config.toml` `[settings.layout.gaps.outer]`.

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

**Aegis is unresponsive / CPU pegged (~1000%).** Aegis spins in a busy loop if it
starts before Rift's Mach service exists (`rift-cli subscribe mach *` dies,
retries instantly, no backoff). The LaunchAgent this installer writes is wrapped
by `scripts/start-aegis`, which waits up to 120 s for `rift-cli query workspaces`
to succeed before launching Aegis, so this should not happen on a fresh install.
If you hit it anyway:

1. Check Rift is up: `rift-cli query workspaces` (should print `[]`, not a Mach error).
2. `launchctl list | grep aegis` and `~/.config/aegis/start-aegis` exist if the wrapper was installed.
3. Restart cleanly: `killall Aegis; rift service stop; rift service start; open -a Aegis`.

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
  the installer grants it (and Borders/Aegis) via `tccutil-rs`. If grants failed,
  the terminal running the installer needs **Full Disk Access** first, then
  `bash scripts/grant-permissions`.

Rift's own debug trail: `launchctl list | grep rift`, logs at `/tmp/rift_iv.out.log`
and `/tmp/rift_iv.err.log`, and `sudo launchctl stop com.apple.tccd` after any
grant. A quick health check of the whole stack:

```sh
bash scripts/ensure-separate-spaces check   # must print "enabled (mode 1)"
rift-cli query workspaces                   # must print [] (Mach service up)
ps -o %cpu -p $(pgrep -x Aegis)             # Aegis should be well under 10%
```

## Multi-monitor

- Rift's recommended "Displays have separate Spaces" = **on** gives each display
  its own independent tiling layout and workspace set.
- The scrolling strip works best when displays are arranged **vertically**
  (System Settings → Displays); side-by-side layouts can cause windows to leak
  between strips.
- Per-display gap overrides are supported in the config (commented template).
  Get your display UUIDs with `rift-cli query displays`.

## Uninstall

```sh
./uninstall
```

Stops and removes Rift (launchd service), the Aegis LaunchAgent, and borders,
deletes `/Applications/Aegis.app` and Aegis's preferences, moves configs (from
`~/.config/rift`, `~/.config/borders`, and `~/.config/aegis`, plus any legacy
`~/.config/aerospace`) to `~/.config/backups/uninstall-<timestamp>/`, then asks
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
config/rift/              Rift config (scrolling strip, bindings, gaps)
config/ghostty/           Ghostty config (frameless title bar)
config/borders/bordersrc  JankyBorders focus-border config
tests/                    VM test workflow (tests/preview + lib/ backends)
```

Configs are installed to `~/.config/{rift,ghostty,borders}` (plus `~/.config/aegis`);
existing files are backed up (`.bak`) before overwriting, and Rift has
`hot_reload`, so editing `~/.config/rift/config.toml` applies live.

> **Note on AeroSpace:** an intermediate version of this installer targeted
> AeroSpace (i3-style tree tiler) with AeroSpaceBar in the menu bar. This
> version is back on Rift (niri-style scrolling strip) with **Aegis** as the
> notch-safe menu bar replacement. Rift's own `[settings.ui.menu_bar]` is
> turned off in `config/rift/config.toml`.