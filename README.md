# aerospace-installer

A niri-like window management setup for macOS, built on **Rift** (tiling window
manager with niri's infinite *scrolling* strip — not a tree-based tiler like
AeroSpace), **SketchyBar** (Nord-themed status bar with workspace indicators
and extra widgets), **JankyBorders** (window focus borders), and **Ghostty**
(terminal). Driven by Option-key shortcuts that don't fight macOS defaults.

## Requirements

- macOS 13+ (Apple Silicon or Intel; Homebrew installed or auto-installed)
- No Karabiner, no disable of System Integrity Protection

## Quick start

```sh
./install.sh
```

The installer runs these steps from `scripts/`:

| Script | Purpose |
|---|---|
| `install-deps` | Install Homebrew if missing, jq, tccutil-rs, nowplaying-cli, Hack Nerd Font, Ghostty |
| `configure-system` | Enable "Displays have separate Spaces", hide the native menu bar |
| `install-rift` | Install Rift + write `~/.config/rift/config.toml` |
| `install-sketchybar` | Install SketchyBar + write `~/.config/sketchybar/` (bar + plugins) |
| `install-borders` | Install JankyBorders + write `~/.config/borders/bordersrc` |
| `grant-permissions` | Grant Accessibility via tccutil-rs (user → sudo → manual fallback) |
| `enable-services` | Start `rift`, `sketchybar`, `borders` as user services |

### After install

1. **Log out and back in** (Cmd+Shift+Q) — applies separate Spaces and the
   hidden menu bar.
2. Rift now tiles **every** Space automatically. Press `Option+Z` on a Space if
   you ever want to take it out of Rift's control.
3. If Accessibility grants failed, grant them manually:
   System Settings → Privacy & Security → Accessibility (enable Rift,
   SketchyBar, Borders).

## Keybindings

Rift modifiers: **Option** (Alt), **Shift**, **Ctrl**, **Cmd** (Meta).

### Navigation & layout

| Shortcut | Action |
|---|---|
| `Option` + Arrows | Move focus between windows |
| `Option` + `Shift` + Arrows | Move window in the strip |
| `Option` + `Ctrl` + Arrows | Resize (left/right grow-shrink, up/down vertical) |
| `Option` + `[` / `]` | Scroll the strip |
| `Option` + `Space` | Center the focused column |
| `Option` + `Tab` | Jump to last workspace |

### Workspaces (9 per display)

| Shortcut | Action |
|---|---|
| `Option` + `1..9` | Switch Rift workspace |
| `Option` + `Shift` + `1..9` | Move window to workspace |
| `Ctrl` + `Left/Right` | Switch macOS Spaces (system default, untouched) |

### Displays (multi-monitor)

| Shortcut | Action |
|---|---|
| `Cmd` + `Option` + Arrows | Move focus to a display |
| `Cmd` + `Option` + `Shift` + Arrows | Move window to a display |

> Scrolling-layout caveat: arrange displays **vertically** in System Settings.
> Side-by-side layouts can leak windows between scrolling strips.

### Window state

| Shortcut | Action |
|---|---|
| `Option` + `Z` | Toggle Rift management of the current Space |
| `Option` + `F` | Fullscreen (no gaps) |
| `Option` + `Shift` + `F` | Fullscreen within gaps |
| `Option` + `V` | Toggle floating |
| `Option` + `Shift` + `Space` | Focus floating windows |
| `Option` + `Q` | Close window |
| `Option` + `W` | Toggle stack |
| `Option` + `/` | Toggle orientation |
| `Option` + `Ctrl` + `E` | Unjoin windows |

### Apps & misc

| Shortcut | Action |
|---|---|
| `Ctrl` + `Cmd` + `T` | Open Ghostty |
| `Cmd` + `Option` + `K` | Toggle the shortcut cheat-sheet in the bar |
| `Option` + `Shift` + `R` | Reload Rift config (hot reload is also on) |
| `Option` + `Shift` + `D` | Debug layout tree |

The **cheat sheet** is a SketchyBar widget (icon ⌨ on the left) that cycles
collapsed → page 1 (navigation) → page 2 (state/misc) → collapsed; it can also
be clicked.

## Multi-monitor

- Each display runs its own independent strip and 9-workspace set; bindings act
  on the focused Space.
- Everything is auto-tiled (`default_disable = false`); `Option+Z` toggles per
  Space.
- Per-display gap overrides are available (commented template in
  `config/rift/config.toml`; get UUIDs with `rift-cli query displays`).

## Uninstall

```sh
./uninstall.sh
```

Stops and removes the services and binaries, moves configs to
`~/.config/backups/uninstall-<timestamp>/`, then asks you which formulae to
**keep** (interactive numbered menu). Untaps `acsandmann/tap`,
`FelixKratz/formulae`, and `uinaf/tap` only when nothing kept depends on them.

## Testing in a macOS VM (Tart)

A full test workflow runs `install.sh` inside a real macOS guest VM, using
Apple's Virtualization.framework for near-native performance:

```sh
./tests/tart-test.sh setup        # installs tart/sshpass (auto), clones host-matched base image
./tests/tart-test.sh up           # boot guest, live-mount the repo, wait for SSH
./tests/tart-test.sh install      # run install.sh in the guest (asks to clean up afterwards)
./tests/tart-test.sh check        # query Rift workspaces + installed formulae
./tests/tart-test.sh shot         # screenshot the bar/tiling into tests/screenshots/
./tests/tart-test.sh clean        # interactively remove VM, tart, sshpass, base image
```

Dependencies (`tart`, `sshpass`) are installed automatically on demand and can
be removed with `clean`. See `./tests/tart-test.sh help` for the full command
list. Limitations: single virtual display (multi-monitor can't be tested),
CPU-rendered animations, Accessibility may need one manual grant inside the
guest.

## Project layout

```
install.sh                Main installer (runs scripts/*.sh)
uninstall.sh              Full uninstaller with interactive keep menu
scripts/                  Per-component install/system/accessibility steps
config/rift/config.toml   Rift config (scrolling layout, bindings, integrations)
config/sketchybar/        Bar config + plugins (rift, clock, media, weather, cpu, ...)
config/borders/bordersrc  JankyBorders focus-border config
tests/                    Tart VM test workflow (tests/tart-test.sh + lib/)
```

Configs are installed to `~/.config/{rift,sketchybar,borders}`; existing files
are backed up (`.bak`) before overwriting. Rift has `hot_reload = true`, so
editing `~/.config/rift/config.toml` applies live.