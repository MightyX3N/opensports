-- MotionController: every input device ends up as one of these.
-- Sports read only these fields; backends only call :feed() and set buttons.
local m = require("core.math")
local gmh = require("core.gmh")
local M = {}
M.__index = M

local G = 9.80665
local DEG = 180 / math.pi

-- Fallback levels (architecture §3)
M.FULL, M.GYRO_POINTER, M.STICK_POINTER, M.GESTURE = 1, 2, 3, 4
M.LEVEL_NAMES = { "Full motion", "Gyro as pointer", "Stick as pointer", "Touch / mouse" }

local HISTORY = 1.0 -- seconds of samples kept for swing detection

-- A profile fixes a device: axis order/sign and button remap. Saved per GUID.
function M.defaultProfile()
  return {
    gyroAxes = { 1, 2, 3 }, gyroSign = { 1, 1, 1 },
    accelAxes = { 1, 2, 3 }, accelSign = { 1, 1, 1 },
    gyroScale = 1, accelScale = 1, -- multiply raw readings into rad/s and m/s²
    buttons = {},                  -- logical name -> backend button id (only overrides)
    level = nil,                   -- nil = pick from motion check
  }
end

function M.new(opts)
  local c = setmetatable({}, M)
  c.id = opts.id
  c.kind = opts.kind or "gyropad"     -- wiimote, joycon, joycon2, gyropad, phone, mouse
  c.name = opts.name or c.kind
  c.guid = opts.guid or c.kind
  c.hasGyro = opts.hasGyro ~= false
  c.hasAccel = opts.hasAccel ~= false
  c.hasPointer = opts.hasPointer or false -- true IR / touch pointer
  c.profile = opts.profile or M.defaultProfile()
  c.level = c.profile.level or (c.hasGyro and M.FULL or M.GESTURE)

  c.orient = m.qid()     -- controller -> world, after recentre
  c.raw = m.qid()        -- filter state, before recentre
  c.yawOffset = 0
  c.gyro = { 0, 0, 0 }   -- rad/s, controller space, bias removed
  c.accel = { 0, 0, 0 }  -- m/s², controller space, including gravity
  c.lin = { 0, 0, 0 }    -- m/s², world space, gravity removed
  c.pointer = { x = 0.5, y = 0.5, valid = false }
  c.stick = { 0, 0 }
  c.buttons, c.pressed, c.released = {}, {}, {}
  c.bias = { 0, 0, 0 }
  c.biasSamples = nil
  c.history = {}         -- ring of {t, gyro, lin, orient}
  c.t = 0
  c.rate = 0             -- measured samples per second
  c.rateAcc, c.rateN = 0, 0
  c.fusion = gmh.new()
  c.pointerFov = { math.rad(22), math.rad(13) } -- gyro-aimed pointer: half-angles that reach the screen edges
  return c
end

local function remap(v, axes, sign, scale)
  return { v[axes[1]] * sign[1] * scale, v[axes[2]] * sign[2] * scale, v[axes[3]] * sign[3] * scale }
end

-- Feed one raw sensor sample. gyroRaw rad/s, accelRaw m/s² (gravity included, device axes).
function M:feed(dt, gyroRaw, accelRaw)
  if dt <= 0 then return end
  self.t = self.t + dt
  self.rateAcc, self.rateN = self.rateAcc + dt, self.rateN + 1
  if self.rateAcc >= 0.5 then
    self.rate = self.rateN / self.rateAcc
    self.rateAcc, self.rateN = 0, 0
  end
  local p = self.profile
  local g = gyroRaw and remap(gyroRaw, p.gyroAxes, p.gyroSign, p.gyroScale) or { 0, 0, 0 }
  local a = accelRaw and remap(accelRaw, p.accelAxes, p.accelSign, p.accelScale) or nil

  if self.biasSamples then -- manual resting calibration ("put it down flat")
    local bs = self.biasSamples
    bs.n = bs.n + 1
    bs.s = m.add(bs.s, g)
    if bs.n >= bs.need then
      self.fusion.bias = m.scale(bs.s, DEG / bs.n)
      self.fusion.confidence = 1
      self.biasSamples = nil
    end
  end

  -- Sensor fusion and automatic gyro calibration: GamepadMotionHelpers (core/gmh.lua).
  local f = self.fusion
  if a then self.accel = a end
  local acc = a or m.qrot(m.qconj(f.q), { 0, G, 0 })
  f:process(m.scale(g, DEG), m.scale(acc, 1 / G), dt)
  self.bias = m.scale(f.bias, 1 / DEG)
  self.gyro = m.scale(f.gyro, 1 / DEG)
  self.raw = f.q
  -- A controller that tracks its own orientation (Joy-Con 2 native reports) wins over our
  -- fusion. Its reference "up" may differ from ours, so it is aligned to gravity whenever
  -- the accelerometer is trustworthy (not swinging).
  if self.extOrient then
    local e = self.extOrient
    if a and math.abs(m.len(a) - G) < 0.6 then
      local upW = m.qrot(e, m.norm(a))
      local target = m.qfromto(upW, m.UP)
      self.extAlign = self.extAlign and m.qslerp(self.extAlign, target, math.min(1, dt * 1.5)) or target
    end
    self.raw = m.qmul(self.extAlign or m.qid(), e)
  end
  self.orient = m.qmul(m.qaxis(m.UP, -self.yawOffset), self.raw)
  if a then
    local wa = m.qrot(self.raw, m.scale(f.accel, G)) -- gravity already removed
    self.lin = wa
  end

  -- gyro pointer: moved by player-space gyro (yaw around gravity, pitch), like a mouse.
  -- It never "loses" its place when orientation drifts, and pins at the screen edges.
  -- pointer comes from the same orientation the 3D model shows (absolute, like the Wii's
  -- IR), so the dot and the model always agree; recentre sets "straight at the screen"
  if not self.hasPointer then
    local yaw, pitch = m.angles(self.orient)
    local px = 0.5 - yaw / (2 * self.pointerFov[1])
    local py = 0.5 - pitch / (2 * self.pointerFov[2])
    self.pointer.valid = math.abs(yaw) < math.rad(80) and math.abs(pitch) < math.rad(70)
    self.pointer.x, self.pointer.y = m.clamp(px, 0, 1), m.clamp(py, 0, 1)
  end

  local h = self.history
  h[#h + 1] = { t = self.t, gyro = self.gyro, lin = self.lin, orient = self.orient }
  while #h > 1 and self.t - h[1].t > HISTORY do table.remove(h, 1) end
end

-- Logical buttons: a, b, one, two, plus, minus, home, up, down, left, right
function M:setButton(name, down)
  local was = self.buttons[name]
  self.buttons[name] = down or nil
  if down and not was then self.pressed[name] = true end
  if was and not down then self.released[name] = true end
end
function M:endFrame() self.pressed, self.released = {}, {} end

-- Point at the screen centre and call this: current heading becomes "forward".
function M:recentre()
  local yaw = m.angles(self.raw)
  self.yawOffset = yaw
  self.orient = m.qmul(m.qaxis(m.UP, -yaw), self.raw)
  self.pointer.x, self.pointer.y = 0.5, 0.5
end

function M:startRestCalibration(samples)
  self.biasSamples = { n = 0, need = samples or 200, s = { 0, 0, 0 } }
end
function M:calibrating() return self.biasSamples ~= nil end

function M:rumble(t, strength) if self.onRumble then self.onRumble(t, strength or 1) end end

return M
