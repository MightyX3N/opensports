## Renders the disc alley from a few viewpoints and saves screenshots:
##   OPENSPORTS_HOME=<folder with rom/> OUT=<dir> godot --path godot res://tests/view_alley.tscn
extends Node3D

func _ready() -> void:
	var out := OS.get_environment("OUT")
	if out == "":
		out = "/tmp"
	print("disc: ", GameData.status)
	Settings.set_value("texture_pack", OS.get_environment("PACK") == "1")
	Settings.set_value("upscale", OS.get_environment("UPSCALE") if OS.get_environment("UPSCALE") != "" else "off")
	print("texture pack images: ", TexturePacks.index().size(), " (pack ", Settings.get_value("texture_pack"), ", upscale ", Settings.get_value("upscale"), ")")
	var t0 := Time.get_ticks_msec()
	var d: DiscAlley = await DiscAlley.build(get_tree())
	if d == null:
		print("no alley")
		get_tree().quit(1)
		return
	print("built in %d ms" % (Time.get_ticks_msec() - t0))
	add_child(d.hall)
	for i in 10:
		var spot: Vector2 = BowlingSetup.pins()[i]
		var p := d.make_pin()
		p.position = Vector3(spot.x, 0, spot.y)
		add_child(p)
		var r := d.make_pin(0.55)
		r.transform = Transform3D(Basis.from_scale(Vector3(1, -1, 1)), Vector3(spot.x, 0, spot.y))
		add_child(r)
	var ball := d.make_ball()
	ball.position = Vector3(0.1, 0.108, -2.0)
	add_child(ball)
	var cam := Camera3D.new()
	cam.fov = 36
	add_child(cam)
	var views := [[Vector3(0, 2.35, 7.9), Vector3(0, 0.05, -8)], [Vector3(0, 0.62, -15.2), Vector3(0, 0.16, -18.8)],
		[Vector3(-3, 3, 4), Vector3(0, 1, -5)]]
	for i in views.size():
		cam.look_at_from_position(views[i][0], views[i][1])
		cam.make_current()
		for k in 3:
			await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(out.path_join("view_%d.png" % i))
	get_tree().quit(0)
