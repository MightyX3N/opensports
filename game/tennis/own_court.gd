## Our own tennis court, for when there's no Wii Sports disc in rom/: grass with mown
## stripes, the lines, the net and posts, a low wall round the run-off and a few stands, all
## built in code with our own lighting (game/ours.gdshader). Same interface as TennisDiscCourt.
class_name TennisOwnCourt
extends RefCounted

const C := preload("res://game/tennis/court.gd")
const FRONT_CW := true # which corner order Godot treats as the front face (checked by rendering)
const GRASS_A := Color(0.36, 0.62, 0.27)
const GRASS_B := Color(0.40, 0.67, 0.30)
const OUT_A := Color(0.30, 0.55, 0.24)
const LINE := Color(0.97, 0.97, 0.94)
const WALL := Color(0.16, 0.42, 0.30)
const SEAT := [Color(0.85, 0.30, 0.28), Color(0.95, 0.80, 0.25), Color(0.30, 0.55, 0.90), Color(0.95, 0.95, 0.95)]

var field: Node3D
var error := ""
static var _mat: ShaderMaterial
static var _ball: ArrayMesh
static var _racket: ArrayMesh

static func material() -> ShaderMaterial:
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = load("res://game/ours.gdshader")
		_mat.set_shader_parameter("spec", 0.08)
		_mat.set_shader_parameter("shine", 16.0)
		_mat.set_shader_parameter("cull_back", false)
	return _mat

## sunny daylight for our own models
static func apply_light() -> void:
	RenderingServer.global_shader_parameter_set("os_fog", Vector2(90, 260))
	RenderingServer.global_shader_parameter_set("os_fog_col", Vector3(0.78, 0.86, 0.95))
	RenderingServer.global_shader_parameter_set("os_sky", Vector3(0.70, 0.74, 0.80))
	RenderingServer.global_shader_parameter_set("os_ground", Vector3(0.45, 0.48, 0.40))
	RenderingServer.global_shader_parameter_set("os_sun_col", Vector3(0.45, 0.43, 0.38))
	RenderingServer.global_shader_parameter_set("os_sun", Vector3(-0.4, 0.8, 0.35).normalized())

# ------------------------------------------------------------------ geometry helpers

## a quad facing `hint` (wound so that side is the front face)
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, hint := Vector3.ZERO) -> void:
	var n := (b - a).cross(d - a)
	if n.length_squared() < 1e-12:
		n = (b - a).cross(c - a)
	n = n.normalized()
	var flip := hint != Vector3.ZERO and n.dot(hint) < 0
	if flip:
		n = -n
	st.set_color(col)
	st.set_normal(n)
	var order := [a, b, c, a, c, d] if flip == FRONT_CW else [a, c, b, a, d, c]
	for p in order:
		st.add_vertex(p)

## a flat rectangle on the ground at height y
static func _flat(st: SurfaceTool, x0: float, z0: float, x1: float, z1: float, y: float, col: Color) -> void:
	_quad(st, Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1), col, Vector3.UP)

static func _box(st: SurfaceTool, mn: Vector3, mx: Vector3, col: Color) -> void:
	var p := [Vector3(mn.x, mn.y, mn.z), Vector3(mx.x, mn.y, mn.z), Vector3(mx.x, mn.y, mx.z), Vector3(mn.x, mn.y, mx.z),
		Vector3(mn.x, mx.y, mn.z), Vector3(mx.x, mx.y, mn.z), Vector3(mx.x, mx.y, mx.z), Vector3(mn.x, mx.y, mx.z)]
	_quad(st, p[4], p[5], p[6], p[7], col, Vector3.UP)
	_quad(st, p[3], p[2], p[6], p[7], col, Vector3.BACK)
	_quad(st, p[1], p[0], p[4], p[5], col, Vector3.FORWARD)
	_quad(st, p[2], p[1], p[5], p[6], col, Vector3.RIGHT)
	_quad(st, p[0], p[3], p[7], p[4], col, Vector3.LEFT)

static func _mesh(st: SurfaceTool) -> ArrayMesh:
	var m := st.commit()
	m.surface_set_material(0, material())
	return m

# ------------------------------------------------------------------ the court

