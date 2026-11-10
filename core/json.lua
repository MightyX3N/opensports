-- Minimal JSON decoder (pure Lua 5.1 / LuaJIT, no engine calls). Enough for glTF:
-- objects, arrays, strings (with \u escapes), numbers, true/false/null (null -> nil).
local J = {}

local sub, byte, find, char = string.sub, string.byte, string.find, string.char

local function err(s, i, what) error(string.format("json: %s at byte %d", what, i), 0) end

local function skip(s, i)
  local _, e = find(s, "^[ \t\r\n]*", i)
  return e + 1
end

local function utf8(cp)
  if cp < 0x80 then return char(cp) end
  if cp < 0x800 then return char(0xC0 + math.floor(cp / 64), 0x80 + cp % 64) end
  return char(0xE0 + math.floor(cp / 4096), 0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
end

local value

local function str(s, i)
  -- i points just after the opening quote
  local out, n = {}, 0
  while true do
    local a, b = find(s, '["\\]', i)
    if not a then err(s, i, "unterminated string") end
    n = n + 1; out[n] = sub(s, i, a - 1)
    if sub(s, a, a) == '"' then return table.concat(out), a + 1 end
    local c = sub(s, a + 1, a + 1)
    if c == "u" then
      n = n + 1; out[n] = utf8(tonumber(sub(s, a + 2, a + 5), 16))
      i = a + 6
    else
      local map = { b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }
      n = n + 1; out[n] = map[c] or c
      i = a + 2
    end
  end
end

value = function(s, i)
  i = skip(s, i)
  local c = byte(s, i)
  if c == 123 then -- {
    local obj = {}
    i = skip(s, i + 1)
    if byte(s, i) == 125 then return obj, i + 1 end
    while true do
      if byte(s, i) ~= 34 then err(s, i, "expected key") end
      local k
      k, i = str(s, i + 1)
      i = skip(s, i)
      if byte(s, i) ~= 58 then err(s, i, "expected ':'") end
      obj[k], i = value(s, i + 1)
      i = skip(s, i)
      local d = byte(s, i)
      if d == 125 then return obj, i + 1 end
      if d ~= 44 then err(s, i, "expected ',' or '}'") end
      i = skip(s, i + 1)
    end
  elseif c == 91 then -- [
    local arr, n = {}, 0
    i = skip(s, i + 1)
    if byte(s, i) == 93 then return arr, i + 1 end
    while true do
      n = n + 1
      arr[n], i = value(s, i)
      i = skip(s, i)
      local d = byte(s, i)
      if d == 93 then return arr, i + 1 end
      if d ~= 44 then err(s, i, "expected ',' or ']'") end
      i = i + 1
    end
  elseif c == 34 then
    return str(s, i + 1)
  elseif sub(s, i, i + 3) == "true" then return true, i + 4
  elseif sub(s, i, i + 4) == "false" then return false, i + 5
  elseif sub(s, i, i + 3) == "null" then return nil, i + 4
  else
    local a, b = find(s, "^-?%d+%.?%d*[eE]?[-+]?%d*", i)
    if not a then err(s, i, "unexpected character") end
    return tonumber(sub(s, a, b)), b + 1
  end
end

function J.decode(s)
  local v = value(s, 1)
  return v
end

return J
