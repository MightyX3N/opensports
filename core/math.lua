-- Small vector / quaternion helpers. Plain tables, no metatables, Lua 5.1 safe.
-- vec3 = {x, y, z}; quat = {w, x, y, z} (unit, rotates controller space -> world space).
local M = {}
local sqrt, sin, cos, atan2, asin, abs = math.sqrt, math.sin, math.cos, math.atan2, math.asin, math.abs
atan2 = atan2 or math.atan

function M.v(x, y, z) return { x or 0, y or 0, z or 0 } end
function M.add(a, b) return { a[1] + b[1], a[2] + b[2], a[3] + b[3] } end
function M.sub(a, b) return { a[1] - b[1], a[2] - b[2], a[3] - b[3] } end
function M.scale(a, s) return { a[1] * s, a[2] * s, a[3] * s } end
function M.dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end
function M.cross(a, b)
  return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] }
end
function M.len(a) return sqrt(a[1] * a[1] + a[2] * a[2] + a[3] * a[3]) end
function M.norm(a)
  local l = M.len(a)
  if l < 1e-12 then return { 0, 0, 0 } end
  return { a[1] / l, a[2] / l, a[3] / l }
end
function M.lerp(a, b, t) return a + (b - a) * t end
function M.clamp(x, lo, hi) if x < lo then return lo elseif x > hi then return hi end return x end

-- quaternions
function M.qid() return { 1, 0, 0, 0 } end
function M.qmul(a, b)
  return {
    a[1] * b[1] - a[2] * b[2] - a[3] * b[3] - a[4] * b[4],
    a[1] * b[2] + a[2] * b[1] + a[3] * b[4] - a[4] * b[3],
    a[1] * b[3] - a[2] * b[4] + a[3] * b[1] + a[4] * b[2],
    a[1] * b[4] + a[2] * b[3] - a[3] * b[2] + a[4] * b[1],
  }
end
function M.qconj(q) return { q[1], -q[2], -q[3], -q[4] } end
function M.qnorm(q)
  local l = sqrt(q[1] * q[1] + q[2] * q[2] + q[3] * q[3] + q[4] * q[4])
  if l < 1e-12 then return M.qid() end
  return { q[1] / l, q[2] / l, q[3] / l, q[4] / l }
end
function M.qaxis(axis, angle)
  local a = M.norm(axis)
  local s = sin(angle / 2)
  return { cos(angle / 2), a[1] * s, a[2] * s, a[3] * s }
end
-- rotate vector v by q (controller -> world)
function M.qrot(q, v)
  local w, x, y, z = q[1], q[2], q[3], q[4]
  local tx = 2 * (y * v[3] - z * v[2])
  local ty = 2 * (z * v[1] - x * v[3])
  local tz = 2 * (x * v[2] - y * v[1])
  return {
    v[1] + w * tx + (y * tz - z * ty),
    v[2] + w * ty + (z * tx - x * tz),
    v[3] + w * tz + (x * ty - y * tx),
  }
end
-- integrate body-frame angular velocity w (rad/s) over dt
function M.qintegrate(q, w, dt)
  local ang = M.len(w) * dt
  if ang < 1e-12 then return q end
  return M.qnorm(M.qmul(q, M.qaxis(w, ang)))
end
function M.qslerp(a, b, t)
  local d = a[1] * b[1] + a[2] * b[2] + a[3] * b[3] + a[4] * b[4]
  if d < 0 then b = { -b[1], -b[2], -b[3], -b[4] }; d = -d end
  if d > 0.9995 then
    return M.qnorm({ M.lerp(a[1], b[1], t), M.lerp(a[2], b[2], t), M.lerp(a[3], b[3], t), M.lerp(a[4], b[4], t) })
  end
  local th = math.acos(d)
  local s = sin(th)
  local wa, wb = sin((1 - t) * th) / s, sin(t * th) / s
  return { a[1] * wa + b[1] * wb, a[2] * wa + b[2] * wb, a[3] * wa + b[3] * wb, a[4] * wa + b[4] * wb }
end

-- shortest rotation taking unit vector a onto unit vector b
function M.qfromto(a, b)
  a, b = M.norm(a), M.norm(b)
  local d = M.dot(a, b)
  if d > 0.999999 then return M.qid() end
  if d < -0.999999 then
    local axis = M.cross({ 1, 0, 0 }, a)
    if M.len(axis) < 1e-6 then axis = M.cross({ 0, 1, 0 }, a) end
    return M.qaxis(axis, math.pi)
  end
  local c = M.cross(a, b)
  return M.qnorm({ 1 + d, c[1], c[2], c[3] })
end

-- Controller convention: x = right, y = up (top face), z = towards the player.
-- Pointing at the screen means the controller's -z points along world -z.
M.FORWARD = { 0, 0, -1 }
M.UP = { 0, 1, 0 }

-- yaw (turn left +), pitch (front up +), roll (right side down +) of the pointing axis
function M.angles(q)
  local f = M.qrot(q, M.FORWARD)
  local r = M.qrot(q, { 1, 0, 0 })
  local yaw = atan2(-f[1], -f[3])
  local pitch = asin(M.clamp(f[2], -1, 1))
  local roll = asin(M.clamp(-r[2], -1, 1))
  return yaw, pitch, roll
end

return M
