-- lib/displays.lua — display navigation: focus/move to the previous/next
-- display, including empty displays and 3+ display setups.
--
-- Cmd+Ctrl+←/→ shift focus to another display without moving the window.
-- Cmd+Ctrl+Shift+←/→ moves the focused window to the previous/next display
-- and follows it.
--
-- Focus is resolved in-process and only the warp itself is delegated to the
-- compiled ~/.config/mac-scrolling-wm/helpers/warp-pointer helper (see that
-- file): the target display comes from the geometric ordering + the mouse's
-- display, and the target point from the live state snapshot (the focused
-- window's center when it is on the target display, else the first window
-- there, else the display center) — no subprocess, where the old helper paid
-- a `paneru query on-screen` spawn + JSON parse on every keypress.
-- focus_display below is therefore target math plus one thin helper exec,
-- guarded by MOVE_BUSY.
--
-- Move is also fully delegated to compiled helpers — both the 2-display
-- path (paneru's own `window nextdisplay` via CLI, confirmed by the
-- wait-display helper) and the 3+ display path (move-display: AX teleport,
-- warp + mouseMoved, blocking settle with adoption confirm). CLI commands
-- are separate Mach port messages that the daemon processes independently;
-- the confirms must span real wall-clock time, so they live in helpers with
-- real sleeps: an in-dispatch `query_json` busy poll exhausts in ~0ms before
-- the daemon's frame runs and can never observe another in-dispatch command,
-- so sequencing across commands needs real ordering.
--
-- Focus assignment follows the runtime both models agree on: the installed
-- paneru 0.5.1 documents pure StackSet handlers (`return
-- ws:focus(ws:east(ws:focused()))` appears verbatim in the binary), where
-- only the returned set commits — bare `ws:focus()` calls without a return
-- are silently discarded. So this file both queues the focus (harmless
-- anywhere) and RETURNS the focused set from successful moves. The
-- source-side centering likewise goes through an immediately-applied CLI
-- (`send-cmd window focus east|west`, which also scrolls via auto_center)
-- rather than a transient in-dispatch focus that a pure runtime would drop.
--
-- The move preserves the window's column-width ratio (tiled) or pixel size
-- (floating, scaled down only on overflow) — never a forced full-width end
-- state: the 3+ helper settles via fullwidth for reliable adoption, then Lua
-- re-pins the source ratio with ws:width on commit. Disposition is preserved
-- too: tiled comes back tiled, deliberately-floating stays floating.
--
-- While a move is mid-flight (3+ displays only — the 2-display path never
-- floats) the focused window is *floating*. MOVE_BUSY blocks a second
-- dispatch from starting while one is already in flight, so rapid re-presses
-- can't race each other or compute targets off a stale "current" display.

local log = require("lib.log").log
local query = require("lib.query")
local query_active_safe = query.active
local query_state_safe = query.state
local find_window = query.find_window

-- paneru.exec either returns a result table ({code, stdout, stderr}) or
-- raises with any error value — including userdata. Never index a result
-- blindly: that turns a failed exec into a fatal dispatch error (seen live
-- when a raised focus CLI crashed the whole move on `cres.stderr`).
local function exec_failed(ok, res)
  if not ok then return true end
  if type(res) ~= "table" then return true end
  return res.code ~= 0
end

-- Safe ": detail" suffix for failure logs: the command's stderr when it ran
-- and failed, or the raised error when the spawn itself failed (e.g. the
-- binary isn't on the daemon's minimal launchd PATH); "" when unavailable.
local function exec_detail(ok, res)
  if ok and type(res) == "table" and type(res.stderr) == "string" and res.stderr ~= "" then
    return ": " .. res.stderr
  end
  if not ok and res ~= nil then
    return ": " .. tostring(res)
  end
  return ""
end

-- Safe stdout string from an exec result; "" when unavailable.
local function exec_stdout(res)
  if type(res) == "table" and type(res.stdout) == "string" then
    return res.stdout
  end
  return ""
end

