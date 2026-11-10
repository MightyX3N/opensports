-- glTF 2.0 binary (.glb) reader. Pure Lua 5.1 / LuaJIT, no engine calls: it takes the
-- file's bytes as a string and gives back plain tables (shared by every shell).
-- Covers what character models need: meshes (positions, normals, UVs, joints, weights,
-- indices), one skin, node hierarchy, animations and embedded images.
local json = require("core.json")
local G = {}

local byte, sub, floor = string.byte, string.sub, math.floor

-- fast path on LuaJIT: read numbers straight out of the string's memory
local ffi_ok, ffi = pcall(require, "ffi")
if ffi_ok and not ffi.abi then ffi_ok = false end

local function u32(s, o) -- o is 0-based
  local a, b, c, d = byte(s, o + 1, o + 4)
  return a + b * 256 + c * 65536 + d * 16777216
end
G.u32 = u32

local function f32(s, o)
  local b1, b2, b3, b4 = byte(s, o + 1, o + 4)
  local sign = b4 >= 128 and -1 or 1
  local exp = (b4 % 128) * 2 + floor(b3 / 128)
  local mant = ((b3 % 128) * 256 + b2) * 256 + b1
  if exp == 0 then return sign * mant * 2 ^ -149 end
  if exp == 255 then return mant == 0 and sign * math.huge or 0 / 0 end
  return sign * (1 + mant / 8388608) * 2 ^ (exp - 127)
end
G.f32 = f32

local COMP = {
  [5120] = { 1, "i8" }, [5121] = { 1, "u8" }, [5122] = { 2, "i16" }, [5123] = { 2, "u16" },
  [5125] = { 4, "u32" }, [5126] = { 4, "f32" },
}
local NCOMP = { SCALAR = 1, VEC2 = 2, VEC3 = 3, VEC4 = 4, MAT2 = 4, MAT3 = 9, MAT4 = 16 }

-- read one component of a type at a 0-based offset
local function reader(s, kind)
  if ffi_ok then
    local base = ffi.cast("const uint8_t*", s)
    if kind == "f32" then
      return function(o) return ffi.cast("const float*", base + o)[0] end
    elseif kind == "u32" then
      return function(o) return ffi.cast("const uint32_t*", base + o)[0] end
    elseif kind == "u16" then
      return function(o) return ffi.cast("const uint16_t*", base + o)[0] end
    elseif kind == "i16" then
      return function(o) return ffi.cast("const int16_t*", base + o)[0] end
    elseif kind == "i8" then
      return function(o) return ffi.cast("const int8_t*", base + o)[0] end
    else
      return function(o) return base[o] end
    end
  end
  if kind == "f32" then return function(o) return f32(s, o) end
  elseif kind == "u32" then return function(o) return u32(s, o) end
  elseif kind == "u16" then return function(o) local a, b = byte(s, o + 1, o + 2); return a + b * 256 end
  elseif kind == "i16" then return function(o) local a, b = byte(s, o + 1, o + 2); local v = a + b * 256; return v >= 32768 and v - 65536 or v end
  elseif kind == "i8" then return function(o) local v = byte(s, o + 1); return v >= 128 and v - 256 or v end
  else return function(o) return byte(s, o + 1) end end
end

-- parse a .glb file; returns a document { json = ..., bin = <binary chunk string> }
function G.load(bytes)
  assert(sub(bytes, 1, 4) == "glTF", "not a binary glTF file")
  assert(u32(bytes, 4) == 2, "only glTF 2.0 is supported")
  local jlen = u32(bytes, 12)
  assert(sub(bytes, 17, 20) == "JSON", "first chunk must be JSON")
  local doc = { json = json.decode(sub(bytes, 21, 20 + jlen)), cache = {} }
  local o = 20 + jlen
  if o + 8 <= #bytes and sub(bytes, o + 5, o + 8) == "BIN\0" then
    doc.bin = sub(bytes, o + 9, o + 8 + u32(bytes, o))
  end
  return doc
end

