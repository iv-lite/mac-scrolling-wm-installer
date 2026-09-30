# Paneru fork feature floor

Fork v0.1.0 is based on upstream 0.5.1. Details moved out of scripts/install-paneru to keep it focused.

Parity verified against upstream `829b93a` (prev. `7d726d1`): tunable glide
pacing bounds (`animation_min/max_duration_ms`, stock 180/80/260 with a
viewport-scaled travel reference), dead event taps re-arm in ~5s plus
finger-count alignment guidance, `move:` transfer logs and the `stuck:`
retile watchlist with `ax:` lane retirement, full-frame mouse-follow center,
rostered native-fullscreen windows, suppressed fullscreen rings, UUID-stable
display mapping, 120Hz tick, and wall-clock tweens. Before that
(from `7d726d1`): the shipped
`swipe.gesture.direction = "Natural"` is now honored (was parsed but ignored —
`Reversed` mirrors strip travel), focus stranded on hidden windows heals to
the nearest visible neighbor (`focus: healed/cleared` lines, same prefix as
the existing triage grep), fast/diagonal flings warp via edge-crossing eval
(`mouse:` misses gain `cross` coordinates), focused-window frame reads keep
borders on live glass, and steady-state AX reads are halved with per-window
state leaks closed. Before that
(from `d04db61`): the Swift
identity is renamed to `com.github.iv-lite.paneru-swift` (label, signing
identifier, Mach default, log paths — install migrates the previous
`...karinushka.paneru.swift` agent away, Rust untouched; the rename
re-prompts the Accessibility grant once), plus the rest-state `overlap:`
watch with slot verdicts, opt-in `PANERU_PERF=1` slow-tick `perf:` timing,
width-change reveal re-evaluation, hover-echo warp suppression,
padding-aware glass borders, full-point-containment stairs drops,
viewport-sized maximized model, and SLS double-vote hardening. Before that
(from `4e0fc64`): focus
arrivals always reveal fully (`203b295` — the `window_hidden_ratio`
threshold now governs unfocused windows only, so partially-hidden focus
reveals too), plus the 5s audit drift re-home with `drift:` diagnostics
and `focus:` reveal/center logs (`4e0fc64`). Before that (from `0d3c2ab`): the Swift
Mach default is now the suffixed label (our `PANERU_MACH_SERVICE` pin is
belt-and-braces for new binaries, still load-bearing for pre-fix ones),
plus the Rust→Swift cold-flip cutover (`paneru handoff` →
`paneru-swift --flip-from`, see README cutover section). Earlier delta
(from `6688825`): `pq subscribe` / `pq state-remove` parity commands and
the Swift 6 language floor (Xcode 16+). Before that (from `e33c52c`):
behavior fixes plus the `--shadow` observer flag and the now-live
per-window `border_radius` rule.

