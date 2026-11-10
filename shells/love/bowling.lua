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
local settings = require("shells.love.settings")
local setup = require("sports.bowling.setup")
local gfx = require("shells.love.gfx3d")
local Scene = require("shells.love.bowling_scene")
local Char = require("shells.love.character")
local U = require("shells.love.ui")
local Snd = require("shells.love.sound")
local lg = love.graphics
local C = U.col

local B = {}
local env -- { I, ctrl(), go(name), quit() }
local g    -- game state
local bowlerUpdate -- the bowler's animation (with the drawing code below)

local L = setup.lane
local START_Z = 2.3          -- where the bowler stands on the approach
local RELEASE_Z = 0.45

-- the bowler: a CC0 KayKit character (assets/characters/robot), 1.45 m tall
local ROBOT_DIR = "assets/characters/robot"
local ROBOT_ANIMS = { "anim_general.glb", "anim_movementbasic.glb", "anim_simulation.glb" }
local ROBOT_SCALE = 1.45 / 2.19
local REACT_AT = 1.4        -- seconds of looking at the pins before the bowler reacts

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

-------------------------------------------------------------------------------- sound

-- Sound is placed in the world: the ears are at the camera, every hit plays where it
-- happened and the ball's roll moves with the ball.
-- The pin crash is a real recorded strike, started on the ball's first hit on a pin. Its
-- volume then follows how many pins are actually moving, so a strike gets the whole crash
-- and a one-pin hit only a knock. While a big crash plays, the single pin hits it already
-- contains are left out; everything else gets single recorded clacks.
local HIT = { -- sound, volume at full strength, pitch
  ball_drop = { "bowling/ball_drop", 0.9, 1.0 },
  ball_pin = { "bowling/ball_pin", 1.0, 1.0 },
  pin_pin = { "bowling/clack", 0.8, 1.0 },
  pin_floor = { "bowling/clack", 0.55, 0.9 },
  pin_wall = { "bowling/pin_wall", 0.6, 1.0 },
  pit = { "bowling/pit", 0.75, 1.0 },
  pin_pit = { "bowling/pin_pit", 0.4, 1.0 },
}
local CRASH_COVERS = { ball_pin = true, pin_pin = true, pin_floor = true }
local MAX_HITS_PER_FRAME = 6
local AMBIENCE = 0.3

-- how loud the crash should be for this many moving pins
local function crashLevel(n)
  if n >= 8 then return 1 end
  return 0.15 + 0.85 * math.max(0, (n - 1) / 7) ^ 1.2
end

local function movingPins()
  local n = 0
  for _, p in ipairs(g.sim.pins) do
    if not p.gone and (p.body.awake or not g.sim:isStanding(p)) then n = n + 1 end
  end
  return n
end

local function playHits(dt)
  local ev = g.sim:takeEvents()
  local cr = g.crash
  -- the crash follows the pins
  if cr then
    local age = g.sim.t - cr.t
    if age < 0.5 then cr.target = crashLevel(movingPins()) end
    cr.level = cr.level + (cr.target - cr.level) * math.min(1, dt * 10)
    Snd.setVolume(cr.src, cr.vol * cr.level)
    if age > 1.6 then g.crash, cr = nil, nil end
  end
  if #ev == 0 then return end
  table.sort(ev, function(a, b) return a.level * HIT[a.kind][2] > b.level * HIT[b.kind][2] end)
  local played = 0
  for _, e in ipairs(ev) do
    if played >= MAX_HITS_PER_FRAME then break end
    local pos = { e.x, math.max(0.05, e.y or 0.1), e.z }
    local lv = e.level ^ 0.8
    if e.kind == "ball_pin" and not g.crashed then
      -- first contact: start the crash where the pins are
      g.crashed = true
      local vol = 0.55 + 0.45 * lv
      local level = math.max(0.6, crashLevel(movingPins()))
      local src = Snd.play("bowling/crash", vol * level, 0.96 + love.math.random() * 0.08,
        { e.x, 0.3, e.z }, { dry = true, near = 9 })
      g.crash = { src = src, t = g.sim.t, vol = vol, level = level, target = level }
      cr = g.crash
      played = played + 1
    elseif not (cr and cr.level > 0.5 and CRASH_COVERS[e.kind]) then
      local h = HIT[e.kind]
      local vol = h[2] * (0.15 + 0.85 * lv)
      if cr and cr.level > 0.5 then vol = vol * 0.6 end
      -- harder hits a touch higher, plus a little randomness so hits don't repeat
      local pitch = h[3] * (0.95 + 0.06 * lv) * (0.95 + love.math.random() * 0.1)
      Snd.play(h[1], vol, pitch, pos)
      played = played + 1
    end
  end