-- Helpers (see helpers/, all compiled by scripts/install-helpers):
--   warp-pointer     — warp-only: pointer to x y + mouseMoved; the target is resolved in-process
--   move-display     — teleport via AX at near-final geometry, warp + mouseMoved, settle via CLI
--   display-geometry — real CG frames of every online display, empties included
--   mouse-display    — which display id currently has the pointer
--   wait-rect        — block until a window center is inside a rect (source repair)
--   wait-display     — block until a window reports the target display (2-display confirm)
local HELPERS_DIR = os.getenv("HOME") .. "/.config/mac-scrolling-wm/helpers/"
local WARP_HELPER = HELPERS_DIR .. "warp-pointer"
local WAIT_HELPER = HELPERS_DIR .. "wait-rect"
local WAIT_DISPLAY_HELPER = HELPERS_DIR .. "wait-display"
local MOVE_HELPER = HELPERS_DIR .. "move-display"
local GEOM_HELPER = HELPERS_DIR .. "display-geometry"
local MOUSE_HELPER = HELPERS_DIR .. "mouse-display"

-- Absolute paneru CLI path: the daemon runs under launchd with a minimal
-- PATH (no /opt/homebrew/bin), so spawning a bare "paneru" from Lua fails
-- (seen live: every 2-display move failed at `window nextdisplay` with no
-- stderr detail). Same probe order as the move-display helper's PANERU_BIN.
local PANERU_BIN = (function()
  local function exists(path)
    local ok, f = pcall(io.open, path, "rb")
    if ok and f then f:close(); return true end
    return false
  end
  for _, candidate in ipairs({ "/opt/homebrew/bin/paneru", "/usr/local/bin/paneru" }) do
    if exists(candidate) then return candidate end
  end
  return "paneru"
end)()

-- Which display id currently has the mouse pointer, or nil if the helper
-- failed. A plain synchronous `paneru.exec` call — no in-process query API.
local function current_display_id()
  local ok, res = pcall(paneru.exec, MOUSE_HELPER, {})
  if exec_failed(ok, res) then return nil end
  return tonumber((exec_stdout(res)):match("%d+"))
end

-- ─── Display geometry cache ───────────────────────────────────────────────
-- Paneru's Lua `display_of` resolves a display by *membership*, so a monitor
-- with no windows is invisible to it and navigation cannot reach it. The real
-- display list (all online displays, cached here and refreshed on display
-- events / on a detected geometry mismatch) is what ordering and targeting use.
local DISPLAYS = {}      -- display_id -> { id, x, y, width, height }
local ORDERED_IDS = {}   -- display ids in geometric order (y, then x, ascending)
local GEOM_STALE = true

local function sort_ordered_ids()
  table.sort(ORDERED_IDS, function(a, b)
    if DISPLAYS[a].y ~= DISPLAYS[b].y then return DISPLAYS[a].y < DISPLAYS[b].y end
    return DISPLAYS[a].x < DISPLAYS[b].x
  end)
end

