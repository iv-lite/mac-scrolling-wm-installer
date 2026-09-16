--- === WarpMouse ===
--- Continuous horizontal multi-monitor cursor wrap with acceleration support.
--- Watches mouseMoved events; at a screen's left/right edge, warps to the
--- opposite edge of the next/previous screen and keeps gliding at the captured
--- velocity (no deceleration) until a real mouse event takes over.
--- Usage: hs.loadSpoon("WarpMouse"); spoon.WarpMouse:start()
--- Tunables (before :start): edgePx, landingInset, continueAfterWarp

local obj = {}
obj.__index = obj

obj.name = "WarpMouse"
obj.version = "2.0"
obj.author = "aerospace-installer"
obj.license = "MIT - https://opensource.org/licenses/MIT"

-- ─── Tunables ───
obj.edgePx = 2.0
obj.landingInset = 3.0
obj.continueAfterWarp = true

-- ─── Internal state ───
obj._screens = {}
obj._eventtap = nil
obj._screenWatcher = nil
obj._posHistory = {}
obj._warpActive = false
obj._moveTimer = nil

-- ─── Screen enumeration ───
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
	self._screens = list
end

-- ─── Velocity: 5-point position history, least-squares slope ───

function obj:_appendHistory(pos, ts)
	if self._warpActive then return end
	local h = self._posHistory
	h[#h + 1] = { t = ts, x = pos.x, y = pos.y }
	if #h > 5 then
		table.remove(h, 1)
	end
end

function obj:_getVelocity()
	local h = self._posHistory
	if #h < 2 then return 0, 0 end
	local dx = h[#h].x - h[1].x
	local dy = h[#h].y - h[1].y
	local dt = (h[#h].t - h[1].t) / 1e9
	if dt <= 0 then return 0, 0 end
	return dx / dt, dy / dt
end

-- ─── Warp target calculation ───
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

function obj:_edgeWarpTarget(point)
	local n = #self._screens
	if n <= 1 then return nil end

	local current = self:_indexContaining(point)
	if not current then return nil end

	local frame = self._screens[current].frame
	local targetIndex = nil
	local landOnRightEdge = false

	if point.x <= frame.x + self.edgePx then
		targetIndex = ((current - 2) % n) + 1
		landOnRightEdge = true
	elseif point.x >= frame.x + frame.w - self.edgePx then
		targetIndex = (current % n) + 1
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

	return { x = targetX, y = targetY }
end

-- ─── Post-warp glide (no deceleration) ───

function obj:_stopContinuation()
	if self._moveTimer then
		self._moveTimer:stop()
		self._moveTimer = nil
	end
end

function obj:_startContinuation(vx, vy)
	self:_stopContinuation()
	if not self.continueAfterWarp then return end
	if math.abs(vx) < 50 and math.abs(vy) < 50 then return end

	local pos = hs.mouse.absolutePosition()
	local frames = 0
	local maxFrames = 12 -- 0.2s at 60Hz

	self._moveTimer = hs.timer.new(1.0 / 60.0, function()
		frames = frames + 1
		if frames > maxFrames then
			self:_stopContinuation()
			return
		end
		pos.x = pos.x + vx / 60.0
		pos.y = pos.y + vy / 60.0
		self:_moveCursor(pos)
	end)
	self._moveTimer:start()
end

-- ─── Warp ───

function obj:_moveCursor(pos)
	self._warpActive = true
	hs.mouse.absolutePosition(pos)
	hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.mouseMoved, pos):post()
	self._warpActive = false
end

function obj:_warp(point)
	local vx, vy = self:_getVelocity()
	self._posHistory = {}
	self:_moveCursor(point)
	self:_startContinuation(vx, vy)
end

-- ─── Public API ───

function obj:init()
	self:_refreshScreens()
end

function obj:start()
	self:_refreshScreens()

	self._screenWatcher = hs.screen.watcher.new(function()
		self:_refreshScreens()
	end)
	self._screenWatcher:start()

	self._eventtap = hs.eventtap.new({ hs.eventtap.event.types.mouseMoved }, function(event)
		local loc = event:location()
		self:_appendHistory(loc, event:timestamp())

		local target = self:_edgeWarpTarget(loc)
		if target then
			self:_warp(target)
		end
		return false
	end)
	self._eventtap:start()

	return self
end

function obj:stop()
	self:_stopContinuation()
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