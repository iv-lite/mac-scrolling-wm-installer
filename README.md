# paneru-wm-installer

A niri-like window management setup for macOS, built on **Paneru** (sliding
infinite-strip tiler with hot-reloadable TOML config, native macOS workspaces
+ virtual workspaces, and a workspace status popup), and **Ghostty**
(terminal). Driven by Cmd+Option-key shortcuts that don't fight macOS defaults.

## Requirements

- macOS 14+ (Paneru)
- Apple Silicon
- Homebrew installed or auto-installed
- "Displays have separate Spaces" enabled (Paneru-recommended; the installer sets it)
- No Karabiner, no disable of System Integrity Protection

## Quick start

```sh
./install
```

Re-running `./install` **upgrades** an existing setup: Homebrew components
(Ghostty, tccutil-rs) are updated (no-op when current), Paneru is refreshed
from its GitHub releases into the canonical daemon path
`~/.local/bin/paneru` (pre-migration copies in `/opt/homebrew/bin` are
removed so two daemons never linger; make sure `~/.local/bin` is on your
`PATH`), configs are refreshed from this repo (previous
copies kept as `*.bak`), and the service is restarted so the new
binary/config apply immediately. `paneru install` is idempotent: it skips
the copy and the re-stamp when the canonical binary already matches, and
rewrites the launchd plist / `Paneru.app` shim whenever they drifted
elsewhere — a real binary change replaces just the binary
and keeps a listed grant (validity confirmed by the post-start health
check; only a failed check triggers revoke + re-grant via repair).

### Local development (`--prefer-local-builds`)

```sh
./install --prefer-local-builds
```

With sibling checkouts next to this repo, the installer builds them from
source instead of downloading releases — no release needed to test a change:

| Sibling repo | Built with | Used for |
|---|---|---|
| `../paneru` | `cargo build --release --bin paneru` (in place, keeps `target/` cache) | the installed binary |
| `../mac-cheatsheet-viewer` | local Tauri build (same as the release-fetch fallback) | the cheat-sheet app |

A missing sibling falls back to its release download; a failed local build
aborts the install (fail fast, so errors surface). Brew/curl dependencies
(Ghostty, tccutil-rs, Antigen) are unaffected by the flag. In VM tests,
forward it via `PREVIEW_INSTALL_ARGS=--prefer-local-builds ./tests/preview install`.

The Paneru build follows the upstream-suggested process: the pinned toolchain
from `../paneru/rust-toolchain.toml` via rustup (a bare Homebrew cargo would
ignore the pin), plain `cargo build --release --bin paneru` (default features
build the vendored LuaJIT — no system Lua needed), and the repo's rustc
wrapper signs the binary with the stable identifier at compile time. The
installer preflights the Xcode command-line tools (needed for the macOS SDKs)
and skips its own re-sign when the identifier is already pinned. To run the
same gate CI runs before installing (fmt, clippy, tests):

```sh
./install --prefer-local-builds --verify   # or PANERU_VERIFY=1
```

The installer runs these steps from `scripts/`:

| Script | Purpose |
|---|---|
| `install-deps` | Install Homebrew if missing, tccutil-rs |
| `configure-system` | Enable "Displays have separate Spaces"; show the native menu bar (Paneru draws its indicator in it) |
| `install-ghostty` | Install Ghostty + write `~/.config/ghostty/config` (frameless title bar) |
| `install-antigen` | Install Antigen (`~/antigen.zsh`) + write `~/.config/zsh/antigen.zsh` (git, command-not-found, completions, autosuggestions, syntax-highlighting last, typewritten theme) + wire it into `~/.zshrc` |
| `install-paneru` | Install Paneru from the `iv-lite/paneru` GitHub releases (newest in list; `PANERU_TAG` pins) into `~/.local/bin/paneru` + write `~/.config/paneru/init.lua` + converge its launchd service and app shim onto the canonical path |
| `repair-paneru` | Self-repair an unhealthy daemon: re-sign → re-grant → restart → re-check (run by `enable-services`, or by hand) |
| `install-helpers` | Install the shortcut helpers into `~/.config/mac-scrolling-wm/helpers/` and install the macOS cheat-sheet viewer app (fetches a pre-built release from GitHub at `iv-lite/mac-cheatsheet-viewer`, falls back to a local source build) |
| `grant-permissions` | Preserve a listed Accessibility grant (zero TCC writes), otherwise grant via tccutil-rs (user → sudo → manual fallback); revokes only on the repair path |
| `enable-services` | Start Paneru |