end

local rollVol, gutterVol = 0, 0
local function rollingSound(dt)
  local what, speed, x = nil, 0, 0
  if g.phase == "rolling" and not g.pause then what, speed, x = g.sim:ballSound() end
  speed = speed or 0
  local k = math.min(1, speed / 9)
  local wantRoll = what == "lane" and (0.3 + 0.7 * k) or 0
  local wantGutter = what == "gutter" and (0.3 + 0.7 * k) * 0.85 or 0
  -- follow quickly but never jump (jumps click)
  local a = math.min(1, dt * 12)
  rollVol = rollVol + (wantRoll - rollVol) * a
  gutterVol = gutterVol + (wantGutter - gutterVol) * a
  local b = g.sim.ball
  local pos = b and { b.pos[1], 0.1, b.pos[3] } or nil
  Snd.loop("bowling/roll_loop", rollVol * 0.8, 0.85 + 0.3 * k, pos)
  Snd.loop("bowling/roll_gutter_loop", gutterVol * 0.7, 0.85 + 0.3 * k, pos)
  Snd.loop("bowling/ambience_loop", AMBIENCE)
  Snd.listener(g.cam.pos, g.cam.target)
end

-- the crowd and a short tune for the result
local function resultSound(res, down)
  if res.strike then
    Snd.play("bowling/jingle_strike", 0.7)
    Snd.play("bowling/crowd_strike", 0.6)
  elseif res.spare then
    Snd.play("bowling/jingle_spare", 0.65)
    Snd.play("bowling/crowd_spare", 0.5)
  elseif down == 0 and g.sim.gutter then
    Snd.play("bowling/jingle_gutter", 0.55)
  end
end

-- leaving the game (menus, sport select): quiet the hall
function B.silence()
  rollVol, gutterVol = 0, 0
  Snd.loop("bowling/roll_loop", 0)
  Snd.loop("bowling/roll_gutter_loop", 0)
  Snd.loop("bowling/ambience_loop", 0)
end

-------------------------------------------------------------------------------- game flow

local function newGame(opts)
  opts = opts or (g and g.opts) or {}
  local c = env.ctrl()
  g = {
    opts = opts,
    tun = tuning.get(opts.physics or "arcade"),
    rules = Rules.new(),
    ctrl = c,
    x = 0, angle = 0, mode = "move",
    phase = "aim", t = 0,
    bz = START_Z, walk = 0,
    msg = nil, msgT = 0, toast = nil, toastT = 0,
    cam = { pos = { 0, 2.35, START_Z + 5.6 }, target = { 0, 0.05, -8 }, fov = 36 },
    pause = nil,
    standingBefore = 10,
  }
  g.sim = Sim.new(g.tun)
  g.reader = Throw.new(c, g.tun)
  g.bowler = Char.new(Char.load(ROBOT_DIR, "robot.glb", ROBOT_ANIMS), ROBOT_SCALE)
  g.bowler:play("Idle_A")
  g.armA, g.armW, g.holdW = -math.pi / 2, 0, 0
  Snd.preload({ "bowling/ball_drop", "bowling/ball_pin", "bowling/crash", "bowling/clack", "bowling/pin_wall",
    "bowling/pit", "bowling/pin_pit", "bowling/crowd_strike", "bowling/crowd_spare", "bowling/jingle_strike",
    "bowling/jingle_spare", "bowling/jingle_gutter", "bowling/jingle_gameover" })
end

local function setCtrl(c)
  g.ctrl = c
  g.motionAlive, g.gyroSeen = nil, 0
  g.reader = Throw.new(c, g.tun)
