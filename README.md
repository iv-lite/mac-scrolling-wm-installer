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
from its GitHub releases into the brew bin dir (`/opt/homebrew/bin/paneru`,
`~/.local/bin/paneru` fallback; `PANERU_BINDIR` overrides), configs are
refreshed from this repo (previous copies kept as `*.bak`), the launchd
plist is re-laid from the installed binary, and the service is restarted so
the new binary/config apply immediately. Upstream `paneru install` is
write-once (skips when the plist exists and pins the invoking binary's
path), so the installer re-lays the plist itself on every run — upgrades keep
the existing Accessibility grant (stable `Paneru Local` signing identity;
grant-permissions grants only when missing, and only a failed post-start
health check triggers repair, the sole revoke path).

### Local development (`--prefer-local-builds`)

```sh
./install --prefer-local-builds
```

With sibling checkouts next to this repo, the installer builds them from
source instead of downloading releases — no release needed to test a change:

| Sibling repo | Built with | Used for |
|---|---|---|
| `../paneru` | `cargo build --release --bin paneru` (in place, keeps `target/` cache) | the installed Rust binary (Rust installs only) |
| `../paneru/swift-daemon` | `swift build -c release` (`paneru-swift` + `RenderPlist` + `pq`, in place keeping `.build/` cache) | the Swift daemon (always from source — `--swift` implies a local build, no release exists) |
| `../mac-cheatsheet-viewer` | local Tauri build (same as the release-fetch fallback) | the cheat-sheet app |

A missing sibling falls back to its release download (except Swift, which
has no release artifact and aborts when the checkout is missing); a failed
local build aborts the install (fail fast, so errors surface).
`--prefer-local-builds` alone builds the Rust daemon; adding `--swift`
switches to a Swift-only install (the Rust daemon is neither built nor
kept). Brew/curl dependencies (Ghostty, tccutil-rs, Antigen) are
unaffected by the flag. In VM tests,
forward it via `PREVIEW_INSTALL_ARGS=--prefer-local-builds ./tests/preview install`.

The Paneru build follows the upstream-suggested process: the pinned toolchain
from `../paneru/rust-toolchain.toml` via rustup (a bare Homebrew cargo would
ignore the pin), plain `cargo build --release --bin paneru` (default features
build the vendored LuaJIT — no system Lua needed), and the repo's rustc
wrapper signs the binary with the stable identifier at compile time. The
installer preflights the Xcode command-line tools (needed for the macOS SDKs)
and re-pins the identifier on the installed binary unconditionally. To run the
same gate CI runs before installing (fmt, clippy, tests — Rust local builds
only; on release installs `--verify` is a no-op for Rust but still gates
the Swift checks when `--swift` is set):

```sh
./install --prefer-local-builds --verify   # or PANERU_VERIFY=1
```

### Swift daemon (`--swift`)

```sh
./install --prefer-local-builds --swift   # or PANERU_SWIFT=1
```

