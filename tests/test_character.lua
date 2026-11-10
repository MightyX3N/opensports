-- Headless tests for the character loader: JSON, glTF (.glb) reading and skeletal animation,
-- run against the real robot files in assets/characters/robot.
-- Run: python3 tools/runlua.py tests/test_character.lua  (or: LUA_PATH="./?.lua;;" luajit tests/test_character.lua)
local json = require("core.json")
local gltf = require("core.gltf")
local Anim = require("core.anim")
local fails, passes = 0, 0
local function ok(cond, msg)
  if cond then passes = passes + 1 else fails = fails + 1; print("FAIL: " .. msg) end
end
local function near(a, b, eps) return math.abs(a - b) < (eps or 1e-4) end
local function read(p)
  local f = assert(io.open(p, "rb"))
  local s = f:read("*a")
  f:close()
  return s
end

-- JSON
do
  local v = json.decode('{"a": [1, 2.5, -3e2, true, false, null, "x\\"y\\u00e9"], "b": {}, "c": []}')
  ok(v.a[1] == 1 and v.a[2] == 2.5 and v.a[3] == -300, "json numbers")
  ok(v.a[4] == true and v.a[5] == false, "json booleans")
  ok(v.a[7] == 'x"y\195\169', "json string escapes")
  ok(type(v.b) == "table" and next(v.b) == nil and #v.c == 0, "json empty object and array")
end

-- float decoding without FFI
do
  ok(gltf.f32(string.char(0, 0, 128, 63), 0) == 1, "f32 1.0")
  ok(gltf.f32(string.char(0, 0, 32, 192), 0) == -2.5, "f32 -2.5")
  ok(gltf.f32(string.char(0, 0, 0, 0), 0) == 0, "f32 0")
end

local dir = "assets/characters/robot/"
local doc = gltf.load(read(dir .. "robot.glb"))
local rig = Anim.rig(doc)
do
  local verts, tris = gltf.meshes(doc)
  ok(#verts > 5000 and #tris % 3 == 0, "robot mesh loads (" .. #verts .. " vertices)")
  local maxJ, wsum = 0, 0
  for _, v in ipairs(verts) do
    for k = 9, 12 do maxJ = math.max(maxJ, v[k]) end
    wsum = math.max(wsum, math.abs(v[13] + v[14] + v[15] + v[16] - 1))
  end
  ok(maxJ < #rig.joints, "joint indices are inside the skeleton")
  ok(wsum < 0.01, "skin weights add up to 1")
  local png = gltf.image(doc, 0)
  ok(png and png:sub(2, 4) == "PNG", "texture is embedded as PNG")
  ok(#rig.joints == 21 and rig.byName["hand.r"] and rig.byName["head"], "skeleton has 21 named joints")
end

for _, f in ipairs({ "anim_general.glb", "anim_movementbasic.glb", "anim_simulation.glb" }) do
  rig:addClips(gltf.animations(gltf.load(read(dir .. f))))
end
for _, name in ipairs({ "Idle_A", "Walking_A", "Cheering", "Hit_B" }) do
  ok(rig.clips[name] and rig:duration(name) > 0.3, "clip " .. name .. " is there")
end

do
  -- bind pose: skinning matrices are identity
  local skin = rig:skin(rig:globals(rig:restPose()))
  local worst = 0
  for _, m in ipairs(skin) do
    for i = 1, 16 do
      local id = (i == 1 or i == 6 or i == 11 or i == 16) and 1 or 0
      worst = math.max(worst, math.abs(m[i] - id))
    end
  end
  ok(worst < 1e-3, "rest pose gives identity skinning")

  -- Idle_A, frame 0, checked against an independent (Python) evaluation of the same file
  local g = rig:globals(rig:sample("Idle_A", 0))
  local h = rig:jointPos(g, "hand.r")
  ok(near(h[1], -0.47961) and near(h[2], 0.63172) and near(h[3], 0.06649), "Idle_A right hand position")
  local hd = rig:jointPos(g, "head")
  ok(near(hd[2], 1.22781), "Idle_A head height")

  -- looping and clamping
  local d = rig:duration("Walking_A")
  local a = rig:jointPos(rig:globals(rig:sample("Walking_A", 0.3)), "foot.l")
  local b = rig:jointPos(rig:globals(rig:sample("Walking_A", 0.3 + d)), "foot.l")
  ok(near(a[1], b[1]) and near(a[2], b[2]) and near(a[3], b[3]), "looping clips wrap around")
  local c1 = rig:jointPos(rig:globals(rig:sample("Hit_B", 99, false)), "head")
  local c2 = rig:jointPos(rig:globals(rig:sample("Hit_B", rig:duration("Hit_B"), false)), "head")
  ok(near(c1[2], c2[2]), "one-shot clips hold their last frame")

  -- blending halfway lands between the two poses
  local pa, pb = rig:sample("Idle_A", 0), rig:sample("Cheering", 0.6)
  local mid = rig:jointPos(rig:globals(rig:blend(pa, pb, 0.5)), "hips")
  local ya, yb = rig:jointPos(rig:globals(pa), "hips")[2], rig:jointPos(rig:globals(pb), "hips")[2]
  ok(near(mid[2], (ya + yb) / 2, 1e-3), "blend halfway")

  -- aiming the bowling arm: straight forward, straight down, straight back
  for _, want in ipairs({ { 0, 0, 1 }, { 0, -1, 0 }, { 0, 0.2, -1 } }) do
    local pose = rig:sample("Idle_A", 0.4)
    local glob = rig:globals(pose)
    rig:aim(pose, glob, "upperarm.r", "lowerarm.r", want)
    rig:aim(pose, glob, "lowerarm.r", "wrist.r", want)
    local s, w = rig:jointPos(glob, "upperarm.r"), rig:jointPos(glob, "wrist.r")
    local v = { w[1] - s[1], w[2] - s[2], w[3] - s[3] }
    local l = math.sqrt(v[1] ^ 2 + v[2] ^ 2 + v[3] ^ 2)
    local wl = math.sqrt(want[1] ^ 2 + want[2] ^ 2 + want[3] ^ 2)
    local dot = (v[1] * want[1] + v[2] * want[2] + v[3] * want[3]) / (l * wl)
    ok(dot > 0.999, string.format("aimed arm points along (%g, %g, %g)", want[1], want[2], want[3]))
    -- the shoulder itself doesn't move
    local s0 = rig:jointPos(rig:globals(rig:sample("Idle_A", 0.4)), "upperarm.r")
    ok(near(s[1], s0[1]) and near(s[2], s0[2]) and near(s[3], s0[3]), "aiming keeps the shoulder in place")
  end
end

print(string.format("%d passed, %d failed", passes, fails))
if fails > 0 then error("tests failed") end
