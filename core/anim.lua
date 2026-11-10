-- Skeletal animation for glTF characters. Pure Lua 5.1 / LuaJIT, no engine calls.
--   local rig = Anim.rig(doc)              -- skeleton of a loaded glTF document (core.gltf)
--   rig:addClips(gltf.animations(doc2))    -- clips from any file made for the same skeleton
--   local pose = rig:sample("Idle_A", t)   -- local transforms of every joint
--   rig:blend(a, b, k), rig:aim(pose, ...) -- mix poses, point a bone somewhere
--   local glob = rig:globals(pose)         -- joint matrices in model space (row-major 4x4)
--   local skin = rig:skin(glob)            -- joint × inverse-bind, for the skinning shader
-- Quaternions here are glTF order { x, y, z, w }; matrices are row-major arrays of 16.
local A = {}
local sqrt, floor, min, max, acos, sin = math.sqrt, math.floor, math.min, math.max, math.acos, math.sin

------------------------------------------------------------------------------ small maths
local function qnorm(q)
  local l = sqrt(q[1] * q[1] + q[2] * q[2] + q[3] * q[3] + q[4] * q[4])
  if l < 1e-12 then return { 0, 0, 0, 1 } end
  return { q[1] / l, q[2] / l, q[3] / l, q[4] / l }
end
local function qmul(a, b)
  return {
    a[4] * b[1] + a[1] * b[4] + a[2] * b[3] - a[3] * b[2],
    a[4] * b[2] - a[1] * b[3] + a[2] * b[4] + a[3] * b[1],
    a[4] * b[3] + a[1] * b[2] - a[2] * b[1] + a[3] * b[4],
    a[4] * b[4] - a[1] * b[1] - a[2] * b[2] - a[3] * b[3],
  }
end
local function qconj(q) return { -q[1], -q[2], -q[3], q[4] } end
local function qslerp(a, b, t)
  local d = a[1] * b[1] + a[2] * b[2] + a[3] * b[3] + a[4] * b[4]
  local bx, by, bz, bw = b[1], b[2], b[3], b[4]
  if d < 0 then d, bx, by, bz, bw = -d, -bx, -by, -bz, -bw end
  if d > 0.9995 then
    return qnorm({ a[1] + (bx - a[1]) * t, a[2] + (by - a[2]) * t, a[3] + (bz - a[3]) * t, a[4] + (bw - a[4]) * t })
  end
  local th = acos(d)
  local s0, s1 = sin((1 - t) * th) / sin(th), sin(t * th) / sin(th)
  return { a[1] * s0 + bx * s1, a[2] * s0 + by * s1, a[3] * s0 + bz * s1, a[4] * s0 + bw * s1 }
end
-- rotation taking unit vector a onto unit vector b
local function qbetween(a, b)
  local d = a[1] * b[1] + a[2] * b[2] + a[3] * b[3]
  if d < -0.999999 then
    local ax = math.abs(a[1]) < 0.9 and { 1, 0, 0 } or { 0, 1, 0 }
    local c = { a[2] * ax[3] - a[3] * ax[2], a[3] * ax[1] - a[1] * ax[3], a[1] * ax[2] - a[2] * ax[1] }
    return qnorm({ c[1], c[2], c[3], 0 })
  end
  local c = { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] }
  return qnorm({ c[1], c[2], c[3], 1 + d })
end
-- quaternion from the rotation part of a row-major matrix
local function qfromm(m)
  local tr = m[1] + m[6] + m[11]
  local x, y, z, w
  if tr > 0 then
    local s = sqrt(tr + 1) * 2
    w = 0.25 * s; x = (m[10] - m[7]) / s; y = (m[3] - m[9]) / s; z = (m[5] - m[2]) / s
  elseif m[1] > m[6] and m[1] > m[11] then
    local s = sqrt(1 + m[1] - m[6] - m[11]) * 2
    w = (m[10] - m[7]) / s; x = 0.25 * s; y = (m[2] + m[5]) / s; z = (m[3] + m[9]) / s
  elseif m[6] > m[11] then
    local s = sqrt(1 + m[6] - m[1] - m[11]) * 2
    w = (m[3] - m[9]) / s; x = (m[2] + m[5]) / s; y = 0.25 * s; z = (m[7] + m[10]) / s
  else
    local s = sqrt(1 + m[11] - m[1] - m[6]) * 2
    w = (m[5] - m[2]) / s; x = (m[3] + m[9]) / s; y = (m[7] + m[10]) / s; z = 0.25 * s
  end
  return qnorm({ x, y, z, w })
end
A.qmul, A.qconj, A.qslerp, A.qbetween, A.qnorm, A.qfromm = qmul, qconj, qslerp, qbetween, qnorm, qfromm