With a sibling `../paneru` checkout containing `swift-daemon/`, this builds
the upstream `paneru-swift` + `RenderPlist` + `pq` products
(`swift build -c release`, in place keeping `.build/` cache; fully
offline — all targets are local plus vendored C; Swift 6 toolchain
required, i.e. Xcode 16+ — the installer aborts otherwise with a clear
message) and installs
`paneru-swift` and `pq`, the daemon signed with
upstream's Swift identifier (`com.github.iv-lite.paneru-swift`, renamed in
upstream `d04db61`) under the
persistent `Paneru Local` signing identity (`scripts/ensure-signing-identity`,
`PANERU_SIGN_IDENTITY` overrides for a paid Developer ID) so the grant
converges with a manual upstream install instead of forking identity —
and stays valid across rebuilds with no remove/regrant (the rename itself
re-prompts once: remove the stale old-Swift Accessibility row
`com.github.karinushka.paneru.swift`, toggle the new `paneru-swift` row on;
`PANERU_SIGN_CERT` renames the
cert before first use only)
(`pq` needs no grant — it only talks to the daemon over XPC, and is
otherwise uninstalled upstream; the installer ships it for health
checks). `enable-services` then bootstraps the
Swift agent (`com.github.iv-lite.paneru-swift`, same model as upstream
`swift-daemon/install-service.sh`, which migrates the previous
`...karinushka.paneru.swift` agent away — this installer does the same on
every `--swift` install). Swift-only: the Rust daemon is neither built
nor kept — an existing Rust service/binary/shim is removed so two tilers
never fight, and a missing/unhealthy Swift agent is a hard error (no Rust
fallback). Downgrading back is plain `./install` (re-fetches Rust and parks
the Swift agent). The installed plist also pins `PANERU_MACH_SERVICE` to the
Swift label (the daemon default since upstream `0d3c2ab`, renamed in
`d04db61`): the daemon
resolves its listener via `paneruServiceNameResolved()` (suffixed unless
overridden) while the plist advertises the suffixed Mach service, so
launchd always routes `pq` to the agent — and `pq` is invoked with the
same env (falling back to bare `pq` for daemons without the pin). Lua handlers and full
TOML options are hosted (`swift.toml` fallback exists upstream, but this
installer ships Lua-only `init.lua`, which replaces TOML rather than
layering); queries answer over XPC with `pq` as the shell one-liner
(`pq state`, `pq active`, `pq virtual-workspaces`, `pq on-screen`,
`pq run`, `pq state-get`/`state-write`, `pq state-remove`, `pq apply`,
`pq subscribe` — the last two mirror Rust `paneru state remove` and
`paneru subscribe`, the latter streaming daemon events as JSON lines
until interrupted) — `enable-services`
and `repair-paneru` use `pq state` as the Swift health check, same as
`paneru query state` for Rust. Session restore persists across restarts
(XDG state dir, 30s dirty cadence + `.bak`, crash marker; display UUIDs
consulted first), every controlled shutdown saves (menubar/XPC
quit+restart, SIGTERM/SIGINT). Stacks split viewport height, per-window
SLS corner radii (plus per-window `border_radius` rule overrides),
epoch-clocked eased glides, async AX writes with ack
mailbox + stall watchdog, focus-heal, SLS strip-per-Space layouts, and
modifier-armed cross-display pointer drags are live. Model focus actuates
the OS without stealing key (hover/ambient arrivals claim only, close
heals to the nearest survivor, and focus stranded on a hidden window (minimized
or stashed on an inactive Space) heals to the nearest visible neighbor, clearing
when none is visible); focus arrivals always land fully in view
(fully- and partially-hidden alike, re-evaluated when the focused window's
width changes, settled clicks still rest quiet —
`window_hidden_ratio` governs unfocused windows only; hover echoes never
warp the mouse); programmatic moves (reveal/center/snap)
glide burst-joined while swipe/scroll stay immediate (the shipped
`swipe.gesture.direction = "Natural"` is honored — `Reversed` mirrors strip
travel); fast and diagonal flings warp via edge-crossing eval instead of
missing the edge band; short singles/tabs
vertically center; cross-display drops resolve by full-point containment so
stairs-arranged monitors land correctly; unarmed drags keep native text selection (zero AX
traffic, ghost + glide-home only) and lone fullWidth-marked columns
(e.g. the Firefox spawn pin below) center absolutely; borders hug the glass
with a padding-aware cutout for dimming and track live glass via boosted
focused-window reads; mouse-follow warps land on the full-frame center,
native-fullscreen windows stay rostered instead of vanishing, and display
mapping is UUID-stable so monitors never shuffle windows. A 5s audit re-homes
drifted windows even when the writer is degraded, a rest-state overlap watch
reports unexplained glass overlaps, and the agent log triages
itself: `drift:` lines name diverged windows (model vs slot vs live frame
plus `leg/homing/held/unacked/streak/degraded` flags, silent when converged),
`overlap:` lines name rest-state overlaps with slot verdicts,
`focus: reveal/center/skipped/healed/cleared` lines explain arrival decisions
and focus-stranding repairs, `move:` lines log
cross-display transfers with source/target/members, and `stuck:` lines list
windows the audit repaired three times running (retile watchlist) alongside
`ax:` lane-retirement and `display:` refresh notes —
`grep -E '^(drift|focus|overlap|perf|move|stuck|ax|display): ' /tmp/com.github.iv-lite.paneru-swift_$(id -u).out.log | tail`.
Opt-in slow-tick timing for jank triage: `PANERU_PERF=1` in the agent env
(restart to toggle) logs `perf:` phase breakdowns past 8ms.
Release installs are
unaffected (no Swift binary ships in release tarballs). With `--verify`,
every Swift checks runner runs, then the Rust trace corpus is dumped
like CI (`PANERU_TRACE_OUT cargo test trace`, or your `PANERU_TRACE_DIR`)
and `FrameParityChecks` diffs the replay. Never set
`PANERU_SWIFT_DAEMON` yourself: upstream `1`/`shadow` hard-errors the Rust
daemon at launch. One path still needs a real login to verify: the
launchd-held Mach port (`pq` against a hand-run daemon gets no reply —
expected, use `cat /tmp/paneru-swift-state.json` instead).