### After install

1. **Log out and back in** (Cmd+Shift+Q) — applies the enabled
   separate-Spaces setting.
2. Paneru tiles in an **niri-style sliding strip**; new windows are appended at
   the end of the strip and **never resize existing windows**. Virtual
   workspaces are **dynamic rows** created on demand (and reaped when empty).
3. **Paneru** shows the active virtual workspace in a brief popup on switch.
4. If the Accessibility grant failed, grant it manually:
   System Settings → Privacy & Security → Accessibility (enable `paneru`,
   usually shown as `paneru` `~/.local/bin/paneru`). After updating, run
   `paneru install` followed by `paneru restart` first so the service
   points at the new binary — then grant once for the updated build.
5. Ghostty opens **frameless** (`macos-titlebar-style = hidden` in
   `~/.config/ghostty/config`) — drag its window edge with `Option+Click`.

## Keybindings

Paneru modifiers: **Cmd+Option** (columns), **Cmd+Ctrl** (displays),
**Ctrl+Option** (virtual workspace rows), **Shift** (**moves** the focused
window in the same lane), **Ctrl**.

### Navigation & layout

| Shortcut | Action |
|---|---|
| `Cmd` + `Option` + Arrows | Move focus between windows |
| 3-finger swipe (← / →) | Page through windows — one full-width window per swipe, snapping on release (`rift-swipe` is gone; Paneru snaps + focuses natively) |
| `Cmd` + `Option` + `Shift` + Arrows | Move window (swap) |
| `Cmd` + `Option` + `W` | Cycle the focused column width (0.3 / 0.5 / 1) |
| `Cmd` + `Option` + `Shift` + `W` | Cycle width backwards |
| `Cmd` + `Option` + `Space` | Center the focused window/viewport |
| `Cmd` + `Option` + `Shift` + `Space` | Snap an overflowing window into the viewport |
| `Cmd` + `Option` + `M` | Toggle full-width for the focused window |

> Focus **follows the mouse**, and keyboard navigation warps the cursor to
> the **center** of the focused window (`focus_follows_mouse` /
> `mouse_follows_focus` in `[options]`) — even when the cursor is already
> inside it. Clicks own their cursor (never yanked) and mid-drag focus
> changes never warp.

### Workspaces (dynamic rows)

| Shortcut | Action |
|---|---|
| `Ctrl` + `Option` + `↑` / `↓` | Switch to the previous/next virtual workspace row (rows are created on demand past the last one) |
| `Ctrl` + `Option` + `Shift` + `↑` / `↓` | Move the focused window to the previous/next row and follow |
| 3-finger swipe (↑ / ↓) | Switch virtual workspace rows (trackpad) |
| `Cmd` + `Option` + `Tab` | Focus the last-focused window on this workspace |

> Workspace rows are **dynamic**: a new row spawns when you cross the last one
> and vanishes once it's empty (`create_virtual_workspace_automatically = true` /
> `reap_empty_workspaces = true` in `[options]`, both booleans defaulting to false upstream).

> Paneru virtual workspaces are stacks of horizontal strips *inside* a native
> macOS workspace. Each native Space (per display, with separate Spaces on) has
> its own strip and its own set of virtual workspaces.

### Displays (multi-monitor)

| Shortcut | Action |
|---|---|
| `Cmd` + `Ctrl` + `←` | Focus the previous display (window stays put) |
| `Cmd` + `Ctrl` + `→` | Focus the next display (window stays put) |
| `Cmd` + `Ctrl` + `Shift` + `←` | Move the focused window to the previous display and follow |
| `Cmd` + `Ctrl` + `Shift` + `→` | Move the focused window to the next display and follow |
| `Cmd` + `Ctrl` + `Alt` + `←` | Send the focused window to the previous display (stay) |
| `Cmd` + `Ctrl` + `Alt` + `→` | Send the focused window to the next display (stay) |
| `Cmd` + `Ctrl` + `↑` | Warp the mouse to the next display |
| `Cmd` + `Ctrl` + `↓` | Warp the mouse to the previous display |
| `Cmd` + `Alt` + drag across display edge | Hold to arm, cross the edge to move the window to that display live (lands in nearest column; a plain titlebar drag scrolls the strip instead, content grabs stay native — `left_drag_scrolls_strip`) |
| `Cmd` + `Option` + `↑`/`↓` | Focus a column above/below — crosses displays when no window is there |
| `Cmd` + `Option` + `Shift` + `↑`/`↓` | Move a window to the display above/below (when no window is there to swap with) |

