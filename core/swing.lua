-- Swing detection: turns a controller's recent motion into one swing event.
-- Every fallback level produces the same event, so sports never care which device it was.
--
-- event = {
--   t,        -- controller time of release
--   speed,    -- m/s at the hand/club head estimate
--   power,    -- 0..1 (speed / opts.maxSpeed)
--   dir,      -- world unit vector of travel at release
--   aim,      -- yaw at release, rad (left +), relative to recentre
--   pitch,    -- rad (up +)
--   spin,     -- rad/s twist about the pointing axis at release (right twist +)
--   source,   -- "motion" | "flick" | "stick" | "gesture"
-- }
local m = require("core.math")
local motion = require("core.motion")
local M = {}
M.__index = M

function M.new(ctrl, opts)
  opts = opts or {}
  return setmetatable({
    ctrl = ctrl,
    startSpeed = opts.startSpeed or 3.0,   -- rad/s to start a swing
    endRatio = opts.endRatio or 0.35,      -- swing ends when ω falls below this × peak
    maxTime = opts.maxTime or 0.8,         -- s
    arm = opts.arm or 0.6,                 -- m, hand-to-shoulder radius used for ω → speed
    maxSpeed = opts.maxSpeed or 12,        -- m/s that counts as power 1
    flickAccel = opts.flickAccel or 15,    -- m/s² for level-2 flicks
    holdButton = opts.holdButton,          -- e.g. "b": swing only counts while held (bowling)
    state = "idle",
  }, M)
end

local function event(self, speed, dir, orient, spin, source)
  local yaw, pitch = m.angles(orient)
  return {
    t = self.ctrl.t, speed = speed, power = m.clamp(speed / self.maxSpeed, 0, 1),
    dir = dir, aim = yaw, pitch = pitch, spin = spin, source = source,
  }
end

-- Level 1: full motion tracking from the history ring.
function M:updateMotion()
  local c = self.ctrl
  local w = m.len(c.gyro)
  if self.holdButton and not c.buttons[self.holdButton] and self.state == "idle" then return end
  if self.state == "cooldown" then -- wait for the follow-through to settle before re-arming
    if w < self.startSpeed * 0.5 then self.state = "idle" end
    return
  end
  if self.state == "idle" then
    if w > self.startSpeed then
      self.state, self.t0, self.peak, self.peakSample = "active", c.t, w, nil
      self.vel = { 0, 0, 0 }
    end
    return
  end
  -- active
  local dt = c.history[#c.history] and c.history[#c.history - 1] and (c.history[#c.history].t - c.history[#c.history - 1].t) or 0
  self.vel = m.add(self.vel, m.scale(c.lin, dt))
  if w >= self.peak then
    self.peak = w
    self.peakSample = { orient = c.orient, gyro = c.gyro, vel = self.vel }
  end
  local released = self.holdButton and c.released[self.holdButton]
  if released or w < self.peak * self.endRatio or c.t - self.t0 > self.maxTime then
    self.state = "cooldown"
    local s = self.peakSample or { orient = c.orient, gyro = c.gyro, vel = self.vel }
    if released then s = { orient = c.orient, gyro = c.gyro, vel = self.vel } end
    local linSpeed = m.len(s.vel)
    local speed = math.max(self.peak * self.arm, linSpeed)
    local dir = linSpeed > 0.3 and m.norm(s.vel) or m.qrot(s.orient, m.FORWARD)
    local spin = -s.gyro[3] -- twist about the pointing axis (-z); right twist is -z rotation
    return event(self, speed, dir, s.orient, spin, "motion")
  end
end

-- Level 2: gyro aims (pointer), a flick of the accelerometer or a press of A releases.
function M:updateFlick()
  local c = self.ctrl
  local a = m.len(c.lin)
  if self.state == "idle" then
    if a > self.flickAccel then self.state, self.peak = "active", a end
    if c.pressed.a then
      return event(self, 0.6 * self.maxSpeed, m.qrot(c.orient, m.FORWARD), c.orient, 0, "flick")
    end
    return
  end
  if a > self.peak then self.peak = a end
  if a < self.flickAccel * 0.5 then
    self.state = "idle"
    local speed = m.clamp(self.peak / (3 * self.flickAccel), 0.2, 1) * self.maxSpeed
    return event(self, speed, m.qrot(c.orient, m.FORWARD), c.orient, 0, "flick")
  end
end

-- Level 3: hold B, pull the stick back and push it forward. Flick speed = power,
-- stick x at release = aim/curve.
function M:updateStick()
  local c = self.ctrl
  local x, y = c.stick[1], c.stick[2]  -- y: up = +1
  if not c.buttons.b then self.state = "idle"; return end
  if self.state == "idle" then
    if y < -0.6 then self.state, self.backT = "back", c.t end
    return
  end
  if self.state == "back" and y > 0.6 then
    self.state = "idle"
    local dt = math.max(0.03, c.t - self.backT)
    local speed = m.clamp(0.25 / dt, 0.15, 1) * self.maxSpeed
    local orient = m.qaxis(m.UP, -x * math.rad(20))
    return event(self, speed, m.qrot(orient, m.FORWARD), orient, x * 6, "stick")
  end
end

-- Level 4: touch / mouse drag. Call M.gesture(points) from the shell on release;
-- points = list of {x, y, t} in screen pixels.
function M:gesture(points, pxPerMetre)
  if #points < 2 then return end
  local last = points[#points]
  local i = #points
  while i > 1 and last.t - points[i].t < 0.08 do i = i - 1 end
  local first = points[i]
  local dt = math.max(1e-3, last.t - first.t)
  local dx, dy = (last.x - first.x) / dt, (last.y - first.y) / dt
  local speed = math.sqrt(dx * dx + dy * dy) / (pxPerMetre or 400)
  local aim = math.atan2 and math.atan2(-dx, -dy) or math.atan(-dx, -dy)
  local orient = m.qaxis(m.UP, aim)
  return event(self, math.min(speed, self.maxSpeed), m.qrot(orient, m.FORWARD), orient, 0, "gesture")
end

function M:update()
  local lvl = self.ctrl.level
  if lvl == motion.FULL then return self:updateMotion()
  elseif lvl == motion.GYRO_POINTER then return self:updateFlick()
  elseif lvl == motion.STICK_POINTER then return self:updateStick() end
  -- GESTURE: driven by M:gesture from the shell
end

return M
