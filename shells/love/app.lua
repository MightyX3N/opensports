-- Input test app: the "Motion test", "Motion check", "Axis wizard" and "Buttons"
-- screens from the design canvas. Build order step 1 (architecture §11).
local m = require("core.math")
local motion = require("core.motion")
local cal = require("core.calibrate")
local swing = require("core.swing")
local U = require("shells.love.ui")
local I = require("shells.love.input")
local remote = require("shells.love.remote3d")
local lg = love.graphics
local C = U.col

local app = { screen = "test", sel = 1, focus = 0, hits = {}, lastSwing = nil, trace = {} }

local function ctrl() return I.list[app.sel] or I.list[1] end
local function detectorFor(c)
  if not c.detector or c.detector.ctrl ~= c then c.detector = swing.new(c) end
  return c.detector
end

------------------------------------------------------------------ screens
local screens = {}

-- footer buttons are focusable left/right; returns list of {label, action, style}
local function footer(items)
  if app.focus == nil then app.focus = #items end -- default focus: the main action
  local hits = {}
  hits.back = U.backButton(80, 640, app.focus == 0, app.screen == "test" and "Quit" or "Back")
  local x = 1200
  for i = #items, 1, -1 do
    local it = items[i]
    local w = U.textWidth(it[1], 18) + 48
    x = x - w
    hits[i] = U.pill(it[1], x, 640, it[3], app.focus == i, w)
    hits[i].action = it[2]
    x = x - 12
  end
  app.hits = hits
  app.footerCount = #items
end

local function levelBadge(c, x, y)
  local ok = c.level == motion.FULL
  local label = motion.LEVEL_NAMES[c.level]
  local w = U.textWidth(label, 14) + 28
  U.rect(x, y, w, 30, 15, ok and C.greenSoft or C.warnSoft)
  U.text(label, x, y + 7, 14, ok and C.greenInk or C.warn, "center", w)
  return w
end