Display navigation is native in the installed Paneru fork
(`iv-lite/paneru`, fetched from its GitHub releases by
`scripts/install-paneru`): `window previousdisplay` /
`previousdisplaysend`, `window nextdisplay` / `nextdisplaysend`, and `mouse
previousdisplay` / `nextdisplay` are first-class commands (Lua:
`paneru.window.previous_display()` / `paneru.mouse.previous_display()`),
all wired as plain `BINDINGS`-table entries in `config/paneru/init.lua` —
no Lua modules, no compiled helpers.

> **Previous/next are true inverses on any number of displays.** The fork
> orders displays into a spatial ring (`min.x, min.y, id` in
> `src/ecs/params.rs`), so next undoes previous from every position —
> the old upstream `other().next()` single-hop limit (which strand‑hopped
> between two of three+ monitors) is gone.
>
> **Focus is the mouse warp.** `Cmd+Ctrl+←/→` send `mouse
> previousdisplay` / `nextdisplay`: the daemon warps to the target
> display's most visible window (focusing it via `focus_follows_mouse`)
> or to the display center when it holds no windows — empty displays stay
> reachable with no helper. `↑`/`↓` are extra chords onto the same two
> commands. Moves (`window previousdisplay` / `nextdisplay`) reposition to
> the target display's center and warp along on follow; `...send` variants
> stay on the source display.
>
> **Vertical crossings are direction-aware.** `Cmd+Option+↑/↓` focus (and
> `Shift`+`↑/↓` swap) fall through to the nearest display above/below —
> not just "the other one" — so multi-monitor stacks behave.
>
> One-time cost: grant Accessibility access to the `paneru` binary itself
> (macOS prompts on first run). No helper binaries need grants anymore —
> `scripts/install-helpers` removes the stale `move-display`,
> `warp-pointer`, `display-geometry`, `mouse-display`, `wait-*` copies.

### Window state

| Shortcut | Action |
|---|---|
| `Cmd` + `Option` + `V` | Toggle floating/tiled |
| `Cmd` + `Option` + `O` | Stack the window into the neighbouring column |
| `Cmd` + `Option` + `Shift` + `O` | Pull a window out of a stack |
| `Cmd` + `Option` + `B` | Balance all columns to the focused window's width |
| `Cmd` + `Option` + `Shift` + `E` | Equalize the heights in a stack |
| `Cmd` + `Option` + `Shift` + `C` | Copy a Paneru window rule for the focused window |
| `Cmd` + `Option` + `Ctrl` + `Q` | Quit Paneru |

### Apps & misc

| Shortcut | Action |
|---|---|
| `Cmd` + `Option` + `Shift` + `R` | Restart Paneru (config also live-reloads on save) |
| `Cmd` + `Shift` + `?` | Show the shortcut cheat sheet (regenerates the JSON from `init.lua`, then opens `mac-cheatsheet-viewer`) |

### Shortcut cheat sheet (Cmd+Shift+?)

`Cmd+Shift+?` runs `display-shortcuts`, which regenerates the cheat-sheet JSON
from the live Paneru config and opens it in `mac-cheatsheet-viewer`, a
borderless always-on-top overlay (Esc / Cmd+W to close). The pieces:

- `helpers/generate-shortcuts-json` — parses the `BINDINGS` table in
  `~/.config/paneru/init.lua`, humanizes the chords, and emits
  `~/.config/paneru/cheatsheet.json` (curated action labels; unknown bindings
  fall back to their command name).
