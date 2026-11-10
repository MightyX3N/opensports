## Bowling, played like Wii Sports bowling: line up with the stick / D-pad / arrow keys,
## hold the throw button with the controller at your chest, swing, let go (or drag the mouse
## down and flick it up). Ten frames, one player. The hall, pins and ball are the real ones
## from the player's Wii Sports disc when it is in rom/, our own otherwise.
class_name BowlingGame
extends Node3D

const START_Z := 2.3       # where the bowler stands on the approach
const RELEASE_Z := 0.45
const ROBOT_SCALE := 1.45 / 2.19
const REACT_AT := 1.4      # seconds of looking at the pins before the bowler reacts
const HIT := {
	ball_drop = ["bowling/ball_drop", 0.9, 1.0], ball_pin = ["bowling/ball_pin", 1.0, 1.0],
	pin_pin = ["bowling/clack", 0.8, 1.0], pin_floor = ["bowling/clack", 0.55, 0.9],
	pin_wall = ["bowling/pin_wall", 0.6, 1.0], pit = ["bowling/pit", 0.75, 1.0], pin_pit = ["bowling/pin_pit", 0.4, 1.0],
}
const CRASH_COVERS := ["ball_pin", "pin_pin", "pin_floor"]
const MAX_HITS_PER_FRAME := 6
const AMBIENCE := 0.3

signal leave(to: String)

var opts := {}
var tun: Dictionary
var rules: BowlingRules
var sim: BowlingSim
var reader: ThrowReader
var ctrl
var x := 0.0
var angle := 0.0
var mode := "move"
var phase := "aim"
var t := 0.0
var bz := START_Z
var walk := 0.0
var msg := ""
var msg_t := 0.0
var toast_text := ""
var toast_t := 0.0
var paused := false
var standing_before := 10
var last_res := {}
var last_throw := {}
var react := ""
var reacting := false
var react_cam := false
var snap := true
var drag = null
var crash = null
var crashed := false
var roll_vol := 0.0
var gutter_vol := 0.0
var arm_a := -PI / 2
var arm_w := 0.0
var hold_w := 0.0
var cam_pos := Vector3(0, 2.35, START_Z + 5.6)
var cam_target := Vector3(0, 0.05, -8)
var cam_fov := 36.0

var alley # DiscAlley or OwnAlley
var real := false
var camera: Camera3D
var pin_nodes := []
var pin_mirrors := []
var pin_shadows := []
var ball_node: Node3D
var ball_mirror: Node3D
var ball_shadow: MeshInstance3D
var bowler: Character
var bowler_shadow: MeshInstance3D
var aim_dots := []
var aim_arrow: MeshInstance3D
var loading := true

func _ready() -> void:
	camera = Camera3D.new()
	camera.near = 0.05
	camera.far = 400
	add_child(camera)
	camera.make_current()
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.82, 0.86, 0.92)
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.environment = e
	add_child(env)
	await _build()
	new_game(opts)
	loading = false

func _build() -> void:
	var d = null
	var t0 := Time.get_ticks_msec()
	if GameData.available():
		d = await DiscAlley.build(get_tree())
		Log.write("bowling: real alley %s in %d ms (texture pack images: %d, upscale %s)" % ["built" if d != null else "failed",
			Time.get_ticks_msec() - t0, TexturePacks.count, Settings.get_value("upscale")])
	if d != null:
		alley = d
		real = true
		RenderingServer.global_shader_parameter_set("os_fog", Vector2(60, 200))
		RenderingServer.global_shader_parameter_set("os_fog_col", Vector3(0.80, 0.74, 0.62))
		RenderingServer.global_shader_parameter_set("os_sky", Vector3(0.66, 0.64, 0.62))
		RenderingServer.global_shader_parameter_set("os_ground", Vector3(0.46, 0.42, 0.38))
		RenderingServer.global_shader_parameter_set("os_sun_col", Vector3(0.42, 0.40, 0.36))
	else:
		alley = OwnAlley.build()
		OwnAlley.apply_light()
	add_child(alley.hall)
	for i in 10:
		var p: Node3D = alley.make_pin()
		add_child(p)
		pin_nodes.append(p)
		if real:
			var r: Node3D = alley.make_pin(0.55)
			add_child(r)
			pin_mirrors.append(r)
		var sh := _shadow()
		pin_shadows.append(sh)
	ball_node = alley.make_ball()
	add_child(ball_node)
	if real:
		ball_mirror = alley.make_ball(0.55)
		add_child(ball_mirror)
	ball_shadow = _shadow()
	bowler = Character.new()
	bowler.scale = Vector3.ONE * ROBOT_SCALE
	add_child(bowler)
	bowler_shadow = _shadow()
	_build_aim()

