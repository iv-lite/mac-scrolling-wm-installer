# nehir-installer

A niri-like window management setup for macOS, built on **Nehir** (Swift
tiling WM fork of OmniWM with niri-style sliding strips, hot-reloadable
split TOML config, fixed virtual workspaces, window borders, and IPC via
`nehirctl`) and **Ghostty** (terminal). Driven by **Cmd**-layered arrow
chords — Cmd to focus, Cmd+Shift to move, Cmd+Option for workspaces,
Cmd+Ctrl for displays — that don't fight macOS defaults. Requires
**Apple Silicon + macOS 26+ (Tahoe)**.

## Requirements

- macOS 26+ (Tahoe) — Apple Silicon (Nehir requires both)
- Homebrew installed or auto-installed
- "Displays have separate Spaces" enabled (Nehir requires it; the installer sets it)
- No Karabiner, no SIP disable

## Quick start

```sh
./install
```

Re-running `./install` **upgrades** an existing setup: Homebrew components
(Nehir, Ghostty, tccutil-rs) are updated, configs are refreshed from this
repo (existing copies backed up as `*.bak`), and the launchd service is
restarted so the new binary/config apply immediately.

The installer runs these steps from `scripts/`:

| Script | Purpose |
|---|---|
| `install-deps` | Install Homebrew if missing, tccutil-rs |
| `configure-system` | Enable "Displays have separate Spaces" (Nehir requires it) |
| `install-ghostty` | Install Ghostty + write `~/.config/ghostty/config` (frameless title bar) |
| `install-nehir` | Install Nehir (Homebrew cask, or build from source via mise), remove any leftover OmniWM, write split config + launchd agent |
| `grant-permissions` | Grant Accessibility to Nehir.app (best-effort) |
| `enable-services` | Bootstrap the Nehir launchd agent (`launchctl bootstrap`) |

### After install

1. **Log out and back in** (Cmd+Shift+Q) — applies the enabled
   separate-Spaces setting.
2. Nehir tiles in an **niri-style sliding strip**; new windows are appended
   at the end and **never resize existing windows**.
3. Workspaces are **fixed**: `[1]+[2]` on the main display, `[10]` on a
   second display. Cmd+Option+↑/↓ cycles the current display's stack;
   Cmd+Option+Shift+↑/↓ moves a window between workspaces.
4. If Accessibility grants failed, grant them manually:
   System Settings → Privacy & Security → Accessibility (toggle Nehir on).
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

Fixed pre-defined list: `[1]+[2]` on main, `[10]` on secondary. Missing
workspaces default to next slot on main.

| Shortcut | Action |
|---|---|
| `Cmd` + `Option` + `↓` / `↑` | Next / previous workspace **on this display** |
| `Cmd` + `Option` + `Shift` + `↓` / `↑` | Move window to next / previous workspace on this display |
| `Cmd` + `Option` + `Tab` | Focus previous window |

### Multi-monitor

| Shortcut | Action |
|---|---|
| `Cmd` + `Ctrl` + `→` / `←` | Focus next / previous display |
| `Cmd` + `Ctrl` + `Shift` + ←/↓/↑/→ | Move the focused window to the adjacent display |

> Workspaces belong to a specific monitor — cycling with Cmd+Option+↑/↓ stays
> within the current display's own stack. The workspace bar shows workspace
> pills; click to jump directly.

### Window state

| Shortcut | Action |
|---|---|
| `Cmd` + `Option` + `V` | Toggle floating/tiled |
| `Cmd` + `Option` + `B` | Balance all columns to the focused column's width |
| `Cmd` + `Option` + `Space` | Center the focused column in the viewport |

### Not available in Nehir

These Paneru features have no Nehir equivalent and were not mapped:

- Inactive-window dim (use the native blue border as a focus cue instead)
- Stack commands (consume/expel — done via niri-style automation in Nehir)
- Copy-window-rule shortcut
- Restart/quit hotkeys (`Ctrl+Cmd+Shift+R`, `Ctrl+Cmd+Shift+Q` — use
  `nehirctl save` to persist config, or `pkill -x Nehir` to quit; the
  launchd agent restarts it automatically)

## The infinite horizontal canvas

The niri layout behaves like a canvas **wider than the monitor**: unfocused
windows park off-screen and glide in/out as focus moves. Two things make it
feel native:

- Nehir keeps a thin **sliver** of each off-screen window visible at the
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
- **Workspace bar**: an overlay drawn by Nehir at the top of each display,
  showing workspace pills. Green-highlighted pills mark the active workspace
  and the current display. Labels are shown (`showLabels = true`); pill
  radius, inset, and top padding are tuned in the shipped config.
- Empty workspaces are hidden when `hideEmptyWorkspaces = true`.

## No title bars (the macOS reality)

macOS tiling window managers (Nehir included — same as yabai/AeroSpace) cannot
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

Nehir supports **IPC** (enabled in the shipped config): the `nehirctl`
binary lets you inspect and control the WM at any time.

