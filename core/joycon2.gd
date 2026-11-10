## Joy-Con 2 / Pro Controller 2 over Bluetooth LE, through the osble extension (Windows,
## native/osble_gd). Windows can't pair these as normal gamepads, so the game scans and
## connects itself. Report layout (common report 0x05, 63 bytes): linux-switch2 PROTOCOL.md
## §29–37. Scales and axes follow SDL's Switch 2 driver.
class_name JoyCon2

const NAMES := {0x2066: "Joy-Con 2 (R)", 0x2067: "Joy-Con 2 (L)", 0x2069: "Pro Controller 2", 0x2073: "GameCube Controller (NSO)"}
## button bits: byte offset 4.. (linux-switch2 §30)
const BUTTONS := {
	Y = [0, 0], X = [0, 1], B = [0, 2], A = [0, 3], SR_R = [0, 4], SL_R = [0, 5], R = [0, 6], ZR = [0, 7],
	MINUS = [1, 0], PLUS = [1, 1], RSTICK = [1, 2], LSTICK = [1, 3], HOME = [1, 4], CAPTURE = [1, 5], C = [1, 6],
	DOWN = [2, 0], UP = [2, 1], RIGHT = [2, 2], LEFT = [2, 3], SR_L = [2, 4], SL_L = [2, 5], L = [2, 6], ZL = [2, 7],
}
## held upright like a Wii Remote: the face button under the thumb is A, the back trigger
## B (the throw button), the top face button re-centres, pressing the stick in is "sclick"
const DEFAULTS := {
	0x2066: {a = "A", b = "ZR", back = "B", plus = "PLUS", recentre = "X", sclick = "RSTICK"},
	0x2067: {a = "RIGHT", b = "ZL", back = "DOWN", plus = "MINUS", recentre = "UP", sclick = "LSTICK"},
	0x2069: {a = "A", b = "ZR", back = "B", plus = "PLUS", recentre = "X", sclick = "LSTICK", up = "UP", down = "DOWN", left = "LEFT", right = "RIGHT"},
}
const ACCEL_G_PER_LSB := 0.000244140625
const GYRO_DPS_PER_LSB := 0.06103515625

static var lib = null
static var available := false
static var reason := ""
static var found := []     # { addr, pid, rssi, name, state, id, status_text, ctrl }
static var pads := {}      # id -> entry
static var status := ""
static var scanning := false
static var background := false

static func init() -> void:
	if not ClassDB.class_exists("OSBLE"):
		reason = "Bluetooth pairing in the game is Windows-only for now" if OS.get_name() != "Windows" else "osble.dll is missing next to the game"
		return
	lib = ClassDB.instantiate("OSBLE")
	available = lib != null
	if available:
		Log.write("Bluetooth: osble %d ready" % lib.version())

static func scan(on: bool) -> void:
	if not available:
		return
	if on:
		found = []
		status = "Searching… press the small SYNC button on the controller's rail"
	lib.scan(on)
	scanning = on

## listen in the background: saved controllers connect themselves when they show up
static func listen(on: bool) -> void:
	if not available:
		return
	background = on
	lib.scan(false)
	if on:
		lib.scan(true)
	scanning = on

static func busy(addr: int) -> bool:
	for e in pads.values():
		if e.addr == addr:
			return true
	return false

static func connect_entry(e: Dictionary) -> void:
	if not available or e.get("id", -1) >= 0:
		return
	e.id = lib.connect_pad(e.addr, e.pid)
	e.state = "connecting"
	pads[e.id] = e

static func _stick(p: PackedByteArray, o: int) -> Vector2:
	var x := p[o] | ((p[o + 1] & 0x0F) << 8)
	var y := (p[o + 1] >> 4) | (p[o + 2] << 4)
	return Vector2(clampf((x - 2048) / 1500.0, -1, 1), clampf((y - 2048) / 1500.0, -1, 1))

static func _s16(p: PackedByteArray, o: int) -> int:
	var v := p[o] | (p[o + 1] << 8)
	return v - 65536 if v >= 32768 else v

static func _u32(p: PackedByteArray, o: int) -> int:
	return p[o] | (p[o + 1] << 8) | (p[o + 2] << 16) | (p[o + 3] << 24)

## raw counts -> the game's frame (via the DSU wire layout, as Dolphin reads it)
static func to_game(rg: Vector3, ra: Vector3) -> Array:
	var acc := Vector3(-ra.x, -ra.z, ra.y) * ACCEL_G_PER_LSB      # DSU accel (g)
	var gyr := Vector3(rg.x, -rg.z, rg.y) * GYRO_DPS_PER_LSB      # DSU gyro (deg/s): pitch, yaw, roll
	var g := Vector3(gyr.x, -gyr.y, -gyr.z) * (PI / 180.0)
	var a := Vector3(-acc.x, -acc.y, -acc.z) * 9.80665
	return [g, a]

