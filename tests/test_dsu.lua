local dsu = require("core.dsu")
local fails, passes = 0, 0
local function ok(c, msg) if c then passes = passes + 1 else fails = fails + 1; print("FAIL: " .. msg) end end
ok(dsu.crc32("123456789") == 0xCBF43926, "crc32 check value")
local p = dsu.listPorts(1234)
ok(#p == 28 and p:sub(1, 4) == "DSUC", "list ports packet size")
ok(p:byte(7) + p:byte(8) * 256 == 12, "message length excludes 16-byte header")
local function f32(x) -- encode for test
  if x == 0 then return "\0\0\0\0" end
  local sign = x < 0 and 128 or 0; x = math.abs(x)
  local e = math.floor(math.log(x) / math.log(2)); local m = x / 2 ^ e - 1
  local mant = math.floor(m * 8388608 + 0.5); e = e + 127
  return string.char(mant % 256, math.floor(mant / 256) % 256, (math.floor(mant / 65536) % 128) + (e % 2) * 128, sign + math.floor(e / 2))
end
-- build a fake server pad packet
local body = string.char(0x02, 0x00, 0x10, 0x00) .. string.char(0, 2, 2, 2) .. string.rep("\0", 6) .. string.char(5, 1)
  .. string.char(7, 0, 0, 0) .. string.char(0x00, 0x40) .. string.char(0, 0) .. string.char(128, 128, 128, 128) .. string.rep("\0", 12)
  .. string.rep("\0", 12) .. string.char(0x40, 0x42, 0x0F, 0, 0, 0, 0, 0)
  .. f32(0.0) .. f32(-1.0) .. f32(0.0) .. f32(90.0) .. f32(-45.0) .. f32(10.0)
local head = "DSUS" .. string.char(0xE9, 0x03) .. string.char(#body % 256, math.floor(#body / 256))
local pkt0 = head .. "\0\0\0\0" .. "\1\0\0\0" .. body
local crc = dsu.crc32(pkt0)
local pkt = head .. string.char(crc % 256, math.floor(crc / 256) % 256, math.floor(crc / 65536) % 256, math.floor(crc / 16777216)) .. "\1\0\0\0" .. body
ok(#pkt == 100, "pad packet is 100 bytes (" .. #pkt .. ")")
local d = dsu.parse(pkt)
ok(d and d.type == 0x100002, "pad data parsed")
if d then
  ok(d.timestamp == 1000000, "timestamp µs")
  ok(math.abs(d.gyro[1] - 90) < 1e-4 and math.abs(d.gyro[2] + 45) < 1e-4, "gyro floats")
  ok(dsu.down(d, "cross"), "cross pressed (bit 6 of buttons2)")
  local g, a = dsu.toGame(d)
  ok(a[2] > 9 and math.abs(a[1]) < 1e-6, "accel y -1 g (Dolphin: up) becomes +g up")
  ok(g[1] > 1.5 and g[2] > 0.7, "pitch up -> +x, yaw right(-45 = left) -> +y")
end
ok(dsu.parse(pkt:sub(1, 99) .. "\1") == nil, "bad crc rejected")
print(string.format("%d passed, %d failed", passes, fails))
if fails > 0 then error("tests failed") end
