-- DSU client over UDP (LuaSocket, bundled with LÖVE). Talks to a DSU server on this PC,
-- e.g. joycon2cpp (Joy-Con 2), BetterJoy, DS4Windows, or joycon2android on the network.
local dsu = require("core.dsu")
local motion = require("core.motion")
local D = { pads = {}, host = "127.0.0.1", port = dsu.PORT }

D.DEFAULT_BUTTONS = { a = "cross", b = "r2", one = "square", two = "r1", recentre = "triangle", sclick = "l3", plus = "options",
  minus = "share", home = "ps", up = "up", down = "down", left = "left", right = "right" }

function D.init()
  local ok, socket = pcall(require, "socket")
  if not ok then D.reason = "LuaSocket missing"; return end
  D.socket = socket
  D.udp = socket.udp()
  D.udp:settimeout(0)
  D.udp:setsockname("0.0.0.0", 0) -- bind first (unbound sendto can fail with "refused")
  D.uid = math.random(1, 2 ^ 30)
  D.nextRequest = 0
end

function D.update(dt, add, remove)
  if not D.udp then return end
  local now = love.timer.getTime()
  if now >= D.nextRequest then -- like Dolphin: re-register every second
    D.udp:sendto(dsu.listPorts(D.uid), D.host, D.port)
    D.udp:sendto(dsu.padDataRequest(D.uid), D.host, D.port)
    D.nextRequest = now + 1
  end
  for _ = 1, 256 do
    local data = D.udp:receivefrom()
    if not data then break end
    local d = dsu.parse(data)
    if d and d.type == 0x100002 and d.state == 2 then
      local key = d.pad
      local entry = D.pads[key]
      if not entry then
        local guid = "dsu-" .. (d.mac ~= "000000000000" and d.mac or tostring(d.pad))
        local c = add(motion.new({ id = "dsu" .. key, kind = "dsu", name = "DSU pad " .. (d.pad + 1), guid = guid }), guid)
        entry = { ctrl = c }
        D.pads[key] = entry
      end
      entry.last = now
      D.feed(entry, d)
    end
  end
  for key, entry in pairs(D.pads) do
    if now - entry.last > 2 then remove(entry.ctrl); D.pads[key] = nil end
  end
end

function D.feed(entry, d)
  local c = entry.ctrl
  if entry.ts == d.timestamp then return end -- duplicate (several clients registered)
  local dt = entry.ts and (d.timestamp - entry.ts) / 1e6 or 0.01
  entry.ts = d.timestamp
  if dt <= 0 or dt > 0.1 then dt = 0.01 end
  local g, a = dsu.toGame(d)
  c.lastRaw = { g = g, a = a }
  c:feed(dt, g, a)
  local map = c.profile.buttons
  for logical, def in pairs(D.DEFAULT_BUTTONS) do
    local name = map[logical] and map[logical]:match("^dsu:(.+)$") or def
    c:setButton(logical, dsu.down(d, name))
  end
  local sx, sy = (d.lx - 128) / 127, (d.ly - 128) / 127
  c.stick = { sx, sy }
  c:setButton("up", c.buttons.up or sy > 0.6)
  c:setButton("down", c.buttons.down or sy < -0.6)
  c:setButton("left", c.buttons.left or sx < -0.6)
  c:setButton("right", c.buttons.right or sx > 0.6)
  if c.capture then
    for name in pairs(dsu.BUTTONS) do
      if dsu.down(d, name) then local f = c.capture; c.capture = nil; f("dsu:" .. name); break end
    end
  end
end

return D