local function trs(t, q, s)
  local x, y, z, w = q[1], q[2], q[3], q[4]
  return {
    (1 - 2 * (y * y + z * z)) * s[1], 2 * (x * y - w * z) * s[2], 2 * (x * z + w * y) * s[3], t[1],
    2 * (x * y + w * z) * s[1], (1 - 2 * (x * x + z * z)) * s[2], 2 * (y * z - w * x) * s[3], t[2],
    2 * (x * z - w * y) * s[1], 2 * (y * z + w * x) * s[2], (1 - 2 * (x * x + y * y)) * s[3], t[3],
    0, 0, 0, 1,
  }
end
local function mmul(a, b)
  local r = {}
  for i = 0, 3 do
    local a1, a2, a3, a4 = a[i * 4 + 1], a[i * 4 + 2], a[i * 4 + 3], a[i * 4 + 4]
    for j = 1, 4 do r[i * 4 + j] = a1 * b[j] + a2 * b[4 + j] + a3 * b[8 + j] + a4 * b[12 + j] end
  end
  return r
end
A.trs, A.mmul = trs, mmul
function A.apply(m, p) -- transform a point
  return { m[1] * p[1] + m[2] * p[2] + m[3] * p[3] + m[4], m[5] * p[1] + m[6] * p[2] + m[7] * p[3] + m[8],
    m[9] * p[1] + m[10] * p[2] + m[11] * p[3] + m[12] }
end
function A.applyDir(m, d)
  return { m[1] * d[1] + m[2] * d[2] + m[3] * d[3], m[5] * d[1] + m[6] * d[2] + m[7] * d[3],
    m[9] * d[1] + m[10] * d[2] + m[11] * d[3] }
end

---------------------------------------------------------------------------------- rig
local Rig = {}
Rig.__index = Rig

