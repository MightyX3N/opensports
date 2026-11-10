## Reads one bowling throw, the Wii Sports way. Every control level gives the same throw event:
##   { type = "ready" }                    waiting for the swing
##   { type = "swing" }                    backswing started
##   { type = "throw", power, hook, aim }  power 0..1, hook -1..1 (right +), aim rad (left +)
##   { type = "cancel", reason }
## Mouse / touch: a drag down (backswing) then a quick flick up. Stick: hold the throw
## trigger, pull the stick back, push it forward.
class_name ThrowReader
extends RefCounted

const STILL_RATE := 0.9      # rad/s: "holding still"
const STILL_TIME := 0.25     # s of stillness that counts as the ready pose
const BACK_RATE := 1.8       # rad/s backwards that starts the swing
const MIN_FORWARD := 1.6     # rad/s forwards needed for a real throw
## forward arm speed (rad/s at its peak) for the slowest and the fastest ball: measured on
## real Joy-Con 2 swings, a relaxed throw peaks around 7, a normal one 15, a hard one 22
const PEAK_SLOW := 4.0
const FULL_TWIST := 1.3      # rad of wrist twist during the forward swing for full hook
const TWIST_DEAD := 0.30     # rad of twist ignored (nobody swings perfectly straight)

var ctrl
var tun: Dictionary
var phase := "idle"
var arm := -PI / 2
var back_t := 0.0
var last_t := -1.0
var still_t := 0.0
var wait_t := 0.0
var peak := 0.0
var twist := 0.0
var release_yaw := 0.0

func _init(c, tuning: Dictionary) -> void:
	ctrl = c
	tun = tuning

func reset() -> void:
	phase = "idle"

func _throw_event(power: float, hook: float, aim: float) -> Dictionary:
	phase = "idle"
	return {type = "throw", power = clampf(power, 0, 1), hook = clampf(hook, -1, 1), aim = aim}

## stick: hold the throw trigger, pull the stick back, push it forward. How fast it goes
## from back to front is the power; sideways at release is the spin.
func update_stick() -> Dictionary:
	var c = ctrl
	var x: float = c.stick.x
	var y: float = c.stick.y
	if not c.buttons.get("b", false):
		var was := phase
		phase = "idle"
		if was == "back":
			return {type = "cancel", reason = "noswing"}
		return {}
	if phase == "idle":
		phase = "ready"
		arm = 1.2
		return {type = "ready"}
	if phase == "ready":
		arm = 1.2
		if y < -0.6:
			phase = "back"
			back_t = c.t
			return {type = "swing"}
		return {}
	if phase == "back":
		arm = -PI / 2 - 0.6 * (-y)
		if y > 0.6:
			var dt := maxf(0.04, c.t - back_t)
			var power := clampf((0.45 - dt) / 0.35, 0, 1)
			var ev := _throw_event(power, x, 0)
			phase = "done"
			return ev
	return {}

## touch / mouse: a drag down (backswing) then a quick flick up releases the ball.
## points = list of { x, y, t } in design pixels. Sideways movement in the flick = spin.
func gesture(points: Array) -> Dictionary:
	if points.size() < 3:
		return {type = "cancel", reason = "noswing"}
	var last: Dictionary = points[-1]
	var i := points.size() - 1
	while i > 0 and last.t - points[i].t < 0.09:
		i -= 1
	var first: Dictionary = points[i]
	var dt := maxf(1e-3, last.t - first.t)
	var vy: float = (first.y - last.y) / dt # upwards px/s
	var vx: float = (last.x - first.x) / dt
	var lowest: float = points[0].y
	for p in points:
		lowest = maxf(lowest, p.y)
	if vy < 250 or lowest - last.y < 40:
		return {type = "cancel", reason = "noswing"}
	var power := clampf((vy - 250) / 2200.0, 0, 1)
	var hook := clampf(vx / maxf(vy, 1) * 2.2, -1, 1)
	if absf(hook) < 0.12:
		hook = 0.0
	phase = "idle"
	return {type = "throw", power = sqrt(power), hook = hook, aim = 0.0}

## how hard the arm must come forward for the fastest ball (Settings: swing strength)
static func peak_fast() -> float:
	return {light = 16.0, normal = 22.0, strong = 28.0}.get(Settings.get_value("swing"), 22.0)