func _shadow() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = OwnAlley.mesh("shadow")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi

func _build_aim() -> void:
	var dot := CylinderMesh.new()
	dot.top_radius = 1.0
	dot.bottom_radius = 1.0
	dot.height = 0.001
	dot.radial_segments = 16
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1, 1, 1, 0.8)
	m.render_priority = 10 # over the lane's see-through polish
	dot.material = m
	for i in 16:
		var mi := MeshInstance3D.new()
		mi.mesh = dot
		mi.scale = Vector3(0.026, 1, 0.026)
		add_child(mi)
		aim_dots.append(mi)
	var arrow := ArrayMesh.new()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0, 0, -1), Vector3(0.4, 0, 0), Vector3(-0.4, 0, 0)])
	arrow.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var am := m.duplicate()
	am.cull_mode = BaseMaterial3D.CULL_DISABLED
	arrow.surface_set_material(0, am)
	aim_arrow = MeshInstance3D.new()
	aim_arrow.mesh = arrow
	add_child(aim_arrow)

# ------------------------------------------------------------------ game flow

func new_game(o := {}) -> void:
	opts = o
	tun = BowlingTuning.get_profile(o.get("physics", "arcade"))
	rules = BowlingRules.new()
	ctrl = Inputs.current
	x = 0.0; angle = 0.0; mode = "move"
	phase = "aim"; t = 0.0; bz = START_Z; walk = 0.0
	msg = ""; toast_text = ""; toast_t = 0.0; paused = false
	standing_before = 10
	sim = BowlingSim.new(tun)
	reader = ThrowReader.new(ctrl, tun)
	snap = true
	if bowler:
		bowler.play("Idle_A")
	arm_a = -PI / 2; arm_w = 0.0; hold_w = 0.0
	Snd.preload_sounds(["bowling/ball_drop", "bowling/ball_pin", "bowling/crash", "bowling/clack", "bowling/pin_wall",
		"bowling/pit", "bowling/pin_pit", "bowling/crowd_strike", "bowling/crowd_spare", "bowling/jingle_strike",
		"bowling/jingle_spare", "bowling/jingle_gutter", "bowling/jingle_gameover"])

func toast(s: String) -> void:
	toast_text = s
	toast_t = 1.6

func _set_ctrl(c) -> void:
	ctrl = c
	reader = ThrowReader.new(c, tun)

func release_ball(ev: Dictionary) -> void:
	var speed: float = tun.min_speed + (tun.max_speed - tun.min_speed) * ev.power
	var hand := x + 0.14 # right hand
	var a: float = angle + ev.get("aim", 0.0)
	standing_before = sim.standing_count()
	sim.throw({x = clampf(hand, -BowlingSetup.HALF_WIDTH + 0.12, BowlingSetup.HALF_WIDTH - 0.12), angle = a, speed = speed,
		hook = ev.get("hook", 0.0) * tun.max_hook})
	phase = "rolling"
	t = 0.0
	crash = null
	crashed = false
	last_throw = {speed = speed, hook = ev.get("hook", 0.0), aim = ev.get("aim", 0.0)}
	if ctrl and ctrl.has_method("rumble"):
		ctrl.rumble(0.15, 0.6)

func _after_turn() -> void:
	var now := sim.standing_count()
	var down := standing_before - now
	var res := rules.record(down)
	_result_sound(res, down)
	last_res = res
	if res.strike: msg = "Strike!"
	elif res.spare: msg = "Spare!"
	elif sim.gutter != 0 and down == 0: msg = "Gutter"
	elif down == 0: msg = "Miss"
	else: msg = "1 pin" if down == 1 else "%d pins" % down
	msg_t = 0.0
	phase = "result"
	t = 0.0
	react = "Cheering" if (res.strike or res.spare) else ("Hit_B" if down == 0 else "")
	reacting = false

