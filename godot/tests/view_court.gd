## Renders the disc tennis court from a few viewpoints and prints mesh bounds:
##   OPENSPORTS_HOME=<folder with rom/> OUT=<dir> godot --path godot res://tests/view_court.tscn
extends Node3D

func _ready() -> void:
	var out := OS.get_environment("OUT")
	if out == "": out = "/tmp"
	var d: TennisDiscCourt = await TennisDiscCourt.build(get_tree())
	if d == null:
		print("no court")
		get_tree().quit(1)
		return
	add_child(d.field)
	for mi in d.field.find_children("*", "MeshInstance3D", true, false):
		var a: AABB = mi.mesh.get_aabb()
		print("mesh ", mi.name, " ", a.position, " .. ", a.end)
	for p in [["ball", d.ball_parts], ["racket", d.racket_parts]]:
		for q in p[1]:
			print(p[0], " ", q.name, " ", q.mesh.get_aabb())
	var b := d.make_ball()
	b.position = Vector3(1, 1, 5)
	add_child(b)
	var cam := Camera3D.new()
	cam.fov = 40
	add_child(cam)
	var views := [[Vector3(0, 6, 22), Vector3(0, 0, 0)], [Vector3(0, 40, 0.1), Vector3(0, 0, 0)], [Vector3(14, 4, 8), Vector3(0, 1, 0)]]
	for i in views.size():
		cam.look_at_from_position(views[i][0], views[i][1])
		cam.make_current()
		for k in 3:
			await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out.path_join("court_%d.png" % i))
	get_tree().quit(0)
