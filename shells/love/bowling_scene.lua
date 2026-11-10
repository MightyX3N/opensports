-- The bowling alley drawn with the real 3D renderer (shells/love/gfx3d.lua).
-- All geometry comes from sports/bowling/models.lua; textures are generated here.
local gfx = require("shells.love.gfx3d")
local models = require("sports.bowling.models")
local setup = require("sports.bowling.setup")
local hall = require("sports.bowling.hall")
local M4 = gfx.M4
local lg = love.graphics

local S = {}
local L = setup.lane
S.LANES = hall.LANES   -- 23 lanes in pairs; ours is at x = 0

-------------------------------------------------------------------------- textures

local function hash(i)
  local x = math.sin(i * 12.9898) * 43758.5453
  return x - math.floor(x)
end
local function noise1(x)
  local i = math.floor(x)
  local f = x - i
  f = f * f * (3 - 2 * f)
  return hash(i) * (1 - f) + hash(i + 1) * f
end

local function image(w, h, fn, wrap)
  local d = love.image.newImageData(w, h)
  d:mapPixel(fn)
  local img = lg.newImage(d, { mipmaps = true })
  img:setFilter("linear", "linear", 8)
  img:setMipmapFilter("linear")
  if wrap then img:setWrap("repeat", "repeat") end
  return img
end

-- maple lane boards: 39 boards across the texture, grain running along the lane
local function woodTexture(light)
  local boards = 39
  local base = light and { 0.98, 0.84, 0.60 } or { 1.0, 0.80, 0.50 }
  return image(512, 512, function(x, y)
    local u, v = x / 512, y / 512
    local b = math.floor(u * boards)
    local inBoard = u * boards - b
    local tone = 0.96 + 0.06 * hash(b + (light and 100 or 0))
    -- grain: long stretched noise per board
    local g = noise1(v * 6 + b * 17.3) * 0.6 + noise1(v * 23 + b * 5.1 + inBoard * 3) * 0.4
    local grain = 0.97 + 0.04 * g
    local seam = (inBoard < 0.03 or inBoard > 0.97) and 0.93 or 1
    local k = tone * grain * seam
    return base[1] * k, base[2] * k, base[3] * k, 1
  end, true)
end

-- ball colour from a direction on the sphere: deep blue with soft marbled swirls
local function ballColor(x, y, z)
  local s = math.sin(x * 5.0 + math.sin(y * 4.0 + z * 3.0) * 1.8 + math.sin(z * 6.0 - x * 2.0) * 0.9)
  local t = math.sin(y * 6.5 + math.sin(x * 3.5 - z * 4.5) * 1.6)
  local k = math.max(0, s * 0.6 + t * 0.4)
  k = k * k
  return 0.10 + 0.22 * k, 0.33 + 0.30 * k, 0.78 + 0.20 * k
end

-- the ball's wrapped image: every texel is coloured from its 3D direction, so there are no
-- seams or pinched poles; the finger holes are painted on (dark inside, lit lower rim)
local function ballTexture()
  local holes = {}
  for i, h in ipairs(models.BALL_HOLES) do
    local l = math.sqrt(h[1] * h[1] + h[2] * h[2] + h[3] * h[3])
    holes[i] = { h[1] / l, h[2] / l, h[3] / l, h[4] * 0.8 }
  end
  return image(1024, 512, function(px, py)
    local th, ph = (px + 0.5) / 1024 * 2 * math.pi, (py + 0.5) / 512 * math.pi
    local x, y, z = math.sin(ph) * math.cos(th), math.cos(ph), math.sin(ph) * math.sin(th)
    local r, g, b = ballColor(x, y, z)
    for _, h in ipairs(holes) do
      local d = math.acos(math.min(1, x * h[1] + y * h[2] + z * h[3])) / h[4]
      if d < 1.25 then
        if d < 1 then
          local k = 0.10 + 0.18 * d * d
          r, g, b = 0.05 + 0.3 * k, 0.07 + 0.3 * k, 0.14 + 0.4 * k
        else
          local k = 1 - (d - 1) / 0.25        -- soft bevel around the hole
          r, g, b = r + 0.12 * k, g + 0.14 * k, b + 0.12 * k
        end
      end
    end
    return math.min(1, r), math.min(1, g), math.min(1, b), 1
  end, false)