func _next_ball() -> void:
	if last_res.game_over:
		phase = "over"
		t = 0.0
		Snd.play("bowling/jingle_gameover", 0.7)
		return
	if last_res.rerack:
		sim.rack()
	else:
		sim.sweep()
	sim.remove_ball()
	phase = "aim"; t = 0.0; bz = START_Z; walk = 0.0
	react = ""; reacting = false
	reader.reset()
	snap = true

# ------------------------------------------------------------------ sound

func _crash_level(n: int) -> float:
	if n >= 8:
		return 1.0
	return 0.15 + 0.85 * pow(maxf(0, (n - 1) / 7.0), 1.2)

func _moving_pins() -> int:
	var n := 0
	for p in sim.pins:
		if not p.gone and (p.body.awake or not sim.is_standing(p)):
			n += 1
	return n

func _play_hits(dt: float) -> void:
	var ev := sim.take_events()
	if crash != null:
		var age: float = sim.t - crash.t
		if age < 0.5:
			crash.target = _crash_level(_moving_pins())
		crash.level += (crash.target - crash.level) * minf(1, dt * 10)
		Snd.set_volume(crash.src, crash.vol * crash.level)
		if age > 1.6:
			crash = null
	if ev.is_empty():
		return
	ev.sort_custom(func(a, b): return a.level * HIT[a.kind][1] > b.level * HIT[b.kind][1])
	var played := 0
	for e in ev:
		if played >= MAX_HITS_PER_FRAME:
			break
		var pos: Vector3 = e.pos
		pos.y = maxf(0.05, pos.y)
		var lv: float = pow(e.level, 0.8)
		if e.kind == "ball_pin" and not crashed:
			crashed = true
			var vol := 0.55 + 0.45 * lv
			var level := maxf(0.6, _crash_level(_moving_pins()))
			var src = Snd.play("bowling/crash", vol * level, 0.96 + randf() * 0.08, Vector3(pos.x, 0.3, pos.z), {dry = true, near = 9.0})
			crash = {src = src, t = sim.t, vol = vol, level = level, target = level}
			played += 1
		elif not (crash != null and crash.level > 0.5 and e.kind in CRASH_COVERS):
			var h: Array = HIT[e.kind]
			var vol: float = h[1] * (0.15 + 0.85 * lv)
			if crash != null and crash.level > 0.5:
				vol *= 0.6
			var pitch: float = h[2] * (0.95 + 0.06 * lv) * (0.95 + randf() * 0.1)
			Snd.play(h[0], vol, pitch, pos)
			played += 1

func _rolling_sound(dt: float) -> void:
	var what := ""
	var speed := 0.0
	if phase == "rolling" and not paused:
		var bs := sim.ball_sound()
		what = bs[0]
		speed = bs[1]
	var k := minf(1, speed / 9.0)
	var want_roll := (0.3 + 0.7 * k) if what == "lane" else 0.0
	var want_gutter := (0.3 + 0.7 * k) * 0.85 if what == "gutter" else 0.0
	var a := minf(1, dt * 12)
	roll_vol += (want_roll - roll_vol) * a
	gutter_vol += (want_gutter - gutter_vol) * a
	var pos = null
	if sim.ball != null:
		pos = Vector3(sim.ball.pos.x, 0.1, sim.ball.pos.z)
	Snd.loop("bowling/roll_loop", roll_vol * 0.8, 0.85 + 0.3 * k, pos if pos != null else Vector3(0, 0.1, 0))
	Snd.loop("bowling/roll_gutter_loop", gutter_vol * 0.7, 0.85 + 0.3 * k, pos if pos != null else Vector3(0, 0.1, 0))
	Snd.loop("bowling/ambience_loop", AMBIENCE)
	Snd.set_listener(cam_pos, cam_target)

func _result_sound(res: Dictionary, down: int) -> void:
	if res.strike:
		Snd.play("bowling/jingle_strike", 0.7)
		Snd.play("bowling/crowd_strike", 0.6)
	elif res.spare:
		Snd.play("bowling/jingle_spare", 0.65)
		Snd.play("bowling/crowd_spare", 0.5)
	elif down == 0 and sim.gutter != 0:
		Snd.play("bowling/jingle_gutter", 0.55)