function A.rig(doc)
  local J = doc.json
  local skin = assert(J.skins and J.skins[1], "model has no skin")
  local gltf = require("core.gltf")
  local parentOf = {}
  for i, n in ipairs(J.nodes) do
    for _, c in ipairs(n.children or {}) do parentOf[c + 1] = i end
  end
  local r = setmetatable({ joints = {}, byName = {}, clips = {} }, Rig)
  local nodeToJoint = {}
  for k, ni in ipairs(skin.joints) do nodeToJoint[ni + 1] = k end
  local ibm = gltf.accessor(doc, skin.inverseBindMatrices)
  for k, ni in ipairs(skin.joints) do
    local n = J.nodes[ni + 1]
    -- the nearest ancestor that is also a joint; anything in between is folded into `pre`
    local p, pre = parentOf[ni + 1], nil
    while p and not nodeToJoint[p] do
      local pn = J.nodes[p]
      local m = trs(pn.translation or { 0, 0, 0 }, pn.rotation or { 0, 0, 0, 1 }, pn.scale or { 1, 1, 1 })
      pre = pre and mmul(m, pre) or m
      p = parentOf[p]
    end
    local inv = {}
    for rr = 0, 3 do for c = 0, 3 do inv[rr * 4 + c + 1] = ibm[(k - 1) * 16 + c * 4 + rr + 1] end end
    r.joints[k] = { name = n.name, parent = p and nodeToJoint[p], pre = pre, inv = inv,
      t = n.translation or { 0, 0, 0 }, r = n.rotation or { 0, 0, 0, 1 }, s = n.scale or { 1, 1, 1 } }
    r.byName[n.name] = k
  end
  -- joints are listed parents-first in glTF skins in practice; make sure of it
  r.order = {}
  local done = {}
  local function visit(k)
    if done[k] then return end
    local pk = r.joints[k].parent
    if pk then visit(pk) end
    done[k] = true
    r.order[#r.order + 1] = k
  end
  for k = 1, #r.joints do visit(k) end
  return r
end

-- add clips (from core.gltf.animations) made for this skeleton; channels are matched by joint name
function Rig:addClips(clips)
  for name, c in pairs(clips) do
    local chans = {}
    for _, ch in ipairs(c.channels) do
      local k = self.byName[ch.node]
      if k then chans[#chans + 1] = { joint = k, path = ch.path, times = ch.times, values = ch.values, nc = ch.nc, interp = ch.interp } end
    end
    self.clips[name] = { name = name, duration = c.duration, channels = chans }
  end
end

function Rig:restPose()
  local p = {}
  for k, j in ipairs(self.joints) do
    p[k] = { t = { j.t[1], j.t[2], j.t[3] }, r = { j.r[1], j.r[2], j.r[3], j.r[4] }, s = { j.s[1], j.s[2], j.s[3] } }
  end
  return p
end

local function find(times, t)
  -- index i with times[i] <= t < times[i+1] (binary search)
  local lo, hi = 1, #times
  if t <= times[1] then return 1, 0 end
  if t >= times[hi] then return hi, 0 end
  while hi - lo > 1 do
    local mid = floor((lo + hi) / 2)
    if times[mid] <= t then lo = mid else hi = mid end
  end
  return lo, (t - times[lo]) / (times[hi] - times[lo])
end

-- local pose of a clip at time t (seconds); loops unless loop == false
function Rig:sample(name, t, loop)
  local c = self.clips[name]
  local pose = self:restPose()
  if not c then return pose end
  if c.duration > 0 then
    if loop == false then t = max(0, min(t, c.duration)) else t = t % c.duration end
  end
  for _, ch in ipairs(c.channels) do
    local i, f = find(ch.times, t)
    local nc = ch.nc
    local cubic = ch.interp == "CUBICSPLINE"
    local stride = cubic and nc * 3 or nc
    local off = cubic and nc or 0
    local a, b = {}, {}
    for k = 1, nc do
      a[k] = ch.values[(i - 1) * stride + off + k]
      b[k] = ch.values[(min(i + 1, #ch.times) - 1) * stride + off + k]
    end
    if ch.interp == "STEP" then f = 0 end
    local jp = pose[ch.joint]
    if ch.path == "rotation" then
      jp.r = qslerp(a, b, f)
    elseif ch.path == "translation" then
      jp.t = { a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f, a[3] + (b[3] - a[3]) * f }
    elseif ch.path == "scale" then
      jp.s = { a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f, a[3] + (b[3] - a[3]) * f }
    end
  end
  return pose
end

function Rig:duration(name) local c = self.clips[name]; return c and c.duration or 0 end

-- mix two poses: k = 0 gives a, 1 gives b
function Rig:blend(a, b, k)
  if k <= 0 then return a end
  if k >= 1 then return b end
  local out = {}
  for i = 1, #a do
    local pa, pb = a[i], b[i]
    out[i] = {
      t = { pa.t[1] + (pb.t[1] - pa.t[1]) * k, pa.t[2] + (pb.t[2] - pa.t[2]) * k, pa.t[3] + (pb.t[3] - pa.t[3]) * k },
      r = qslerp(pa.r, pb.r, k),
      s = { pa.s[1] + (pb.s[1] - pa.s[1]) * k, pa.s[2] + (pb.s[2] - pa.s[2]) * k, pa.s[3] + (pb.s[3] - pa.s[3]) * k },
    }
  end
  return out
end

-- joint matrices in model space
function Rig:globals(pose)
  local g = {}
  for _, k in ipairs(self.order) do
    local j, p = self.joints[k], pose[k]
    local m = trs(p.t, p.r, p.s)
    if j.pre then m = mmul(j.pre, m) end
    if j.parent then m = mmul(g[j.parent], m) end
    g[k] = m
  end
  return g
end

-- skinning matrices (joint global × inverse bind), in joint order
function Rig:skin(glob)
  local out = {}
  for k, j in ipairs(self.joints) do out[k] = mmul(glob[k], j.inv) end
  return out
end

-- model-space position of a joint
function Rig:jointPos(glob, name)
  local m = glob[self.byName[name]]
  return { m[4], m[8], m[12] }
end

-- turn joint `name` so that the direction from it to its child joint `child` points
-- along `dir` (model space). Changes `pose` in place; `glob` must be this pose's globals
-- and is updated for the joint and everything below it.
function Rig:aim(pose, glob, name, child, dir, weight)
  local k, ck = self.byName[name], self.byName[child]
  local m = glob[k]
  local cp = glob[ck]
  local cur = { cp[4] - m[4], cp[8] - m[8], cp[12] - m[12] }
  local l = sqrt(cur[1] * cur[1] + cur[2] * cur[2] + cur[3] * cur[3])
  local dl = sqrt(dir[1] * dir[1] + dir[2] * dir[2] + dir[3] * dir[3])
  if l < 1e-9 or dl < 1e-9 then return end
  cur = { cur[1] / l, cur[2] / l, cur[3] / l }
  local want = { dir[1] / dl, dir[2] / dl, dir[3] / dl }
  local d = qbetween(cur, want)
  if weight and weight < 1 then d = qslerp({ 0, 0, 0, 1 }, d, weight) end
  -- new global rotation, then back into the parent's space
  local gq = qmul(d, qfromm(m))
  local pq = { 0, 0, 0, 1 }
  local j = self.joints[k]
  if j.parent then pq = qfromm(glob[j.parent]) end
  if j.pre then pq = qmul(pq, qfromm(j.pre)) end
  pose[k].r = qnorm(qmul(qconj(pq), gq))
  -- refresh the globals below
  local ng = self:globals(pose)
  for i = 1, #ng do glob[i] = ng[i] end
end

A.Rig = Rig
return A
