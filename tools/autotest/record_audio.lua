-- Plays a few balls in real time with nothing drawn, so the game's sound can be recorded
-- without a sound card (OpenAL Soft's wave writer):
--   printf '[general]\ndrivers=wave\n[wave]\nfile=out.wav\n' > alsoft.conf
--   ALSOFT_CONF=alsoft.conf xvfb-run -a love . --script tools/autotest/record_audio.lua
-- It walks through a couple of menus (UI sounds), then bowls: a strike try, a gutter ball,
-- and a couple more, waiting for each result so the crowd and tunes are heard.
local bowling = require("shells.love.bowling")
local App = require("shells.love.app")

local co
local now = love.timer.getTime
local function wait(s)
  local t = now() + s
  while now() < t do coroutine.yield() end
end
local function waitUntil(f, limit)
  local t = now() + (limit or 30)
  while not f() and now() < t do coroutine.yield() end
  return f()
end
local function key(k) love.keypressed(k) end
local function st() return bowling.state() end

local function mouseThrow(dx, slow)
  local W, H = love.graphics.getDimensions()
  local x, y = W / 2, H * 0.45
  love.mousepressed(x, y, 1)
  for _ = 1, 12 do wait(1 / 60); y = y + 14; love.mousemoved(x, y) end
  for _ = 1, 6 do wait(1 / 60); y = y - (slow and 30 or 60); x = x + (dx or 0); love.mousemoved(x, y) end
  love.mousereleased(x, y, 1)
  return waitUntil(function() return st().phase == "rolling" end, 0.5)
end

local function ball(dx, slow, standAt)
  waitUntil(function() return st().phase == "aim" end, 15)
  wait(0.8)
  if standAt then st().x = standAt end
  mouseThrow(dx, slow)
  waitUntil(function() return st().phase == "result" end, 20)
  print("result: " .. tostring(st().msg))
end

local function script()
  wait(1.0)
  key("return"); wait(0.6)          -- title -> sports
  key("right"); wait(0.3); key("left"); wait(0.3)
  key("escape"); wait(0.8)          -- back to the title
  App.state().env.startBowling({ physics = "arcade" })
  ball(-5, false, 0.06)             -- into the pocket with a little hook: strike
  ball(14)                          -- spare try
  ball(40)                          -- a hard angle: gutter
  ball(-4, true)                    -- slow ball
  waitUntil(function() return st().phase == "aim" end, 15)
  wait(1.0)
  love.event.quit(0)
end

local origLoad, origUpdate, origDraw = love.load, love.update, love.draw
love.errorhandler = function(msg) print("LUA ERROR: " .. tostring(msg) .. "\n" .. debug.traceback()); os.exit(2) end
-- menus register their buttons while drawing, so they draw; the 3D game doesn't (too slow here)
love.draw = function() if App.state().screen ~= "bowling" then origDraw() end end
love.load = function(...)
  origLoad(...)
  co = coroutine.create(script)
end
love.update = function(dt)
  origUpdate(dt)
  if co and coroutine.status(co) ~= "dead" then
    local ok, err = coroutine.resume(co)
    if not ok then print("SCRIPT ERROR: " .. tostring(err)); love.event.quit(2) end
  end
end
