-- Exports Open Sports' own bowling hall (built in code by sports/bowling/hall.lua and
-- models.lua, textures from shells/love/bowling_scene.lua) for the Godot version:
-- one gzipped .bin per mesh (vertex count, then 12 floats per vertex: x y z u v nx ny nz r g b a)
-- plus its texture as PNG and a meshes.json with each mesh's shading options.
--   OUT=<godot/assets/hall> xvfb-run love . --script tools/godot/export_hall.lua
local out = os.getenv("OUT") or "hall"
os.execute('mkdir -p "' .. out .. '"')
local gfx = require("shells.love.gfx3d")
local lg = love.graphics
local datas = setmetatable({}, { __mode = "k" })
local newImage = lg.newImage
lg.newImage = function(d, ...)
  local img = newImage(d, ...)
  if type(d) == "userdata" and d.typeOf and d:typeOf("ImageData") then datas[img] = d end
  return img
end
gfx.mesh = function(verts, tex, opts) return { verts = verts, tex = tex, opts = opts or {} } end
local Scene = require("shells.love.bowling_scene")
local b = Scene.build()
local texNames, texCount = {}, 0
local json = { "{" }
local first = true
for name, m in pairs(b) do
  if type(m) == "table" and m.verts then
    local f = io.open(out .. "/" .. name .. ".bin", "wb")
    local n = #m.verts
    local parts = { love.data.pack("string", "<I4", n) }
    for _, v in ipairs(m.verts) do
      parts[#parts + 1] = love.data.pack("string", "<ffffffffffff", v[1], v[2], v[3], v[4] or 0, v[5] or 0,
        v[6] or 0, v[7] or 1, v[8] or 0, v[9] or 1, v[10] or 1, v[11] or 1, v[12] or 1)
    end
    f:write(love.data.compress("string", "gzip", table.concat(parts), 9)); f:close()
    local texName = ""
    if m.tex then
      texName = texNames[m.tex]
      if not texName then
        texCount = texCount + 1
        texName = "tex_" .. name
        texNames[m.tex] = texName
        local d = datas[m.tex]
        local wrap = m.tex:getWrap()
        local fh = io.open(out .. "/" .. texName .. ".png", "wb")
        fh:write(d:encode("png"):getString()); fh:close()
        texName = texName .. (wrap == "repeat" and ":repeat" or "")
      end
    end
    local o = m.opts
    json[#json + 1] = string.format('%s"%s": {"tex": "%s", "spec": %s, "shine": %s, "rim": %s, "unlit": %s, "alpha": %s, "cull": %s}',
      first and "" or ",\n", name, texName, o.spec or 0.15, o.shine or 24, o.rim or 0, tostring(o.unlit == true),
      tostring(o.alpha == true), tostring(o.cull ~= false))
    first = false
  end
end
json[#json + 1] = "}"
local f = io.open(out .. "/meshes.json", "w"); f:write(table.concat(json)); f:close()
print("exported to " .. out)
love.event.quit(0)
