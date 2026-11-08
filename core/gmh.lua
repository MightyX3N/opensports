-- Lua port of GamepadMotionHelpers by Julian "Jibb" Smart (MIT), the sensor fusion used by
-- JoyShockMapper and many emulators: orientation + gravity tracking, automatic gyro
-- calibration while the controller is still, and player-space gyro for aiming.
-- https://github.com/JibbSmart/GamepadMotionHelpers — see THIRD_PARTY.md.
--
-- Units here match the original: gyro in degrees/s, accel in g. Frame: x right, y up,
-- z towards the player (same as core.math). Gravity points down (-y at rest).
local m = require("core.math")
local exp2 = function(x) return 2 ^ x end
local deg = 180 / math.pi
local M = {}
M.__index = M

M.settings = {
  MinStillnessSamples = 10, MinStillnessCollectionTime = 0.5, MinStillnessCorrectionTime = 2.0,
  MaxStillnessError = 2.0, StillnessSampleDeteriorationRate = 0.2, StillnessErrorClimbRate = 0.1,
  StillnessErrorDropOnRecalibrate = 0.1, StillnessCalibrationEaseInTime = 3.0,
  StillnessCalibrationHalfTime = 0.1, StillnessConfidenceRate = 1.0,
  GravityCorrectionShakinessMaxThreshold = 0.4, GravityCorrectionShakinessMinThreshold = 0.01,
  GravityCorrectionStillSpeed = 1.0, GravityCorrectionShakySpeed = 0.1,
  GravityCorrectionGyroFactor = 0.1, GravityCorrectionGyroMinThreshold = 0.05,
  GravityCorrectionGyroMaxThreshold = 0.25, GravityCorrectionMinimumSpeed = 0.01,
  ShortSteadinessHalfTime = 0.25,
}

local function vmin(a, b) return { math.min(a[1], b[1]), math.min(a[2], b[2]), math.min(a[3], b[3]) } end
local function vmax(a, b) return { math.max(a[1], b[1]), math.max(a[2], b[2]), math.max(a[3], b[3]) } end
local function vlerp(a, b, t) return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t } end
local function clamp(x, lo, hi) return x < lo and lo or (x > hi and hi or x) end
-- v * q in the original = rotate v by q's inverse... original "Vec *= Quat" rotates by q
local function rotInv(q, v) return m.qrot(m.qconj(q), v) end

function M.new()
  local s = setmetatable({}, M)
  s:reset()
  return s
end

function M:reset()
  self.q = m.qid()
  self.grav = { 0, -1, 0 }
  self.accel = { 0, 0, 0 }
  self.smoothAccel = { 0, 0, 0 }
  self.shakiness = 0
  self.gyro = { 0, 0, 0 }
  self.bias = { 0, 0, 0 }
  self.biasSamples = 0
  -- auto calibration (stillness)
  self.win = { n = 0, t = 0 }
  self.confidence = 0
  self.steady = false
  self.minDeltaGyro = { 1, 1, 1 }
  self.minDeltaAccel = { 0.25, 0.25, 0.25 }
  self.recalThreshold = 1
  self.timeSteady = 0
end

local function winReset(w, rem) w.n = 0; w.t = rem or 0 end
local function winAdd(w, g, a, dt)
  if w.n == 0 then
    w.maxG, w.minG, w.meanG = { g[1], g[2], g[3] }, { g[1], g[2], g[3] }, { g[1], g[2], g[3] }
    w.maxA, w.minA, w.meanA = { a[1], a[2], a[3] }, { a[1], a[2], a[3] }, { a[1], a[2], a[3] }
    w.startA = { a[1], a[2], a[3] }
    w.n, w.t = 1, w.t + dt
    return
  end
  w.maxG, w.minG = vmax(w.maxG, g), vmin(w.minG, g)
  w.maxA, w.minA = vmax(w.maxA, a), vmin(w.minA, a)
  w.n, w.t = w.n + 1, w.t + dt
  w.meanG = m.add(w.meanG, m.scale(m.sub(g, w.meanG), 1 / w.n))
  w.meanA = m.add(w.meanA, m.scale(m.sub(a, w.meanA), 1 / w.n))
end

