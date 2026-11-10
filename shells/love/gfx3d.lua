-- Small real 3D renderer for LÖVE (11.5 and 12): meshes with positions, normals, UVs and
-- vertex colours, a depth buffer, soft lighting (sky/ground ambient + sun + specular) and
-- distance fog. Draws into an off-screen canvas with multisampling, then onto the screen.
local lg = love.graphics
local R = {}

-- LÖVE 11 doesn't flip render targets for custom projections: our scene comes out upside
-- down in the canvas with its face winding reversed, so it is drawn flipped and culls
-- "front". LÖVE 12 flips y (and the winding) itself when drawing into a canvas
-- (opengl/Shader.cpp clip-space params, opengl/Graphics.cpp glFrontFace), so there the
-- canvas is already upright and back faces are the ones to cull.
R.FLIPPED_RT = (love.getVersion and select(1, love.getVersion()) or 11) < 12
-- testing only: on LÖVE 11, behave like LÖVE 12 does with canvases (flip clip-space y and
-- the front-face winding), to check the LÖVE 12 settings without a LÖVE 12 build
R.EMULATE_12 = false

-------------------------------------------------------------------------- matrices (row-major)
local M4 = {}
R.M4 = M4
function M4.identity() return { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 } end
function M4.mul(a, b)
  local r = {}
  for i = 0, 3 do
    for j = 0, 3 do
      r[i * 4 + j + 1] = a[i * 4 + 1] * b[j + 1] + a[i * 4 + 2] * b[4 + j + 1] + a[i * 4 + 3] * b[8 + j + 1] + a[i * 4 + 4] * b[12 + j + 1]
    end
  end
  return r
end
function M4.perspective(fovy, aspect, near, far)
  local f = 1 / math.tan(fovy / 2)
  return { f / aspect, 0, 0, 0, 0, f, 0, 0, 0, 0, (far + near) / (near - far), 2 * far * near / (near - far), 0, 0, -1, 0 }
end
local function norm(x, y, z)
  local l = math.sqrt(x * x + y * y + z * z)
  return x / l, y / l, z / l
end
function M4.lookAt(eye, at, up)
  up = up or { 0, 1, 0 }
  local fx, fy, fz = norm(at[1] - eye[1], at[2] - eye[2], at[3] - eye[3])
  local sx, sy, sz = norm(fy * up[3] - fz * up[2], fz * up[1] - fx * up[3], fx * up[2] - fy * up[1])
  local ux, uy, uz = sy * fz - sz * fy, sz * fx - sx * fz, sx * fy - sy * fx
  return {
    sx, sy, sz, -(sx * eye[1] + sy * eye[2] + sz * eye[3]),
    ux, uy, uz, -(ux * eye[1] + uy * eye[2] + uz * eye[3]),
    -fx, -fy, -fz, (fx * eye[1] + fy * eye[2] + fz * eye[3]),
    0, 0, 0, 1,
  }
end
-- translation, rotation (quaternion {w,x,y,z}) and uniform or per-axis scale
function M4.trs(t, q, s)
  local w, x, y, z = 1, 0, 0, 0
  if q then w, x, y, z = q[1], q[2], q[3], q[4] end
  local sx, sy, sz = 1, 1, 1
  if type(s) == "number" then sx, sy, sz = s, s, s elseif s then sx, sy, sz = s[1], s[2], s[3] end
  return {
    (1 - 2 * (y * y + z * z)) * sx, 2 * (x * y - w * z) * sy, 2 * (x * z + w * y) * sz, t and t[1] or 0,
    2 * (x * y + w * z) * sx, (1 - 2 * (x * x + z * z)) * sy, 2 * (y * z - w * x) * sz, t and t[2] or 0,
    2 * (x * z - w * y) * sx, 2 * (y * z + w * x) * sy, (1 - 2 * (x * x + y * y)) * sz, t and t[3] or 0,
    0, 0, 0, 1,
  }
end
local function rows(m)
  return { { m[1], m[2], m[3], m[4] }, { m[5], m[6], m[7], m[8] }, { m[9], m[10], m[11], m[12] }, { m[13], m[14], m[15], m[16] } }
end