```sh
nehirctl query active-workspace   # show current workspace + display
nehirctl query workspaces         # list all workspaces + their displays
nehirctl query displays           # list connected displays
nehirctl ping                     # check if Nehir is responding
```

Config is split into three TOML files under `~/.config/nehir/`:

- `settings.toml` — appearance, focus, gaps, borders, workspace bar, gestures
- `hotkeys.toml` — all keyboard shortcuts (missing keys fall back to defaults silently)
- `workspaces.toml` — fixed workspace definitions and monitor assignments

Changes to `settings.toml` and `hotkeys.toml` live-reload on save — edit them
and the changes apply instantly (no restart needed). Unlike OmniWM's strict
canonical schema, Nehir's config is lenient: unknown keys are preserved,
missing keys keep built-in defaults, and only duplicate bindings within a
section are rejected.

App rules live in `~/.config/nehir/apprules.d/*.toml` — each file defines
a match condition and an effect (e.g. `apploating = true`).

## Multi-monitor

- Nehir workspaces are **fixed pre-defined entities**, each assigned to a
  **Monitor** (not per-display stacks like Paneru's native Spaces).
- Workspaces `[1]+[2]` are on the main display, `[10]` on a second display.
  Empty workspace pills are hidden automatically.
- `Cmd+Ctrl+→` / `Cmd+Ctrl+←` cycles focus between displays (round-robin);
  `Cmd+Ctrl+Shift+←/↓/↑/→` moves just the focused window to a display.
- The sliding strip works best when displays are arranged **vertically**
  (laptop above/below the external monitor, System Settings → Displays).

## Troubleshooting

**Nehir won't start / instantly exits.** Nehir requires Accessibility
permission and "Displays have separate Spaces" **ON**. The installer's
`configure-system` / `ensure-separate-spaces` handles the latter. If grants
failed, give the terminal **Full Disk Access** first, then:

```sh
bash scripts/grant-permissions
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/dev.guria.nehir.plist
```

**IPC not working (`nehirctl` gives errors).** The shipped config sets
`ipcEnabled = true` in `~/.config/nehir/settings.toml`. If it was changed,
restore it and restart:

```sh
# Edit ~/.config/nehir/settings.toml and set general.ipcEnabled = true
# Then restart Nehir or press the save keybind to live-reload
pkill -x Nehir   # launchd will restart it automatically
```

**Config won't load / validation errors.** Nehir's config files are
lenient — unknown keys are preserved, missing keys keep defaults. If you see
errors, check for TOML syntax mistakes. The shipped configs in this repo are
validated reference files:

```sh
python3 -c "import tomllib; tomllib.load(open('config/nehir/settings.toml','rb'))"
```

**Accessibility grants failed.** The terminal app running this installer needs
**Full Disk Access** (System Settings → Privacy & Security → Full Disk Access),
then quit and reopen the terminal and re-run:

```sh
bash scripts/grant-permissions
```

Nehir only needs **Accessibility** — no Input Monitoring is required.

## Uninstall

```sh
./uninstall
```

Stops and removes Nehir (launchd agent + app), cleans up any leftover OmniWM
(from the previous stack) plus any **legacy** Rift / `rift-swipe` /
JankyBorders / AeroSpace / AeroSpaceBar / Aegis residue (services,
LaunchAgents, apps), moves configs (from `~/.config/nehir`, `~/.config/ghostty`,
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
./tests/preview check        # query nehirctl state + installed formulae
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
config/nehir/             Nehir config (settings.toml, hotkeys.toml, workspaces.toml, apprules.d/)
config/ghostty/           Ghostty config (frameless title bar)
tests/                    VM test workflow (tests/preview + lib/ backends)
```

Configs are installed to `~/.config/nehir/` and `~/.config/ghostty/`; existing
files are backed up (`.bak`) before overwriting. Nehir live-reloads
`settings.toml` and `hotkeys.toml` on save, and a launchd agent
(`~/Library/LaunchAgents/dev.guria.nehir.plist`) keeps Nehir running.

> **Note on the history:** an early version of this installer targeted
> AeroSpace (i3-style tree tiler) with AeroSpaceBar in the menu bar; a later
> version used **Rift** (niri-style scrolling strip) plus a custom `rift-swipe`
> C helper; the most recent version used **Paneru** (niri-style sliding strip
> with native per-Space virtual workspaces), followed by **OmniWM** (Swift
> tiling WM with niri-style sliding strips, dynamic workspaces, workspace bar
> overlay, and `omniwmctl` IPC). This version is on **Nehir** (Swift fork of
> OmniWM, niri-style sliding strips, fixed virtual workspaces, window borders,
> workspace bar overlay, and `nehirctl` IPC), which retains the niri layout
> and cursor-warp focus model while switching to a fixed workspace model and
> split TOML config — the `omniwmctl` binary, OmniWM's strict canonical
> schema, and the dynamic workspace lifecycle are all replaced.
