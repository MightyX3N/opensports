-- LÖVE input backends -> MotionController objects (architecture §3).
--   * SDL gamepads with gyro/accel (Joy-Con, Pro Controller, DualSense, DS4, many BT pads)
--   * device sensors on Android tablets/phones (love.sensor, when present)
--   * mouse / touch (gesture level)
-- Wii Remote (DolphinBar) and Joy-Con 2 backends come later (build order step 6).
local motion = require("core.motion")
local jc2 = require("shells.love.joycon2")
local ser = require("core.serialize")
local I = { list = {}, byJoystick = {}, raw = {}, nav = {}, listeners = {} }

-- logical button -> default SDL gamepad button
I.DEFAULT_BUTTONS = {
  a = "a", b = "b", one = "x", two = "y", plus = "start", minus = "back", home = "guide",
  up = "dpup", down = "dpdown", left = "dpleft", right = "dpright",
}
I.ACTIONS = { "a", "b", "one", "two", "plus", "minus", "home" }

local function safeName(s) return (s or "unknown"):gsub("[^%w%-]", "_") end

function I.loadProfile(guid)
  local data = love.filesystem.read("input/" .. safeName(guid) .. ".lua")
  local p = data and ser.load(data)
  if not p then return motion.defaultProfile() end
  local d = motion.defaultProfile()
  for k, v in pairs(d) do if p[k] == nil then p[k] = v end end
  return p
end

function I.saveProfile(c)
  love.filesystem.createDirectory("input")
  love.filesystem.write("input/" .. safeName(c.guid) .. ".lua", ser.dump(c.profile))
end

-- sensor names differ between LÖVE builds; try both spellings
local GYRO_NAMES = { "gyroscope", "gyro" }
local function sensorCall(js, fn, names, ...)
  for _, n in ipairs(names) do
    local ok, a, b, c = pcall(js[fn], js, n, ...)
    if ok then return true, a, b, c end
  end
  return false
end

