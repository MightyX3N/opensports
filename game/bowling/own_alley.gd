## Open Sports' own bowling hall, pins and ball (built in code by the original Lua version,
## exported to assets/hall by tools/godot/export_hall.lua).
class_name OwnAlley
extends RefCounted

const DIR := "res://assets/hall/"
const HALL := ["room", "lane", "approach", "gutter", "ends", "divs", "masks", "plates", "pinSpots", "ceiling",
	"lights", "walls", "decals", "seating", "screens", "rack", "rackBalls", "walkway", "otherPins", "otherShadows"]

static var _meshes := {}
static var _info := {}
static var _mats := {}

var hall: Node3D

static func _load_info() -> void:
	if _info.is_empty():
		var f := FileAccess.open(DIR + "meshes.json", FileAccess.READ)
		_info = JSON.parse_string(f.get_as_text())

## one mesh of the hall, as an ArrayMesh with its material
static func mesh(name: String) -> ArrayMesh:
	if _meshes.has(name):
		return _meshes[name]
	_load_info()
	var raw := FileAccess.get_file_as_bytes(DIR + name + ".bin")
	var data := raw.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
	var n := data.decode_u32(0)
	var pos := PackedVector3Array(); pos.resize(n)
	var nrm := PackedVector3Array(); nrm.resize(n)
	var uv := PackedVector2Array(); uv.resize(n)
	var col := PackedColorArray(); col.resize(n)
	var f := data.slice(4).to_float32_array()
	for i in n:
		var o := i * 12
		# our triangles wind counter-clockwise, Godot's front faces clockwise: swap two corners
		var j := i
		var k := i % 3
		if k == 1: j = i + 1
		elif k == 2: j = i - 1
		pos[j] = Vector3(f[o], f[o + 1], f[o + 2])
		uv[j] = Vector2(f[o + 3], f[o + 4])
		nrm[j] = Vector3(f[o + 5], f[o + 6], f[o + 7])
		col[j] = Color(f[o + 8], f[o + 9], f[o + 10], f[o + 11])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pos
	arrays[Mesh.ARRAY_NORMAL] = nrm
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_COLOR] = col
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	m.surface_set_material(0, material(name))
	_meshes[name] = m
	return m

static func material(name: String, tint := Color(1, 1, 1, 1)) -> ShaderMaterial:
	var key := name + tint.to_html()
	if _mats.has(key):
		return _mats[key]
	_load_info()
	var o: Dictionary = _info.get(name, {})
	var m := ShaderMaterial.new()
	m.shader = load("res://game/ours_alpha.gdshader") if o.get("alpha", false) else load("res://game/ours.gdshader")
	var tex: String = o.get("tex", "").split(":")[0]
	if tex != "":
		m.set_shader_parameter("tex", load(DIR + tex + ".png"))
	if not o.get("alpha", false):
		m.set_shader_parameter("spec", o.get("spec", 0.15))
		m.set_shader_parameter("shine", o.get("shine", 24.0))
		m.set_shader_parameter("rim", o.get("rim", 0.0))
		m.set_shader_parameter("cull_back", o.get("cull", true))
	m.set_shader_parameter("unlit", 1.0 if o.get("unlit", false) else 0.0)
	m.set_shader_parameter("tint", tint)
	_mats[key] = m
	return m

static func build() -> OwnAlley:
	var a := OwnAlley.new()
	a.hall = Node3D.new()
	a.hall.name = "OwnHall"
	for n in HALL:
		var mi := MeshInstance3D.new()
		mi.name = n
		mi.mesh = mesh(n)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		a.hall.add_child(mi)
	return a

func make_pin(_tint := 1.0) -> Node3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh("pin")
	return mi

func make_ball(_tint := 1.0) -> Node3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh("ball")
	return mi

## the lighting and fog of our own hall
static func apply_light() -> void:
	RenderingServer.global_shader_parameter_set("os_fog", Vector2(40, 140))
	RenderingServer.global_shader_parameter_set("os_fog_col", Vector3(0.86, 0.88, 0.92))
	RenderingServer.global_shader_parameter_set("os_sky", Vector3(0.62, 0.62, 0.64))
	RenderingServer.global_shader_parameter_set("os_ground", Vector3(0.42, 0.40, 0.40))
	RenderingServer.global_shader_parameter_set("os_sun_col", Vector3(0.34, 0.33, 0.31))
	RenderingServer.global_shader_parameter_set("os_sun", Vector3(-0.35, 0.85, 0.45).normalized())