-- an accessor as a flat array of numbers; returns array, count, components
function G.accessor(doc, index)
  local cached = doc.cache[index]
  if cached then return cached[1], cached[2], cached[3] end
  local J = doc.json
  local a = J.accessors[index + 1]
  local nc = NCOMP[a.type]
  local size, kind = COMP[a.componentType][1], COMP[a.componentType][2]
  local out = {}
  if a.bufferView then
    local bv = J.bufferViews[a.bufferView + 1]
    local start = (bv.byteOffset or 0) + (a.byteOffset or 0)
    local stride = bv.byteStride or size * nc
    local rd = reader(doc.bin, kind)
    local n = 0
    local scale = 1
    if a.normalized then
      scale = ({ u8 = 1 / 255, u16 = 1 / 65535, i8 = 1 / 127, i16 = 1 / 32767 })[kind] or 1
    end
    for i = 0, a.count - 1 do
      local o = start + i * stride
      for c = 0, nc - 1 do
        n = n + 1
        out[n] = rd(o + c * size) * scale
      end
    end
  else
    for i = 1, a.count * nc do out[i] = 0 end
  end
  doc.cache[index] = { out, a.count, nc }
  return out, a.count, nc
end

-- bytes of an embedded image (PNG/JPEG), or nil
function G.image(doc, index)
  local im = doc.json.images and doc.json.images[(index or 0) + 1]
  if not im or not im.bufferView then return nil end
  local bv = doc.json.bufferViews[im.bufferView + 1]
  return sub(doc.bin, (bv.byteOffset or 0) + 1, (bv.byteOffset or 0) + bv.byteLength), im.mimeType
end

-- all mesh primitives of nodes that have a mesh, as one indexed vertex list:
-- verts[i] = { x, y, z, u, v, nx, ny, nz, j1, j2, j3, j4, w1, w2, w3, w4 } (joints are
-- 0-based indices into the skin's joint list), tris = 1-based vertex indices.
-- `filter(nodeName)` can skip parts.
function G.meshes(doc, filter)
  local J = doc.json
  local verts, tris = {}, {}
  for _, node in ipairs(J.nodes or {}) do
    if node.mesh and (not filter or filter(node.name or "")) then
      for _, p in ipairs(J.meshes[node.mesh + 1].primitives) do
        local A = p.attributes
        local P, cnt = G.accessor(doc, A.POSITION)
        local N = A.NORMAL and G.accessor(doc, A.NORMAL)
        local T = A.TEXCOORD_0 and G.accessor(doc, A.TEXCOORD_0)
        local Jt = A.JOINTS_0 and G.accessor(doc, A.JOINTS_0)
        local W = A.WEIGHTS_0 and G.accessor(doc, A.WEIGHTS_0)
        local base = #verts
        for i = 0, cnt - 1 do
          local v = { P[i * 3 + 1], P[i * 3 + 2], P[i * 3 + 3],
            T and T[i * 2 + 1] or 0, T and T[i * 2 + 2] or 0,
            N and N[i * 3 + 1] or 0, N and N[i * 3 + 2] or 1, N and N[i * 3 + 3] or 0,
            0, 0, 0, 0, 1, 0, 0, 0 }
          if Jt and W then
            for k = 1, 4 do v[8 + k] = Jt[i * 4 + k]; v[12 + k] = W[i * 4 + k] end
          end
          verts[base + i + 1] = v
        end
        if p.indices then
          local I, ic = G.accessor(doc, p.indices)
          for i = 1, ic do tris[#tris + 1] = base + I[i] + 1 end
        else
          for i = 1, cnt do tris[#tris + 1] = base + i end
        end
      end
    end
  end
  return verts, tris
end

-- animations: { [name] = { name, duration, channels = { { node = nodeName, path, times, values, nc, interp } } } }
function G.animations(doc)
  local J = doc.json
  local out = {}
  for _, an in ipairs(J.animations or {}) do
    local clip = { name = an.name, duration = 0, channels = {} }
    for _, ch in ipairs(an.channels) do
      local smp = an.samplers[ch.sampler + 1]
      local times, n = G.accessor(doc, smp.input)
      local values, _, nc = G.accessor(doc, smp.output)
      local node = J.nodes[ch.target.node + 1]
      if node and times[n] then
        clip.duration = math.max(clip.duration, times[n])
        clip.channels[#clip.channels + 1] = { node = node.name, path = ch.target.path, times = times, values = values,
          nc = nc, interp = smp.interpolation or "LINEAR" }
      end
    end
    out[an.name] = clip
  end
  return out
end

return G
