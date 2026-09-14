# omniwm-installer

A niri-like window management setup for macOS, built on **OmniWM** (Swift
tiling WM with niri-style sliding strips, hot-reloadable TOML config, virtual
workspaces, window borders, and IPC via `omniwmctl`) and **Ghostty**
(terminal). Driven by **Cmd**-layered arrow chords — Cmd to focus,
Cmd+Shift to move, Cmd+Option for workspaces, Cmd+Ctrl for displays — that
don't fight macOS defaults. Requires **Apple Silicon + macOS 26+ (Tahoe)**.

## Requirements

- macOS 26+ (Tahoe) — Apple Silicon (OmniWM cask depends on both)
- Homebrew installed or auto-installed
- "Displays have separate Spaces" enabled (OmniWM requires it; the installer sets it)
- No Karabiner, no SIP disable

## Quick start

```sh
./install
```

Re-running `./install` **upgrades** an existing setup: Homebrew components
(OmniWM, Ghostty, tccutil-rs) are updated, configs are refreshed from this
repo (existing copies backed up as `*.bak`), and the launchd service is
restarted so the new binary/config apply immediately.

The installer runs these steps from `scripts/`:

| Script | Purpose |
|---|---|
| `install-deps` | Install Homebrew if missing, tccutil-rs |
| `configure-system` | Enable "Displays have separate Spaces" (OmniWM requires it) |
| `install-ghostty` | Install Ghostty + write `~/.config/ghostty/config` (frameless title bar) |
| `install-omniwm` | Install OmniWM (Homebrew cask), remove any leftover Paneru, write config + launchd agent |
| `grant-permissions` | Grant Accessibility to OmniWM.app (best-effort) + open Input Monitoring pane |
| `enable-services` | Bootstrap the OmniWM launchd agent (`launchctl bootstrap`) |

### After install

1. **Log out and back in** (Cmd+Shift+Q) — applies the enabled
   separate-Spaces setting.
2. OmniWM tiles in an **niri-style sliding strip**; new windows are appended
   at the end and **never resize existing windows**.
3. Workspaces are **dynamic**: they appear on demand and vanish when empty.
   Each display seeds one workspace (main "1", a second display "10").
   `Cmd+Option+↑/↓` navigates the current display's stack; left/right arrows
   handle windows within it.
4. If Accessibility or Input Monitoring grants failed, grant them manually:
   System Settings → Privacy & Security → Accessibility (toggle OmniWM on)
   and Privacy & Security → Input Monitoring (toggle OmniWM on).
5. Ghostty opens **frameless** (`macos-titlebar-style = hidden` in
   `~/.config/ghostty/config`) — drag its window edge with `Option+Click`.

## Keybindings

Arrow-key hierarchy — **Cmd** (focus), **Cmd+Shift** (move), **Cmd+Option**
(workspaces), **Cmd+Ctrl** (displays).

### Navigation & layout

| Shortcut | Action |
|---|---|
| `Cmd` + ←/↓/↑/→ | Move focus between windows |
| `Cmd` + `Shift` + ←/↓/↑/→ | Move window (swap) |
| `Cmd` + `Option` + `W` | Cycle column width forward (0.3 / 0.5 / 1) |
| `Cmd` + `Option` + `Shift` + `W` | Cycle column width backward |
| `Cmd` + `Option` + `M` | Toggle full-width |
| `Cmd` + `Option` + `Space` | Center column |
| `Cmd` + `Option` + `Shift` + `Space` | Center all visible columns |
| `Cmd` + `Option` + `V` | Toggle floating |
| `Cmd` + `Option` + `B` | Balance sizes |
| `Cmd` + `Option` + `Tab` | Focus last-focused window |
| 3-finger vertical swipe | Switch workspaces (trackpad) |

> Focus **follows the mouse**, and keyboard navigation warps the cursor to the
> focused window (`followsWindowToMonitor` / `moveMouseToFocusedWindow`).

### Workspaces

Dynamic: workspaces are created on demand at the ends of the stack and
auto-removed when emptied. Each display seeds one (main "1", second "10").

| Shortcut | Action |
|---|---|
| `Cmd` + `Option` + `↓` / `↑` | Next / previous workspace **on this display** |
| `Cmd` + `Option` + `Shift` + `↓` / `↑` | Move window to next / previous workspace on this display |
| `Cmd` + `Option` + `Tab` | Focus previous window |

> Workspaces are global but each belongs to a **Home Monitor** — cycling with
> `Cmd+Option+↑/↓` stays within the current display's own stack. Numeric
> workspace shortcuts are disabled because workspace numbers are assigned
> dynamically. The workspace bar pills are clickable for direct access.

### Multi-monitor

