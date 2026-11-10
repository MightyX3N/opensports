## Small fixed-step rigid-body physics. Bodies are compounds of spheres (the original bowling
## game builds its pins the same way); static geometry is a list of bounded planes. Contacts
## are solved with sequential impulses (normal + Coulomb friction) plus a little positional
## correction. Units: metres, kilograms, seconds. Nothing here knows about any sport.
class_name Physics
extends RefCounted

class StaticPlane:
	var n: Vector3
	var d: float
	var mu: float
	var e: float
	var bounds = null # Vector4(xmin, xmax, zmin, zmax) or null
	var name: String
	var ymax = null

class Body:
	var pos: Vector3
	var q := Quaternion.IDENTITY
	var v := Vector3.ZERO
	var w := Vector3.ZERO      # world-space angular velocity
	var mass: float
	var inv_mass: float
	var inv_i: Vector3
	var spheres: Array         # Vector4(x, y, z, r) in body space (relative to the centre of mass)
	var mu := 0.3
	var e := 0.3
	var lin_damp := 0.0        # fraction of speed lost per second
	var ang_damp := 0.0
	var awake := true
	var still := 0.0
	var collide := true
	var can_sleep := true
	var kind := ""
	var id := 0
	var bound := 0.0
	var world_spheres: Array = [] # this step's sphere centres (Vector3)

class Contact:
	var a: Body                # null for a plane contact
	var b: Body
	var plane: StaticPlane
	var n: Vector3
	var p: Vector3
	var depth: float
	var mu: float
	var e: float
	var ra: Vector3
	var rb: Vector3
	var kn: float
	var t1: Vector3
	var t2: Vector3
	var k1: float
	var k2: float
	var vn0: float
	var bias: float
	var jn := 0.0
	var j1 := 0.0
	var j2 := 0.0

var bodies: Array[Body] = []
var planes: Array[StaticPlane] = []
var gravity := -9.81
var iterations := 8
var slop := 0.002
var beta := 0.2
var sleep_lin := 0.04
var sleep_ang := 0.25
var sleep_time := 0.35
var t := 0.0
var on_contact: Callable # (a: Body or StaticPlane, b: Body, impulse, contact)

func _init(iters := 8) -> void:
	iterations = iters

## plane: normal n (out of the solid), offset d (n.x = d on the surface); bounds limits it
## to a region (xmin, xmax, zmin, zmax); ymax: it only exists below that height
func add_plane(n: Vector3, d: float, mu: float, e: float, name := "", bounds = null, ymax = null) -> StaticPlane:
	var p := StaticPlane.new()
	p.n = n.normalized(); p.d = d; p.mu = mu; p.e = e; p.name = name; p.bounds = bounds; p.ymax = ymax
	planes.append(p)
	return p

func add_body(def: Dictionary) -> Body:
	var b := Body.new()
	b.pos = def.pos
	b.q = def.get("q", Quaternion.IDENTITY)
	b.v = def.get("v", Vector3.ZERO)
	b.w = def.get("w", Vector3.ZERO)
	b.mass = def.mass
	b.inv_mass = 1.0 / def.mass if def.mass > 0 else 0.0
	var I: Vector3 = def.inertia
	b.inv_i = Vector3(1.0 / I.x, 1.0 / I.y, 1.0 / I.z)
	b.spheres = def.spheres
	b.mu = def.get("mu", 0.3)
	b.e = def.get("e", 0.3)
	b.lin_damp = def.get("lin_damp", 0.0)
	b.ang_damp = def.get("ang_damp", 0.0)
	b.awake = def.get("awake", true)
	b.kind = def.get("kind", "")
	b.id = def.get("id", 0)
	var r := 0.0
	for s: Vector4 in b.spheres:
		r = maxf(r, Vector3(s.x, s.y, s.z).length() + s.w)
	b.bound = r
	b.world_spheres.resize(b.spheres.size())
	bodies.append(b)
	return b