## forward/back swing rate in world space: rotation about the player's left-right axis.
## Positive = the hand moving forward (tip of the controller turning up).
static func _pitch_rate(orient: Quaternion, gyro: Vector3) -> float:
	return (orient * gyro).x

## which way the player faces, from a controller held in any pose: pointing roughly level
## it is the pointing axis; held upright at the chest (the ready pose) or hanging down, the
## button face tells the heading instead
static func heading_yaw(q: Quaternion) -> float:
	var f := q * Vector3(0, 0, -1)
	var h := f
	if f.y > 0.7:
		h = q * Vector3(0, -1, 0)
	elif f.y < -0.7:
		h = q * Vector3(0, 1, 0)
	return atan2(-h.x, -h.z)

## full motion: reads every new sample, so a 33 Hz controller loses nothing between frames
func update_motion() -> Dictionary:
	var c = ctrl
	var held: bool = c.buttons.get("b", false)
	var samples := []
	for h in c.history:
		if h.t > last_t:
			samples.append(h)
	var prev_t := last_t
	if samples.size() > 0:
		last_t = samples[-1].t
	var sdt := func(i: int) -> float:
		var p: float = samples[i - 1].t if i > 0 else prev_t
		var d: float = samples[i].t - p
		if p < 0 or d <= 0 or d > 0.1:
			return 1.0 / 60.0
		return d
	# arm angle for the bowler on screen: 0 = forward, -90 deg = hanging, -150 deg = behind
	var f: Vector3 = c.orient * Vector3(0, 0, -1)
	arm = atan2(f.y, -f.z)
	if phase == "idle":
		if c.pressed.get("b", false) or held:
			phase = "wait"
			still_t = 0.0
			wait_t = 0.0
		return {}
	if phase == "wait":
		if not held:
			phase = "idle"
			return {type = "cancel", reason = "early"}
		for i in samples.size():
			var h: Dictionary = samples[i]
			var dt: float = sdt.call(i)
			wait_t += dt
			if h.gyro.length() < STILL_RATE:
				still_t += dt
			else:
				still_t = 0.0
			if still_t >= STILL_TIME:
				c.recentre(heading_yaw(c.raw))
				phase = "ready"
				return {type = "ready"}
			# already swinging without pausing: go anyway, the last recentre stays
			if _pitch_rate(h.orient, h.gyro) < -BACK_RATE * 1.5 and wait_t > 0.15:
				phase = "swing"
				peak = 0.0
				twist = 0.0
				return {type = "swing"}
		return {}
	var ev := {}
	for i in samples.size():
		var h: Dictionary = samples[i]
		var dt: float = sdt.call(i)
		var pr := _pitch_rate(h.orient, h.gyro)
		if phase == "ready" and (pr < -BACK_RATE or pr > BACK_RATE * 1.5):
			phase = "swing"
			peak = 0.0
			twist = 0.0
			ev = {type = "swing"}
		if phase == "swing":
			peak = maxf(peak, pr)
			if pr > 1.0:
				# twist about the pointing axis while the arm comes forward = spin
				twist += -h.gyro.z * dt
			release_yaw = Inputs.angles(h.orient).x
	if not held:
		if phase == "swing" and peak >= MIN_FORWARD:
			var power := clampf((peak - PEAK_SLOW) / (peak_fast() - PEAK_SLOW), 0, 1)
			var hook := 0.0
			if absf(twist) > TWIST_DEAD:
				hook = (twist - (TWIST_DEAD if twist > 0 else -TWIST_DEAD)) / (FULL_TWIST - TWIST_DEAD)
			var aim := clampf(release_yaw * tun.aim_from_swing, -tun.max_swing_aim, tun.max_swing_aim)
			var out := _throw_event(power, hook, aim)
			out.info = {peak = peak, twist = twist, release_yaw = release_yaw}
			return out
		var was := phase
		phase = "idle"
		return {type = "cancel", reason = "weak" if was == "swing" else "noswing"}
	return ev

func update() -> Dictionary:
	if ctrl.level == Inputs.FULL or ctrl.level == Inputs.GYRO_POINTER:
		return update_motion()
	if ctrl.level == Inputs.STICK_POINTER:
		return update_stick()
	return {}
