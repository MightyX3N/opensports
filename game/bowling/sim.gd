## Bowling lane simulation: builds the lane and pins on game/physics.gd and runs one throw.
class_name BowlingSim
extends RefCounted

const DT := 1.0 / 240.0 # 4 steps per 60 Hz frame, like the original
## what made the noise, with the closing speed (m/s) that counts as a full-volume hit
const HIT_REF := {ball_drop = 2.0, ball_pin = 7.0, pin_pin = 4.0, pin_floor = 3.0, pin_wall = 3.0, pit = 5.0, pin_pit = 3.0}
const MIN_HIT := 0.35  # slower than this is resting / rocking, not a hit
const REPEAT := 0.07   # the same two things can't make the same noise again sooner than this
const PLANE_KIND := {lane = "floor", kickback = "wall", pit = "pit", cushion = "pit", pitfront = "pit"}

var tun: Dictionary
var layout: Array
var world: Physics
var pins := [] # { body, spot, n, gone }
var ball: Physics.Body
var state := ""
var acc := 0.0
var t := 0.0
var deck_t = null
var gutter := 0
var gutter_landed := false
var stop_t := 0.0
var events := []
var _last_hit := {}

func _init(tuning: Dictionary, pin_layout = null) -> void:
	tun = tuning
	layout = pin_layout if pin_layout != null else BowlingSetup.pins()
	world = Physics.new(10)
	world.add_plane(Vector3.UP, 0, 1.0, 0.0, "lane", Vector4(-BowlingSetup.KICKBACK, BowlingSetup.KICKBACK, -BowlingSetup.DECK_END, BowlingSetup.APPROACH))
	world.add_plane(Vector3.UP, -BowlingSetup.PIT_DEPTH, 0.6, 0.05, "pit")
	world.add_plane(Vector3.RIGHT, -BowlingSetup.KICKBACK, 0.2, 0.3, "kickback", Vector4(-10, 10, -BowlingSetup.PIT_BACK - 1, -BowlingSetup.KICKBACK_START))
	world.add_plane(Vector3.LEFT, -BowlingSetup.KICKBACK, 0.2, 0.3, "kickback", Vector4(-10, 10, -BowlingSetup.PIT_BACK - 1, -BowlingSetup.KICKBACK_START))
	world.add_plane(Vector3.BACK, -BowlingSetup.PIT_BACK, 0.8, 0.05, "cushion")
	world.add_plane(Vector3.FORWARD, BowlingSetup.DECK_END, 0.4, 0.1, "pitfront", null, -0.005)
	rack()
	world.on_contact = _contact

func _contact(a, b: Physics.Body, _j: float, c: Physics.Contact) -> void:
	var speed := -c.vn0
	if speed < MIN_HIT:
		return
	var kind := ""
	var key := ""
	if a is Physics.StaticPlane:
		var surf: String = PLANE_KIND.get(a.name, "")
		if surf == "":
			return
		if b.kind == "ball":
			if surf == "floor": kind = "ball_drop"
			elif surf == "pit": kind = "pit"
			else: return
		elif surf == "floor": kind = "pin_floor"
		elif surf == "wall": kind = "pin_wall"
		else: kind = "pin_pit"
		key = "%s%d" % [a.name, b.id]
	else:
		kind = "ball_pin" if (a.kind == "ball" or b.kind == "ball") else "pin_pin"
		key = "%d:%d" % [mini(a.id, b.id), maxi(a.id, b.id)]
	if _last_hit.has(key) and t - _last_hit[key] < REPEAT:
		return
	_last_hit[key] = t
	events.append({kind = kind, speed = speed, pos = c.p, t = t, level = minf(1.0, speed / HIT_REF[kind])})

## hand over (and clear) the sound events since the last call
func take_events() -> Array:
	var e := events
	events = []
	return e

## what the ball is doing, for the rolling sound: [what, speed, x] with what in
## "lane", "gutter", "air", "pit" or ""
func ball_sound() -> Array:
	if ball == null or state != "rolling":
		return ["", 0.0, 0.0]
	var speed := Vector2(ball.v.x, ball.v.z).length()
	if ball.pos.z < -BowlingSetup.DECK_END: return ["pit", speed, ball.pos.x]
	if gutter != 0: return ["gutter", speed, ball.pos.x]
	if ball.pos.y > tun.ball_radius + 0.012: return ["air", speed, ball.pos.x]
	return ["lane", speed, ball.pos.x]

static func _pin_inertia(mass: float) -> Vector3:
	var s := mass / 1.53
	return Vector3(0.0194 * s, 0.0019 * s, 0.0194 * s)

## a full rack of standing pins
func rack() -> void:
	for p in pins:
		world.remove_body(p.body)
	pins = []
	var spheres := []
	for sp: Vector4 in BowlingSetup.pin_spheres():
		spheres.append(Vector4(sp.x, sp.y - BowlingSetup.PIN_COM, sp.z, sp.w))
	for i in layout.size():
		var spot: Vector2 = layout[i]
		var b := world.add_body({pos = Vector3(spot.x, BowlingSetup.PIN_COM, spot.y), mass = tun.pin_mass, inertia = _pin_inertia(tun.pin_mass),
			spheres = spheres, mu = tun.pin_mu, e = tun.pin_e, lin_damp = 0.05, ang_damp = 0.4, awake = false, kind = "pin", id = i + 1})
		pins.append({body = b, spot = spot, n = i + 1, gone = false})

## second ball: fallen pins are swept away, standing ones are set straight where they stand
func sweep() -> void:
	for p in pins:
		if not p.gone and not is_standing(p):
			world.remove_body(p.body)
			p.gone = true
		elif not p.gone:
			var b: Physics.Body = p.body
			b.q = Quaternion.IDENTITY
			b.v = Vector3.ZERO
			b.w = Vector3.ZERO
			b.pos.y = BowlingSetup.PIN_COM
			b.awake = false; b.still = 0.0; b.lin_damp = 0.05; b.ang_damp = 0.4

