-- Joy-Con 2 / Pro Controller 2 sensor axes -> core.math convention
-- (x = right, y = up out of the button face, z = towards the player; held like a remote,
-- the shoulder-button end points along -z).
--
-- Joy-Con 2 (R) is measured from a real recording (tests/data/jc2-right-ceiling-twist.txt):
-- raw X points along the shoulder end, raw Y to the left side, raw Z out of the buttons.
-- Joy-Con 2 (L) is assumed to be the same until we have a recording of one.
-- Pro Controller 2 / GameCube use SDL_hidapi_switch2.c's gamepad mapping (x, z, -y).
local M = {}
local G = 9.80665

local function remote(v) return { -v[2], v[3], -v[1] } end
local function gamepad(v) return { v[1], v[3], -v[2] } end

M.MAP = { [0x2066] = remote, [0x2067] = remote }

-- map a quaternion given in the device's native axes into the game's axes (similarity
-- transform by the same axis permutation: w stays, the vector part is permuted)
function M.quat(pid, q)
  local f = M.MAP[pid] or gamepad
  local v = f({ q[2], q[3], q[4] })
  return { q[1], v[1], v[2], v[3] }
end
function M.vec(pid, v) return (M.MAP[pid] or gamepad)(v) end

-- raw int16 gyro/accel -> rad/s, m/s² in the game's frame. gyroFull = full-scale rad/s.
function M.convert(pid, rawG, rawA, gyroFull)
  local f = M.MAP[pid] or gamepad
  local gs, as = (gyroFull or 34.8) / 32767, G * 8 / 32767
  local g, a = f(rawG), f(rawA)
  return { g[1] * gs, g[2] * gs, g[3] * gs }, { a[1] * as, a[2] * as, a[3] * as }
end

return M
