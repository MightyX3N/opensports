## Plays tennis end to end through the real main scene and saves screenshots:
##   OPENSPORTS_HOME=<folder with rom/> OUT=<dir> godot --path godot --rendering-driver opengl3 res://tests/play_tennis.tscn
## Goes to tennis through the menus, plays points in real time with well-timed swings (the
## swing calls, a mouse flick and a stick flick), then plays the rest of the match fast,
## and checks the pause menu, the end of the match and playing again.
extends Node

var out := "/tmp"
var main: Node
var fails := 0
var shots := {}

func L(s: String) -> void:
	print(s)

func check(c: bool, what: String) -> void:
	if c:
		L("  ok   " + what)
	else:
		fails += 1
		L("  FAIL " + what)

func shot(name: String) -> void:
	for i in 3:
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))

func nav(k: String) -> void:
	Inputs._nav[k] = true
	await get_tree().process_frame
	await get_tree().process_frame

## the person's side of the game: toss, serve at the top, swing at each ball
var _swung_for = null
func bot(g: TennisGame, offset := 0.1) -> void:
	var m := g.match_
	if m.state == "serve" and m.serve_team == 1 and not m.moving() and m.state_t > 0.5:
		g.do_swing({power = 0.7, shape = "flat"})
	elif m.state == "toss" and m.serve_team == 1 and m.t >= m.toss_peak_t - 0.01:
		g.do_swing({power = 0.7, shape = "flat"})
	var cin = m.contact_in(1)
	if cin != null and m.plan != _swung_for and cin <= offset:
		_swung_for = m.plan
		g.do_swing({power = 0.65, shape = ["flat", "flat", "slice", "lob"][randi() % 4]})

