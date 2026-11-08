-- Scripted play-through of bowling, for testing without a real controller:
--   xvfb-run -s "-screen 0 1280x720x24" love . --script tools/autotest/play_bowling.lua <outdir>
-- It plays a full game: one ball with the mouse, the rest with a simulated Joy-Con 2 (R)
-- that sends motion at 33 reports a second like the real one over Bluetooth, swinging the
-- way the instruction pictures show. It opens the pause menu, the game-over screen and the
-- controller screens, saves screenshots and writes a log of every ball to <outdir>.
local outdir = ... or "autotest-out"
os.execute('mkdir -p "' .. outdir .. '"')
local m = require("core.math")
local motion = require("core.motion")
local I = require("shells.love.input")
local bowling = require("shells.love.bowling")
local G = 9.80665

local simT = 0
love.timer.getTime = function() return simT end

local logf = io.open(outdir .. "/log.txt", "w")
local function L(fmt, ...)
  local s = string.format(fmt, ...)
  logf:write(s .. "\n"); logf:flush()
  print(s)
end
local failures = 0
local function check(cond, what)
  if cond then L("  ok   %s", what) else failures = failures + 1; L("  FAIL %s", what) end
end

------------------------------------------------------------------ simulated Joy-Con 2 (R)
local fake = { pitch = math.rad(80), twist = 0, heading = 0, dPitch = 0, dTwist = 0, acc = 0, buttons = {},
  stick = { 0, 0 } }
local function fakeOrient()
  return m.qmul(m.qaxis({ 0, 1, 0 }, fake.heading),
    m.qmul(m.qaxis({ 1, 0, 0 }, fake.pitch), m.qaxis({ 0, 0, -1 }, fake.twist)))
end
function fake.pump(dt)
  local c = fake.c
  if not c then return end
  for k, v in pairs(fake.buttons) do c:setButton(k, v) end
  c.stick = { fake.stick[1], fake.stick[2] }
  fake.acc = fake.acc + dt
  local step = 1 / 33
  while fake.acc >= step do
    fake.acc = fake.acc - step
    fake.pitch = fake.pitch + fake.dPitch * step
    fake.twist = fake.twist + fake.dTwist * step
    local q = fakeOrient()
    local d = m.qmul(m.qconj(fake.prev), q)
    local ang = 2 * math.acos(m.clamp(d[1], -1, 1))
    local s = math.sqrt(math.max(1e-12, 1 - d[1] * d[1]))
    local w = ang > 1e-9 and { d[2] / s * ang / step, d[3] / s * ang / step, d[4] / s * ang / step } or { 0, 0, 0 }
    -- a little sensor noise, like a real gyro
    for i = 1, 3 do w[i] = w[i] + (math.random() - 0.5) * 0.03 end
    fake.prev = q
    c:feed(step, w, m.qrot(m.qconj(q), { 0, G, 0 }))
  end
