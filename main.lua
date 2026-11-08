-- LÖVE entry point. All real code lives in core/ (shared) and shells/love/ (this platform).
require("shells.love.app")

-- Development only: `love . --script path/to/script.lua` runs a scripted play-through
-- (see tools/autotest/). Nothing happens without the flag.
for i, a in ipairs(arg or {}) do
  if a == "--script" and arg[i + 1] then
    local f = assert(io.open(arg[i + 1], "r"))
    local src = f:read("*a")
    f:close()
    assert(loadstring(src, "@" .. arg[i + 1]))(arg[i + 2])
  end
end
