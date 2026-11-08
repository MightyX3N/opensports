-- Headless tests for bowling: scoring, lane physics and the throw reader.
-- Run: python3 tools/runlua.py tests/test_bowling.lua  (or: LUA_PATH="./?.lua;;" luajit tests/test_bowling.lua)
local Rules = require("sports.bowling.modes.standard")
local Sim = require("sports.bowling.sim")
local T = require("sports.bowling.tuning")
local fails, passes = 0, 0
local function ok(cond, msg)
  if cond then passes = passes + 1 else fails = fails + 1; print("FAIL: " .. msg) end
end
local function game(balls)
  local r = Rules.new()
  for _, n in ipairs(balls) do r:record(n) end
  return r
end

-- scoring
ok(game({ 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10 }):total() == 300, "perfect game is 300")
ok(game({ 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10 }).over, "perfect game ends after 12 balls")
local all9 = {}
for _ = 1, 10 do all9[#all9 + 1] = 9; all9[#all9 + 1] = 0 end
ok(game(all9):total() == 90, "nine-and-miss game is 90")
local spares = {}
for _ = 1, 21 do spares[#spares + 1] = 5 end
ok(game(spares):total() == 150, "all 5/5 spares is 150")
ok(game({ 10, 3, 4 }):totals()[1] == 17 and game({ 10, 3, 4 }):totals()[2] == 24, "strike bonus")
ok(game({ 10, 3 }):totals()[1] == nil, "strike total waits for two more balls")
ok(game({ 7, 3, 4 }):totals()[1] == 14, "spare bonus")
do
  local r = game({ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 7, 2 })
  ok(r.over and r:total() == 9, "open 10th frame ends after two balls")
  local r2 = game({ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 7, 3, 5 })
  ok(r2.over and r2:total() == 15, "10th frame spare gives a third ball")
  local r3 = Rules.new()
  for _ = 1, 18 do r3:record(0) end
  local a = r3:record(10); local b = r3:record(4)
  ok(a.rerack and not b.rerack and not b.frameDone, "10th: strike reracks, then 4 leaves pins for the third ball")
  local c = r3:record(6)
  ok(c.spare and c.gameOver, "10th: X 4 / ends with a spare")
  local mk = r3:marks(10)
  ok(mk[1] == "X" and mk[2] == "4" and mk[3] == "/", "10th frame marks X 4 /")
end
do
  local r = Rules.new()
  local a = r:record(10)
  ok(a.strike and a.frameDone and r.frame == 2, "strike ends the frame")
  local b = r:record(0)
  ok(b.gutter and not b.frameDone, "first-ball zero is a gutter")
  local c = r:record(10)
  ok(c.spare and r:marks(2)[1] == "-" and r:marks(2)[2] == "/", "0 then 10 is a spare, marked - /")
end

-- lane physics
local function throw(th)
  local s = Sim.new(T.get("arcade"))
  s:throw(th)
  local n = s:runToEnd(30)
  return n, s
end
do
  local n, s = throw({ x = 0, angle = 0, speed = 8, hook = 0 })
  ok(n < 10, "a straight ball at the head pin knocks pins down (" .. n .. " left)")
  ok(s.t < 8, "the turn ends in reasonable time")
  local n2, s2 = throw({ x = 0.45, angle = math.rad(-2.5), speed = 7, hook = 0 })
  ok(s2.gutter and n2 == 10, "a gutter ball leaves all 10 standing")
  local n3 = throw({ x = 0.07, angle = 0, speed = 8.5, hook = 0 })
  ok(n3 <= 2, "a pocket hit takes almost everything (" .. n3 .. " left)")
end
do -- second ball: fallen pins are swept, standing ones stay put
  local s = Sim.new(T.get("arcade"))
  s:throw({ x = 0.30, angle = 0, speed = 7, hook = 0 })
  local left = s:runToEnd(30)
  s:sweep()
  local cnt = 0
  for _, p in ipairs(s.pins) do if not p.gone then cnt = cnt + 1 end end
  ok(cnt == left and left > 0 and left < 10, "sweep keeps exactly the standing pins (" .. left .. ")")
  s:throw({ x = 0.45, angle = math.rad(-2.5), speed = 7, hook = 0 })
  ok(s:runToEnd(30) == left, "untouched pins stay standing for the second ball")
end

-- throw reader: a simulated Wii-style bowling swing through the real motion pipeline
local m = require("core.math")
local motion = require("core.motion")
local Throw = require("sports.bowling.throw")
local G = 9.80665
-- plays a swing: still upright at the chest, back, forward with a wrist twist, release.
-- rate = controller samples per second (Joy-Con 2 over Bluetooth sends about 33).
-- heading = which way the player faces (rad, left +); fwdTime = forward swing duration.
local function swingThrow(opts)
  local rate, heading = opts.rate or 200, opts.heading or 0
  local c = motion.new({ id = "sim", kind = "joycon2" })
  local tr = Throw.new(c, T.get("arcade"))
  local events = {}
  local turn = m.qaxis({ 0, 1, 0 }, heading)
  local pitch = math.rad(80)
  local twist = 0
  local function orient()
    -- arm swing about the player's left-right axis, then the wrist twist about the pointing axis
    return m.qmul(turn, m.qmul(m.qaxis({ 1, 0, 0 }, pitch), m.qaxis({ 0, 0, -1 }, twist)))
  end
  local dt = 1 / rate
  local prev = orient()
  local function step(dPitch, dTwist, held)
    pitch = pitch + dPitch * dt
    twist = twist + dTwist * dt
    local q = orient()
    -- body-frame rate that turns prev into q
    local d = m.qmul(m.qconj(prev), q)
    local ang = 2 * math.acos(m.clamp(d[1], -1, 1))
    local s = math.sqrt(math.max(1e-12, 1 - d[1] * d[1]))
    local w = ang > 1e-9 and { d[2] / s * ang / dt, d[3] / s * ang / dt, d[4] / s * ang / dt } or { 0, 0, 0 }
    prev = q
    c:setButton("b", held)
    c:feed(dt, w, m.qrot(m.qconj(q), { 0, G, 0 }))
    local ev = tr:update()
    if ev then events[#events + 1] = ev end
    c:endFrame()
  end
  for _ = 1, rate * 0.6 do step(0, 0, false) end                 -- settle the filter
  for _ = 1, rate * 0.5 do step(0, 0, true) end                  -- ready pose, button held
  local back = math.rad(-150) - pitch
  for _ = 1, rate * 0.6 do step(back / 0.6, 0, true) end         -- backswing
  local fwdT = opts.fwdTime or 0.25
  local fwd = math.rad(0) - pitch
  for _ = 1, math.floor(rate * fwdT) do step(fwd / fwdT, (opts.twist or 0) / fwdT, true) end
  step(0, 0, false)                                              -- let go
  for _ = 1, rate * 0.2 do step(0, 0, false) end
  return events, c
end
local function find(evs, kind) for _, e in ipairs(evs) do if e.type == kind then return e end end end
do
  local evs = swingThrow({ twist = 0 })
  local th = find(evs, "throw")
  ok(find(evs, "ready") ~= nil, "holding still at the chest counts as the ready pose")
  ok(th ~= nil, "a back-and-forward swing throws the ball")
  ok(th and th.power > 0.6, "a fast swing is a strong throw (" .. (th and string.format("%.2f", th.power) or "-") .. ")")
  ok(th and math.abs(th.hook) < 0.15, "no wrist twist, no hook")
  ok(th and math.abs(th.aim) < math.rad(1), "straight swing aims straight")
  local slow = find(swingThrow({ fwdTime = 0.7 }), "throw")
  ok(slow and th and slow.power < th.power - 0.2, "a slow swing is a weaker throw")
  local right = find(swingThrow({ twist = 1.2 }), "throw")
  ok(right and right.hook > 0.5, "twisting right while swinging hooks right")
  local left = find(swingThrow({ twist = -1.2 }), "throw")
  ok(left and left.hook < -0.5, "twisting left hooks left")
  local turned = find(swingThrow({ heading = math.rad(40) }), "throw")
  ok(turned and math.abs(turned.aim) < math.rad(1.5), "the ready pose re-centres: standing turned 40° still bowls straight")
  local jc2 = find(swingThrow({ rate = 33, twist = 1.0 }), "throw")
  ok(jc2 and jc2.power > 0.5 and jc2.hook > 0.3, "works at Joy-Con 2's 33 reports a second")
end
do -- letting go without swinging does not throw
  local c = motion.new({ id = "sim2" })
  local tr = Throw.new(c, T.get("arcade"))
  local got
  for i = 1, 120 do
    c:setButton("b", i > 20 and i < 70)
    c:feed(1 / 60, { 0, 0, 0 }, { 0, G, 0 })
    local ev = tr:update()
    if ev then got = got or ev.type == "throw" end
    c:endFrame()
  end
  ok(not got, "pressing and letting go without a swing never throws")
end
do -- stick fallback: hold B, stick back, stick forward
  local c = motion.new({ id = "pad", hasGyro = false })
  c.level = motion.STICK_POINTER
  local tr = Throw.new(c, T.get("arcade"))
  local got
  local seq = { { 0, false }, { 0, true }, { 0, true }, { -1, true }, { -1, true }, { 1, true }, { 1, true }, { 0, false } }
  for _, st in ipairs(seq) do
    c.stick = { 0.4, st[1] }
    c:setButton("b", st[2])
    c.t = c.t + 1 / 30
    local ev = tr:update()
    if ev and ev.type == "throw" then got = ev end
    c:endFrame()
  end
  ok(got and got.power > 0.5 and got.hook > 0.3, "stick: hold B, pull back, push forward throws (sideways = spin)")
end
do -- mouse flick
  local tr = Throw.new(motion.new({ id = "mouse", kind = "mouse" }), T.get("arcade"))
  local pts = {}
  for i = 0, 10 do pts[#pts + 1] = { x = 640, y = 400 + i * 20, t = i * 0.03 } end
  for i = 1, 6 do pts[#pts + 1] = { x = 640 + i * 6, y = 600 - i * 70, t = 0.3 + i * 0.02 } end
  local ev = tr:gesture(pts)
  ok(ev.type == "throw" and ev.power > 0.5 and ev.hook > 0, "mouse: drag down and flick up-right throws with a right hook")
  local ev2 = tr:gesture({ { x = 0, y = 0, t = 0 }, { x = 0, y = 5, t = 0.1 }, { x = 0, y = 2, t = 0.2 } })
  ok(ev2.type == "cancel", "mouse: a tiny wiggle doesn't throw")
end

print(string.format("%d passed, %d failed", passes, fails))
if fails > 0 then error("tests failed") end
