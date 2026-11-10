## Shot solver: from where the ball is hit, where it should land, how hard and with what
## spin, find the launch velocity by simulating the real flight and searching the angle.
class_name TennisShot

const DT := 1.0 / 120.0

## fly a test ball to its first bounce: [distance along the aim (or null), net clearance
## (null if it never crossed, -1 into the net), time, landing x, landing z]
static func _fly(from: Vector3, dirx: float, dirz: float, speed: float, elev: float, top: float, side: float) -> Array:
	var ch := cos(elev)
	var sh := sin(elev)
	var v := Vector3(dirx * ch * speed, sh * speed, dirz * ch * speed)
	var b := TennisBall.make(from, v, TennisBall.spin_for(v, top, side))
	var clear = null
	for _i in 900:
		var oz := b.p.z
		var ev := b.step(DT)
		if (oz > 0) != (b.p.z > 0) and clear == null:
			clear = b.p.y - TennisCourt.net_height(b.p.x) - TennisBall.R
		if ev.get("kind", "") == "net":
			return [null, -1.0, b.t, 0.0, 0.0]
		if ev.get("kind", "") == "bounce":
			break
	var dx := b.p.x - from.x
	var dz := b.p.z - from.z
	return [dx * dirx + dz * dirz, clear, b.t, b.p.x, b.p.z]

## opts: speed, top (spin rad/s), side, lob (high arc), margin (net clearance, m).
## Returns { v, w, land: Vector2, clear, time, speed } or {} if nothing works.
static func solve(from: Vector3, target: Vector2, opts := {}) -> Dictionary:
	var dx := target.x - from.x
	var dz := target.y - from.z
	var dist := sqrt(dx * dx + dz * dz)
	var dirx := dx / dist
	var dirz := dz / dist
	var top: float = opts.get("top", 0.0)
	var side: float = opts.get("side", 0.0)
	var speed: float = opts.get("speed", 20.0)
	var margin: float = opts.get("margin", 0.15)
	var lob: bool = opts.get("lob", false)
	for _k in 10:
		var lo := deg_to_rad(40.0) if lob else deg_to_rad(-25.0)
		var hi := deg_to_rad(70.0) if lob else deg_to_rad(40.0)
		var d_lo = _fly(from, dirx, dirz, speed, hi if lob else lo, top, side)[0]
		var d_hi = _fly(from, dirx, dirz, speed, lo if lob else hi, top, side)[0]
		if d_hi != null and d_hi < dist:
			speed *= 1.15 # can't reach: hit harder
		elif d_lo != null and d_lo > dist:
			speed *= 0.88 # even the flattest shot goes long
		else:
			var a := lo
			var c := hi
			var el := (a + c) / 2
			for _j in 22:
				el = (a + c) / 2
				var d = _fly(from, dirx, dirz, speed, el, top, side)[0]
				if d == null:
					d = -1.0
				if lob:
					if d < dist: c = el
					else: a = el
				else:
					if d < dist: a = el
					else: c = el
			var f := _fly(from, dirx, dirz, speed, el, top, side)
			if f[0] != null and f[1] != null and f[1] >= margin:
				var ch := cos(el)
				var sh := sin(el)
				var v := Vector3(dirx * ch * speed, sh * speed, dirz * ch * speed)
				return {v = v, w = TennisBall.spin_for(v, top, side), land = Vector2(f[3], f[4]), clear = f[1], time = f[2], speed = speed, elev = el}
			speed *= 0.9 # hits the net at this pace: take some off
	return {}