| Shortcut | Action |
|---|---|
| `Cmd` + `Ctrl` + ←/↓/↑/→ | Move the current workspace to the adjacent display |
| `Cmd` + `Ctrl` + `Shift` + ←/↓/↑/→ | Move the focused window to the adjacent display |

> A workspace belongs to a Home Monitor — it follows you when you move to it.
> Every connected display needs at least one seed workspace (the shipped
> config assigns "1" to main and "10" to a second display; the rest are
> created dynamically).

### Window state

| Shortcut | Action |
|---|---|
| `Cmd` + `Option` + `V` | Toggle floating/tiled |
| `Cmd` + `Option` + `B` | Balance all columns to the focused column's width |
| `Cmd` + `Option` + `Space` | Center the focused column in the viewport |

### Not available in OmniWM

These Paneru features have no OmniWM equivalent and were not mapped:

- Inactive-window dim (use the native blue border as a focus cue instead)
- Stack commands (consume/expel — done via niri-style automation in OmniWM)
- Copy-window-rule shortcut
- Restart/quit hotkeys (`Ctrl+Cmd+Shift+R`, `Ctrl+Cmd+Shift+Q` — use
  `omniwmctl save` to persist config, or `pkill -x OmniWM` to quit; the
  launchd agent restarts it automatically)

## The infinite horizontal canvas

The niri layout behaves like a canvas **wider than the monitor**: unfocused
windows park off-screen and glide in/out as focus moves. Two things make it
feel native:

- OmniWM keeps a thin **sliver** of each off-screen window visible at the
  screen edge — a workaround for macOS relocating windows that move fully
  off-screen.
- The workspace bar shows which display is active and which workspace it is
  on, with green-highlighted pills for the focused display.
- `[niri.containerPrimarySpanPresets]` cycling and
  `toggleContainerFullPrimarySpan` (Cmd+Option+M) cover on-demand sizing;
  new windows are appended at the end and never resize existing ones.

## Borders & workspace bar

- **Active-window border**: a 4px Nord blue (`#88ACE4`) border replaces
  JankyBorders — no extra process needed.
- **Workspace bar**: an overlay drawn by OmniWM at the top of each display,
  showing workspace pills. Green-highlighted pills mark the active workspace
  and the current display. Labels are shown (`showLabels = true`); pill
  radius, inset, and top padding are tuned in the shipped config.

## No title bars (the macOS reality)

macOS tiling window managers (OmniWM included — same as yabai/AeroSpace) cannot
hide a window's title bar or toolbar: each app draws its own chrome, so removal
has to happen per app. This installer does what's safely possible:

- **Ghostty is frameless by default** — `~/.config/ghostty/config` sets
  `macos-titlebar-style = hidden` and `macos-window-buttons = hidden`. Drag
  the window by its edge with `Option+Click`.
- **Other apps**: use each app's native toggle:

  | App | How |
  |---|---|
  | Finder, Mail, Notes, Safari, Chrome, Slack | `View → Hide Toolbar` (often `Cmd+Option+T`) |
  | Safari fullscreen | `View → Always Show Toolbar in Full Screen` off |
  | Ghostty | handled for you above |
  | VS Code | no clean path since 1.94 (hair-line third-party extensions only — not shipped) |

> Global tools that strip titlebars everywhere (e.g. `Brutalium`, `winBuddy`)
> inject code into running apps and require disabling SIP — out of scope here,
> the same reason this project never disables SIP.

## IPC & config live-reload

OmniWM supports **IPC** (enabled in the shipped config): the `omniwmctl`
binary lets you inspect and control the WM at any time.

```sh
omniwmctl query active-workspace   # show current workspace + display
omniwmctl query workspaces          # list all workspaces + their displays
omniwmctl query displays            # list connected displays
omniwmctl log                       # tail OmniWM logs
omniwmctl save                      # persist the live config to disk
```

`settings.toml` live-reloads on save — edit `~/.config/omniwm/settings.toml`
and the changes apply instantly (no restart needed). The schema is strict:
all required keys must be present and each hotkey action must appear exactly
once. Use `omniwmctl save` from OmniWM's own UI to export the canonical file,
then edit values in place.

## Multi-monitor

