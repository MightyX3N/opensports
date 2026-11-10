## Controllers: the mouse (or touch) is always there; gamepads come and go. Each controller
## gives the same fields to the games: buttons / pressed (this frame), the stick, a motion
## level and, for motion controllers, a history of orientation samples.
## Buttons: a, b = throw (trigger), back, plus (pause), recentre, sclick (stick press),
## left / right / up / down.
extends Node

enum { FULL = 1, GYRO_POINTER = 2, STICK_POINTER = 3, GESTURE = 4 }
## what each game action is on a gamepad (Godot's button numbers; "rt" / "lt" are the triggers);
## a list means any of them. Changed on the Buttons screen (saved in settings "button_maps").
const ACTIONS := ["b", "a", "back", "plus", "recentre", "sclick"]
const ACTION_NAMES := {b = "Swing / throw", a = "A (select, toss)", back = "Back", plus = "Pause", recentre = "Re-centre", sclick = "Switch move / turn"}
const PAD_DEFAULT := {b = ["rt", JOY_BUTTON_RIGHT_SHOULDER], a = [JOY_BUTTON_A], back = [JOY_BUTTON_B], plus = [JOY_BUTTON_START],
	recentre = [JOY_BUTTON_Y], sclick = [JOY_BUTTON_LEFT_STICK]}
const PAD_NAMES := {0: "A", 1: "B", 2: "X", 3: "Y", 4: "Back", 5: "Guide", 6: "Start", 7: "Left stick", 8: "Right stick",
	9: "LB", 10: "RB", 11: "Up", 12: "Down", 13: "Left", 14: "Right", 15: "Misc", "rt": "RT", "lt": "LT"}
const LEVEL_NAMES := {1: "Full motion", 2: "Gyro as pointer", 3: "Stick as pointer", 4: "Touch / mouse"}

class Ctrl:
	var id = null
	var kind := "gamepad"   # mouse, gamepad, joycon2, dsu
	var name := "Controller"
	var device := -1
	var buttons := {}
	var pressed := {}
	var _held := {}
	var stick := Vector2.ZERO
	var rstick := Vector2.ZERO # the second stick, if the controller has one
	var level := 3
	var has_gyro := false
	var history := []       # last second of { t, gyro: Vector3 (rad/s), orient: Quaternion }
	var orient := Quaternion.IDENTITY # controller -> world, after recentre
	var raw := Quaternion.IDENTITY    # fusion state, before recentre
	var gyro := Vector3.ZERO
	var yaw_offset := 0.0
	var fusion := GMH.new()
	var t := 0.0
	var ble = null          # Joy-Con 2: its Bluetooth entry
	var rate_text := ""

	## one raw sensor sample: gyro rad/s, accel m/s^2 (gravity included), controller axes
	## (x right, y up out of the buttons, z towards the player when held like a Wii Remote)
	func feed(dt: float, g: Vector3, a: Vector3) -> void:
		if dt <= 0:
			return
		t += dt
		fusion.process(g * (180.0 / PI), a / 9.80665, dt)
		gyro = fusion.gyro * (PI / 180.0)
		raw = fusion.q
		orient = Quaternion(Vector3.UP, -yaw_offset) * raw
		history.append({t = t, gyro = gyro, orient = orient})
		while history.size() > 1 and t - history[0].t > 1.0:
			history.pop_front()

	func set_button(n: String, down: bool) -> void:
		if down and not _held.get(n, false):
			pressed[n] = true
		_held[n] = down
		buttons[n] = down

	## the current heading becomes "forward" (a sport can pass its own heading)
	func recentre(yaw = null) -> void:
		if yaw == null:
			yaw = Inputs.angles(raw).x
		yaw_offset = yaw
		orient = Quaternion(Vector3.UP, -yaw_offset) * raw

	func rumble(dur: float, strength: float) -> void:
		if device >= 0:
			Input.start_joy_vibration(device, strength, strength, dur)

## yaw (turn left +), pitch (front up +), roll of the pointing axis (-z)
static func angles(q: Quaternion) -> Vector3:
	var f := q * Vector3(0, 0, -1)
	var r := q * Vector3(1, 0, 0)
	return Vector3(atan2(-f.x, -f.z), asin(clampf(f.y, -1, 1)), asin(clampf(-r.y, -1, 1)))

