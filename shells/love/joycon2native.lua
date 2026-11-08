-- Decoder for Joy-Con 2 native side reports (0x07 left / 0x08 right) over BLE.
-- These carry the controller's OWN orientation quaternion (it fuses its IMU internally at a
-- high rate), so fast swings can't throw the game's tracking off like 33 Hz raw gyro can.
-- Field map from linux-switch2 PROTOCOL.md §13, §19–27 (our own implementation of the spec).
-- `get(i)` returns byte i (0-based) of the 63-byte GATT value.
local M = {}
local SQRT2 = math.sqrt(2)
local GYRO = math.rad(500) / 16384   -- rad/s per native count
local ACC = 1 / 4096                  -- g per count

local function bits(buf, pos, n) -- little-endian bit stream, bit 0 = LSB of byte 0
  local v, mul = 0, 1
  for i = 0, n - 1 do
    local b = pos + i
    local byte = buf[math.floor(b / 8)] or 0
    if math.floor(byte / 2 ^ (b % 8)) % 2 == 1 then v = v + mul end
    mul = mul * 2
  end
  return v
end
local function sbits(buf, pos, n)
  local v = bits(buf, pos, n)
  if v >= 2 ^ (n - 1) then v = v - 2 ^ n end
  return v
end
M.bits, M.sbits = bits, sbits

local function quat(sel, r0, r1, r2, nbits)
  local maxv = 2 ^ nbits - 1
  local function c(r) return (2 * r / maxv - 1) / SQRT2 end
  local a, b, d = c(r0), c(r1), c(r2)
  local miss = math.sqrt(math.max(0, 1 - a * a - b * b - d * d))
  local q = {}
  if sel == 0 then q[0], q[1], q[2], q[3] = a, b, d, miss
  elseif sel == 1 then q[1], q[2], q[3], q[0] = a, b, d, miss
  elseif sel == 2 then q[2], q[3], q[0], q[1] = a, b, d, miss
  else q[3], q[0], q[1], q[2] = a, b, d, miss end
  return { q[3], q[0], q[1], q[2] } -- {w, x, y, z} in native body axes
end

-- returns a table or nil if the packet carries no motion
function M.decode(get, pid)
  local buf = {}
  for i = 0, 62 do buf[i] = get(i) end
  -- right Joy-Con has an extra NFC-state byte before the motion length (§19)
  if buf[14] == 0 and (buf[15] == 0x28 or buf[15] == 0x1e) then
    for i = 14, 61 do buf[i] = buf[i + 1] end
    buf[62] = 0
  end
  local len = buf[14]
  if len == 0x28 then
    return {
      kind = "ordinary",
      time12 = bits(buf, 120, 12), dtime8 = bits(buf, 132, 8), prefix = bits(buf, 140, 8),
      q = quat(bits(buf, 154, 2), bits(buf, 157, 21), bits(buf, 178, 21), bits(buf, 199, 21), 21),
      g2 = { sbits(buf, 263, 15) * GYRO, sbits(buf, 279, 15) * GYRO, sbits(buf, 295, 15) * GYRO },
      g3 = { sbits(buf, 350, 15) * GYRO, sbits(buf, 366, 15) * GYRO, sbits(buf, 382, 15) * GYRO },
      a0 = { sbits(buf, 220, 14) * ACC, sbits(buf, 234, 14) * ACC, sbits(buf, 248, 14) * ACC },
      a2 = { sbits(buf, 397, 14) * ACC, sbits(buf, 411, 14) * ACC, sbits(buf, 425, 14) * ACC },
    }
  elseif len == 0x1e then
    local b0 = 120
    return {
      kind = "compact",
      time12 = bits(buf, b0, 12),
      q = quat(bits(buf, b0 + 32, 2), bits(buf, b0 + 41, 25), bits(buf, b0 + 72, 25), bits(buf, b0 + 103, 25), 25),
      a2 = { sbits(buf, b0 + 144, 16) * ACC, sbits(buf, b0 + 176, 16) * ACC, sbits(buf, b0 + 208, 16) * ACC },
    }
  end
end

return M
