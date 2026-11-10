-- Reads one bowling throw from a MotionController, the Wii Sports way:
--   1. hold the throw button (B on a Wii Remote, ZR / ZL on a Joy-Con) with the controller
--      held still in front of your chest: that still moment re-centres the aim,
--   2. swing back and forward,
--   3. let go of the button to release the ball.
-- Power comes from the forward swing, spin from how far the wrist twists during it
-- (see docs/research/bowling.md). Every fallback level produces the same throw event.
--
-- update() returns at most one event per call:
--   { type = "ready" }                    held still, aim re-centred, waiting for the swing
--   { type = "swing" }                    backswing started
--   { type = "throw", power, hook, aim }  power 0..1, hook -1..1 (right +), aim rad (left +)
--   { type = "cancel", reason }           button let go without a real swing
local m = require("core.math")
local motion = require("core.motion")

local R = {}
R.__index = R

R.STILL_RATE = 0.9      -- rad/s: "holding still"
R.STILL_TIME = 0.25     -- s of stillness that counts as the ready pose
R.BACK_RATE = 1.8       -- rad/s backwards that starts the swing
R.MIN_FORWARD = 1.6     -- rad/s forwards needed for a real throw
-- forward arm speed (rad/s at its peak) that gives the slowest and the fastest ball:
-- measured on real Joy-Con 2 swings, a relaxed throw peaks around 7, a normal one around
-- 15 and a hard one around 22
R.PEAK_SLOW, R.PEAK_FAST = 4, 22
R.FULL_TWIST = 1.3      -- rad of wrist twist during the forward swing for full hook
R.TWIST_DEAD = 0.30     -- rad of twist ignored (nobody swings perfectly straight)

function R.new(ctrl, tun)
  return setmetatable({ ctrl = ctrl, tun = tun, phase = "idle", lastT = -1, arm = -math.pi / 2 }, R)
end

function R:reset() self.phase = "idle" end

-- forward/back swing rate in world space: rotation about the player's left-right axis.
-- Positive = the hand moving forward (tip of the controller turning up).
local function pitchRate(orient, gyro)
  return m.qrot(orient, gyro)[1]
end

-- Which way the player faces, from a controller held in any pose: pointing roughly level
-- it is the pointing axis; held upright at the chest (the ready pose) or hanging down,
-- the pointing axis is near vertical, so the button face tells the heading instead.
function R.headingYaw(q)
  local f = m.qrot(q, m.FORWARD)
  local h
  if f[2] > 0.7 then h = m.qrot(q, { 0, -1, 0 })
  elseif f[2] < -0.7 then h = m.qrot(q, { 0, 1, 0 })
  else h = f end
  return math.atan2(-h[1], -h[3])
end

local function throwEvent(self, power, hook, aim)
  self.phase = "idle"
  return { type = "throw", power = m.clamp(power, 0, 1), hook = m.clamp(hook, -1, 1), aim = aim or 0,
    -- what was read, for the on-screen readout and the throw log
    info = { peak = self.peak, twist = self.twist, releaseYaw = self.releaseYaw, trace = self.trace } }
end