static func build() -> TennisOwnCourt:
	var d := TennisOwnCourt.new()
	d.field = Node3D.new()
	d.field.name = "OwnCourt"
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# run-off and the land around, then the court in mown stripes across its length
	_flat(st, -120, -120, 120, 120, -0.02, Color(0.42, 0.62, 0.32))
	var ox := C.HALF_W + C.RUNOFF_SIDE
	var oz := C.HALF_LEN + C.RUNOFF_BACK
	_flat(st, -ox, -oz, ox, oz, 0.0, OUT_A)
	var stripes := 12
	for i in stripes:
		var z0 := -C.HALF_LEN + i * (2 * C.HALF_LEN / stripes)
		var z1 := z0 + 2 * C.HALF_LEN / stripes
		_flat(st, -C.HALF_W, z0, C.HALF_W, z1, 0.002, GRASS_A if i % 2 == 0 else GRASS_B)
	# lines (all 5 cm, drawn inside the court's measurements)
	var w := C.LINE_W
	var y := 0.004
	for sx in [-1.0, 1.0]:
		_flat(st, sx * C.HALF_W - (w if sx > 0 else 0.0), -C.HALF_LEN, sx * C.HALF_W + (0.0 if sx > 0 else w), C.HALF_LEN, y, LINE)
		_flat(st, sx * C.SINGLES_HALF_W - w / 2, -C.HALF_LEN, sx * C.SINGLES_HALF_W + w / 2, C.HALF_LEN, y, LINE)
	for sz in [-1.0, 1.0]:
		_flat(st, -C.HALF_W, sz * C.HALF_LEN - (w if sz > 0 else 0.0), C.HALF_W, sz * C.HALF_LEN + (0.0 if sz > 0 else w), y, LINE)
		_flat(st, -C.SINGLES_HALF_W, sz * C.SERVICE - w / 2, C.SINGLES_HALF_W, sz * C.SERVICE + w / 2, y, LINE)
		# centre mark on the baseline
		_flat(st, -w / 2, sz * C.HALF_LEN - (0.1 if sz > 0 else 0.0), w / 2, sz * C.HALF_LEN + (0.0 if sz > 0 else 0.1), y, LINE)
	_flat(st, -w / 2, -C.SERVICE, w / 2, C.SERVICE, y, LINE)
	# low wall round the run-off and stands behind it
	var wh := 1.0
	_box(st, Vector3(-ox - 0.3, 0, -oz - 0.3), Vector3(ox + 0.3, wh, -oz), WALL)
	_box(st, Vector3(-ox - 0.3, 0, oz), Vector3(ox + 0.3, wh, oz + 0.3), WALL)
	_box(st, Vector3(-ox - 0.3, 0, -oz), Vector3(-ox, wh, oz), WALL)
	_box(st, Vector3(ox, 0, -oz), Vector3(ox + 0.3, wh, oz), WALL)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for side in [-1.0, 1.0]:
		for row in 6:
			var x0: float = side * (ox + 0.6 + row * 0.9)
			var x1: float = x0 + side * 0.9
			_box(st, Vector3(minf(x0, x1), 0, -oz + 2), Vector3(maxf(x0, x1), wh + 0.4 * row, oz - 2), Color(0.80, 0.82, 0.84))
			# people: little coloured blocks along each row
			var zz := -oz + 2.5
			while zz < oz - 2.5:
				if rng.randf() < 0.7:
					var c: Color = SEAT[rng.randi() % SEAT.size()]
					var cx := (x0 + x1) / 2
					_box(st, Vector3(cx - 0.18, wh + 0.4 * row, zz - 0.18), Vector3(cx + 0.18, wh + 0.4 * row + 0.55, zz + 0.18), c)
				zz += 0.6
	d._add(_mesh(st))
	d._add_net()
	return d