-- AutoCalibration::AddSampleStillness with sensor fusion
function M:stillness(g, a, dt)
  local S = M.settings
  local w = self.win
  winAdd(w, g, a, dt)
  local gd = m.sub(w.maxG, w.minG)
  local ad = m.sub(w.maxA, w.minA)
  local climb = S.StillnessSampleDeteriorationRate * dt
  if self.confidence < 1 then
    self.minDeltaGyro = m.add(self.minDeltaGyro, { climb, climb, climb })
    self.minDeltaAccel = m.add(self.minDeltaAccel, { climb, climb, climb })
  end
  if w.n >= S.MinStillnessSamples and w.t >= S.MinStillnessCollectionTime then
    self.minDeltaGyro = vmin(self.minDeltaGyro, gd)
    self.minDeltaAccel = vmin(self.minDeltaAccel, ad)
  else
    self.recalThreshold = math.min(self.recalThreshold + S.StillnessErrorClimbRate * dt, S.MaxStillnessError)
    return
  end
  local th = self.recalThreshold
  local still = true
  for i = 1, 3 do
    if gd[i] > self.minDeltaGyro[i] * th or ad[i] > self.minDeltaAccel[i] * th then still = false end
  end
  self.steady = false
  if still then
    if w.t >= S.MinStillnessCorrectionTime then
      self.timeSteady = math.min(self.timeSteady + dt, S.StillnessCalibrationEaseInTime)
      local easeIn = self.timeSteady / S.StillnessCalibrationEaseInTime
      local calibrated = w.meanG
      local halfTime = S.StillnessCalibrationHalfTime * self.confidence
      local lerpF = halfTime <= 0 and 0 or exp2(-easeIn * dt / halfTime)
      local newBias = vlerp(calibrated, self.bias, lerpF)
      self.confidence = math.min(self.confidence + dt * S.StillnessConfidenceRate, 1)
      self.steady = true
      -- sensor fusion: remove the part of the "still" reading explained by gravity turning
      local pn, tn = m.norm(w.startA), m.norm(a)
      local av = m.cross(tn, pn)
      local cl = m.len(av)
      if cl > 0 then
        local ang = math.acos(clamp(m.dot(tn, pn), -1, 1)) * deg
        av = m.scale(av, (ang / w.t) / cl)
      end
      local sf = vlerp(m.sub(calibrated, av), self.bias, lerpF)
      for i = 1, 3 do if math.abs(tn[i]) <= 0.7 then newBias[i] = sf[i] end end
      self.bias = newBias
    else
      self.recalThreshold = math.min(self.recalThreshold + S.StillnessErrorClimbRate * dt, S.MaxStillnessError)
    end
  elseif self.timeSteady > 0 then
    self.recalThreshold = math.max(1, self.recalThreshold - S.StillnessErrorDropOnRecalibrate)
    self.timeSteady = 0
    winReset(w, 0)
  else
    self.recalThreshold = math.min(self.recalThreshold + S.StillnessErrorClimbRate * dt, S.MaxStillnessError)
    winReset(w, 0)
  end
end

-- Motion::Update. gyro °/s (already bias-corrected), accel g.
function M:motion(gyro, accel, gravityLength, dt)
  local S = M.settings
  local angleSpeed = m.len(gyro) / deg
  local rotation = m.qaxis(gyro, angleSpeed * dt)
  if angleSpeed * dt < 1e-12 then rotation = m.qid() end
  self.q = m.qmul(self.q, rotation)
  local amag = m.len(accel)
  if amag > 0 then
    local an = m.scale(accel, 1 / amag)
    self.smoothAccel = rotInv(rotation, self.smoothAccel)
    local sf = S.ShortSteadinessHalfTime <= 0 and 0 or exp2(-dt / S.ShortSteadinessHalfTime)
    self.shakiness = math.max(self.shakiness * sf, m.len(m.sub(accel, self.smoothAccel)))
    self.smoothAccel = vlerp(accel, self.smoothAccel, sf)
    self.grav = rotInv(rotation, self.grav)
    local gravToAccel = m.sub(m.scale(an, -gravityLength), self.grav)
    local dir = m.norm(gravToAccel)
    local speed = S.GravityCorrectionStillSpeed + (S.GravityCorrectionShakySpeed - S.GravityCorrectionStillSpeed) *
      clamp((self.shakiness - S.GravityCorrectionShakinessMinThreshold) /
        (S.GravityCorrectionShakinessMaxThreshold - S.GravityCorrectionShakinessMinThreshold), 0, 1)
    local limit = math.max(angleSpeed * S.GravityCorrectionGyroFactor, S.GravityCorrectionMinimumSpeed)
    if speed > limit then
      local close = clamp((m.len(gravToAccel) - S.GravityCorrectionGyroMinThreshold) /
        (S.GravityCorrectionGyroMaxThreshold - S.GravityCorrectionGyroMinThreshold), 0, 1)
      speed = limit + (speed - limit) * close
    end
    local delta = m.scale(dir, speed * dt)
    if m.dot(delta, delta) < m.dot(gravToAccel, gravToAccel) then
      self.grav = m.add(self.grav, delta)
    else
      self.grav = m.scale(an, -gravityLength)
    end
    -- pull the orientation so its gravity matches the tracked gravity
    local gravWorld = m.qrot(self.q, m.norm(self.grav))
    local down = { 0, -1, 0 }
    local err = math.acos(clamp(m.dot(down, gravWorld), -1, 1))
    local flat = m.cross(gravWorld, down)
    if m.len(flat) > 1e-9 and err > 1e-9 then
      self.q = m.qmul(m.qaxis(flat, err), self.q)
    end
    self.accel = m.add(accel, self.grav)
  else
    self.grav = rotInv(rotation, self.grav)
    self.accel = { self.grav[1], self.grav[2], self.grav[3] }
  end
  self.q = m.qnorm(self.q)
end

-- GamepadMotion::ProcessMotion. gyro °/s raw, accel g raw.
function M:process(gyro, accel, dt)
  if gyro[1] == 0 and gyro[2] == 0 and gyro[3] == 0 and accel[1] == 0 and accel[2] == 0 and accel[3] == 0 then return end
  self:stillness(gyro, accel, dt)
  local g = m.sub(gyro, self.bias)
  self.gyro = g
  self:motion(g, accel, m.len(accel), dt)
end

-- player-space gyro (°/s): x = pitch rate (up +), y = yaw rate around gravity (left +)
function M:playerSpace(yawRelax)
  yawRelax = yawRelax or 1.41
  local g, gr = self.gyro, m.norm(self.grav)
  local worldYaw = -(gr[2] * g[2] + gr[3] * g[3])
  local sign = worldYaw < 0 and -1 or 1
  local y = sign * math.min(math.abs(worldYaw) * yawRelax, math.sqrt(g[2] * g[2] + g[3] * g[3]))
  return g[1], y
end

return M
