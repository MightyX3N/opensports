-- Bowling tuning table (mod layer 1): every number that shapes how bowling plays.
-- Units: metres, kilograms, seconds, radians. Profiles override fields of `base`.
local T = {}

T.base = {
  -- ball
  ballRadius = 0.108, ballMass = 6.5,
  minSpeed = 3.0, maxSpeed = 9.5,    -- m/s down the lane for power 0 and 1
  releaseHeight = 0.12,              -- centre height when it leaves the hand
  maxHook = 10,                      -- rad/s of side rotation at full twist
  aimFromSwing = 0.35,               -- share of the controller's sideways angle at release that steers the ball
  maxSwingAim = math.rad(3.5),       -- cap on that steering

  -- lane friction: oiled front, dry back end, as on a real lane
  oilLength = 12.0,                  -- m from the foul line
  oilMu = 0.012, dryMu = 0.20,
  ballLinDamp = 0.02,

  -- pins
  pinMass = 1.53,
  pinMu = 0.25, pinE = 0.45,         -- pin friction / bounce
  ballPinE = 0.55,
  settleAfter = 1.0,                 -- s after the ball reaches the pins before damping ramps up
  settleRamp = 1.2,                  -- extra damping per second added after that (per second²)
  maxTurnTime = 8.0,                 -- s after the ball reaches the pins before the turn is forced over

  -- standing / knocked down
  downTilt = math.rad(25),           -- a pin tilted further than this counts as down
  downShift = 0.20,                  -- or moved further than this from its spot... and lying

  -- player
  moveRange = 0.45,                  -- m left/right of centre the bowler can stand
  moveSpeed = 0.55,                  -- m/s while the stick / D-pad is held
  turnRange = math.rad(6),
  turnSpeed = math.rad(6),           -- rad/s
}

T.profiles = {
  arcade = { pinMass = 1.1, pinMu = 0.12 },   -- lighter, slippier pins: more pin action, like the original
  realistic = { },
}

function T.get(profile, overrides)
  local t = {}
  for k, v in pairs(T.base) do t[k] = v end
  for k, v in pairs(T.profiles[profile or "arcade"] or {}) do t[k] = v end
  for k, v in pairs(overrides or {}) do t[k] = v end
  return t
end

return T
