-- Tiny 3D for LÖVE without shaders or a depth buffer (works the same on LÖVE 11 and 12):
-- a perspective camera, near-plane clipping and a painter's-algorithm draw list.
-- Good enough for a bowling lane and ten pins; a real mesh renderer comes later.
local m = require("core.math")
local lg = love.graphics
local R = {}

local Cam = {}
Cam.__index = Cam

-- pos, target: world points; fov: vertical field of view (rad); w, h: screen size in pixels
function R.camera(pos, target, fov, w, h)
  local f = m.norm(m.sub(target, pos))
  local r = m.norm(m.cross(f, { 0, 1, 0 }))
  local u = m.cross(r, f)
  return setmetatable({ pos = pos, f = f, r = r, u = u, w = w, h = h,
    focal = (h / 2) / math.tan(fov / 2), near = 0.05 }, Cam)
end

function Cam:toCam(p)
  local dx, dy, dz = p[1] - self.pos[1], p[2] - self.pos[2], p[3] - self.pos[3]
  return dx * self.r[1] + dy * self.r[2] + dz * self.r[3],
    dx * self.u[1] + dy * self.u[2] + dz * self.u[3],
    dx * self.f[1] + dy * self.f[2] + dz * self.f[3]
end

function Cam:project(p)
  local x, y, z = self:toCam(p)
  if z < self.near then return nil end
  return self.w / 2 + self.focal * x / z, self.h / 2 - self.focal * y / z, z
end

-- world polygon -> flat list of screen coords (clipped at the near plane), plus mean depth
function Cam:poly(pts)
  local cs = {}
  for i, p in ipairs(pts) do
    local x, y, z = self:toCam(p)
    cs[i] = { x, y, z }
  end
  local out, n = {}, #cs
  local near = self.near
  local depth, cnt = 0, 0
  for i = 1, n do
    local a, b = cs[i], cs[i % n + 1]
    local ain, bin = a[3] >= near, b[3] >= near
    if ain then out[#out + 1] = a end
    if ain ~= bin then
      local t = (near - a[3]) / (b[3] - a[3])
      out[#out + 1] = { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, near }
    end
  end
  if #out < 3 then return nil end
  local flat = {}
  for _, c in ipairs(out) do
    flat[#flat + 1] = self.w / 2 + self.focal * c[1] / c[3]
    flat[#flat + 1] = self.h / 2 - self.focal * c[2] / c[3]
    depth, cnt = depth + c[3], cnt + 1
  end
  return flat, depth / cnt
end

-- is a world-space face with normal n (at point p) facing the camera?
function Cam:facing(p, n)
  return (self.pos[1] - p[1]) * n[1] + (self.pos[2] - p[2]) * n[2] + (self.pos[3] - p[3]) * n[3] > 0
end

-- draw a world polygon immediately
function Cam:fill(pts, color)
  local flat = self:poly(pts)
  if flat then
    lg.setColor(color)
    lg.polygon("fill", flat)
  end
  return flat
end

-- painter's list ---------------------------------------------------------------------------
local List = {}
List.__index = List
function R.list() return setmetatable({ items = {} }, List) end

-- add a polygon (already projected) with a colour
function List:poly(flat, depth, color, line)
  if flat then self.items[#self.items + 1] = { d = depth, flat = flat, c = color, line = line } end
end
-- add any draw function at a depth
function List:fn(depth, f) self.items[#self.items + 1] = { d = depth, f = f } end

function List:draw()
  table.sort(self.items, function(a, b) return a.d > b.d end)
  for _, it in ipairs(self.items) do
    if it.f then it.f()
    else
      lg.setColor(it.c)
      lg.polygon("fill", it.flat)
      if it.line then
        lg.setColor(it.line); lg.setLineWidth(1); lg.polygon("line", it.flat)
      end
    end
  end
end

-- shade a colour by a world normal (simple key light + ambient)
local LIGHT = m.norm({ -0.35, 0.85, 0.45 })
function R.shade(c, n, amb)
  local k = (amb or 0.62) + (1 - (amb or 0.62)) * math.max(0, m.dot(n, LIGHT))
  return { c[1] * k, c[2] * k, c[3] * k, c[4] or 1 }
end

-- lathe mesh (pins): profile {height, radius}, seg segments around. Returns faces in body
-- space: { pts = {4 points}, n = normal, ring = profile index }
function R.lathe(profile, seg)
  local faces = {}
  for i = 1, #profile - 1 do
    local h0, r0, h1, r1 = profile[i][1], profile[i][2], profile[i + 1][1], profile[i + 1][2]
    for s = 0, seg - 1 do
      local a0, a1 = s / seg * math.pi * 2, (s + 1) / seg * math.pi * 2
      local pts = {
        { math.cos(a0) * r0, h0, math.sin(a0) * r0 }, { math.cos(a1) * r0, h0, math.sin(a1) * r0 },
        { math.cos(a1) * r1, h1, math.sin(a1) * r1 }, { math.cos(a0) * r1, h1, math.sin(a0) * r1 },
      }
      local am = (a0 + a1) / 2
      local dh, dr = h1 - h0, r1 - r0
      local nl = math.sqrt(dh * dh + dr * dr)
      local n = nl > 0 and { math.cos(am) * dh / nl, -dr / nl, math.sin(am) * dh / nl } or { 0, 1, 0 }
      -- degenerate quads (cap centres) become triangles
      if r0 == 0 then table.remove(pts, 1) elseif r1 == 0 then table.remove(pts, 4) end
      faces[#faces + 1] = { pts = pts, n = n, ring = i, mid = (h0 + h1) / 2 }
    end
  end
  return faces
end

return R