Observer mode: `paneru-swift --shadow` runs the Swift daemon as a dry-run
observer beside live Rust — no AX writes, no cursor warps, no overlay
paint, no menubar, no XPC serve, no session saves. It polls the running
Rust daemon (`paneru query state --json`, so `paneru` must be on `PATH`)
and logs rest-state diffs (`shadow: DIFF…`, capped per poll); rest state
lands at `/tmp/paneru-swift-shadow.json` instead of
`/tmp/paneru-swift-state.json`. Hand-run only (never bootstrapped);
`uninstall` cleans up both state files. Unavailable after a Swift-only
install (no Rust binary is kept) — use a Rust install for shadow runs.

Cutover (Rust→Swift cold flip): `bash scripts/cutover-flip` migrates the
live Rust layout to Swift without losing window placement — `paneru
handoff` captures strips/offsets/focus to ephemeral
`/tmp/paneru-handoff.json` (never the session file), Rust stops, and the
Swift binary hand-runs with `--flip-from` (the launchd agent cannot take
flags, so the flipped daemon is `nohup`-detached, not launchd-managed,
and the agent stays disabled until the next `./install --swift`). A
failed health poll undoes the flip automatically (Swift killed, Rust
restarted). `rollback` returns to Rust (it only ever stops the recorded
flip PID, never the launchd agent); `status` reports both sides.
Grants are untouched (same binary path, stable identity).
Requires both binaries present — not usable after a Swift-only install
removed Rust (re-install Rust first, or just `./install --swift`).

Live reload during development (config hot-reloads in place, source
changes rebuild + kickstart the agent):

```sh
./install --prefer-local-builds --swift --live   # or PANERU_LIVE=1
# or, after an install: bash scripts/dev-swift-watch
```

Shared Swift helpers live in `scripts/lib/swift-common.sh` (label,
`pq` wrapper, health poll, launchd start/stop) used by
`install-paneru` / `enable-services` / `repair-paneru`;
`scripts/verify-swift` holds the `--verify` checks gate.

The installer runs these steps from `scripts/`:

| Script | Purpose |
|---|---|
| `install-deps` | Install Homebrew if missing, tccutil-rs from its GitHub releases (tracks latest; `TCCUTIL_RS_VERSION` pins) |
| `configure-system` | Enable "Displays have separate Spaces"; show the native menu bar (Paneru draws its indicator in it) |
| `install-ghostty` | Install Ghostty + write `~/.config/ghostty/config` (frameless title bar) |
| `install-antigen` | Install Antigen (`~/antigen.zsh`) + write `~/.config/zsh/antigen.zsh` (git, command-not-found, completions, autosuggestions, syntax-highlighting last, typewritten theme) + wire it into `~/.zshrc` |
| `install-paneru` | Install Paneru from the `iv-lite/paneru` GitHub releases (newest in list; `PANERU_TAG` pins) into the brew bin dir + write `~/.config/paneru/init.lua` + re-lay its launchd service from the installed binary and refresh the app shim (binaries signed with the persistent `Paneru Local` identity so grants survive updates) |
| `ensure-signing-identity` | Create/reuse the persistent self-signed `Paneru Local` code-signing identity (one-time keychain approval; `PANERU_SIGN_IDENTITY`/`PANERU_SIGN_CERT` override) |
| `repair-paneru` | Self-repair an unhealthy daemon: re-sign (stable identity) → revoke + re-grant → restart → re-check (run by `enable-services` on failed health poll, or by hand; the only revoke path) |
| `install-helpers` | Install the shortcut helpers into `~/.config/mac-scrolling-wm/helpers/` and install the macOS cheat-sheet viewer app (fetches a pre-built release from GitHub at `iv-lite/mac-cheatsheet-viewer`, falls back to a local source build) |
| `grant-permissions` | Grant-if-missing Accessibility via tccutil-rs (user → sudo → manual fallback; never revokes except under `PANERU_GRANT_REVOKE=1` from repair); hands off to the daemon dialog without Full Disk Access |
| `enable-services` | Start Paneru |

### After install

1. **Log out and back in** (Cmd+Shift+Q) — applies the enabled
   separate-Spaces setting.
2. Paneru tiles in an **niri-style sliding strip**; new windows are appended at
   the end of the strip and **never resize existing windows**. Virtual
   workspaces are **dynamic rows** created on demand (and reaped when empty).
3. **Paneru** shows the active virtual workspace in a brief popup on switch.
4. If the Accessibility grant failed, grant it manually:
   System Settings → Privacy & Security → Accessibility (enable the
   installed `paneru` / `paneru-swift` binary or `Paneru.app`). Grants are
   sticky across updates via the stable signing identity — grant once, then
   re-run `./install` freely with no remove/regrant.
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
| `Cmd` + `Alt` + drag across display edge | Hold to arm, cross the edge to move the window to that display live (lands in nearest column; unarmed drags move the column with the pointer and glide home instead of transferring) |
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
  opt out, outer screen edges stay in `padding`. (Implementation: slots
  abut and gaps apply as per-window AX padding, retargeted live on
  reload — same user-visible values.)
- A lone column narrower than the viewport is centered
  (`options.center_single_column = true`); multi-column strips stay
  left-pinned. `auto_center` remains `false`, so focus changes never
  recenter — only the single-column case does.
- Gutter drags scroll the strip 1:1 — press in the padding whitespace
  between windows or the trailing viewport past the last column
  (single-column strips never arm); presses on windows stay fully native
  (text selection, tabs, native drags) and glide home on release. Friction
  lives only on the release glide (pace-sensitive release velocity seeds
  inertia/snap, click jitter absorbed by a dead-zone, scroll-glides never
  transfer displays, hover focus deferred while held), while armed `Cmd+Alt`
  drags move live, landing
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
  distance-proportional duration around the 180ms default (bounded 80–260ms
  against a viewport-scaled travel reference, tunable via
  `options.animation_duration_ms = 180` clamped 0–2000 with
  `options.animation_min_duration_ms = 80` / `options.animation_max_duration_ms = 260`
  bounds); `false` snaps instantly — one switch since fork
  `7496610`, older binaries ignore the new keys and glide on their default);
  virtual-row switches snap (`options.virtual_workspace_animations = false`).
- Session restore remembers each window's display UUID/frame (state v4, active-display
  fallback clamped to the viewport, duplicate titles tie-break by geometry) and prunes
  saved windows whose app never opened at grace expiry
  (`restore.missing_windows = "drop"` — post-crash restarts preserve unlaunched
  windows regardless; state saves every 30s when dirty with a `.bak` fallback).
