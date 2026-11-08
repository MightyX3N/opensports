-- MotionController: every input device ends up as one of these.
-- Sports read only these fields; backends only call :feed() and set buttons.
local m = require("core.math")
local M = {}
M.__index = M

local G = 9.80665

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
  c.kp, c.ki = 1.5, 0.01 -- Mahony gains
  c.eInt = { 0, 0, 0 }
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

  if self.biasSamples then -- resting calibration in progress
    local b = self.biasSamples
    b.n = b.n + 1
    b.s = m.add(b.s, g)
    if b.n >= b.need then
      self.bias = m.scale(b.s, 1 / b.n)
      self.biasSamples = nil
    end
  end
  -- auto bias: while the controller lies truly still, learn the gyro's zero offset.
  -- "Truly still" = the reading barely varies (sensor noise only) and gravity is steady.
  -- A hand always trembles, so even a slow aiming turn is never learned as bias.
  if not self.biasSamples and a then
    local k = math.min(1, dt * 2)          -- ~0.5 s running mean / variance
    self.gMean = self.gMean and m.add(self.gMean, m.scale(m.sub(g, self.gMean), k)) or { g[1], g[2], g[3] }
    local d = m.sub(g, self.gMean)
    self.gVar = (self.gVar or 1e-3) + (m.dot(d, d) - (self.gVar or 1e-3)) * k
    local steady = self.lastA and m.len(m.sub(a, self.lastA)) < 0.08
    if math.sqrt(self.gVar) < 0.006 and math.abs(m.len(a) - G) < 0.4 and steady and m.len(self.gMean) < 0.2 then
      self.stillT = (self.stillT or 0) + dt
      if self.stillT > 1.0 then
        self.bias = m.add(self.bias, m.scale(m.sub(self.gMean, self.bias), math.min(1, dt * 3)))
      end
    else
      self.stillT = 0
    end
    self.lastA = a
  end
  g = m.sub(g, self.bias)
  self.gyro = g

  -- Mahony: pull the estimated "up" towards the measured gravity reaction.
  if a then
    self.accel = a
    local al = m.len(a)
    if al > 0.5 * G and al < 1.5 * G then -- only trust accel when not swinging hard
      local an = m.scale(a, 1 / al)
      local up = m.qrot(m.qconj(self.raw), m.UP) -- world up in controller space
      local e = m.cross(an, up)
      self.eInt = m.add(self.eInt, m.scale(e, self.ki * dt))
      g = m.add(g, m.add(m.scale(e, self.kp), self.eInt))
    end
  end
  self.raw = m.qintegrate(self.raw, g, dt)
  self.orient = m.qmul(m.qaxis(m.UP, -self.yawOffset), self.raw)

  if a then
    local wa = m.qrot(self.raw, a)
    self.lin = { wa[1], wa[2] - G, wa[3] }
  end

  if not self.hasPointer then -- gyro-aimed pointer
    local yaw, pitch = m.angles(self.orient)
    local px = 0.5 - yaw / (2 * self.pointerFov[1])
    local py = 0.5 - pitch / (2 * self.pointerFov[2])
    -- pin to the screen edge instead of vanishing; "valid" only when really pointing at it
    self.pointer.valid = px >= -0.25 and px <= 1.25 and py >= -0.25 and py <= 1.25
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
end

function M:startRestCalibration(samples)
  self.biasSamples = { n = 0, need = samples or 200, s = { 0, 0, 0 } }
  self.bias = { 0, 0, 0 }
end
function M:calibrating() return self.biasSamples ~= nil end

function M:rumble(t, strength) if self.onRumble then self.onRumble(t, strength or 1) end end

return M
