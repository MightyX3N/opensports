## Tennis, played like Wii Sports tennis: doubles, you and a partner (both run by themselves)
## against two computer players. Swing to toss, swing again to serve; in a rally just swing
## when the ball comes: early pulls it across, late pushes it the other way, the swing's
## shape makes topspin, a slice or a lob. The court, ball and rackets are the real ones from
## the player's Wii Sports disc when it is in rom/, our own otherwise.
class_name TennisGame
extends Node3D

const ROBOT_SCALE := 1.65 / 2.19
const TEAM_COLS := [Color(0.25, 0.55, 0.95), Color(0.92, 0.30, 0.28)]
const SKILLS := {easy = 0.25, normal = 0.5, hard = 0.8}

signal leave(to: String)

var opts := {}
var match_: TennisMatch
var reader: SwingReader
var ctrl
var phase := "play"         # play, over
var t := 0.0
var paused := false
var msg := ""
var msg_sub := ""
var msg_t := 0.0
var msg_col := Color.WHITE
var toast_text := ""
var toast_t := 0.0
var loading := true
var swing_flash := 0.0      # a person's swing was taken: brief HUD feedback
var last_swing := ""        # "hit", "miss", "early", "serve", "toss"
var cam_pos := Vector3(0, 5.6, 21.5)
var cam_target := Vector3(0, 0.4, -2.5)
var snap := true
var stats := {hits = 0, winners = 0, aces = 0}

var court # TennisDiscCourt or TennisOwnCourt
var real := false
var camera: Camera3D
var ball_node: Node3D
var ball_spin := Basis.IDENTITY
var ball_shadow: MeshInstance3D
var bodies := []    # per player: { char, racket, shadow, ring, arm (current arm weight), look }

func _ready() -> void:
	camera = Camera3D.new()
	camera.near = 0.1
	camera.far = 500
	add_child(camera)
	camera.make_current()
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.62, 0.78, 0.95)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.72, 0.74, 0.78)
	e.ambient_light_energy = 0.75
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-1.0, 0.6, 0)
	sun.light_energy = 0.9
	add_child(sun)
	await _build()
	new_match(opts)
	loading = false

func _build() -> void:
	# loaded while the menus were up (core/preload.gd)
	if Preload.loading or Preload.court == null:
		if not Preload.loading:
			Preload.start()
		await Preload.finished
	court = Preload.court
	real = Preload.court_real
	if not real:
		TennisOwnCourt.apply_light()
	add_child(court.field)
	ball_node = court.make_ball()
	add_child(ball_node)
	ball_shadow = _shadow()
	for i in 4:
		var ch := Character.new()
		ch.scale = Vector3.ONE * ROBOT_SCALE
		add_child(ch)
		var racket: Node3D = court.make_racket()
		add_child(racket)
		var ring := _ring(TEAM_COLS[0 if i < 2 else 1])
		bodies.append({char = ch, racket = racket, shadow = _shadow(), ring = ring, arm = 0.0, left = 0.0})

## hand the shared court back before this game is freed (it is kept for the next game)
func release_hall() -> void:
	if court != null and court.field != null and court.field.get_parent() == self:
		remove_child(court.field)

func _shadow() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = OwnAlley.mesh("shadow")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi

## a coloured ring on the ground under each player (whose side they're on)
func _ring(col: Color) -> MeshInstance3D:
	var tm := TorusMesh.new()
	tm.inner_radius = 0.36
	tm.outer_radius = 0.44
	tm.rings = 24
	tm.ring_segments = 4
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(col, 0.75)
	m.render_priority = 5
	tm.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = tm
	mi.scale = Vector3(1, 0.05, 1)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi

# ------------------------------------------------------------------ game flow

func new_match(o := {}) -> void:
	opts = o
	var sd = o.get("seed", null)
	var mo := {games = o.get("games", 1), humans = {1: true}, skill = SKILLS.get(o.get("skill", "normal"), 0.5)}
	if sd != null:
		mo.seed = sd
	match_ = TennisMatch.new(mo)
	ctrl = Inputs.current
	reader = SwingReader.new(ctrl)
	phase = "play"
	t = 0.0
	paused = false
	msg = ""
	toast_text = ""
	snap = true
	stats = {hits = 0, winners = 0, aces = 0}
	Snd.preload_sounds(["tennis/hit", "tennis/bounce", "tennis/net", "tennis/swish", "tennis/crowd_point",
		"tennis/crowd_game", "tennis/jingle_game", "tennis/jingle_match", "tennis/jingle_lose", "tennis/ambience_loop"])
	if ctrl.kind == "joycon2":
		ctrl.recentre()

