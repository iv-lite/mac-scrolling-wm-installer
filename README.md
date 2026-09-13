# aerospace-installer

An i3-like window management setup for macOS, built on **AeroSpace** (tree-based
tiler with plain-text TOML config and virtual workspaces), **AeroSpaceBar**
(SwiftUI menu-bar companion showing your workspaces), **JankyBorders** (window
focus borders), and **Ghostty** (terminal). Driven by Option-key shortcuts that
don't fight macOS defaults.

## Requirements

- macOS 15+ (required by AeroSpaceBar; AeroSpace itself runs on 13+)
- Apple Silicon or Intel; Homebrew installed or auto-installed
- No Karabiner, no disable of System Integrity Protection

## Quick start

```sh
./install
```

The installer runs these steps from `scripts/`:

| Script | Purpose |
|---|---|
| `install-deps` | Install Homebrew if missing, tccutil-rs, Ghostty |
| `configure-system` | Disable "Displays have separate Spaces" (AeroSpace-recommended) |
| `install-aerospace` | Install AeroSpace + write `~/.config/aerospace/aerospace.toml` |
| `install-aerospacebar` | Install AeroSpaceBar (menu-bar workspace switcher) |
| `install-borders` | Install JankyBorders + write `~/.config/borders/bordersrc` |
| `grant-permissions` | Grant Accessibility via tccutil-rs (user → sudo → manual fallback) |
| `enable-services` | Start AeroSpace, AeroSpaceBar, and the `borders` service |

### After install

1. **Log out and back in** (Cmd+Shift+Q) — applies the disabled
   separate-Spaces setting.
2. AeroSpace tiles in the **i3-style tree layout**; workspaces `1..9` are
   persistent. `Option+Shift+R` reloads the config (auto-reload is also on).
3. **AeroSpaceBar** shows the workspace badges in the native menu bar — click a
   badge to switch, hover to preview windows. Enable "start at login" in its
   Settings if you want it always on.
4. If Accessibility grants failed, grant them manually:
   System Settings → Privacy & Security → Accessibility (enable AeroSpace,
   Borders).

## Keybindings

AeroSpace modifiers: **Option** (Alt), **Shift**, **Ctrl**, **Cmd** (Meta).

### Navigation & layout

| Shortcut | Action |
|---|---|
| `Option` + Arrows | Move focus between windows |
| `Option` + `Shift` + Arrows | Move window in the tree |
| `Option` + `Ctrl` + Arrows | Resize (left/right width, up/down height) |
| `Option` + `Tab` | Jump to last workspace |
| `Option` + `Shift` + `Tab` | Move workspace to next display |

### Workspaces (1-9)

| Shortcut | Action |
|---|---|
| `Option` + `1..9` | Switch AeroSpace workspace |
| `Option` + `Shift` + `1..9` | Move window to workspace |
| `Option` + `Shift` + `;` | Enter `service` mode (reset layout, balance, etc.) |

### Displays (multi-monitor)

| Shortcut | Action |
|---|---|
| `Cmd` + `Option` + Arrows | Move focus to a display |
| `Cmd` + `Option` + `Shift` + Arrows | Move window to a display |

> AeroSpace workspaces are **not** 1:1 with macOS Spaces — each workspace is a
> virtual container you can move between monitors. Moves across the tree still
> respect physical display layout.

### Window state

| Shortcut | Action |
|---|---|
| `Option` + `F` | Toggle fullscreen (with outer gaps) |
| `Option` + `V` | Toggle floating/tiling |
| `Option` + `Q` | Close window |
| `Option` + `W` | Accordion (stack-like) layout |
| `Option` + `/` | Toggle orientation |
| `Option` + `Ctrl` + `E` | Flatten/reset the layout tree |

### Apps & misc

| Shortcut | Action |
|---|---|
| `Ctrl` + `Cmd` + `T` | Open Ghostty |
| `Option` + `Shift` + `R` | Reload AeroSpace config (auto-reload also on) |
| `Option` + `Tab` | Jump to last workspace |

> **Moved/removed vs. the old Rift setup:** the scrolling strip (`Option+[`
> `]`), per-Space tiling toggle (`Option+Z`), and the SketchyBar cheat sheet
> (`Cmd+Option+K`) don't map to AeroSpace's tree model and are gone. Workspace
> switching via macOS Spaces (`Ctrl+Left/Right`) is replaced by `Option+1..9`.

## The notch

Two sides to it:

- **AeroSpaceBar** is a native menu-bar app — macOS already lays the menu bar
  around the notch, so there is **no notch configuration** needed.
- **AeroSpace** measures the top gap from the bottom of the notch on notched
  displays and from the very top of un-notched ones. If you mix a notched MacBook
  with an external display, set a per-monitor top gap (commented template in
  `~/.config/aerospace/aerospace.toml`):

  ```toml
  gaps.outer.top = [{ monitor.main = 8 }, 15]
  ```

  `monitor.main` is the display holding the menu bar (usually the laptop).
  Get your identifiers with `aerospace list-monitors`.

## Multi-monitor

- AeroSpace's recommended "Displays have separate Spaces" = **off** means fewer
  macOS Spaces and more stable window tracking. Trade-off: with native macOS
  fullscreen, a second display shows a black screen.
- Workspaces are virtual; keep them on your preferred monitor with
  `workspace-to-monitor-force-assignment` in the config, or move them live with
  `Option+Shift+Tab`.
- Per-monitor gap overrides are supported (see the notch section above).

## Uninstall

```sh
./uninstall
```

Stops and removes the apps and services, moves configs (from `~/.config/
aerospace` and `~/.config/borders`) to
`~/.config/backups/uninstall-<timestamp>/`, then asks you which formulae to
**keep** (interactive numbered menu). Untaps `nikitabobko/tap`,
`rdrkr/tap`, `FelixKratz/formulae`, and `uinaf/tap` only when nothing kept
depends on them, and re-enables "Displays have separate Spaces".

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
./tests/preview check        # query AeroSpace workspaces + installed formulae
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
config/aerospace/         AeroSpace config (tree layout, bindings, gaps)
config/borders/bordersrc  JankyBorders focus-border config
tests/                    VM test workflow (tests/preview + lib/ backends)
```

Configs are installed to `~/.config/{aerospace,borders}`; existing files are
backed up (`.bak`) before overwriting, and AeroSpace has `auto-reload-config`,
so editing `~/.config/aerospace/aerospace.toml` applies live.

> **Note on Rift:** an earlier version of this installer set up Rift (a
> niri-style scrolling-strip tiler). This version switched to AeroSpace (tree
> tiler) with AeroSpaceBar in the menu bar.