func silence() -> void:
	roll_vol = 0.0
	gutter_vol = 0.0
	Snd.loop("bowling/roll_loop", 0)
	Snd.loop("bowling/roll_gutter_loop", 0)
	Snd.loop("bowling/ambience_loop", 0)

# ------------------------------------------------------------------ update

func _move_input(dt: float) -> void:
	var dir := 0.0
	if ctrl.buttons.get("left", false) or Inputs.key(KEY_LEFT) or Inputs.key(KEY_A): dir -= 1
	if ctrl.buttons.get("right", false) or Inputs.key(KEY_RIGHT) or Inputs.key(KEY_D): dir += 1
	if dir == 0 and absf(ctrl.stick.x) > 0.25 and reader.phase == "idle":
		dir = ctrl.stick.x
	if mode == "move":
		x = clampf(x + dir * tun.move_speed * dt, -tun.move_range, tun.move_range)
	else:
		angle = clampf(angle - dir * tun.turn_speed * dt, -tun.turn_range, tun.turn_range)

func _process(dt: float) -> void:
	if loading or sim == null:
		return
	dt = minf(dt, 0.05)
	if ctrl != Inputs.current and phase == "aim":
		_set_ctrl(Inputs.current)
		if ctrl.kind != "mouse":
			toast("Playing with " + ctrl.name)
	t += dt
	if toast_t > 0: toast_t -= dt
	if msg != "": msg_t += dt
	_rolling_sound(dt)
	if not paused:
		if ctrl.pressed.get("plus", false):
			open_pause()
		elif phase == "aim":
			if ctrl.pressed.get("sclick", false) or ctrl.pressed.get("a", false):
				mode = "turn" if mode == "move" else "move"
				Snd.ui("toggle")
			if reader.phase == "idle" or reader.phase == "ready":
				_move_input(dt)
			var ev := reader.update()
			if not ev.is_empty():
				match ev.type:
					"swing": walk = 0.001
					"throw": release_ball(ev)
					"cancel":
						if ev.reason == "weak": toast("Swing a little harder")
			if walk > 0 and phase == "aim":
				walk = minf(1, walk + dt / 0.8)
			bz = START_Z - (START_Z - RELEASE_Z) * (walk * walk * (3 - 2 * walk))
		elif phase == "rolling":
			if bz > RELEASE_Z:
				bz = maxf(RELEASE_Z, bz - dt * 3)
			var done := sim.update(dt)
			_play_hits(dt)
			if done:
				_after_turn()
		elif phase == "result":
			var length := (REACT_AT + (1.9 if react == "Cheering" else 1.5)) if react != "" else 2.0
			if t > length:
				msg = ""
				_next_ball()
	_bowler_update(dt)
	_camera(dt)
	_place()

func _camera(dt: float) -> void:
	var tp: Vector3
	var tt: Vector3
	var fov := 38.0
	var reacting_now := phase == "result" and react != "" and t >= REACT_AT
	if phase == "aim":
		tp = Vector3(x * 0.5, 2.35, START_Z + 5.6); tt = Vector3(x * 0.2, 0.05, -8); fov = 36
	elif reacting_now:
		if not react_cam:
			react_cam = true
			snap = true
		tp = Vector3(x - 0.9, 1.25, bz - 4.6); tt = Vector3(x, 1.12, bz); fov = 34
	elif phase == "rolling" and sim.ball != null:
		var b := sim.ball.pos
		var z := maxf(b.z, -14.6)
		tp = Vector3(b.x * 0.5, 1.15 - 0.3 * minf(1, -z / 14.6), z + 3.4)
		tt = Vector3(b.x * 0.3, 0.15, maxf(z - 6, -18.9))
	else:
		tp = Vector3(0, 0.62, -15.2); tt = Vector3(0, 0.16, -18.8)
	if not reacting_now:
		react_cam = false
	var k := minf(1, dt * (6 if phase == "rolling" else 3))
	if snap:
		k = 1.0
		snap = false
	cam_fov += (fov - cam_fov) * k
	cam_pos += (tp - cam_pos) * k
	cam_target += (tt - cam_target) * k
	camera.fov = cam_fov
	camera.look_at_from_position(cam_pos, cam_target)