end

local function toast(s) g.toast, g.toastT = s, 1.6 end

-- throw log next to the game (only in the packaged game): what the controller did from
-- the ready pose to the release, to tune the throw on real swings
function B.logThrow(ev, speed, angle)
  if not (love.filesystem.isFused and love.filesystem.isFused()) then return end
  local ok, err = pcall(function()
    local dir = love.filesystem.getSourceBaseDirectory()
    local f = io.open(dir .. "/throwlog.txt", "a")
    if not f then return end
    local inf = ev.info or {}
    f:write(string.format("throw %s ctrl=%s x=%.3f setAngle=%.4f aim=%.4f hook=%.3f power=%.3f speed=%.2f peak=%.3f twist=%.4f releaseYaw=%.4f\n",
      os.date("%H:%M:%S"), g.ctrl.name or "?", g.x, g.angle, ev.aim or 0, ev.hook or 0, ev.power or 0, speed,
      inf.peak or 0, inf.twist or 0, inf.releaseYaw or 0))
    for _, t in ipairs(inf.trace or {}) do
      f:write(string.format("  %.4f g %.3f %.3f %.3f q %.4f %.4f %.4f %.4f pr %.3f\n", t[1], t[2], t[3], t[4], t[5], t[6], t[7], t[8], t[9]))
    end
    f:close()
  end)
end

local function releaseBall(ev)
  local T = g.tun
  local speed = T.minSpeed + (T.maxSpeed - T.minSpeed) * ev.power
  local hand = g.x + 0.14 -- right hand
  local angle = g.angle + (ev.aim or 0)
  g.standingBefore = g.sim:standingCount()
  g.sim:throw({ x = m.clamp(hand, -L.halfWidth + 0.12, L.halfWidth - 0.12), angle = angle, speed = speed,
    hook = (ev.hook or 0) * T.maxHook })
  g.phase, g.t = "rolling", 0
  g.crash, g.crashed = nil, nil
  g.lastThrow = { speed = speed, hook = ev.hook or 0, aim = ev.aim or 0 }
  B.logThrow(ev, speed, angle)
  g.ctrl:rumble(0.15, 0.6)
end

local function afterTurn()
  local now = g.sim:standingCount()
  local down = g.standingBefore - now
  local res = g.rules:record(down)
  resultSound(res, down)
  g.lastRes = res
  if res.strike then g.msg = "Strike!"
  elseif res.spare then g.msg = "Spare!"
  elseif g.sim.gutter and down == 0 then g.msg = "Gutter"
  elseif down == 0 then g.msg = "Miss"
  else g.msg = down == 1 and "1 pin" or (down .. " pins") end
  g.msgT = 0
  g.phase, g.t = "result", 0
  -- the bowler reacts to a strike, spare or a gutter ball
  g.react = (res.strike or res.spare) and "Cheering" or (down == 0 and "Hit_B" or nil)
  g.reacting = nil
end

local function nextBall()
  local res = g.lastRes
  if res.gameOver then
    g.phase, g.t, g.pauseSel = "over", 0, 1
    Snd.play("bowling/jingle_gameover", 0.7)
    return
  end
  if res.rerack then g.sim:rack() else g.sim:sweep() end
  if g.sim.ball then g.sim.world:removeBody(g.sim.ball); g.sim.ball = nil end
  g.sim.state = nil
  g.phase, g.t, g.bz, g.walk = "aim", 0, START_Z, 0
  g.react, g.reacting = nil, nil
  g.reader:reset()
  g.snap = true -- cut straight back to the bowler instead of flying through the lane
end

------------------------------------------------------------------------------- update

function B.enter(e)
  env = e
  if not g then newGame() end
end

-- a fresh game from the mode screen (opts.physics = "arcade" | "realistic")
function B.newGame(e, opts)
  env = e
  newGame(opts)
end

