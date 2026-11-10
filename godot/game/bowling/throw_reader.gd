## Reads one bowling throw, the Wii Sports way. Every control level gives the same throw event:
##   { type = "ready" }                    waiting for the swing
##   { type = "swing" }                    backswing started
##   { type = "throw", power, hook, aim }  power 0..1, hook -1..1 (right +), aim rad (left +)
##   { type = "cancel", reason }
## Mouse / touch: a drag down (backswing) then a quick flick up. Stick: hold the throw
## trigger, pull the stick back, push it forward.
class_name ThrowReader
extends RefCounted

var ctrl
var tun: Dictionary
var phase := "idle"
var arm := -PI / 2
var back_t := 0.0

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

func update() -> Dictionary:
	if ctrl.level == Inputs.STICK_POINTER:
		return update_stick()
	return {}
