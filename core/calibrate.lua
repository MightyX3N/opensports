-- Motion check (is this controller's motion usable?) and the axis wizard
-- (tilt forward / turn left / twist right -> fix swapped or flipped axes).
local m = require("core.math")
local motion = require("core.motion")
local M = {}

local G = 9.80665

----------------------------------------------------------------- motion check
-- Feed raw device samples for a few seconds (some at rest, some moving).
function M.newCheck(duration)
  return { duration = duration or 4, t = 0, n = 0, frozen = 0, last = nil,
           gsum = { 0, 0, 0 }, gsq = { 0, 0, 0 }, gmax = 0, asum = 0, an = 0, done = false }
end

function M.checkFeed(c, dt, gyroRaw, accelRaw)
  if c.done then return end
  c.t, c.n = c.t + dt, c.n + 1
  if gyroRaw then
    if c.last and gyroRaw[1] == c.last[1] and gyroRaw[2] == c.last[2] and gyroRaw[3] == c.last[3] then
      c.frozen = c.frozen + 1
    end
    c.last = { gyroRaw[1], gyroRaw[2], gyroRaw[3] }
    for i = 1, 3 do
      c.gsum[i] = c.gsum[i] + gyroRaw[i]
      c.gsq[i] = c.gsq[i] + gyroRaw[i] * gyroRaw[i]
    end
    c.gmax = math.max(c.gmax, m.len(gyroRaw))
    c.hasGyroData = true
  end
  if accelRaw then c.asum, c.an = c.asum + m.len(accelRaw), c.an + 1 end
  if c.t >= c.duration then c.done = true end
end

-- Returns { items = { {name, ok, note} ... }, level = recommended fallback level }
function M.checkReport(c)
  local items, level = {}, motion.FULL
  local function add(name, ok, note) items[#items + 1] = { name = name, ok = ok, note = note } end
  local rate = c.t > 0 and c.n / c.t or 0

  if not c.hasGyroData or c.gmax < 1e-4 then
    add("Gyro found", false, "No gyro")
    level = motion.STICK_POINTER
  else
    add("Gyro found", true, "Yes")
    local frozenRatio = c.frozen / math.max(1, c.n)
    if frozenRatio > 0.5 then
      add("Gyro updates", false, "Frozen")
      level = motion.STICK_POINTER
    end
    if rate < 90 then
      add("Sample rate", false, string.format("%d Hz (low)", math.floor(rate + 0.5)))
      if level == motion.FULL then level = motion.GYRO_POINTER end
    else
      add("Sample rate", true, string.format("%d Hz", math.floor(rate + 0.5)))
    end
    -- noise: std dev while mostly still (whole window is fine for a rough check)
    local var = 0
    for i = 1, 3 do
      local mean = c.gsum[i] / c.n
      var = var + (c.gsq[i] / c.n - mean * mean)
    end
    local std = math.sqrt(math.max(0, var))
    if c.gmax < 0.3 then -- never moved: std is pure noise
      if std > 0.05 then
        add("Noise at rest", false, "Noisy")
        if level == motion.FULL then level = motion.GYRO_POINTER end
      else
        add("Noise at rest", true, "Fine")
      end
    end
  end

  if c.an > 0 then
    local g = c.asum / c.an
    if g > 0.7 * G and g < 1.3 * G then
      add("Accelerometer", true, "Fine")
    elseif g > 0.7 and g < 1.3 then
      add("Accelerometer", false, "Reports in g (fixed)")
      c.accelScale = G
    else
      add("Accelerometer", false, string.format("Odd scale (%.1f)", g))
    end
  end
  return { items = items, level = level, accelScale = c.accelScale }
end

------------------------------------------------------------------ axis wizard
-- Steps in the controller convention of core.math (x right, y up, z to player):
-- tilt forward = negative rotation about x, turn left = positive about y,
-- twist right (right side down) = negative about z.
M.STEPS = {
  { id = "forward", title = "Tilt the controller forward", hint = "Point at the screen, tip the front down, then bring it back.", axis = 1, sign = -1 },
  { id = "left", title = "Turn the controller left", hint = "Keep it level, turn it to the left, then bring it back.", axis = 2, sign = 1 },
  { id = "twist", title = "Twist the controller right", hint = "Keep pointing at the screen, roll the right side down, then bring it back.", axis = 3, sign = -1 },
}

function M.newWizard() return { step = 1, integ = {}, cur = { 0, 0, 0 }, peak = { 0, 0, 0 } } end

-- Integrate raw gyro during the current step. Only the first half of the motion
-- counts (until the integral peaks), so "and back up" doesn't cancel it.
function M.wizardFeed(w, dt, gyroRaw)
  if not gyroRaw or w.step > #M.STEPS then return end
  for i = 1, 3 do
    w.cur[i] = w.cur[i] + gyroRaw[i] * dt
    if math.abs(w.cur[i]) > math.abs(w.peak[i]) then w.peak[i] = w.cur[i] end
  end
end

-- Strongest raw axis so far in this step, and how far it has turned (rad)
function M.wizardLive(w)
  local best, bi = 0, 1
  for i = 1, 3 do if math.abs(w.peak[i]) > math.abs(best) then best, bi = w.peak[i], i end end
  return bi, best
end

-- Accept the step once the motion was big enough (default 25°). Returns true if accepted.
function M.wizardNext(w, minAngle)
  local _, best = M.wizardLive(w)
  if math.abs(best) < (minAngle or math.rad(25)) then return false end
  w.integ[w.step] = w.peak
  w.step = w.step + 1
  w.cur, w.peak = { 0, 0, 0 }, { 0, 0, 0 }
  return true
end

function M.wizardRedo(w) w.cur, w.peak = { 0, 0, 0 }, { 0, 0, 0 } end

-- Build axis order/sign from the three recorded steps.
-- Returns axes, signs or nil, reason.
function M.wizardSolve(w)
  if #w.integ < #M.STEPS then return nil, "not finished" end
  local axes, signs, used = { 0, 0, 0 }, { 1, 1, 1 }, {}
  for s, step in ipairs(M.STEPS) do
    local v = w.integ[s]
    local best, bi = -1, nil
    for i = 1, 3 do
      if not used[i] and math.abs(v[i]) > best then best, bi = math.abs(v[i]), i end
    end
    used[bi] = true
    axes[step.axis] = bi
    signs[step.axis] = (v[bi] * step.sign) >= 0 and 1 or -1
  end
  return axes, signs
end

-- Apply the result to a profile. The accelerometer normally shares the gyro's
-- frame, so it gets the same order/sign; gravity is then checked separately.
function M.applyAxes(profile, axes, signs)
  profile.gyroAxes, profile.gyroSign = axes, signs
  profile.accelAxes = { axes[1], axes[2], axes[3] }
  profile.accelSign = { signs[1], signs[2], signs[3] }
end

-- With the controller held flat and pointing at the screen, mapped accel y must be +g.
-- Call with a raw resting accel sample; flips accel signs if gravity reads upside down.
function M.fixGravity(profile, accelRaw)
  local a = profile.accelAxes
  local y = accelRaw[a[2]] * profile.accelSign[2] * (profile.accelScale or 1)
  if y < 0 then
    for i = 1, 3 do profile.accelSign[i] = -profile.accelSign[i] end
    return true
  end
  return false
end

return M
