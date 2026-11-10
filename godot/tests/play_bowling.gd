## Plays bowling end to end through the real main scene and saves screenshots:
##   OPENSPORTS_HOME=<folder with rom/> OUT=<dir> godot --path godot --rendering-driver opengl3 res://tests/play_bowling.tscn
## Goes through the menus with the keyboard-style navigation, bowls a whole game with mouse
## flicks, opens the pause menu and the settings pages.
extends Node

var out := "/tmp"
var main: Node
var fails := 0
var log_lines := PackedStringArray()

func L(s: String) -> void:
	print(s)
	log_lines.append(s)

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

func wait(s: float) -> void:
	await get_tree().create_timer(s).timeout

func nav(k: String) -> void:
	Inputs._nav[k] = true
	await get_tree().process_frame
	await get_tree().process_frame

func flick(dx := 0.0) -> void:
	var g: BowlingGame = main.game
	var t := 0.0
	var y := 330.0
	var x := 640.0
	g.drag = [{x = x, y = y, t = t}]
	for i in 12:
		t += 1 / 60.0; y += 14
		g.drag.append({x = x, y = y, t = t})
	for i in 6:
		t += 1 / 60.0; y -= 60; x += dx
		g.drag.append({x = x, y = y, t = t})
	g.pointer_up()

func _ready() -> void:
	var o := OS.get_environment("OUT")
	if o != "":
		out = o
	main = load("res://main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await get_tree().process_frame
	L("disc: " + GameData.status)
	# everything loads while the title screen is up
	var tp := Time.get_ticks_msec()
	Preload.start()
	await shot("01a_title_loading")
	while Preload.loading:
		await get_tree().process_frame
	L("  preloaded in %d ms (real look: %s)" % [Time.get_ticks_msec() - tp, str(Preload.real)])
	await shot("01_title")
	await nav("a")
	check(main.screen == "sports", "title -> sport select")
	await shot("02_sports")
	await nav("a")
	check(main.screen == "modes", "bowling -> mode select")
	await shot("03_modes")
	main.start_bowling({physics = "arcade"})
	var g: BowlingGame = main.game
	var t0 := Time.get_ticks_msec()
	while g.loading and Time.get_ticks_msec() - t0 < 60000:
		await get_tree().process_frame
	L("  alley ready in %d ms (real look: %s)" % [Time.get_ticks_msec() - t0, str(g.real)])
	check(not g.loading, "alley loaded")
	check(Time.get_ticks_msec() - t0 < 1500, "the game starts straight away (everything was preloaded)")
	await wait(0.5)
	await shot("04_aim")
	var frames := 0
	var balls := 0
	while g.phase != "over" and balls < 25:
		while g.phase != "aim":
			await get_tree().process_frame
		await wait(0.2)
		flick(randf_range(-3, 3))
		balls += 1
		check(g.phase == "rolling", "ball %d thrown" % balls)
		if balls == 1:
			await wait(0.6)
			await shot("05_rolling")
		var tt := Time.get_ticks_msec()
		while g.phase == "rolling" and Time.get_ticks_msec() - tt < 40000:
			await get_tree().process_frame
		if balls == 1:
			await wait(0.3)
			await shot("06_result")
		L("  ball %d: %s (frame %d, total %d)" % [balls, g.msg, g.rules.frame, g.rules.total()])
		if balls == 3:
			await nav("b")
			check(g.paused, "pause menu opens")
			await shot("07_pause")
			await nav("b")
			check(not g.paused, "pause menu closes")
		while g.phase == "result":
			await get_tree().process_frame
	check(g.phase == "over", "the game reaches game over (%d balls)" % balls)
	await wait(0.4)
	await shot("08_over")
	main.root("sports")
	await main.get_tree().process_frame
	main.go("settings")
	await shot("09_settings")
	main.go("wiidisc")
	await shot("10_wiidisc")
	L("done, %d failure(s)" % fails)
	var f := FileAccess.open(out.path_join("log.txt"), FileAccess.WRITE)
	f.store_string("\n".join(log_lines))
	f.close()
	get_tree().quit(1 if fails > 0 else 0)
