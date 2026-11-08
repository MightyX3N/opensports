-- Headless tests for core input code. Run: python3 tools/runlua.py tests/test_core.lua
local m = require("core.math")
local motion = require("core.motion")
local cal = require("core.calibrate")
local swing = require("core.swing")
local ser = require("core.serialize")
local G = 9.80665
local fails, passes = 0, 0
local function ok(cond, msg)
  if cond then passes = passes + 1 else fails = fails + 1; print("FAIL: " .. msg) end
end
local function near(a, b, tol, msg) ok(math.abs(a - b) <= tol, string.format("%s (got %.4f want %.4f)", msg, a, b)) end

-- simulated true motion -> what an ideal device reports in its own axes
local function sample(q, w) -- q: true orient, w: true body rate
  local a = m.qrot(m.qconj(q), { 0, G, 0 }) -- gravity reaction in body frame
  return w, a
end

-- 1. pure yaw rotation integrates correctly
do
  local c = motion.new({ id = 1 })
  local q, w, dt = m.qid(), { 0, math.rad(90), 0 }, 1 / 200
  for _ = 1, 200 do
    q = m.qintegrate(q, w, dt)
    c:feed(dt, sample(q, w))
  end
  local yaw, pitch = m.angles(c.orient)
  near(math.deg(yaw), 90, 1.0, "yaw after 1 s at 90°/s")
  near(math.deg(pitch), 0, 1.0, "pitch stays level during yaw")
  c:recentre()
  near(math.deg((m.angles(c.orient))), 0, 0.01, "recentre zeroes yaw")
end

-- 2. Mahony pulls a wrong start back to the gravity direction
do
  local c = motion.new({ id = 1 })
  c.raw = m.qaxis({ 1, 0, 0 }, math.rad(25))
  for _ = 1, 600 do c:feed(1 / 200, { 0, 0, 0 }, { 0, G, 0 }) end
  local _, pitch = m.angles(c.orient)
  near(math.deg(pitch), 0, 2.0, "tilt drift corrected from accelerometer")
end

-- 3. axis wizard recovers swapped / flipped axes
do
  -- broken device: reports (trueY, -trueX, -trueZ)
  local function broken(v) return { v[2], -v[1], -v[3] } end
  local wz = cal.newWizard()
  local dt = 1 / 100
  local truths = { { -2, 0, 0 }, { 0, 2, 0 }, { 0, 0, -2 } } -- forward, left, twist right
  for s = 1, 3 do
    for _ = 1, 40 do cal.wizardFeed(wz, dt, broken(truths[s])) end
    ok(cal.wizardNext(wz), "wizard step " .. s .. " accepted")
  end
  local axes, signs = cal.wizardSolve(wz)
  ok(axes ~= nil, "wizard solved")
  local p = motion.defaultProfile()
  cal.applyAxes(p, axes, signs)
  -- feed the broken device through the profile and check we get the truth back
  local c = motion.new({ id = 1, profile = p })
  c:feed(0.01, broken({ 0.3, -0.7, 1.1 }), nil)
  near(c.gyro[1], 0.3, 1e-9, "fixed gyro x")
  near(c.gyro[2], -0.7, 1e-9, "fixed gyro y")
  near(c.gyro[3], 1.1, 1e-9, "fixed gyro z")
  -- gravity check: resting broken accel of true (0, g, 0)
  local flipped = cal.fixGravity(p, broken({ 0, G, 0 }))
  ok(not flipped, "gravity already upright after axis fix")
  local q = motion.defaultProfile(); q.accelSign = { -1, -1, -1 }
  ok(cal.fixGravity(q, { 0, G, 0 }), "upside-down accel gets flipped")
end

-- 4. motion check picks the right fallback level
do
  local function run(rate, frozen, noise)
    local c = cal.newCheck(2)
    local dt = 1 / rate
    local i = 0
    while not c.done do
      i = i + 1
      local g = frozen and { 0.01, 0.01, 0.01 } or { math.sin(i * 0.1) * noise + 0.001 * i % 0.003, 0.002, -0.001 }
      cal.checkFeed(c, dt, g, { 0, G, 0 })
    end
    return cal.checkReport(c)
  end
  ok(run(200, false, 0.01).level == motion.FULL, "good pad -> full motion")
  ok(run(60, false, 0.01).level == motion.GYRO_POINTER, "62 Hz pad -> gyro as pointer")
  ok(run(200, true, 0).level == motion.STICK_POINTER, "frozen gyro -> stick as pointer")
  local c = cal.newCheck(1)
  while not c.done do cal.checkFeed(c, 0.01, { 0.001, 0, 0 }, { 0, 1, 0 }) end
  ok(cal.checkReport(c).accelScale == G, "accel reported in g gets scaled")
end

-- 5. a bell-shaped forward swing becomes one event with sensible speed
do
  local c = motion.new({ id = 1 })
  local det = swing.new(c, { arm = 0.6 })
  local q, dt, ev = m.qid(), 1 / 200, nil
  for i = 0, 120 do
    local t = i * dt
    local w = 18 * math.exp(-((t - 0.25) / 0.08) ^ 2) -- peak 18 rad/s at 0.25 s
    local wv = { w, 0, 0 }
    q = m.qintegrate(q, wv, dt)
    local g, a = sample(q, wv)
    c:feed(dt, g, a)
    ev = det:update() or ev
  end
  ok(ev ~= nil, "swing detected")
  if ev then
    near(ev.speed, 18 * 0.6, 1.0, "swing speed ≈ peak ω × arm")
    ok(ev.source == "motion", "source is motion")
  end
end

-- 6. stick flick fallback
do
  local c = motion.new({ id = 1, hasGyro = false })
  c.level = motion.STICK_POINTER
  local det = swing.new(c)
  c:setButton("b", true)
  c.stick = { 0, -1 }; c:feed(0.01, nil, nil); det:update()
  c.stick = { 0.5, 1 }; c:feed(0.08, nil, nil)
  local ev = det:update()
  ok(ev and ev.source == "stick" and ev.power > 0.3, "stick flick makes a swing")
  ok(ev and ev.aim < 0, "stick to the right aims right")
end

-- 7. serializer round trip, and saved files can't call functions
do
  local p = motion.defaultProfile(); p.buttons.a = "x"; p.level = 2
  local back = ser.load(ser.dump(p))
  ok(back and back.buttons.a == "x" and back.level == 2 and back.gyroAxes[3] == 3, "profile round trip")
  ok(ser.load("return os.exit()") == nil, "sandboxed load blocks globals")
end

-- 8. auto bias: a resting controller with a gyro offset stops drifting
do
  local c = motion.new({ id = 1 })
  local off = { 0.05, -0.03, 0.02 }
  for _ = 1, 800 do c:feed(1 / 200, off, { 0, G, 0 }) end
  near(c.bias[1], 0.05, 0.005, "auto bias x learned")
  near(c.bias[2], -0.03, 0.005, "auto bias y learned")
  local y0 = (m.angles(c.orient))
  for _ = 1, 200 do c:feed(1 / 200, off, { 0, G, 0 }) end
  near(math.deg((m.angles(c.orient)) - y0), 0, 0.2, "no yaw drift once bias is learned")
end

print(string.format("%d passed, %d failed", passes, fails))
if fails > 0 then error("tests failed") end