-------------------------------------------------------------------------- shader
local SHADER = [[
varying vec3 vNormal;
varying vec3 vWorld;
varying float vDepth;
#ifdef VERTEX
uniform mat4 uProj;
uniform mat4 uView;
uniform mat4 uModel;
attribute vec3 VertexNormal;
#ifdef SKINNED
attribute vec4 VertexJoints;
attribute vec4 VertexWeights;
uniform mat4 uBones[MAX_BONES];
#endif
vec4 position(mat4 transform_projection, vec4 vertex_position) {
  vec4 p = vec4(vertex_position.xyz, 1.0);
  vec3 nrm = VertexNormal;
#ifdef SKINNED
  mat4 sk = uBones[int(VertexJoints.x + 0.5)] * VertexWeights.x + uBones[int(VertexJoints.y + 0.5)] * VertexWeights.y
          + uBones[int(VertexJoints.z + 0.5)] * VertexWeights.z + uBones[int(VertexJoints.w + 0.5)] * VertexWeights.w;
  p = sk * p;
  nrm = mat3(sk) * nrm;
#endif
  vec4 world = uModel * p;
  vWorld = world.xyz;
  vNormal = mat3(uModel) * nrm;
  vec4 viewPos = uView * world;
  vDepth = -viewPos.z;
  return uProj * viewPos;
}
#endif
#ifdef PIXEL
uniform vec3 uSun;        // direction towards the sun
uniform vec3 uSunCol;
uniform vec3 uSky;        // ambient from above
uniform vec3 uGround;     // ambient from below
uniform vec3 uEye;
uniform float uSpec;      // specular strength (0 = matte)
uniform float uShine;     // specular exponent
uniform vec3 uFogCol;
uniform vec2 uFog;        // start, end distance
uniform float uUnlit;     // 1 = draw flat (UI-like decals)
uniform float uRim;       // soft edge light for round objects
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen) {
  vec4 base = Texel(tex, uv) * color;
  if (base.a < 0.02) discard;
  vec3 n = normalize(vNormal);
  // two-sided surfaces: light the side we see (see R.FLIPPED_RT for the winding)
#ifdef FLIPPED_RT
  if (gl_FrontFacing) n = -n;
#else
  if (!gl_FrontFacing) n = -n;
#endif
  float hemi = n.y * 0.5 + 0.5;
  vec3 amb = mix(uGround, uSky, hemi);
  float diff = max(dot(n, uSun), 0.0);
  // soft wrap so the shadow side never goes black (toy-like look)
  diff = diff * 0.75 + 0.25 * max(dot(n, uSun) * 0.5 + 0.5, 0.0);
  vec3 v = normalize(uEye - vWorld);
  vec3 h = normalize(uSun + v);
  float spec = pow(max(dot(n, h), 0.0), uShine) * uSpec;
  float rim = pow(1.0 - max(dot(n, v), 0.0), 3.0) * uRim;
  vec3 lit = base.rgb * (amb + uSunCol * diff) + vec3(spec) + vec3(rim);
  lit = mix(lit, base.rgb, uUnlit);
  float fog = clamp((vDepth - uFog.x) / (uFog.y - uFog.x), 0.0, 1.0);
  lit = mix(lit, uFogCol, fog * fog);
  return vec4(lit, base.a);
}
#endif
]]

local FORMAT = {
  { "VertexPosition", "float", 3 }, { "VertexTexCoord", "float", 2 },
  { "VertexNormal", "float", 3 }, { "VertexColor", "byte", 4 },
}
local FORMAT_SKIN = {
  { "VertexPosition", "float", 3 }, { "VertexTexCoord", "float", 2 },
  { "VertexNormal", "float", 3 }, { "VertexColor", "byte", 4 },
  { "VertexJoints", "float", 4 }, { "VertexWeights", "float", 4 },
}
R.MAX_BONES = 32
R.MSAA = 4 -- multisampling for new scenes (0 = off: faster)

local white
local function whiteTex()
  if not white then
    local d = love.image.newImageData(2, 2)
    d:mapPixel(function() return 1, 1, 1, 1 end)
    white = lg.newImage(d)
  end
  return white
end

-- verts: list of { x, y, z, u, v, nx, ny, nz, r, g, b, a } (colour 0..1), triangles in order
function R.mesh(verts, tex, opts)
  local mesh = lg.newMesh(FORMAT, verts, "triangles", "static")
  mesh:setTexture(tex or whiteTex())
  opts = opts or {}
  return { mesh = mesh, spec = opts.spec or 0.15, shine = opts.shine or 24, unlit = opts.unlit, alpha = opts.alpha,
    rim = opts.rim or 0,
    cull = opts.cull ~= false }
end

-- skinned mesh from core.gltf.meshes(): verts = { x, y, z, u, v, nx, ny, nz, j1..j4, w1..w4 },
-- tris = 1-based vertex indices. Draw it with Scene:add(m, model, tint, bones).
function R.skinnedMesh(verts, tris, tex, opts)
  local data = {}
  for i, v in ipairs(verts) do
    data[i] = { v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8], 1, 1, 1, 1, v[9], v[10], v[11], v[12], v[13], v[14], v[15], v[16] }
  end
  local mesh = lg.newMesh(FORMAT_SKIN, data, "triangles", "static")
  mesh:setVertexMap(tris)
  mesh:setTexture(tex or whiteTex())
  opts = opts or {}
  return { mesh = mesh, skinned = true, spec = opts.spec or 0.1, shine = opts.shine or 20, unlit = opts.unlit,
    alpha = opts.alpha, rim = opts.rim or 0, cull = opts.cull ~= false }
end

-------------------------------------------------------------------------- scene

local Scene = {}
Scene.__index = Scene