local function refresh_geometry()
  local ok, res = pcall(paneru.exec, GEOM_HELPER, {})
  if exec_failed(ok, res) then return false end
  local t, ids = {}, {}
  for line in (exec_stdout(res)):gmatch("[^\r\n]+") do
    local id, x, y, w, h = line:match("(%d+)%s+(%-?%d+)%s+(%-?%d+)%s+(%d+)%s+(%d+)")
    if id then
      id, x, y, w, h = tonumber(id), tonumber(x), tonumber(y), tonumber(w), tonumber(h)
      t[id] = { id = id, x = x, y = y, width = w, height = h }
      ids[#ids + 1] = id
    end
  end
  if #ids == 0 then return false end
  DISPLAYS, ORDERED_IDS, GEOM_STALE = t, ids, false
  sort_ordered_ids()
  return true
end

-- Re-read geometry when the cached set went stale, or when any window sits on
-- a display we know nothing about (a display appeared outside an event).
local function ensure_geometry(ws)
  if GEOM_STALE then
    if refresh_geometry() then return end
  else
    for _, w in ipairs(ws:windows()) do
      local d = ws:display_of(w.id)
      if d and not DISPLAYS[d.id] then
        GEOM_STALE = true
        refresh_geometry()
        return
      end
    end
  end
end

-- Geometric display ordering (all physical displays, empty ones included).
local function ordered_displays(ws)
  ensure_geometry(ws)
  if #ORDERED_IDS >= 2 then return ORDERED_IDS end
  -- geometry helper unavailable: fall back to window-derived ordering
  local displays = {}
  for _, w in ipairs(ws:windows()) do
    local d = ws:display_of(w.id)
    if d and not displays[d.id] then
      displays[d.id] = { id = d.id, x = d.x, y = d.y }
    end
  end
  local ids = {}
  for id in pairs(displays) do ids[#ids + 1] = id end
  table.sort(ids, function(a, b)
    if displays[a].y ~= displays[b].y then return displays[a].y < displays[b].y end
    return displays[a].x < displays[b].x
  end)
  return ids
end

-- ─── Move busy-guard ───────────────────────────────────────────────────────
-- `ws:window(id).floating` is a snapshot taken once at the start of *this*
-- dispatch — it never reflects a `window manage` toggle a still-in-flight
-- move is in the middle of applying, only what was true before that move's
-- own first await. Two rapid Cmd+Ctrl+Shift+arrow presses could each pass
-- that stale check, both start floating/teleporting the same window to
-- different displays (a visible jiggle: one teleport lands, then the other
-- immediately overwrites it), and their two uncoordinated `window manage`
-- calls (`window manage` toggles tiled/floating, not idempotent) could
-- leave the window stuck floating forever, which then made every later
-- focus/move look "broken" since the stale-floating check never clears on
-- its own. MOVE_BUSY is a plain Lua variable instead: set as the very first
-- statement, before any `paneru.exec`/`query_*` await, so a second dispatch
-- that starts while the first is still in flight sees it immediately — no
-- yield happens between the check and the set.
local MOVE_BUSY = false

local function display_frame(ws, display_id)
  ensure_geometry(ws)
  local t = DISPLAYS[display_id]
  if t then return t end
  for _, w in ipairs(ws:windows()) do
    local d = ws:display_of(w.id)
    if d and d.id == display_id then return d end
  end
end

-- A window frame's center as {x, y}, or nil when the frame is missing or
-- malformed. State frames are plain Lua numbers (no Swift-side casts).
local function frame_center(frame)
  if type(frame) ~= "table" then return nil end
  local x, y, w, h = frame.x, frame.y, frame.width, frame.height
  if type(x) ~= "number" or type(y) ~= "number"
      or type(w) ~= "number" or type(h) ~= "number" then
    return nil
  end
  return { x = x + w / 2, y = y + h / 2 }
end

-- Locate the current display in the geometric ordering, refreshing the
-- geometry cache once when it isn't there. `cur_id` is the caller's best
-- guess (focused window for moves, pointer for focus); when even a refresh
-- can't place it, one pointer lookup is tried as a last resort before
-- giving up — so the mouse spawn pays only on this rare miss path, while
-- empty targets stay reachable through the full ordering. Returns
-- ids, idx, resolved id (all nil on failure).
local function current_index(kind, ws, ids, cur_id)
  if not cur_id then
    log(kind .. ": current display unknown")
    return nil, nil, nil
  end
  if not DISPLAYS[cur_id] then
    log(kind .. ": cur_id " .. cur_id .. " not in geometry cache, refreshing")
    GEOM_STALE = true
    if refresh_geometry() then ids = ORDERED_IDS end
  end
  if not DISPLAYS[cur_id] then
    local mouse_id = current_display_id()
    if mouse_id ~= nil and mouse_id ~= cur_id and DISPLAYS[mouse_id] then
      log(kind .. ": falling back to mouse display " .. mouse_id)
      cur_id = mouse_id
    end
  end
  for i, id in ipairs(ids) do
    if id == cur_id then return ids, i, cur_id end
  end
  log(kind .. ": cur_id " .. cur_id .. " not in ids [" .. table.concat(ids, ",") .. "] even after refresh")
  return nil, nil, nil
end

-- Where to warp for `target_id`: the focused window's center when it is on
-- the target display, else the first window there, else the display center.
-- Resolved in-process from the state snapshot — no subprocess. Candidates
-- must be visible and geometrically on the target display: state also lists
-- windows on hidden workspaces (and strip positions past the viewport)
-- whose display_id matches but whose frames sit nowhere near the display —
-- warping to one of those misses every monitor.
local function focus_point(ws, target, target_id)
  local t = display_frame(ws, target_id)
  local function contains(p)
    return p ~= nil and t ~= nil
      and type(t.x) == "number" and type(t.y) == "number"
      and type(t.width) == "number" and type(t.height) == "number"
      and p.x >= t.x and p.x < t.x + t.width
      and p.y >= t.y and p.y < t.y + t.height
  end
  local state = query_state_safe()
  if state then
    local first = nil
    for _, row in ipairs(state.virtual_workspaces or {}) do
      for _, w in ipairs(row.windows or {}) do
        if w.display_id == target_id and w.visible ~= false then
          local p = frame_center(w.frame)
          if contains(p) then
            if w.focused then return p end
            if first == nil then first = p end
          end
        end
      end
    end
    if first ~= nil then return first end
  end
  if t and type(t.x) == "number" and type(t.y) == "number" then
    local w, h = t.width or 0, t.height or 0
    if type(w) ~= "number" then w = 0 end
    if type(h) ~= "number" then h = 0 end
    return { x = t.x + w / 2, y = t.y + h / 2 }
  end
  log("focus " .. target .. ": no geometry for target display " .. target_id)
  return nil
end

-- Focus is resolved in-process (target display + point, see above) and the
-- compiled warp-pointer helper only performs the warp: pointer there plus
-- the synthetic mouseMoved that makes focus_follows_mouse pick it up. The
-- only thing worth skipping in-process is a move in flight (MOVE_BUSY).
local function focus_display(ws, target)
  if MOVE_BUSY then
    log("focus " .. target .. ": busy (a move is in flight)")
    return
  end
  local ids = ordered_displays(ws)
  if #ids < 2 then
    log("focus " .. target .. ": fewer than 2 displays (" .. #ids .. ")")
    return
  end
  local _, idx = current_index("focus " .. target, ws, ids, current_display_id())
  if not idx then return end
  local n = #ids
  local step = (target == "previous") and (n - 1) or 1
  local target_id = ids[((idx - 1 + step) % n) + 1]
  local point = focus_point(ws, target, target_id)
  if not point then return end
  log(string.format("focus %s: -> display %d (%.0f, %.0f)",
    target, target_id, point.x, point.y))
  local ok, res = pcall(paneru.exec, WARP_HELPER, {
    tostring(math.floor(point.x)), tostring(math.floor(point.y)),
  })
  if exec_failed(ok, res) then
    log("focus " .. target .. ": warp-pointer helper failed" .. exec_detail(ok, res))
  end
end

-- Neighbor to center on the source display, as side + window id: toward
-- the target display (east target → east neighbor), falling back to the
-- other side. Resolved in layers: true column structure first
-- (ws:columns + ws:column_of — handles stacks correctly, and the focused
-- window must be a member of its own column entry or the indexing is
-- distrusted), then flat state-row order (next else previous per side),
-- then nil + reason (skips are always logged by the caller — never silent).
local function source_neighbor_side(ws, focused, cur_id, target_id)
  local cur = DISPLAYS[cur_id]
  local tgt = DISPLAYS[target_id]
  local toward, away = "east", "west"
  if tgt and cur and type(tgt.x) == "number" and type(cur.x) == "number" then
    local tcx = tgt.x + (type(tgt.width) == "number" and tgt.width / 2 or 0)
    local ccx = cur.x + (type(cur.width) == "number" and cur.width / 2 or 0)
    if tcx < ccx then toward, away = "west", "east" end
  end
  local saw_structure = false
  local function via_columns(side)
    local ok, col_idx = pcall(function() return ws:column_of(focused) end)
    if not ok then return nil end
    saw_structure = true
    local ok2, cols = pcall(function() return ws:columns(ws:workspace_of(focused)) end)
    if not ok2 or type(col_idx) ~= "number" or type(cols) ~= "table" then return nil end
    local here = cols[col_idx]
    if type(here) ~= "table" then return nil end
    local found = false
    for _, id in ipairs(here) do
      if id == focused then found = true break end
    end
    if not found then return nil end
    local neighbor = cols[col_idx + ((side == "east") and 1 or -1)]
    if type(neighbor) ~= "table" then return nil end
    local id = neighbor[1]
    if id == nil or id == focused then return nil end
    return side, id
  end
  local function via_order(side)
    local state = query_state_safe()
    if not state then return nil end
    local order = {}
    for _, row in ipairs(state.virtual_workspaces or {}) do
      for _, w in ipairs(row.windows or {}) do
        if w.display_id == cur_id then order[#order + 1] = w.window_id end
      end
    end
    local pos
    for i, id in ipairs(order) do
      if id == focused then pos = i break end
    end
    if not pos then return nil end
    saw_structure = true
    local id = (side == "east") and order[pos + 1] or order[pos - 1]
    if id == nil then return nil end
    return side, id
  end
  for _, side in ipairs({ toward, away }) do
    local s, id = via_columns(side)
    if s ~= nil then return s, id, nil end
  end
  for _, side in ipairs({ toward, away }) do
    local s, id = via_order(side)
    if s ~= nil then return s, id, nil end
  end
  if saw_structure then return nil, nil, "single column" end
  return nil, nil, "no column data"
end

-- Warp exactly onto the moved window's live center. Used by the 2-display
-- path only — on 3+ the move-display helper re-warps post-settle itself, so
-- a second helper spawn here would just be latency.
-- Final focus is handled by the caller returning ws:focus (see below).
-- This runs inside a move dispatch (MOVE_BUSY is set), never via
-- focus_display(), which refuses to run while a move is in flight.
-- Repair the source viewport after a native 2-display move: the daemon owns
-- both strips but leaves the source scrolled stale. Warp onto the neighbor
-- so focus_follows_mouse + auto_center scroll it into view (no ws: use —
-- a CLI focus would resolve on the wrong display now that focus already
-- left, and a transient id-focus can't commit under either runtime model),
-- prove it with wait-rect, and let the caller warp back. wait-rect needs no
-- Accessibility grant. Skipped for floating moves, single-column sources,
-- and already-consistent viewports — and never fails the move.
-- Returns true when the caller should warp back to the moved window (repair
-- unneeded or verified), false when the repair wait failed — warping back
-- then would interrupt the still-running scroll mid-flight (jiggle).
local function repair_source_viewport(ws, focused, target, cur_id, target_id, was_floating)
  if was_floating then return true end
  local t = DISPLAYS[cur_id]
  if t == nil or type(t.x) ~= "number" or type(t.y) ~= "number"
      or type(t.width) ~= "number" or type(t.height) ~= "number" then
    return true
  end
  local side, nid = source_neighbor_side(ws, focused, cur_id, target_id)
  if side == nil or type(nid) ~= "number" then return true end
  local w = find_window(query_state_safe(), nid)
  if w == nil or w.display_id ~= cur_id then return true end
  local p = frame_center(w.frame)
  if p == nil then return true end
  local function inside(pt)
    return pt.x >= t.x and pt.x < t.x + t.width
      and pt.y >= t.y and pt.y < t.y + t.height
  end
  if inside(p) then
    log("move " .. target .. ": source neighbor already in viewport, skipping repair")
    return true
  end
  pcall(paneru.exec, WARP_HELPER, {
    tostring(math.floor(p.x)), tostring(math.floor(p.y)),
  })
  local wok, wres = pcall(paneru.exec, WAIT_HELPER, {
    tostring(nid), tostring(math.floor(t.x)), tostring(math.floor(t.y)),
    tostring(math.floor(t.width)), tostring(math.floor(t.height)),
  })
  local line = ""
  if type(wres) == "table" and type(wres.stdout) == "string" then
    line = wres.stdout:gsub("^%s+", ""):gsub("%s+$", "")
  end
  if not exec_failed(wok, wres) then
    log("move " .. target .. ": source viewport repaired (" .. line .. ")")
    return true
  else
    log("move " .. target .. ": source viewport repair failed" .. exec_detail(wok, wres) .. " (" .. line .. ")")
    return false
  end
end

-- Warp-only: pointer onto the moved window's live center so
-- focus_follows_mouse lands on it (no ws: use — the single return-commit
-- below owns focus; a second queued focus here would double-trigger the
-- auto_center scroll). Used by the 2-display path only — on 3+ the
-- move-display helper re-warps post-settle itself, so a second helper spawn
-- here would just be latency. This runs inside a move dispatch (MOVE_BUSY is
-- set), never via focus_display(), which refuses to run while a move is in
-- flight. The caller gates this on the repair outcome: on a failed repair
-- the source scroll is still running, and warping back now would cut it off
-- mid-flight (visible jiggle) — the pointer stays where the scroll settles.
local function warp_to_moved(ws, focused, target)
  local w = find_window(query_state_safe(), focused)
  local p = w and frame_center(w.frame) or nil
  if p then
    pcall(paneru.exec, WARP_HELPER, {
      tostring(math.floor(p.x)), tostring(math.floor(p.y)),
    })
  else
    log("move " .. target .. ": no live frame for window " .. tostring(focused) .. ", skipping warp")
  end
end

local function move_to_display(ws, target)
  if MOVE_BUSY then
    log("move " .. target .. ": busy (another move already in flight)")
    return
  end
  MOVE_BUSY = true
  -- Set on the success paths below; when true the handler returns a focused
  -- set so pure runtimes commit the focus (see header).
  -- restore_ratio carries the source column ratio (tiled 3+ path only) to the
  -- return-commit below, where ws:width re-pins it after the helper's
  -- fullwidth-for-adoption settle.
  local moved_ok = false
  local focused_id = nil
  local restore_ratio = nil
  local ok, err = pcall(function()
    local focused = ws:focused()
    if not focused then
      log("move " .. target .. ": no focused window")
      return
    end
    focused_id = focused
    -- The window's disposition right now, before anything below touches
    -- it — this move must restore exactly this afterward, never force it
    -- tiled just because it changed displays.
    local w0 = find_window(query_state_safe(), focused)
    local was_floating = w0 ~= nil and w0.floating
    local ids = ordered_displays(ws)
    if #ids < 2 then
      log("move " .. target .. ": fewer than 2 displays (" .. #ids .. ")")
      return
    end
    -- Anchor moves on the focused window's display (in-process, no spawn):
    -- the acted-on window is what "current" should mean. The pointer lookup
    -- stays as the last resort inside current_index (miss path only).
    local cur_guess = nil
    if w0 ~= nil and type(w0.display_id) == "number" then
      cur_guess = w0.display_id
    end
    local ids2, idx, cur_id = current_index("move " .. target, ws, ids, cur_guess)
    if not idx then return end
    ids = ids2
    local anchor = (cur_guess ~= nil and cur_id == cur_guess) and "window" or "mouse"
    local n = #ids
    local step = (target == "previous") and (n - 1) or 1
    local target_id = ids[((idx - 1 + step) % n) + 1]
    log(string.format("move %s: cur=%d(%s) idx=%d/%d ids=[%s] -> target=%d",
      target, cur_id, anchor, idx, n, table.concat(ids, ","), target_id))
    if target_id == cur_id then
      log("move " .. target .. ": target == current, nothing to do")
      return
    end
    -- Source column ratio for the tiled 3+ restore below (the 2-display path
    -- is native and preserves it already). Paneru width ratios are fractions
    -- of screen width (preset_column_widths), so the full display width is
    -- the right denominator — no padding/border math needed.
    local src_ratio = nil
    if not was_floating and w0 ~= nil and type(w0.frame) == "table"
        and type(w0.frame.width) == "number" then
      local src = DISPLAYS[cur_id]
      if src ~= nil and type(src.width) == "number" and src.width > 0 then
        local r = w0.frame.width / src.width
        if r >= 0.2 and r <= 1.0 then
          src_ratio = r
        elseif r > 1.0 then
          src_ratio = 1.0
        end
      end
    end
    if src_ratio ~= nil then
      log(string.format("move %s: source ratio %.3f", target, src_ratio))
    end
    if n == 2 then
      -- 2-display path: `paneru window nextdisplay` via CLI, which applies
      -- as its own Mach message; the confirm below must span real wall-clock
      -- time. An in-dispatch query_json busy poll cannot do that — it
      -- exhausts in ~0ms before the daemon's frame runs (seen live: 100%
      -- "timed out in 50 ticks" with moves landing right after). One
      -- blocking wait-display spawn both yields the dispatch and waits.
      local exec_ok, res = pcall(paneru.exec, PANERU_BIN, { "send-cmd", "window", "nextdisplay" })
      if exec_failed(exec_ok, res) then
        log("move " .. target .. ": nextdisplay CLI failed" .. exec_detail(exec_ok, res))
        paneru.flash("move display: nextdisplay failed", 3.0)
        return
      end
      local wok, wres = pcall(paneru.exec, WAIT_DISPLAY_HELPER, {
        tostring(focused), tostring(target_id),
      })
      local wline = ""
      if type(wres) == "table" and type(wres.stdout) == "string" then
        wline = wres.stdout:gsub("^%s+", ""):gsub("%s+$", "")
      end
      local settled = not exec_failed(wok, wres)
      log(string.format("move %s: adoption %s (%s)",
        target, settled and "settled" or "timed out", wline))
      if not settled then
        log("move " .. target .. ": window " .. focused .. " never reported display " .. target_id)
        paneru.flash("move display: failed to settle on target display", 3.0)
      else
        if repair_source_viewport(ws, focused, target, cur_id, target_id, was_floating) then
          warp_to_moved(ws, focused, target)
        else
          log("move " .. target .. ": skipping warp-back after failed repair")
        end
        moved_ok = true
      end
      return
    end
    -- 3+ display path: the move-display helper owns the whole move (AX
    -- teleport, warp + mouseMoved, blocking settle with adoption confirm,
    -- source-neighbor centering with verify, live re-warp). Lua checks the
    -- exit code — the helper only reports success once the window is
    -- adopted — then restores focus to the moved window.
    local t = display_frame(ws, target_id)
    if not t then
      log("move " .. target .. ": no geometry for target display " .. target_id)
      paneru.flash("move display: no geometry for target display", 3.0)
      return
    end
    -- Side + id of the neighbor to center on the source display (toward
    -- the target, else the other side). Skipped for floating moves (no
    -- strip gap) and single-column sources: "none"/"0" tells the helper
    -- there is nothing to center.
    local side, neighbor_id = "none", "0"
    if not was_floating then
      local s, id, reason = source_neighbor_side(ws, focused, cur_id, target_id)
      -- Number check: a non-numeric id would fail the helper's strict
      -- parse and fail the whole move — centering must never do that.
      if s ~= nil and type(id) == "number" then
        side, neighbor_id = s, tostring(id)
      else
        log("move " .. target .. ": no source neighbor to center (" .. tostring(reason) .. ")")
      end
    end
    local exec_ok, res = pcall(paneru.exec, MOVE_HELPER, {
      tostring(focused), tostring(math.floor(t.x)), tostring(math.floor(t.y)),
      tostring(math.floor(t.width)), tostring(math.floor(t.height)),
      was_floating and "1" or "0",
      tostring(target_id),
      side, neighbor_id,
    })
    if exec_failed(exec_ok, res) then
      log("move " .. target .. ": move-display failed for window " .. focused ..
        " to display " .. target_id .. exec_detail(exec_ok, res))
      paneru.flash("move display: move failed", 3.0)
      return
    end
    moved_ok = true
    -- Pin for the return-commit below: the helper settles via fullwidth for
    -- reliable adoption, then this restores the source column ratio (tiled
    -- only; floating keeps its teleported pixels, so src_ratio is nil there).
    restore_ratio = src_ratio
    -- Surface the helper's outcome lines (timing + centering audit) in one
    -- log line — without this only failures were ever visible.
    local notes = {}
    if type(res) == "table" and type(res.stderr) == "string" then
      for _, pat in ipairs({
        "elapsed=%d+ms",
        "centered source [^%s]+ neighbor %d+ at [^%s]+",
        "source neighbor %d+ already in viewport, skipping centering",
        "centering skipped: [^\n]*",
        "source viewport never centered neighbor %d+[^\n]*",
        "centering verify [^\n]*",
        "source focus [^%s]+ failed",
      }) do
        local m = res.stderr:match(pat)
        if m then notes[#notes + 1] = m end
      end
    end
    local suffix = ""
    if #notes > 0 then suffix = " (" .. table.concat(notes, "; ") .. ")" end
    log("move " .. target .. ": window " .. focused .. " moved to display " .. target_id .. suffix)
  end)
  MOVE_BUSY = false
  if not ok then
    log("move " .. target .. ": internal error: " .. tostring(err))
    return nil
  end
  -- Commit the focus for pure runtimes (their docs: handlers return the
  -- transformed set; bare calls commit nothing). Tiled 3+ moves also re-pin
  -- the source column ratio here: the helper settles via fullwidth for
  -- reliable adoption, and ws:width restores ratio afterward (any ratio ≤1.0
  -- fits by definition, so the restore can't re-break adoption). A no-op
  -- queue entry on outbox runtimes, where the warp_to_moved call above
  -- already queued focus.
  if moved_ok and focused_id then
    local fok, res = pcall(function()
      local nws = ws
      if restore_ratio ~= nil then
        nws = nws:width(focused_id, restore_ratio)
      end
      return nws:focus(focused_id)
    end)
    if fok then return res end
    log("move " .. target .. ": return-focus failed: " .. tostring(res))
  end
  return nil
end

-- Any display event invalidates the geometry cache (re-read on next use).
for _, evt in ipairs({ "display_added", "display_removed", "display_moved",
                        "display_resized", "display_configured", "display_changed" }) do
  paneru.on(evt, function() GEOM_STALE = true end)
end

return {
  focus = focus_display,
  move = move_to_display,
}
