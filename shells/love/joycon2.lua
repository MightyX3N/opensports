-- Joy-Con 2 / Pro Controller 2 over Bluetooth LE, through native/osble (Windows).
-- Windows can't pair these as normal gamepads, so the game scans and connects itself.
-- Report layout (common report 0x05, 63 bytes): linux-switch2 PROTOCOL.md §29–37.
local ok, ffi = pcall(require, "ffi")
local motion = require("core.motion")
local jmap = require("shells.love.joycon2map")
local B = { available = false, found = {}, status = nil, pads = {} }

local G = 9.80665
-- Scales and axis order follow SDL's Switch 2 driver (SDL_hidapi_switch2.c): 8 g and
-- 34.8 rad/s full scale, raw (x, y, z) -> (x, z, -y). That frame has the controller's top
-- end pointing along -z and the button face along +y, which is exactly how a Joy-Con is
-- held like a Wii Remote, so it matches core.math's convention with no further rotation.
B.ACCEL_SCALE = G * 8 / 32767   -- m/s² per count
B.GYRO_SCALE = 34.8 / 32767     -- rad/s per count

B.NAMES = { [0x2066] = "Joy-Con 2 (R)", [0x2067] = "Joy-Con 2 (L)", [0x2069] = "Pro Controller 2", [0x2073] = "GameCube Controller (NSO)" }

-- button bits: byte offset 4.. (linux-switch2 §30)
B.BUTTONS = {
  Y = { 0, 0 }, X = { 0, 1 }, B = { 0, 2 }, A = { 0, 3 }, SR_R = { 0, 4 }, SL_R = { 0, 5 }, R = { 0, 6 }, ZR = { 0, 7 },
  MINUS = { 1, 0 }, PLUS = { 1, 1 }, RSTICK = { 1, 2 }, LSTICK = { 1, 3 }, HOME = { 1, 4 }, CAPTURE = { 1, 5 }, C = { 1, 6 },
  DOWN = { 2, 0 }, UP = { 2, 1 }, RIGHT = { 2, 2 }, LEFT = { 2, 3 }, SR_L = { 2, 4 }, SL_L = { 2, 5 }, L = { 2, 6 }, ZL = { 2, 7 },
}
-- held upright like a Wii Remote: the face button under the thumb is A, the back trigger is B
B.DEFAULTS = {
  [0x2066] = { a = "A", b = "ZR", one = "B", two = "Y", plus = "PLUS", minus = "X", home = "HOME" },
  [0x2067] = { a = "RIGHT", b = "ZL", one = "DOWN", two = "LEFT", plus = "UP", minus = "MINUS", home = "CAPTURE" },
  [0x2069] = { a = "A", b = "B", one = "X", two = "Y", plus = "PLUS", minus = "MINUS", home = "HOME",
    up = "UP", down = "DOWN", left = "LEFT", right = "RIGHT" },
}
B.DEFAULTS[0x2073] = B.DEFAULTS[0x2069]