-- back from Controllers / Settings opened from the pause menu: carry on playing
function B.resume() if g then g.pause = nil end end

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
  -- what the controller is actually sending (for the status strip and the level fix)
  local gmag = 0
  for _, h in ipairs(c.history or {}) do
    if h.t > (c.t or 0) - 0.5 and h.gyro then gmag = math.max(gmag, m.len(h.gyro)) end
  end
  g.gyroSeen = math.max(gmag, (g.gyroSeen or 0) * math.max(0, 1 - dt * 2))
  if gmag > 0.15 then g.motionAlive = true end
  -- a controller that sends motion always bowls with full motion here, whatever level an
  -- older motion check saved for it (not saved, only for this game)
  if c.kind ~= "mouse" and c.hasGyro and g.motionAlive and c.level ~= motion.FULL and g.reader.phase == "idle" then
    c.level = motion.FULL
    toast("Using full motion")
  end
  -- swing strength setting: how fast the arm must come forward for the fastest ball
  Throw.PEAK_FAST = ({ light = 16, normal = 22, strong = 28 })[settings.get("swing")] or 22
  rollingSound(dt)
  if g.pause then return end
  if c.pressed.plus then B.openPause(); return end
  if c.pressed.recentre then c:recentre(); toast("Aim re-centred") end

  if g.phase == "aim" then
    if c.pressed.sclick then g.mode = g.mode == "move" and "turn" or "move"; Snd.ui("toggle") end
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
    local done = g.sim:update(dt)
    playHits(dt)
    if done then afterTurn() end
  elseif g.phase == "result" then
    local len = g.react and (REACT_AT + (g.react == "Cheering" and 1.9 or 1.5)) or 2.0
    if g.t > len then g.msg = nil; nextBall() end
  end
  bowlerUpdate(dt)

  -- camera
  local tp, tt
  local fov = 38
  if g.phase == "aim" then
    tp, tt, fov = { g.x * 0.5, 2.35, START_Z + 5.6 }, { g.x * 0.2, 0.05, -8 }, 36
  elseif g.phase == "result" and g.react and g.t >= REACT_AT then
    -- cut to the bowler, seen from the lane, for the reaction
    if not g.reactCam then g.reactCam, g.snap = true, true end
    tp, tt, fov = { g.x - 0.9, 1.25, g.bz - 4.6 }, { g.x, 1.12, g.bz }, 34
  elseif g.phase == "rolling" and g.sim.ball then
    local b = g.sim.ball.pos
    local z = math.max(b[3], -14.6)
    tp = { b[1] * 0.5, 1.15 - 0.3 * math.min(1, -z / 14.6), z + 3.4 }
    tt = { b[1] * 0.3, 0.15, math.max(z - 6, -18.9) }
  else
    tp, tt = { 0, 0.62, -15.2 }, { 0, 0.16, -18.8 }
  end
  if not (g.phase == "result" and g.react and g.t >= REACT_AT) then g.reactCam = nil end
  local k = math.min(1, dt * (g.phase == "rolling" and 6 or 3))
  if g.snap then k, g.snap = 1, nil end
  g.cam.fov = g.cam.fov + (fov - g.cam.fov) * k
  for i = 1, 3 do
    g.cam.pos[i] = g.cam.pos[i] + (tp[i] - g.cam.pos[i]) * k
    g.cam.target[i] = g.cam.target[i] + (tt[i] - g.cam.target[i]) * k
  end
end

-------------------------------------------------------------------------------- pause / over

local PAUSE = { { "Resume", "resume" }, { "Connect Joy-Con 2", "pair" }, { "Restart", "restart" }, { "Controllers", "controllers" },
  { "Settings", "settings" }, { "Quit to sport select", "sports" } }
local OVER = { { "Play again", "restart" }, { "Sport select", "sports" } }

function B.openPause() g.pause, g.pauseSel = true, 1; Snd.ui("select") end

local function menuAction(a)
  if a == "resume" then g.pause = nil
  elseif a == "restart" then newGame()
  elseif a == "controllers" then g.pause = nil; env.go("controllers")
  elseif a == "settings" then g.pause = nil; env.go("settings")
  elseif a == "pair" then g.pause = nil; env.go("pair")
  elseif a == "sports" then g.pause = nil; env.root("sports") end
end

