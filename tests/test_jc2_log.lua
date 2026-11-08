-- Replays a real Joy-Con 2 (R) recording through the same decode + fusion the game uses,
-- with joycon2android's measured axis frame. Read that way the recording is: level at rest,
-- ~4 s rolled a quarter turn to the left and held, ~6.5 s back, ~7 s nose raised to the
-- ceiling and held to the end.
local m = require("core.math")
local motion = require("core.motion")
local jc2map = require("shells.love.joycon2map")

local fails, passes = 0, 0
local function ok(c, msg) if c then passes = passes + 1 else fails = fails + 1; print("FAIL: " .. msg) end end

local function hexbyte(s, i) return tonumber(s:sub(2 * i + 1, 2 * i + 2), 16) end
local function s16(s, o) local v = hexbyte(s, o) + hexbyte(s, o + 1) * 256; return v >= 32768 and v - 65536 or v end
local function u32(s, o) return hexbyte(s, o) + hexbyte(s, o + 1) * 256 + hexbyte(s, o + 2) * 65536 + hexbyte(s, o + 3) * 16777216 end

local c = motion.new({ id = 1 })
local samples = {}
for line in io.lines("tests/data/jc2-right-ceiling-twist.txt") do
  if line:sub(1, 1) ~= "#" then
    local t, _, hex = line:match("^(%S+)%s+(%S+)%s+(%S+)")
    samples[#samples + 1] = { t = tonumber(t), hex = hex }
  end
end
local prevTs, at = nil, {}
for _, smp in ipairs(samples) do
  local h = smp.hex
  local raw = { s16(h, 0x36), s16(h, 0x38), s16(h, 0x3A) }
  local rawA = { s16(h, 0x30), s16(h, 0x32), s16(h, 0x34) }
  local g, a = jc2map.convert(0x2066, raw, rawA)
  local ts = u32(h, 0x2A)
  local dt = prevTs and (ts - prevTs) / 1e6 or 0.03
  prevTs = ts
  c:feed(dt, g, a)
  at[#at + 1] = { t = smp.t, orient = c.orient }
end
local function anglesAt(t)
  local best = at[1]
  for _, v in ipairs(at) do if math.abs(v.t - t) < math.abs(best.t - t) then best = v end end
  local y, p, r = m.angles(best.orient)
  return math.deg(y), math.deg(p), math.deg(r)
end
local _, p0, r0 = anglesAt(1.0)
ok(math.abs(p0) < 20 and math.abs(r0) < 20, string.format("start roughly level (pitch %.0f roll %.0f)", p0, r0))
local _, p1, r1 = anglesAt(5.0)
ok(r1 < -65 and math.abs(p1) < 25, string.format("quarter roll left (roll %.0f°, pitch %.0f°)", r1, p1))
local _, p2, r2 = anglesAt(7.0)
ok(math.abs(r2) < 20 and math.abs(p2) < 25, string.format("back to level (roll %.0f°, pitch %.0f°)", r2, p2))
local _, p3 = anglesAt(9.5)
ok(p3 > 75, string.format("nose to the ceiling (pitch %.0f°)", p3))

print(string.format("%d passed, %d failed", passes, fails))
if fails > 0 then error("tests failed") end