var list: Array[Ctrl] = []
var mouse: Ctrl
var current: Ctrl
var _nav := {}
var listening = null        # remapping: { ctrl, action, t, before: raw buttons already down }
var _swallow := 0.0         # after a remap press, ignore menu input for a moment
signal remapped(c: Ctrl, action: String, src)
var _prev := {}

signal connected(c: Ctrl)

func _ready() -> void:
	JoyCon2.init()
	mouse = Ctrl.new()
	mouse.id = "mouse"
	mouse.kind = "mouse"
	mouse.name = "Mouse / touch"
	mouse.level = GESTURE
	list.append(mouse)
	current = mouse
	for d in Input.get_connected_joypads():
		_add_pad(d)
	Input.joy_connection_changed.connect(_on_joy)
	if Settings.get_value("dsu"):
		DSU.start(Settings.get_value("dsu_server"))
	Settings.changed.connect(_on_setting)

func _on_setting(k: String, _v) -> void:
	if k == "dsu" or k == "dsu_server":
		if Settings.get_value("dsu"):
			DSU.start(Settings.get_value("dsu_server"))
		else:
			DSU.stop()

func _on_joy(device: int, is_connected: bool) -> void:
	if is_connected:
		var c := _add_pad(device)
		current = c
		connected.emit(c)
	else:
		for c in list:
			if c.device == device:
				list.erase(c)
				if current == c:
					current = mouse
				break

func _add_pad(device: int) -> Ctrl:
	for c in list:
		if c.device == device:
			return c
	var c := Ctrl.new()
	c.id = "pad%d" % device
	c.device = device
	c.name = Input.get_joy_name(device)
	if c.name == "":
		c.name = "Controller"
	c.kind = "joycon" if c.name.contains("Joy-Con") else "gamepad"
	c.level = STICK_POINTER
	list.append(c)
	return c

func _process(dt: float) -> void:
	JoyCon2.update(self, dt)
	DSU.update(self, dt)
	_listen(dt)
	for c in list:
		if c.kind == "joycon2":
			for k in ["up", "down", "left", "right", "a"]:
				if c.pressed.get(k):
					_nav[k] = true
			if c != current and (c.pressed.get("a") or c.pressed.get("b")):
				current = c
		if c.device < 0:
			continue
		c.t += dt
		var d := c.device
		var b := {
			left = Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_LEFT),
			right = Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_RIGHT),
			up = Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_UP),
			down = Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_DOWN),
		}
		for act in ACTIONS:
			var on := false
			for src in binding(c, act):
				on = on or _pad_down(d, src)
			b[act] = on
		c.stick = Vector2(Input.get_joy_axis(d, JOY_AXIS_LEFT_X), -Input.get_joy_axis(d, JOY_AXIS_LEFT_Y))
		c.rstick = Vector2(Input.get_joy_axis(d, JOY_AXIS_RIGHT_X), -Input.get_joy_axis(d, JOY_AXIS_RIGHT_Y))
		# the stick also works as a D-pad in menus (with a little repeat guard)
		var prev: Dictionary = _prev.get(c, {})
		var sdir := {left = c.stick.x < -0.6, right = c.stick.x > 0.6, up = c.stick.y > 0.6, down = c.stick.y < -0.6}
		c.pressed = {}
		for k in b:
			c.pressed[k] = b[k] and not c.buttons.get(k, false)
		for k in sdir:
			if sdir[k] and not prev.get(k, false):
				c.pressed[k] = true
		_prev[c] = sdir
		c.buttons = b
		for k in ["up", "down", "left", "right", "a"]:
			if c.pressed.get(k):
				_nav[k] = true
				if c != current and k == "a":
					pass
		if c.pressed.get("back"):
			_nav["b"] = true
		# picking up a controller and pressing a button hands it the game
		if c != current and (c.pressed.get("a") or c.pressed.get("b")):
			current = c

func _unhandled_key_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_UP, KEY_W: _nav["up"] = true
			KEY_DOWN, KEY_S: _nav["down"] = true
			KEY_LEFT, KEY_A: _nav["left"] = true
			KEY_RIGHT, KEY_D: _nav["right"] = true
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE: _nav["a"] = true
			KEY_ESCAPE, KEY_BACKSPACE: _nav["b"] = true

