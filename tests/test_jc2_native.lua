-- Round-trip test for the Joy-Con 2 native side-report decoder (bit layout per
-- linux-switch2 PROTOCOL.md §20/§24): encode known values, decode them back.
local native = require("shells.love.joycon2native")
local m = require("core.math")
local fails, passes = 0, 0
local function ok(c, msg) if c then passes = passes + 1 else fails = fails + 1; print("FAIL: " .. msg) end end

local function put(buf, pos, n, v)
  if v < 0 then v = v + 2 ^ n end
  for i = 0, n - 1 do
    local bit = math.floor(v / 2 ^ i) % 2
    local b = math.floor((pos + i) / 8)
    buf[b] = (buf[b] or 0) + bit * 2 ^ ((pos + i) % 8)
  end
end
local function enc(c) return math.floor(((c * math.sqrt(2)) + 1) / 2 * (2 ^ 21 - 1) + 0.5) end

local function packet(right, q, g3)
  -- q = {w,x,y,z}; store with selector 0: stored q0 q1 q2 (= x y z), omitted q3 (= w, positive)
  local buf = {}
  for i = 0, 62 do buf[i] = 0 end
  local off = right and 8 or 0
  buf[14] = right and 0 or 0x28
  if right then buf[15] = 0x28 end
  local function P(pos, n, v) put(buf, pos + off, n, v) end
  P(120, 12, 1234); P(132, 8, 49); P(140, 8, 0xF0)
  P(154, 2, 0); P(157, 21, enc(q[2])); P(178, 21, enc(q[3])); P(199, 21, enc(q[4]))
  local GY = 16384 / math.rad(500)
  P(350, 15, math.floor(g3[1] * GY + 0.5)); P(366, 15, math.floor(g3[2] * GY + 0.5)); P(382, 15, math.floor(g3[3] * GY + 0.5))
  return function(i) return buf[i] end
end

for _, right in ipairs({ false, true }) do
  local q = m.qnorm({ 0.8, 0.3, -0.4, 0.2 })
  local d = native.decode(packet(right, q, { 1.5, -2.0, 0.25 }), right and 0x2066 or 0x2067)
  local side = right and "right" or "left"
  ok(d and d.kind == "ordinary", side .. ": ordinary packet recognised")
  if d then
    ok(d.time12 == 1234 and d.dtime8 == 49 and d.prefix == 0xF0, side .. ": header fields")
    local dot = math.abs(d.q[1] * q[1] + d.q[2] * q[2] + d.q[3] * q[3] + d.q[4] * q[4])
    ok(dot > 0.99999, side .. string.format(": quaternion round trip (dot %.6f)", dot))
    ok(math.abs(d.g3[1] - 1.5) < 0.002 and math.abs(d.g3[2] + 2.0) < 0.002, side .. ": gyro G3 round trip")
  end
end

print(string.format("%d passed, %d failed", passes, fails))
if fails > 0 then error("tests failed") end