func remove_body(b: Body) -> void:
	bodies.erase(b)

static func wake(b: Body) -> void:
	b.awake = true
	b.still = 0.0

# ------------------------------------------------------------------ helpers

## world inverse inertia applied to a world vector: R . I^-1 . R^T . x
static func inv_inertia(b: Body, x: Vector3) -> Vector3:
	if b.inv_mass == 0.0:
		return Vector3.ZERO
	var l := b.q.inverse() * x
	l *= b.inv_i
	return b.q * l

static func _vel_at(b: Body, r: Vector3) -> Vector3:
	if b == null:
		return Vector3.ZERO
	return b.v + b.w.cross(r)

static func _apply(b: Body, r: Vector3, j: Vector3) -> void:
	if b == null or b.inv_mass == 0.0:
		return
	b.v += j * b.inv_mass
	b.w += inv_inertia(b, r.cross(j))

static func _eff_mass(a: Body, b: Body, ra: Vector3, rb: Vector3, n: Vector3) -> float:
	var k := 0.0
	if a != null and a.inv_mass > 0.0:
		k += a.inv_mass + n.dot(inv_inertia(a, ra.cross(n)).cross(ra))
	if b != null and b.inv_mass > 0.0:
		k += b.inv_mass + n.dot(inv_inertia(b, rb.cross(n)).cross(rb))
	return 1.0 / k if k > 0.0 else 0.0

static func _tangents(n: Vector3) -> Array:
	var t1: Vector3
	if absf(n.x) > 0.57:
		t1 = Vector3(n.y, -n.x, 0).normalized()
	else:
		t1 = Vector3(0, n.z, -n.y).normalized()
	return [t1, n.cross(t1)]

static func _in_bounds(p: StaticPlane, c: Vector3) -> bool:
	if p.ymax != null and c.y > p.ymax:
		return false
	if p.bounds == null:
		return true
	var bd: Vector4 = p.bounds
	return c.x >= bd.x and c.x <= bd.y and c.z >= bd.z and c.z <= bd.w

# ------------------------------------------------------------------ contacts

func _sphere_centres(b: Body) -> void:
	for i in b.spheres.size():
		var s: Vector4 = b.spheres[i]
		b.world_spheres[i] = b.pos + b.q * Vector3(s.x, s.y, s.z)

func contacts() -> Array[Contact]:
	var out: Array[Contact] = []
	var nb := bodies.size()
	for b in bodies:
		if b.awake:
			_sphere_centres(b)
	for i in nb:
		var a := bodies[i]
		if a.collide and a.awake:
			# body vs static planes
			for p in planes:
				var dc := p.n.dot(a.pos) - p.d
				if dc < a.bound + 0.01:
					for si in a.spheres.size():
						var c: Vector3 = a.world_spheres[si]
						var r: float = a.spheres[si].w
						var cd := p.n.dot(c) - p.d
						var dist := cd - r
						# only spheres whose centre is on the open side: one already past a bounded
						# plane (down in the pit, under the deck) never gets pulled through it
						if dist < 0.004 and cd > -0.01 and _in_bounds(p, c):
							var ct := Contact.new()
							ct.b = a; ct.plane = p; ct.n = p.n; ct.p = c - p.n * r; ct.depth = -dist
							ct.mu = sqrt(a.mu * p.mu)
							ct.e = maxf(a.e, p.e) * 0.5 + minf(a.e, p.e) * 0.5
							out.append(ct)
		# body vs body
		for k in range(i + 1, nb):
			var b := bodies[k]
			if not (a.collide and b.collide and (a.awake or b.awake)):
				continue
			var rr := a.bound + b.bound
			if (b.pos - a.pos).length_squared() >= rr * rr:
				continue
			if not a.awake: _sphere_centres(a)
			if not b.awake: _sphere_centres(b)
			for sbi in b.spheres.size():
				var cb: Vector3 = b.world_spheres[sbi]
				var rb: float = b.spheres[sbi].w
				for sai in a.spheres.size():
					var ca: Vector3 = a.world_spheres[sai]
					var ra: float = a.spheres[sai].w
					var e := cb - ca
					var r := ra + rb
					var d2 := e.length_squared()
					if d2 < r * r and d2 > 1e-12:
						var d := sqrt(d2)
						var n := e / d # a -> b
						# a sleeping body is woken by anything moving into it
						if not a.awake or not b.awake:
							wake(a); wake(b)
						var ct := Contact.new()
						ct.a = a; ct.b = b; ct.n = n; ct.p = ca + n * ra; ct.depth = r - d
						ct.mu = sqrt(a.mu * b.mu); ct.e = (a.e + b.e) * 0.5
						out.append(ct)
	return out