func _add(m: Mesh, mat: Material = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	if mat != null:
		mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	field.add_child(mi)
	return mi

func _add_net() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for sx in [-1.0, 1.0]:
		var x: float = sx * C.POST_X
		_box(st, Vector3(x - 0.05, 0, -0.05), Vector3(x + 0.05, C.NET_POST + 0.04, 0.05), Color(0.20, 0.35, 0.28))
	# the white band along the top, following the sag
	var n := 24
	for i in n:
		var xa := -C.POST_X + 2 * C.POST_X * i / n
		var xb := -C.POST_X + 2 * C.POST_X * (i + 1) / n
		var ha := C.net_height(xa)
		var hb := C.net_height(xb)
		for s in [-1.0, 1.0]:
			var z: float = s * 0.012
			_quad(st, Vector3(xa, ha - 0.06, z), Vector3(xb, hb - 0.06, z), Vector3(xb, hb + 0.01, z), Vector3(xa, ha + 0.01, z), LINE, Vector3(0, 0, s))
		_quad(st, Vector3(xa, ha + 0.01, -0.012), Vector3(xb, hb + 0.01, -0.012), Vector3(xb, hb + 0.01, 0.012), Vector3(xa, ha + 0.01, 0.012), LINE, Vector3.UP)
	_quad(st, Vector3(-0.025, 0, 0.013), Vector3(0.025, 0, 0.013), Vector3(0.025, C.NET_CENTRE, 0.013), Vector3(-0.025, C.NET_CENTRE, 0.013), LINE, Vector3.BACK)
	_add(_mesh(st))
	# the mesh: a see-through dark grid
	var net := SurfaceTool.new()
	net.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in n:
		var xa := -C.POST_X + 2 * C.POST_X * i / n
		var xb := -C.POST_X + 2 * C.POST_X * (i + 1) / n
		net.set_uv(Vector2(xa, 0))
		var a := Vector3(xa, 0.03, 0)
		var b := Vector3(xb, 0.03, 0)
		var c := Vector3(xb, C.net_height(xb) - 0.06, 0)
		var dd := Vector3(xa, C.net_height(xa) - 0.06, 0)
		for p in [a, c, b, a, dd, c]:
			net.set_uv(Vector2(p.x, p.y) * 12.0)
			net.add_vertex(p)
	var nm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;
void fragment() {
	// antialiased grid; far away (cells smaller than a few pixels) it turns into its average
	vec2 g = abs(fract(UV) - 0.5);
	vec2 w = fwidth(UV);
	float lx = smoothstep(0.40 - w.x, 0.40 + w.x, g.x);
	float ly = smoothstep(0.40 - w.y, 0.40 + w.y, g.y);
	float line = max(lx, ly);
	float far = smoothstep(0.15, 0.4, max(w.x, w.y));
	ALBEDO = vec3(0.08, 0.10, 0.10);
	ALPHA = mix(line, 0.36, far) * 0.85;
}"""
	nm.shader = sh
	_add(net.commit(), nm)

# ------------------------------------------------------------------ ball and racket

func make_ball() -> Node3D:
	if _ball == null:
		var s := SphereMesh.new()
		s.radius = 0.065
		s.height = 0.13
		s.radial_segments = 16
		s.rings = 8
		var st := SurfaceTool.new()
		st.create_from(s, 0)
		_ball = ArrayMesh.new()
		var arr := st.commit_to_arrays()
		var n: int = arr[Mesh.ARRAY_VERTEX].size()
		var cols := PackedColorArray()
		cols.resize(n)
		for i in n:
			var p: Vector3 = arr[Mesh.ARRAY_VERTEX][i]
			# the seam: a white band curving round the ball
			var seam := absf(p.y / 0.065 - 0.6 * sin(atan2(p.z, p.x) * 2)) < 0.12
			cols[i] = Color(0.98, 0.98, 0.9) if seam else Color(0.86, 0.95, 0.20)
		arr[Mesh.ARRAY_COLOR] = cols
		_ball.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		_ball.surface_set_material(0, material())
	var mi := MeshInstance3D.new()
	mi.mesh = _ball
	return mi

## grip at the origin, the head up +y, the strings in the x-y plane; 0.68 m long
func make_racket() -> Node3D:
	if _racket == null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_box(st, Vector3(-0.016, 0.0, -0.016), Vector3(0.016, 0.20, 0.016), Color(0.15, 0.15, 0.18))
		_box(st, Vector3(-0.012, 0.20, -0.012), Vector3(0.012, 0.36, 0.012), Color(0.85, 0.25, 0.22))
		var seg := 20
		var cy := 0.52
		for i in seg:
			var a0 := TAU * i / seg
			var a1 := TAU * (i + 1) / seg
			var p0 := Vector3(0.13 * sin(a0), cy + 0.16 * cos(a0), 0)
			var p1 := Vector3(0.13 * sin(a1), cy + 0.16 * cos(a1), 0)
			var mid := (p0 + p1) / 2
			var r := 0.014
			_box(st, mid - Vector3(r, r, r), mid + Vector3(r, r, r), Color(0.85, 0.25, 0.22))
			for s in [-1.0, 1.0]:
				_quad(st, Vector3(0, cy, s * 0.002), p0 + Vector3(0, 0, s * 0.002), p1 + Vector3(0, 0, s * 0.002), Vector3(0, cy, s * 0.002), Color(0.92, 0.92, 0.88, 1), Vector3(0, 0, s))
		_racket = st.commit()
		_racket.surface_set_material(0, material())
	var mi := MeshInstance3D.new()
	mi.mesh = _racket
	return mi
