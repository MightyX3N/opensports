-- Small fixed-step rigid-body physics (architecture §4), pure Lua 5.1 / LuaJIT.
--
-- Bodies are compounds of spheres (the original bowling game builds its pins the same way,
-- see docs/research/bowling.md). Static geometry is a list of bounded planes. Contacts are
-- solved with sequential impulses (normal + Coulomb friction), plus a little positional
-- correction. Units: metres, kilograms, seconds.
--
-- Nothing here knows about any sport: bowling builds its lane and pins on top of it.
local m = require("core.math")
local P = {}
P.__index = P

local sqrt, abs, min, max = math.sqrt, math.abs, math.min, math.max

-- world -------------------------------------------------------------------------------------

function P.newWorld(opts)
  opts = opts or {}
  return setmetatable({
    bodies = {},
    planes = {},
    gravity = opts.gravity or -9.81,
    iterations = opts.iterations or 8,
    slop = 0.002,          -- penetration allowed without correction (m)
    beta = 0.2,            -- fraction of penetration corrected per step
    sleepLin = 0.04,       -- m/s
    sleepAng = 0.25,       -- rad/s
    sleepTime = 0.35,      -- s below both thresholds before a body sleeps
    t = 0,
    onContact = nil,       -- function(a, b, impulse, contact) for sounds / effects; a may be a plane; contact.vn0 = closing speed
  }, P)
end