## after every frame: forget this frame's presses of the Bluetooth controllers
func end_frame() -> void:
	for c in list:
		if c.kind == "joycon2" or c.kind == "dsu":
			c.pressed = {}

func add(c: Ctrl) -> void:
	list.append(c)
	current = c
	connected.emit(c)

func remove(c: Ctrl) -> void:
	list.erase(c)
	if current == c:
		current = mouse

## menu navigation pressed since the last call: { up, down, left, right, a, b }
func take_nav() -> Dictionary:
	var n := _nav
	_nav = {}
	if _swallow > 0 or listening != null:
		return {}
	return n

# ------------------------------------------------------------------ button maps

static func _pad_down(d: int, src) -> bool:
	if src is String:
		return Input.get_joy_axis(d, JOY_AXIS_TRIGGER_RIGHT if src == "rt" else JOY_AXIS_TRIGGER_LEFT) > 0.5
	return Input.is_joy_button_pressed(d, int(src))

## which settings entry holds this controller's buttons ("" = can't be changed)
static func map_key(c: Ctrl) -> String:
	if c.kind == "joycon2" and c.ble != null:
		return "jc2_%d" % c.ble.pid
	if c.device >= 0:
		return "pad"
	return ""

static func default_binding(c: Ctrl, action: String) -> Array:
	if c.kind == "joycon2" and c.ble != null:
		var d: Dictionary = JoyCon2.DEFAULTS.get(c.ble.pid, JoyCon2.DEFAULTS[0x2069])
		return [d[action]] if d.has(action) else []
	return PAD_DEFAULT.get(action, [])

static func binding(c: Ctrl, action: String) -> Array:
	var maps = Settings.get_value("button_maps")
	var k := map_key(c)
	if maps is Dictionary and maps.has(k) and maps[k].has(action):
		return maps[k][action]
	return default_binding(c, action)

static func source_name(src) -> String:
	if src is String and not (src in ["rt", "lt"]):
		return src # Joy-Con 2 buttons go by their own names
	return PAD_NAMES.get(src if src is String else int(src), "Button %s" % str(src))

## raw buttons down right now (gamepad numbers / "rt" / Joy-Con 2 names)
func raw_down(c: Ctrl) -> Array:
	var out := []
	if c.kind == "joycon2":
		for n in c.get_meta("raw", {}):
			if c.get_meta("raw")[n]:
				out.append(n)
	elif c.device >= 0:
		for i in 21:
			if Input.is_joy_button_pressed(c.device, i):
				out.append(i)
		for t in ["rt", "lt"]:
			if _pad_down(c.device, t):
				out.append(t)
	return out

## wait for the next button pressed on c and put action on it
func listen_for(c: Ctrl, action: String) -> void:
	listening = {ctrl = c, action = action, t = 0.0, before = raw_down(c)}

func cancel_listen() -> void:
	listening = null
	_swallow = 0.3

func reset_buttons(c: Ctrl) -> void:
	var maps: Dictionary = Settings.get_value("button_maps").duplicate(true)
	maps.erase(map_key(c))
	Settings.set_value("button_maps", maps)

func _listen(dt: float) -> void:
	_swallow = maxf(0, _swallow - dt)
	if listening == null:
		return
	listening.t += dt
	var c: Ctrl = listening.ctrl
	if listening.t > 6.0 or not list.has(c) or Input.is_physical_key_pressed(KEY_ESCAPE):
		cancel_listen()
		return
	var now := raw_down(c)
	# a button held when listening started counts only once it's been let go and pressed again
	listening.before = listening.before.filter(func(s): return now.has(s))
	for s in now:
		if not listening.before.has(s):
			var maps: Dictionary = Settings.get_value("button_maps").duplicate(true)
			var k := map_key(c)
			if not maps.has(k):
				maps[k] = {}
			maps[k][listening.action] = [s]
			Settings.set_value("button_maps", maps)
			remapped.emit(c, listening.action, s)
			listening = null
			_swallow = 0.4
			return

## a key, as the bowling game moves the bowler with the arrows too
func key(k: Key) -> bool:
	return Input.is_physical_key_pressed(k)
