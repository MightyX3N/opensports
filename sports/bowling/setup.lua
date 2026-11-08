-- Bowling field as data (mod layer 2). Real lane dimensions, which are also what the
-- original game uses (1 unit ≈ 10 cm): a 1.05 m lane with 22 cm gutters, 18.29 m from
-- the foul line to the head pin, pins 30.48 cm apart.
--
-- World axes: x right, y up, z towards the player. The foul line is z = 0 and the lane
-- runs to negative z.
local S = {}

S.lane = {
  halfWidth = 0.527,
  gutterWidth = 0.22,
  gutterDepth = 0.045,
  length = 18.29,          -- foul line to head pin
  deckEnd = 19.15,         -- end of the pin deck (pit starts here)
  pitDepth = 0.30,
  pitBack = 19.95,         -- back cushion
  kickback = 0.80,         -- side walls around the pin deck (x)
  kickbackStart = 17.4,
  approach = 4.6,          -- approach length behind the foul line
  arrows = { dist = 4.57, spacing = 0.127, boards = { 5, 10, 15, 20, 25, 30, 35 } }, -- target arrows
  dots = { dist = 2.13 },
  boardWidth = 0.0266,     -- 39 boards
}

-- pin layouts: a list of {x, z} spots (z negative, down the lane)
S.layouts = {}

-- triangle of `rows` rows, the head pin first, numbered like real pins (row by row, left to right)
function S.layouts.triangle(rows, spacing, headZ)
  spacing = spacing or 0.3048
  headZ = headZ or -S.lane.length
  local rowGap = spacing * math.sqrt(3) / 2
  local out = {}
  for r = 0, rows - 1 do
    for i = 0, r do
      out[#out + 1] = { (i - r / 2) * spacing, headZ - r * rowGap }
    end
  end
  return out
end

S.pins = S.layouts.triangle(4)

-- pin shape: lathe profile {height, radius} from the base (real pin: 38.1 cm tall,
-- 12.1 cm across the belly, 4.6 cm at the neck)
S.pinProfile = {
  { 0.000, 0.000 }, { 0.000, 0.026 }, { 0.030, 0.040 }, { 0.070, 0.054 }, { 0.114, 0.0605 },
  { 0.160, 0.056 }, { 0.205, 0.042 }, { 0.245, 0.0255 }, { 0.270, 0.0232 }, { 0.300, 0.027 },
  { 0.335, 0.0322 }, { 0.360, 0.028 }, { 0.375, 0.017 }, { 0.381, 0.000 },
}
S.pinStripes = { { 0.232, 0.244 }, { 0.252, 0.264 } } -- two red neck bands (height ranges)
S.pinHeight = 0.381

-- collision spheres in pin space (base at y = 0): a ring of small feet so the pin stands,
-- then a stack up the body like the original's 8-sphere pins
S.pinSpheres = {}
for i = 0, 5 do
  local a = i / 6 * math.pi * 2
  S.pinSpheres[#S.pinSpheres + 1] = { math.cos(a) * 0.017, 0.010, math.sin(a) * 0.017, 0.010 }
end
for _, s in ipairs({ { 0.045, 0.045 }, { 0.090, 0.058 }, { 0.130, 0.058 }, { 0.170, 0.051 },
  { 0.210, 0.037 }, { 0.255, 0.024 }, { 0.300, 0.026 }, { 0.340, 0.030 } }) do
  S.pinSpheres[#S.pinSpheres + 1] = { 0, s[1], 0, s[2] }
end
S.pinCOM = 0.145 -- centre of mass height

return S
