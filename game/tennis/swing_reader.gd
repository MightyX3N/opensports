## Reads tennis swings from whatever the player holds. A swing is { power 0..1, shape } where
## shape is "flat" (a level swing: topspin drive), "slice" (high to low) or "lob" (low to high).
##  - motion (Joy-Con 2): a swing is a burst of rotation; it fires at its fastest moment (that
##    is the contact), power from how fast, shape from how much the controller tipped up or
##    down on the way;
##  - sticks: flick the stick (the right one when there is one): sideways = flat, up = lob,
##    down = slice; the throw button / trigger is a plain flat swing;
##  - mouse: hold the button and flick (up = lob, down = slice), or just click;
##  - keyboard: Space swings, with W / Up held for a lob or S / Down for a slice.
class_name SwingReader
extends RefCounted

const START := 5.0        # rad/s: a swing has begun
const MIN_PEAK := 8.0     # rad/s: weaker bursts are fidgeting, not swings
const FULL := 22.0        # rad/s: a full-power swing
const TIP := 0.55         # rad of pitch change that makes a lob or a slice
const COOLDOWN := 0.45
const FLICK_TIME := 0.15
const MOUSE_FAST := 1700.0  # design px/s
const MOUSE_FULL := 6000.0

var ctrl
var t := 0.0
var cool := 0.0
var _sw = null              # motion swing in progress { t0, peak, pitch0, pitch_at_peak, last }
var _flick = null           # stick flick in progress { t0, stick }
var _was_out := false
var _keys := {}
var _mouse := []            # recent pointer samples { p, t } while the button is held
var _mouse_down := false
var _mouse_fired := false

func _init(c) -> void:
	ctrl = c

func reset() -> void:
	_sw = null
	_flick = null
	cool = 0.0

func motion() -> bool:
	return ctrl != null and ctrl.level == Inputs.FULL and ctrl.has_gyro

## call every frame; returns a swing or {}
func update(dt: float) -> Dictionary:
	t += dt
	cool = maxf(0, cool - dt)
	var out := {}
	if ctrl == null:
		return out
	if motion():
		out = _motion()
	elif ctrl.kind != "mouse":
		out = _stick()
	if out.is_empty() and ctrl.pressed.get("b", false) and not motion():
		out = {power = 0.65, shape = "flat"}
	var k := _key_swing()
	if out.is_empty() and not k.is_empty():
		out = k
	if not out.is_empty():
		if cool > 0:
			return {}
		cool = COOLDOWN
	return out

func _motion() -> Dictionary:
	var speed: float = ctrl.gyro.length()
	var pitch: float = Inputs.angles(ctrl.orient).y
	if _sw == null:
		if speed > START and cool <= 0:
			# start from where the controller pointed just before the burst
			var p0 := pitch
			for h in ctrl.history:
				if ctrl.t - h.t < 0.12:
					p0 = Inputs.angles(h.orient).y
					break
			_sw = {t0 = t, peak = speed, pitch0 = p0, pitch_peak = pitch, falling = 0}
		return {}
	if speed > _sw.peak:
		_sw.peak = speed
		_sw.pitch_peak = pitch
		_sw.falling = 0
		return {}
	_sw.falling += 1
	# past the fastest moment (two readings in a row slower, or it has died away)
	if _sw.falling >= 2 or speed < START * 0.6 or t - _sw.t0 > 0.5:
		var sw: Dictionary = _sw
		_sw = null
		if sw.peak < MIN_PEAK:
			return {}
		var tip: float = sw.pitch_peak - sw.pitch0
		var shape := "flat"
		if tip > TIP: shape = "lob"
		elif tip < -TIP: shape = "slice"
		return {power = clampf((sw.peak - MIN_PEAK * 0.6) / (FULL - MIN_PEAK * 0.6), 0.1, 1), shape = shape}
	return {}

func _stick() -> Dictionary:
	var s: Vector2 = ctrl.rstick if ctrl.rstick.length() > 0.2 or ctrl.kind == "gamepad" else ctrl.stick
	var m := s.length()
	if m < 0.35:
		_flick = {t0 = t}
		_was_out = false
		return {}
	if m > 0.85 and not _was_out:
		_was_out = true
		if _flick == null:
			return {}
		var took: float = t - _flick.t0
		_flick = null
		if took > FLICK_TIME * 2:
			return {} # pushed slowly: not a swing
		var shape := "flat"
		if s.y > 0.6 and absf(s.y) > absf(s.x): shape = "lob"
		elif s.y < -0.6 and absf(s.y) > absf(s.x): shape = "slice"
		return {power = clampf(1.0 - (took - 0.02) / (FLICK_TIME * 2), 0.3, 1), shape = shape}
	return {}

func _key_swing() -> Dictionary:
	var down := Inputs.key(KEY_SPACE)
	var was: bool = _keys.get("space", false)
	_keys.space = down
	if down and not was:
		var shape := "flat"
		if Inputs.key(KEY_W) or Inputs.key(KEY_UP): shape = "lob"
		elif Inputs.key(KEY_S) or Inputs.key(KEY_DOWN): shape = "slice"
		return {power = 0.65, shape = shape}
	return {}

# ------------------------------------------------------------------ mouse (design coordinates)

static func _now() -> float:
	return Time.get_ticks_usec() / 1e6

## `at` (seconds) is for tests; the real clock otherwise
func pointer_down(p: Vector2, at := -1.0) -> void:
	_mouse_down = true
	_mouse_fired = false
	_mouse = [{p = p, t = _now() if at < 0 else at}]

func pointer_move(p: Vector2, at := -1.0) -> Dictionary:
	if not _mouse_down:
		return {}
	var now := _now() if at < 0 else at
	_mouse.append({p = p, t = now})
	while _mouse.size() > 2 and now - _mouse[0].t > 0.08:
		_mouse.pop_front()
	if _mouse_fired or cool > 0 or _mouse.size() < 2:
		return {}
	var a: Dictionary = _mouse[0]
	var d: Vector2 = p - a.p
	var span: float = maxf(now - a.t, 1.0 / 240)
	var speed := d.length() / span
	if speed < MOUSE_FAST:
		return {}
	_mouse_fired = true
	cool = COOLDOWN
	var shape := "flat"
	if d.y < 0 and absf(d.y) > 1.2 * absf(d.x): shape = "lob"
	elif d.y > 0 and absf(d.y) > 1.2 * absf(d.x): shape = "slice"
	return {power = clampf((speed - MOUSE_FAST * 0.5) / (MOUSE_FULL - MOUSE_FAST * 0.5), 0.2, 1), shape = shape}

## a click without a flick is a plain swing
func pointer_up() -> Dictionary:
	if not _mouse_down:
		return {}
	_mouse_down = false
	if _mouse_fired or cool > 0:
		return {}
	cool = COOLDOWN
	return {power = 0.55, shape = "flat"}
