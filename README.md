# rift-wm-installer

A niri-like window management setup for macOS, built on **Rift** (niri-style
scrolling-strip tiler with hot-reloadable TOML config and virtual workspaces),
**Rift's native menu-bar workspace indicators** (no bar app needed),
**JankyBorders** (window focus borders), and **Ghostty** (terminal). Driven by
Option-key shortcuts that don't fight macOS defaults.

## Requirements

- macOS 13+ (Rift; tested on Sequoia and later)
- Apple Silicon or Intel; Homebrew installed or auto-installed
- "Displays have separate Spaces" enabled (Rift-recommended; the installer sets it)
- No Karabiner, no disable of System Integrity Protection

## Quick start

```sh
./install
```

The installer runs these steps from `scripts/`:

| Script | Purpose |
|---|---|
| `install-deps` | Install Homebrew if missing, tccutil-rs, Ghostty |
| `configure-system` | Enable "Displays have separate Spaces" (Rift-recommended) |
| `install-rift` | Install Rift + write `~/.config/rift/config.toml` + install its launchd service |
| `install-borders` | Install JankyBorders + write `~/.config/borders/bordersrc` |
| `grant-permissions` | Grant Accessibility via tccutil-rs (user → sudo → manual fallback) |
| `enable-services` | Start Rift and the `borders` service |

### After install

1. **Log out and back in** (Cmd+Shift+Q) — applies the enabled
   separate-Spaces setting.
2. Rift tiles in a **niri-style scrolling strip**; workspaces `1..9` are
   persistent. `Option+Shift+R` reloads the config (hot reload is also on).
3. Rift draws **workspace badges in the native menu bar** — click a badge to
   switch, and the Rift menu-bar icon opens a workspace/layout menu. No extra
   bar app to install or configure.
4. If Accessibility grants failed, grant them manually:
   System Settings → Privacy & Security → Accessibility (enable Rift, Borders).

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
> gone — Rift's own menu bar replaces SketchyBar entirely.

## The menu bar & notch

- **Workspace indicators** live in the **native menu bar** (Rift's
  `[settings.ui.menu_bar]`): badges for every workspace, click to switch, with a
  menu-bar icon for layout and workspace controls. macOS already lays the menu
  bar around the notch, so there's no notch configuration needed.
- Tune the top gap if the menu bar extends over the notch area on a notched
  display — see `~/.config/rift/config.toml` `[settings.layout.gaps.outer]`.

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

Stops and removes Rift (launchd service) and borders, moves configs (from
`~/.config/rift` and `~/.config/borders`, plus any legacy `~/.config/aerospace`)
to `~/.config/backups/uninstall-<timestamp>/`, then asks you which formulae to
**keep** (interactive numbered menu). Untaps `acsandmann/tap`,
`FelixKratz/formulae`, `uinaf/tap` (and legacy `nikitabobko/tap`, `rdrkr/tap`
only when nothing kept depends on them), and leaves separate Spaces enabled.

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
config/rift/              Rift config (scrolling strip, bindings, gaps, menu bar)
config/borders/bordersrc  JankyBorders focus-border config
tests/                    VM test workflow (tests/preview + lib/ backends)
```

Configs are installed to `~/.config/{rift,borders}`; existing files are backed
up (`.bak`) before overwriting, and Rift has `hot_reload`, so editing
`~/.config/rift/config.toml` applies live.

> **Note on AeroSpace:** an intermediate version of this installer targeted
> AeroSpace (i3-style tree tiler) with AeroSpaceBar in the menu bar. This
> version is back on Rift (niri-style scrolling strip) with Rift's own native
> menu-bar workspace indicators as the bar.