func _ready() -> void:
	var o := OS.get_environment("OUT")
	if o != "":
		out = o
	main = load("res://main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await get_tree().process_frame
	L("disc: " + GameData.status)
	var tp := Time.get_ticks_msec()
	Preload.start()
	while Preload.loading:
		await get_tree().process_frame
	L("  preloaded in %d ms (real alley: %s, real court: %s)" % [Time.get_ticks_msec() - tp, str(Preload.real), str(Preload.court_real)])
	check(Preload.court != null, "the tennis court was loaded with everything else")
	await nav("a")
	check(main.screen == "sports", "title -> sport select")
	await nav("right")
	await shot("t01_sports")
	await nav("a")
	check(main.screen == "modes" and main.menus.mode_sport == "tennis", "tennis -> its mode select")
	await shot("t02_modes")
	main.start_tennis({games = 1, skill = "normal", seed = 4})
	var g: TennisGame = main.game
	var t0 := Time.get_ticks_msec()
	while g.loading and Time.get_ticks_msec() - t0 < 60000:
		await get_tree().process_frame
	check(not g.loading, "court ready")
	check(Time.get_ticks_msec() - t0 < 1500, "the game starts straight away (%d ms)" % (Time.get_ticks_msec() - t0))
	check(main.screen == "tennis" and main.hud is TennisHud and main.hud.visible, "the tennis HUD is up")
	await shot("t03_start")
	# real time: play until a few points are over, taking pictures along the way
	var m := g.match_
	var hits := 0
	var points := 0
	var took_rally := false
	var took_call := false
	var took_serve := false
	var took_toss := false
	var start := Time.get_ticks_msec()
	var prev := ""
	while points < 3 and Time.get_ticks_msec() - start < 25000:
		bot(g)
		await get_tree().process_frame
		if m.state == "point" and prev != "point":
			points += 1
		prev = m.state
		if m.state == "toss" and not took_toss and m.serve_team == 1:
			took_toss = true
			await shot("t04_toss")
		if m.state == "rally" and not took_rally and m.ball.p.z > 6 and m.last_hit == 2:
			took_rally = true
			await shot("t05_rally")
		if m.state == "point" and not took_call and g.msg != "":
			took_call = true
			await shot("t06_call")
	L("  real-time: %d points in %.1f s, team 1 shots %d" % [points, (Time.get_ticks_msec() - start) / 1000.0, g.stats.hits])
	check(g.stats.hits > 0, "the person's team returns the ball (%d shots)" % g.stats.hits)
	if not took_call:
		# the machine is slow: play on fast to the end of the point, then look
		var guard := 0
		while m.state != "point" and guard < 100000:
			guard += 1
			bot(g)
			m.update(1 / 60.0)
			g._events()
		for i in 3:
			await get_tree().process_frame
		took_call = g.msg != ""
		await shot("t06_call")
	check(took_call, "points are called (%s)" % g.msg)
	# the mouse: a fast flick is a swing
	g.reader.cool = 0
	g.reader.pointer_down(Vector2(600, 500), 0.0)
	var sw := {}
	for i in 6:
		var r := g.reader.pointer_move(Vector2(600 + i * 60, 500 - i * 5), (i + 1) / 60.0)
		if not r.is_empty():
			sw = r
	g.reader.pointer_up()
	check(not sw.is_empty(), "a mouse flick swings (%s)" % str(sw))
	var sw2 := {}
	g.reader.cool = 0
	g.reader.pointer_down(Vector2(600, 500), 0.0)
	for i in 6:
		var r := g.reader.pointer_move(Vector2(600 + i * 3, 500 - i * 70), (i + 1) / 60.0)
		if not r.is_empty():
			sw2 = r
	g.reader.pointer_up()
	check(sw2.get("shape", "") == "lob", "flicking up is a lob")
	# a stick flick
	var pad := Inputs.Ctrl.new()
	pad.kind = "gamepad"
	var rd := SwingReader.new(pad)
	pad.rstick = Vector2.ZERO
	rd.update(1 / 60.0)
	pad.rstick = Vector2(0.95, 0.1)
	var s3 := rd.update(1 / 60.0)
	check(s3.get("shape", "") == "flat", "a sideways stick flick is a drive")
	pad.rstick = Vector2.ZERO
	for i in 30: rd.update(1 / 60.0)
	pad.rstick = Vector2(0.1, -0.95)
	check(rd.update(1 / 60.0).get("shape", "") == "slice", "a downward stick flick is a slice")
	# a motion swing: a fast turn that tips down on the way
	var jc := Inputs.Ctrl.new()
	jc.kind = "joycon2"
	jc.level = Inputs.FULL
	jc.has_gyro = true
	var rm := SwingReader.new(jc)
	var got := {}
	for i in 40:
		var k := sin(clampf(i / 20.0, 0, 1) * PI)
		jc.gyro = Vector3(-6.0 * k, 14.0 * k, 0)
		jc.t += 1 / 100.0
		jc.orient = Quaternion(Vector3.RIGHT, -0.06 * i)
		jc.history.append({t = jc.t, gyro = jc.gyro, orient = jc.orient})
		var r := rm.update(1 / 100.0)
		if not r.is_empty():
			got = r
	check(not got.is_empty() and got.shape == "slice", "a downward motion swing is a slice (%s)" % str(got))
	# pause menu
	Inputs._nav["b"] = true
	await get_tree().process_frame
	await get_tree().process_frame
	check(g.paused, "B pauses")
	await shot("t07_pause")
	await nav("b")
	check(not g.paused, "B again resumes")
	# the rest of the match, fast
	var guard := 0
	while m.state != "over" and guard < 200000:
		guard += 1
		bot(g, randf_range(-0.05, 0.3))
		m.update(1 / 60.0)
		g._events()
	check(m.state == "over", "the match finishes")
	L("  score: games %s, winner team %d" % [str(m.rules.games), m.rules.winner])
	for i in 10:
		await get_tree().process_frame
	check(g.phase == "over", "the game shows the end of the match")
	await shot("t08_over")
	await nav("a")
	check(g.phase == "play" and g.match_.state == "serve", "play again")
	await shot("t09_again")
	# a DSU server on this computer: the game finds it and reads its motion
	var srv := PacketPeerUDP.new()
	check(srv.bind(26799, "127.0.0.1") == OK, "test DSU server listening")
	Settings.set_value("dsu_server", "127.0.0.1:26799")
	var asked := false
	var ts := 0
	var t1 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t1 < 4000 and DSU.slots.is_empty():
		await get_tree().process_frame
		while srv.get_available_packet_count() > 0:
			var q := srv.get_packet()
			asked = asked or (q.slice(0, 4).get_string_from_ascii() == "DSUC" and q.decode_u32(16) == DSU.MSG_PAD)
			srv.set_dest_address(srv.get_packet_ip(), srv.get_packet_port())
		if asked:
			for k in 3:
				ts += 10000
				srv.put_packet(load("res://tests/run_tests.gd").dsu_server_packet(0, ts, Vector3(0, 1, 0), Vector3(0, 0, 0)))
	check(asked, "the game asks the DSU server for pads")
	check(not DSU.slots.is_empty() and Inputs.current.kind == "dsu" and Inputs.current.level == Inputs.FULL, "a DSU controller joins with full motion")
	main.root("sports")
	main.go("controllers")
	await shot("t11_controllers")
	main.go("motion")
	for i in 30:
		ts += 10000
		var turn := Vector3(0, 0, 0) if i < 15 else Vector3(-200, 900, 0)
		srv.put_packet(load("res://tests/run_tests.gd").dsu_server_packet(0, ts, Vector3(0, 1, 0), turn))
		await get_tree().process_frame
	await shot("t12_motion")
	check(main.menus.motion_peak > 5, "the motion check sees the swing (peak %.1f rad/s)" % main.menus.motion_peak)
	main.back()
	main.go("buttons")
	await shot("t13_buttons_dsu")
	Inputs.current = Inputs.mouse
	srv.close()
	Settings.set_value("dsu_server", "127.0.0.1:26760")
	main.root("sports")
	# quit to sport select and back into bowling: the shared hall and court both survive
	main.root("sports")
	await get_tree().process_frame
	check(main.game == null and main.screen == "sports", "quit to sport select")
	main.start_bowling({physics = "arcade"})
	for i in 20:
		await get_tree().process_frame
	check(main.game is BowlingGame and not main.game.loading, "bowling still starts afterwards")
	main.root("sports")
	main.start_tennis({games = 1, skill = "easy"})
	for i in 20:
		await get_tree().process_frame
	check(main.game is TennisGame and not main.game.loading and Preload.court.field.get_parent() == main.game, "tennis starts again with the same court")
	await shot("t10_again2")
	L("%d failed" % fails)
	get_tree().quit(1 if fails > 0 else 0)