-- menu navigation from app.lua (D-pad / keyboard / A / B)
function B.nav(nav)
  if not g then return end
  local list = g.pause and PAUSE or (g.phase == "over" and OVER or nil)
  if not list then
    if nav.b and not g.ctrl.buttons.b then B.openPause() end -- Esc / Back
    if nav.a and g.phase == "aim" and g.reader.phase == "idle" then
      g.mode = g.mode == "move" and "turn" or "move"
      Snd.ui("toggle")
    end
    return
  end
  local was = g.pauseSel
  if nav.up then g.pauseSel = math.max(1, g.pauseSel - 1) end
  if nav.down then g.pauseSel = math.min(#list, g.pauseSel + 1) end
  if g.pauseSel ~= was then Snd.ui("move") end
  if nav.a then Snd.ui("select"); menuAction(list[g.pauseSel][2]) end
  if nav.b and g.pause then g.pause = nil; Snd.ui("back") end
end

-------------------------------------------------------------------------------- the bowler

-- which way the right arm points (model space of the character file: forward is +z,
-- the right arm is on -x); arm = 0 straight forward, -pi/2 hanging, -pi straight back
local function armDir(a) return { -0.10, math.sin(a), math.cos(a) } end

function bowlerUpdate(dt)
  local bw = g.bowler
  -- arm: follows the controller while the throw button is held, then a follow-through
  local want, a, hold = 0, g.armA, 0
  if g.phase == "aim" then
    local arm, rp = g.reader.arm or -math.pi / 2, g.reader.phase
    if g.ctrl.kind == "mouse" and g.drag then
      local p = g.drag[#g.drag]
      arm = -math.pi / 2 - m.clamp((p.y - g.drag[1].y) / 200, -1.2, 1.4)
      rp = "swing"
    end
    if rp == "swing" or (rp == "ready" and arm < 0.4) then
      want, a = 1, m.clamp(arm, -math.pi * 0.95, 0.6)
    elseif rp == "wait" or rp == "ready" then
      hold = 1
    end
  elseif g.phase == "rolling" and g.t < 0.7 then
    want = 1
    a = g.armA + (0.45 - g.armA) * math.min(1, dt * 8)
  end
  g.armA = a
  local k = math.min(1, dt * (want > g.armW and 14 or 4))
  g.armW = g.armW + (want - g.armW) * k
  -- both hands holding the ball at the chest while getting ready
  local kh = math.min(1, dt * (hold > g.holdW and 8 or 14))
  g.holdW = g.holdW + (hold - g.holdW) * kh

  -- body animation
  if g.phase == "aim" then
    if g.walk > 0 then bw:play("Walking_A", { rate = 1.25, fade = 0.15 }) else bw:play("Idle_A", { fade = 0.3 }) end
  elseif g.phase == "result" and g.react and g.t >= REACT_AT then
    if not g.reacting then
      g.reacting = true
      bw:play(g.react, { loop = false, restart = true, fade = 0.1 })
    end
  elseif g.phase == "result" and g.react then
    bw:play("Idle_A", { fade = 0.3 })
  elseif not g.reacting then
    bw:play("Idle_A", { fade = 0.4 })
  end
  bw:update(dt)
end

-- pose the bowler for drawing: returns its placement matrix, joint matrices and where the
-- ball sits in its right hand (world space)
local function bowlerPose()
  local bw = g.bowler
  local rig = bw.rig
  local pose, glob = bw:pose()
  if g.holdW > 0.01 then
    -- upper arms down and a little forward, forearms forward and in towards the ball
    for _, s in ipairs({ { "r", 1 }, { "l", -1 } }) do
      local side, sx = s[1], s[2]
      rig:aim(pose, glob, "upperarm." .. side, "lowerarm." .. side, { 0.08 * sx, -0.8, 0.42 }, g.holdW)
      rig:aim(pose, glob, "lowerarm." .. side, "wrist." .. side, { 0.55 * sx, 0.22, 0.75 }, g.holdW)
      rig:aim(pose, glob, "wrist." .. side, "hand." .. side, { 0.55 * sx, 0.22, 0.75 }, g.holdW)
    end
  end
  if g.armW > 0.01 then
    local d = armDir(g.armA)
    rig:aim(pose, glob, "upperarm.r", "lowerarm.r", d, g.armW)
    rig:aim(pose, glob, "lowerarm.r", "wrist.r", d, g.armW)
    rig:aim(pose, glob, "wrist.r", "hand.r", d, g.armW)
  end
  local model = Char.place({ g.x, 0, g.bz }, math.pi + g.angle, ROBOT_SCALE)
  local w = rig:jointPos(glob, "wrist.r")
  local h = rig:jointPos(glob, "hand.r")
  local dx, dy, dz = h[1] - w[1], h[2] - w[2], h[3] - w[3]
  local l = math.sqrt(dx * dx + dy * dy + dz * dz)
  -- the ball sits in the palm, a little further along the hand
  local r = g.tun.ballRadius / ROBOT_SCALE
  local c = { h[1] + dx / l * r * 0.55, h[2] + dy / l * r * 0.55 - r * 0.25, h[3] + dz / l * r * 0.55 + r * 0.35 }
  if g.holdW > 0.01 then
    -- held in both hands: between the palms
    local hl = rig:jointPos(glob, "hand.l")
    local both = { (h[1] + hl[1]) / 2, (h[2] + hl[2]) / 2 + r * 0.15, (h[3] + hl[3]) / 2 + r * 0.45 }
    local k = g.holdW
    c = { c[1] + (both[1] - c[1]) * k, c[2] + (both[2] - c[2]) * k, c[3] + (both[3] - c[3]) * k }
  end
  return model, glob, Char.toWorld(model, c)
end

-------------------------------------------------------------------------------- drawing

local aimMeshes
local function buildAim()
  if aimMeshes then return aimMeshes end
  local dot, arrow = {}, {}
  local n = 16
  for i = 0, n - 1 do
    local a0, a1 = i / n * 2 * math.pi, (i + 1) / n * 2 * math.pi
    dot[#dot + 1] = { 0, 0, 0, 0, 0, 0, 1, 0, 1, 1, 1, 1 }
    dot[#dot + 1] = { math.cos(a1), 0, math.sin(a1), 0, 0, 0, 1, 0, 1, 1, 1, 1 }
    dot[#dot + 1] = { math.cos(a0), 0, math.sin(a0), 0, 0, 0, 1, 0, 1, 1, 1, 1 }
  end
  arrow[1] = { 0, 0, -1, 0, 0, 0, 1, 0, 1, 1, 1, 1 }
  arrow[2] = { -0.4, 0, 0, 0, 0, 0, 1, 0, 1, 1, 1, 1 }
  arrow[3] = { 0.4, 0, 0, 0, 0, 0, 1, 0, 1, 1, 1, 1 }
  aimMeshes = {
    dot = gfx.mesh(dot, nil, { unlit = true, alpha = true, cull = false }),
    arrow = gfx.mesh(arrow, nil, { unlit = true, alpha = true, cull = false }),
  }
  return aimMeshes
end

-- dotted throw line with an arrow head on the lane, like the original's guide
local function drawAimLine(sc)
  local am = buildAim()
  local M4 = gfx.M4
  local x0 = m.clamp(g.x + 0.14, -L.halfWidth + 0.12, L.halfWidth - 0.12)
  local dir = { -math.sin(g.angle), 0, -math.cos(g.angle) }
  local pulse = 0.6 + 0.4 * math.sin(love.timer.getTime() * 5)
  local tint = { 1, 1, 1, 0.8 * pulse }
  for i = 0, 15 do
    local dist = 2.0 + i * 0.6
    local p = { x0 + dir[1] * dist, 0.004, dir[3] * dist }
    if math.abs(p[1]) < L.halfWidth - 0.02 then sc:add(am.dot, M4.trs(p, nil, { 0.026, 1, 0.026 }), tint) end
  end
  local tip = 2.0 + 16 * 0.6
  local p = { x0 + dir[1] * tip, 0.005, dir[3] * tip }
  local h = g.angle / 2
  sc:add(am.arrow, M4.trs(p, { math.cos(h), 0, math.sin(h), 0 }, 0.28), { 1, 1, 1, 0.85 * pulse })
end

local scene
function B.draw3d()
  if not g then return end
  local W, H = lg.getDimensions()
  if scene and scene.msaa ~= gfx.MSAA then scene = nil end -- graphics quality changed
  if not scene then scene = gfx.scene(W, H) else scene:resize(W, H) end
  scene:camera(g.cam.pos, g.cam.target, math.rad(g.cam.fov or 38), 0.05, 400)
  scene:begin({ 0.82, 0.86, 0.92, 1 })
  local pins = {}
  for _, p in ipairs(g.sim.pins) do
    if not p.gone then pins[#pins + 1] = { pos = p.body.pos, q = p.body.q } end
  end
  local model, glob, hand = bowlerPose()
  local ball
  if g.sim.ball and g.phase ~= "aim" then
    ball = { pos = g.sim.ball.pos, q = g.sim.ball.q }
  elseif g.phase == "aim" then
    ball = { pos = hand, q = { 1, 0, 0, 0 } }
  end
  Scene.draw(scene, { pins = pins, ball = ball, extra = function(sc, b)
    g.bowler:draw(sc, model, glob)
    sc:add(b.shadow, gfx.M4.trs({ g.x, 0.002, g.bz }, nil, { 0.34, 1, 0.30 }))
    if g.phase == "aim" and g.reader.phase ~= "swing" and g.walk == 0 and settings.get("aimLine") then drawAimLine(sc) end
  end })
  scene:render()
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
  if c.kind ~= "mouse" then
    -- what the game receives right now: throw button, motion, control level
    local x = 24 + nw + 8
    local held = c.buttons.b
    local tw = U.textWidth(lb.throw, 12) + 30
    U.rect(x, 118, tw, 28, 14, held and C.blue or C.card)
    lg.setColor(held and C.card or C.line); lg.circle("fill", x + 14, 132, 5)
    U.text(lb.throw, x + 22, 125, 12, held and C.card or C.ink)
    x = x + tw + 6
    local mv = math.min(1, (g.gyroSeen or 0) / 6)
    U.rect(x, 118, 104, 28, 14, C.card)
    U.text("Motion", x + 10, 125, 12, (g.motionAlive and C.ink) or C.warn)
    U.rect(x + 60, 129, 34, 6, 3, C.line)
    if mv > 0.01 then U.rect(x + 60, 129, math.max(6, 34 * mv), 6, 3, C.blue) end
    if c.level ~= motion.FULL then
      x = x + 110
      local name = motion.LEVEL_NAMES[c.level] or "?"
      local w2 = U.textWidth(name, 12) + 24
      U.rect(x, 118, w2, 28, 14, C.warnSoft or C.card)
      U.text(name, x, 125, 12, C.warn or C.ink, "center", w2)
    end
  end

  g.connectHit = nil
  if c.kind == "mouse" and g.phase ~= "over" and not g.pause then
    -- no motion controller yet: offer to connect one right here
    local x, y, w = 956, 172, 300
    U.rect(x, y + 4, w, 118, 20, C.shadow)
    U.rect(x, y, w, 118, 20, C.card)
    U.text("NO MOTION CONTROLLER", x, y + 14, 12, C.sub, "center", w)
    g.connectHit = U.pill("Connect Joy-Con 2", x + 24, y + 40, "primary", false, w - 48)
    U.text("or press Esc, then Connect Joy-Con 2", x, y + 96, 11, C.sub, "center", w)
  end

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
      local lt = g.lastThrow
      local spin = math.floor(math.abs(lt.hook) * 100 + 0.5)
      local aimDeg = math.deg(lt.aim or 0)
      local sp = string.format("%.0f km/h  ·  spin %s  ·  aim %s", lt.speed * 3.6,
        spin == 0 and "none" or (spin .. "% " .. (lt.hook > 0 and "right" or "left")),
        math.abs(aimDeg) < 0.05 and "straight" or string.format("%.1f° %s", math.abs(aimDeg), aimDeg > 0 and "left" or "right"))
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
    for _, h in ipairs(g.menuHits) do if U.hit(h, dx, dy) then Snd.ui("select"); menuAction(h.action); return true end end
    return true
  end
  if g.connectHit and U.hit(g.connectHit, dx, dy) then env.go("pair"); return true end
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