end

-- the plate on each masking unit: our own emblem, a 10-pin triangle in a rounded frame
local function plateTexture()
  local W, H = 256, 160
  local spots = {}
  for row = 0, 3 do
    for i = 0, row do spots[#spots + 1] = { 128 + (i - row / 2) * 34, 36 + row * 28 } end
  end
  return image(W, H, function(x, y)
    -- rounded rectangle mask with a blue border
    local rx, ry = math.max(0, math.abs(x - W / 2) - (W / 2 - 22)), math.max(0, math.abs(y - H / 2) - (H / 2 - 22))
    local dist = math.sqrt(rx * rx + ry * ry)
    if dist > 22 then return 0, 0, 0, 0 end
    if dist > 16 then return 0.184, 0.490, 0.882, 1 end
    for _, p in ipairs(spots) do
      local dx, dy = x - p[1], y - p[2]
      local d = math.sqrt(dx * dx + dy * dy)
      if d < 12 then
        local e = math.min(1, (12 - d) / 1.5)
        return 1 - e * (1 - 0.184), 1 - e * (1 - 0.490), 1 - e * (1 - 0.882), 1
      end
    end
    return 0.98, 0.98, 0.99, 1
  end, false)
end

-- ceiling planks: warm wood running across the room
local function ceilingTexture()
  return image(256, 256, function(x, y)
    local plank = math.floor(y / 32)
    local inP = (y % 32) / 32
    local tone = 0.90 + 0.10 * hash(plank + 7)
    local g = 0.96 + 0.05 * noise1(x / 256 * 5 + plank * 9.1)
    local seam = (inP < 0.06) and 0.82 or 1
    local k = tone * g * seam
    return 0.78 * k, 0.64 * k, 0.48 * k, 1
  end, true)
end

-- soft speckle for carpets, floors, walls and fabric (tinted by vertex colour)
local function speckleTexture()
  return image(256, 256, function(x, y)
    local n = hash(x * 131 + y * 7919) * 0.6 + hash(math.floor(x / 3) * 17 + math.floor(y / 3) * 4513) * 0.4
    local k = 0.90 + 0.12 * n
    return k, k, k, 1
  end, true)
end

-- ceiling slats running down the hall (u across, 8 slats per repeat)
local function slatTexture()
  return image(256, 256, function(x, y)
    local slat = math.floor(x / 32)
    local inS = (x % 32) / 32
    local tone = 0.92 + 0.08 * hash(slat + 31)
    local g = 0.97 + 0.04 * noise1(y / 256 * 6 + slat * 7.7)
    local seam = (inS < 0.08) and 0.70 or 1
    local k = tone * g * seam
    return k, 0.93 * k, 0.86 * k, 1
  end, true)
end

-- the score monitors: our own simple scoreboard (ten frame boxes and a total)
local function screenTexture()
  local W, H = 256, 128
  return image(W, H, function(x, y)
    local r, g, b = 0.05, 0.10, 0.22
    if y > 30 and y < 82 and x > 10 and x < 246 then
      local fx = (x - 10) / 236 * 11
      local inF = fx - math.floor(fx)
      if inF < 0.05 or y < 33 or y > 79 or (y > 54 and y < 57) then r, g, b = 0.55, 0.70, 0.95 end
    end
    if y > 92 and y < 112 and x > 10 and x < 120 then r, g, b = 0.184, 0.490, 0.882 end
    return r, g, b, 1
  end, false)
end

-------------------------------------------------------------------------- building

local built
local function vertsCopy(list, ox, oy, oz)
  for _, v in ipairs(list) do v[1], v[2], v[3] = v[1] + (ox or 0), v[2] + (oy or 0), v[3] + (oz or 0) end
  return list
end

local function decals()
  -- target arrows, dots and the foul line on our lane (slightly above the wood)
  local out = {}
  local A = L.arrows
  local DARK = { 0.45, 0.27, 0.12 }
  for i, bd in ipairs(A.boards) do
    local x = (bd - 20) * L.boardWidth
    local z = -A.dist - math.abs(i - 4) * 0.30
    local y = 0.0015
    for _, t in ipairs({ { { x, y, z - 0.22 }, { x - 0.024, y, z }, { x + 0.024, y, z } } }) do
      for _, p in ipairs(t) do out[#out + 1] = { p[1], p[2], p[3], 0, 0, 0, 1, 0, DARK[1], DARK[2], DARK[3], 1 } end
    end
  end
  for _, bd in ipairs({ 3, 5, 8, 11, 14, 26, 29, 32, 35, 37 }) do
    local x = (bd - 20) * L.boardWidth
    models.quad(out, { x - 0.009, 0.0015, -L.dots.dist + 0.009 }, { x + 0.009, 0.0015, -L.dots.dist + 0.009 },
      { x + 0.009, 0.0015, -L.dots.dist - 0.009 }, { x - 0.009, 0.0015, -L.dots.dist - 0.009 }, DARK)
  end
  local hw = L.halfWidth + L.gutterWidth
  models.quad(out, { -hw, 0.0015, 0.015 }, { hw, 0.0015, 0.015 }, { hw, 0.0015, -0.015 }, { -hw, 0.0015, -0.015 },
    { 0.18, 0.22, 0.30 })
  return out
end

function S.build()
  if built then return built end
  local b = {}
  local woodTex, approachTex = woodTexture(false), woodTexture(true)
  local speckle = speckleTexture()
  local BODY, STRIPE = { 0.95, 0.95, 0.96 }, { 0.184, 0.490, 0.882 }
  local lane, gutter, ends, divs = hall.lanes(BODY, STRIPE)
  b.lane = gfx.mesh(lane, woodTex, { spec = 0.18, shine = 80 })
  b.approach = gfx.mesh(hall.approach(), approachTex, { spec = 0.15, shine = 30 })
  b.gutter = gfx.mesh(gutter, nil, { spec = 0.45, shine = 40, cull = false })
  b.ends = gfx.mesh(ends, nil, { spec = 0.05, cull = false })
  b.divs = gfx.mesh(divs, nil, { spec = 0.5, shine = 50 })
  local masks, plates = hall.pinEnd()
  b.masks = gfx.mesh(masks, nil, { spec = 0.2, shine = 20 })
  b.plates = gfx.mesh(plates, plateTexture(), { spec = 0.3, shine = 40, alpha = true, cull = false })
  b.pinSpots = gfx.mesh(hall.pinSpots(), nil, { spec = 0.1, cull = false })
  b.decals = gfx.mesh(decals(), nil, { spec = 0.2, cull = false })
  b.room = gfx.mesh(hall.floors(), speckle, { spec = 0.02, cull = false })
  local ceil, lights = hall.ceiling()
  b.ceiling = gfx.mesh(ceil, slatTexture(), { unlit = true, cull = false })
  b.walls = gfx.mesh(hall.walls(), speckle, { unlit = true, cull = false })
  b.lights = gfx.mesh(lights, nil, { unlit = true, cull = false })
  local seats, screens = hall.seating()
  b.seating = gfx.mesh(seats, speckle, { spec = 0.12, shine = 20 })
  b.screens = gfx.mesh(screens, screenTexture(), { unlit = true, cull = false })
  local rack, rackBalls = hall.rackWall()
  b.rack = gfx.mesh(rack, speckle, { spec = 0.15, shine = 20 })
  b.rackBalls = gfx.mesh(rackBalls, nil, { spec = 0.9, shine = 40, rim = 0.1 })
  b.walkway = gfx.mesh(hall.walkway(), speckle, { spec = 0.12, shine = 20 })
  -- far pins: the plain profile (no smoothing rings) is plenty at that distance
  local farPin = models.lathe(setup.pinProfile, 8, function(h0, h1)
    local mid = (h0 + h1) / 2
    for _, st in ipairs(setup.pinStripes) do if mid > st[1] and mid < st[2] then return { 0.86, 0.16, 0.16 } end end
    return { 0.97, 0.96, 0.94 }
  end)
  local otherPins, otherShadows = hall.otherPins(farPin)
  b.otherPins = gfx.mesh(otherPins, nil, { spec = 0.5, shine = 60, rim = 0.1 })
  b.otherShadows = gfx.mesh(otherShadows, nil, { unlit = true, alpha = true, cull = false })
  b.pin = gfx.mesh(models.pin(28), nil, { spec = 0.6, shine = 70, rim = 0.12 })
  b.pinLow = gfx.mesh(models.pin(14), nil, { spec = 0.5, shine = 60, rim = 0.1 })
  b.ball = gfx.mesh(models.ball(0.108, 64, 40), ballTexture(), { spec = 1.1, shine = 45, rim = 0.22 })
  -- soft round shadow, drawn flat on the floor
  local sh = {}
  local segs = 24
  for i = 0, segs - 1 do
    local a0, a1 = i / segs * 2 * math.pi, (i + 1) / segs * 2 * math.pi
    sh[#sh + 1] = { 0, 0, 0, 0.5, 0.5, 0, 1, 0, 0, 0, 0, 0.30 }
    sh[#sh + 1] = { math.cos(a1), 0, math.sin(a1), 0, 0, 0, 1, 0, 0, 0, 0, 0 }
    sh[#sh + 1] = { math.cos(a0), 0, math.sin(a0), 0, 0, 0, 1, 0, 0, 0, 0, 0 }
  end
  b.shadow = gfx.mesh(sh, nil, { unlit = true, alpha = true, cull = false })
  built = b
  return b
end

-------------------------------------------------------------------------- drawing

-- state = { pins = { {pos, q, standing}... } (our lane), ball = {pos, q} or nil,
--   extra = function(scene, built) for more items (e.g. the bowler) }
function S.draw(scene, state)
  local b = S.build()
  scene.light.fog = { 40, 140 }
  scene.light.fogCol = { 0.86, 0.88, 0.92 }
  scene.light.sky = { 0.62, 0.62, 0.64 }
  scene.light.ground = { 0.42, 0.40, 0.40 }
  scene.light.sunCol = { 0.34, 0.33, 0.31 }
  local I = M4.identity()
  for _, k in ipairs({ "room", "lane", "approach", "gutter", "ends", "divs", "masks", "plates", "pinSpots", "ceiling",
    "lights", "walls", "decals", "seating", "screens", "rack", "rackBalls", "walkway", "otherPins", "otherShadows" }) do
    scene:add(b[k], I)
  end
  for _, p in ipairs(state.pins or {}) do
    -- pins are drawn from their base; the physics position is the centre of mass
    local q = p.q
    local up = { 2 * (q[2] * q[3] - q[1] * q[4]), 1 - 2 * (q[2] * q[2] + q[4] * q[4]), 2 * (q[3] * q[4] + q[1] * q[2]) }
    local base = { p.pos[1] - up[1] * setup.pinCOM, p.pos[2] - up[2] * setup.pinCOM, p.pos[3] - up[3] * setup.pinCOM }
    scene:add(b.pin, M4.trs(base, q))
    if p.pos[2] > 0 then scene:add(b.shadow, M4.trs({ p.pos[1], 0.001, p.pos[3] }, nil, { 0.08, 1, 0.08 })) end
  end
  if state.ball then
    local bp = state.ball.pos
    scene:add(b.ball, M4.trs(bp, state.ball.q))
    if bp[2] > -0.02 then scene:add(b.shadow, M4.trs({ bp[1], math.max(0.001, bp[2] - 0.108) + 0.001, bp[3] }, nil, { 0.12, 1, 0.12 })) end
  end
  if state.extra then state.extra(scene, b) end
end

return S