```sh
# ─────────────────────────────────────────────────────────────
# Version floor: the fork's v0.1.0 is based on upstream 0.5.1, so the
# event-tap watchdog (karinushka/paneru#350) is present, plus native
# window/mouse previousdisplay commands. The Cmd+Alt cross-display drag
# (mouse_drag_display_modifier) needs fork ≥ v0.2.2.
# The shipped config also sets options.default_ratio,
# options.center_single_column (need a fork build containing d8b5677),
# and gaps = { horizontal = 8,
# vertical = 8 } (needs 43d3644; per-window horizontal/vertical_padding
# wins, including 0 to opt out),
# options.ax_writer
# (default-on since d1fb7dd; the experimental_ax_writer spelling still works
# as a deprecated alias; window-id drain order since c148819, frame epochs +
# stuck-writer watchdog since 113bd4e — worker supervision was reverted in
# f5c1535, then restored in d67df09 with sync fallback; verify reads moved
# to an off-main pool and driving resizes joined the writer lane in
# d67df09) and options.maximize_tiled_windows
# (needs e25b6f9). options.animations = true (ease-out-cubic fast attack
# with decelerating landing, lockstep bursts with synced pacing via
# join_duration, first-tick kick, distance-proportional duration around
# the 180ms default bounded 80–260ms against a viewport-scaled travel
# reference; needs 7496610 — the old
# animation_speed knob is gone) plus options.animation_duration_ms = 180
# (clamped 0–2000; animations = false still snaps; pre-knob binaries
# silently ignore it and glide on their own default; ease-out-cubic
# since 0a967df, join_duration pacing since 684b931, 250ms default +
# duration knob since 21ed647, 180ms default + min/max bounds since
# 4c29f48) plus options.animation_min_duration_ms = 80 (clamped 0–1000)
# and options.animation_max_duration_ms = 260 (clamped 0–2000, floored at
# the min; older binaries silently ignore both), plus
# options.virtual_workspace_animations =
# false (no config needed on older binaries — false is the default).
# Unarmed window drags move the grabbed column with the pointer and glide
# home on release; only armed (mouse_drag_display_modifier) drags reorder
# or transfer across displays. The removed keys left_drag_scrolls_strip
# (gutter-scroll) and ffm_drag_suppress_ratio/ms (hover-focus sleep) are
# NOT set here — current builds ignore them, so old configs still parse.
# Held drags fold each HID burst into one drive per frame and track 1:1 with
# friction only on the release glide (b4852e0 — the drag_friction_* keys are
# removed upstream and no longer set here, but old configs still parse;
# per-frame folding since 6793ee8; pace-sensitive release velocity,
# click dead-zone, scroll-detach guard and held hover-defer since 0a967df;
# reveal skipped on pure clicks and size frozen on click-focus since
# 684b931). Vsync retrace pacing is always-on where
# supported since e25b6f9 (the experimental_vsync flag is removed, no longer
# set here). restore.missing_windows = "drop" (needs 42add2b; older binaries
# reject the unknown value, unlike unknown keys) is also set. 416e418
# (same-tick drags, most-visible reveal), 8bda31b (pump focus, overlay gate,
# chase-ahead borders), c148819 (rigid strip riding), 8ed9e3d (driven
# moves cancel live glides) and dd0f628 (single-flight keyboard focus:
# strip-only centering, echo stand-down while the strip is mid-flight)
# need no config. e803dd5 (keyboard focus recenters the cursor even when it
# is already inside the window; clicks own their cursor and mid-drag focus
# changes never warp) and 314ede8 (strips fill the viewport on focus, move
# and drag so they never rest next to whitespace) need no config either.
# 088fa45 (already-placed centering skips redundant markers, pure clicks
# issue no reorder/homing/reshuffle, holders carry no timeout fuse) needs
# no config either. 3c053fb (optional Swift overlay backend via dlopen
# strangler, Rust fallback; non-default cargo feature, runtime opt-in) and
# 6793ee8 (snappy easing, proportional glides, folded drag input) need no
# config either. 837a6e4 (writer-degraded fallback ladder with fast resize
# path and stall recovery) needs no config either. 30ff4d8 (owner-viewport
# focus centering, warp-rebased drag anchor, deferred expose on transient
# frames, per-frame fold bound) needs no config either. 04f9469/a9a2f83
# (viewport-clamped tiles, new windows glide into view, click-focus
# clamp-down, state v4 display UUIDs with active-display fallback) need no
# config. 0a967df (ease-out-cubic, release-only pace friction, scroll
# detach guard, close-up on removal) needs no config. 5bd61ae (app
# termination cascades to windows so borders clear and strips re-tile)
# needs no config. 684b931 (drift-loop kill, glide join pacing, frozen
# click size, layout-gated borders) needs no config. 43d3644 (global gaps,
# § above) is the only new table. d67df09 (no-crash Single/unwrap
# removal, supervised workers with sync fallback, AX reads off-main, writer
# resize lane, crash-flag + .bak + 30s saves, geometry tie-break, Lua
# 10s-timeout with no-script fallback) needs no config.
# Service note: upstream reverted the canonical-path convergence (0a29efc) —
# `paneru install` is write-once (skips when the plist exists) and the plist
# pins the invoking binary's path, so this script re-lays the plist from the
# installed binary below. Grants stay sticky across byte changes via the
# persistent signing identity (stable identifier+certificate DR).
# All still unreleased with no tag yet; --prefer-local-builds from a current
# sibling checkout has them.
# Older binaries silently ignore unknown keys/tables: new windows keep their
# OS size, a lone column left-pins, AX work
# stays on the main thread, tiled windows fill their slot,
# gaps fall back to
# zero (per-rule padding only), glides run the built-in length
# and moves glide on
# the built-in default. (restore.missing_windows = "drop" is the
# exception: pin "ignore" if you run an older Paneru.)
# ─────────────────────────────────────────────────────────────
```