# ------------------------------------------------------------------ the bowler

## which way the right arm points (model space of the character: forward is +z, the right
## arm is on -x); arm = 0 straight forward, -pi/2 hanging, -pi straight back
static func _arm_dir(a: float) -> Vector3:
	return Vector3(-0.10, sin(a), cos(a)).normalized()

func _bowler_update(dt: float) -> void:
	var want := 0.0
	var a := arm_a
	var hold := 0.0
	if phase == "aim":
		var arm := reader.arm
		var rp := reader.phase
		if ctrl.kind == "mouse" and drag != null:
			var p: Dictionary = drag[-1]
			arm = -PI / 2 - clampf((p.y - drag[0].y) / 200.0, -1.2, 1.4)
			rp = "swing"
		if rp == "swing" or rp == "back" or (rp == "ready" and arm < 0.4):
			want = 1.0
			a = clampf(arm, -PI * 0.95, 0.6)
		elif rp == "wait" or rp == "ready":
			hold = 1.0
	elif phase == "rolling" and t < 0.7:
		want = 1.0
		a = arm_a + (0.45 - arm_a) * minf(1, dt * 8)
	arm_a = a
	arm_w += (want - arm_w) * minf(1, dt * (14 if want > arm_w else 4))
	hold_w += (hold - hold_w) * minf(1, dt * (8 if hold > hold_w else 14))
	if phase == "aim":
		if walk > 0:
			bowler.play("Walking_A", {rate = 1.25, fade = 0.15})
		else:
			bowler.play("Idle_A", {fade = 0.3})
	elif phase == "result" and react != "" and t >= REACT_AT:
		if not reacting:
			reacting = true
			bowler.play(react, {loop = false, restart = true, fade = 0.1})
	elif not reacting:
		bowler.play("Idle_A", {fade = 0.4})
	if hold_w > 0.01:
		for s in [["r", 1.0], ["l", -1.0]]:
			var side: String = s[0]
			var sx: float = s[1]
			bowler.aim("upperarm." + side, "lowerarm." + side, Vector3(0.08 * sx, -0.8, 0.42), hold_w)
			bowler.aim("lowerarm." + side, "wrist." + side, Vector3(0.55 * sx, 0.22, 0.75), hold_w)
			bowler.aim("wrist." + side, "hand." + side, Vector3(0.55 * sx, 0.22, 0.75), hold_w)
	if arm_w > 0.01:
		var d := _arm_dir(arm_a)
		bowler.aim("upperarm.r", "lowerarm.r", d, arm_w)
		bowler.aim("lowerarm.r", "wrist.r", d, arm_w)
		bowler.aim("wrist.r", "hand.r", d, arm_w)
	bowler.position = Vector3(x, 0, bz)
	bowler.rotation = Vector3(0, PI + angle, 0)
	bowler.advance(dt)

# ------------------------------------------------------------------ placing things

func _pin_transform(b: Physics.Body) -> Transform3D:
	var up := b.q * Vector3.UP
	var base := b.pos - up * BowlingSetup.PIN_COM
	return Transform3D(Basis(b.q), base)

