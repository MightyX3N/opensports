-- Bowling, played like Wii Sports bowling: line up with the stick / D-pad, hold the throw
-- button with the controller at your chest, swing, let go. Ten frames, one player.
-- Game rules, physics and throw reading are shared Lua (sports/bowling, core/); this file
-- only draws the lane and HUD and wires LÖVE input to them.
local m = require("core.math")
local motion = require("core.motion")
local Sim = require("sports.bowling.sim")
local Rules = require("sports.bowling.modes.standard")
local Throw = require("sports.bowling.throw")
local tuning = require("sports.bowling.tuning")
local setup = require("sports.bowling.setup")
local R3 = require("shells.love.render3d")
local U = require("shells.love.ui")
local lg = love.graphics
local C = U.col

local B = {}
local env -- { I, ctrl(), go(name), quit() }
local g    -- game state

local L = setup.lane
local START_Z = 2.3          -- where the bowler stands on the approach
local RELEASE_Z = 0.45

-- colours (our own palette from the design previews)
local COL = {
  wall = { 0.80, 0.86, 0.93 }, wallLow = { 0.72, 0.79, 0.87 }, floor = { 0.62, 0.69, 0.77 },
  lane = { 0.90, 0.72, 0.47 }, laneDark = { 0.84, 0.65, 0.41 }, approach = { 0.93, 0.79, 0.58 },
  board = { 0.80, 0.61, 0.38, 0.35 }, arrow = { 0.47, 0.30, 0.16 }, foul = { 0.20, 0.25, 0.32 },
  gutter = { 0.55, 0.62, 0.70 }, gutterIn = { 0.44, 0.51, 0.60 }, pit = { 0.16, 0.20, 0.27 },
  kick = { 0.67, 0.74, 0.82 }, mask = { 0.184, 0.490, 0.882 }, maskDark = { 0.106, 0.373, 0.722 },
  pin = { 0.98, 0.98, 0.97 }, stripe = { 0.886, 0.275, 0.247 },
  ball = { 0.184, 0.490, 0.882 }, ballDark = { 0.09, 0.30, 0.62 },
  skin = { 0.98, 0.82, 0.66 }, hair = { 0.33, 0.22, 0.14 }, shirt = { 0.184, 0.490, 0.882 },
  shirtDark = { 0.12, 0.38, 0.72 }, pants = { 0.15, 0.22, 0.33 }, shadow = { 0.10, 0.12, 0.18, 0.22 },
  aim = { 1, 1, 1, 0.85 },
}