- AX moves and driving resizes go through a dedicated writer thread
  (`options.ax_writer = true`, window-id drain order, frame-epoch
  convergence with stuck-writer watchdog, supervised workers with sync
  fallback, degrade-to-sync fallback ladder with automatic recovery),
  verify reads go through an off-main pool so slow apps never stall the
  pump, and the pump paces to the display
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
  dimming uses native macOS (`decorations.inactive.dim`). Individual apps
  can override the corner radius with a per-window `border_radius` rule
  (commented example in `config/paneru/init.lua`; older binaries ignore it).
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
the event-tap watchdog (karinushka/paneru#350) is present. The Swift daemon
additionally re-arms a macOS-disabled tap on its own within ~5s (during the
gap native gestures win outright), so a brief dead spell resolves without a
restart. Swipe-gesture note: the tap consumes exactly the configured finger
count (`swipe.gesture.fingers_count = 3` here) — keep macOS Trackpad system
swipes (Mission Control / spaces) on a different count or off, or the native
gesture wins whenever the counts match.

**Paneru runs but doesn't tile after an upgrade.** Upgrades keep the existing
Accessibility grant: the installer signs every binary with the persistent
`Paneru Local` identity (`scripts/ensure-signing-identity`, identifier
`com.github.karinushka.paneru` for Rust / `com.github.iv-lite.paneru-swift`
for Swift), so the TCC row stays valid across
rebuilds. Re-run `./install` — it re-lays the plist from the installed binary
(`paneru uninstall` + `paneru install`, since upstream `install` is write-once)
and grants only when missing — no remove/regrant, no fresh manual grant.
One-time migration from old ad-hoc installs: remove the stale `paneru` /
`paneru-swift` entries with `–` in System Settings → Privacy & Security →
Accessibility, re-run `./install`, then toggle them back on once; all later
updates stay sticky. The upstream `d04db61` Swift rename is the same one-time
shape: delete the stale `com.github.karinushka.paneru.swift` row and toggle
the new `paneru-swift` row on once (the `--swift` install already migrates
the old agent's plist/logs away; Rust is untouched).
If it is still dead, the grant is stale-but-listed: `enable-services`
runs a self-repair on an unhealthy daemon (`scripts/repair-paneru`: re-sign
with the stable identity → revoke + re-grant → restart → re-check, twice,
then one manual-grant pause when interactive; the only path that revokes).
Revoking and granting both go through `tccutil-rs`, which
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
bash scripts/ensure-signing-identity  # one-time stable cert
codesign --force --sign "$(bash scripts/ensure-signing-identity 2>/dev/null)" --identifier com.github.karinushka.paneru "$(command -v paneru)"
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
  line the warp landing up with the desk positions. Diagonally-offset
  ("stairs") pairs with no shared Y band map the cursor's fractional height
  proportionally onto the target instead of sticking at the edge (a large
  configured offset can still push the mapping off-target, in which case the
  clamped landing applies).
- A window can be sent to another display with `Cmd+Ctrl+Shift+→` (follow) or
  `Cmd+Ctrl+Alt+→` (stay), `Cmd+Ctrl+←/→` focuses the other display, and
  `Cmd+Ctrl+↑/↓` warps the mouse there.

## Uninstall

```sh
./uninstall
```

Stops and removes Paneru (release binary, launchd service, app launcher;
plus `paneru-swift`/`pq` and the Swift agent when `--swift` was used),
revokes its Accessibility grant, moves configs (from `~/.config/paneru`,
`~/.config/ghostty`, `~/.config/mac-scrolling-wm`, `~/.config/zsh/antigen.zsh`,
plus `~/.paneru*` and
Paneru's state dir incl. the XDG variant, the Swift live state and
launchd log pair) to `~/.config/backups/uninstall-<timestamp>/`, removes
`~/antigen.zsh`, the Antigen caches and the marked `~/.zshrc` block, removes
the `tccutil-rs` release binary, then asks
you which formulae to **keep** (interactive numbered menu), and restores the
native menu bar.
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