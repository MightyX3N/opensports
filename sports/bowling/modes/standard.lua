-- Standard ten-pin game (mod layer 3: rules script): 10 frames, strikes and spares,
-- up to three balls in the 10th frame.
local R = {}
R.__index = R
R.id, R.name = "standard", "Standard game"

function R.new(pinCount)
  return setmetatable({ frames = {}, frame = 1, ball = 1, pinCount = pinCount or 10, over = false }, R)
end

-- record a ball that knocked down `n` pins; returns what happened:
-- { strike, spare, gutter, rerack (all pins stand again for the next ball), frameDone, gameOver }
function R:record(n)
  local f = self.frames[self.frame] or {}
  self.frames[self.frame] = f
  f[#f + 1] = n
  local P = self.pinCount
  local res = { pins = n }
  local tenth = self.frame == 10
  if not tenth then
    if #f == 1 and n == P then res.strike = true; res.frameDone = true
    elseif #f == 2 then
      if f[1] + f[2] == P then res.spare = true end
      res.frameDone = true
    end
  else
    local k = #f
    local fresh = k == 1 or f[k - 1] == P or (k == 3 and f[1] < P and f[1] + f[2] == P)
    if fresh and n == P then res.strike = true end
    if not fresh and f[k - 1] + n == P then res.spare = true end
    if k == 3 or (k == 2 and f[1] < P and f[1] + n < P) then res.frameDone = true
    else res.rerack = res.strike or res.spare end
  end
  if n == 0 and #f == 1 then res.gutter = true end
  if res.frameDone then
    res.rerack = true
    if self.frame == 10 then self.over = true; res.gameOver = true
    else self.frame = self.frame + 1 end
    self.ball = 1
  else
    self.ball = #f + 1
  end
  return res
end

-- all balls in order, for bonus lookups
local function rolls(self)
  local out, idx = {}, {}
  for fi = 1, 10 do
    local f = self.frames[fi]
    if not f then break end
    idx[fi] = #out + 1
    for _, n in ipairs(f) do out[#out + 1] = n end
  end
  return out, idx
end

-- running totals per frame (nil where not known yet)
function R:totals()
  local P = self.pinCount
  local r, idx = rolls(self)
  local out, total = {}, 0
  for fi = 1, 10 do
    local f = self.frames[fi]
    if not f then break end
    local i = idx[fi]
    local score
    if fi < 10 then
      if f[1] == P then
        if r[i + 1] and r[i + 2] then score = P + r[i + 1] + r[i + 2] end
      elseif f[2] then
        if f[1] + f[2] == P then
          if r[i + 2] then score = P + r[i + 2] end
        else score = f[1] + f[2] end
      end
    else
      local need = (f[1] == P or (f[2] and f[1] + f[2] == P)) and 3 or 2
      if #f >= need then score = 0; for _, n in ipairs(f) do score = score + n end end
    end
    if not score then break end
    total = total + score
    out[fi] = total
  end
  return out
end

function R:total()
  local t = self:totals()
  local last = 0
  for fi = 1, 10 do if t[fi] then last = t[fi] end end
  return last
end

-- scorecard marks for one frame: list of strings ("X", "/", "-", digits)
function R:marks(fi)
  local P = self.pinCount
  local f = self.frames[fi]
  if not f then return {} end
  local out = {}
  for i, n in ipairs(f) do
    local mark
    if fi < 10 then
      if i == 1 and n == P then mark = "X"
      elseif i == 2 and f[1] + n == P then mark = "/"
      end
    else
      local prev = f[i - 1]
      local freshRack = i == 1 or prev == P or (i == 3 and f[1] + f[2] == P and f[1] < P)
      if freshRack and n == P then mark = "X"
      elseif not freshRack and prev and prev + n == P then mark = "/" end
    end
    out[i] = mark or (n == 0 and "-" or tostring(n))
  end
  return out
end

return R