-- pin mesh with extra rings where the red stripes start and end
local PIN_FACES
local function pinFaces()
  if PIN_FACES then return PIN_FACES end
  local prof = {}
  local cuts = {}
  for _, s in ipairs(setup.pinStripes) do cuts[#cuts + 1] = s[1]; cuts[#cuts + 1] = s[2] end
  local src = setup.pinProfile
  for i = 1, #src do
    prof[#prof + 1] = src[i]
    if src[i + 1] then
      for _, h in ipairs(cuts) do
        if h > src[i][1] and h < src[i + 1][1] then
          local t = (h - src[i][1]) / (src[i + 1][1] - src[i][1])
          prof[#prof + 1] = { h, src[i][2] + (src[i + 1][2] - src[i][2]) * t }
        end
      end
    end
  end
  table.sort(prof, function(a, b) return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2]) end)
  PIN_FACES = R3.lathe(prof, 10)
  for _, f in ipairs(PIN_FACES) do
    f.red = false
    for _, s in ipairs(setup.pinStripes) do if f.mid > s[1] and f.mid < s[2] then f.red = true end end
  end
  return PIN_FACES
end

----------------------------------------------------------------------------- controls text

-- what to call each control on the controller in hand
local function labels(c)
  local k, name = c.kind, c.name or ""
  if k == "mouse" then
    return { throw = "Drag down, then flick up", move = "Arrow keys", toggle = "Space", recentre = nil, pause = "Esc", mouse = true }
  end
  if k == "joycon2" or name:find("Joy%-Con") then
    local left = name:find("%(L%)")
    return { throw = left and "ZL" or "ZR", move = "Stick", toggle = "Press stick", recentre = left and "Up" or "X",
      pause = left and "−" or "+" }
  end
  if name:find("Pro Controller") then
    return { throw = "ZR", move = "Stick / D-pad", toggle = "A", recentre = "X", pause = "+" }
  end
  if c.dsu then return { throw = "R2", move = "D-pad", toggle = "Cross", recentre = "Triangle", pause = "Options" } end
  return { throw = "R2 / RT", move = "Stick / D-pad", toggle = "A", recentre = "Y", pause = "Start" }
end

local function instruction()
  local c = g.ctrl
  local lb = labels(c)
  if lb.mouse then return "Drag the mouse down, then flick it up to throw · sideways at the end = spin" end
  if c.level == motion.STICK_POINTER then
    return "Hold " .. lb.throw .. ", pull the stick back, then push it forward"
  end
  if c.level == motion.GESTURE then return "Use the mouse: drag down, then flick up" end
  if g.reader.phase == "wait" then return "Hold still…" end
  if g.reader.phase == "ready" or g.reader.phase == "swing" then return "Swing back and forward, let go of " .. lb.throw .. " to release" end
  return "Hold the controller upright in front of your chest and hold " .. lb.throw
end

-------------------------------------------------------------------------------- game flow

local function newGame()
  local c = env.ctrl()
  g = {
    tun = tuning.get("arcade"),
    rules = Rules.new(),
    ctrl = c,
    x = 0, angle = 0, mode = "move",
    phase = "aim", t = 0,
    bz = START_Z, walk = 0,
    msg = nil, msgT = 0, toast = nil, toastT = 0,
    cam = { pos = { 0, 2.25, START_Z + 4.6 }, target = { 0, 0, -9 } },
    pause = nil,
    standingBefore = 10,
  }
  g.sim = Sim.new(g.tun)
  g.reader = Throw.new(c, g.tun)
end

local function setCtrl(c)
  g.ctrl = c
  g.reader = Throw.new(c, g.tun)
end

local function toast(s) g.toast, g.toastT = s, 1.6 end

local function releaseBall(ev)
  local T = g.tun
  local speed = T.minSpeed + (T.maxSpeed - T.minSpeed) * ev.power
  local hand = g.x + 0.14 -- right hand
  local angle = g.angle + (ev.aim or 0)
  g.standingBefore = g.sim:standingCount()
  g.sim:throw({ x = m.clamp(hand, -L.halfWidth + 0.12, L.halfWidth - 0.12), angle = angle, speed = speed,
    hook = (ev.hook or 0) * T.maxHook })
  g.phase, g.t = "rolling", 0
  g.lastThrow = { speed = speed, hook = ev.hook or 0 }
  g.ctrl:rumble(0.15, 0.6)
end

local function afterTurn()
  local now = g.sim:standingCount()
  local down = g.standingBefore - now
  local res = g.rules:record(down)
  g.lastRes = res
  if res.strike then g.msg = "Strike!"
  elseif res.spare then g.msg = "Spare!"
  elseif g.sim.gutter and down == 0 then g.msg = "Gutter"
  elseif down == 0 then g.msg = "Miss"
  else g.msg = down == 1 and "1 pin" or (down .. " pins") end
  g.msgT = 0
  g.phase, g.t = "result", 0
end

local function nextBall()
  local res = g.lastRes
  if res.gameOver then g.phase, g.t, g.pauseSel = "over", 0, 1; return end
  if res.rerack then g.sim:rack() else g.sim:sweep() end
  if g.sim.ball then g.sim.world:removeBody(g.sim.ball); g.sim.ball = nil end
  g.sim.state = nil
  g.phase, g.t, g.bz, g.walk = "aim", 0, START_Z, 0
  g.reader:reset()
  g.snap = true -- cut straight back to the bowler instead of flying through the lane
end

------------------------------------------------------------------------------- update

function B.enter(e)
  env = e
  if not g then newGame() end
end

local function moveInput(dt)
  local c = g.ctrl
  local dir = 0
  if c.buttons.left or love.keyboard.isDown("left", "a") then dir = dir - 1 end
  if c.buttons.right or love.keyboard.isDown("right", "d") then dir = dir + 1 end
  if dir == 0 and math.abs(c.stick[1]) > 0.25 then dir = c.stick[1] end
  local T = g.tun
  if g.mode == "move" then
    g.x = m.clamp(g.x + dir * T.moveSpeed * dt, -T.moveRange, T.moveRange)
  else
    g.angle = m.clamp(g.angle - dir * T.turnSpeed * dt, -T.turnRange, T.turnRange)
  end
end

function B.update(dt)
  if not g then return end
  local c = g.ctrl
  if g.ctrl ~= env.ctrl() then setCtrl(env.ctrl()); c = g.ctrl end
  g.t = g.t + dt
  if g.toastT > 0 then g.toastT = g.toastT - dt end
  if g.msg then g.msgT = g.msgT + dt end

  -- picking up another controller and pressing a button hands it the game
  for _, o in ipairs(env.list()) do
    if o ~= c and o.kind ~= "mouse" and (o.pressed.b or o.pressed.a or o.pressed.sclick) and g.phase == "aim" then
      env.use(o); setCtrl(o); c = o
      toast("Playing with " .. o.name)
    end
  end
  if g.pause then return end
  if c.pressed.plus then B.openPause(); return end
  if c.pressed.recentre then c:recentre(); toast("Aim re-centred") end

  if g.phase == "aim" then
    if c.pressed.sclick then g.mode = g.mode == "move" and "turn" or "move" end
    if g.reader.phase == "idle" then moveInput(dt) end
    local ev = g.reader:update()
    if ev then
      if ev.type == "ready" then g.ctrl:rumble(0.05, 0.3)
      elseif ev.type == "swing" then g.walk = 0.001
      elseif ev.type == "throw" then releaseBall(ev)
      elseif ev.type == "cancel" and ev.reason == "weak" then toast("Swing a little harder")
      end
    end
    if g.walk > 0 and g.phase == "aim" then g.walk = math.min(1, g.walk + dt / 0.8) end
    g.bz = START_Z - (START_Z - RELEASE_Z) * (g.walk * g.walk * (3 - 2 * g.walk))
  elseif g.phase == "rolling" then
    if g.bz > RELEASE_Z then g.bz = math.max(RELEASE_Z, g.bz - dt * 3) end
    g.ballSpin = (g.ballSpin or 0) + dt
    if g.sim:update(dt) then afterTurn() end
  elseif g.phase == "result" then
    if g.t > 2.0 then g.msg = nil; nextBall() end
  end

  -- camera
  local tp, tt
  if g.phase == "aim" then
    tp, tt = { g.x * 0.5, 2.25, START_Z + 4.6 }, { g.x * 0.2, 0, -9 }
  elseif g.phase == "rolling" and g.sim.ball then
    local b = g.sim.ball.pos
    local z = math.max(b[3], -14.6)
    tp = { b[1] * 0.5, 1.15 - 0.3 * math.min(1, -z / 14.6), z + 3.4 }
    tt = { b[1] * 0.3, 0.15, math.max(z - 6, -18.9) }
  else
    tp, tt = { 0, 0.62, -15.2 }, { 0, 0.16, -18.8 }
  end
  local k = math.min(1, dt * (g.phase == "rolling" and 6 or 3))
  if g.snap then k, g.snap = 1, nil end
  for i = 1, 3 do
    g.cam.pos[i] = g.cam.pos[i] + (tp[i] - g.cam.pos[i]) * k
    g.cam.target[i] = g.cam.target[i] + (tt[i] - g.cam.target[i]) * k
  end
end

-------------------------------------------------------------------------------- pause / over

local PAUSE = { { "Resume", "resume" }, { "Restart", "restart" }, { "Controllers", "controllers" }, { "Quit", "quit" } }
local OVER = { { "Play again", "restart" }, { "Controllers", "controllers" }, { "Quit", "quit" } }

function B.openPause() g.pause, g.pauseSel = true, 1 end

local function menuAction(a)
  if a == "resume" then g.pause = nil
  elseif a == "restart" then newGame()
  elseif a == "controllers" then g.pause = nil; env.go("test")
  elseif a == "quit" then env.quit() end
end

-- menu navigation from app.lua (D-pad / keyboard / A / B)
function B.nav(nav)
  if not g then return end
  local list = g.pause and PAUSE or (g.phase == "over" and OVER or nil)
  if not list then
    if nav.b and not g.ctrl.buttons.b then B.openPause() end -- Esc / Back
    if nav.a and g.phase == "aim" and g.reader.phase == "idle" then g.mode = g.mode == "move" and "turn" or "move" end
    return
  end
  if nav.up then g.pauseSel = math.max(1, g.pauseSel - 1) end
  if nav.down then g.pauseSel = math.min(#list, g.pauseSel + 1) end
  if nav.a then menuAction(list[g.pauseSel][2]) end
  if nav.b and g.pause then g.pause = nil end
end

-------------------------------------------------------------------------------- drawing

local function drawSky(cam, W, H)
  lg.setColor(COL.wall); lg.rectangle("fill", 0, 0, W, H)
  -- horizon band behind the pins
  local _, hy = cam:project({ 0, 1.6, -21 })
  if hy then
    lg.setColor(COL.wallLow); lg.rectangle("fill", 0, hy, W, H - hy)
  end
end

local function quad(cam, a, b, c, d, col) cam:fill({ a, b, c, d }, col) end

local function drawLaneBed(cam, ox, dim)
  local hw, gw, gd = L.halfWidth, L.gutterWidth, L.gutterDepth
  local far, near = -L.deckEnd, L.approach
  local function col(c) return dim and { c[1] * 0.88, c[2] * 0.88, c[3] * 0.9 } or c end
  -- gutters (slightly below the lane)
  for _, s in ipairs({ -1, 1 }) do
    local x0, x1 = ox + s * hw, ox + s * (hw + gw)
    quad(cam, { x0, -gd * 0.3, 0 }, { x1, 0, 0 }, { x1, 0, far }, { x0, -gd * 0.3, far }, col(COL.gutter))
    quad(cam, { ox + s * (hw + gw * 0.25), -gd, 0 }, { ox + s * (hw + gw * 0.75), -gd, 0 },
      { ox + s * (hw + gw * 0.75), -gd, far }, { ox + s * (hw + gw * 0.25), -gd, far }, col(COL.gutterIn))
  end
  -- lane wood
  quad(cam, { ox - hw, 0, 0 }, { ox + hw, 0, 0 }, { ox + hw, 0, far }, { ox - hw, 0, far }, col(COL.lane))
  -- approach
  quad(cam, { ox - hw - gw, 0, near }, { ox + hw + gw, 0, near }, { ox + hw + gw, 0, 0 }, { ox - hw - gw, 0, 0 }, col(COL.approach))
  -- pin deck tint
  quad(cam, { ox - hw, 0.0005, -L.length + 0.5 }, { ox + hw, 0.0005, -L.length + 0.5 }, { ox + hw, 0.0005, far },
    { ox - hw, 0.0005, far }, col(COL.laneDark))
  if dim then return end
  -- boards every 5
  lg.setLineWidth(1)
  for i = -15, 15, 5 do
    local x = ox + i * L.boardWidth
    local p1x, p1y = cam:project({ x, 0, -0.2 })
    local p2x, p2y = cam:project({ x, 0, far + 0.6 })
    if p1x and p2x then lg.setColor(COL.board); lg.line(p1x, p1y, p2x, p2y) end
  end
  -- target arrows and dots
  local A = L.arrows
  for i, bd in ipairs(A.boards) do
    local x = ox + (bd - 20) * L.boardWidth
    local z = -A.dist - math.abs(i - 4) * 0.30
    cam:fill({ { x, 0.001, z - 0.2 }, { x + 0.022, 0.001, z }, { x - 0.022, 0.001, z } }, COL.arrow)
  end
  for _, bd in ipairs({ 3, 5, 8, 11, 14, 26, 29, 32, 35, 37 }) do
    local x = ox + (bd - 20) * L.boardWidth
    cam:fill({ { x - 0.008, 0.001, -L.dots.dist - 0.008 }, { x + 0.008, 0.001, -L.dots.dist - 0.008 },
      { x + 0.008, 0.001, -L.dots.dist + 0.008 }, { x - 0.008, 0.001, -L.dots.dist + 0.008 } }, COL.arrow)
  end
  -- foul line
  quad(cam, { ox - hw - gw, 0.001, 0.02 }, { ox + hw + gw, 0.001, 0.02 }, { ox + hw + gw, 0.001, -0.02 },
    { ox - hw - gw, 0.001, -0.02 }, COL.foul)
end

-- the far end: pit, back wall, kickbacks and the masking panel above the pins
local function drawPinEnd(cam, ox, dim)
  local k = L.kickback
  local f = dim and 0.88 or 1
  local function col(c) return { c[1] * f, c[2] * f, c[3] * f } end
  quad(cam, { ox - k, -L.pitDepth, -L.deckEnd }, { ox + k, -L.pitDepth, -L.deckEnd }, { ox + k, -L.pitDepth, -L.pitBack },
    { ox - k, -L.pitDepth, -L.pitBack }, COL.pit)
  quad(cam, { ox - k, -L.pitDepth, -L.pitBack }, { ox + k, -L.pitDepth, -L.pitBack }, { ox + k, 0.9, -L.pitBack },
    { ox - k, 0.9, -L.pitBack }, col({ 0.24, 0.29, 0.37 }))
  for _, s in ipairs({ -1, 1 }) do
    quad(cam, { ox + s * k, -L.pitDepth, -L.kickbackStart }, { ox + s * k, 0.55, -L.kickbackStart },
      { ox + s * k, 0.55, -L.pitBack }, { ox + s * k, -L.pitDepth, -L.pitBack }, col(COL.kick))
  end
end

local function drawMask(cam, ox, dim)
  local k = L.kickback + 0.2
  local f = dim and 0.85 or 1
  local z = -L.kickbackStart - 0.4
  quad(cam, { ox - k, 0.78, z }, { ox + k, 0.78, z }, { ox + k, 1.05, z }, { ox - k, 1.05, z },
    { COL.mask[1] * f, COL.mask[2] * f, COL.mask[3] * f })
  quad(cam, { ox - k, 0.78, z }, { ox + k, 0.78, z }, { ox + k, 0.81, z }, { ox - k, 0.81, z }, COL.maskDark)
end

-- pins as shaded lathe faces into the painter's list
local LOW_FACES
local function addPin(list, cam, pos, q, low)
  local faces = pinFaces()
  if low then
    LOW_FACES = LOW_FACES or R3.lathe(setup.pinProfile, 6)
    faces = LOW_FACES
  end
  local base = m.sub(pos, m.qrot(q, { 0, setup.pinCOM, 0 }))
  for _, f in ipairs(faces) do
    local wn = m.qrot(q, f.n)
    local w1 = m.add(base, m.qrot(q, f.pts[1]))
    if cam:facing(w1, wn) then
      local wp = { w1 }
      for i = 2, #f.pts do wp[i] = m.add(base, m.qrot(q, f.pts[i])) end
      local flat, d = cam:poly(wp)
      if flat then list:poly(flat, d, R3.shade(f.red and COL.stripe or COL.pin, wn, 0.68)) end
    end
  end
end


local function shadowAt(list, cam, x, z, r, y)
  local pts = {}
  for i = 0, 11 do
    local a = i / 12 * math.pi * 2
    pts[#pts + 1] = { x + math.cos(a) * r, (y or 0) + 0.002, z + math.sin(a) * r * 0.9 }
  end
  local flat = cam:poly(pts)
  if flat then lg.setColor(COL.shadow); lg.polygon("fill", flat) end
end

local HOLES = { m.norm({ 0.0, 0.6, -0.8 }), m.norm({ -0.18, 0.75, -0.62 }), m.norm({ 0.18, 0.75, -0.62 }) }
local function addBall(list, cam, pos, q, r)
  local sx, sy, d = cam:project(pos)
  if not sx then return end
  local pr = cam.focal * r / d
  list:fn(d, function()
    lg.setColor(COL.ballDark); lg.circle("fill", sx, sy, pr, 40)
    lg.setColor(COL.ball); lg.circle("fill", sx - pr * 0.08, sy - pr * 0.08, pr * 0.9, 40)
    lg.setColor(1, 1, 1, 0.55); lg.ellipse("fill", sx - pr * 0.38, sy - pr * 0.42, pr * 0.22, pr * 0.14)
    for _, h in ipairs(HOLES) do
      local wn = m.qrot(q, h)
      local wp = m.add(pos, m.scale(wn, r))
      if cam:facing(wp, wn) then
        local hx, hy = cam:project(wp)
        if hx then lg.setColor(0.05, 0.08, 0.15); lg.circle("fill", hx, hy, pr * 0.11, 12) end
      end
    end
  end)
end

-- the bowler, seen from behind: a "Bean" avatar (big head, bean body, floating hands)
local function addBowler(list, cam, x, z, holdingBall)
  local function at(p) return cam:project(p) end
  local hx, hy, d = at({ x, 1.42, z })
  if not hx then return end
  local s = cam.focal / d
  list:fn(d, function()
    local bx, by = at({ x, 0.95, z })
    local fx, fy = at({ x, 0.0, z })
    -- shadow
    lg.setColor(COL.shadow); lg.ellipse("fill", fx, fy, 0.32 * s, 0.07 * s)
    -- legs
    lg.setColor(COL.pants)
    lg.rectangle("fill", bx - 0.17 * s, by, 0.13 * s, fy - by - 0.02 * s, 0.06 * s)
    lg.rectangle("fill", bx + 0.04 * s, by, 0.13 * s, fy - by - 0.02 * s, 0.06 * s)
    -- body (bean)
    lg.setColor(COL.shirtDark); lg.ellipse("fill", bx, by - 0.22 * s, 0.25 * s, 0.34 * s, 32)
    lg.setColor(COL.shirt); lg.ellipse("fill", bx - 0.02 * s, by - 0.24 * s, 0.22 * s, 0.31 * s, 32)
    -- head from behind: hair
    lg.setColor(COL.skin); lg.circle("fill", hx - 0.23 * s, hy + 0.02 * s, 0.06 * s)
    lg.circle("fill", hx + 0.23 * s, hy + 0.02 * s, 0.06 * s)
    lg.setColor(COL.hair); lg.circle("fill", hx, hy, 0.25 * s, 40)
    -- left hand
    local lx, ly = at({ x - 0.36, 0.95, z - 0.05 })
    lg.setColor(COL.skin); lg.circle("fill", lx, ly, 0.075 * s, 20)
  end)
end

local function drawBallInHand(list, cam, x, z)
  -- the arm follows the controller: pointing down = hanging, level = forward
  local arm = g.reader.arm or -math.pi / 2
  local rp = g.reader.phase
  local hand
  if g.ctrl.kind == "mouse" and g.drag then
    local p = g.drag[#g.drag]
    local dy = p.y - g.drag[1].y
    arm = -math.pi / 2 - m.clamp(dy / 200, -1.2, 1.4)
    rp = "swing"
  end
  if rp == "swing" or (rp == "ready" and arm < 0.4) then
    local a = m.clamp(arm, -math.pi * 0.95, 0.6)
    hand = { x + 0.2, 1.2 + math.sin(a) * 0.62, z - math.cos(a) * 0.62 }
  else
    hand = { x + 0.30, 1.0, z - 0.18 }
  end
  local q = m.qid()
  addBall(list, cam, hand, q, g.tun.ballRadius)
  local sx, sy, d = cam:project(m.add(hand, { 0.06, -0.02, 0.09 }))
  if sx then
    list:fn(d - 0.01, function()
      lg.setColor(COL.skin); lg.circle("fill", sx, sy, cam.focal * 0.07 / d, 20)
    end)
  end
end

local function drawAimLine(cam)
  -- dotted throw line with an arrow head, like the original's guide on the lane
  local x0 = m.clamp(g.x + 0.14, -L.halfWidth + 0.12, L.halfWidth - 0.12)
  local dir = { -math.sin(g.angle), 0, -math.cos(g.angle) }
  local pulse = 0.6 + 0.4 * math.sin(love.timer.getTime() * 5)
  for i = 0, 15 do
    local dist = 2.0 + i * 0.6
    local p = { x0 + dir[1] * dist, 0.003, dir[3] * dist }
    local sx, sy, d = cam:project(p)
    if sx and math.abs(p[1]) < L.halfWidth then
      local rr = cam.focal * 0.022 / d
      lg.setColor(1, 1, 1, 0.75 * pulse)
      lg.ellipse("fill", sx, sy, rr, rr * 0.45)
    end
  end
  local tip = 2.0 + 16 * 0.6
  local side = { -dir[3], 0, dir[1] }
  local p = { x0 + dir[1] * tip, 0.004, dir[3] * tip }
  cam:fill({ m.add(p, m.scale(dir, 0.5)), m.add(p, m.scale(side, 0.1)), m.add(p, m.scale(side, -0.1)) },
    { 1, 1, 1, 0.8 * pulse })
end

function B.draw3d()
  if not g then return end
  local W, H = lg.getDimensions()
  local cam = R3.camera(g.cam.pos, g.cam.target, math.rad(46), W, H)
  drawSky(cam, W, H)
  -- room floor
  quad(cam, { -12, -0.01, 8 }, { 12, -0.01, 8 }, { 12, -0.01, -21 }, { -12, -0.01, -21 }, COL.floor)
  -- neighbouring lanes (static), outermost first so nearer ones paint over them
  for _, ox in ipairs({ -3.6, 3.6, -1.8, 1.8 }) do
    drawPinEnd(cam, ox, true)
    drawLaneBed(cam, ox, true)
    local nl = R3.list()
    for _, spot in ipairs(setup.pins) do addPin(nl, cam, { ox + spot[1], setup.pinCOM, spot[2] }, m.qid(), true) end
    nl:draw()
    drawMask(cam, ox, true)
  end
  drawPinEnd(cam, 0)
  drawLaneBed(cam, 0)
  if g.phase == "aim" and g.reader.phase ~= "swing" then drawAimLine(cam) end

  local list = R3.list()
  local sim = g.sim
  for _, p in ipairs(sim.pins) do
    if not p.gone then
      local b = p.body
      if b.pos[2] > -0.1 then shadowAt(list, cam, b.pos[1], b.pos[3], 0.07) end
      addPin(list, cam, b.pos, b.q)
    end
  end
  if sim.ball and g.phase ~= "aim" then
    local b = sim.ball
    if b.pos[2] > -0.05 and not sim.gutter then shadowAt(list, cam, b.pos[1], b.pos[3], 0.1) end
    addBall(list, cam, b.pos, b.q, g.tun.ballRadius)
  end
  local bx = g.x
  addBowler(list, cam, bx, g.bz, g.phase == "aim")
  if g.phase == "aim" then drawBallInHand(list, cam, bx, g.bz) end
  list:draw()
  drawMask(cam, 0)
end

-------------------------------------------------------------------------------- HUD

local function scorecard(x, y, big)
  local rules = g.rules
  local totals = rules:totals()
  local cw, ch = big and 84 or 62, big and 92 or 66
  local w = 120 + cw * 9 + cw * 1.5
  U.rect(x, y + 4, w, ch, 18, C.shadow)
  U.rect(x, y, w, ch, 18, C.card)
  U.text("P1", x + 16, y + (big and 18 or 10), big and 26 or 20)
  U.text(tostring(rules:total()), x + 16, y + (big and 52 or 38), big and 20 or 15, C.sub)
  for fi = 1, 10 do
    local fx = x + 120 + (fi - 1) * cw
    local fw = fi == 10 and cw * 1.5 or cw
    local cur = fi == rules.frame and not rules.over
    if cur then U.rect(fx + 2, y + 4, fw - 4, ch - 8, 10, C.blueSoft) end
    lg.setColor(C.line); lg.setLineWidth(2); lg.line(fx, y + 10, fx, y + ch - 10)
    U.text(tostring(fi), fx + 6, y + 6, 11, C.sub)
    local marks = rules:marks(fi)
    local slots = fi == 10 and 3 or 2
    local sw = fw / (slots + 0.4)
    for i = 1, slots do
      local mk = marks[i]
      if mk then
        local mx = fx + fw - (slots - i + 1) * sw
        U.text(mk, mx, y + (big and 10 or 6), big and 18 or 15, (mk == "X" or mk == "/") and C.blue or C.ink, "center", sw)
      end
    end
    if totals[fi] then U.text(tostring(totals[fi]), fx, y + ch * 0.5, big and 24 or 18, C.ink, "center", fw) end
  end
  lg.setLineWidth(1)
  return w
end

local function pinDiagram(x, y)
  U.rect(x, y + 4, 150, 130, 18, C.shadow)
  U.rect(x, y, 150, 130, 18, C.card)
  local mask = g.sim:standingMask()
  for i, spot in ipairs(setup.pins) do
    local px = x + 75 + spot[1] / 0.3048 * 32
    local py = y + 104 + (spot[2] + L.length) / 0.264 * 25
    local st = mask[i]
    lg.setColor(st and C.ink or C.line)
    lg.circle("fill", px, py, 11)
    if st then lg.setColor(1, 1, 1); lg.circle("fill", px, py, 4) end
  end
end

local function keyChip(x, y, key, text)
  local kw = math.max(36, U.textWidth(key, 14) + 20)
  lg.setColor(C.ink); lg.rectangle("fill", x, y, kw, 30, 15, 15)
  U.text(key, x, y + 7, 14, C.card, "center", kw)
  U.text(text, x + kw + 8, y + 6, 15, C.ink)
  return kw + 16 + U.textWidth(text, 15)
end

local function drawMenu(list, title, sub)
  lg.setColor(0.106, 0.165, 0.227, 0.45); lg.rectangle("fill", -2000, -2000, 6000, 6000)
  local w, h = 420, 120 + #list * 62
  local x, y = 640 - w / 2, 360 - h / 2
  U.rect(x, y + 6, w, h, 28, C.shadow)
  U.rect(x, y, w, h, 28, C.card)
  U.text(sub, x + 30, y + 26, 13, C.sub)
  U.text(title, x + 30, y + 44, 34)
  g.menuHits = {}
  for i, it in ipairs(list) do
    local by = y + 100 + (i - 1) * 62
    g.menuHits[i] = U.pill(it[1], x + 30, by, i == 1 and "primary" or nil, g.pauseSel == i, w - 60)
    g.menuHits[i].action = it[2]
  end
end

function B.drawHud()
  if not g then return end
  local c = g.ctrl
  local lb = labels(c)
  if g.phase ~= "over" then
    scorecard(24, 18)
    pinDiagram(1106, 18)
    U.text(string.format("FRAME %d · BALL %d", math.min(g.rules.frame, 10), g.rules.ball), 26, 96, 13, C.sub)
  end
  -- controller chip
  local nw = U.textWidth(c.name, 13) + 26
  U.rect(24, 118, nw, 28, 14, C.card)
  U.text(c.name, 24, 124, 13, C.ink, "center", nw)

  if g.phase == "aim" and not g.pause then
    -- move / turn helper (bottom left), like the original's little control card
    local y = 560
    U.rect(24, y, 300, 108, 20, C.card)
    U.text(g.mode == "move" and "MOVING" or "TURNING", 40, y + 12, 12, C.blue)
    keyChip(40, y + 32, lb.move, g.mode == "move" and "Move" or "Turn")
    keyChip(40, y + 68, lb.toggle, g.mode == "move" and "Switch to turn" or "Switch to move")
    if lb.recentre then
      U.rect(24, y - 44, 220, 36, 18, C.card)
      keyChip(30, y - 41, lb.recentre, "Re-centre aim")
    end
    -- instruction belt (bottom)
    local txt = instruction()
    local tw = U.textWidth(txt, 18) + 60
    U.rect(640 - tw / 2 + 170, 628, tw, 52, 26, C.blue)
    U.text(txt, 640 - tw / 2 + 170, 644, 18, C.card, "center", tw)
  end

  if g.msg then
    local t = g.msgT
    local s = t < 0.25 and (0.6 + 1.6 * t) or 1
    local big = (g.msg == "Strike!" or g.msg == "Spare!")
    local size = big and 96 or 64
    lg.push()
    local cy = 210
    lg.translate(640, cy); lg.scale(s); lg.translate(-640, -cy)
    U.text(g.msg, 0 + 4, cy - size / 2 + 5, size, C.shadow, "center", 1280)
    U.text(g.msg, 0, cy - size / 2, size, big and C.blue or C.ink, "center", 1280)
    lg.pop()
    if g.lastThrow then
      local sp = string.format("%.0f km/h", g.lastThrow.speed * 3.6)
      local sw = U.textWidth(sp, 16) + 32
      U.rect(640 - sw / 2, cy + size / 2 + 14, sw, 32, 16, C.card)
      U.text(sp, 640 - sw / 2, cy + size / 2 + 21, 16, C.ink, "center", sw)
    end
  end
  if g.toastT > 0 and g.toast then
    local tw = U.textWidth(g.toast, 16) + 40
    U.rect(640 - tw / 2, 170, tw, 40, 20, C.ink)
    U.text(g.toast, 640 - tw / 2, 180, 16, C.card, "center", tw)
  end
  if g.phase == "over" then
    lg.setColor(0.106, 0.165, 0.227, 0.35); lg.rectangle("fill", -2000, -2000, 6000, 6000)
    U.text("GAME OVER", 0, 120, 15, C.card, "center", 1280)
    U.text(tostring(g.rules:total()), 0, 140, 72, C.card, "center", 1280)
    local w = 120 + 84 * 10.5
    scorecard(640 - w / 2, 250, true)
    g.menuHits = {}
    local x = 640 - (#OVER * 220 + (#OVER - 1) * 16) / 2
    for i, it in ipairs(OVER) do
      g.menuHits[i] = U.pill(it[1], x + (i - 1) * 236, 400, i == 1 and "primary" or nil, g.pauseSel == i, 220)
      g.menuHits[i].action = it[2]
    end
  elseif g.pause then
    drawMenu(PAUSE, "Paused", string.format("BOWLING · FRAME %d", math.min(g.rules.frame, 10)))
  end
end

-------------------------------------------------------------------------------- mouse

function B.mousepressed(dx, dy)
  if not g then return end
  if g.menuHits and (g.pause or g.phase == "over") then
    for _, h in ipairs(g.menuHits) do if U.hit(h, dx, dy) then menuAction(h.action); return true end end
    return true
  end
  if g.phase == "aim" then
    g.drag = { { x = dx, y = dy, t = love.timer.getTime() } }
    if g.ctrl.kind ~= "mouse" then env.useMouse(); setCtrl(env.ctrl()) end
    g.walk = 0.001
    return true
  end
end
function B.mousemoved(dx, dy)
  if g and g.drag then g.drag[#g.drag + 1] = { x = dx, y = dy, t = love.timer.getTime() } end
end
function B.mousereleased()
  if not g or not g.drag then return end
  local ev = g.reader:gesture(g.drag)
  g.drag = nil
  if ev.type == "throw" and g.phase == "aim" then releaseBall(ev)
  else
    g.walk = 0
    if g.phase == "aim" then toast("Drag down, then flick up quickly") end
  end
end

-- for tests: peek at the game state
function B.state() return g end

return B
