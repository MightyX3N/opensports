-- Player settings, saved as plain Lua data in the save folder (settings.lua), plus the
-- list of Joy-Con 2 controllers this computer has connected before.
local ser = require("core.serialize")
local S = {}

S.DEFAULTS = {
  fullscreen = false,
  quality = "high",          -- "high" = smooth edges (MSAA 4), "low" = faster
  swing = "normal",          -- swing strength needed for a fast ball: "light", "normal", "strong"
  aimLine = true,            -- dotted aim guide on the lane
  physics = "arcade",        -- last bowling physics choice
  volume = "high",           -- sound effects: "high", "medium", "low", "off"
  autoConnect = true,        -- listen for saved Joy-Cons and connect them when they wake up
  saved = {},                -- { { addr = "hex", pid = n, name = "...", last = time } }
}

-- the choices offered for each setting, in order (used by the settings screen)
S.CHOICES = {
  fullscreen = { false, true },
  quality = { "high", "low" },
  swing = { "light", "normal", "strong" },
  aimLine = { true, false },
  volume = { "high", "medium", "low", "off" },
  autoConnect = { true, false },
}

local data
local FILE = "settings.lua"

function S.load()
  data = {}
  local txt = love and love.filesystem and love.filesystem.read(FILE)
  local loaded = txt and ser.load(txt)
  if type(loaded) == "table" then data = loaded end
  for k, v in pairs(S.DEFAULTS) do
    if data[k] == nil then data[k] = type(v) == "table" and {} or v end
  end
  return data
end

function S.save()
  if not data then return end
  if love and love.filesystem then love.filesystem.write(FILE, ser.dump(data)) end
end

function S.get(k)
  if not data then S.load() end
  return data[k]
end

function S.set(k, v)
  if not data then S.load() end
  data[k] = v
  S.save()
end

-- step a setting to its next (dir = 1) or previous (-1) choice; returns the new value
function S.cycle(k, dir)
  local list = S.CHOICES[k]
  local cur = S.get(k)
  local i = 1
  for j, v in ipairs(list) do if v == cur then i = j end end
  i = (i - 1 + (dir or 1)) % #list + 1
  S.set(k, list[i])
  return list[i]
end

------------------------------------------------------------------ saved controllers
-- (pure functions over a list, so they can be tested without LÖVE)

local function key(addr)
  if type(addr) == "string" then return addr:lower() end
  return string.format("%012x", tonumber(addr) or 0)
end
S.addrKey = key

-- the saved entry for a Bluetooth address, or nil
function S.findSaved(list, addr)
  local k = key(addr)
  for i, e in ipairs(list) do if e.addr == k then return e, i end end
end

-- remember a controller (newest first, no duplicates)
function S.remember(list, addr, pid, name, now)
  local e, i = S.findSaved(list, addr)
  if i then table.remove(list, i) end
  e = { addr = key(addr), pid = pid, name = name, last = now or 0 }
  table.insert(list, 1, e)
  while #list > 8 do table.remove(list) end
  return e
end

function S.forget(list, addr)
  local _, i = S.findSaved(list, addr)
  if i then table.remove(list, i) end
end

return S