local function add(c)
  c.index = #I.list + 1
  I.list[#I.list + 1] = c
  return c
end

function I.init()
  -- mouse / touch is always player-capable at the gesture level
  I.mouse = add(motion.new({ id = "mouse", kind = "mouse", name = "Mouse / touch", guid = "mouse",
    hasGyro = false, hasAccel = false, hasPointer = true }))
  I.mouse.level = motion.GESTURE
  I.mouse.drag = nil

  -- Android device sensors (tablet / phone), if this LÖVE build has love.sensor
  if love.sensor and love.sensor.hasSensor then
    local okG, hasG = pcall(love.sensor.hasSensor, "gyroscope")
    local okA, hasA = pcall(love.sensor.hasSensor, "accelerometer")
    if okG and hasG then
      pcall(love.sensor.setEnabled, "gyroscope", true)
      if okA and hasA then pcall(love.sensor.setEnabled, "accelerometer", true) end
      local c = add(motion.new({ id = "device", kind = "phone", name = "This device's gyro", guid = "device-sensors",
        profile = I.loadProfile("device-sensors") }))
      c.sensorSource = "device"
    end
  end
  for _, js in ipairs(love.joystick.getJoysticks()) do I.joystickadded(js) end
  jc2.init()
  I.jc2 = jc2
end

-- Switch 2 controllers connected by the game itself over Bluetooth LE
local function bleConnected(entry)
  local guid = string.format("jc2-%012x", tonumber(entry.addr))
  local c = add(motion.new({ id = "ble" .. entry.id, kind = "joycon2", name = entry.name, guid = guid,
    profile = I.loadProfile(guid) }))
  c.ble = entry
  -- profiles saved before the axis-frame fix would double-rotate: reset their axes once
  if c.profile.jc2frame ~= 2 then
    local d = motion.defaultProfile()
    c.profile.gyroAxes, c.profile.gyroSign = d.gyroAxes, d.gyroSign
    c.profile.accelAxes, c.profile.accelSign = d.accelAxes, d.accelSign
    c.profile.gyroScale, c.profile.accelScale = 1, 1
    c.profile.jc2frame = 2
    I.saveProfile(c)
  end
  c:recentre()
  if I.onNew then I.onNew(c) end
  return c
end
local function bleDisconnected(c)
  for i, v in ipairs(I.list) do if v == c then table.remove(I.list, i) break end end
  for i, v in ipairs(I.list) do v.index = i end
end

function I.joystickadded(js)
  if I.byJoystick[js] then return end
  local name = js:getName() or "Controller"
  local guid = (js.getGUID and js:getGUID()) or name
  local hasGyro, hasAccel = false, false
  if js.hasSensor then
    local ok, v = sensorCall(js, "hasSensor", GYRO_NAMES); hasGyro = ok and v or false
    local ok2, v2 = pcall(js.hasSensor, js, "accelerometer"); hasAccel = ok2 and v2 or false
    if hasGyro then sensorCall(js, "setSensorEnabled", GYRO_NAMES, true) end
    if hasAccel then pcall(js.setSensorEnabled, js, "accelerometer", true) end
  end
  local kind = name:find("Joy%-Con") and "joycon" or (name:find("Wii") and "wiimote") or "gyropad"
  local c = add(motion.new({ id = js, kind = kind, name = name, guid = guid,
    hasGyro = hasGyro, hasAccel = hasAccel, profile = I.loadProfile(guid) }))
  if not c.profile.level then c.level = hasGyro and motion.FULL or motion.STICK_POINTER end
  c.joystick = js
  c.onRumble = function(t, s) if js.setVibration then pcall(js.setVibration, js, s, s, t) end end
  I.byJoystick[js] = c
end

function I.joystickremoved(js)
  local c = I.byJoystick[js]
  if not c then return end
  I.byJoystick[js] = nil
  for i, v in ipairs(I.list) do if v == c then table.remove(I.list, i) break end end
  for i, v in ipairs(I.list) do v.index = i end
end

-- raw sample of a controller this frame (device axes, before the profile is applied)
local function readRaw(c)
  if c.joystick and c.joystick.getSensorData then
    local g, a
    if c.hasGyro then
      local ok, x, y, z = sensorCall(c.joystick, "getSensorData", GYRO_NAMES)
      if ok and x then g = { x, y, z } end
    end
    if c.hasAccel then
      local ok, x, y, z = pcall(c.joystick.getSensorData, c.joystick, "accelerometer")
      if ok and x then a = { x, y, z } end
    end
    return g, a
  elseif c.sensorSource == "device" then
    local okg, gx, gy, gz = pcall(love.sensor.getData, "gyroscope")
    local oka, ax, ay, az = pcall(love.sensor.getData, "accelerometer")
    return okg and gx and { gx, gy, gz } or nil, oka and ax and { ax, ay, az } or nil
  end
end

local function readButtons(c)
  local js = c.joystick
  if not js then return end
  local map = c.profile.buttons
  for logical, def in pairs(I.DEFAULT_BUTTONS) do
    local b = map[logical] or def
    local down = false
    local n = type(b) == "string" and b:match("^btn:(%d+)$")
    if n then down = js:isDown(tonumber(n))
    elseif js:isGamepad() then down = js:isGamepadDown(b) end
    c:setButton(logical, down)
  end
  if js:isGamepad() then
    c.stick = { js:getGamepadAxis("leftx"), -js:getGamepadAxis("lefty") }
  elseif js:getAxisCount() >= 2 then
    c.stick = { js:getAxis(1), -js:getAxis(2) }
  end
  -- stick doubles as D-pad for menus
  c:setButton("up", c.buttons.up or c.stick[2] > 0.6)
  c:setButton("down", c.buttons.down or c.stick[2] < -0.6)
  c:setButton("left", c.buttons.left or c.stick[1] < -0.6)
  c:setButton("right", c.buttons.right or c.stick[1] > 0.6)
end

function I.update(dt)
  jc2.update(bleConnected, bleDisconnected)
  for _, c in ipairs(I.list) do
    if c.ble then
      jc2.read(c, dt)
      I.raw[c] = c.lastRaw
    elseif c ~= I.mouse then
      readButtons(c)
      local g, a = readRaw(c)
      I.raw[c] = { g = g, a = a }
      c:feed(dt, g, a)
    else
      c.t = c.t + dt
    end
  end
end

function I.endFrame() for _, c in ipairs(I.list) do c:endFrame() end end

-- menu navigation: any controller or the keyboard can drive menus
function I.navPressed()
  local out = {}
  for _, c in ipairs(I.list) do
    for _, k in ipairs({ "up", "down", "left", "right", "a", "b", "one", "two" }) do
      if c.pressed[k] then out[k] = c end
    end
  end
  for k, v in pairs(I.nav) do out[k] = out[k] or v end
  I.nav = {}
  return out
end

local KEYS = { up = "up", down = "down", left = "left", right = "right",
  ["return"] = "a", kpenter = "a", space = "a", escape = "b", backspace = "b", tab = "two", r = "one" }
function I.keypressed(key) if KEYS[key] then I.nav[KEYS[key]] = true end end

-- raw button capture for the remap screen
function I.capture(fn, c)
  if c and c.ble then c.capture = function(button) fn(c, button) end; return end
  I.capturing = fn
end
function I.shutdown() jc2.shutdown() end
function I.gamepadpressed(js, button)
  if I.capturing and I.byJoystick[js] then local f = I.capturing; I.capturing = nil; f(I.byJoystick[js], button) end
end
function I.joystickpressed(js, n)
  if I.capturing and I.byJoystick[js] and not js:isGamepad() then
    local f = I.capturing; I.capturing = nil; f(I.byJoystick[js], "btn:" .. n)
  end
end

return I
