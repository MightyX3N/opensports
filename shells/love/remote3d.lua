-- Draws a remote-shaped box in perspective from a controller orientation.
-- No 3D engine needed: 8 corners projected by hand, faces painter-sorted.
local m = require("core.math")
local lg = love.graphics
local R = {}

local HX, HY, HZ = 0.018, 0.015, 0.074 -- half extents in metres (Wii Remote-ish)
local CAM = 0.42                        -- camera distance
local FOCAL = 900                       -- pixels at scale 1

local corners = {
  { -HX, -HY, -HZ }, { HX, -HY, -HZ }, { HX, HY, -HZ }, { -HX, HY, -HZ },
  { -HX, -HY, HZ }, { HX, -HY, HZ }, { HX, HY, HZ }, { -HX, HY, HZ },
}
local faces = { -- indices, local normal, colour
  { { 4, 3, 7, 8 }, { 0, 1, 0 }, { 1, 1, 1 } },        -- top (buttons)
  { { 1, 2, 6, 5 }, { 0, -1, 0 }, { 0.86, 0.90, 0.94 } },
  { { 1, 4, 3, 2 }, { 0, 0, -1 }, { 0.106, 0.165, 0.227 } }, -- front (IR window)
  { { 5, 6, 7, 8 }, { 0, 0, 1 }, { 0.86, 0.92, 0.98 } },
  { { 2, 3, 7, 6 }, { 1, 0, 0 }, { 0.95, 0.96, 0.98 } },
  { { 1, 5, 8, 4 }, { -1, 0, 0 }, { 0.95, 0.96, 0.98 } },
}
-- decals on the top face: {x, z, size, colour}
local decals = {
  { 0, -0.050, 0.0075, { 0.79, 0.84, 0.89 } }, -- d-pad
  { 0, -0.028, 0.0065, { 0.184, 0.490, 0.882 } }, -- A
  { 0, 0.030, 0.0030, { 0.106, 0.165, 0.227 } }, -- 1
  { 0, 0.043, 0.0030, { 0.106, 0.165, 0.227 } }, -- 2
}

local LIGHT = m.norm({ -0.4, 0.8, 0.5 })
-- camera sits behind and a little above/right of the player's hand
-- camera straight behind the player's hand, looking slightly down: pointing at the TV shows
-- the remote straight ahead (no sideways camera angle that makes "forward" look turned)
local VIEW = m.qaxis({ 1, 0, 0 }, math.rad(18))

local function project(p, cx, cy, f)
  local d = CAM - p[3]
  return cx + f * p[1] / d, cy - f * p[2] / d, d
end

function R.draw(orient, cx, cy, scale)
  local f = FOCAL * (scale or 1)
  orient = m.qmul(VIEW, orient)
  -- show the controller as seen from behind the player: rotate world so -z goes into the screen
  local pts, world = {}, {}
  for i, c in ipairs(corners) do
    local w = m.qrot(orient, c)
    world[i] = w
    local x, y, d = project(w, cx, cy, f)
    pts[i] = { x, y, d }
  end
  local list = {}
  for _, face in ipairs(faces) do
    local n = m.qrot(orient, face[2])
    local centre = { 0, 0, 0 }
    for _, i in ipairs(face[1]) do centre = m.add(centre, world[i]) end
    centre = m.scale(centre, 0.25)
    local toCam = m.sub({ 0, 0, CAM }, centre)
    if m.dot(n, toCam) > 0 then
      list[#list + 1] = { face = face, n = n, depth = CAM - centre[3] }
    end
  end
  table.sort(list, function(a, b) return a.depth > b.depth end)
  lg.setLineJoin("bevel")
  for _, it in ipairs(list) do
    local poly = {}
    for _, i in ipairs(it.face[1]) do poly[#poly + 1] = pts[i][1]; poly[#poly + 1] = pts[i][2] end
    local shade = 0.72 + 0.28 * math.max(0, m.dot(it.n, LIGHT))
    local c = it.face[3]
    lg.setColor(c[1] * shade, c[2] * shade, c[3] * shade)
    lg.polygon("fill", poly)
    lg.setColor(0.106, 0.165, 0.227)
    lg.setLineWidth(3)
    lg.polygon("line", poly)
    if it.face == faces[1] then
      for _, dcl in ipairs(decals) do
        local s = dcl[3]
        local q = {}
        for _, o in ipairs({ { -s, -s }, { s, -s }, { s, s }, { -s, s } }) do
          local w = m.qrot(orient, { dcl[1] + o[1], HY + 0.0005, dcl[2] + o[2] })
          local x, y = project(w, cx, cy, f)
          q[#q + 1] = x; q[#q + 1] = y
        end
        lg.setColor(dcl[4])
        lg.polygon("fill", q)
      end
    end
  end
  lg.setLineWidth(1)
  -- return the projected tip (front centre) for the pointer laser
  local tip = m.qrot(orient, { 0, 0, -HZ })
  local tx, ty = project(tip, cx, cy, f)
  return tx, ty
end

return R