--------------------------------------------------------------- 7 Motion test
screens.test = {}
function screens.test.draw()
  local c = ctrl()
  U.header("DEVELOPER · INPUT TEST", "Motion test")
  -- scene card
  U.rect(80, 130, 640, 480, 32, C.soft)
  U.clip(80, 130, 640, 480)
  lg.setColor(C.line)
  lg.rectangle("fill", 80, 430, 640, 180)
  lg.setColor(0.788, 0.839, 0.890)
  lg.setLineWidth(2)
  for i = -3, 3 do lg.line(400, 430, 400 + i * 170, 610) end
  lg.line(80, 460, 720, 460); lg.line(80, 510, 720, 510); lg.line(80, 570, 720, 570)
  U.clip()
  -- screen + pointer
  U.rect(468, 196, 190, 122, 10, C.card)
  lg.setColor(C.line); lg.setLineWidth(3); lg.rectangle("line", 468, 196, 190, 122, 10, 10)
  local px, py = 468 + c.pointer.x * 190, 196 + c.pointer.y * 122
  local tx, ty = remote.draw(c.orient, 380, 380, 1)
  if c.pointer.valid or c.hasPointer then
    lg.setColor(C.blue); lg.setLineWidth(3)
    local dx, dy = px - tx, py - ty
    local len = math.sqrt(dx * dx + dy * dy)
    for s = 0, len - 8, 13 do
      lg.line(tx + dx * s / len, ty + dy * s / len, tx + dx * math.min(s + 6, len) / len, ty + dy * math.min(s + 6, len) / len)
    end
    lg.setColor(1, 1, 1); lg.circle("fill", px, py, 15)
    lg.setColor(C.red); lg.circle("fill", px, py, 11)
  end
  lg.setLineWidth(1)
  -- axis gizmo
  local o = { 150, 540 }
  local axes = { { { 60, 0, 0 }, C.red, "X" }, { { 0, 60, 0 }, C.green, "Y" }, { { 0, 0, 60 }, C.blue, "Z" } }
  for _, a in ipairs(axes) do
    local w = m.qrot(c.orient, a[1])
    local ex, ey = o[1] + w[1] + w[3] * 0.45, o[2] - w[2] + w[3] * 0.35
    lg.setColor(a[2]); lg.setLineWidth(5); lg.line(o[1], o[2], ex, ey)
    U.text(a[3], ex + 4, ey - 10, 16, a[2])
  end
  lg.setLineWidth(1)
  -- chips
  local nw = U.textWidth(c.name, 14) + 28
  U.rect(104, 152, nw, 30, 15, C.card)
  U.text(c.name, 104, 159, 14, C.ink, "center", nw)
  levelBadge(c, 112 + nw, 152)
  local yaw, pitch, roll = m.angles(c.orient)
  U.text(string.format("Yaw %+.0f°  Pitch %+.0f°  Roll %+.0f°", math.deg(yaw), math.deg(pitch), math.deg(roll)),
    104, 582, 14, C.sub)
  U.text(string.format("Pointer %.2f · %.2f", c.pointer.x, c.pointer.y), 420, 582, 14, C.sub, "right", 276)

  -- sensor cards
  local function card(y, title, unit, v, range)
    U.rect(744, y, 456, 132, 24, C.card)
    U.text(title, 766, y + 16, 16)
    U.text(unit, 766, y + 18, 14, C.sub, "right", 412)
    local cols = { C.red, C.green, C.blue }
    for i = 1, 3 do
      local yy = y + 48 + (i - 1) * 26
      U.text(({ "X", "Y", "Z" })[i], 766, yy - 3, 14, C.sub)
      U.bar(794, yy, 300, v[i] / range, cols[i])
      U.text(string.format("%+.2f", v[i]), 1104, yy - 3, 14, C.ink, "right", 70)
    end
  end
  local rate = c.rate > 0 and string.format("%d Hz", math.floor(c.rate + 0.5)) or "—"
  card(130, "Gyro", "rad/s · " .. rate, c.gyro, 10)
  card(276, "Accel (gravity removed)", "m/s²", c.lin, 20)

  -- last swing
  U.rect(744, 422, 456, 188, 24, C.card)
  U.text("Last swing", 766, 440, 16)
  local s = app.lastSwing
  U.text(s and "detected · " .. s.source or "swing the controller", 766, 442, 14, s and C.greenInk or C.sub, "right", 412)
  U.rect(766, 468, 412, 54, 10, C.soft)
  local tr = app.trace
  if #tr > 1 then
    local maxw = 1
    for _, v in ipairs(tr) do maxw = math.max(maxw, v) end
    local pts = {}
    for i, v in ipairs(tr) do
      pts[#pts + 1] = 774 + (i - 1) / (#tr - 1) * 396
      pts[#pts + 1] = 514 - v / maxw * 40
    end
    lg.setColor(C.blue); lg.setLineWidth(3); lg.line(pts); lg.setLineWidth(1)
  end
  local function stat(x, label, value)
    U.rect(x, 532, 132, 52, 14, C.soft)
    U.text(label, x + 12, 540, 12, C.sub)
    U.text(value, x + 12, 556, 18)
  end
  stat(766, "SPEED", s and string.format("%.1f m/s", s.speed) or "—")
  stat(906, "SPIN", s and string.format("%+.1f %s", s.spin, s.spin >= 0 and "right" or "left") or "—")
  stat(1046, "AIM", s and string.format("%.0f° %s", math.abs(math.deg(s.aim)), s.aim >= 0 and "left" or "right") or "—")

  footer({ { "Connect Joy-Con 2", "pair" }, { "Buttons", "remap" }, { "Motion check", "check" }, { "Recentre", "recentre" }, { "Next controller", "next", nil } })
end

function screens.test.update(dt)
  local c = ctrl()
  local det = detectorFor(c)
  local ev = det:update()
  if ev then app.lastSwing = ev end
  -- rolling trace of angular speed (or pointer speed for mouse)
  local tr = app.trace
  tr[#tr + 1] = m.len(c.gyro)
  while #tr > 120 do table.remove(tr, 1) end
end

---------------------------------------------------------- 8 Motion check
screens.check = {}
function screens.check.enter()
  app.check = cal.newCheck(4)
  app.report = nil
  app.levelSel = ctrl().level
end
function screens.check.update(dt)
  local c = ctrl()
  if app.check and not app.check.done then
    local r = I.raw[c]
    cal.checkFeed(app.check, dt, r and r.g, r and r.a)
    if app.check.done then
      app.report = cal.checkReport(app.check)
      if not c.joystick and not c.sensorSource then app.report.level = motion.GESTURE end
      app.levelSel = app.report.level
      if app.report.accelScale then c.profile.accelScale = app.report.accelScale end
    end
  end
end
function screens.check.draw()
  local c = ctrl()
  U.header("SETUP · " .. c.name:upper(), "Motion check")
  U.rect(80, 130, 540, 480, 32, C.card)
  U.text(c.name, 110, 156, 24)
  if not app.report then
    local t = app.check.t / app.check.duration
    U.text(t < 0.5 and "Leave it still on a table…" or "Now pick it up and move it around", 110, 190, 15, C.sub)
    U.rect(110, 240, 480, 14, 7, C.line)
    U.rect(110, 240, 480 * math.min(1, t), 14, 7, C.blue)
  else
    U.text("Checked for 4 seconds while resting and moving", 110, 190, 15, C.sub)
    for i, it in ipairs(app.report.items) do
      local y = 226 + (i - 1) * 54
      lg.setColor(it.ok and C.greenSoft or C.warnSoft); lg.circle("fill", 124, y + 14, 14)
      U.text(it.ok and "✓" or "!", 110, y + 5, 16, it.ok and C.greenInk or C.warn, "center", 28)
      U.text(it.name, 152, y + 4, 17)
      U.text(it.note, 300, y + 6, 15, it.ok and C.greenInk or C.warn, "right", 290)
      lg.setColor(C.bg); lg.rectangle("fill", 110, y + 40, 480, 2)
    end
  end
  U.text("HOW THIS PLAYER SWINGS", 652, 130, 16, C.sub)
  app.levelHits = {}
  for l = 1, 4 do
    local y = 160 + (l - 1) * 76
    U.rect(652, y, 548, 64, 20, C.card)
    U.rect(670, y + 15, 34, 34, 12, C.blueSoft)
    U.text(tostring(l), 670, y + 22, 17, C.blueDark, "center", 34)
    U.text(motion.LEVEL_NAMES[l], 718, y + 12, 17)
    local subs = { "Swing tracking from gyro + accelerometer", "Aim with gyro, flick or press to swing",
      "No motion: hold B and flick the stick", "Drag to aim, flick to throw" }
    U.text(subs[l], 718, y + 34, 14, C.sub)
    if app.report and l == app.report.level then
      U.rect(1066, y + 20, 112, 24, 12, C.greenSoft)
      U.text("Recommended", 1066, y + 24, 13, C.greenInk, "center", 112)
    end
    if l == app.levelSel then U.selected(652, y, 548, 64, 20) end
    app.levelHits[l] = { x = 652, y = y, w = 548, h = 64 }
  end
  footer({ { "Fix axes", "wizard" }, { "Run check again", "recheck" }, { "Use level " .. app.levelSel, "uselevel", "primary" } })
end

------------------------------------------------------------ 9 Axis wizard
screens.wizard = {}
function screens.wizard.enter() app.wiz = cal.newWizard(); app.wizDone = nil end
function screens.wizard.update(dt)
  local c = ctrl()
  local r = I.raw[c]
  if app.wizDone or not r then return end
  cal.wizardFeed(app.wiz, dt, r.g)
  -- auto-advance: moved far enough and came most of the way back
  local _, peak = cal.wizardLive(app.wiz)
  local _, curAxisVal = nil, nil
  local cur = app.wiz.cur
  local maxCur = math.max(math.abs(cur[1]), math.abs(cur[2]), math.abs(cur[3]))
  if math.abs(peak) > math.rad(25) and maxCur < math.abs(peak) * 0.4 then
    cal.wizardNext(app.wiz)
    if app.wiz.step > #cal.STEPS then
      local axes, signs = cal.wizardSolve(app.wiz)
      if axes then
        cal.applyAxes(c.profile, axes, signs)
        if r.a then cal.fixGravity(c.profile, r.a) end
        c.raw = m.qid(); c:recentre()
        I.saveProfile(c)
        app.wizDone = { axes = axes, signs = signs }
      end
    end
  end
end
function screens.wizard.draw()
  local c = ctrl()
  U.header("SETUP · FIX AXES", "Tilt to teach the game")
  U.rect(80, 130, 1120, 480, 32, C.card)
  local w = app.wiz
  local step = cal.STEPS[math.min(w.step, #cal.STEPS)]
  if app.wizDone then
    U.text("All set", 112, 162, 28)
    U.text("The fix is saved for " .. c.name .. " and loads automatically next time.", 112, 202, 16, C.sub)
  else
    U.text(step.title, 112, 162, 28)
    U.text(step.hint, 112, 202, 16, C.sub, "left", 520)
  end
  -- illustration: a bar rotated by the live angle
  U.rect(112, 252, 520, 250, 22, C.soft)
  local bi, peak = cal.wizardLive(w)
  lg.push(); lg.translate(372, 382)
  local cur = w.cur[bi] or 0
  lg.rotate(-cur)
  U.rect(-130, -22, 260, 44, 22, C.card)
  lg.setColor(C.ink); lg.setLineWidth(4); lg.rectangle("line", -130, -22, 260, 44, 22, 22)
  lg.setColor(C.blue); lg.circle("fill", 78, 0, 10)
  lg.pop(); lg.setLineWidth(1)
  for i, s in ipairs(cal.STEPS) do
    local x = 112 + (i - 1) * 176
    local state = (app.wizDone or i < w.step) and "done" or (i == w.step and "now" or "todo")
    U.rect(x, 518, 166, 58, 16, state == "done" and C.greenSoft or (state == "now" and C.blueSoft or C.soft))
    U.text(state == "done" and "DONE" or (state == "now" and "NOW" or "STEP " .. i), x + 14, 528, 13,
      state == "done" and C.greenInk or (state == "now" and C.blueDark or C.sub))
    U.text(({ "Tilt forward", "Turn left", "Twist right" })[i], x + 14, 546, 16)
  end
  U.text("WHAT THE GAME SEES", 664, 162, 16, C.sub)
  U.rect(664, 194, 504, 122, 20, C.soft)
  local names = { "Device X", "Device Y", "Device Z" }
  U.text("Strongest axis", 684, 210, 17); U.text(names[bi], 684, 210, 17, C.ink, "right", 464)
  local flipped = step and peak * step.sign < 0
  U.text("Direction", 684, 242, 17)
  U.text(math.abs(peak) < 0.05 and "—" or (flipped and "Flipped" or "Normal"), 684, 242, 17, flipped and C.warn or C.greenInk, "right", 464)
  U.text("Mapped to", 684, 274, 17)
  U.text(({ "Pitch", "Yaw", "Roll" })[step.axis] .. (math.abs(peak) > math.rad(25) and " ✓" or ""), 684, 274, 17, C.greenInk, "right", 464)
  U.rect(664, 330, 504, 78, 20, C.soft)
  U.text("Live", 684, 344, 15)
  U.bar(704, 374, 260, cur / math.rad(60), C.blue)
  U.text(string.format("%+.0f°", math.deg(cur)), 980, 371, 14)
  footer({ { "Redo this step", "redo" }, { app.wizDone and "Done" or "Skip", "back", app.wizDone and "primary" } })
end

------------------------------------------------------------ 10 Buttons
screens.remap = {}
function screens.remap.enter() app.remapSel = 1; app.listening = nil end
function screens.remap.draw()
  local c = ctrl()
  U.header("SETUP · " .. c.name:upper(), "Buttons")
  local labels = { a = "A · confirm / swing", b = "B · back / brake", one = "1 · camera", two = "2 · ready",
    plus = "+ · pause", minus = "− · options", home = "Home · menu" }
  app.rowHits = {}
  for i, act in ipairs(I.ACTIONS) do
    local y = 130 + (i - 1) * 66
    U.rect(80, y, 560, 56, 18, C.card)
    U.text(labels[act], 98, y + 17, 18)
    if app.listening == act then
      U.rect(470, y + 12, 150, 32, 16, C.warnSoft)
      U.text("Press a button…", 470, y + 18, 15, C.warn, "center", 150)
    else
      local b = c.profile.buttons[act] or (c.ble and (I.jc2.DEFAULTS[c.ble.pid] or {})[act]) or I.DEFAULT_BUTTONS[act]
      b = b:gsub("^jc:", "")
      local bw = math.max(38, U.textWidth(b:upper(), 16) + 20)
      lg.setColor(C.ink); lg.rectangle("fill", 622 - bw, y + 9, bw, 38, 19, 19)
      U.text(b:upper(), 622 - bw, y + 19, 16, C.card, "center", bw)
    end
    if app.remapSel == i and app.focus == -1 then U.focus(80, y, 560, 56, 18) end
    app.rowHits[i] = { x = 80, y = y, w = 560, h = 56 }
  end
  U.rect(680, 130, 520, 420, 32, C.card)
  U.text(app.listening and ("Press the button you want for " .. app.listening:upper())
    or "Pick an action, then press its new button", 712, 162, 24, C.ink, "center", 456)
  U.text((c.joystick or c.ble) and "Saved for this exact controller" or "This device has no buttons to remap", 712, 500, 14, C.sub, "center", 456)
  footer({ { "Reset to default", "reset" }, { "Save for this controller", "save", "primary" } })
end

------------------------------------------------------------ Pair Joy-Con 2
screens.pair = {}
function screens.pair.enter() app.pairSel = 1; if I.jc2.available then I.jc2.scan(true) end end
function screens.pair.leave() if I.jc2.available then I.jc2.scan(false) end end
function screens.pair.draw()
  local B = I.jc2
  U.header("SETUP · BLUETOOTH", "Connect Joy-Con 2")
  U.rect(80, 130, 540, 480, 32, C.card)
  U.text("Press the SYNC button", 110, 160, 26)
  U.text("It's the small round button on the flat rail side of each Joy-Con 2 (or next to the USB port on a Pro Controller 2). The lights will run back and forth.",
    110, 200, 16, C.sub, "left", 480)
  -- rail illustration
  U.rect(150, 300, 400, 120, 22, C.soft)
  U.rect(200, 340, 300, 40, 20, C.red)
  U.rect(200, 340, 300, 12, 6, { 0.949, 0.416, 0.384 })
  lg.setColor(C.ink); lg.circle("fill", 282, 360, 8)
  for i = 0, 3 do lg.setColor(i == 1 and C.green or C.line); lg.circle("fill", 380 + i * 22, 360, 6) end
  lg.setColor(C.blue); lg.setLineWidth(3); lg.circle("line", 282, 360, 18); lg.setLineWidth(1)
  U.text("SYNC", 252, 392, 13, C.blueDark, "center", 60)
  U.text("Windows doesn't list Joy-Con 2 under Bluetooth settings — the game connects to them directly. Press SYNC every time you connect.",
    110, 446, 14, C.sub, "left", 480)

  U.text("CONTROLLERS NEARBY", 652, 130, 16, C.sub)
  app.pairHits = {}
  if not B.available then
    U.rect(652, 160, 548, 90, 20, C.warnSoft)
    U.text(B.reason or "Bluetooth isn't available", 676, 180, 17, C.warn, "left", 500)
  else
    if #B.found == 0 then
      U.rect(652, 160, 548, 64, 20, C.card)
      U.text(B.status or "Searching…", 676, 182, 15, C.sub, "left", 500)
    end
    for i, e in ipairs(B.found) do
      local y = 160 + (i - 1) * 76
      U.rect(652, y, 548, 64, 20, C.card)
      U.text(e.name, 676, y + 12, 17)
      local st = ({ found = "Press A to connect", connecting = e.statusText or "Connecting…", connected = "Connected",
        failed = e.statusText or "Failed — press SYNC and try again", lost = "Disconnected" })[e.state] or e.state
      U.text(st, 676, y + 34, 14, e.state == "connected" and C.greenInk or (e.state == "failed" and C.warn or C.sub), "left", 380)
      U.text(string.format("%d dBm", e.rssi), 1050, y + 22, 14, C.sub, "right", 130)
      if app.pairSel == i and app.focus == -1 then U.focus(652, y, 548, 64, 20) end
      app.pairHits[i] = { x = 652, y = y, w = 548, h = 64 }
    end
  end
  footer({ { "Search again", "rescan" }, { "Done", "back", "primary" } })
end

------------------------------------------------------------ actions
local function go(name)
  if screens[app.screen].leave then screens[app.screen].leave() end
  app.screen = name
  app.focus = (name == "remap" or name == "pair") and -1 or nil
  if screens[name].enter then screens[name].enter() end
end

local actions = {
  next = function() app.sel = app.sel % #I.list + 1; app.lastSwing = nil end,
  recentre = function() ctrl():recentre() end,
  check = function() go("check") end,
  remap = function() go("remap") end,
  pair = function() go("pair") end,
  rescan = function() I.jc2.scan(false); I.jc2.scan(true) end,
  wizard = function() go("wizard") end,
  recheck = function() screens.check.enter() end,
  uselevel = function() local c = ctrl(); c.level = app.levelSel; c.profile.level = app.levelSel; I.saveProfile(c); go("test") end,
  redo = function() cal.wizardRedo(app.wiz) end,
  back = function() go("test") end,
  reset = function() ctrl().profile.buttons = {} end,
  save = function() I.saveProfile(ctrl()); go("test") end,
}

local function activate(i)
  if i == 0 then
    if app.screen == "test" then love.event.quit() else go("test") end
    return
  end
  local h = app.hits[i]
  if h and actions[h.action] then actions[h.action]() end
end

local function navigate(nav)
  -- B goes back from setup screens; on the test screen it does nothing (B/ZR is a game button)
  if nav.b and not app.listening and app.screen ~= "test" then activate(0); return end
  if app.screen == "check" and app.report then
    if nav.up then app.levelSel = math.max(1, app.levelSel - 1) end
    if nav.down then app.levelSel = math.min(4, app.levelSel + 1) end
  end
  if app.screen == "pair" then
    local nf = #I.jc2.found
    if app.focus == -1 then
      if nav.up then app.pairSel = math.max(1, app.pairSel - 1) end
      if nav.down then
        if app.pairSel >= nf then app.focus = app.footerCount else app.pairSel = app.pairSel + 1 end
      end
      if nav.a and I.jc2.found[app.pairSel] then I.jc2.connect(I.jc2.found[app.pairSel]) end
      if nf == 0 then app.focus = app.footerCount end
      if nav.b then activate(0) end
      return
    elseif nav.up and nf > 0 then app.focus = -1; return end
  end
  if app.screen == "remap" then
    if app.focus == -1 then
      if nav.up then app.remapSel = math.max(1, app.remapSel - 1) end
      if nav.down then
        if app.remapSel == #I.ACTIONS then app.focus = app.footerCount else app.remapSel = app.remapSel + 1 end
      end
      if nav.a and (ctrl().joystick or ctrl().ble) then
        local act = I.ACTIONS[app.remapSel]
        app.listening = act
        I.capture(function(c, button)
          if c == ctrl() then c.profile.buttons[act] = button end
          app.listening = nil
        end, ctrl())
      end
      return
    elseif nav.up then app.focus = -1; return end
  end
  if nav.left then app.focus = math.max(0, app.focus - 1) end
  if nav.right then app.focus = math.min(app.footerCount or 0, app.focus + 1) end
  if nav.a then activate(app.focus) end
  if nav.two and app.screen == "test" then actions.next() end
  if nav.one and app.screen == "test" then actions.recentre() end
end

------------------------------------------------------------ LÖVE callbacks
function love.load()
  U.resize(lg.getDimensions())
  I.init()
  app.sel = (#I.list > 1) and 2 or 1 -- prefer a real controller over the mouse
  app.focus = nil
end
function love.resize(w, h) U.resize(w, h) end
function love.quit() I.shutdown() end
function love.update(dt)
  dt = math.min(dt, 0.05)
  I.update(dt)
  if screens[app.screen].update then screens[app.screen].update(dt) end
  if not app.listening then navigate(I.navPressed()) else I.navPressed() end
  I.endFrame()
end
function love.draw()
  U.begin()
  screens[app.screen].draw()
  U.finish()
end
function love.keypressed(k) I.keypressed(k) end
function love.joystickadded(js) I.joystickadded(js) end
function love.joystickremoved(js)
  I.joystickremoved(js)
  if app.sel > #I.list then app.sel = 1 end
end
function love.gamepadpressed(js, b) I.gamepadpressed(js, b) end
function love.joystickpressed(js, b) I.joystickpressed(js, b) end

-- mouse / touch: menu clicks, and gesture swings on the mouse controller
function love.mousepressed(x, y, button)
  local dx, dy = U.toDesign(x, y)
  for i = 0, app.footerCount or 0 do
    local h = i == 0 and app.hits.back or app.hits[i]
    if U.hit(h, dx, dy) then activate(i); return end
  end
  if app.screen == "check" and app.levelHits then
    for l, h in ipairs(app.levelHits) do if U.hit(h, dx, dy) then app.levelSel = l; return end end
  end
  if app.screen == "pair" and app.pairHits then
    for i, h in ipairs(app.pairHits) do
      if U.hit(h, dx, dy) then app.focus = -1; app.pairSel = i; I.jc2.connect(I.jc2.found[i]); return end
    end
  end
  if app.screen == "remap" and app.rowHits then
    for i, h in ipairs(app.rowHits) do
      if U.hit(h, dx, dy) then app.focus = -1; app.remapSel = i; navigate({ a = true }); return end
    end
  end
  if app.screen == "test" and ctrl() == I.mouse then
    I.mouse.drag = { { x = x, y = y, t = love.timer.getTime() } }
  end
end
function love.mousemoved(x, y)
  local c = I.mouse
  if not c then return end
  local w, h = lg.getDimensions()
  c.pointer.x, c.pointer.y, c.pointer.valid = x / w, y / h, true
  if c.drag then c.drag[#c.drag + 1] = { x = x, y = y, t = love.timer.getTime() } end
end
function love.mousereleased(x, y)
  local c = I.mouse
  if c and c.drag then
    local ev = detectorFor(c):gesture(c.drag, 400 * U.scale)
    if ev then app.lastSwing = ev end
    c.drag = nil
  end
end