func _place() -> void:
	var on_lane := func(p: Vector3) -> bool: return p.y > -0.02 and absf(p.x) < 0.55
	var mirror := Transform3D(Basis.from_scale(Vector3(1, -1, 1)), Vector3.ZERO)
	for i in pin_nodes.size():
		var node: Node3D = pin_nodes[i]
		var sh: MeshInstance3D = pin_shadows[i]
		var p = sim.pins[i] if i < sim.pins.size() else null
		var vis: bool = p != null and not p.gone
		node.visible = vis
		sh.visible = vis and p.body.pos.y > 0
		if real:
			pin_mirrors[i].visible = vis and on_lane.call(p.body.pos)
		if not vis:
			continue
		var tr := _pin_transform(p.body)
		node.transform = tr
		sh.transform = Transform3D(Basis.from_scale(Vector3(0.08, 1, 0.08)), Vector3(p.body.pos.x, 0.001, p.body.pos.z))
		if real:
			pin_mirrors[i].transform = mirror * tr
	var bpos: Vector3
	var bq := Quaternion.IDENTITY
	var show_ball := true
	if sim.ball != null and phase != "aim":
		bpos = sim.ball.pos
		bq = sim.ball.q
	elif phase == "aim":
		bpos = _hand_ball()
	else:
		show_ball = false
	ball_node.visible = show_ball
	ball_shadow.visible = show_ball and bpos.y > -0.02
	if show_ball:
		ball_node.transform = Transform3D(Basis(bq), bpos)
		ball_shadow.transform = Transform3D(Basis.from_scale(Vector3(0.12, 1, 0.12)), Vector3(bpos.x, maxf(0.001, bpos.y - 0.108) + 0.001, bpos.z))
	if real:
		ball_mirror.visible = show_ball and on_lane.call(bpos) and phase != "aim"
		if ball_mirror.visible:
			ball_mirror.transform = mirror * Transform3D(Basis(bq), bpos)
	# the camera flies past the bowler after the throw: don't fly through its head
	bowler.visible = phase == "aim" or (cam_pos - (bowler.position + Vector3(0, 1.0, 0))).length() > 0.9
	bowler_shadow.transform = Transform3D(Basis.from_scale(Vector3(0.34, 1, 0.30)), Vector3(x, 0.002, bz))
	# dotted throw line with an arrow head on the lane, like the original's guide
	var show_aim: bool = phase == "aim" and reader.phase != "swing" and reader.phase != "back" and walk == 0 and Settings.get_value("aim_line")
	var x0 := clampf(x + 0.14, -BowlingSetup.HALF_WIDTH + 0.12, BowlingSetup.HALF_WIDTH - 0.12)
	var dir := Vector3(-sin(angle), 0, -cos(angle))
	var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 1000.0 * 5)
	for i in aim_dots.size():
		var dist := 2.0 + i * 0.6
		var p := Vector3(x0 + dir.x * dist, 0.004, dir.z * dist)
		var dot: MeshInstance3D = aim_dots[i]
		dot.visible = show_aim and absf(p.x) < BowlingSetup.HALF_WIDTH - 0.02
		dot.position = p
		dot.transparency = 1.0 - pulse
	var tip := 2.0 + 16 * 0.6
	aim_arrow.visible = show_aim
	aim_arrow.transform = Transform3D(Basis(Vector3.UP, angle).scaled(Vector3.ONE * 0.28), Vector3(x0 + dir.x * tip, 0.005, dir.z * tip))
	aim_arrow.transparency = 1.0 - 0.85 * pulse

## where the ball sits in the bowler's hand (world space)
func _hand_ball() -> Vector3:
	var w := bowler.joint_world("wrist.r")
	var h := bowler.joint_world("hand.r")
	var d := (h - w).normalized()
	var r: float = tun.ball_radius
	var c := h + d * r * 0.55 + Vector3(0, -r * 0.25, 0) + bowler.global_basis.z.normalized() * r * 0.35
	if hold_w > 0.01:
		var hl := bowler.joint_world("hand.l")
		var both := (h + hl) / 2 + Vector3(0, r * 0.15, 0) + bowler.global_basis.z.normalized() * r * 0.45
		c = c.lerp(both, hold_w)
	return c

# ------------------------------------------------------------------ pause / menus / mouse

func open_pause() -> void:
	paused = true
	Snd.ui("select")

func resume() -> void:
	paused = false

## mouse / touch in design coordinates
func pointer_down(p: Vector2) -> void:
	if phase == "aim" and not paused:
		drag = [{x = p.x, y = p.y, t = Time.get_ticks_msec() / 1000.0}]
		if ctrl != Inputs.mouse:
			Inputs.current = Inputs.mouse
			_set_ctrl(Inputs.mouse)
		walk = 0.001

func pointer_move(p: Vector2) -> void:
	if drag != null:
		drag.append({x = p.x, y = p.y, t = Time.get_ticks_msec() / 1000.0})

func pointer_up() -> void:
	if drag == null:
		return
	var ev := reader.gesture(drag)
	drag = null
	if ev.type == "throw" and phase == "aim":
		release_ball(ev)
	else:
		walk = 0.0
		if phase == "aim":
			toast("Drag down, then flick up quickly")