- `helpers/display-shortcuts` — runs the generator and opens the viewer.
- `mac-cheatsheet-viewer` — a separate repo (`iv-lite/mac-cheatsheet-viewer`)
  holding the Tauri app (static vanilla frontend, no npm) whose CLI arg is the
  JSON path; it validates strictly (`cheatsheet-core` crate) and renders
  bordered groups. `install-helpers` fetches the `.app.zip` of the **newest
  release in the GitHub release list** (the special-latest endpoint is never
  used; prereleases are included, drafts excluded, releases without the asset
  skipped) and overwrites the installed bundle on every run.
  `MAC_WM_VIEWER_REPO` changes the repo, `MAC_WM_VIEWER_TAG` pins an exact
  tag; a CI workflow in that repo builds DMG + `.app` releases for every `v*`
  tag. If the fetch fails, it falls back to a local source build at
  `../mac-cheatsheet-viewer`.
- Paneru itself runs the launcher via its Lua API
  (`paneru.exec`), which is why the config is `init.lua` (a Lua config
  replaces the legacy `paneru.toml`; TOML bindings cannot launch scripts).

Installed helpers live in `~/.config/mac-scrolling-wm/helpers/` (copied on
`install`, removed by `uninstall`).

> **Removed vs. the Rift/AeroSpace setups:** fine-grained resizing
> (`Option+Ctrl+arrows` step-resize), fullscreen toggles, per-Space tiling
> toggles (`Alt+Z`), strip scroll half-steps (`Alt+[`/`]`), and an
> `open-terminal` shortcut have no Paneru equivalent and were dropped. The
> SketchyBar cheat sheet is long gone — Paneru draws the workspace indicator in
> the (native) menu bar.

### The infinite horizontal canvas

The niri-style sliding strip behaves like a canvas **wider than the monitor**:
unfocused windows park off-screen and glide in/out of the screen edges as focus
moves. Two things make it feel native:

- Paneru keeps a thin **sliver** of each off-screen window visible at the
  screen edge (a workaround for macOS relocating windows that move fully
  off-screen, not a design choice; the shipped config uses the upstream
  defaults).
- `swipe.continuous = true` bounds the strip to its left/right-most window,
  so a full 3-finger swipe lands exactly on the next full-width window
  (page-flip).
- `options.preset_column_widths = { 0.3, 0.5, 1.0 }` cycling and
  `window_fullwidth` (Cmd+Option+M) cover on-demand sizing; new windows
  start full-width (`options.default_ratio = 1.0`, large Firefox windows
  re-pinned to `0.5` at spawn by the config handler), are appended at the
  end and never resize existing ones.
- Between-window gaps come from the `gaps` table (`horizontal = 8`,
  `vertical = 8`): the per-window inset every tiled window gets. The
  visual gap between neighbours is the sum (`8 + 8 = 16px` between
  columns); values clamp `0–50`, a per-window rule wins including `0` to
  opt out, outer screen edges stay in `padding`.
- A lone column narrower than the viewport is centered
  (`options.center_single_column = true`); multi-column strips stay
  left-pinned. `auto_center` remains `false`, so focus changes never
  recenter — only the single-column case does.
- Titlebar (top 28px) **or blank toolbar chrome** left-drags scroll the strip horizontally only (vertical
  travel is dropped) tracking the pointer 1:1 while held — friction lives
  only on the release glide (pace-sensitive release velocity seeds inertia/snap,
  click jitter absorbed by a dead-zone, scroll-glides never transfer displays,
  hover focus deferred while held); buttons, text fields, tab drags and content grabs stay native and drive nothing beyond
  press/release bookkeeping, while armed `Cmd+Alt` drags move live, landing
  in the nearest column. Click-focus never grows a window, pure clicks skip
  the most-visible reveal, and single-flight keyboard focus (strip-only centering
  with monotonic offsets plus settle detection; the focus echo stands down while the strip is
  mid-flight) are native. Tiles clamp to the viewport, new windows glide
  into view, app quit cascades to its windows (borders clear, strips
  re-tile), and strips fill the viewport on focus, move and drag
  so they never rest next to whitespace.
- Tiled windows fill their tile slot (`options.maximize_tiled_windows = true`,
  at launch snap and on every layout change).