- OmniWM workspaces are **global entities**, each assigned to a **Home
  Monitor** (not per-display stacks like Paneru's native Spaces).
- Workspaces are **dynamic**: a new one is created at the stack edges when
  `Cmd+Option+↑/↓` overflows; empty ones are cleaned up automatically. The
  shipped config only seeds "1" on the main display and "10" on a second
  display.
- `Cmd+Ctrl+←/↓/↑/→` moves the current workspace to an adjacent display;
  `Cmd+Ctrl+Shift+←/↓/↑/→` moves just the focused window.
- The sliding strip works best when displays are arranged **vertically**
  (laptop above/below the external monitor, System Settings → Displays).

## Troubleshooting

**OmniWM won't start / instantly exits.** OmniWM requires Accessibility and
Input Monitoring permissions, plus "Displays have separate Spaces" **ON**.
The installer's `configure-system` / `ensure-separate-spaces` handles the
latter. If grants failed, give the terminal **Full Disk Access** first, then:

```sh
bash scripts/grant-permissions
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.barut.OmniWM.plist
```

Check the OmniWM logs for errors:

```sh
omniwmctl log
```

**IPC not working (`omniwmctl` gives errors).** The shipped config sets
`general.ipcEnabled = true`. If it was changed, restore it and save:

```sh
# Edit ~/.config/omniwm/settings.toml and set general.ipcEnabled = true
# Then restart OmniWM or press the save keybind to live-reload
pkill -x OmniWM   # launchd will restart it automatically
```

**Config won't load / validation errors.** OmniWM's `settings.toml` is a
strict canonical schema — all required keys must be present and each hotkey
action must appear exactly once. Never delete entries; only edit values. To
export the current valid config from OmniWM itself: save from the OmniWM UI
or run `omniwmctl save`. The shipped `config/omniwm/settings.toml` in this
repo is the full validated canonical config.

**Accessibility grants failed.** The terminal app running this installer needs
**Full Disk Access** (System Settings → Privacy & Security → Full Disk Access),
then quit and reopen the terminal and re-run:

```sh
bash scripts/grant-permissions
```

Input Monitoring **cannot** be granted programmatically — you must toggle
OmniWM on manually in System Settings → Privacy & Security → Input Monitoring.

## Uninstall

```sh
./uninstall
```

Stops and removes OmniWM (launchd agent + app), cleans up any leftover Paneru
(from the previous stack) plus any **legacy** Rift / `rift-swipe` /
JankyBorders / AeroSpace / AeroSpaceBar / Aegis residue (services,
LaunchAgents, apps), moves configs (from `~/.config/omniwm`, `~/.config/ghostty`,
plus legacy dirs) to `~/.config/backups/uninstall-<timestamp>/`, then asks
which brew packages to **keep** (interactive numbered menu). Untaps unused
repos and restores system defaults.

## Testing in a macOS VM

The `tests/preview` workflow runs `./install` inside a real macOS guest VM.
The host OS is auto-detected and a matching hypervisor backend is used:

| Host | Backend | Requirements |
| --- | --- | --- |
| macOS (Apple Silicon) | Tart (`tests/lib/backend_tart.sh`) | macOS 15+, Homebrew; `tart`/`sshpass` auto-installed |
| Linux x86_64 | QEMU/KVM + OpenCore (`tests/lib/backend_qemu.sh`) | `/dev/kvm`, `qemu-system-x86`, `sshpass`, `rsync`, a **Tahoe (macOS 26)** disk |

macOS host:

```sh
./tests/preview setup        # installs tart/sshpass (auto), clones host-matched base image
./tests/preview up           # boot guest, live-mount the repo, wait for SSH
./tests/preview install      # run ./install in the guest (asks to clean up afterwards)
./tests/preview check        # query omniwmctl state + installed formulae
./tests/preview shot         # screenshot the tiling into tests/screenshots/
./tests/preview clean        # interactively remove VM, tart, sshpass, base image
```

Linux x86_64 host:

```sh
export TESTS_MACOS_DISK=/path/to/macos-tahoe.qcow2   # required (admin/admin)
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
config/omniwm/            OmniWM config (canonical settings.toml)
config/ghostty/           Ghostty config (frameless title bar)
tests/                    VM test workflow (tests/preview + lib/ backends)
```

Configs are installed to `~/.config/{omniwm,ghostty}`; existing files are
backed up (`.bak`) before overwriting. OmniWM live-reloads
`~/.config/omniwm/settings.toml` on save, and a launchd agent
(`~/Library/LaunchAgents/com.barut.OmniWM.plist`) keeps OmniWM running.

> **Note on the history:** an early version of this installer targeted
> AeroSpace (i3-style tree tiler) with AeroSpaceBar in the menu bar; a later
> version used **Rift** (niri-style scrolling strip) plus a custom `rift-swipe`
> C helper; the most recent version used **Paneru** (niri-style sliding strip
> with native per-Space virtual workspaces). This version is on **OmniWM**
> (Swift, niri-style sliding strips, global virtual workspaces, window borders,
> workspace bar overlay, and `omniwmctl` IPC), which retains the niri layout
> and cursor-warp focus model while adding a workspace bar overlay and native
> IPC — the Rift-era helper, its LaunchAgent, JankyBorders, Paneru's menu-bar
> workspace indicator workaround, and the `cycle-column-width` Python helper
> are all gone.