-- full motion (and gyro-as-pointer): reads every new sample, so a 33 Hz controller
-- loses nothing between frames
function R:updateMotion()
  local c = self.ctrl
  local held = c.buttons.b
  local ev
  local newSamples = {}
  for _, h in ipairs(c.history) do if h.t > self.lastT then newSamples[#newSamples + 1] = h end end
  local prevT = self.lastT
  if #newSamples > 0 then self.lastT = newSamples[#newSamples].t end
  -- time step of each new sample (the first one is measured from the last sample we saw)
  local function sdt(i)
    local p = i > 1 and newSamples[i - 1].t or prevT
    local d = newSamples[i].t - p
    if p < 0 or d <= 0 or d > 0.1 then return 1 / 60 end
    return d
  end
  -- arm angle for the bowler on screen, all the way round: 0 = pointing forward,
  -- -90° = hanging down, -150° = swung back behind
  local f = m.qrot(c.orient, m.FORWARD)
  self.arm = math.atan2(f[2], -f[3])

  if self.phase == "idle" then
    if c.pressed.b or held then self.phase, self.stillT, self.waitT = "wait", 0, 0 end
    return
  end
  if self.phase == "wait" then
    if not held then self.phase = "idle"; return { type = "cancel", reason = "early" } end
    for i, h in ipairs(newSamples) do
      local dt = sdt(i)
      local w = m.len(h.gyro)
      self.waitT = self.waitT + dt
      if w < R.STILL_RATE then self.stillT = self.stillT + dt else self.stillT = 0 end
      if self.stillT >= R.STILL_TIME then
        c:recentre(R.headingYaw(c.raw))
        self.phase = "ready"
        self.trace = {}
        return { type = "ready" }
      end
      -- already swinging without pausing: go anyway, the last recentre stays
      if pitchRate(h.orient, h.gyro) < -R.BACK_RATE * 1.5 and self.waitT > 0.15 then
        self.phase, self.peak, self.twist = "swing", 0, 0
        self.trace = {}
        return { type = "swing" }
      end
    end
    return
  end
  if self.phase == "ready" or self.phase == "swing" then
    for i, h in ipairs(newSamples) do
      local dt = sdt(i)
      local pr = pitchRate(h.orient, h.gyro)
      if self.trace and #self.trace < 400 then
        self.trace[#self.trace + 1] = { h.t, h.gyro[1], h.gyro[2], h.gyro[3], h.orient[1], h.orient[2], h.orient[3], h.orient[4], pr }
      end
      if self.phase == "ready" and (pr < -R.BACK_RATE or pr > R.BACK_RATE * 1.5) then
        self.phase, self.peak, self.twist = "swing", 0, 0
        ev = { type = "swing" }
      end
      if self.phase == "swing" then
        if pr > self.peak then self.peak = pr end
        if pr > 1.0 then
          -- twist about the pointing axis while the arm comes forward = spin
          self.twist = self.twist + (-h.gyro[3]) * dt
        end
        self.releaseYaw = m.angles(h.orient)
      end
    end
    if not held then
      if self.phase == "swing" and self.peak >= R.MIN_FORWARD then
        -- ball speed follows how fast the arm comes forward
        local power = m.clamp((self.peak - R.PEAK_SLOW) / (R.PEAK_FAST - R.PEAK_SLOW), 0, 1)
        local tw = self.twist
        local hook = 0
        if math.abs(tw) > R.TWIST_DEAD then
          hook = (tw - (tw > 0 and R.TWIST_DEAD or -R.TWIST_DEAD)) / (R.FULL_TWIST - R.TWIST_DEAD)
        end
        local aim = m.clamp((self.releaseYaw or 0) * self.tun.aimFromSwing, -self.tun.maxSwingAim, self.tun.maxSwingAim)
        return throwEvent(self, power, hook, aim)
      end
      local was = self.phase
      self.phase = "idle"
      return { type = "cancel", reason = was == "swing" and "weak" or "noswing" }
    end
    return ev
  end
end

-- stick fallback: hold the throw button, pull the stick back, push it forward.
-- How fast it goes from back to front is the power; sideways at release is the spin.
function R:updateStick()
  local c = self.ctrl
  local x, y = c.stick[1], c.stick[2]
  if not c.buttons.b then
    local was = self.phase
    self.phase = "idle"
    if was == "back" then return { type = "cancel", reason = "noswing" } end
    return
  end
  if self.phase == "idle" then self.phase = "ready"; self.arm = 1.2; return { type = "ready" } end
  if self.phase == "ready" then
    self.arm = 1.2
    if y < -0.6 then self.phase, self.backT = "back", c.t; return { type = "swing" } end
    return
  end
  if self.phase == "back" then
    self.arm = -math.pi / 2 - 0.6 * (-y)
    if y > 0.6 then
      local dt = math.max(0.04, c.t - self.backT)
      local power = m.clamp((0.45 - dt) / 0.35, 0, 1)
      self.phase = "done"
      local ev = throwEvent(self, power, x, 0)
      self.phase = "done"
      return ev
    end
  end
end

-- touch / mouse: a drag down (backswing) then a quick flick up releases the ball.
-- points = list of {x, y, t} in design pixels. Sideways movement in the flick = spin.
function R:gesture(points)
  if #points < 3 then return { type = "cancel", reason = "noswing" } end
  local last = points[#points]
  local i = #points
  while i > 1 and last.t - points[i].t < 0.09 do i = i - 1 end
  local first = points[i]
  local dt = math.max(1e-3, last.t - first.t)
  local vy, vx = (first.y - last.y) / dt, (last.x - first.x) / dt -- vy: upwards px/s
  local lowest = points[1].y
  for _, p in ipairs(points) do lowest = math.max(lowest, p.y) end
  if vy < 250 or lowest - last.y < 40 then return { type = "cancel", reason = "noswing" } end
  local power = m.clamp((vy - 250) / 2200, 0, 1)
  local hook = m.clamp(vx / math.max(vy, 1) * 2.2, -1, 1)
  if math.abs(hook) < 0.12 then hook = 0 end
  self.phase = "idle"
  return { type = "throw", power = math.sqrt(power), hook = hook, aim = 0 }
end

function R:update()
  local lvl = self.ctrl.level
  if lvl == motion.FULL or lvl == motion.GYRO_POINTER then return self:updateMotion()
  elseif lvl == motion.STICK_POINTER then return self:updateStick() end
end

return R
