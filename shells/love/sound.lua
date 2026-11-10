-- Sound effects: loads the generated sounds in assets/sounds (see tools/sfx/make_sounds.py),
-- plays one-shots from a small pool of voices per file (picking a random variant when a
-- sound has _1, _2 ... files) and runs loops (rolling ball, hall ambience).
-- Everything is a no-op when there is no audio device (headless tests, CI).
local settings = require("shells.love.settings")

local S = {}

local ROOT = "assets/sounds/"
local VOICES_PER_FILE = 6
local MAX_VOICES = 40

local ok = love and love.audio and love.sound and pcall(function() return love.audio.getActiveSourceCount() end)
local data = {}    -- name -> { SoundData, ... } (variants)
local pools = {}   -- SoundData -> { Source, ... }
local loops = {}   -- name -> Source

S.VOLUMES = { high = 1.0, medium = 0.6, low = 0.3, off = 0 }

function S.available() return ok end

function S.master()
  return S.VOLUMES[settings.get("volume") or "high"] or 1
end

local function exists(p) return love.filesystem.getInfo(p) ~= nil end

-- the variants of a sound: "bowling/pin_pin" -> pin_pin_1.ogg, pin_pin_2.ogg ... or pin_pin.ogg
local function variants(name)
  local v = data[name]
  if v then return v end
  v = {}
  if ok then
    if exists(ROOT .. name .. ".ogg") then
      v[1] = love.sound.newSoundData(ROOT .. name .. ".ogg")
    else
      local i = 1
      while exists(ROOT .. name .. "_" .. i .. ".ogg") do
        v[i] = love.sound.newSoundData(ROOT .. name .. "_" .. i .. ".ogg")
        i = i + 1
      end
    end
  end
  data[name] = v
  return v
end

-- load a list of sounds now (so the first hit doesn't stall a frame)
function S.preload(names)
  if not ok then return end
  for _, n in ipairs(names) do
    for _, sd in ipairs(variants(n)) do
      pools[sd] = pools[sd] or {}
      if #pools[sd] == 0 then pools[sd][1] = love.audio.newSource(sd) end
    end
  end
end

local function voiceFor(sd)
  local pool = pools[sd]
  if not pool then pool = {}; pools[sd] = pool end
  for _, src in ipairs(pool) do
    if not src:isPlaying() then return src end
  end
  if #pool < VOICES_PER_FILE and love.audio.getActiveSourceCount() < MAX_VOICES then
    local src = love.audio.newSource(sd)
    pool[#pool + 1] = src
    return src
  end
  -- all busy: take over the one that has played longest
  local best, bestT = nil, -1
  for _, src in ipairs(pool) do
    local t = src:tell()
    if t > bestT then best, bestT = src, t end
  end
  if best then best:stop() end
  return best
end

-- where a sound is: pos = {x, y, z} in the world (heard from the listener, quieter with
-- distance, with the room's echo) or nil (played straight to the ears: menus, tunes, crowd)
local function place(src, sd, pos, opts)
  if sd:getChannelCount() ~= 1 then return end -- only mono sounds can be placed
  if pos then
    src:setRelative(false)
    src:setPosition(pos[1], pos[2], pos[3])
    src:setAttenuationDistances(opts and opts.near or S.NEAR, S.FAR)
    src:setRolloff(opts and opts.rolloff or S.ROLLOFF)
  else
    src:setRelative(true)
    src:setPosition(0, 0, 0)
  end
  if S.room then
    local wantRoom = pos ~= nil and not (opts and opts.dry)
    pcall(src.setEffect, src, "room", wantRoom)
  end
end

-- play a one-shot. vol 0..1, pitch (1 = as made), pos {x, y, z} or nil, opts { near, dry }
function S.play(name, vol, pitch, pos, opts)
  if not ok then return end
  local m = S.master()
  if m <= 0 then return end
  local v = variants(name)
  if #v == 0 then return end
  local sd = v[love.math.random(#v)]
  local src = voiceFor(sd)
  if not src then return end
  src:setVolume(math.max(0, math.min(1, (vol or 1) * m)))
  src:setPitch(pitch or 1)
  place(src, sd, pos, opts)
  src:play()
  return src
end

-- change the volume of a playing one-shot (vol before the master volume)
function S.setVolume(src, vol)
  if src then src:setVolume(math.max(0, math.min(1, vol * S.master()))) end
end

-- a looping sound kept by name: S.loop(name, vol, pitch, pos) each frame; vol 0 pauses it
function S.loop(name, vol, pitch, pos)
  if not ok then return end
  local src = loops[name]
  local m = S.master()
  if not src then
    if (vol or 0) * m <= 0 then return end
    local v = variants(name)
    if #v == 0 then return end
    src = love.audio.newSource(v[1])
    src:setLooping(true)
    loops[name] = { src = src, sd = v[1] }
    src = loops[name]
  end
  local s_, sd = src.src, src.sd
  local vv = (vol or 0) * m
  if vv <= 0.001 then
    if s_:isPlaying() then s_:pause() end
    return
  end
  s_:setVolume(math.min(1, vv))
  s_:setPitch(math.max(0.1, pitch or 1))
  place(s_, sd, pos)
  if not s_:isPlaying() then s_:play() end
end

-- the ears: at the camera, looking at its target
function S.listener(pos, target)
  if not ok then return end
  local fx, fy, fz = target[1] - pos[1], target[2] - pos[2], target[3] - pos[3]
  local l = math.sqrt(fx * fx + fy * fy + fz * fz)
  if l < 1e-6 then return end
  fx, fy, fz = fx / l, fy / l, fz / l
  -- up: world up made square to forward
  local d = fy
  local ux, uy, uz = -d * fx, 1 - d * fy, -d * fz
  local ul = math.sqrt(ux * ux + uy * uy + uz * uz)
  love.audio.setPosition(pos[1], pos[2], pos[3])
  love.audio.setOrientation(fx, fy, fz, ux / ul, uy / ul, uz / ul)
end

function S.stopLoops()
  for _, l in pairs(loops) do l.src:stop() end
end

-- UI sounds, with a short guard so a held key doesn't machine-gun them
local last = {}
function S.ui(kind, vol)
  local now = love.timer and love.timer.getTime() or 0
  if last[kind] and now - last[kind] < 0.04 then return end
  last[kind] = now
  S.play("ui/" .. kind, (vol or 1) * 0.7)
end

-- distance: full volume within NEAR metres, then fading (inverse distance, clamped)
S.NEAR, S.FAR, S.ROLLOFF = 7, 80, 0.9

function S.init()
  if not ok then return end
  love.audio.setDistanceModel("inverseclamped")
  love.audio.setPosition(0, 0, 0)
  love.audio.setOrientation(0, 0, -1, 0, 1, 0)
  -- one shared room echo for placed sounds (the recordings that already have the hall in
  -- them are played dry)
  if love.audio.isEffectsSupported and love.audio.isEffectsSupported() then
    S.room = pcall(love.audio.setEffect, "room", {
      type = "reverb", gain = 0.2, highgain = 0.7, density = 0.7, diffusion = 0.9, decaytime = 1.25,
      decayhighratio = 0.55, earlygain = 0.4, lategain = 0.7, airabsorption = 0.994,
    }) or nil
  end
  S.preload({ "ui/move", "ui/select", "ui/back", "ui/toggle", "ui/start" })
end

return S