-- plane: normal n (unit, pointing out of the solid), offset d (n·x = d on the surface).
-- bounds (optional) = {xmin, xmax, zmin, zmax}: the plane only exists above that region;
-- mat.ymax (optional): it only exists below that height.
function P:addPlane(n, d, mat, bounds)
  local p = { n = m.norm(n), d = d, mu = mat and mat.mu or 0.3, e = mat and mat.e or 0.2, bounds = bounds,
    name = mat and mat.name, ymax = mat and mat.ymax }
  self.planes[#self.planes + 1] = p
  return p
end

-- body: spheres = list of {x, y, z, r} in body space (relative to the centre of mass),
-- inertia = {ix, iy, iz} principal moments in body space.
function P:addBody(def)
  local b = {
    pos = { def.pos[1], def.pos[2], def.pos[3] },
    q = def.q or m.qid(),
    v = def.v or { 0, 0, 0 },
    w = def.w or { 0, 0, 0 },       -- world-space angular velocity
    mass = def.mass,
    invMass = def.mass > 0 and 1 / def.mass or 0,
    invI = { 1 / def.inertia[1], 1 / def.inertia[2], 1 / def.inertia[3] },
    spheres = def.spheres,
    mu = def.mu or 0.3, e = def.e or 0.3,
    linDamp = def.linDamp or 0, angDamp = def.angDamp or 0, -- fraction of speed lost per second
    awake = def.awake ~= false, still = 0,
    collide = true,
    kind = def.kind, id = def.id,
  }
  local r = 0
  for _, s in ipairs(b.spheres) do r = max(r, sqrt(s[1] * s[1] + s[2] * s[2] + s[3] * s[3]) + s[4]) end
  b.bound = r
  self.bodies[#self.bodies + 1] = b
  return b
end

function P:removeBody(b)
  for i, v in ipairs(self.bodies) do if v == b then table.remove(self.bodies, i) return end end
end

function P.wake(b) b.awake, b.still = true, 0 end

-- helpers -----------------------------------------------------------------------------------

-- world inverse inertia applied to a world vector: R · I⁻¹ · Rᵀ · x
local function invInertia(b, x)
  if b.invMass == 0 then return { 0, 0, 0 } end
  local l = m.qrot(m.qconj(b.q), x)
  l[1], l[2], l[3] = l[1] * b.invI[1], l[2] * b.invI[2], l[3] * b.invI[3]
  return m.qrot(b.q, l)
end
P.invInertia = invInertia

local function velAt(b, r)
  if not b then return { 0, 0, 0 } end
  local w = b.w
  return { b.v[1] + w[2] * r[3] - w[3] * r[2], b.v[2] + w[3] * r[1] - w[1] * r[3], b.v[3] + w[1] * r[2] - w[2] * r[1] }
end

local function applyImpulse(b, r, j)
  if not b or b.invMass == 0 then return end
  b.v[1], b.v[2], b.v[3] = b.v[1] + j[1] * b.invMass, b.v[2] + j[2] * b.invMass, b.v[3] + j[3] * b.invMass
  local dw = invInertia(b, m.cross(r, j))
  b.w[1], b.w[2], b.w[3] = b.w[1] + dw[1], b.w[2] + dw[2], b.w[3] + dw[3]
end

local function sphereWorld(b, s)
  local o = m.qrot(b.q, s)
  return { b.pos[1] + o[1], b.pos[2] + o[2], b.pos[3] + o[3] }
end

-- effective mass along direction n for a contact at offsets rA, rB
local function effMass(a, b, ra, rb, n)
  local k = 0
  if a and a.invMass > 0 then
    k = k + a.invMass + m.dot(n, m.cross(invInertia(a, m.cross(ra, n)), ra))
  end
  if b and b.invMass > 0 then
    k = k + b.invMass + m.dot(n, m.cross(invInertia(b, m.cross(rb, n)), rb))
  end
  return k > 0 and 1 / k or 0
end

local function tangents(n)
  local t1
  if abs(n[1]) > 0.57 then t1 = m.norm({ n[2], -n[1], 0 }) else t1 = m.norm({ 0, n[3], -n[2] }) end
  return t1, m.cross(n, t1)
end

-- contact generation ------------------------------------------------------------------------

local function inBounds(p, c)
  if p.ymax and c[2] > p.ymax then return false end
  local bd = p.bounds
  return not bd or (c[1] >= bd[1] and c[1] <= bd[2] and c[3] >= bd[3] and c[3] <= bd[4])
end

function P:contacts()
  local out = {}
  local bodies, planes = self.bodies, self.planes
  for i = 1, #bodies do
    local a = bodies[i]
    if a.collide and a.awake then
      -- body vs static planes
      for _, p in ipairs(planes) do
        local dc = m.dot(p.n, a.pos) - p.d
        if dc < a.bound + 0.01 then
          for _, s in ipairs(a.spheres) do
            local c = sphereWorld(a, s)
            local cd = m.dot(p.n, c) - p.d
            local dist = cd - s[4]
            -- only spheres whose centre is on the open side: a sphere that is already past a
            -- bounded plane (e.g. down in the pit, under the deck) never gets pulled through it
            if dist < 0.004 and cd > -0.01 and inBounds(p, c) then
              out[#out + 1] = { b = a, plane = p, n = p.n, p = m.sub(c, m.scale(p.n, s[4])), depth = -dist,
                mu = sqrt(a.mu * p.mu), e = max(a.e, p.e) * 0.5 + min(a.e, p.e) * 0.5 }
            end
          end
        end
      end
    end
    -- body vs body
    for k = i + 1, #bodies do
      local b = bodies[k]
      if a.collide and b.collide and (a.awake or b.awake) then
        local dx, dy, dz = b.pos[1] - a.pos[1], b.pos[2] - a.pos[2], b.pos[3] - a.pos[3]
        local rr = a.bound + b.bound
        if dx * dx + dy * dy + dz * dz < rr * rr then
          local wa = {}
          for si, s in ipairs(a.spheres) do wa[si] = sphereWorld(a, s) end
          for _, sb in ipairs(b.spheres) do
            local cb = sphereWorld(b, sb)
            for si, sa in ipairs(a.spheres) do
              local ca = wa[si]
              local ex, ey, ez = cb[1] - ca[1], cb[2] - ca[2], cb[3] - ca[3]
              local r = sa[4] + sb[4]
              local d2 = ex * ex + ey * ey + ez * ez
              if d2 < r * r and d2 > 1e-12 then
                local d = sqrt(d2)
                local n = { ex / d, ey / d, ez / d } -- a -> b
                -- a sleeping body is woken by anything moving into it
                if not a.awake or not b.awake then P.wake(a); P.wake(b) end
                out[#out + 1] = { a = a, b = b, n = n, p = { ca[1] + n[1] * sa[4], ca[2] + n[2] * sa[4], ca[3] + n[3] * sa[4] },
                  depth = r - d, mu = sqrt(a.mu * b.mu), e = (a.e + b.e) * 0.5 }
              end
            end
          end
        end
      end
    end
  end
  return out
end

-- one fixed step ----------------------------------------------------------------------------

function P:step(dt)
  self.t = self.t + dt
  local g = self.gravity
  for _, b in ipairs(self.bodies) do
    if b.awake and b.invMass > 0 then b.v[2] = b.v[2] + g * dt end
  end

  local cs = self:contacts()
  -- prepare
  for _, c in ipairs(cs) do
    local a, b = c.a, c.b
    c.ra = a and m.sub(c.p, a.pos) or { 0, 0, 0 }
    c.rb = m.sub(c.p, b.pos)
    c.kn = effMass(a, b, c.ra, c.rb, c.n)
    c.t1, c.t2 = tangents(c.n)
    c.k1 = effMass(a, b, c.ra, c.rb, c.t1)
    c.k2 = effMass(a, b, c.ra, c.rb, c.t2)
    local rel = m.sub(velAt(b, c.rb), velAt(a, c.ra))
    local vn = m.dot(rel, c.n)
    c.vn0 = vn -- approach speed before solving (negative = closing): how hard the hit was
    c.bias = 0
    if vn < -0.6 then c.bias = -c.e * vn end -- bounce only on real impacts, not resting contact
    c.bias = c.bias + self.beta * max(0, c.depth - self.slop) / dt
    c.jn, c.j1, c.j2 = 0, 0, 0
  end
  -- iterate
  for _ = 1, self.iterations do
    for _, c in ipairs(cs) do
      local a, b = c.a, c.b
      local rel = m.sub(velAt(b, c.rb), velAt(a, c.ra))
      local vn = m.dot(rel, c.n)
      local dj = c.kn * (c.bias - vn)
      local jn = max(0, c.jn + dj)
      dj = jn - c.jn
      c.jn = jn
      local J = m.scale(c.n, dj)
      applyImpulse(b, c.rb, J); applyImpulse(a, c.ra, m.scale(J, -1))
      -- friction
      local lim = c.mu * c.jn
      rel = m.sub(velAt(b, c.rb), velAt(a, c.ra))
      local d1 = -c.k1 * m.dot(rel, c.t1)
      local j1 = m.clamp(c.j1 + d1, -lim, lim); d1 = j1 - c.j1; c.j1 = j1
      local d2 = -c.k2 * m.dot(rel, c.t2)
      local j2 = m.clamp(c.j2 + d2, -lim, lim); d2 = j2 - c.j2; c.j2 = j2
      local F = m.add(m.scale(c.t1, d1), m.scale(c.t2, d2))
      applyImpulse(b, c.rb, F); applyImpulse(a, c.ra, m.scale(F, -1))
    end
  end
  if self.onContact then
    for _, c in ipairs(cs) do if c.jn > 0 then self.onContact(c.a or c.plane, c.b, c.jn, c) end end
  end
  self.lastContacts = cs

  -- integrate
  for _, b in ipairs(self.bodies) do
    if b.awake and b.invMass > 0 then
      local ld = max(0, 1 - b.linDamp * dt)
      local ad = max(0, 1 - b.angDamp * dt)
      b.v[1], b.v[2], b.v[3] = b.v[1] * ld, b.v[2] * ld, b.v[3] * ld
      b.w[1], b.w[2], b.w[3] = b.w[1] * ad, b.w[2] * ad, b.w[3] * ad
      b.pos[1], b.pos[2], b.pos[3] = b.pos[1] + b.v[1] * dt, b.pos[2] + b.v[2] * dt, b.pos[3] + b.v[3] * dt
      local wl = m.len(b.w)
      if wl > 1e-9 then b.q = m.qnorm(m.qmul(m.qaxis(b.w, wl * dt), b.q)) end
      -- sleeping
      if b.canSleep ~= false and m.len(b.v) < self.sleepLin and wl < self.sleepAng then
        b.still = b.still + dt
        if b.still > self.sleepTime then
          b.awake = false
          b.v, b.w = { 0, 0, 0 }, { 0, 0, 0 }
        end
      else
        b.still = 0
      end
    end
  end
end

return P
