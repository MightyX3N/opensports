## Tennis ball flight: gravity, air drag, Magnus lift from spin, bounces on grass that grip
## and turn spin into speed, and the net.
##  drag   F = 1/2 rho Cd A v^2 (Cd 0.55 for a fuzzy ball)
##  Magnus F = 1/2 rho Cl A v^2 (w^ x v^), Cl = 1 / (2 + v / (r w)) (Cross & Lindsey's fit)
##  bounce: restitution e; friction at the contact point up to mu * normal impulse (hollow sphere)
class_name TennisBall
extends RefCounted

const R := 0.0335
const MASS := 0.057
const RHO := 1.21
const AREA := PI * R * R
const KD := 0.5 * RHO * 0.55 * AREA / MASS
const KL := 0.5 * RHO * AREA / MASS
const G := 9.81
const E_GRASS := 0.72
const MU_GRASS := 0.6
const SPIN_DECAY := 0.03

var p := Vector3.ZERO
var v := Vector3.ZERO
var w := Vector3.ZERO
var t := 0.0

static func make(pos: Vector3, vel := Vector3.ZERO, spin := Vector3.ZERO) -> TennisBall:
	var b := TennisBall.new()
	b.p = pos; b.v = vel; b.w = spin
	return b

func copy() -> TennisBall:
	var b := TennisBall.new()
	b.p = p; b.v = v; b.w = w; b.t = t
	return b

## spin for a ball travelling along horizontal direction d: top > 0 topspin, < 0 backspin;
## side > 0 curves to the right of travel
static func spin_for(d: Vector3, top: float, side := 0.0) -> Vector3:
	var l := sqrt(d.x * d.x + d.z * d.z)
	if l < 1e-9:
		return Vector3.ZERO
	var dx := d.x / l
	var dz := d.z / l
	return Vector3(dz * top, -side, -dx * top)

func _accel() -> Vector3:
	var s := v.length()
	var a := Vector3(-KD * s * v.x, -G - KD * s * v.y, -KD * s * v.z)
	var wl := w.length()
	if wl > 1e-6 and s > 1e-3:
		var cl := 1.0 / (2.0 + s / (R * wl))
		a += w.cross(v) / wl * (KL * cl * s)
	return a

## bounce off the ground (the ball's bottom touched y = 0)
func bounce(e := E_GRASS, mu := MU_GRASS) -> void:
	var vn := -v.y
	if vn <= 0:
		return
	var jn := (1 + e) * vn
	v.y = e * vn
	var cx := v.x + R * w.z
	var cz := v.z - R * w.x
	var cs := sqrt(cx * cx + cz * cz)
	if cs > 1e-6:
		var jt := minf(mu * jn, cs / 2.5) # 2.5 = 1 + m r^2 / I for a hollow sphere
		var tx := -cx / cs * jt
		var tz := -cz / cs * jt
		v.x += tx
		v.z += tz
		var k := 3.0 / (2 * R * R)
		w.x += (-R * tz) * k
		w.z += (R * tx) * k

## advance by dt (~1/240 s). Returns {} or { kind = "bounce", x, z } / { kind = "net" } / { kind = "cord" }
func step(dt: float) -> Dictionary:
	v += _accel() * dt
	var oz := p.z
	p += v * dt
	w *= 1.0 - SPIN_DECAY * dt
	t += dt
	var ev := {}
	if (oz > 0) != (p.z > 0) and absf(p.x) < TennisCourt.POST_X:
		var h := TennisCourt.net_height(p.x)
		if p.y < h - R * 0.3:
			# into the net: it soaks the ball up and drops it on the hitter's side
			var side := 1.0 if oz > 0 else -1.0
			p.z = side * (R + 0.01)
			v = Vector3(v.x * 0.2, minf(v.y, 0) * 0.3, -v.z * 0.08)
			w = Vector3.ZERO
			ev = {kind = "net"}
		elif p.y < h + R:
			# clips the cord: loses pace, pops up a little, carries on
			v.x *= 0.55
			v.z *= 0.4
			v.y = absf(v.y) * 0.3 + 1.0
			ev = {kind = "cord"}
	if p.y < R:
		p.y = R
		if v.y < -0.4:
			ev = {kind = "bounce", x = p.x, z = p.z}
			bounce()
		else:
			v.y = 0
			var f := maxf(0, 1 - 1.5 * dt)
			v.x *= f
			v.z *= f
	return ev

## predict the flight: samples { t, x, y, z, bounces } every `every` steps until tmax or the
## second bounce
func predict(tmax: float, dt := 1.0 / 240.0, every := 2) -> Array:
	var s := copy()
	var out := []
	var bounces := 0
	var n := 0
	var t0 := t
	while s.t - t0 < tmax:
		var ev := s.step(dt)
		n += 1
		if not ev.is_empty():
			if ev.kind == "bounce": bounces += 1
			if ev.kind == "net": break
			if bounces >= 2: break
		if n % every == 0:
			out.append({t = s.t - t0, x = s.p.x, y = s.p.y, z = s.p.z, bounces = bounces})
	return out
