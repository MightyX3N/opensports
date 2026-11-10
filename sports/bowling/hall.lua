-- The bowling hall around the lanes, built in code (pure Lua, no engine calls): 23 lanes in
-- pairs, vaulted ceiling with lights, masking and pinsetters, the seating area behind the
-- approach, a ball-rack wall and the back walkway. Layout follows a classic bowling centre
-- (and the proportions of the hall in Wii Sports); every shape and colour is our own.
-- Builders return vertex lists { x, y, z, u, v, nx, ny, nz, r, g, b, a } grouped by
-- material, for the shell to turn into meshes. Metres; our lane is centred on x = 0 with
-- the foul line at z = 0 and the pins towards -z.
local setup = require("sports.bowling.setup")
local models = require("sports.bowling.models")
local H = {}
local L = setup.lane
local sqrt, sin, cos, pi, abs, max, min, floor = math.sqrt, math.sin, math.cos, math.pi, math.abs, math.max, math.min, math.floor

-------------------------------------------------------------------------------- layout

-- lanes come in pairs that share a ball return: 1.75 m between the two lanes of a pair,
-- 1.615 m from one pair to the next (lane + gutters = 1.494 m)
H.PAIR_GAP, H.NEXT_GAP = 1.75, 1.615
H.NUM_LANES = 23
H.LANES = { 0 }
do
  local x, i = 0, 0
  for _ = 1, 11 do i = i + 1; x = x + (i % 2 == 1 and H.PAIR_GAP or H.NEXT_GAP); H.LANES[#H.LANES + 1] = x end
  x, i = 0, 0
  for _ = 1, 11 do i = i + 1; x = x - (i % 2 == 1 and H.NEXT_GAP or H.PAIR_GAP); table.insert(H.LANES, 1, x) end
end
-- pairs: centre x between the two lanes; ours is the pair (0, 1.75)
H.PAIRS = {}
for i = 1, #H.LANES - 1 do
  local a, b = H.LANES[i], H.LANES[i + 1]
  if abs((b - a) - H.PAIR_GAP) < 1e-6 then H.PAIRS[#H.PAIRS + 1] = (a + b) / 2 end
end
H.HALF_W = H.LANES[#H.LANES] + 1.3        -- side walls
H.CEIL_LOW, H.CEIL_HIGH = 4.05, 4.55      -- vault springing and crown
H.MASK_Z = -L.kickbackStart - 0.2         -- front face of the masking units
H.MASK_Y0, H.MASK_Y1 = 0.55, 1.85
H.SEAT_Z0, H.SEAT_Z1 = L.approach, 8.8    -- carpeted seating area
H.BACK_Z = 16.0                           -- back wall
H.FRONT_Z = -22.3                         -- back of the pinsetters

-- which pairs get a seating group (the five in the middle of the hall)
H.GROUPS = {}
for _, pc in ipairs(H.PAIRS) do if abs(pc - 0.875) < 7.0 then H.GROUPS[#H.GROUPS + 1] = pc end end

-------------------------------------------------------------------------------- helpers

local function vtx(out, x, y, z, u, v, nx, ny, nz, c)
  out[#out + 1] = { x, y, z, u, v, nx, ny, nz, c[1], c[2], c[3], c[4] or 1 }
end
local quad, box = models.quad, models.box
local function append(dst, src) for _, v in ipairs(src) do dst[#dst + 1] = v end return dst end

-- rounded box (a superellipsoid): centre c, half sizes h, roundness e (1 = ellipsoid,
-- small = boxy). `rot` turns it about y (radians). uv = (x, z) of the surface in metres
-- so speckle textures tile evenly.
function H.rbox(out, c, h, col, e, rot, segU, segV)
  e = e or 0.25
  segU, segV = segU or 24, segV or 12
  local cr, sr = cos(rot or 0), sin(rot or 0)
  local function sg(v) return v < 0 and -1 or 1 end
  local function at(iu, iv)
    local th, ph = iu / segU * 2 * pi, iv / segV * pi
    local nx, ny, nz = sin(ph) * cos(th), cos(ph), sin(ph) * sin(th)
    local x = h[1] * sg(nx) * abs(nx) ^ e
    local y = h[2] * sg(ny) * abs(ny) ^ e
    local z = h[3] * sg(nz) * abs(nz) ^ e
    local gx, gy, gz = sg(nx) * abs(nx) ^ (2 - e) / h[1], sg(ny) * abs(ny) ^ (2 - e) / h[2], sg(nz) * abs(nz) ^ (2 - e) / h[3]
    local l = sqrt(gx * gx + gy * gy + gz * gz)
    if l < 1e-9 then gx, gy, gz, l = nx, ny, nz, 1 end
    gx, gy, gz = gx / l, gy / l, gz / l
    local wx, wz = x * cr - z * sr, x * sr + z * cr
    local mx, mz = gx * cr - gz * sr, gx * sr + gz * cr
    return { c[1] + wx, c[2] + y, c[3] + wz, c[1] + wx, c[3] + wz, mx, gy, mz }
  end
  for iv = 0, segV - 1 do
    for iu = 0, segU - 1 do
      local a, b, cc, d = at(iu, iv), at(iu + 1, iv), at(iu + 1, iv + 1), at(iu, iv + 1)
      for _, q in ipairs({ a, b, cc, a, cc, d }) do vtx(out, q[1], q[2], q[3], q[4], q[5], q[6], q[7], q[8], col) end
    end
  end
  return out
end

-- upright cylinder (with a top cap) from y0 to y1
function H.cyl(out, x, z, r, y0, y1, col, seg)
  seg = seg or 16
  for s = 0, seg - 1 do
    local a0, a1 = s / seg * 2 * pi, (s + 1) / seg * 2 * pi
    local p0, p1 = { x + cos(a0) * r, z + sin(a0) * r }, { x + cos(a1) * r, z + sin(a1) * r }
    -- side (outward)
    quad(out, { p1[1], y0, p1[2] }, { p0[1], y0, p0[2] }, { p0[1], y1, p0[2] }, { p1[1], y1, p1[2] }, col)
    -- cap
    vtx(out, x, y1, z, 0, 0, 0, 1, 0, col)
    vtx(out, p1[1], y1, p1[2], 0, 0, 0, 1, 0, col)
    vtx(out, p0[1], y1, p0[2], 0, 0, 0, 1, 0, col)
  end
  return out
end

-- quad with uv in metres (for tiling textures): a,b,c,d as models.quad; uv from two axes
local function mquad(out, a, b, c, d, col, ua, va)
  local function uv(p) return p[ua[1]] * ua[2], p[va[1]] * va[2] end
  local u0, v0 = uv(a)
  local u1, v1 = uv(c)
  return quad(out, a, b, c, d, col, { u0, v0, u1, v1 })
end
H.mquad = mquad

-- quad with a colour per corner (baked light gradients); uv = { u0, v0, u1, v1 }
local function gquad(out, a, b, c, d, ca, cb, cc, cd, uv)
  uv = uv or { 0, 0, 1, 1 }
  local ux, uy, uz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
  local vx, vy, vz = d[1] - a[1], d[2] - a[2], d[3] - a[3]
  local nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
  local l = sqrt(nx * nx + ny * ny + nz * nz)
  nx, ny, nz = nx / l, ny / l, nz / l
  local u0, v0, u1, v1 = uv[1], uv[2], uv[3], uv[4]
  vtx(out, a[1], a[2], a[3], u0, v0, nx, ny, nz, ca)
  vtx(out, b[1], b[2], b[3], u1, v0, nx, ny, nz, cb)
  vtx(out, c[1], c[2], c[3], u1, v1, nx, ny, nz, cc)
  vtx(out, a[1], a[2], a[3], u0, v0, nx, ny, nz, ca)
  vtx(out, c[1], c[2], c[3], u1, v1, nx, ny, nz, cc)
  vtx(out, d[1], d[2], d[3], u0, v1, nx, ny, nz, cd)
end
local function shade(c, k) return { min(1, c[1] * k), min(1, c[2] * k), min(1, c[3] * k) } end

-------------------------------------------------------------------------------- colours
local C = {
  carpet = { 0.66, 0.62, 0.40 }, walk = { 0.50, 0.58, 0.56 }, wall = { 0.96, 0.88, 0.70 },
  wallBase = { 0.86, 0.80, 0.68 }, dark = { 0.10, 0.10, 0.12 }, side = { 0.16, 0.14, 0.13 },
  seat = { 0.92, 0.88, 0.76 }, seatBase = { 0.55, 0.58, 0.60 }, table = { 0.97, 0.97, 0.96 },
  chrome = { 0.80, 0.83, 0.86 }, hood = { 0.62, 0.66, 0.66 }, hoodDark = { 0.30, 0.33, 0.34 },
  screen = { 0.06, 0.07, 0.10 }, cabinet = { 0.62, 0.74, 0.72 }, cabinetTop = { 0.86, 0.92, 0.90 },
  blue = { 0.184, 0.490, 0.882 }, counter = { 0.95, 0.91, 0.80 }, counterTop = { 0.55, 0.38, 0.22 },
  light = { 1.0, 0.97, 0.88 }, glow = { 1.0, 0.92, 0.75 }, pinSpot = { 0.80, 0.42, 0.30 },
  inside = { 0.13, 0.13, 0.15 }, wood = { 0.94, 0.78, 0.57 }, insideBar = { 0.22, 0.22, 0.24 },
  BALLS = { { 0.184, 0.490, 0.882 }, { 0.85, 0.20, 0.22 }, { 0.15, 0.62, 0.40 }, { 0.95, 0.70, 0.15 },
    { 0.55, 0.30, 0.75 }, { 0.10, 0.12, 0.18 }, { 0.95, 0.45, 0.65 }, { 0.20, 0.70, 0.80 } },
}
H.COLOURS = C

-------------------------------------------------------------------------------- floors & walls

-- approach wood across the whole hall (textured like the lanes; u across, v along)
function H.approach()
  local out = {}
  local X = H.HALF_W
  quad(out, { -X, 0, L.approach }, { X, 0, L.approach }, { X, 0, 0 }, { -X, 0, 0 }, { 1, 1, 1 },
    { -X / 1.68, -L.approach, X / 1.68, 0 })
  -- the strip between the lanes' far ends of the gutters and the foul line is also wood:
  -- covered by the lanes themselves
  return out
end

-- speckled floors and walls (uv in metres)
function H.floors()
  local out = {}
  local X = H.HALF_W
  local XZ = { { 1, 0.5 }, { 3, 0.5 } }
  -- carpet in the seating area
  mquad(out, { -X, 0, H.SEAT_Z1 }, { X, 0, H.SEAT_Z1 }, { X, 0, H.SEAT_Z0 }, { -X, 0, H.SEAT_Z0 }, C.carpet, XZ[1], XZ[2])
  -- walkway at the back
  mquad(out, { -X, 0, H.BACK_Z }, { X, 0, H.BACK_Z }, { X, 0, H.SEAT_Z1 }, { -X, 0, H.SEAT_Z1 }, C.walk, XZ[1], XZ[2])
  -- under the lanes and gutters (hidden mostly; stops gaps from showing the void)
  quad(out, { -X, -0.35, 0 }, { X, -0.35, 0 }, { X, -0.35, -L.pitBack }, { -X, -0.35, -L.pitBack }, C.dark)
  local B = H.BACK_Z
  -- side walls: dark, like the far corners of a dim hall
  for _, s in ipairs({ -1, 1 }) do
    local x = s * X
    local a, b = { x, 0, B }, { x, 0, H.FRONT_Z }
    local c, d = { x, H.CEIL_HIGH, H.FRONT_Z }, { x, H.CEIL_HIGH, B }
    if s < 0 then quad(out, a, b, c, d, C.side) else quad(out, b, a, d, c, C.side) end
  end
  return out
end

-------------------------------------------------------------------------------- ceiling

-- one shallow barrel vault per lane pair, running down the hall; returns wood (textured)
-- and the lights (unlit) separately
function H.ceiling()
  local wood, lights = {}, {}
  local z0, z1 = H.MASK_Z, H.BACK_Z
  local w = H.PAIR_GAP + H.NEXT_GAP
  local steps = 10
  local function vaultY(t) return H.CEIL_LOW + (H.CEIL_HIGH - H.CEIL_LOW) * sin(t * pi) end
  local edges = {}
  for _, pc in ipairs(H.PAIRS) do edges[#edges + 1] = pc end
  -- extend one pair-width beyond the outer pairs so the whole hall is covered
  table.insert(edges, 1, edges[1] - w)
  edges[#edges + 1] = edges[#edges] + w
  for _, pc in ipairs(edges) do
    local x0 = pc - w / 2
    for k = 0, steps - 1 do
      local t0, t1 = k / steps, (k + 1) / steps
      local xa, xb = x0 + t0 * w, x0 + t1 * w
      local ya, yb = vaultY(t0), vaultY(t1)
      -- facing down: wind so the normal points down/inwards
      local dx, dy = xb - xa, yb - ya
      local l = sqrt(dx * dx + dy * dy)
      local nx, ny = dy / l, -dx / l
      -- baked light: bright along the light strips in the valleys, a little darker at the crown
      local function lit(t) return shade(C.wood, 0.80 + 0.22 * (1 - sin(t * pi)) ^ 2) end
      local ca, cb = lit(t0), lit(t1)
      local function v(x, y, z, u, vv) vtx(wood, x, y, z, u, vv, nx, ny, 0, x == xa and ca or cb) end
      local ua, ub = (xa - x0) * 1.2, (xb - x0) * 1.2
      v(xa, ya, z0, ua, z0 / 3); v(xb, yb, z1, ub, z1 / 3); v(xa, ya, z1, ua, z1 / 3)
      v(xa, ya, z0, ua, z0 / 3); v(xb, yb, z0, ub, z0 / 3); v(xb, yb, z1, ub, z1 / 3)
    end
    -- light strip along the valley between vaults, and soft panels along the crown
    local y = H.CEIL_LOW - 0.03
    quad(lights, { x0 - 0.10, y, z1 }, { x0 + 0.10, y, z1 }, { x0 + 0.10, y, z0 }, { x0 - 0.10, y, z0 }, C.light)
    for z = z0 + 1.5, z1 - 1.0, 3.0 do
      local yc = H.CEIL_HIGH - 0.02
      quad(lights, { pc - 0.55, yc, z + 0.45 }, { pc + 0.55, yc, z + 0.45 }, { pc + 0.55, yc, z - 0.45 },
        { pc - 0.55, yc, z - 0.45 }, C.glow)
    end
  end
  -- fascias closing the vaults: above the masking (facing the bowlers) and above the back
  -- wall (facing the lanes); lit from the strip below, darker towards the top
  for _, f in ipairs({ { H.MASK_Z + 0.002, H.MASK_Y1, 1 }, { H.BACK_Z - 0.002, H.CEIL_LOW - 0.25, -1 } }) do
    local fz, y0, dir = f[1], f[2], f[3]
    for _, pc in ipairs(edges) do
      local x0 = pc - w / 2
      for k = 0, steps - 1 do
        local t0, t1 = k / steps, (k + 1) / steps
        local xa, xb = x0 + t0 * w, x0 + t1 * w
        local lo, hi = shade(C.wood, 1.0), shade(C.wood, 0.82)
        local uv = { xa * 1.2, y0, xb * 1.2, vaultY(t1) }
        if dir > 0 then
          gquad(wood, { xa, y0, fz }, { xb, y0, fz }, { xb, vaultY(t1), fz }, { xa, vaultY(t0), fz }, lo, lo, hi, hi, uv)
        else
          gquad(wood, { xb, y0, fz }, { xa, y0, fz }, { xa, vaultY(t0), fz }, { xb, vaultY(t1), fz }, lo, lo, hi, hi, uv)
        end
      end
    end
  end
  -- the back walkway's wall-top glow (cove light)
  quad(lights, { H.HALF_W, H.CEIL_LOW - 0.25, H.BACK_Z - 0.02 }, { -H.HALF_W, H.CEIL_LOW - 0.25, H.BACK_Z - 0.02 },
    { -H.HALF_W, H.CEIL_LOW - 0.05, H.BACK_Z - 0.02 }, { H.HALF_W, H.CEIL_LOW - 0.05, H.BACK_Z - 0.02 }, C.glow)
  return wood, lights
end

-- the back wall: cream, brightest under the cove light at the top, with a skirting
function H.walls()
  local out = {}
  local X, B = H.HALF_W, H.BACK_Z
  local top, mid, low = shade(C.wall, 1.04), shade(C.wall, 0.94), shade(C.wall, 0.84)
  local y1 = H.CEIL_LOW - 0.25
  gquad(out, { X, 1.6, B }, { -X, 1.6, B }, { -X, y1, B }, { X, y1, B }, mid, mid, top, top, { X, 1.6, -X, y1 })
  gquad(out, { X, 0.6, B }, { -X, 0.6, B }, { -X, 1.6, B }, { X, 1.6, B }, low, low, mid, mid, { X, 0.6, -X, 1.6 })
  -- a lighter panel band along the bottom with a wooden rail on top
  local band = shade(C.counter, 0.95)
  box(out, { -X, 0, B - 0.08 }, { X, 0.55, B }, band)
  box(out, { -X, 0.55, B - 0.10 }, { X, 0.60, B }, shade(C.counterTop, 1.2))
  return out
end

-------------------------------------------------------------------------------- pin end

-- masking units (one long panel per pair) and the dark pinsetter space behind them
function H.pinEnd()
  local out, plates = {}, {}
  local w = H.PAIR_GAP + H.NEXT_GAP
  local z = H.MASK_Z
  local PANEL, EDGE = { 0.60, 0.72, 0.86 }, { 0.36, 0.48, 0.66 }
  local edges = { H.PAIRS[1] - w }
  for _, pc in ipairs(H.PAIRS) do edges[#edges + 1] = pc end
  edges[#edges + 1] = H.PAIRS[#H.PAIRS] + w
  for _, pc in ipairs(edges) do
    local x0, x1 = pc - w / 2 + 0.01, pc + w / 2 - 0.01
    box(out, { x0, H.MASK_Y0, z - 0.35 }, { x1, H.MASK_Y1, z }, PANEL)
    box(out, { x0, H.MASK_Y0 - 0.03, z - 0.35 }, { x1, H.MASK_Y0 + 0.03, z + 0.015 }, EDGE)
    box(out, { x0, H.MASK_Y1 - 0.06, z - 0.35 }, { x1, H.MASK_Y1, z + 0.015 }, EDGE)
    -- the emblem plate in the middle of the panel
    local pz = z + 0.018
    quad(plates, { pc - 0.62, 0.86, pz }, { pc + 0.62, 0.86, pz }, { pc + 0.62, 1.64, pz }, { pc - 0.62, 1.64, pz },
      { 1, 1, 1 }, { 0, 1, 1, 0 })
  end
  -- inside of the pinsetters: dark back, dark ceiling, a machine bar across each lane
  local X = H.HALF_W
  quad(out, { -X, -0.4, -L.pitBack - 0.05 }, { X, -0.4, -L.pitBack - 0.05 }, { X, 2.6, -L.pitBack - 0.05 },
    { -X, 2.6, -L.pitBack - 0.05 }, C.inside)
  quad(out, { X, H.MASK_Y1, z - 0.35 }, { -X, H.MASK_Y1, z - 0.35 }, { -X, H.MASK_Y1, -L.pitBack - 0.05 },
    { X, H.MASK_Y1, -L.pitBack - 0.05 }, C.inside)
  for _, ox in ipairs(H.LANES) do
    box(out, { ox - 0.6, 0.95, -L.pitBack + 0.2 }, { ox + 0.6, 1.08, -L.pitBack + 0.5 }, C.insideBar)
  end
  return out, plates
end

-- the painted spots on every pin deck where the pins stand
function H.pinSpots()
  local out = {}
  local seg = 12
  for _, ox in ipairs(H.LANES) do
    for _, sp in ipairs(setup.pins) do
      local x, z = ox + sp[1], sp[2]
      for s = 0, seg - 1 do
        local a0, a1 = s / seg * 2 * pi, (s + 1) / seg * 2 * pi
        vtx(out, x, 0.0012, z, 0, 0, 0, 1, 0, C.pinSpot)
        vtx(out, x + cos(a1) * 0.058, 0.0012, z + sin(a1) * 0.058, 0, 0, 0, 1, 0, C.pinSpot)
        vtx(out, x + cos(a0) * 0.058, 0.0012, z + sin(a0) * 0.058, 0, 0, 0, 1, 0, C.pinSpot)
      end
    end
  end
  return out
end

-------------------------------------------------------------------------------- seating area

-- a bench of bucket seats facing `rot` (0 = facing -z, towards the lanes)
local function bench(out, x, z, rot, n)
  local cr, sr = cos(rot), sin(rot)
  local function at(lx, lz) return x + lx * cr - lz * sr, z + lx * sr + lz * cr end
  -- base rail and feet
  local bx, bz = at(0, 0.05)
  H.rbox(out, { bx, 0.20, bz }, { 0.30 * n, 0.03, 0.06 }, C.seatBase, 0.3, rot, 16, 6)
  for _, s in ipairs({ -1, 1 }) do
    local fx, fz = at(s * (0.30 * n - 0.08), 0.05)
    H.rbox(out, { fx, 0.10, fz }, { 0.04, 0.10, 0.18 }, C.seatBase, 0.3, rot, 10, 6)
  end
  for i = 1, n do
    local lx = (i - (n + 1) / 2) * 0.56
    local sx, sz = at(lx, 0)
    H.rbox(out, { sx, 0.40, sz }, { 0.24, 0.07, 0.23 }, C.seat, 0.35, rot, 14, 7)         -- seat pan
    local kx, kz = at(lx, 0.22)
    H.rbox(out, { kx, 0.70, kz }, { 0.24, 0.27, 0.06 }, C.seat, 0.35, rot, 14, 7)         -- backrest
  end
end

local function tableAt(out, x, z)
  H.rbox(out, { x, 0.72, z }, { 0.48, 0.03, 0.32 }, C.table, 0.2, 0, 20, 6)
  H.cyl(out, x, z, 0.05, 0.02, 0.70, C.chrome, 12)
  H.rbox(out, { x, 0.02, z }, { 0.22, 0.02, 0.22 }, C.chrome, 0.4, 0, 12, 4)
end

-- ball return hood between the two lanes of a pair: a low rail from the approach and a
-- rounded hood with the returned balls on top
local function ballReturn(out, x)
  H.rbox(out, { x, 0.08, 3.05 }, { 0.12, 0.08, 0.80 }, C.hood, 0.3, 0, 16, 6)
  H.rbox(out, { x, 0.27, 4.20 }, { 0.27, 0.27, 0.40 }, C.hood, 0.3, 0, 20, 10)
  H.rbox(out, { x, 0.24, 3.81 }, { 0.19, 0.14, 0.04 }, C.hoodDark, 0.4, 0, 12, 6)    -- opening
  H.rbox(out, { x, 0.55, 4.20 }, { 0.29, 0.03, 0.42 }, C.blue, 0.3, 0, 16, 4)        -- blue trim
  for i, c in ipairs({ C.BALLS[(floor(x * 7) % 8) + 1], C.BALLS[(floor(x * 3) % 8) + 1] }) do
    local b = models.ball(0.108, 14, 9, function() return c end)
    for _, v in ipairs(b) do v[1], v[2], v[3] = v[1] + x + (i - 1.5) * 0.23, v[2] + 0.66, v[3] + 4.10 end
    append(out, b)
  end
end

-- score console at the front of a seating group: a pedestal with a monitor facing the lanes
local function console(out, screens, x, z)
  H.rbox(out, { x, 0.03, z }, { 0.20, 0.03, 0.16 }, C.hoodDark, 0.4, 0, 12, 4)
  H.cyl(out, x, z, 0.05, 0.05, 0.62, C.chrome, 12)
  H.rbox(out, { x, 0.80, z }, { 0.27, 0.19, 0.06 }, C.hoodDark, 0.3, 0, 12, 6)
  quad(screens, { x + 0.22, 0.66, z - 0.065 }, { x - 0.22, 0.66, z - 0.065 }, { x - 0.22, 0.95, z - 0.065 },
    { x + 0.22, 0.95, z - 0.065 }, C.screen, { 1, 1, 0, 0 })
  -- second screen facing the seats
  quad(screens, { x - 0.22, 0.66, z + 0.065 }, { x + 0.22, 0.66, z + 0.065 }, { x + 0.22, 0.95, z + 0.065 },
    { x - 0.22, 0.95, z + 0.065 }, C.screen, { 0, 1, 1, 0 })
end

function H.seating()
  local out, screens = {}, {}
  for _, pc in ipairs(H.PAIRS) do ballReturn(out, pc) end
  for gi, pc in ipairs(H.GROUPS) do
    console(out, screens, pc - 0.72, 5.25)
    tableAt(out, pc, 5.55)
    -- two benches angled in towards the table, and a longer one behind facing the lanes
    bench(out, pc - 0.95, 5.85, -0.5, 2)
    bench(out, pc + 0.95, 5.85, 0.5, 2)
    bench(out, pc, 7.15, 0, 3)
  end
  return out, screens
end

-------------------------------------------------------------------------------- ball-rack wall

function H.rackWall()
  local out, balls = {}, {}
  local z0, z1 = H.SEAT_Z1 - 0.45, H.SEAT_Z1
  local segW = 3.1
  -- segments across the middle of the hall with walk-through gaps between them
  local starts = {}
  local first, last = H.GROUPS[1] - 1.6, H.GROUPS[#H.GROUPS] + 1.6
  local x = first
  while x + segW <= last + 0.01 do starts[#starts + 1] = x; x = x + segW + 0.6 end
  for si, x0 in ipairs(starts) do
    local x1 = x0 + segW
    -- cabinet body, top and shelf
    box(out, { x0, 0, z0 }, { x1, 0.78, z1 }, C.cabinet)
    box(out, { x0 - 0.02, 0.78, z0 - 0.02 }, { x1 + 0.02, 0.83, z1 + 0.02 }, C.cabinetTop)
    box(out, { x0 + 0.05, 0.05, z0 - 0.005 }, { x1 - 0.05, 0.10, z0 + 0.12 }, C.cabinetTop)
    box(out, { x0 + 0.05, 0.40, z0 - 0.005 }, { x1 - 0.05, 0.44, z0 + 0.12 }, C.cabinetTop)
    -- two rows of balls in the open front
    local n = 11
    for row = 0, 1 do
      for i = 0, n - 1 do
        local c = C.BALLS[((si * 5 + i * 3 + row * 7) % #C.BALLS) + 1]
        local b = models.ball(0.108, 10, 6, function() return c end)
        local bx, by, bz = x0 + 0.20 + i * (segW - 0.40) / (n - 1), 0.21 + row * 0.35, z0 + 0.06
        for _, v in ipairs(b) do v[1], v[2], v[3] = v[1] + bx, v[2] + by, v[3] + bz end
        append(balls, b)
      end
    end
    -- a ball cleaner machine at every other segment's end
    if si % 2 == 1 then
      H.rbox(out, { x1 + 0.30, 0.55, z1 - 0.25 }, { 0.24, 0.55, 0.22 }, { 0.80, 0.86, 0.92 }, 0.3, 0, 16, 10)
      H.rbox(out, { x1 + 0.30, 0.72, z1 - 0.47 }, { 0.11, 0.11, 0.02 }, C.hoodDark, 1, 0, 16, 8)
      H.rbox(out, { x1 + 0.30, 1.08, z1 - 0.25 }, { 0.25, 0.03, 0.23 }, C.blue, 0.3, 0, 12, 4)
    end
  end
  return out, balls
end

-------------------------------------------------------------------------------- back walkway

function H.walkway()
  local out = {}
  local B = H.BACK_Z
  -- the counter in the back left corner: a long front with a rounded end and a wood top
  local cx0, cx1, cz = -H.HALF_W + 0.6, -9.5, B - 2.4
  box(out, { cx0, 0, cz }, { cx1, 1.0, cz + 0.6 }, C.counter)
  box(out, { cx0, 1.0, cz - 0.08 }, { cx1, 1.06, cz + 0.65 }, C.counterTop)
  H.cyl(out, cx1, cz + 0.3, 0.3, 0, 1.0, C.counter, 16)
  H.cyl(out, cx1, cz + 0.3, 0.36, 1.0, 1.06, C.counterTop, 16)
  box(out, { cx1 - 0.3, 0, cz + 0.6 }, { cx1 + 0.3, 1.0, B - 0.05 }, C.counter)
  box(out, { cx1 - 0.36, 1.0, cz + 0.6 }, { cx1 + 0.36, 1.06, B - 0.05 }, C.counterTop)
  -- vending machines against the back wall, near the middle
  for i, x in ipairs({ 0.4, 1.35 }) do
    local body = i == 1 and { 0.78, 0.80, 0.82 } or { 0.92, 0.94, 0.96 }
    box(out, { x - 0.42, 0, B - 0.75 }, { x + 0.42, 1.8, B - 0.02 }, body)
    -- the window with rows of drinks
    box(out, { x - 0.34, 0.85, B - 0.77 }, { x + 0.18, 1.65, B - 0.74 }, C.screen)
    for row = 0, 2 do
      for k = 0, 3 do
        local c = C.BALLS[((row * 4 + k + i) % #C.BALLS) + 1]
        box(out, { x - 0.30 + k * 0.12, 0.95 + row * 0.24, B - 0.79 }, { x - 0.22 + k * 0.12, 1.12 + row * 0.24, B - 0.77 }, c)
      end
    end
    -- buttons and the slot
    for k = 0, 3 do box(out, { x + 0.24, 1.0 + k * 0.15, B - 0.78 }, { x + 0.34, 1.08 + k * 0.15, B - 0.75 }, C.blue) end
    box(out, { x - 0.30, 0.25, B - 0.78 }, { x + 0.30, 0.40, B - 0.75 }, C.hoodDark)
  end
  -- benches along the back wall
  for _, x in ipairs({ -6.5, 5.5, 9.5 }) do bench(out, x, B - 0.6, 0, 3) end
  return out
end

-------------------------------------------------------------------------------- neighbouring racks

-- all other lanes' pins standing (one static mesh) plus their soft shadows
function H.otherPins(pinVerts)
  local pins, shadows = {}, {}
  for _, ox in ipairs(H.LANES) do
    if ox ~= 0 then
      for _, sp in ipairs(setup.pins) do
        local x, z = ox + sp[1], sp[2]
        for _, v in ipairs(pinVerts) do
          pins[#pins + 1] = { v[1] + x, v[2], v[3] + z, v[4], v[5], v[6], v[7], v[8], v[9], v[10], v[11], v[12] }
        end
        local seg = 12
        for s = 0, seg - 1 do
          local a0, a1 = s / seg * 2 * pi, (s + 1) / seg * 2 * pi
          shadows[#shadows + 1] = { x, 0.0015, z, 0, 0, 0, 1, 0, 0, 0, 0, 0.30 }
          shadows[#shadows + 1] = { x + cos(a1) * 0.075, 0.0015, z + sin(a1) * 0.075, 0, 0, 0, 1, 0, 0, 0, 0, 0 }
          shadows[#shadows + 1] = { x + cos(a0) * 0.075, 0.0015, z + sin(a0) * 0.075, 0, 0, 0, 1, 0, 0, 0, 0, 0 }
        end
      end
    end
  end
  return pins, shadows
end

-------------------------------------------------------------------------------- lanes

-- lane beds, gutters, pit ends and dividers for all lanes. Within a pair the divider is
-- wide with the ball-return rail on it; between pairs it's narrow.
function H.lanes(BODY, STRIPE)
  local lane, gutter, ends, divs = {}, {}, {}, {}
  for _, ox in ipairs(H.LANES) do
    local p = models.lane(ox)
    append(lane, p.wood)
    append(gutter, p.gutter)
    append(ends, models.pinEnd(ox))
  end
  local lw = 2 * (L.halfWidth + L.gutterWidth)
  for i = 1, #H.LANES - 1 do
    local a, b = H.LANES[i], H.LANES[i + 1]
    local w = (b - a) - lw
    local wide = abs((b - a) - H.PAIR_GAP) < 1e-6
    append(divs, models.divider((a + b) / 2, w, wide and 0.11 or 0.075, 0.6, -L.kickbackStart, BODY, STRIPE))
  end
  -- outermost dividers against the side walls
  for _, s in ipairs({ -1, 1 }) do
    local edge = s < 0 and H.LANES[1] or H.LANES[#H.LANES]
    local x = edge + s * (lw / 2 + 0.06)
    append(divs, models.divider(x, 0.12, 0.075, 0.6, -L.kickbackStart, BODY, STRIPE))
  end
  return lane, gutter, ends, divs
end

return H
