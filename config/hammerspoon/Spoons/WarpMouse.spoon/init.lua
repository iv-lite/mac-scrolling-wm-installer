--- === WarpMouse ===
---
--- Continuous horizontal multi-monitor cursor wrap.
---
--- Rift's scrolling (niri-style) layout requires displays arranged
--- VERTICALLY in macOS System Settings even when they sit physically
--- side-by-side (avoids an off-screen-column leak bug). That means native
--- macOS mouse edge-crossing only auto-continues on the top/bottom edges
--- (matching the vertical arrangement); moving the cursor to the real
--- physical left/right edge does nothing, since Rift has no equivalent of
--- Paneru's old `horizontal_mouse_warp` setting.
---
--- This Spoon fills that gap: an hs.eventtap watches mouseMoved events,
--- and when the cursor hits the left/right edge of its current screen,
--- warps it to the far edge of the "next"/"previous" screen in a logical
--- left-to-right cycle (wrapping past either end) — giving the feel of
--- one continuous horizontal desktop. It only ever moves the cursor:
--- dragged events (a button held) are not in the watched event types, so
--- a window mid-drag is never yanked across displays by this.
---
--- This replaces an earlier from-scratch Swift CGEventTap
--- daemon/LaunchAgent that could never get its own Accessibility/Input
--- Monitoring grants recognized when launched via launchd. Running as a
--- Hammerspoon Spoon instead sidesteps that entirely: Hammerspoon itself
--- is a single, already-trusted (once granted) process, and everything a
--- Spoon does runs inside it — no separate signing/bundling/LaunchAgent
--- machinery needed.
---
--- Usage (in ~/.hammerspoon/init.lua):
---   hs.loadSpoon("WarpMouse")
---   spoon.WarpMouse:start()
---
--- Tunables (set before :start() to override the defaults):
---   spoon.WarpMouse.edgePx = 2.0
---   spoon.WarpMouse.landingInset = 3.0
---   spoon.WarpMouse.quietMs = 150.0
---   spoon.WarpMouse.invertOrder = false

local obj = {}
obj.__index = obj

obj.name = "WarpMouse"
obj.version = "1.0"
obj.author = "aerospace-installer"
obj.license = "MIT - https://opensource.org/licenses/MIT"
obj.homepage = "https://github.com/"

-- ─── Tunables ───
obj.edgePx = 2.0
obj.landingInset = 3.0
obj.quietMs = 0.0
obj.invertOrder = false

-- ─── Internal state ───
obj._screens = {}
obj._lastWarp = 0
obj._eventtap = nil
obj._screenWatcher = nil

-- ─── Screen enumeration (sorted top-to-bottom -> logical left-to-right) ───
function obj:_refreshScreens()
	local list = {}
	for _, scr in ipairs(hs.screen.allScreens()) do
		table.insert(list, { id = scr:id(), frame = scr:fullFrame() })
	end
	table.sort(list, function(a, b)
		if a.frame.y == b.frame.y then
			return a.frame.x < b.frame.x
		end
		return a.frame.y < b.frame.y
	end)
	if self.invertOrder then
		local reversed = {}
		for i = #list, 1, -1 do
			table.insert(reversed, list[i])
		end
		list = reversed
	end
	self._screens = list
end

local function frameContains(frame, point)
	return point.x >= frame.x and point.x < frame.x + frame.w
		and point.y >= frame.y and point.y < frame.y + frame.h
end

function obj:_indexContaining(point)
	for i, s in ipairs(self._screens) do
		if frameContains(s.frame, point) then
			return i
		end
	end
	return nil
end

--- Returns the warp target `{x=, y=}`, if the point is at a left/right
--- edge worth acting on, or nil otherwise.
function obj:_edgeWarpTarget(point)
	local n = #self._screens
	if n <= 1 then return nil end

	local current = self:_indexContaining(point)
	if not current then return nil end

	local now = hs.timer.secondsSinceEpoch()
	if (now - self._lastWarp) * 1000.0 < self.quietMs then return nil end

	local frame = self._screens[current].frame
	local targetIndex = nil
	local landOnRightEdge = false -- true: land near target's right edge; false: near its left edge

	if point.x <= frame.x + self.edgePx then
		targetIndex = ((current - 2) % n) + 1 -- previous, 1-based, wraps to n
		landOnRightEdge = true
	elseif point.x >= frame.x + frame.w - self.edgePx then
		targetIndex = (current % n) + 1 -- next, 1-based, wraps to 1
		landOnRightEdge = false
	else
		return nil
	end

	if targetIndex == current then return nil end
	local targetFrame = self._screens[targetIndex].frame

	local frac = 0.5
	if frame.h > 0 then
		frac = (point.y - frame.y) / frame.h
	end
	frac = math.max(0.0, math.min(1.0, frac))
	local targetY = targetFrame.y + frac * targetFrame.h
	local targetX
	if landOnRightEdge then
		targetX = targetFrame.x + targetFrame.w - self.landingInset
	else
		targetX = targetFrame.x + self.landingInset
	end

	self._lastWarp = now
	return { x = targetX, y = targetY }
end

function obj:_warp(point)
	hs.mouse.absolutePosition(point)
	-- A bare position set posts no real mouse-moved event to any tap —
	-- including Rift's own focus_follows_mouse tap — so announce it
	-- synthetically, same rationale as the earlier Swift implementation.
	hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.mouseMoved, point):post()
end

--- WarpMouse:init()
--- Method
--- Standard Spoon initializer, called once by hs.loadSpoon().
function obj:init()
	self:_refreshScreens()
end

--- WarpMouse:start()
--- Method
--- Starts watching the mouse and warping it at screen edges.
function obj:start()
	self:_refreshScreens()

	self._screenWatcher = hs.screen.watcher.new(function()
		self:_refreshScreens()
	end)
	self._screenWatcher:start()

	self._eventtap = hs.eventtap.new({ hs.eventtap.event.types.mouseMoved }, function(event)
		local target = self:_edgeWarpTarget(event:location())
		if target then
			self:_warp(target)
		end
		return false
	end)
	self._eventtap:start()

	return self
end

--- WarpMouse:stop()
--- Method
--- Stops watching the mouse and tears down the screen watcher.
function obj:stop()
	if self._eventtap then
		self._eventtap:stop()
		self._eventtap = nil
	end
	if self._screenWatcher then
		self._screenWatcher:stop()
		self._screenWatcher = nil
	end
	return self
end

return obj