func toast(s: String) -> void:
	toast_text = s
	toast_t = 1.8

func show_msg(s: String, sub := "", col := Color.WHITE) -> void:
	msg = s
	msg_sub = sub
	msg_t = 0.0
	msg_col = col

func _set_ctrl(c) -> void:
	ctrl = c
	reader = SwingReader.new(c)

## the human team's swing (from any input)
func do_swing(sw: Dictionary) -> void:
	if phase != "play" or paused or match_ == null:
		return
	var r := match_.swing(1, sw)
	last_swing = r
	swing_flash = 0.35
	if r == "early":
		toast("Wait for the ball to reach the top of the toss")

# ------------------------------------------------------------------ events: sounds and calls

func _events() -> void:
	for e in match_.take_events():
		match e.kind:
			"hit":
				var pos: Vector3 = e.get("pos", match_.ball.p)
				var k := clampf(e.get("speed", 20.0) / 35.0, 0.2, 1.0)
				Snd.play("tennis/hit", 0.45 + 0.55 * k, 0.92 + 0.16 * k, pos, {dry = true, near = 14.0})
				if e.team == 1:
					stats.hits += 1
					if ctrl != null:
						ctrl.rumble(0.08, 0.5 + 0.4 * k)
			"whiff":
				Snd.play("tennis/swish", 0.5, 1.0, _human_pos(), {dry = true, near = 14.0})
			"bounce":
				var p := Vector3(e.x, 0.05, e.z)
				Snd.play("tennis/bounce", 0.7, 0.95 + randf() * 0.1, p, {dry = true, near = 14.0})
				if not e.inn and match_.state != "point":
					show_msg("Out", "", Color(1, 0.85, 0.3))
			"net":
				Snd.play("tennis/net", 0.8, 1.0, Vector3(match_.ball.p.x, 0.6, 0), {dry = true, near = 14.0})
			"cord":
				Snd.play("tennis/net", 0.5, 1.25, Vector3(match_.ball.p.x, 0.9, 0), {dry = true, near = 14.0})
			"fault":
				show_msg("Double fault" if e.double else "Fault", "", Color(1, 0.85, 0.3))
			"let":
				show_msg("Let", "Serve again")
			"point":
				_on_point(e)

func _on_point(e: Dictionary) -> void:
	var won: bool = e.team == 1
	if e.reason == "winner" and won:
		stats.winners += 1
	if e.match != 0:
		show_msg("Game and match" , "You win!" if won else "The computer wins", TEAM_COLS[0] if won else TEAM_COLS[1])
		Snd.play("tennis/jingle_match" if won else "tennis/jingle_lose", 0.75)
		Snd.play("tennis/crowd_game", 0.7)
	elif e.game != 0:
		var g: Array = match_.rules.games
		show_msg("Game", "%d – %d" % [g[0], g[1]], TEAM_COLS[0] if won else TEAM_COLS[1])
		Snd.play("tennis/jingle_game" if won else "tennis/jingle_lose", 0.6)
		Snd.play("tennis/crowd_game", 0.6)
	else:
		show_msg(e.call, _reason_text(e.reason, won), TEAM_COLS[0] if won else TEAM_COLS[1])
		Snd.play("tennis/crowd_point", 0.45 if won else 0.3)

func _reason_text(r: String, won: bool) -> String:
	match r:
		"winner": return "Winner!" if won else "Point to them"
		"out": return "Their shot was out" if won else "Your shot was out"
		"net": return "Into the net" if not won else "Their shot found the net"
		"double fault": return "Double fault"
	return ""

func _human_pos() -> Vector3:
	var p: Dictionary = match_.player(1, 1)
	return Vector3(p.pos.x, 1.0, p.pos.z)

# ------------------------------------------------------------------ update