# ------------------------------------------------------------------ one fixed step

func step(dt: float) -> void:
	t += dt
	for b in bodies:
		if b.awake and b.inv_mass > 0.0:
			b.v.y += gravity * dt
	var cs := contacts()
	for c in cs:
		var a := c.a
		var b := c.b
		c.ra = c.p - a.pos if a != null else Vector3.ZERO
		c.rb = c.p - b.pos
		c.kn = _eff_mass(a, b, c.ra, c.rb, c.n)
		var tt := _tangents(c.n)
		c.t1 = tt[0]; c.t2 = tt[1]
		c.k1 = _eff_mass(a, b, c.ra, c.rb, c.t1)
		c.k2 = _eff_mass(a, b, c.ra, c.rb, c.t2)
		var vn := (_vel_at(b, c.rb) - _vel_at(a, c.ra)).dot(c.n)
		c.vn0 = vn # closing speed before solving (negative = closing): how hard the hit was
		c.bias = 0.0
		if vn < -0.6:
			c.bias = -c.e * vn # bounce only on real impacts, not resting contact
		c.bias += beta * maxf(0.0, c.depth - slop) / dt
	for _it in iterations:
		for c in cs:
			var a := c.a
			var b := c.b
			var vn := (_vel_at(b, c.rb) - _vel_at(a, c.ra)).dot(c.n)
			var jn := maxf(0.0, c.jn + c.kn * (c.bias - vn))
			var dj := jn - c.jn
			c.jn = jn
			var J := c.n * dj
			_apply(b, c.rb, J)
			_apply(a, c.ra, -J)
			# friction
			var lim := c.mu * c.jn
			var rel := _vel_at(b, c.rb) - _vel_at(a, c.ra)
			var j1 := clampf(c.j1 - c.k1 * rel.dot(c.t1), -lim, lim)
			var d1 := j1 - c.j1
			c.j1 = j1
			var j2 := clampf(c.j2 - c.k2 * rel.dot(c.t2), -lim, lim)
			var d2 := j2 - c.j2
			c.j2 = j2
			var F := c.t1 * d1 + c.t2 * d2
			_apply(b, c.rb, F)
			_apply(a, c.ra, -F)
	if on_contact.is_valid():
		for c in cs:
			if c.jn > 0.0:
				on_contact.call(c.a if c.a != null else c.plane, c.b, c.jn, c)
	# integrate
	for b in bodies:
		if b.awake and b.inv_mass > 0.0:
			b.v *= maxf(0.0, 1.0 - b.lin_damp * dt)
			b.w *= maxf(0.0, 1.0 - b.ang_damp * dt)
			b.pos += b.v * dt
			var wl := b.w.length()
			if wl > 1e-9:
				b.q = (Quaternion(b.w / wl, wl * dt) * b.q).normalized()
			# sleeping
			if b.can_sleep and b.v.length() < sleep_lin and wl < sleep_ang:
				b.still += dt
				if b.still > sleep_time:
					b.awake = false
					b.v = Vector3.ZERO
					b.w = Vector3.ZERO
			else:
				b.still = 0.0
