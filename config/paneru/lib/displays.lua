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
-- path (paneru's own `window nextdisplay` via CLI) and the 3+ display
-- path (move-display: AX teleport, warp + mouseMoved, blocking settle with
-- adoption confirm). CLI commands are separate Mach port messages that the
-- daemon processes independently; by the time the next CLI invocation
-- (exec or query) arrives, the previous command has been applied. A short
-- poll with retries covers the edge case where the daemon's frame hasn't
-- run yet — but no in-dispatch `query_json` poll can observe another
-- in-dispatch command, so sequencing across commands needs real ordering.
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
-- The move never resizes or maximizes the window — it keeps whatever size
-- it had before, on either display — and never changes its tiled/floating
-- disposition either: a window that was tiled comes back tiled; a window
-- the user had deliberately left floating (a scratchpad, a picture-in-
-- picture-style utility window) comes back floating.
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

-- Safe ": stderr" suffix for failure logs; "" when unavailable.
local function exec_detail(res)
  if type(res) == "table" and type(res.stderr) == "string" and res.stderr ~= "" then
    return ": " .. res.stderr
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
local HELPERS_DIR = os.getenv("HOME") .. "/.config/mac-scrolling-wm/helpers/"
local WARP_HELPER = HELPERS_DIR .. "warp-pointer"
local MOVE_HELPER = HELPERS_DIR .. "move-display"
local GEOM_HELPER = HELPERS_DIR .. "display-geometry"
local MOUSE_HELPER = HELPERS_DIR .. "mouse-display"

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
    local id, x, y, w, h = line:match("(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)")
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

-- Locate the mouse pointer's display in the geometric ordering, refreshing
-- the geometry cache once when it isn't there. Returns ids, idx (both nil
-- when the current display can't be determined). Shared by the focus and
-- move paths: both step previous/next off the pointer's display, never the
-- focused window — Lua can't see empty displays, the pointer is always
-- somewhere.
local function current_index(kind, ws, ids)
  local cur_id = current_display_id()
  if not cur_id then
    log(kind .. ": mouse-display helper failed")
    return nil, nil
  end
  if not DISPLAYS[cur_id] then
    log(kind .. ": cur_id " .. cur_id .. " not in geometry cache, refreshing")
    GEOM_STALE = true
    if refresh_geometry() then ids = ORDERED_IDS end
  end
  for i, id in ipairs(ids) do
    if id == cur_id then return ids, i end
  end
  log(kind .. ": cur_id " .. cur_id .. " not in ids [" .. table.concat(ids, ",") .. "] even after refresh")
  return nil, nil
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
  local _, idx = current_index("focus " .. target, ws, ids)
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
    log("focus " .. target .. ": warp-pointer helper failed" .. exec_detail(res))
  end
end

-- Warp exactly onto the moved window's live center. Used by the 2-display
-- path only — on 3+ the move-display helper re-warps post-settle itself, so
-- a second helper spawn here would just be latency.
-- Final focus is handled by the caller returning ws:focus (see below).
-- This runs inside a move dispatch (MOVE_BUSY is set), never via
-- focus_display(), which refuses to run while a move is in flight.
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
  -- Belt and suspenders for outbox-model runtimes: queue the focus as well
  -- (a no-op on pure runtimes, where only the returned set commits).
  pcall(function() ws:focus(focused) end)
end

-- Poll `find_window(query_state_safe(), wid)` until `predicate(w)` holds
-- or the budget runs out. Returns true if the predicate was satisfied.
-- Used by the 2-display `nextdisplay` confirm (that CLI is blocking, so the
-- window is already moved when the poll starts). The 3+ adoption confirm
-- lives in the move-display helper instead, where real sleeps are possible.
local function poll_window(wid, ticks, predicate)
  for _ = 1, ticks do
    local w = find_window(query_state_safe(), wid)
    if w and predicate(w) then return true end
  end
  return false
end

local function move_to_display(ws, target)
  if MOVE_BUSY then
    log("move " .. target .. ": busy (another move already in flight)")
    return
  end
  MOVE_BUSY = true
  -- Set on the success paths below; when true the handler returns a focused
  -- set so pure runtimes commit the focus (see header).
  local moved_ok = false
  local focused_id = nil
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
    local ids2, idx = current_index("move " .. target, ws, ids)
    if not idx then return end
    ids = ids2
    local cur_id = ids[idx]
    local n = #ids
    local step = (target == "previous") and (n - 1) or 1
    local target_id = ids[((idx - 1 + step) % n) + 1]
    log(string.format("move %s: cur=%d idx=%d/%d ids=[%s] -> target=%d",
      target, cur_id, idx, n, table.concat(ids, ","), target_id))
    if target_id == cur_id then
      log("move " .. target .. ": target == current, nothing to do")
      return
    end
    if n == 2 then
      -- 2-display path: `paneru window nextdisplay` via CLI, which applies
      -- immediately (an in-dispatch command could not be observed by the
      -- poll below). Poll for display_id to confirm the window arrived on
      -- the target.
      local exec_ok, res = pcall(paneru.exec, "paneru", { "send-cmd", "window", "nextdisplay" })
      if exec_failed(exec_ok, res) then
        log("move " .. target .. ": nextdisplay CLI failed" .. exec_detail(res))
        paneru.flash("move display: nextdisplay failed", 3.0)
        return
      end
      local settled = poll_window(focused, 200,
        function(w) return w.display_id == target_id end)
      if not settled then
        log("move " .. target .. ": window " .. focused .. " never reported display " .. target_id)
        paneru.flash("move display: failed to settle on target display", 3.0)
      else
        warp_to_moved(ws, focused, target)
        moved_ok = true
      end
      return
    end
    -- 3+ display path: the move-display helper owns the whole move (AX
    -- teleport, warp + mouseMoved, blocking settle with adoption confirm,
    -- live re-warp). Lua checks the exit code — the helper only reports
    -- success once the window is adopted — then restores focus to the
    -- moved window.
    local t = display_frame(ws, target_id)
    if not t then
      log("move " .. target .. ": no geometry for target display " .. target_id)
      paneru.flash("move display: no geometry for target display", 3.0)
      return
    end
    local exec_ok, res = pcall(paneru.exec, MOVE_HELPER, {
      tostring(focused), tostring(math.floor(t.x)), tostring(math.floor(t.y)),
      tostring(math.floor(t.width)), tostring(math.floor(t.height)),
      was_floating and "1" or "0",
      tostring(target_id),
    })
    if exec_failed(exec_ok, res) then
      log("move " .. target .. ": move-display failed for window " .. focused ..
        " to display " .. target_id .. exec_detail(res))
      paneru.flash("move display: move failed", 3.0)
      return
    end
    moved_ok = true
    local timing = ""
    if type(res) == "table" and type(res.stderr) == "string" then
      timing = res.stderr:match("elapsed=%d+ms") or ""
    end
    if timing ~= "" then timing = " (" .. timing .. ")" end
    log("move " .. target .. ": window " .. focused .. " moved to display " .. target_id .. timing)
  end)
  MOVE_BUSY = false
  if not ok then
    log("move " .. target .. ": internal error: " .. tostring(err))
    return nil
  end
  -- Commit the focus for pure runtimes (their docs: handlers return the
  -- transformed set; bare calls commit nothing). A no-op queue entry on
  -- outbox runtimes, where the warp_to_moved call above already queued it.
  if moved_ok and focused_id then
    local fok, res = pcall(function() return ws:focus(focused_id) end)
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