static func update(inputs, frame_dt: float) -> void:
	if not available:
		return
	for c in inputs.list:
		if c.kind == "joycon2":
			c.pressed = {}
	for e in lib.poll():
		match int(e.type):
			1: # found
				var entry := {addr = e.addr, pid = e.pid, rssi = e.rssi, name = NAMES.get(e.pid, "Switch 2 controller %04X" % e.pid),
					state = "found", id = -1, status_text = ""}
				found.append(entry)
				if not busy(e.addr) and _is_saved(e.addr) and Settings.get_value("auto_connect"):
					connect_entry(entry)
			2: # connected
				var entry = pads.get(e.id)
				if entry != null:
					entry.state = "connected"
					entry.ctrl = _make_ctrl(inputs, entry)
					lib.leds(e.id, [0x01, 0x03, 0x07, 0x0F][mini(3, inputs.list.size() - 2)])
					_remember(entry)
			3: # disconnected
				var entry = pads.get(e.id)
				if entry != null:
					entry.state = "lost"
					if entry.has("ctrl"):
						inputs.remove(entry.ctrl)
					lib.disconnect_pad(e.id)
					pads.erase(e.id)
					if background:
						listen(true)
			4: # status
				var entry = pads.get(e.id)
				if entry != null:
					entry.status_text = e.text
					if str(e.text).begins_with("Fast updates") and entry.has("ctrl"):
						entry.ctrl.rate_text = e.text
			5: # failed
				var entry = pads.get(e.id)
				if entry != null:
					entry.state = "failed"
					entry.status_text = e.text
					entry.id = -1
					pads.erase(e.id)
				else:
					status = e.text
	for e in pads.values():
		if e.has("ctrl"):
			_read(e.ctrl, frame_dt)

static func _make_ctrl(inputs, entry: Dictionary):
	var c = inputs.Ctrl.new()
	c.kind = "joycon2"
	c.name = entry.name
	c.id = "ble%d" % entry.id
	c.level = inputs.FULL
	c.has_gyro = true
	c.ble = entry
	c.set_meta("ts", -1)
	inputs.add(c)
	c.recentre()
	Log.write("Bluetooth: %s connected" % entry.name)
	return c

static func _read(c, frame_dt: float) -> void:
	var reports: Array = lib.reports(c.ble.id)
	var n := reports.size()
	if n == 0:
		return
	for i in n:
		var p: PackedByteArray = reports[i]
		if p[63] == 1:
			continue # native side report (orientation path not used)
		# time step per report, the way SDL's Switch 2 driver does it: the motion timestamp
		# is normally microseconds, but some firmware counts in other units, so measure it
		# once against the clock over the first ~100 reports
		var ts := _u32(p, 0x2A)
		var now := Time.get_ticks_usec() / 1e6
		var cal: Dictionary = c.get_meta("tscal", {n = 0, ts0 = -1, t0 = 0.0, tick = 0.0, done = false})
		if not cal.done and ts != 0:
			if cal.ts0 < 0:
				cal.ts0 = ts
				cal.t0 = now
			else:
				cal.n += 1
				if cal.n >= 100 and now - cal.t0 > 0.3:
					var span: int = ts - cal.ts0
					if span < 0:
						span += 4294967296
					var per_sec: float = span / (now - cal.t0)
					if absf(per_sec / 1e6 - 1) < 0.1:
						cal.tick = 1e-6
					elif per_sec > 0:
						cal.tick = 1.0 / per_sec
					cal.done = true
		c.set_meta("tscal", cal)
		var dt := frame_dt / n
		var prev: int = c.get_meta("ts")
		if prev >= 0 and cal.tick > 0:
			var d := ts - prev
			if d < 0:
				d += 4294967296
			var s: float = d * cal.tick
			if s > 0 and s < 0.06:
				dt = s
		c.set_meta("ts", ts)
		var ga := to_game(Vector3(_s16(p, 0x36), _s16(p, 0x38), _s16(p, 0x3A)), Vector3(_s16(p, 0x30), _s16(p, 0x32), _s16(p, 0x34)))
		c.feed(dt, ga[0], ga[1])
		if i == n - 1:
			var raw := {}
			for bn in BUTTONS:
				var bb: Array = BUTTONS[bn]
				raw[bn] = (p[4 + bb[0]] & (1 << bb[1])) != 0
			c.set_meta("raw", raw)
			for logical in ["a", "b", "back", "plus", "recentre", "sclick", "up", "down", "left", "right"]:
				var down := false
				for bn in Inputs.binding(c, logical):
					down = down or raw.get(bn, false)
				c.set_button(logical, down)
			var st := _stick(p, 0x0D if c.ble.pid == 0x2066 else 0x0A)
			c.stick = st
			if c.ble.pid == 0x2069:
				c.rstick = _stick(p, 0x0D)
			c.set_button("up", c.buttons.get("up", false) or st.y > 0.6)
			c.set_button("down", c.buttons.get("down", false) or st.y < -0.6)
			c.set_button("left", c.buttons.get("left", false) or st.x < -0.6)
			c.set_button("right", c.buttons.get("right", false) or st.x > 0.6)
			if c.pressed.get("back", false):
				Inputs._nav["b"] = true

# ------------------------------------------------------------------ saved controllers

static func _saved() -> Array:
	var s = Settings.get_value("saved")
	return s if s is Array else []

static func _is_saved(addr: int) -> bool:
	for e in _saved():
		if int(e.addr) == addr:
			return true
	return false

static func _remember(entry: Dictionary) -> void:
	var list := _saved().filter(func(e): return int(e.addr) != entry.addr)
	list.push_front({addr = entry.addr, pid = entry.pid, name = entry.name})
	while list.size() > 8:
		list.pop_back()
	Settings.set_value("saved", list)

static func shutdown() -> void:
	if available:
		lib.shutdown()
