## Controllers: the mouse (or touch) is always there; gamepads come and go. Each controller
## gives the same fields to the games: buttons / pressed (this frame), the stick, a motion
## level and, for motion controllers, a history of orientation samples.
## Buttons: a, b = throw (trigger), back, plus (pause), recentre, sclick (stick press),
## left / right / up / down.
extends Node

enum { FULL = 1, GYRO_POINTER = 2, STICK_POINTER = 3, GESTURE = 4 }
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
			a = Input.is_joy_button_pressed(d, JOY_BUTTON_A),
			back = Input.is_joy_button_pressed(d, JOY_BUTTON_B),
			b = Input.get_joy_axis(d, JOY_AXIS_TRIGGER_RIGHT) > 0.5 or Input.is_joy_button_pressed(d, JOY_BUTTON_RIGHT_SHOULDER),
			recentre = Input.is_joy_button_pressed(d, JOY_BUTTON_Y),
			plus = Input.is_joy_button_pressed(d, JOY_BUTTON_START),
			sclick = Input.is_joy_button_pressed(d, JOY_BUTTON_LEFT_STICK),
			left = Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_LEFT),
			right = Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_RIGHT),
			up = Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_UP),
			down = Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_DOWN),
		}
		c.stick = Vector2(Input.get_joy_axis(d, JOY_AXIS_LEFT_X), -Input.get_joy_axis(d, JOY_AXIS_LEFT_Y))
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
		if c.kind == "joycon2":
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
	return n

## a key, as the bowling game moves the bowler with the arrows too
func key(k: Key) -> bool:
	return Input.is_physical_key_pressed(k)
