-- Bowling lane simulation: builds the lane and pins on core/physics and runs one throw.
-- Pure Lua, no engine calls, so LÖVE, Android and GMod all run the same pins.
local m = require("core.math")
local physics = require("core.physics")
local setup = require("sports.bowling.setup")

local Sim = {}
Sim.__index = Sim

local DT = 1 / 240 -- 4 steps per 60 Hz frame, like the original

function Sim.new(tuning, layout)
  local self = setmetatable({ tun = tuning, layout = layout or setup.pins, acc = 0, t = 0 }, Sim)
  local L = setup.lane
  local w = physics.newWorld({ iterations = 10 })
  self.world = w
  -- lane and pin deck (one surface; the ball's friction changes with the oil pattern)
  self.lanePlane = w:addPlane({ 0, 1, 0 }, 0, { mu = 1, e = 0, name = "lane" },
    { -L.kickback, L.kickback, -L.deckEnd, L.approach })
  w:addPlane({ 0, 1, 0 }, -L.pitDepth, { mu = 0.6, e = 0.05, name = "pit" })
  w:addPlane({ 1, 0, 0 }, -L.kickback, { mu = 0.2, e = 0.3, name = "kickback" }, { -10, 10, -L.pitBack - 1, -L.kickbackStart })
  w:addPlane({ -1, 0, 0 }, -L.kickback, { mu = 0.2, e = 0.3, name = "kickback" }, { -10, 10, -L.pitBack - 1, -L.kickbackStart })
  w:addPlane({ 0, 0, 1 }, -L.pitBack, { mu = 0.8, e = 0.05, name = "cushion" })
  w:addPlane({ 0, 0, -1 }, L.deckEnd, { mu = 0.4, e = 0.1, name = "pitfront", ymax = -0.005 })
  self.pins = {}
  self:rack()
  return self
end

local function pinInertia(mass)
  local s = mass / 1.53
  return { 0.0194 * s, 0.0019 * s, 0.0194 * s }
end

-- a full rack of standing pins
function Sim:rack()
  for _, p in ipairs(self.pins) do self.world:removeBody(p.body) end
  self.pins = {}
  local spheres = {}
  for i, s in ipairs(setup.pinSpheres) do spheres[i] = { s[1], s[2] - setup.pinCOM, s[3], s[4] } end
  for i, spot in ipairs(self.layout) do
    local b = self.world:addBody({
      pos = { spot[1], setup.pinCOM, spot[2] }, mass = self.tun.pinMass, inertia = pinInertia(self.tun.pinMass),
      spheres = spheres, mu = self.tun.pinMu, e = self.tun.pinE, linDamp = 0.05, angDamp = 0.4,
      awake = false, kind = "pin", id = i,
    })
    self.pins[i] = { body = b, spot = spot, n = i, standing = true, gone = false }
  end
end

-- second ball: fallen pins are swept away, standing ones are set straight where they stand
function Sim:sweep()
  for _, p in ipairs(self.pins) do
    if not p.gone and not self:isStanding(p) then
      self.world:removeBody(p.body)
      p.gone, p.standing = true, false
    elseif not p.gone then
      local b = p.body
      b.q, b.v, b.w = m.qid(), { 0, 0, 0 }, { 0, 0, 0 }
      b.pos[2] = setup.pinCOM
      b.awake, b.still, b.linDamp, b.angDamp = false, 0, 0.05, 0.4
    end
  end
end

function Sim:isStanding(p)
  if p.gone then return false end
  local b = p.body
  local up = m.qrot(b.q, { 0, 1, 0 })
  local L = setup.lane
  if up[2] < math.cos(self.tun.downTilt) then return false end
  if b.pos[2] < setup.pinCOM - 0.05 then return false end
  if b.pos[3] < -L.deckEnd or math.abs(b.pos[1]) > L.kickback then return false end
  return true
end

function Sim:standingCount()
  local n = 0
  for _, p in ipairs(self.pins) do if self:isStanding(p) then n = n + 1 end end
  return n
end
function Sim:standingMask()
  local s = {}
  for i, p in ipairs(self.pins) do s[i] = self:isStanding(p) end
  return s
end

-- throw = { x, angle (rad, left +), speed (m/s), hook (rad/s, right curve +) }
function Sim:throw(th)
  local T = self.tun
  if self.ball then self.world:removeBody(self.ball) end
  local r = T.ballRadius
  local dir = { -math.sin(th.angle), 0, -math.cos(th.angle) }
  local ePair = 2 * T.ballPinE - T.pinE
  self.ball = self.world:addBody({
    pos = { th.x, T.releaseHeight, 0.35 }, mass = T.ballMass,
    inertia = { 0.4 * T.ballMass * r * r, 0.4 * T.ballMass * r * r, 0.4 * T.ballMass * r * r },
    spheres = { { 0, 0, 0, r } }, mu = T.oilMu * T.oilMu, e = ePair, linDamp = T.ballLinDamp, angDamp = 0.05,
    v = m.scale(dir, th.speed), w = m.scale(dir, th.hook or 0), kind = "ball",
  })
  self.ball.canSleep = false
  self.state = "rolling"
  self.t, self.deckT, self.gutter, self.stopT = 0, nil, nil, 0
  self.throwInfo = th
  self.firstHit = nil
end

function Sim:stepOnce()
  local T, L, b = self.tun, setup.lane, self.ball
  local w = self.world
  -- oil: low friction on the front of the lane, dry back end
  if b and not self.gutter then
    local dist = -b.pos[3]
    local mu = dist < T.oilLength and T.oilMu or T.dryMu
    if dist > T.oilLength and dist < T.oilLength + 1 then mu = T.oilMu + (T.dryMu - T.oilMu) * (dist - T.oilLength) end
    b.mu = mu * mu
  end
  w:step(DT)
  self.t = self.t + DT
  if not b then return end
  -- gutter: once over the edge the ball runs in the channel past the pins
  if not self.gutter and b.pos[3] < 0 and b.pos[3] > -L.length + 0.2 and math.abs(b.pos[1]) > L.halfWidth then
    self.gutter = b.pos[1] > 0 and 1 or -1
    b.collide = false
  end
  if self.gutter then
    local r = T.ballRadius
    b.pos[1] = self.gutter * (L.halfWidth + L.gutterWidth / 2)
    b.v[1] = 0
    if b.pos[3] > -L.deckEnd then
      b.pos[2], b.v[2] = r - L.gutterDepth, 0
      if b.v[3] > -1.5 then b.v[3] = -1.5 end -- gutter balls never stall in the channel
    else
      b.pos[2] = math.max(-L.pitDepth + r, b.pos[2] + b.v[2] * DT)
      b.v[2] = b.v[2] - 9.81 * DT
    end
    b.pos[3] = math.max(b.pos[3], -L.pitBack + r)
  end
  if not self.deckT and b.pos[3] < -(L.length - 0.5) then self.deckT = self.t end
  if self.deckT then
    -- the original's settling trick: after a while pins get heavier damping every frame
    local since = self.t - self.deckT
    if since > T.settleAfter then
      for _, p in ipairs(self.pins) do
        if not p.gone then
          p.body.linDamp = p.body.linDamp + T.settleRamp * DT
          p.body.angDamp = p.body.angDamp + T.settleRamp * 3 * DT
        end
      end
    end
  end
  if m.len(b.v) < 0.05 then self.stopT = self.stopT + DT else self.stopT = 0 end
end

-- advance real time dt; returns true once the turn is over
function Sim:update(dt)
  if self.state ~= "rolling" then return self.state == "done" end
  self.acc = math.min(self.acc + dt, 0.1)
  while self.acc >= DT do
    self.acc = self.acc - DT
    self:stepOnce()
    if self:finished() then self.state = "done"; return true end
  end
  return false
end

function Sim:finished()
  local L, b = setup.lane, self.ball
  local pinsQuiet = true
  for _, p in ipairs(self.pins) do
    local pb = p.body
    if not p.gone and pb.awake and pb.pos[3] > -L.deckEnd and pb.pos[2] > 0 then pinsQuiet = false end
  end
  local ballDone = b.pos[3] < -L.deckEnd or self.stopT > 1.0
  if self.deckT and self.t - self.deckT > self.tun.maxTurnTime then return true end
  if ballDone and pinsQuiet and (not self.deckT or self.t - self.deckT > 0.6) then return true end
  if self.stopT > 3 then return true end
  return false
end

-- run a throw to the end without rendering (tests, CPU players)
function Sim:runToEnd(maxT)
  maxT = maxT or 30
  while self.state == "rolling" and self.t < maxT do
    self:stepOnce()
    if self:finished() then self.state = "done" end
  end
  return self:standingCount()
end

return Sim
