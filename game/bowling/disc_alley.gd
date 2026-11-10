## The real bowling alley, pins and ball from the player's own Wii Sports disc (rom/),
## built once into a node tree. Pins and balls are kept as part lists so the game can place
## as many copies as it needs.
class_name DiscAlley
extends RefCounted

const REFLECT := ["roof_mirror_mat", "mirror_mat"]
const BALL_SCALE := 0.108 / 0.11

var hall: Node3D         # the hall: room, pin end, lanes
var pin_parts := []      # parts of one pin (recentred on its base)
var pin_offset := Vector3.ZERO
var ball_parts := []
var error := ""

## run work on a background thread and wait for it without freezing the screen
static func in_thread(tree: SceneTree, work: Callable):
	var th := Thread.new()
	th.start(work)
	while th.is_alive():
		await tree.process_frame
	return th.wait_to_finish()

## build from the disc: reading, decoding and mesh building happen on a background thread,
## upscaling on the GPU (a few frames); null on failure
static func build(tree: SceneTree) -> DiscAlley:
	var d := DiscAlley.new()
	var data: Dictionary = await in_thread(tree, func():
		var files := GameData.archive("bow_common")
		if files.is_empty():
			return {}
		var out := {field = Brres.parse(files["/G3D/bwg_field.brres"]), pins = Brres.parse(files["/G3D/bwg_Pin.brres"]),
			balls = Brres.parse(files["/G3D/bwg_ball.brres"])}
		for k in out:
			for t in out[k].textures.values():
				Brres.decode_texture(t)
		return out)
	if data.is_empty():
		d.error = "no bowling files on the disc"
		return null
	var field: Dictionary = data.field
	var pins: Dictionary = data.pins
	var balls: Dictionary = data.balls
	var all_tex := []
	for arch in [field, pins, balls]:
		all_tex.append_array(arch.textures.values())
	await Upscale.prepare(tree, all_tex)
	var parts: Dictionary = await in_thread(tree, func():
		# the hall is several models; reflection layers first, then the rest in the game's order
		var first := []
		var rest := []
		for name in ["bwg_field", "bwg_field_front", "bwg_field_pin", "lane_alpha"]:
			if field.models.has(name):
				for p in WiiModel.build(field, name):
					if p.mat_name in REFLECT:
						first.append(p)
					else:
						rest.append(p)
		# one pin out of the 10-pin rack, recentred on its base
		var pm_name := "bwg_pin_438_10" if pins.models.has("bwg_pin_438_10") else str(pins.models.keys()[0])
		var pm: Dictionary = pins.models[pm_name]
		var shape: Dictionary = pm.shapes[0]
		var bname := "bwg_ball_blue" if balls.models.has("bwg_ball_blue") else str(balls.models.keys()[0])
		return {hall = first + rest, pin = WiiModel.build(pins, pm_name, {shape = shape.name, local_space = true}),
			pin_offset = recentre(shape), ball = WiiModel.build(balls, bname)})
	d.hall = Node3D.new()
	d.hall.name = "DiscHall"
	WiiModel.instance(parts.hall, d.hall)
	d.pin_parts = parts.pin
	d.pin_offset = parts.pin_offset
	d.ball_parts = parts.ball
	return d

## where a stored shape sits (so a pin taken out of a rack can be put back on its base)
static func recentre(shape: Dictionary) -> Vector3:
	var mn := Vector3(1e9, 1e9, 1e9)
	var mx := Vector3(-1e9, -1e9, -1e9)
	for p: Vector3 in shape.pos:
		mn = mn.min(p * WiiModel.SCALE)
		mx = mx.max(p * WiiModel.SCALE)
	return Vector3(-(mn.x + mx.x) / 2, -mn.y, -(mn.z + mx.z) / 2)

## a node with one pin (its parts), placed by the caller; tint < 1 for reflections
func make_pin(tint := 1.0) -> Node3D:
	return _make(pin_parts, tint, Transform3D(Basis.IDENTITY, pin_offset))

func make_ball(tint := 1.0) -> Node3D:
	return _make(ball_parts, tint, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * BALL_SCALE), Vector3.ZERO))

static var _tinted := {}
func _make(parts: Array, tint: float, inner: Transform3D) -> Node3D:
	var root := Node3D.new()
	var holder := Node3D.new()
	holder.transform = inner
	root.add_child(holder)
	for p in parts:
		var mi := MeshInstance3D.new()
		mi.mesh = p.mesh
		var m: ShaderMaterial = p.material
		if tint < 1.0:
			var key := [m, tint]
			if not _tinted.has(key):
				var dm: ShaderMaterial = m.duplicate()
				dm.set_shader_parameter("uTint", Color(tint, tint * 0.95, tint * 0.87, 1))
				_tinted[key] = dm
			m = _tinted[key]
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mi)
	return root
