-- DSU ("cemuhook") motion protocol client: packet build/parse only, no sockets.
-- DSU is what Dolphin, Cemu, Yuzu/Ryujinx read; servers include joycon2cpp (Joy-Con 2 on
-- Windows), joycon2android, BetterJoy (Joy-Con 1/Pro), DS4Windows, SteamDeckGyroDSU.
-- Packet layout and axis meanings follow Dolphin's DualShockUDPClient (GPL-2+), protocol 1001.
local bitlib = bit or bit32
local band, bxor, rshift = bitlib.band, bitlib.bxor, bitlib.rshift
local M = { PORT = 26760, VERSION = 1001 }

-- CRC-32 (zlib/IEEE)
local CRC = {}
for i = 0, 255 do
  local c = i
  for _ = 1, 8 do
    if band(c, 1) == 1 then c = bxor(rshift(c, 1), 0xEDB88320) else c = rshift(c, 1) end
  end
  CRC[i] = c
end
function M.crc32(s)
  local c = 0xFFFFFFFF
  for i = 1, #s do c = bxor(rshift(c, 8), CRC[band(bxor(c, s:byte(i)), 0xFF)]) end
  c = bxor(c, 0xFFFFFFFF)
  if c < 0 then c = c + 4294967296 end
  return c
end

local function u8(n) return string.char(n % 256) end
local function u16(n) return string.char(n % 256, math.floor(n / 256) % 256) end
local function u32(n)
  return string.char(n % 256, math.floor(n / 256) % 256, math.floor(n / 65536) % 256, math.floor(n / 16777216) % 256)
end
local function ru16(s, o) return s:byte(o + 1) + s:byte(o + 2) * 256 end
local function ru32(s, o) return ru16(s, o) + ru16(s, o + 2) * 65536 end
local function rf32(s, o) -- little-endian IEEE754 single
  local b1, b2, b3, b4 = s:byte(o + 1, o + 4)
  local sign = b4 >= 128 and -1 or 1
  local exp = (b4 % 128) * 2 + math.floor(b3 / 128)
  local mant = ((b3 % 128) * 256 + b2) * 256 + b1
  if exp == 0 then return sign * mant * 2 ^ -149 end
  if exp == 255 then return 0 end
  return sign * (1 + mant / 8388608) * 2 ^ (exp - 127)
end
M.rf32 = rf32

local function packet(uid, msgType, payload)
  local body = u32(msgType) .. payload
  -- message_length = packet size minus the 16-byte header
  local head = "DSUC" .. u16(M.VERSION) .. u16(#body)
  local pkt = head .. u32(0) .. u32(uid) .. body
  local crc = M.crc32(pkt)
  return head .. u32(crc) .. u32(uid) .. body
end

function M.listPorts(uid) return packet(uid, 0x100001, u32(4) .. string.char(0, 1, 2, 3)) end
-- register for every pad (flags 0)
function M.padDataRequest(uid) return packet(uid, 0x100002, u8(0) .. u8(0) .. string.rep("\0", 6)) end

-- parse a server datagram; returns table for pad data, or nil
function M.parse(s)
  if #s < 20 or s:sub(1, 4) ~= "DSUS" then return nil end
  local crcIn = ru32(s, 8)
  local zeroed = s:sub(1, 8) .. "\0\0\0\0" .. s:sub(13)
  if M.crc32(zeroed) ~= crcIn then return nil, "crc" end
  local msgType = ru32(s, 16)
  if msgType ~= 0x100002 or #s < 100 then return { type = msgType } end
  local d = {
    type = msgType,
    pad = s:byte(21), state = s:byte(22), model = s:byte(23), connection = s:byte(24),
    mac = string.format("%02x%02x%02x%02x%02x%02x", s:byte(25, 30)),
    battery = s:byte(31), active = s:byte(32), counter = ru32(s, 32),
    buttons1 = s:byte(37), buttons2 = s:byte(38), ps = s:byte(39), touchButton = s:byte(40),
    lx = s:byte(41), ly = s:byte(42), rx = s:byte(43), ry = s:byte(44),
    r2 = s:byte(55), l2 = s:byte(56),
    timestamp = ru32(s, 68) + ru32(s, 72) * 4294967296, -- µs
    accel = { rf32(s, 76), rf32(s, 80), rf32(s, 84) }, -- g
    gyro = { rf32(s, 88), rf32(s, 92), rf32(s, 96) },  -- pitch, yaw, roll in °/s
  }
  return d
end

-- DS4-style button bits in DSU
M.BUTTONS = {
  share = { 1, 0 }, l3 = { 1, 1 }, r3 = { 1, 2 }, options = { 1, 3 }, up = { 1, 4 }, right = { 1, 5 }, down = { 1, 6 }, left = { 1, 7 },
  l2 = { 2, 0 }, r2 = { 2, 1 }, l1 = { 2, 2 }, r1 = { 2, 3 }, triangle = { 2, 4 }, circle = { 2, 5 }, cross = { 2, 6 }, square = { 2, 7 },
}
function M.down(d, name)
  if name == "ps" then return d.ps ~= 0 end
  if name == "touch" then return d.touchButton ~= 0 end
  local b = M.BUTTONS[name]
  if not b then return false end
  local v = b[1] == 1 and d.buttons1 or d.buttons2
  return math.floor(v / 2 ^ b[2]) % 2 == 1
end

-- DSU motion -> core.math frame (x right, y up, z towards the player), rad/s and m/s².
-- Meanings as Dolphin reads them: pitch + = up, yaw + = right, roll + = right;
-- accel: up = -y, left = +x, forward = +z.
local G, R = 9.80665, math.pi / 180
function M.toGame(d)
  local g = { d.gyro[1] * R, -d.gyro[2] * R, -d.gyro[3] * R }
  local a = { -d.accel[1] * G, -d.accel[2] * G, -d.accel[3] * G }
  return g, a
end

return M
