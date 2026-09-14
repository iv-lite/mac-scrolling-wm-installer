# Rift feature request: snap to nearest column and focus it on scroll-gesture release

Paste as a GitHub issue on `acsandmann/rift`. Composes with open PR
[#476](https://github.com/acsandmann/rift/pull/476) (smooth continuous scrolling) and
[#418](https://github.com/acsandmann/rift/pull/418) (neighbor peeks).

**Title:** `feat(scrolling): snap to nearest column and focus it on scroll-gesture release`

## Summary

When a horizontal scroll gesture on a scrolling-layout workspace ends, Rift currently
discards the pending position: `handle_scroll` returns on `touches.len() == 0` after only
resetting the gesture state, so the strip stays wherever the pan left it — often mid-window —
and keyboard focus never follows the swipe.

Request: when a scroll gesture that emitted at least one `ScrollStrip` ends, send one final
`SnapStrip` instead of resetting silently. `snap_to_nearest_column` already pins the strip to
the nearest column boundary **and** returns the landed window as the focus target, so this
single change yields page-flip semantics:

- a swipe never rests mid-window;
- the fully visible window becomes the focused window;
- the final snap animates at the configured `animation_duration`.

## Behavior

- **While the gesture is active**: keep the current pan unchanged (compose with #476 `smooth`
  mode when enabled).
- **On gesture end** (`touches.len() == 0`): if at least one `ScrollStrip` was emitted this
  session, issue one `SnapStrip` to the *nearest* column (round to nearest: a swipe ≥ 0.5 step
  goes to the next window, < 0.5 returns to the current one). Otherwise leave a no-op, exactly
  as today.
- **Partial swipes** below `distance_pct` emit nothing and stay no-ops — no accidental jumping.
- **Overscroll at the boundaries** keeps the existing `workspace_switch_threshold` /
  `propagate_to_workspace_swipe` behavior: if the pan is already at a strip boundary the stored
  overscroll still flows into the workspace swipe as today.
- Keep gesture direction processing, finger-count/cohort selection, vertical tolerance, palm
  filtering, inversion, and `consume` semantics unchanged.

Proposed as an opt-in **`snap_on_release = true`** key under
`[settings.layout.scrolling.gestures]` (default `false`) so existing behavior is preserved and
the change is purely additive.

## Why this shape

The scrolling layout already has the exact mechanism needed: `SyncMessage::SnapStrip` /
`snap_to_nearest_column` computes the target column and stores its window in
`EventResponse.focus_window`, which the reactor already applies. The missing piece is a single
call site on gesture release; there is no new animation system, no inertia, no new dependency.

Inertia remains intentionally out of scope per #476 — this is only about where the strip (and
focus) rests after a deliberate swipe.

## Validation

- `cargo +nightly fmt --all`
- `cargo test --lib`
- `git diff --check`

New tests to mirror #476's suite:

- nearest-column rounding: swipe landing ≥ 0.5 step focuses and pins the next column, < 0.5 the
  current one;
- partial swipe below `distance_pct`: no `ScrollStrip`, no `SnapStrip`, no focus change;
- focus forwarding: the snapped column's window is set as `focus_window` and focused;
- boundary + overscroll: `workspace_switch_threshold`/workspace-swipe propagation unaffected;
- `snap_on_release = false`: today's behavior byte-for-byte.

## Manual testing

With `column_width_ratio = 1` (full-width windows) and a three-finger horizontal gesture in a
scrolling workspace:

- a full swipe settles centered on the next window, which becomes focused;
- a short flick past half a window advances one window; a smaller flick returns to the current;
- swiping up to the strip edge and beyond still flows into the neighboring workspace.