func _process(dt: float) -> void:
	if loading or match_ == null:
		return
	dt = minf(dt, 0.05)
	if ctrl != Inputs.current:
		_set_ctrl(Inputs.current)
		if ctrl.kind != "mouse":
			toast("Playing with " + ctrl.name)
	t += dt
	if toast_t > 0: toast_t -= dt
	if msg != "": msg_t += dt
	if msg_t > 2.2: msg = ""
	swing_flash = maxf(0, swing_flash - dt)
	Snd.loop("tennis/ambience_loop", 0.35)
	Snd.set_listener(cam_pos, cam_target)
	if not paused:
		if ctrl.pressed.get("plus", false):
			open_pause()
		elif phase == "play":
			if ctrl.pressed.get("recentre", false) and ctrl.kind == "joycon2":
				ctrl.recentre()
				toast("Controller re-centred")
			var sw := reader.update(dt)
			if not sw.is_empty():
				do_swing(sw)
			# the A button tosses for a serve, like the original
			if ctrl.pressed.get("a", false) and match_.state == "serve" and match_.serve_team == 1:
				match_.toss()
			match_.update(dt)
			_events()
			if match_.state == "over":
				phase = "over"
				t = 0.0
	_players(dt)
	_camera(dt)
	_place(dt)

func _camera(dt: float) -> void:
	var b := match_.ball.p
	var tp := Vector3(clampf(b.x, -4, 4) * 0.25, 5.6, 21.5)
	var tt := Vector3(clampf(b.x, -4, 4) * 0.15, 0.4, -2.5)
	if phase == "over":
		tp = Vector3(0, 9.0, 25.0)
		tt = Vector3(0, 0, -1.0)
	var k := minf(1, dt * 3)
	if snap:
		k = 1.0
		snap = false
	cam_pos += (tp - cam_pos) * k
	cam_target += (tt - cam_target) * k
	camera.fov = 42
	camera.look_at_from_position(cam_pos, cam_target)

# ------------------------------------------------------------------ players

## which way the right arm points in the robot's own space (forward +z, the right arm on -x),
## at angle phi round the body (0 = out to the right side, pi/2 = straight ahead) and height h
static func _arm(phi: float, h: float) -> Vector3:
	return Vector3(-cos(phi), h, sin(phi)).normalized()

## the stroke: k 0 = racket back, 0.4 = contact, 1 = follow-through
static func _stroke(side: String, shape: String, k: float) -> Vector3:
	var phi0 := -1.1 if side == "fore" else 3.8
	var phi1 := 2.5 if side == "fore" else 0.6
	var h0 := -0.1
	var h1 := 0.3
	match shape:
		"lob": h0 = -0.7; h1 = 0.9
		"slice": h0 = 0.6; h1 = -0.35
	var e := k * k * (3 - 2 * k)
	return _arm(lerpf(phi0, phi1, e), lerpf(h0, h1, e))

