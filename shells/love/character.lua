-- Animated glTF characters for the LÖVE shell: loads a model plus animation files made for
-- the same skeleton (core.gltf / core.anim), plays and crossfades clips, lets the game
-- override bones (e.g. the bowling arm follows the controller) and draws it with gfx3d.
local gltf = require("core.gltf")
local Anim = require("core.anim")
local gfx = require("shells.love.gfx3d")
local lg = love.graphics

local C = {}
local cache = {}

local function read(path) return assert(love.filesystem.read(path), "missing " .. path) end

-- load a character folder once: model file + animation files
function C.load(dir, model, animFiles)
  local key = dir .. "/" .. model
  if cache[key] then return cache[key] end
  local doc = gltf.load(read(dir .. "/" .. model))
  local rig = Anim.rig(doc)
  rig:addClips(gltf.animations(doc))
  for _, f in ipairs(animFiles or {}) do rig:addClips(gltf.animations(gltf.load(read(dir .. "/" .. f)))) end
  local tex
  local png = gltf.image(doc, 0)
  if png then
    local img = lg.newImage(love.image.newImageData(love.filesystem.newFileData(png, "skin.png")), { mipmaps = true })
    img:setFilter("linear", "linear", 4)
    img:setMipmapFilter("linear")
    tex = img
  end
  local verts, tris = gltf.meshes(doc)
  local def = { rig = rig, tex = tex, mesh = gfx.skinnedMesh(verts, tris, tex, { spec = 0.10, shine = 20, rim = 0.02 }) }
  cache[key] = def
  return def
end

local Inst = {}
Inst.__index = Inst

-- a character in the world: def from C.load, scale to metres
function C.new(def, scale)
  local c = setmetatable({ def = def, rig = def.rig, scale = scale or 1, clip = nil, t = 0, rate = 1, loop = true,
    prev = nil, prevT = 0, prevRate = 1, prevLoop = true, fade = 0, fadeLen = 0 }, Inst)
  return c
end

-- switch to a clip, crossfading from the current one over `fade` seconds
function Inst:play(name, opts)
  opts = opts or {}
  if self.clip == name and not opts.restart then
    self.rate = opts.rate or self.rate
    return
  end
  if self.clip then
    self.prev, self.prevT, self.prevRate, self.prevLoop = self.clip, self.t, self.rate, self.loop
    self.fadeLen = opts.fade or 0.25
    self.fade = self.fadeLen
  end
  self.clip, self.t, self.rate = name, opts.at or 0, opts.rate or 1
  self.loop = opts.loop ~= false
end

function Inst:update(dt)
  self.t = self.t + dt * self.rate
  if self.prev then self.prevT = self.prevT + dt * self.prevRate end
  if self.fade > 0 then
    self.fade = self.fade - dt
    if self.fade <= 0 then self.prev = nil end
  end
end

-- has a non-looping clip reached its end?
function Inst:done() return not self.loop and self.t >= self.rig:duration(self.clip) end

-- current pose and joint matrices (model space, before placement and scale)
function Inst:pose()
  local rig = self.rig
  local pose = rig:sample(self.clip, self.t, self.loop)
  if self.prev and self.fade > 0 then
    local from = rig:sample(self.prev, self.prevT, self.prevLoop)
    local k = 1 - self.fade / self.fadeLen
    pose = rig:blend(from, pose, k * k * (3 - 2 * k))
  end
  return pose, rig:globals(pose)
end

-- placement matrix: stand at pos, turned by yaw (radians about +y; 0 faces +z like the
-- model files, math.pi faces -z like the player)
function C.place(pos, yaw, scale)
  local h = yaw / 2
  return gfx.M4.trs(pos, { math.cos(h), 0, math.sin(h), 0 }, scale)
end

-- world position of a joint
function C.toWorld(model, p)
  return { model[1] * p[1] + model[2] * p[2] + model[3] * p[3] + model[4],
    model[5] * p[1] + model[6] * p[2] + model[7] * p[3] + model[8],
    model[9] * p[1] + model[10] * p[2] + model[11] * p[3] + model[12] }
end

-- queue the character into a gfx3d scene with a given pose's joint matrices
function Inst:draw(scene, model, glob, tint)
  local skin = self.rig:skin(glob)
  scene:add(self.def.mesh, model, tint, skin)
end

return C
