-- Joy-Con 2 sensor axes -> the game's frame, using joycon2android's measured conversion
-- (GPL-3.0, github.com/JoeGeC/joycon2android, docs/dsu-motion.md, verified there against
-- Dolphin's pointer) followed by Dolphin's reading of the DSU/cemuhook frame (core/dsu.lua).
--
-- joycon2android, Joy-Con 2 (R) raw: x = controller's right, y = toward the tail,
-- z = out of the button face. Scales: 4096 LSB per g, 0.06103515625 °/s per LSB (±2000 °/s).
-- Left Joy-Con and Pro Controller 2 are assumed to share the raw frame (as there).
local dsu = require("core.dsu")
local M = {}

local ACCEL_G_PER_LSB = 0.000244140625
local GYRO_DPS_PER_LSB = 0.06103515625

-- joycon2android MotionConverter.convert: raw -> cemuhook wire (accel g, gyro °/s)
function M.toWire(rawG, rawA)
  return {
    accel = { -rawA[1] * ACCEL_G_PER_LSB, -rawA[3] * ACCEL_G_PER_LSB, rawA[2] * ACCEL_G_PER_LSB },
    gyro = { rawG[1] * GYRO_DPS_PER_LSB, -rawG[3] * GYRO_DPS_PER_LSB, rawG[2] * GYRO_DPS_PER_LSB }, -- pitch, yaw, roll
  }
end

-- raw int16 gyro/accel -> rad/s, m/s² in the game's frame
function M.convert(pid, rawG, rawA)
  return dsu.toGame(M.toWire(rawG, rawA))
end

return M