local lib
function B.init()
  if not ok or not ffi or ffi.os ~= "Windows" then B.reason = "Bluetooth pairing in the game is Windows-only for now"; return end
  ffi.cdef [[
    typedef struct { int type; int id; uint64_t addr; int pid; int rssi; char text[96]; } osble_event;
    int osble_version(void);
    int osble_scan(int on);
    int osble_poll(osble_event* out, int max);
    int osble_connect(uint64_t addr, int pid);
    int osble_reports(int id, uint8_t* out, int max);
    int osble_leds(int id, int pattern);
    void osble_disconnect(int id);
    void osble_shutdown(void);
  ]]
  local tried = {}
  for _, dir in ipairs({ love.filesystem.getSourceBaseDirectory(), love.filesystem.getSource(), "." }) do
    local path = dir .. "/osble.dll"
    tried[#tried + 1] = path
    local good, l = pcall(ffi.load, path)
    if good then lib = l; break end
  end
  if not lib then B.reason = "osble.dll not found next to the game"; return end
  B.available = true
  B.events = ffi.new("osble_event[32]")
  B.buf = ffi.new("uint8_t[?]", 64 * 64)
end

function B.scan(on)
  if not B.available then return end
  if on then B.found = {}; B.status = "Searching… press the small SYNC button on the controller's rail" end
  lib.osble_scan(on and 1 or 0)
  B.scanning = on
end

function B.connect(entry)
  if not B.available or entry.id then return end
  entry.id = lib.osble_connect(entry.addr, entry.pid)
  entry.state = "connecting"
  B.pads[entry.id] = entry
end

local function u16(p, o) return p[o] + p[o + 1] * 256 end
local function u32(p, o) return p[o] + p[o + 1] * 256 + p[o + 2] * 65536 + p[o + 3] * 16777216 end
local function s16(p, o) local v = u16(p, o); return v >= 32768 and v - 65536 or v end

local function stick(p, o)
  local x = p[o] + (bit.band(p[o + 1], 0x0F) * 256)
  local y = bit.rshift(p[o + 1], 4) + p[o + 2] * 16
  local function n(v) return math.max(-1, math.min(1, (v - 2048) / 1500)) end
  return n(x), n(y)
end

function B.pressedButton(p)
  for name, bb in pairs(B.BUTTONS) do
    if bit.band(p[4 + bb[1]], bit.lshift(1, bb[2])) ~= 0 then return name end
  end
end

-- returns newly connected MotionControllers (caller adds them to the input list)
function B.update(onConnected, onDisconnected)
  if not B.available then return end
  local n = lib.osble_poll(B.events, 32)
  for i = 0, n - 1 do
    local e = B.events[i]
    local text = ffi.string(e.text)
    if e.type == 1 then -- found
      local entry = { addr = e.addr, pid = e.pid, rssi = e.rssi, name = B.NAMES[e.pid] or string.format("Switch 2 controller %04X", e.pid), state = "found" }
      B.found[#B.found + 1] = entry
    elseif e.type == 2 then -- connected
      local entry = B.pads[e.id]
      if entry then
        entry.state = "connected"
        entry.ctrl = onConnected(entry)
        lib.osble_leds(e.id, ({ 0x01, 0x03, 0x07, 0x0F })[math.min(4, entry.ctrl.index or 1)] or 0x01)
      end
    elseif e.type == 3 then -- disconnected
      local entry = B.pads[e.id]
      if entry then
        entry.state = "lost"
        if entry.ctrl then onDisconnected(entry.ctrl) end
        lib.osble_disconnect(e.id)
        B.pads[e.id] = nil
      end
    elseif e.type == 4 then
      local entry = B.pads[e.id]
      if entry then entry.statusText = text end
    elseif e.type == 5 then
      local entry = B.pads[e.id]
      if entry then entry.state = "failed"; entry.statusText = text; entry.id = nil; B.pads[e.id] = nil
      else B.status = text end
    end
  end
end

-- feed queued reports into the controller; called every frame
function B.read(c, frameDt)
  local id = c.ble and c.ble.id
  if not id then return end
  local n = lib.osble_reports(id, B.buf, 64)
  if n <= 0 then return end
  local defaults = B.DEFAULTS[c.ble.pid] or B.DEFAULTS[0x2069]
  for i = 0, n - 1 do
    local p = B.buf + i * 64
    -- Time step per report, done the way SDL's Switch 2 driver does it: the motion
    -- timestamp is normally microseconds (gyro full scale 34.8 rad/s) but some firmware
    -- counts in other units (then the gyro full scale is 40 rad/s). Measure it once
    -- against the wall clock over the first ~100 reports.
    local ts = u32(p, 0x2A)
    local now = love.timer.getTime()
    local dt
    if not c.tsCal then c.tsCal = { n = 0, ts0 = nil, t0 = nil } end
    local tc = c.tsCal
    if not tc.done and ts ~= 0 then
      if not tc.ts0 then tc.ts0, tc.t0 = ts, now
      else
        tc.n = tc.n + 1
        if tc.n >= 100 and now - tc.t0 > 0.3 then
          local span = ts - tc.ts0
          if span < 0 then span = span + 4294967296 end
          local perSec = span / (now - tc.t0)
          if math.abs(perSec / 1e6 - 1) < 0.1 then
            tc.tick, c.gyroFull = 1e-6, 34.8
          elseif perSec > 0 then
            tc.tick, c.gyroFull = 1 / perSec, 40.0
          end
          tc.done = true
        end
      end
    end
    if tc.tick and c.bleTs then
      local d = ts - c.bleTs
      if d < 0 then d = d + 4294967296 end
      local s = d * tc.tick
      if s > 0 and s < 0.06 then dt = s end
    end
    c.bleTs = ts
    dt = dt or frameDt / n
    local g, a = jmap.convert(c.ble.pid, { s16(p, 0x36), s16(p, 0x38), s16(p, 0x3A) },
      { s16(p, 0x30), s16(p, 0x32), s16(p, 0x34) }, c.gyroFull)
    if B.log and B.log.ctrl == c then
      local hex = {}
      for k = 0, 0x3D do hex[#hex + 1] = string.format("%02x", p[k]) end
      B.log.lines[#B.log.lines + 1] = string.format("%.4f %.5f %s", love.timer.getTime() - B.log.t0, dt, table.concat(hex))
    end
    c.lastRaw = { g = g, a = a }
    c:feed(dt, g, a)
    if i == n - 1 then
      local map = c.profile.buttons
      for logical in pairs({ a = 1, b = 1, one = 1, two = 1, plus = 1, minus = 1, home = 1, up = 1, down = 1, left = 1, right = 1 }) do
        local name = map[logical] and map[logical]:match("^jc:(.+)$") or defaults[logical]
        local bb = name and B.BUTTONS[name]
        c:setButton(logical, bb and bit.band(p[4 + bb[1]], bit.lshift(1, bb[2])) ~= 0 or false)
      end
      local sx, sy = stick(p, c.ble.pid == 0x2066 and 0x0D or 0x0A)
      c.stick = { sx, sy }
      c:setButton("up", c.buttons.up or sy > 0.6)
      c:setButton("down", c.buttons.down or sy < -0.6)
      c:setButton("left", c.buttons.left or sx < -0.6)
      c:setButton("right", c.buttons.right or sx > 0.6)
      c.rawButtons = p -- for the remap screen (valid until the next read)
      if c.capture then
        local name = B.pressedButton(p)
        if name then local f = c.capture; c.capture = nil; f("jc:" .. name) end
      end
    end
  end
end

-- diagnostics: record raw reports of one controller for `secs` seconds to the save folder
function B.startLog(c, secs)
  B.log = { ctrl = c, t0 = love.timer.getTime(), secs = secs or 12, lines = { "# time dt hex(0x00..0x3d) pid=" .. string.format("%04x", c.ble.pid) } }
end
function B.logTick()
  local L = B.log
  if not L then return end
  local left = L.secs - (love.timer.getTime() - L.t0)
  if left <= 0 then
    local name = os.date("jc2-log-%Y%m%d-%H%M%S.txt")
    love.filesystem.write(name, table.concat(L.lines, "\n"))
    B.lastLog = love.filesystem.getSaveDirectory() .. "/" .. name
    B.log = nil
    pcall(love.system.openURL, "file:///" .. love.filesystem.getSaveDirectory():gsub("\\", "/"))
  end
  return left
end

function B.shutdown() if B.available then lib.osble_shutdown() end end

return B
