## Loads everything the games need while the menus are up, so starting a game is instant:
## the alley from the player's disc (or our own), pins, ball, the bowler and the sounds.
## Shaders are compiled by drawing it all once off screen.
extends Node

signal finished

var alley = null # DiscAlley or OwnAlley
var real := false
var loading := false
var status := ""

func _ready() -> void:
	_auto.call_deferred()

## start right away in the game itself (tests start it when they need it)
func _auto() -> void:
	var cs := get_tree().current_scene
	if cs != null and cs.scene_file_path == "res://main.tscn":
		start()

func start() -> void:
	if loading:
		return
	loading = true
	status = "Loading…"
	var t0 := Time.get_ticks_msec()
	alley = null
	real = false
	if GameData.available():
		status = "Reading your Wii Sports disc…"
		var d = await DiscAlley.build(get_tree())
		if d != null:
			alley = d
			real = true
	if alley == null:
		await DiscAlley.in_thread(get_tree(), func():
			for n in OwnAlley.HALL + ["pin", "ball", "shadow"]:
				OwnAlley.mesh(n))
		alley = OwnAlley.build()
	# the bowler and the sounds
	for f in ["robot.glb"] + Character.ANIMS:
		load(Character.DIR + f)
	Snd.preload_sounds(["bowling/ball_drop", "bowling/ball_pin", "bowling/crash", "bowling/clack", "bowling/pin_wall",
		"bowling/pit", "bowling/pin_pit", "bowling/crowd_strike", "bowling/crowd_spare", "bowling/jingle_strike",
		"bowling/jingle_spare", "bowling/jingle_gutter", "bowling/jingle_gameover", "bowling/roll_loop",
		"bowling/roll_gutter_loop", "bowling/ambience_loop"])
	await _warm_up()
	Log.write("preload: %s alley ready in %d ms (texture pack images: %d, upscale %s)" % ["real" if real else "own",
		Time.get_ticks_msec() - t0, TexturePacks.count, Settings.get_value("upscale")])
	status = "Wii Sports disc ready" if real else ""
	loading = false
	finished.emit()

## draw everything once in a small hidden view so every shader is compiled now
func _warm_up() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(64, 36)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var cam := Camera3D.new()
	vp.add_child(cam)
	cam.look_at_from_position(Vector3(0, 2.35, 7.9), Vector3(0, 0.05, -8))
	vp.add_child(alley.hall)
	var extra := [alley.make_pin(), alley.make_ball(), Character.new()]
	if real:
		extra.append(alley.make_pin(0.55))
		extra.append(alley.make_ball(0.55))
	var sh := MeshInstance3D.new()
	sh.mesh = OwnAlley.mesh("shadow")
	extra.append(sh)
	for i in extra.size():
		extra[i].position = Vector3(0, 0, 2.0 - i * 0.5)
		vp.add_child(extra[i])
	for i in 3:
		await RenderingServer.frame_post_draw
	vp.remove_child(alley.hall)
	vp.queue_free()

## the disc, packs or upscaling changed: load again
func restart() -> void:
	if loading:
		await finished
	if alley != null and alley.hall != null and alley.hall.get_parent() == null:
		alley.hall.free()
	alley = null
	start()