end
local function addFake()
  local c = motion.new({ id = "fake-jc2", kind = "joycon2", name = "Joy-Con 2 (R)", guid = "fake-jc2" })
  c.dsu = true -- not read by I.update: this script feeds it
  c.lastRaw = {}
  fake.prev = fakeOrient()
  fake.c = c
  I.list[#I.list + 1] = c
  c.index = #I.list
  I.onNew(c)
  return c
end

------------------------------------------------------------------ script plumbing
local co
local function wait(s)
  local t = simT + s
  while simT < t do coroutine.yield() end
end
local function waitUntil(f, limit)
  local t = simT + (limit or 30)
  while not f() and simT < t do coroutine.yield() end
  return f()
end
local function shot(name)
  love.graphics.captureScreenshot(function(img)
    local f = io.open(outdir .. "/" .. name .. ".png", "wb")
    f:write(img:encode("png"):getString()); f:close()
  end)
  coroutine.yield(); coroutine.yield()
end
local function key(k) love.keypressed(k) end
local function rates(dp, dt_, dur) fake.dPitch, fake.dTwist = dp, dt_; wait(dur); fake.dPitch, fake.dTwist = 0, 0 end
local function poseTo(pitch, dur) rates((pitch - fake.pitch) / dur, -fake.twist / dur, dur) end

local function st() return bowling.state() end
local function frameText()
  local r = st().rules
  local out = {}
  for fi = 1, 10 do
    local mk = r:marks(fi)
    if #mk > 0 then out[#out + 1] = table.concat(mk, " ") end
  end
  return table.concat(out, " | ") .. "   total " .. r:total()
end

-- a Wii Sports style throw with the simulated Joy-Con: upright at the chest, hold ZR,
-- swing back, swing forward (twisting the wrist for spin), let go of ZR
local function jcThrow(opts)
  local g = st()
  local before = #g.rules.frames
  fake.buttons.b = true
  wait(0.5)
  if opts.shotReady then shot(opts.shotReady) end
  rates((math.rad(-150) - fake.pitch) / 0.6, 0, 0.6)
  if opts.shotSwing then shot(opts.shotSwing) end
  local fwdT = opts.fwdTime or 0.28
  rates((math.rad(0) - fake.pitch) / fwdT, (opts.twist or 0) / fwdT, fwdT)
  fake.buttons.b = false
  local thrown = waitUntil(function() return st().phase == "rolling" end, 1.0)
  poseTo(math.rad(80), 0.8)
  return thrown
end

local function mouseThrow(dx)
  local W, H = love.graphics.getDimensions()
  local x, y = W / 2, H * 0.45
  love.mousepressed(x, y, 1)
  for i = 1, 12 do wait(1 / 60); y = y + 14; love.mousemoved(x, y) end
  for i = 1, 6 do wait(1 / 60); y = y - 60; x = x + (dx or 0); love.mousemoved(x, y) end
  love.mousereleased(x, y, 1)
  return waitUntil(function() return st().phase == "rolling" end, 0.5)
end

local function finishBall(tag)
  waitUntil(function() return st().phase == "result" end, 20)
  wait(0.3)
  local g = st()
  local th = g.sim.throwInfo or {}
  L("%-28s -> %-8s  x %+.2f angle %+.2f° speed %.1f m/s hook %+.2f   %s", tag, g.msg or "?", th.x or 0,
    math.deg(th.angle or 0), th.speed or 0, g.lastThrow and g.lastThrow.hook or 0, frameText())
  waitUntil(function() return st().phase == "aim" or st().phase == "over" end, 5)
end

local function script()
  wait(1.0)
  L("== bowling autotest")
  local g = st()
  check(g ~= nil and g.phase == "aim", "game starts on the lane, ready to aim")
  check(g.ctrl.kind == "mouse", "with no controller the mouse is in play")
  shot("01_start_mouse")

  -- 1st ball: mouse flick, slightly right
  local ok = mouseThrow(3)
  check(ok, "mouse: drag down + flick up throws the ball")
  wait(0.9); shot("02_mouse_rolling")
  waitUntil(function() return st().phase == "result" end, 20)
  wait(0.4); shot("03_result")
  finishBall("ball 1 (mouse)")

  -- connect the simulated Joy-Con 2
  local c = addFake()
  wait(0.6)
  check(st().ctrl == c, "a newly connected Joy-Con 2 takes over")
  shot("04_aim_joycon2")

  -- move right, switch to turning, turn a bit, switch back
  local x0 = st().x
  fake.stick = { 1, 0 }; wait(0.4); fake.stick = { 0, 0 }
  check(st().x > x0 + 0.1, "stick moves the bowler right")
  fake.buttons.sclick = true; wait(0.05); fake.buttons.sclick = false; wait(0.05)
  check(st().mode == "turn", "pressing the stick switches to turning")
  fake.stick = { -1, 0 }; wait(0.3); fake.stick = { 0, 0 }
  check(st().angle > 0, "stick turns the aim left")
  shot("05_turning")
  fake.stick = { 1, 0 }; wait(0.3); fake.stick = { 0, 0 }
  check(math.abs(st().angle) < 0.01, "and back right")
  fake.buttons.sclick = true; wait(0.05); fake.buttons.sclick = false; wait(0.05)
  check(st().mode == "move", "pressing the stick again switches back to moving")
  fake.stick = { -1, 0 }; wait(0.45); fake.stick = { 0, 0 }
  -- recentre button
  fake.buttons.recentre = true; wait(0.05); fake.buttons.recentre = false; wait(0.1)
  check(st().toast == "Aim re-centred", "X re-centres the aim")

  -- pause menu: + opens, B/Esc closes
  fake.buttons.plus = true; wait(0.05); fake.buttons.plus = false; wait(0.2)
  check(st().pause, "+ opens the pause menu")
  shot("06_pause")
  key("escape"); wait(0.1)
  check(not st().pause, "Esc closes it again")

  -- pressing ZR and letting go without a swing must not throw
  fake.buttons.b = true; wait(0.6); fake.buttons.b = false; wait(0.3)
  check(st().phase == "aim", "letting go of ZR without swinging doesn't throw")

  -- 2nd ball of frame 1
  local thrown = jcThrow({ shotReady = "07_ready", shotSwing = "08_backswing" })
  check(thrown, "Joy-Con 2: hold ZR, swing back and forward, let go = throw")
  wait(1.2); shot("09_jc2_rolling")
  finishBall("ball 2 (joycon, straight)")

  -- the rest of the game with varied swings
  local styles = {
    { twist = 0.0, fwdTime = 0.25 }, { twist = 0.6, fwdTime = 0.25 }, { twist = -0.5, fwdTime = 0.3 },
    { twist = 0.0, fwdTime = 0.32 }, { twist = 0.9, fwdTime = 0.22 }, { twist = 0.3, fwdTime = 0.45 },
    { twist = 0.0, fwdTime = 0.6 },
  }
  local n, shots = 0, 0
  while st().phase ~= "over" and n < 40 do
    n = n + 1
    local s = styles[n % #styles + 1]
    local ok2 = jcThrow(s)
    if not ok2 then L("  throw %d did not register", n) end
    if shots < 1 and s.twist > 0.5 then wait(2.2); shot("10_hook_at_pins"); shots = shots + 1 end
    finishBall(string.format("joycon twist %+.1f fwd %.2fs", s.twist, s.fwdTime))
  end
  check(st().phase == "over", "a whole game can be played to the end")
  check(st().rules.over, "the rules agree the game is over")
  wait(0.5); shot("11_game_over")
  L("final: %s", frameText())

  -- game over menu: Controllers goes to the controller test screen
  key("down"); wait(0.1); key("return"); wait(0.4)
  shot("12_controllers")
  -- and its remap screen shows the new buttons
  love.keypressed("tab")
  wait(0.2)
  L("done, %d failure(s)", failures)
  logf:close()
  love.event.quit(failures == 0 and 0 or 1)
end

------------------------------------------------------------------ hook into the app
local origLoad, origUpdate = love.load, love.update
love.load = function(...)
  origLoad(...)
  love.window.setVSync(0)
  co = coroutine.create(script)
end
love.update = function()
  for _ = 1, 2 do
    simT = simT + 1 / 60
    fake.pump(1 / 60)
    origUpdate(1 / 60)
  end
  if co and coroutine.status(co) ~= "dead" then
    local ok, err = coroutine.resume(co)
    if not ok then L("SCRIPT ERROR: %s", tostring(err)); logf:close(); love.event.quit(2) end
  end
end