- Driven moves glide with an ease-out-cubic curve (`options.animations = true`: fast
  attack, decelerating landing, lockstep bursts with synced join pacing, 2px first-tick kick,
  distance-proportional duration around the 150ms base up to 220ms on
  long/ultrawide traverses; `false` snaps instantly — one switch since fork
  `7496610`, older binaries ignore it and glide on their default);
  virtual-row switches snap (`options.virtual_workspace_animations = false`).
- Session restore remembers each window's display UUID/frame (state v4, active-display
  fallback clamped to the viewport) and prunes
  saved windows whose app never opened at grace expiry
  (`restore.missing_windows = "drop"`).
- AX position commits go through a dedicated writer thread
  (`options.ax_writer = true`, window-id drain order, frame-epoch
  convergence with stuck-writer watchdog, degrade-to-sync fallback ladder
  with automatic recovery), and the pump paces to the display
  retrace where supported (always-on, macOS 14+).

## The menu bar

- The **native macOS menu bar** is kept. The menu-bar workspace indicator is
  **disabled by default** (`decorations` in `~/.config/paneru/init.lua`,
  `workspace_menu_status = false`) because Paneru < the fix in
  [karinushka/paneru#390](https://github.com/karinushka/paneru/issues/390)
  hosts a live view in the status item, and its AppKit redraw loop starves the
  run loop that services Paneru's `CGEventTap` — keybindings silently die after
  leaving native fullscreen. A brief status popup still announces the active
  workspace on switch; re-enable the indicator once a Paneru release ships #390.
- **Focus cues**: a slim active-window border (`decorations.active.border`, Nord
  blue, 2px at full opacity) replaces JankyBorders — no extra bar process needed.
  Inactive borders stay off (`decorations.inactive.border`) since they re-sync
  every tiled window on each animating tick; inactive-window
  dimming uses native macOS (`decorations.inactive.dim`).
- **Top gap:** `padding.top` is 8px in the config (all sides 8px, menu bar kept visible).
  Between-window gutters are separate: `gaps = { horizontal = 8, vertical = 8 }`.

## No title bars (the macOS reality)

macOS tiling window managers (Paneru included — same as yabai/AeroSpace) cannot
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

**Shortcuts become unresponsive after toggling off full screen.** Upstream bug
[karinushka/paneru#390](https://github.com/karinushka/paneru/issues/390): the
menu-bar workspace indicator's live view starves the run loop that services
Paneru's `CGEventTap`, so macOS disables the tap and keybindings (clicks and
swipes too) silently stop working. This repo works around it by shipping
`workspace_menu_status = false` (workspace switches are still announced by the
popup). Immediate recourse: `paneru restart`. Re-enable the indicator once a
Paneru release includes the #390 fix; concurrently, keep Paneru at ≥ 0.5.0 so
the event-tap watchdog (karinushka/paneru#350) is present.

**Paneru runs but doesn't tile after an upgrade.** Replacing an
identifier-pinned binary at the same canonical path normally preserves the
Accessibility grant (the installer pins the stable identifier
`com.github.karinushka.paneru` onto the downloaded binary and keeps a listed
grant with zero TCC writes — verified live: tiling survives the swap).
If tiling still doesn't start, converge first (`paneru install`, then
`paneru restart`) so the plist and shim point at the new binary — then
re-grant once, since ad-hoc signatures change hash per build.
If it is still dead, the grant is stale-but-listed: `enable-services`
runs a self-repair on an unhealthy daemon (`scripts/repair-paneru`: re-sign →
revoke + re-grant → restart → re-check, twice, then one manual-grant pause
when interactive). Revoking and granting both go through `tccutil-rs`, which
can only touch the TCC database when the terminal running the installer has
**Full Disk Access** (System Settings → Privacy & Security → Full Disk Access, then
fully quit and reopen the terminal). Without it the installer skips all
scripted TCC writes and hands off to Paneru itself: the freshly started
daemon parks with a setup dialog and waits — flip the toggle in System
Settings → Privacy & Security → Accessibility and tiling starts (the toggle
replaces a stale row itself). Only if Paneru is already listed-but-dead,
remove that entry with `–` first, then toggle it back on. If you still
see no tiling, repair by hand:

```sh
codesign --force --sign - --identifier com.github.karinushka.paneru "$HOME/.local/bin/paneru"
bash scripts/grant-permissions   # terminal needs Full Disk Access for this
paneru restart
```

**Paneru won't start / instantly exits.** Paneru hard-exits unless it has
Accessibility and "Displays have separate Spaces" is **ON**. The installer's
`configure-system` / `ensure-separate-spaces` handles the latter. If grants
failed, give the terminal **Full Disk Access** first, then:

```sh
bash scripts/grant-permissions
paneru restart
```

Paneru's own debug trail: `paneru printstate` (via `paneru send-cmd printstate`),
logs from its LaunchAgent, and the interactive `paneru` front-run for the same
output. A quick health check of the whole stack:

```sh
bash scripts/ensure-separate-spaces check   # must print "enabled (mode 1)"
paneru query state --json                   # must print a JSON snapshot (service up)
```

## Multi-monitor

- Paneru gives each display its **own independent window strip** and its own
  set of native workspaces (with "Displays have separate Spaces" on).
- The shipped config targets **horizontally stacked** (side-by-side) monitors:
  arrange the displays **vertically** in System Settings → Displays (laptop
  above/below the external monitor) but place them physically side-by-side.
  `horizontal_mouse_warp = -1` (in `options` in `config/paneru/init.lua`) then
  makes the cursor cross screen edges left↔right exactly as if the monitors
  were side-by-side — matching macOS's native behavior while keeping Paneru's
  vertical display traversal intact.
- If one display physically sits higher or lower than the other (e.g. a
  portrait monitor on a stand), adjust `horizontal_mouse_warp_offset` (px) to
  line the warp landing up with the desk positions.
- A window can be sent to another display with `Cmd+Ctrl+Shift+→` (follow) or
  `Cmd+Ctrl+Alt+→` (stay), `Cmd+Ctrl+←/→` focuses the other display, and
  `Cmd+Ctrl+↑/↓` warps the mouse there.

## Uninstall

```sh
./uninstall
```

Stops and removes Paneru (release binary, launchd service, app launcher),
revokes its Accessibility grant, moves configs (from `~/.config/paneru`,
`~/.config/ghostty`, `~/.config/mac-scrolling-wm`, `~/.config/zsh/antigen.zsh`,
plus `~/.paneru*` and
Paneru's state dir) to `~/.config/backups/uninstall-<timestamp>/`, removes
`~/antigen.zsh`, the Antigen caches and the marked `~/.zshrc` block, then asks
you which formulae to **keep** (interactive numbered menu). Untaps
`uinaf/tap` when nothing kept needs it, and restores the native menu bar.
Only items that are actually present are touched — absent items are silently
skipped, never warned about.

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
./tests/preview check        # query Paneru state + binary + native display cmds
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
config/paneru/            Paneru config (sliding strip, bindings, rules) — init.lua
config/ghostty/           Ghostty config (frameless title bar)
helpers/                  shortcut cheat-sheet: generate-shortcuts-json,
                           display-shortcuts (mac-cheatsheet-viewer app lives
                           in its own repo at iv-lite/mac-cheatsheet-viewer)
tests/                    VM test workflow (tests/preview + lib/ backends)
```

Configs are installed to `~/.config/{paneru,ghostty}` (plus shortcut helpers
under `~/.config/mac-scrolling-wm/`);
existing files are backed up (`.bak`) before overwriting, and Paneru
hot-reloads `~/.config/paneru/init.lua`, so edits apply live.

> **Note on the history:** an early version of this installer targeted
> AeroSpace (i3-style tree tiler) with AeroSpaceBar in the menu bar; a later
> version used **Rift** (niri-style scrolling strip) plus a custom `rift-swipe`
> C helper repurposing Rift's pan-only gesture. This version is on **Paneru**
> (niri-style sliding strip), which pages windows + snaps + focuses on gesture
> release natively — so the Rift-era helper, its LaunchAgent, JankyBorders, and
> the `cycle-column-width` Python helper are all gone, and BSP/border chromes
> come from Paneru itself. The pre-fork display-navigation workarounds are
> gone too (`lib/displays.lua`, `move-display`, `warp-pointer`,
> `display-geometry`, `mouse-display`, `wait-*`): the `iv-lite/paneru` fork
> implements previous/next display natively.