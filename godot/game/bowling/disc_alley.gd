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

## build from the disc (await: upscaling textures takes a few frames); null on failure
static func build(tree: SceneTree) -> DiscAlley:
	var d := DiscAlley.new()
	var files := GameData.archive("bow_common")
	if files.is_empty():
		d.error = "no bowling files on the disc"
		return null
	var field := Brres.parse(files["/G3D/bwg_field.brres"])
	var pins := Brres.parse(files["/G3D/bwg_Pin.brres"])
	var balls := Brres.parse(files["/G3D/bwg_ball.brres"])
	var all_tex := []
	for arch in [field, pins, balls]:
		all_tex.append_array(arch.textures.values())
	await Upscale.prepare(tree, all_tex)
	d.hall = Node3D.new()
	d.hall.name = "DiscHall"
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
	WiiModel.instance(first + rest, d.hall)
	# one pin out of the 10-pin rack, recentred on its base
	var pm_name := "bwg_pin_438_10" if pins.models.has("bwg_pin_438_10") else str(pins.models.keys()[0])
	var pm: Dictionary = pins.models[pm_name]
	var shape: Dictionary = pm.shapes[0]
	d.pin_parts = WiiModel.build(pins, pm_name, {shape = shape.name, local_space = true})
	d.pin_offset = recentre(shape)
	var bname := "bwg_ball_blue" if balls.models.has("bwg_ball_blue") else str(balls.models.keys()[0])
	d.ball_parts = WiiModel.build(balls, bname)
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
