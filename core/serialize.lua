-- Write plain Lua data (numbers, strings, booleans, tables) as a readable Lua chunk,
-- and load it back in an empty environment so saved files can't run code.
local M = {}

local function ser(v, ind, out)
  local t = type(v)
  if t == "number" then
    out[#out + 1] = (v == math.floor(v) and math.abs(v) < 1e15) and string.format("%d", v) or string.format("%.17g", v)
  elseif t == "string" then out[#out + 1] = string.format("%q", v)
  elseif t == "boolean" then out[#out + 1] = tostring(v)
  elseif t == "table" then
    local keys, n = {}, #v
    for k in pairs(v) do
      if not (type(k) == "number" and k >= 1 and k <= n and k == math.floor(k)) then keys[#keys + 1] = k end
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    out[#out + 1] = "{"
    local inner = ind .. "  "
    local flat = #keys == 0 and n <= 8
    for i = 1, n do
      out[#out + 1] = flat and (i > 1 and " " or "") or ("\n" .. inner)
      ser(v[i], inner, out); out[#out + 1] = ","
    end
    for _, k in ipairs(keys) do
      out[#out + 1] = "\n" .. inner
      if type(k) == "string" and k:match("^[%a_][%w_]*$") then out[#out + 1] = k
      else out[#out + 1] = "["; ser(k, inner, out); out[#out + 1] = "]" end
      out[#out + 1] = " = "; ser(v[k], inner, out); out[#out + 1] = ","
    end
    if not flat then out[#out + 1] = "\n" .. ind end
    out[#out + 1] = "}"
  else
    out[#out + 1] = "nil"
  end
end

function M.dump(v)
  local out = { "return " }
  ser(v, "", out)
  out[#out + 1] = "\n"
  return table.concat(out)
end

function M.load(str)
  local f, err
  if setfenv then
    f, err = loadstring(str, "data")
    if f then setfenv(f, {}) end
  else
    f, err = load(str, "data", "t", {})
  end
  if not f then return nil, err end
  local ok, res = pcall(f)
  if not ok then return nil, res end
  return res
end

return M
