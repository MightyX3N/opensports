-- Menu drawing in a fixed 1280×720 design space, scaled uniformly to any screen
-- (architecture §9b). Colours and shapes follow the design canvas.
local lg = love.graphics
local U = { W = 1280, H = 720, scale = 1, ox = 0, oy = 0, fonts = {} }

U.col = {
  bg = { 0.933, 0.953, 0.973 }, card = { 1, 1, 1 }, soft = { 0.953, 0.969, 0.984 },
  ink = { 0.106, 0.165, 0.227 }, sub = { 0.290, 0.357, 0.424 }, line = { 0.890, 0.922, 0.953 },
  blue = { 0.184, 0.490, 0.882 }, blueDark = { 0.106, 0.373, 0.722 }, blueSoft = { 0.863, 0.922, 0.984 },
  red = { 0.886, 0.275, 0.247 }, green = { 0.231, 0.667, 0.420 }, greenInk = { 0.180, 0.490, 0.310 },
  greenSoft = { 0.875, 0.953, 0.902 }, warn = { 0.631, 0.361, 0 }, warnSoft = { 1, 0.941, 0.839 },
  shadow = { 0.827, 0.871, 0.914 },
}

local SAFE = 0.03 -- TV overscan / notch margin, fraction of each side

function U.resize(w, h)
  local sw, sh = w * (1 - 2 * SAFE), h * (1 - 2 * SAFE)
  U.scale = math.min(sw / U.W, sh / U.H)
  U.ox = (w - U.W * U.scale) / 2
  U.oy = (h - U.H * U.scale) / 2
  U.fonts = {}
end

-- fonts are created at real pixel size so text stays sharp at any scale.
-- Nunito (SIL OFL, assets/fonts) in the three weights the design uses.
local FONT_FILES = { bold = "assets/fonts/Nunito-Bold.ttf", extra = "assets/fonts/Nunito-ExtraBold.ttf", black = "assets/fonts/Nunito-Black.ttf" }
function U.font(size, weight)
  weight = weight or "extra"
  local key = weight .. size
  if not U.fonts[key] then
    local px = math.max(8, math.floor(size * U.scale + 0.5))
    local ok, f = pcall(lg.newFont, FONT_FILES[weight], px)
    U.fonts[key] = ok and f or lg.newFont(px)
  end
  return U.fonts[key]
end

-- weight from role: big text is black, secondary text is bold, the rest extra-bold
local function weightFor(size, color)
  if size >= 22 then return "black" end
  if color == U.col.sub then return "bold" end
  return "extra"
end

function U.begin()
  lg.clear(U.col.bg)
  lg.push()
  lg.translate(U.ox, U.oy)
  lg.scale(U.scale)
end
function U.finish() lg.pop() end

function U.toDesign(x, y) return (x - U.ox) / U.scale, (y - U.oy) / U.scale end

function U.text(str, x, y, size, color, align, w)
  local f = U.font(size, weightFor(size, color))
  lg.setFont(f)
  lg.setColor(color or U.col.ink)
  local inv = 1 / U.scale
  if align then
    lg.printf(str, x, y, (w or 400) * U.scale, align, 0, inv, inv)
  else
    lg.print(str, x, y, 0, inv, inv)
  end
end
function U.textWidth(str, size, color) return U.font(size, weightFor(size, color)):getWidth(str) / U.scale end

-- clip drawing to a design-space rectangle
function U.clip(x, y, w, h)
  if not x then lg.setScissor(); return end
  lg.setScissor(U.ox + x * U.scale, U.oy + y * U.scale, w * U.scale, h * U.scale)
end

function U.rect(x, y, w, h, r, color)
  lg.setColor(color)
  lg.rectangle("fill", x, y, w, h, r, r, 16)
end

function U.header(kicker, title)
  U.text(kicker, 80, 36, 15, U.col.sub)
  U.text(title, 80, 56, 40, U.col.ink)
end

-- focus ring for TV-remote / D-pad navigation
function U.focus(x, y, w, h, r)
  lg.setColor(U.col.blue[1], U.col.blue[2], U.col.blue[3], 0.18)
  lg.setLineWidth(12)
  lg.rectangle("line", x - 4, y - 4, w + 8, h + 8, r + 4, r + 4, 16)
  lg.setColor(U.col.blue)
  lg.setLineWidth(4)
  lg.rectangle("line", x + 2, y + 2, w - 4, h - 4, r, r, 16)
  lg.setLineWidth(1)
end

-- "this one is chosen" outline (no glow, so it never looks like the focus ring)
function U.selected(x, y, w, h, r)
  lg.setColor(U.col.blue); lg.setLineWidth(3)
  lg.rectangle("line", x + 1.5, y + 1.5, w - 3, h - 3, r, r, 16)
  lg.setLineWidth(1)
end

-- pill button. style: nil | "primary". Returns its rect for hit testing.
function U.pill(label, x, y, style, focused, w)
  w = w or (U.textWidth(label, 18) + 48)
  local h = 48
  local primary = style == "primary"
  U.rect(x, y + 4, w, h, 24, primary and U.col.blueDark or U.col.shadow)
  U.rect(x, y, w, h, 24, primary and U.col.blue or U.col.card)
  U.text(label, x, y + 13, 18, primary and U.col.card or U.col.ink, "center", w)
  if focused then U.focus(x, y, w, h, 24) end
  return { x = x, y = y, w = w, h = h }
end

function U.backButton(x, y, focused)
  local w = U.textWidth("Back", 18) + 80
  U.rect(x, y + 4, w, 48, 24, U.col.shadow)
  U.rect(x, y, w, 48, 24, U.col.card)
  lg.setColor(U.col.ink); lg.circle("fill", x + 28, y + 24, 16)
  U.text("B", x + 12, y + 13, 16, U.col.card, "center", 32)
  U.text("Back", x + 56, y + 13, 18)
  if focused then U.focus(x, y, w, 48, 24) end
  return { x = x, y = y, w = w, h = 48 }
end

-- centred bar for a signed value in -1..1
function U.bar(x, y, w, v, color)
  U.rect(x, y, w, 12, 6, U.col.line)
  local half = w / 2
  local bw = math.min(1, math.abs(v)) * half
  if bw > 1 then U.rect(v >= 0 and x + half or x + half - bw, y, bw, 12, 6, color) end
  lg.setColor(0.663, 0.737, 0.812); lg.rectangle("fill", x + half - 1, y - 3, 2, 18)
end

function U.hit(r, x, y) return r and x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h end

return U