func _players(dt: float) -> void:
	for i in 4:
		var p: Dictionary = match_.players[i]
		var bd: Dictionary = bodies[i]
		var ch: Character = bd.char
		var facing := PI if p.team == 1 else 0.0
		var speed: float = p.vel.length()
		# animation: run, stand, cheer
		if p.state == "cheer" and match_.state_t > 0.3:
			ch.play("Cheering", {fade = 0.2})
		elif p.state == "sad" and match_.state_t > 0.3:
			ch.play("Idle_B", {fade = 0.3})
		elif speed > 0.8:
			ch.play("Running_A", {fade = 0.15, rate = clampf(speed / 5.0, 0.6, 1.5)})
		else:
			ch.play("Idle_A", {fade = 0.25})
		# a little lean into the run, and turn towards where the ball will be met
		var side_lean := 0.0
		if speed > 0.8:
			var dir := Vector2(p.vel.x, p.vel.y if p.team == 2 else -p.vel.y)
			side_lean = clampf(dir.x / maxf(speed, 1e-3), -1, 1) * 0.5 * (1 if p.team == 1 else -1)
		ch.position = p.pos
		ch.rotation = Vector3(0, facing - side_lean, 0)
		# the swing: the right arm follows the stroke
		var want := 0.0
		var d := Vector3.ZERO
		var st: float = p.state_t
		if p.state == "swing":
			want = 1.0 if st < 0.45 else 0.0
			var k := clampf((st + 0.12) / 0.3, 0, 1)
			if st < -0.12:
				k = 0.0
			d = _stroke(p.swing_side, p.swing_shape, k)
		elif p.state == "toss":
			want = 1.0
			d = Vector3(-0.35, 0.55, -0.75).normalized() # racket back behind the head
		elif p.state == "serve":
			want = 1.0 if st < 0.45 else 0.0
			var k := clampf(st / 0.3, 0, 1)
			d = Vector3(-0.35, 0.9, -0.3).normalized().slerp(Vector3(0.25, -0.45, 0.85).normalized(), k * k * (3 - 2 * k))
		elif match_.state == "rally" and match_.plan != null and match_.plan.player == p:
			# ready position: racket out in front on the side the ball will come
			want = 0.6
			d = _stroke(match_.plan.side, "flat", 0.0).lerp(_arm(PI / 2, -0.2), 0.3).normalized()
		bd.arm += (want - bd.arm) * minf(1, dt * (16 if want > bd.arm else 5))
		if bd.arm > 0.01 and d != Vector3.ZERO:
			bd.last_dir = d
		var ad: Vector3 = bd.get("last_dir", _arm(0.3, -0.6))
		if bd.arm > 0.01:
			ch.aim("upperarm.r", "lowerarm.r", ad, bd.arm)
			ch.aim("lowerarm.r", "wrist.r", ad, bd.arm)
			ch.aim("wrist.r", "hand.r", ad, bd.arm)
		# the tossing arm
		var lw := 1.0 if (p.state == "toss" or (match_.state == "serve" and p == match_.server)) else 0.0
		bd.left += (lw - bd.left) * minf(1, dt * 10)
		if bd.left > 0.01:
			var up := Vector3(0.15, 1.0, 0.25).normalized() if p.state == "toss" else Vector3(0.35, -0.2, 0.8).normalized()
			ch.aim("upperarm.l", "lowerarm.l", up, bd.left)
			ch.aim("lowerarm.l", "wrist.l", up, bd.left)
		ch.advance(dt)

func _place(dt: float) -> void:
	var b := match_.ball
	var show: bool = match_.state != "over"
	ball_node.visible = show
	ball_shadow.visible = show
	ball_spin = (Basis(b.w.normalized(), b.w.length() * dt * 0.5) * ball_spin).orthonormalized() if b.w.length() > 0.1 else ball_spin
	ball_node.transform = Transform3D(ball_spin, b.p)
	var sh := clampf(1.0 - b.p.y / 6.0, 0.3, 1.0)
	ball_shadow.transform = Transform3D(Basis.from_scale(Vector3(0.07, 1, 0.07) * sh), Vector3(b.p.x, 0.006, b.p.z))
	for i in 4:
		var p: Dictionary = match_.players[i]
		var bd: Dictionary = bodies[i]
		var ch: Character = bd.char
		bd.shadow.transform = Transform3D(Basis.from_scale(Vector3(0.36, 1, 0.32)), Vector3(p.pos.x, 0.007, p.pos.z))
		bd.ring.position = Vector3(p.pos.x, 0.01, p.pos.z)
		bd.ring.visible = p.team == 1
		# the racket in the right hand: grip in the palm, the head carrying on along the arm
		var w := ch.joint_world("wrist.r")
		var h := ch.joint_world("hand.r")
		var up := (h - w).normalized()
		var fwd := ch.global_basis.z.normalized()
		var x := up.cross(fwd)
		if x.length_squared() < 1e-6:
			x = ch.global_basis.x.normalized()
		x = x.normalized()
		var z := x.cross(up).normalized()
		bd.racket.transform = Transform3D(Basis(x, up, z), h - up * 0.04)

# ------------------------------------------------------------------ pause / menus / mouse

func open_pause() -> void:
	paused = true
	Snd.ui("select")

func resume() -> void:
	paused = false

func silence() -> void:
	Snd.loop("tennis/ambience_loop", 0)

func pointer_down(p: Vector2) -> void:
	if phase != "play" or paused:
		return
	if ctrl != Inputs.mouse:
		Inputs.current = Inputs.mouse
		_set_ctrl(Inputs.mouse)
	reader.pointer_down(p)

func pointer_move(p: Vector2) -> void:
	var sw := reader.pointer_move(p)
	if not sw.is_empty():
		do_swing(sw)

func pointer_up() -> void:
	var sw := reader.pointer_up()
	if not sw.is_empty():
		do_swing(sw)
