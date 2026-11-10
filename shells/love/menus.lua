-- The game's menus, following the design previews: title screen, sport select, bowling
-- mode select, controllers and settings. Every screen works with a pointer (mouse /
-- touch), a D-pad or stick (focus moves to the nearest item in that direction), A to pick
-- and B to go back.
local motion = require("core.motion")
local U = require("shells.love.ui")
local settings = require("shells.love.settings")
local Snd = require("shells.love.sound")
local lg = love.graphics
local C = U.col

local M = {}
local app -- set by M.init: { go, back, root, ctrl, I, toast, quit, startBowling, sel(i) }

function M.init(env) app = env end

------------------------------------------------------------------ focus system
-- Each frame a screen registers its interactive items; the focus is kept by item id.
local items, focusId, hoverId = {}, nil, nil
local screenName

local function beginItems(name)
  if name ~= screenName then screenName = name; focusId = nil end
  items = {}
end

-- register an item: rect {x, y, w, h}, id (stable string), fn (on pick), opts
-- opts: { default = true, left = fn, right = fn, r = corner radius, noRing = true }
local function item(rect, id, fn, opts)
  opts = opts or {}
  local it = { x = rect.x, y = rect.y, w = rect.w, h = rect.h, id = id, fn = fn, opts = opts }
  items[#items + 1] = it
  if not focusId and opts.default then focusId = id end
  return it
end

local function focused(id) return focusId == id end

-- a new screen is showing: its items register on its first draw, so nothing from the
-- previous screen can be picked in between
function M.clearItems() items = {} end

-- draw the focus ring on the focused item (call after drawing the items)
local function drawFocus()
  for _, it in ipairs(items) do
    if it.id == focusId and not it.opts.noRing then U.focus(it.x, it.y, it.w, it.h, it.opts.r or 20) end
  end
end

local function find(id) for _, it in ipairs(items) do if it.id == id then return it end end end

-- move focus to the nearest item in a direction
local function moveFocus(dx, dy)
  local cur = find(focusId)
  if not cur then
    if items[1] then focusId = items[1].id end
    return
  end
  local cx, cy = cur.x + cur.w / 2, cur.y + cur.h / 2
  -- prefer items that line up with this one (same row for left/right, same column for
  -- up/down), nearest first; otherwise the nearest one on that side
  local best, bestScore, wide, wideScore
  for _, it in ipairs(items) do
    if it ~= cur then
      local ix, iy = it.x + it.w / 2, it.y + it.h / 2
      local ddx, ddy = ix - cx, iy - cy
      local along = ddx * dx + ddy * dy
      if along > 4 then
        local lined
        if dx ~= 0 then lined = it.y < cur.y + cur.h and it.y + it.h > cur.y
        else lined = it.x < cur.x + cur.w and it.x + it.w > cur.x end
        local across = math.abs(ddx * dy) + math.abs(ddy * dx)
        local score = along + across * 2.5
        if lined then
          if not bestScore or score < bestScore then best, bestScore = it, score end
        elseif not wideScore or score < wideScore then wide, wideScore = it, score end
      end
    end
  end
  best = best or wide
  if best then focusId = best.id; Snd.ui("move") end
end

-- picking an item: "Back" items make the back sound themselves (app.back)
local function pick(it)
  if it.id ~= "back" then Snd.ui("select") end
  it.fn()
end

local function navItems(nav)
  if nav.up then moveFocus(0, -1) end
  if nav.down then moveFocus(0, 1) end
  local cur = find(focusId)
  if nav.left then if cur and cur.opts.left then Snd.ui("toggle"); cur.opts.left() else moveFocus(-1, 0) end end
  if nav.right then if cur and cur.opts.right then Snd.ui("toggle"); cur.opts.right() else moveFocus(1, 0) end end
  if nav.a and cur and cur.fn then pick(cur) end
end

local function itemAt(x, y)
  for i = #items, 1, -1 do
    local it = items[i]
    if x >= it.x and x <= it.x + it.w and y >= it.y and y <= it.y + it.h then return it end
  end
end

-- shared mouse handling: hovering focuses, clicking picks
local function mouseMove(x, y)
  local it = itemAt(x, y)
  if it and it.id ~= focusId then focusId = it.id; Snd.ui("move", 0.6) end
end
local function mouseClick(x, y)
  local it = itemAt(x, y)
  if it then focusId = it.id; if it.fn then pick(it) end; return true end
end

-- the round "B Back" button, bottom left
local function backButton(label)
  local r = U.backButton(80, 640, false, label or "Back")
  item(r, "back", function() app.back() end, { r = 24 })
end

-- pill button helper that registers itself
local function pill(label, x, y, style, fn, w, id)
  w = w or (U.textWidth(label, 18) + 48)
  local r = U.pill(label, x, y, style, false, w)
  item(r, id or label, fn, { r = 24, default = style == "primary" })
  return r
end

-- little chips showing the connected controllers
local function controllerChips(x, y, alignRight)
  local list = {}
  for _, c in ipairs(app.I.list) do list[#list + 1] = c end
  local widths, total = {}, 0
  for i, c in ipairs(list) do
    widths[i] = U.textWidth(c.name, 13) + 44
    total = total + widths[i] + 8
  end
  local cx = alignRight and (x - total + 8) or x
  local cols = { C.blue, C.red, C.green, { 0.95, 0.55, 0.15 } }
  for i, c in ipairs(list) do
    local w = widths[i]
    U.rect(cx, y, w, 30, 15, C.card)
    lg.setColor(cols[(i - 1) % 4 + 1]); lg.circle("fill", cx + 16, y + 15, 9)
    U.text(tostring(i), cx + 8, y + 7, 12, C.card, "center", 16)
    U.text(c.name, cx + 32, y + 7, 13, C.ink)
    cx = cx + w + 8
  end
end

------------------------------------------------------------------ sport icons
-- simple flat icons drawn with shapes, centred on (x, y), about 64 px across
local function poly(...) lg.polygon("fill", ...) end
local ICONS = {}
function ICONS.bowling(x, y)
  -- pin (white with an outline so it shows on light tiles)
  lg.setColor(0.55, 0.62, 0.70)
  lg.ellipse("fill", x - 14, y + 2, 11.5, 22.5); lg.circle("fill", x - 14, y - 22, 8.5)
  lg.rectangle("fill", x - 18.5, y - 22, 9, 12)
  lg.setColor(0.99, 0.99, 0.99); lg.ellipse("fill", x - 14, y + 2, 10, 21)
  lg.circle("fill", x - 14, y - 22, 7); lg.rectangle("fill", x - 17, y - 22, 6, 12)
  lg.setColor(C.red); lg.rectangle("fill", x - 18, y - 15, 8, 3)
  lg.setColor(C.blue); lg.circle("fill", x + 10, y + 6, 17)
  lg.setColor(0.08, 0.2, 0.45)
  lg.circle("fill", x + 6, y + 1, 2.6); lg.circle("fill", x + 13, y, 2.6); lg.circle("fill", x + 10, y + 7, 3)
end
function ICONS.tennis(x, y)
  lg.setColor(0.80, 0.90, 0.18); lg.circle("fill", x, y, 22)
  lg.setColor(1, 1, 1); lg.setLineWidth(3)
  lg.arc("line", "open", x - 26, y, 20, -0.9, 0.9); lg.arc("line", "open", x + 26, y, 20, math.pi - 0.9, math.pi + 0.9)
  lg.setLineWidth(1)
end
function ICONS.tabletennis(x, y)
  lg.setColor(0.45, 0.28, 0.16); lg.push(); lg.translate(x + 8, y + 12); lg.rotate(-0.6)
  lg.rectangle("fill", -4, 0, 8, 22, 3); lg.pop()
  lg.setColor(C.red); lg.circle("fill", x - 2, y - 6, 18)
  lg.setColor(1, 1, 1); lg.circle("fill", x + 18, y + 14, 5)
end
function ICONS.golf(x, y)
  lg.setColor(0.36, 0.70, 0.32); lg.ellipse("fill", x, y + 18, 26, 8)
  lg.setColor(0.35, 0.35, 0.38); lg.rectangle("fill", x - 1, y - 24, 3, 42)
  lg.setColor(C.red); poly(x + 2, y - 24, x + 22, y - 17, x + 2, y - 10)
end
function ICONS.baseball(x, y)
  lg.setColor(0.55, 0.62, 0.70); lg.circle("fill", x, y, 23.5)
  lg.setColor(0.99, 0.99, 0.98); lg.circle("fill", x, y, 22)
  lg.setColor(0.86, 0.25, 0.24); lg.setLineWidth(2.5)
  lg.arc("line", "open", x - 30, y, 22, -0.7, 0.7); lg.arc("line", "open", x + 30, y, 22, math.pi - 0.7, math.pi + 0.7)
  lg.setLineWidth(1)
end
function ICONS.boxing(x, y)
  lg.setColor(0.86, 0.18, 0.20)
  lg.ellipse("fill", x + 2, y - 4, 20, 18); lg.ellipse("fill", x - 14, y + 2, 9, 11)
  lg.setColor(0.96, 0.96, 0.96); lg.rectangle("fill", x - 12, y + 12, 26, 12, 4)
end
function ICONS.archery(x, y)
  local cols = { { 0.98, 0.98, 0.98 }, { 0.10, 0.12, 0.18 }, { 0.20, 0.50, 0.90 }, { 0.90, 0.25, 0.22 }, { 0.98, 0.82, 0.20 } }
  for i, c in ipairs(cols) do lg.setColor(c); lg.circle("fill", x, y, 24 - (i - 1) * 5) end
end
function ICONS.swordplay(x, y)
  lg.push(); lg.translate(x, y); lg.rotate(0.7)
  lg.setColor(0.36, 0.55, 0.95); lg.rectangle("fill", -4, -28, 8, 38, 3)
  lg.setColor(0.98, 0.98, 1); lg.rectangle("fill", -2, -26, 3, 32)
  lg.setColor(0.25, 0.30, 0.40); lg.rectangle("fill", -12, 10, 24, 5, 2); lg.rectangle("fill", -3, 14, 6, 12, 2)
  lg.pop()
end
function ICONS.frisbee(x, y)
  lg.setColor(0.93, 0.48, 0.18); lg.ellipse("fill", x, y, 26, 12)
  lg.setColor(0.98, 0.66, 0.35); lg.ellipse("fill", x, y - 2, 18, 7)
end
function ICONS.basketball(x, y)
  lg.setColor(0.93, 0.48, 0.14); lg.circle("fill", x, y, 22)
  lg.setColor(0.35, 0.18, 0.08); lg.setLineWidth(2)
  lg.line(x - 22, y, x + 22, y); lg.line(x, y - 22, x, y + 22)
  lg.arc("line", "open", x - 26, y, 18, -1.0, 1.0); lg.arc("line", "open", x + 26, y, 18, math.pi - 1.0, math.pi + 1.0)
  lg.setLineWidth(1)
end
function ICONS.cycling(x, y)
  lg.setColor(0.18, 0.45, 0.30); lg.setLineWidth(3.5)
  lg.circle("line", x - 15, y + 8, 12); lg.circle("line", x + 15, y + 8, 12)
  lg.line(x - 15, y + 8, x - 3, y - 10, x + 9, y - 10, x + 15, y + 8, x, y + 8, x - 3, y - 10)
  lg.setLineWidth(1)
end
function ICONS.more(x, y)
  lg.setColor(C.blue); lg.circle("fill", x, y, 18)
  lg.setColor(1, 1, 1); lg.rectangle("fill", x - 9, y - 2, 18, 4, 2); lg.rectangle("fill", x - 2, y - 9, 4, 18, 2)
end

M.SPORTS = {
  { id = "bowling", name = "Bowling", group = "classic", tint = { 0.87, 0.93, 0.99 }, ready = true },
  { id = "tennis", name = "Tennis", group = "classic", tint = { 0.92, 0.97, 0.86 } },
  { id = "tabletennis", name = "Table tennis", group = "island", tint = { 0.99, 0.90, 0.90 } },
  { id = "golf", name = "Golf", group = "classic", tint = { 0.88, 0.96, 0.89 } },
  { id = "baseball", name = "Baseball", group = "classic", tint = { 0.97, 0.93, 0.87 } },
  { id = "boxing", name = "Boxing", group = "classic", tint = { 0.99, 0.89, 0.89 } },
  { id = "archery", name = "Archery", group = "island", tint = { 0.88, 0.92, 0.98 } },
  { id = "swordplay", name = "Swordplay", group = "island", tint = { 0.92, 0.90, 0.99 } },
  { id = "frisbee", name = "Frisbee", group = "island", tint = { 0.99, 0.93, 0.86 } },
  { id = "basketball", name = "Basketball", group = "island", tint = { 0.99, 0.92, 0.85 } },
  { id = "cycling", name = "Cycling", group = "island", tint = { 0.89, 0.96, 0.90 } },
}

------------------------------------------------------------------ 1 Title screen
M.title = {}
function M.title.draw()
  beginItems("title")
  local W, H = 1280, 720
  -- the scene runs past the safe area to the real screen edges
  lg.push(); lg.origin()
  local sw, sh = lg.getDimensions()
  lg.setColor(0.80, 0.90, 0.98); lg.rectangle("fill", 0, 0, sw, sh)
  lg.pop()
  lg.setColor(0.86, 0.93, 0.99); lg.rectangle("fill", -200, -100, W + 400, 380)
  -- clouds
  lg.setColor(1, 1, 1)
  for _, cl in ipairs({ { 220, 100, 1 }, { 1050, 70, 1.2 }, { 1110, 190, 0.7 }, { 640, 40, 0.6 } }) do
    local x, y, s = cl[1], cl[2], cl[3]
    lg.ellipse("fill", x, y, 90 * s, 26 * s); lg.ellipse("fill", x - 40 * s, y + 8 * s, 60 * s, 22 * s)
    lg.ellipse("fill", x + 50 * s, y + 6 * s, 70 * s, 20 * s)
  end
  -- hills, sea and sand
  lg.setColor(0.55, 0.80, 0.50); lg.ellipse("fill", 980, 470, 420, 190)
  lg.setColor(0.62, 0.85, 0.55); lg.ellipse("fill", 1200, 500, 300, 150)
  lg.setColor(0.45, 0.72, 0.42); lg.ellipse("fill", 200, 520, 380, 120)
  lg.setColor(0.35, 0.35, 0.38); lg.rectangle("fill", 958, 300, 4, 70)
  lg.setColor(C.red); poly(962, 300, 1000, 312, 962, 324)
  lg.push(); lg.origin()
  local _, sy0 = U.ox, U.oy + 520 * U.scale
  lg.setColor(0.42, 0.72, 0.92); lg.rectangle("fill", 0, sy0, sw, sh - sy0)
  lg.setColor(0.94, 0.86, 0.66); lg.rectangle("fill", 0, U.oy + 650 * U.scale, sw, sh)
  lg.pop()
  lg.setColor(1, 1, 1, 0.55)
  for i = 0, 5 do lg.rectangle("fill", 120 + i * 190, 560 + (i % 2) * 30, 70, 3, 1.5) end
  -- logo card
  U.rect(370, 128, 540, 176, 32, C.shadow)
  U.rect(370, 120, 540, 176, 32, C.card)
  U.text("Open Sports", 370, 146, 72, C.blue, "center", 540)
  U.text("O P E N - S O U R C E   M O T I O N   S P O R T S", 370, 244, 15, C.sub, "center", 540)
  -- start prompt
  local label = "Press A or click to start"
  local w = U.textWidth(label, 19) + 84
  local x, y = 640 - w / 2, 410
  local pulse = 0.5 + 0.5 * math.sin(love.timer.getTime() * 3)
  lg.setColor(C.ink[1], C.ink[2], C.ink[3], 0.92)
  lg.rectangle("fill", x, y, w, 56, 28, 28, 16)
  lg.setColor(1, 1, 1, 0.85 + 0.15 * pulse); lg.circle("fill", x + 32, y + 28, 15)
  U.text("A", x + 20, y + 16, 17, C.ink, "center", 24)
  U.text(label, x + 58, y + 16, 19, C.card)
  item({ x = 0, y = 0, w = 1280, h = 720 }, "start", function() app.go("sports") end, { noRing = true, default = true })
  -- connected controllers and version
  controllerChips(40, 670)
  U.text("v0.1 · GPL-3.0", 1000, 676, 13, C.sub, "right", 240)
end
function M.title.nav(nav)
  if nav.a then Snd.ui("start"); app.go("sports") return end
  if nav.b then app.quit() end
end
function M.title.update(dt)
  -- the throw button on a controller also starts
  for _, c in ipairs(app.I.list) do if c.pressed.b and c.kind ~= "mouse" then app.go("sports"); return end end
end
function M.title.mousepressed() app.go("sports") end

------------------------------------------------------------------ 2 Sport select
M.sports = { tab = "all" }
local TABS = { { "all", "All" }, { "classic", "Classic" }, { "island", "Island" }, { "addons", "Add-ons" } }
function M.sports.draw()
  beginItems("sports")
  U.text("Choose a sport", 104, 34, 40)
  -- tabs
  local x = 104
  for _, t in ipairs(TABS) do
    local on = M.sports.tab == t[1]
    local w = U.textWidth(t[2], 15) + 36
    U.rect(x, 96, w, 34, 17, on and C.blue or C.card)
    U.text(t[2], x, 104, 15, on and C.card or C.ink, "center", w)
    item({ x = x, y = 96, w = w, h = 34 }, "tab_" .. t[1], function() M.sports.tab = t[1] end, { r = 17 })
    x = x + w + 10
  end
  controllerChips(1176, 40, true)
  -- tiles
  local list = {}
  for _, s in ipairs(M.SPORTS) do
    if M.sports.tab == "all" or M.sports.tab == s.group then list[#list + 1] = s end
  end
  if M.sports.tab == "all" or M.sports.tab == "addons" then list[#list + 1] = { id = "more", name = "More sports", more = true } end
  local tw, th, gap = 252, 140, 22
  for i, s in ipairs(list) do
    local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
    local tx, ty = 104 + col * (tw + gap), 150 + row * (th + gap)
    if s.more then
      lg.setColor(C.line); lg.setLineWidth(3)
      lg.rectangle("line", tx + 1.5, ty + 1.5, tw - 3, th - 3, 22, 22, 16); lg.setLineWidth(1)
      ICONS.more(tx + tw / 2, ty + 52)
      U.text("More sports", tx, ty + 82, 18, C.ink, "center", tw)
      U.text("From add-ons", tx, ty + 106, 13, C.sub, "center", tw)
      item({ x = tx, y = ty, w = tw, h = th }, "sport_more", function() app.toast("Add-on sports aren't available yet") end, { r = 22 })
    else
      U.rect(tx, ty + 4, tw, th, 22, C.shadow)
      U.rect(tx, ty, tw, th, 22, C.card)
      U.rect(tx, ty, tw, th - 40, 22, s.tint)
      lg.setColor(s.tint); lg.rectangle("fill", tx, ty + 60, tw, th - 100)
      ICONS[s.id](tx + tw / 2, ty + 50)
      U.text(s.name, tx, ty + th - 31, 18, C.ink, "center", tw)
      if not s.ready then
        lg.setColor(C.bg[1], C.bg[2], C.bg[3], 0.55); lg.rectangle("fill", tx, ty, tw, th, 22, 22, 16)
        local lw = U.textWidth("Coming soon", 12) + 20
        U.rect(tx + tw - lw - 12, ty + 12, lw, 24, 12, C.card)
        U.text("Coming soon", tx + tw - lw - 12, ty + 17, 12, C.sub, "center", lw)
      end
      item({ x = tx, y = ty, w = tw, h = th }, "sport_" .. s.id, function()
        if s.ready then app.go("modes") else app.toast(s.name .. " is coming soon") end
      end, { r = 22, default = s.id == "bowling" })
    end
  end
  backButton()
  local rx = 1176
  local w2 = U.textWidth("Settings", 18) + 48
  pill("Settings", rx - w2, 640, nil, function() app.go("settings") end, w2)
  local w1 = U.textWidth("Controllers", 18) + 48
  pill("Controllers", rx - w2 - 12 - w1, 640, nil, function() app.go("controllers") end, w1)
  drawFocus()
end
function M.sports.nav(nav) if nav.b then app.back() return end navItems(nav) end
M.sports.mousepressed = function(x, y) mouseClick(x, y) end
M.sports.mousemoved = mouseMove

------------------------------------------------------------------ 4 Bowling: mode select
M.modes = {}
local function laneArt(x, y, w, h)
  U.rect(x, y, w, h, 24, { 0.86, 0.92, 0.98 })
  U.clip(x, y, w, h)
  local cx = x + w / 2
  lg.setColor(0.70, 0.78, 0.88); poly(cx - 30, y + 20, cx + 30, y + 20, cx + 150, y + h, cx - 150, y + h)
  lg.setColor(0.93, 0.78, 0.55); poly(cx - 22, y + 20, cx + 22, y + 20, cx + 118, y + h, cx - 118, y + h)
  lg.setColor(0.97, 0.97, 0.97)
  for row = 3, 0, -1 do
    for i = 0, row do lg.ellipse("fill", cx + (i - row / 2) * 9, y + 44 - row * 3, 3, 7) end
  end
  lg.setColor(C.blue); lg.circle("fill", cx, y + h - 70, 30)
  lg.setColor(0.08, 0.2, 0.45)
  lg.circle("fill", cx - 8, y + h - 78, 4); lg.circle("fill", cx + 7, y + h - 80, 4); lg.circle("fill", cx, y + h - 68, 4.5)
  U.clip()
end
function M.modes.draw()
  beginItems("modes")
  -- left card
  U.rect(80, 64, 360, 556, 28, C.card)
  laneArt(96, 80, 328, 290)
  U.text("Bowling", 104, 390, 34)
  U.text("PHYSICS", 104, 440, 13, C.sub)
  local phys = settings.get("physics")
  for i, p in ipairs({ { "arcade", "Arcade" }, { "realistic", "Realistic" } }) do
    local bx = 104 + (i - 1) * 156
    local on = phys == p[1]
    U.rect(bx, 462, 150, 40, 20, on and C.blue or C.soft)
    U.text(p[2], bx, 472, 16, on and C.card or C.ink, "center", 150)
    item({ x = bx, y = 462, w = 150, h = 40 }, "phys_" .. p[1], function() settings.set("physics", p[1]) end, {
      r = 20,
      left = function() settings.set("physics", "arcade") end, right = function() settings.set("physics", "realistic") end,
    })
  end
  U.text(phys == "arcade" and "Forgiving: lighter pins that scatter more, like the original."
    or "Real pin weight and friction: you have to earn your strikes.", 104, 516, 14, C.sub, "left", 312)
  -- modes
  U.text("CHOOSE A MODE", 476, 64, 13, C.sub)
  local modes = {
    { "standard", "Standard game", "10 frames, classic scoring", "1 player", true },
    { "pinparty", "Pin party", "Pick any number of pins and a layout", "Coming soon" },
    { "training", "Training", "Spin control, power throws, spare pick-ups", "Coming soon" },
  }
  for i, md in ipairs(modes) do
    local y = 88 + (i - 1) * 96
    U.rect(476, y, 724, 82, 20, C.card)
    U.text(md[2], 500, y + 16, 20, md[5] and C.ink or C.sub)
    U.text(md[3], 500, y + 46, 14, C.sub)
    U.text(md[4], 1000, y + 30, 14, md[5] and C.ink or C.sub, "right", 176)
    if md[5] then U.selected(476, y, 724, 82, 20) end
    item({ x = 476, y = y, w = 724, h = 82 }, "mode_" .. md[1], function()
      if md[5] then app.startBowling({ physics = settings.get("physics") }) else app.toast(md[2] .. " is coming soon") end
    end, { r = 20 })
  end
  backButton()
  local w = U.textWidth("Start", 18) + 80
  pill("Start", 1200 - w, 640, "primary", function() app.startBowling({ physics = settings.get("physics") }) end, w)
  drawFocus()
end
function M.modes.nav(nav) if nav.b then app.back() return end navItems(nav) end
M.modes.mousepressed = function(x, y) mouseClick(x, y) end
M.modes.mousemoved = mouseMove

------------------------------------------------------------------ 5 Controllers
M.controllers = {}
-- open with the controller in play selected
function M.controllers.enter()
  M.controllers.sel = 1
  for i, c in ipairs(app.I.list) do if c == app.ctrl() then M.controllers.sel = i end end
end
local function ctrlKind(c)
  if c.kind == "mouse" then return "Mouse / touch · drag to swing" end
  if c.ble then return "Bluetooth · gyro + accelerometer" end
  if c.dsu then return "DSU motion server" end
  return (c.hasGyro and "Gamepad · gyro" or "Gamepad")
end
function M.controllers.draw()
  beginItems("controllers")
  U.header("SETUP", "Controllers")
  local I = app.I
  local rows = {}
  for i, c in ipairs(I.list) do rows[#rows + 1] = { ctrl = c, index = i } end
  -- saved Joy-Cons that aren't connected right now
  local saved = settings.get("saved")
  for _, e in ipairs(saved) do
    local on = false
    for _, c in ipairs(I.list) do if c.ble and settings.addrKey(c.ble.addr) == e.addr then on = true end end
    if not on then rows[#rows + 1] = { saved = e } end
  end
  M.controllers.sel = math.min(M.controllers.sel or 1, #rows + 1)
  local cols = { C.blue, C.red, C.green, { 0.95, 0.55, 0.15 } }
  local active = app.ctrl()
  for i, r in ipairs(rows) do
    local y = 128 + (i - 1) * 64
    local isSel = M.controllers.sel == i
    U.rect(80, y, 420, 54, 18, C.card)
    if isSel then U.selected(80, y, 420, 54, 18) end
    if r.ctrl then
      local c = r.ctrl
      lg.setColor(cols[(r.index - 1) % 4 + 1]); lg.circle("fill", 106, y + 27, 12)
      U.text(tostring(r.index), 94, y + 18, 14, C.card, "center", 24)
      U.text(c.name, 130, y + 9, 16)
      U.text(ctrlKind(c), 130, y + 30, 12, C.sub)
      local st = c == active and "In play" or "Ready"
      U.text(st, 380, y + 19, 13, c == active and C.blueDark or C.greenInk, "right", 104)
    else
      lg.setColor(C.line); lg.circle("fill", 106, y + 27, 12)
      U.text(r.saved.name or "Joy-Con 2", 130, y + 9, 16, C.sub)
      U.text("Saved · press SYNC on it to connect", 130, y + 30, 12, C.sub)
      U.text("Offline", 380, y + 19, 13, C.sub, "right", 104)
    end
    item({ x = 80, y = y, w = 420, h = 54 }, "row" .. i, function()
      M.controllers.sel = i
      if r.ctrl then app.use(r.ctrl) end
    end, { r = 18, default = isSel })
  end
  -- connect a new one
  local py = 128 + #rows * 64
  lg.setColor(C.line); lg.setLineWidth(3); lg.rectangle("line", 81.5, py + 1.5, 417, 51, 18, 18, 16); lg.setLineWidth(1)
  lg.setColor(C.blue); lg.circle("fill", 106, py + 27, 12)
  lg.setColor(1, 1, 1); lg.rectangle("fill", 100, py + 25, 12, 4, 2); lg.rectangle("fill", 104, py + 21, 4, 12, 2)
  U.text("Connect a new Joy-Con 2", 130, py + 17, 16)
  item({ x = 80, y = py, w = 420, h = 54 }, "pair", function() app.go("pair") end, { r = 18, default = #rows == 0 })

  -- detail panel for the selected row
  U.rect(540, 128, 660, 482, 28, C.card)
  local r = rows[M.controllers.sel]
  if not r then
    U.text("Connect a Joy-Con 2", 572, 156, 26)
    U.text("Press the small SYNC button on its rail. Once connected, it's saved: next time just press SYNC on it anywhere in the game and it connects by itself.",
      572, 196, 15, C.sub, "left", 600)
  elseif r.saved then
    U.text(r.saved.name or "Joy-Con 2", 572, 156, 26)
    U.text("Saved on this computer. Press the small SYNC button on its rail to connect it — from any screen, no menus needed.",
      572, 196, 15, C.sub, "left", 600)
    if not settings.get("autoConnect") then
      U.rect(572, 270, 596, 56, 16, C.warnSoft)
      U.text("Automatic connecting is off in Settings, so use \"Connect a new Joy-Con 2\" instead.", 590, 280, 14, C.warn, "left", 560)
    end
    pill("Forget this controller", 572, 540, nil, function()
      settings.forget(settings.get("saved"), r.saved.addr); settings.save(); app.toast("Forgotten")
    end, nil, "forget")
  else
    local c = r.ctrl
    U.text(c.name, 572, 156, 26)
    U.text(ctrlKind(c), 572, 192, 15, C.sub)
    local lvl = motion.LEVEL_NAMES[c.level] or "?"
    U.text("Control: " .. lvl, 572, 222, 15, c.level == motion.FULL and C.greenInk or C.warn)
    if c.ble and c.rate and c.rate > 0 then U.text(string.format("Motion reports: %d per second", math.floor(c.rate + 0.5)), 572, 246, 15, C.sub) end
    if c ~= active then
      pill("Play with this one", 572, 300, "primary", function() app.use(c); app.toast("Playing with " .. c.name) end, nil, "use")
    else
      U.rect(572, 300, 240, 48, 24, C.blueSoft)
      U.text("In play", 572, 313, 18, C.blueDark, "center", 240)
    end
    if c.kind ~= "mouse" then
      local bx = 572
      for _, b in ipairs({ { "Buttons", "remap" }, { "Motion check", "check" }, { "Motion test", "test" }, { "Re-centre", "recentre" } }) do
        local w = U.textWidth(b[1], 18) + 48
        pill(b[1], bx, 380, nil, function()
          app.use(c)
          if b[2] == "recentre" then c:recentre(); app.toast("Aim re-centred") else app.go(b[2]) end
        end, w, "act_" .. b[2])
        bx = bx + w + 10
      end
      if c.ble then
        local e = settings.findSaved(settings.get("saved"), c.ble.addr)
        U.text(e and "Saved: connects by itself when you press SYNC on it." or "Not saved", 572, 460, 14, C.sub)
        if e then
          pill("Forget this controller", 572, 540, nil, function()
            settings.forget(settings.get("saved"), c.ble.addr); settings.save(); app.toast("Forgotten — it stays connected until you turn it off")
          end, nil, "forget")
        end
      end
    end
  end
  backButton()
  drawFocus()
end
function M.controllers.nav(nav) if nav.b then app.back() return end navItems(nav) end
M.controllers.mousepressed = function(x, y) mouseClick(x, y) end
M.controllers.mousemoved = mouseMove

------------------------------------------------------------------ Settings
M.settings = {}
local function onOff(v) return v and "On" or "Off" end
local ROWS = {
  { section = "SCREEN AND SOUND" },
  { key = "fullscreen", label = "Fullscreen", sub = "Fill the whole screen", value = onOff },
  { key = "quality", label = "Graphics", sub = "Smooth edges look nicer; Faster helps slower PCs",
    value = function(v) return v == "high" and "Smooth" or "Faster" end },
  { key = "volume", label = "Sound", sub = "Volume of the game's sounds",
    value = function(v) return ({ high = "Loud", medium = "Medium", low = "Quiet", off = "Off" })[v] or v end },
  { section = "BOWLING" },
  { key = "swing", label = "Swing strength", sub = "How hard you need to swing for the fastest ball",
    value = function(v) return ({ light = "Light", normal = "Normal", strong = "Strong" })[v] or v end },
  { key = "aimLine", label = "Aim line", sub = "The dotted guide on the lane", value = onOff },
  { section = "CONTROLLERS" },
  { key = "autoConnect", label = "Connect saved Joy-Cons by themselves", sub = "Press SYNC on a saved Joy-Con on any screen", value = onOff },
  { action = "controllers", label = "Saved and connected controllers", sub = "Forget, re-check or set up buttons" },
}
function M.settings.draw()
  beginItems("settings")
  U.header("OPTIONS", "Settings")
  local y = 112
  for _, row in ipairs(ROWS) do
    if row.section then
      U.text(row.section, 80, y + 6, 13, C.sub)
      y = y + 28
    else
      U.rect(80, y, 1120, 54, 18, C.card)
      U.text(row.label, 104, y + 7, 17)
      U.text(row.sub, 104, y + 31, 12, C.sub)
      if row.key then
        local v = settings.get(row.key)
        local label = row.value(v)
        local w = 200
        local bx = 1176 - w
        U.rect(bx, y + 8, w, 38, 19, C.soft)
        U.text("<", bx + 10, y + 15, 16, C.sub, "left", 20)
        U.text(">", bx + w - 30, y + 15, 16, C.sub, "right", 20)
        U.text(label, bx, y + 16, 16, C.ink, "center", w)
        item({ x = 80, y = y, w = 1120, h = 54 }, "set_" .. row.key, function() M.settings.change(row.key, 1) end, {
          r = 18, default = row.key == "fullscreen",
          left = function() M.settings.change(row.key, -1) end, right = function() M.settings.change(row.key, 1) end,
        })
      else
        U.text("Open  >", 1000, y + 17, 16, C.blue, "right", 176)
        item({ x = 80, y = y, w = 1120, h = 54 }, "set_" .. row.action, function() app.go(row.action) end, { r = 18 })
      end
      y = y + 60
    end
  end
  U.text("Open Sports v0.1 · GPL-3.0 · Bowler: KayKit by Kay Lousberg (CC0) · Bowling sounds: juskiddink (CC-BY-SA 3.0), qubodup (CC0)", 1200 - 860, 656, 12, C.sub, "right", 860)
  backButton()
  drawFocus()
end
function M.settings.change(k, dir)
  local v = settings.cycle(k, dir)
  if app.applySetting then app.applySetting(k, v) end
end
function M.settings.nav(nav) if nav.b then app.back() return end navItems(nav) end
M.settings.mousepressed = function(x, y) mouseClick(x, y) end
M.settings.mousemoved = mouseMove

M.ICONS = ICONS
M.focusedId = function() return focusId end
return M
