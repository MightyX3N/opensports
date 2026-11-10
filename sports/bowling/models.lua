-- Bowling geometry, built in code (pure Lua, no engine calls): pins, ball, lane, gutters,
-- dividers, pin end and the room. Each builder returns a list of vertices
--   { x, y, z, u, v, nx, ny, nz, r, g, b, a }
-- three per triangle, in metres, which any shell can turn into a mesh.
local setup = require("sports.bowling.setup")
local M = {}

local sqrt, cos, sin, pi = math.sqrt, math.cos, math.sin, math.pi

local function vtx(out, x, y, z, u, v, nx, ny, nz, c)
  out[#out + 1] = { x, y, z, u, v, nx, ny, nz, c[1], c[2], c[3], c[4] or 1 }
end

-- a flat quad (a,b,c,d counter-clockwise seen from the front), with uv corners
function M.quad(out, a, b, c, d, col, uv)
  uv = uv or { 0, 0, 1, 1 }
  local ux, uy, uz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
  local vx, vy, vz = d[1] - a[1], d[2] - a[2], d[3] - a[3]
  local nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
  local l = sqrt(nx * nx + ny * ny + nz * nz)
  nx, ny, nz = nx / l, ny / l, nz / l
  local u0, v0, u1, v1 = uv[1], uv[2], uv[3], uv[4]
  vtx(out, a[1], a[2], a[3], u0, v0, nx, ny, nz, col)
  vtx(out, b[1], b[2], b[3], u1, v0, nx, ny, nz, col)
  vtx(out, c[1], c[2], c[3], u1, v1, nx, ny, nz, col)
  vtx(out, a[1], a[2], a[3], u0, v0, nx, ny, nz, col)
  vtx(out, c[1], c[2], c[3], u1, v1, nx, ny, nz, col)
  vtx(out, d[1], d[2], d[3], u0, v1, nx, ny, nz, col)
  return out
end

-- a box from min to max corners
function M.box(out, mn, mx, col)
  local x0, y0, z0, x1, y1, z1 = mn[1], mn[2], mn[3], mx[1], mx[2], mx[3]
  M.quad(out, { x0, y1, z1 }, { x1, y1, z1 }, { x1, y1, z0 }, { x0, y1, z0 }, col) -- top
  M.quad(out, { x0, y0, z1 }, { x1, y0, z1 }, { x1, y1, z1 }, { x0, y1, z1 }, col) -- front (+z)
  M.quad(out, { x1, y0, z0 }, { x0, y0, z0 }, { x0, y1, z0 }, { x1, y1, z0 }, col) -- back
  M.quad(out, { x0, y0, z0 }, { x0, y0, z1 }, { x0, y1, z1 }, { x0, y1, z0 }, col) -- left
  M.quad(out, { x1, y0, z1 }, { x1, y0, z0 }, { x1, y1, z0 }, { x1, y1, z1 }, col) -- right
  return out
end

-- smooth surface of revolution around y. profile = list of {height, radius};
-- colorAt(h) gives the colour at a height. Normals come from the profile's slope, so
-- the surface shades smoothly.
function M.lathe(profile, seg, colorAt)
  local out = {}
  local n = #profile
  local nrm = {}
  for i = 1, n do
    local a, b = profile[math.max(1, i - 1)], profile[math.min(n, i + 1)]
    local dh, dr = b[1] - a[1], b[2] - a[2]
    local l = sqrt(dh * dh + dr * dr)
    nrm[i] = l > 0 and { dh / l, -dr / l } or { 0, 1 }
    if profile[i][2] == 0 then nrm[i] = { 0, i == 1 and -1 or 1 } end
  end
  for i = 1, n - 1 do
    local h0, r0, h1, r1 = profile[i][1], profile[i][2], profile[i + 1][1], profile[i + 1][2]
    local c0, c1 = colorAt(h0, h1), colorAt(h0, h1)
    for s = 0, seg - 1 do
      local a0, a1 = s / seg * 2 * pi, (s + 1) / seg * 2 * pi
      local p = {
        { cos(a0) * r0, h0, sin(a0) * r0, cos(a0) * nrm[i][1], nrm[i][2], sin(a0) * nrm[i][1], s / seg, i / n },
        { cos(a1) * r0, h0, sin(a1) * r0, cos(a1) * nrm[i][1], nrm[i][2], sin(a1) * nrm[i][1], (s + 1) / seg, i / n },
        { cos(a1) * r1, h1, sin(a1) * r1, cos(a1) * nrm[i + 1][1], nrm[i + 1][2], sin(a1) * nrm[i + 1][1], (s + 1) / seg, (i + 1) / n },
        { cos(a0) * r1, h1, sin(a0) * r1, cos(a0) * nrm[i + 1][1], nrm[i + 1][2], sin(a0) * nrm[i + 1][1], s / seg, (i + 1) / n },
      }
      local function put(q, c) vtx(out, q[1], q[2], q[3], q[7], q[8], q[4], q[5], q[6], c) end
      -- wind so the outside faces out
      if r0 > 0 then put(p[1], c0); put(p[2], c0); put(p[3], c1) end
      if r1 > 0 then put(p[1], c0); put(p[3], c1); put(p[4], c1) end
    end
  end
  return out
end

-- pin: the real pin profile, smoothed with extra rings, white with two red neck bands
function M.pin(seg)
  local src = setup.pinProfile
  local prof = {}
  -- Catmull-Rom between profile points for a smooth outline
  for i = 1, #src - 1 do
    local p0, p1, p2, p3 = src[math.max(1, i - 1)], src[i], src[i + 1], src[math.min(#src, i + 2)]
    local steps = (p1[2] == 0 or p2[2] == 0) and 1 or 4
    for k = 0, steps - 1 do
      local t = k / steps
      local t2, t3 = t * t, t * t * t
      local function cr(a, b, c, d) return 0.5 * (2 * b + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3) end
      prof[#prof + 1] = { cr(p0[1], p1[1], p2[1], p3[1]), math.max(0, cr(p0[2], p1[2], p2[2], p3[2])) }
    end
  end
  prof[#prof + 1] = src[#src]
  -- add rings exactly at the stripe edges so the bands are crisp
  for _, s in ipairs(setup.pinStripes) do
    for _, h in ipairs({ s[1], s[2] }) do
      for i = 1, #prof - 1 do
        if prof[i][1] < h and prof[i + 1][1] > h then
          local t = (h - prof[i][1]) / (prof[i + 1][1] - prof[i][1])
          table.insert(prof, i + 1, { h, prof[i][2] + (prof[i + 1][2] - prof[i][2]) * t })
          break
        end
      end
    end
  end
  local WHITE, RED = { 0.97, 0.96, 0.94 }, { 0.86, 0.16, 0.16 }
  return M.lathe(prof, seg or 28, function(h0, h1)
    local mid = (h0 + h1) / 2
    for _, s in ipairs(setup.pinStripes) do if mid > s[1] and mid < s[2] then return RED end end
    return WHITE
  end)
end

-- ball: a smooth UV sphere (u around, v top to bottom). The look, finger holes included,
-- comes from a wrapped texture (see M.BALL_HOLES), like the original game does it.
-- colorAt(nx, ny, nz), if given, tints vertices from the 3D direction.
M.BALL_HOLES = { { 0, 0.62, -0.78, 0.17 }, { -0.20, 0.80, -0.56, 0.12 }, { 0.20, 0.80, -0.56, 0.12 } }
function M.ball(r, segU, segV, colorAt, modelHoles)
  local out = {}
  segU, segV = segU or 40, segV or 24
  local holes = {}
  for i, h in ipairs(modelHoles and M.BALL_HOLES or {}) do holes[i] = h end
  for i = 1, #holes do
    local h = holes[i]
    local l = sqrt(h[1] * h[1] + h[2] * h[2] + h[3] * h[3])
    holes[i] = { h[1] / l, h[2] / l, h[3] / l, h[4] }
  end
  local function at(iu, iv)
    local u, v = iu / segU, iv / segV
    local th, ph = u * 2 * pi, v * pi
    local nx, ny, nz = sin(ph) * cos(th), cos(ph), sin(ph) * sin(th)
    -- dark inside the finger holes (a dimple)
    local c = colorAt and colorAt(nx, ny, nz) or { 1, 1, 1 }
    local rr = r
    for _, h in ipairs(holes) do
      local d = nx * h[1] + ny * h[2] + nz * h[3]
      local ang = math.acos(math.min(1, d))
      if ang < h[4] then
        c = { 0.10, 0.12, 0.18 }
        rr = r * (1 - 0.18 * (1 - ang / h[4]))
      end
    end
    return { nx * rr, ny * rr, nz * rr, u, v, nx, ny, nz, c }
  end
  for iv = 0, segV - 1 do
    for iu = 0, segU - 1 do
      local a, b, c, d = at(iu, iv), at(iu + 1, iv), at(iu + 1, iv + 1), at(iu, iv + 1)
      for _, q in ipairs({ a, b, c, a, c, d }) do vtx(out, q[1], q[2], q[3], q[4], q[5], q[6], q[7], q[8], q[9]) end
    end
  end
  return out
end

-- the lane bed of one lane centred on x = ox: parts keyed by the texture they use
function M.lane(ox)
  local L = setup.lane
  local hw, gw, gd = L.halfWidth, L.gutterWidth, L.gutterDepth
  local far, near = -L.deckEnd, L.approach
  local W = { 1, 1, 1 }
  local parts = { wood = {}, gutter = {}, approach = {} }
  -- lane: u across (0..1 = all 39 boards), v along (1 unit = 1 m)
  M.quad(parts.wood, { ox - hw, 0, 0 }, { ox + hw, 0, 0 }, { ox + hw, 0, far }, { ox - hw, 0, far }, W, { 0, 0, 1, -far })
  M.quad(parts.approach, { ox - 0.9, 0, near }, { ox + 0.9, 0, near }, { ox + 0.9, 0, 0 }, { ox - 0.9, 0, 0 }, W,
    { -0.35, -near, 1.35, 0 })
  -- gutters: a rounded channel
  local GC = { 0.78, 0.81, 0.86 }
  local steps = 8
  for _, side in ipairs({ -1, 1 }) do
    local x0 = ox + side * hw
    local prev
    for k = 0, steps do
      local a = k / steps * pi
      local x = x0 + side * (1 - cos(a)) * gw / 2
      local y = -sin(a) * gd
      local nx, ny = side * -cos(a) * 0 + (side * (-(1 - cos(a)) + 1) * 0), 1
      -- normal of a half-pipe points to its centre line
      local cx, cy = x0 + side * gw / 2, 0
      local dx, dy = cx - x, cy - y
      local l = sqrt(dx * dx + dy * dy)
      nx, ny = dx / l, dy / l
      if k > 0 then
        local g = parts.gutter
        local p0, p1 = prev, { x, y, nx, ny }
        if side < 0 then p0, p1 = p1, p0 end
        vtx(g, p0[1], p0[2], 0, 0, 0, p0[3], p0[4], 0, GC)
        vtx(g, p1[1], p1[2], 0, 1, 0, p1[3], p1[4], 0, GC)
        vtx(g, p1[1], p1[2], far, 1, 1, p1[3], p1[4], 0, GC)
        vtx(g, p0[1], p0[2], 0, 0, 0, p0[3], p0[4], 0, GC)
        vtx(g, p1[1], p1[2], far, 1, 1, p1[3], p1[4], 0, GC)
        vtx(g, p0[1], p0[2], far, 0, 1, p0[3], p0[4], 0, GC)
      end
      prev = { x, y, nx, ny }
    end
  end
  return parts
end

-- the cover between two lanes' gutters (it hides the ball return): a long rounded hump
-- centred on x = cx, `w` wide, with a coloured stripe along its top
function M.divider(cx, w, h, z0, z1, body, stripe)
  local out = {}
  local steps = 10
  local pts = {}
  for k = 0, steps do
    local a = k / steps * pi
    pts[k] = { cx - cos(a) * w / 2, sin(a) * h, -cos(a), sin(a) * 1.0 }
  end
  for k = 1, steps do
    local p0, p1 = pts[k - 1], pts[k]
    local c = (k == steps / 2 or k == steps / 2 + 1) and stripe or body
    local function n(p)
      local l = sqrt(p[3] * p[3] + p[4] * p[4]); return p[3] / l, p[4] / l
    end
    local n0x, n0y = n(p0)
    local n1x, n1y = n(p1)
    vtx(out, p0[1], p0[2], z0, 0, 0, n0x, n0y, 0, c)
    vtx(out, p1[1], p1[2], z0, 1, 0, n1x, n1y, 0, c)
    vtx(out, p1[1], p1[2], z1, 1, 1, n1x, n1y, 0, c)
    vtx(out, p0[1], p0[2], z0, 0, 0, n0x, n0y, 0, c)
    vtx(out, p1[1], p1[2], z1, 1, 1, n1x, n1y, 0, c)
    vtx(out, p0[1], p0[2], z1, 0, 1, n0x, n0y, 0, c)
  end
  -- rounded front end cap
  for k = 1, steps do
    local p0, p1 = pts[k - 1], pts[k]
    vtx(out, cx, 0, z0 + 0.02, 0, 0, 0, 0.3, 1, body)
    vtx(out, p1[1], p1[2], z0, 0, 0, 0, 0.3, 1, body)
    vtx(out, p0[1], p0[2], z0, 0, 0, 0, 0.3, 1, body)
  end
  return out
end

-- the far end of one lane: pin deck colour, pit, side kickbacks and back curtain
function M.pinEnd(ox)
  local L = setup.lane
  local out = {}
  local k = L.kickback
  local PIT, KICK, CURTAIN = { 0.12, 0.14, 0.19 }, { 0.30, 0.34, 0.42 }, { 0.10, 0.11, 0.15 }
  M.quad(out, { ox - k, -L.pitDepth, -L.deckEnd }, { ox + k, -L.pitDepth, -L.deckEnd }, { ox + k, -L.pitDepth, -L.pitBack },
    { ox - k, -L.pitDepth, -L.pitBack }, PIT)
  M.quad(out, { ox - k, -L.pitDepth, -L.pitBack }, { ox + k, -L.pitDepth, -L.pitBack }, { ox + k, 1.0, -L.pitBack },
    { ox - k, 1.0, -L.pitBack }, CURTAIN)
  M.quad(out, { ox - k, -L.pitDepth, -L.deckEnd }, { ox + k, -L.pitDepth, -L.deckEnd }, { ox + k, 0, -L.deckEnd },
    { ox - k, 0, -L.deckEnd }, PIT)
  for _, s in ipairs({ -1, 1 }) do
    local x = ox + s * k
    local a, b = { x, -L.pitDepth, -L.kickbackStart }, { x, -L.pitDepth, -L.pitBack }
    local c, d = { x, 0.55, -L.pitBack }, { x, 0.55, -L.kickbackStart }
    if s < 0 then M.quad(out, a, b, c, d, KICK) else M.quad(out, b, a, d, c, KICK) end
  end
  return out
end

return M