func is_standing(p: Dictionary) -> bool:
	if p.gone:
		return false
	var b: Physics.Body = p.body
	var up := b.q * Vector3.UP
	if up.y < cos(tun.down_tilt): return false
	if b.pos.y < BowlingSetup.PIN_COM - 0.05: return false
	if b.pos.z < -BowlingSetup.DECK_END or absf(b.pos.x) > BowlingSetup.KICKBACK: return false
	return true

func standing_count() -> int:
	var n := 0
	for p in pins:
		if is_standing(p): n += 1
	return n

func standing_mask() -> Array:
	var out := []
	for p in pins:
		out.append(is_standing(p))
	return out

## th = { x, angle (rad, left +), speed (m/s), hook (rad/s, right curve +) }
func throw(th: Dictionary) -> void:
	if ball != null:
		world.remove_body(ball)
	var r: float = tun.ball_radius
	var dir := Vector3(-sin(th.angle), 0, -cos(th.angle))
	var e_pair: float = 2.0 * tun.ball_pin_e - tun.pin_e
	var I: float = 0.4 * tun.ball_mass * r * r
	ball = world.add_body({pos = Vector3(th.x, tun.release_height, 0.35), mass = tun.ball_mass, inertia = Vector3(I, I, I),
		spheres = [Vector4(0, 0, 0, r)], mu = tun.oil_mu * tun.oil_mu, e = e_pair, lin_damp = tun.ball_lin_damp, ang_damp = 0.05,
		v = dir * th.speed, w = dir * th.get("hook", 0.0), kind = "ball"})
	ball.can_sleep = false
	state = "rolling"
	t = 0.0
	deck_t = null
	gutter = 0
	stop_t = 0.0
	gutter_landed = false
	events = []
	_last_hit = {}

func remove_ball() -> void:
	if ball != null:
		world.remove_body(ball)
		ball = null
	state = ""

func step_once() -> void:
	var b := ball
	# oil: low friction on the front of the lane, dry back end
	if b != null and gutter == 0:
		var dist := -b.pos.z
		var mu: float = tun.oil_mu if dist < tun.oil_length else tun.dry_mu
		if dist > tun.oil_length and dist < tun.oil_length + 1:
			mu = tun.oil_mu + (tun.dry_mu - tun.oil_mu) * (dist - tun.oil_length)
		b.mu = mu * mu
	world.step(DT)
	t += DT
	if b == null:
		return
	# gutter: once over the edge the ball runs in the channel past the pins
	if gutter == 0 and b.pos.z < 0 and b.pos.z > -BowlingSetup.LENGTH + 0.2 and absf(b.pos.x) > BowlingSetup.HALF_WIDTH:
		gutter = 1 if b.pos.x > 0 else -1
		b.collide = false
		events.append({kind = "ball_drop", speed = 1.0, pos = b.pos, t = t, level = 0.45})
	if gutter != 0:
		var r: float = tun.ball_radius
		b.pos.x = gutter * (BowlingSetup.HALF_WIDTH + BowlingSetup.GUTTER_WIDTH / 2)
		b.v.x = 0
		if b.pos.z > -BowlingSetup.DECK_END:
			b.pos.y = r - BowlingSetup.GUTTER_DEPTH
			b.v.y = 0
			if b.v.z > -1.5:
				b.v.z = -1.5 # gutter balls never stall in the channel
		else:
			var y := b.pos.y + b.v.y * DT
			if y <= -BowlingSetup.PIT_DEPTH + r and not gutter_landed:
				# the gutter ball doesn't collide with anything, so make its landing noise here
				gutter_landed = true
				events.append({kind = "pit", speed = 3.0, pos = b.pos, t = t, level = 0.6})
			b.pos.y = maxf(-BowlingSetup.PIT_DEPTH + r, y)
			b.v.y -= 9.81 * DT
		b.pos.z = maxf(b.pos.z, -BowlingSetup.PIT_BACK + r)
	if deck_t == null and b.pos.z < -(BowlingSetup.LENGTH - 0.5):
		deck_t = t
	if deck_t != null:
		# the original's settling trick: after a while pins get heavier damping every frame
		if t - deck_t > tun.settle_after:
			for p in pins:
				if not p.gone:
					p.body.lin_damp += tun.settle_ramp * DT
					p.body.ang_damp += tun.settle_ramp * 3 * DT
	if b.v.length() < 0.05:
		stop_t += DT
	else:
		stop_t = 0.0

## advance real time dt; returns true once the turn is over
func update(dt: float) -> bool:
	if state != "rolling":
		return state == "done"
	acc = minf(acc + dt, 0.1)
	while acc >= DT:
		acc -= DT
		step_once()
		if finished():
			state = "done"
			return true
	return false

func finished() -> bool:
	var pins_quiet := true
	for p in pins:
		var pb: Physics.Body = p.body
		if not p.gone and pb.awake and pb.pos.z > -BowlingSetup.DECK_END and pb.pos.y > 0:
			pins_quiet = false
	var ball_done := ball.pos.z < -BowlingSetup.DECK_END or stop_t > 1.0
	if deck_t != null and t - deck_t > tun.max_turn_time: return true
	if ball_done and pins_quiet and (deck_t == null or t - deck_t > 0.6): return true
	if stop_t > 3: return true
	return false

## run a throw to the end without rendering (tests, CPU players)
func run_to_end(max_t := 30.0) -> int:
	while state == "rolling" and t < max_t:
		step_once()
		if finished():
			state = "done"
	return standing_count()