function R.scene(w, h)
  local s = setmetatable({ items = {}, w = w, h = h, msaa = R.MSAA }, Scene)
  local pre = R.FLIPPED_RT and "#define FLIPPED_RT\n" or ""
  s.shader = lg.newShader(pre .. SHADER)
  s.skinShader = lg.newShader(pre .. "#define SKINNED\n#define MAX_BONES " .. R.MAX_BONES .. "\n" .. SHADER)
  local ok, c = pcall(lg.newCanvas, w, h, { msaa = R.MSAA > 1 and R.MSAA or nil })
  s.canvas = ok and c or lg.newCanvas(w, h)
  s.light = {
    sun = { norm(-0.35, 0.85, 0.45) }, sunCol = { 0.55, 0.53, 0.50 },
    sky = { 0.62, 0.66, 0.72 }, ground = { 0.42, 0.40, 0.40 },
    fogCol = { 0.82, 0.86, 0.92 }, fog = { 30, 120 },
  }
  return s
end

function Scene:resize(w, h)
  if w == self.w and h == self.h then return end
  self.w, self.h = w, h
  local ok, c = pcall(lg.newCanvas, w, h, { msaa = self.msaa > 1 and self.msaa or nil })
  self.canvas = ok and c or lg.newCanvas(w, h)
end

function Scene:camera(eye, at, fovy, near, far)
  self.eye = eye
  self.view = M4.lookAt(eye, at)
  self.proj = M4.perspective(fovy, self.w / self.h, near or 0.05, far or 300)
end

function Scene:begin(clear)
  self.items = {}
  self.clear = clear or { 0.8, 0.85, 0.92, 1 }
end

-- queue a mesh with a model matrix (and optional colour tint; skinned meshes take the
-- skinning matrices from core.anim's Rig:skin)
function Scene:add(m, model, tint, bones)
  self.items[#self.items + 1] = { m = m, model = model or M4.identity(), tint = tint, bones = bones }
end

function Scene:render()
  local sh, L = self.shader, self.light
  lg.push("all")
  local ok = pcall(lg.setCanvas, { self.canvas, depth = true })
  if not ok then lg.setCanvas({ self.canvas, depthstencil = true }) end
  lg.clear(self.clear[1], self.clear[2], self.clear[3], self.clear[4] or 1, true, true)
  local proj = self.proj
  if R.EMULATE_12 then
    -- LÖVE 11 already swaps the front-face winding for canvases, like 12 does, so only
    -- the y flip is missing
    proj = M4.mul({ 1, 0, 0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 }, proj)
  end
  for _, s in ipairs({ sh, self.skinShader }) do
    s:send("uProj", "row", rows(proj))
    s:send("uView", "row", rows(self.view))
    s:send("uSun", L.sun); s:send("uSunCol", L.sunCol)
    s:send("uSky", L.sky); s:send("uGround", L.ground)
    s:send("uEye", self.eye)
    s:send("uFogCol", L.fogCol); s:send("uFog", L.fog)
  end
  -- opaque first, then see-through items back to front
  local opaque, alpha = {}, {}
  for _, it in ipairs(self.items) do
    if it.m.alpha then alpha[#alpha + 1] = it else opaque[#opaque + 1] = it end
  end
  local e = self.eye
  for _, it in ipairs(alpha) do
    local dx, dy, dz = it.model[4] - e[1], it.model[8] - e[2], it.model[12] - e[3]
    it.d = dx * dx + dy * dy + dz * dz
  end
  table.sort(alpha, function(a, b) return a.d > b.d end)
  local function draw(list, write)
    lg.setDepthMode("lequal", write)
    for _, it in ipairs(list) do
      local m = it.m
      local sh = m.skinned and self.skinShader or self.shader
      lg.setShader(sh)
      if m.skinned and it.bones then sh:send("uBones", "row", unpack(it.bones)) end
      -- the canvas is rendered upside down (see below), which mirrors the winding
      lg.setMeshCullMode(m.cull and (R.FLIPPED_RT and "front" or "back") or "none")
      sh:send("uModel", "row", rows(it.model))
      sh:send("uSpec", m.spec); sh:send("uShine", m.shine); sh:send("uUnlit", m.unlit and 1 or 0)
      sh:send("uRim", m.rim)
      local t = it.tint
      lg.setColor(t and t[1] or 1, t and t[2] or 1, t and t[3] or 1, t and t[4] or 1)
      lg.draw(m.mesh)
    end
  end
  draw(opaque, true)
  draw(alpha, false)
  lg.pop()
  lg.setColor(1, 1, 1, 1)
  if R.FLIPPED_RT then
    lg.draw(self.canvas, 0, self.h, 0, 1, -1)
  else
    lg.draw(self.canvas, 0, 0)
  end
end

-- project a world point to screen pixels (for HUD markers); nil when behind the camera
function Scene:toScreen(p)
  local v, pr = self.view, self.proj
  local x = v[1] * p[1] + v[2] * p[2] + v[3] * p[3] + v[4]
  local y = v[5] * p[1] + v[6] * p[2] + v[7] * p[3] + v[8]
  local z = v[9] * p[1] + v[10] * p[2] + v[11] * p[3] + v[12]
  local cx = pr[1] * x
  local cy = pr[6] * y
  local cw = -z
  if cw <= 0.01 then return nil end
  return (cx / cw * 0.5 + 0.5) * self.w, (0.5 - cy / cw * 0.5) * self.h, cw
end

return R
