## Wii GPU (GX) materials as Godot shaders: texture coordinate generation (texture
## coordinates, environment maps, camera projections, texture matrices), the colour channels,
## the TEV combine stages, swap tables, constant colours, the alpha test and blending.
## A port of the shader generation in noclip.website's src/gx/gx_material.ts (MIT).
## Hardware lights are not emulated: Wii Sports' stages bake their lighting into vertex
## colours; lit models without lights get material x ambient, as on the console.
class_name GXShader

const KC := {0: "vec3(1.0)", 1: "vec3(7.0/8.0)", 2: "vec3(6.0/8.0)", 3: "vec3(5.0/8.0)", 4: "vec3(4.0/8.0)",
	5: "vec3(3.0/8.0)", 6: "vec3(2.0/8.0)", 7: "vec3(1.0/8.0)",
	0x0C: "k0.rgb", 0x0D: "k1.rgb", 0x0E: "k2.rgb", 0x0F: "k3.rgb",
	0x10: "k0.rrr", 0x11: "k1.rrr", 0x12: "k2.rrr", 0x13: "k3.rrr",
	0x14: "k0.ggg", 0x15: "k1.ggg", 0x16: "k2.ggg", 0x17: "k3.ggg",
	0x18: "k0.bbb", 0x19: "k1.bbb", 0x1A: "k2.bbb", 0x1B: "k3.bbb",
	0x1C: "k0.aaa", 0x1D: "k1.aaa", 0x1E: "k2.aaa", 0x1F: "k3.aaa"}
const KA := {0: "1.0", 1: "(7.0/8.0)", 2: "(6.0/8.0)", 3: "(5.0/8.0)", 4: "(4.0/8.0)", 5: "(3.0/8.0)",
	6: "(2.0/8.0)", 7: "(1.0/8.0)",
	0x10: "k0.r", 0x11: "k1.r", 0x12: "k2.r", 0x13: "k3.r", 0x14: "k0.g", 0x15: "k1.g", 0x16: "k2.g", 0x17: "k3.g",
	0x18: "k0.b", 0x19: "k1.b", 0x1A: "k2.b", 0x1B: "k3.b", 0x1C: "k0.a", 0x1D: "k1.a", 0x1E: "k2.a", 0x1F: "k3.a"}
const REG := ["prev", "r0", "r1", "r2"]
const SW := ["r", "g", "b", "a"]
const TEXSRC := ["UV", "UV2", "CUSTOM0.xy", "CUSTOM0.zw", "CUSTOM1.xy", "CUSTOM1.zw", "CUSTOM2.xy", "CUSTOM2.zw"]
const WRAP_HINT := ["repeat_disable", "repeat_enable", "repeat_enable"]

static func _ras(st: Dictionary) -> String:
	if st.channel == 0: return "vColor0"
	if st.channel == 1: return "vColor1"
	return "vec4(0.0)"

static func _swz(tbl: Array, ch: int) -> String:
	return SW[tbl[ch]]

static func _color_swz(tbl: Array, alpha: bool) -> String:
	if alpha:
		var a := _swz(tbl, 3)
		return a + a + a
	return _swz(tbl, 0) + _swz(tbl, 1) + _swz(tbl, 2)

static func _color_in(st: Dictionary, v: int) -> String:
	match v:
		0: return "prev.rgb"
		1: return "prev.aaa"
		2: return "r0.rgb"
		3: return "r0.aaa"
		4: return "r1.rgb"
		5: return "r1.aaa"
		6: return "r2.rgb"
		7: return "r2.aaa"
		8: return "ts." + _color_swz(st.tex_swap, false)
		9: return "ts." + _color_swz(st.tex_swap, true)
		10: return "clamp(" + _ras(st) + "." + _color_swz(st.ras_swap, false) + ", 0.0, 1.0)"
		11: return "clamp(" + _ras(st) + "." + _color_swz(st.ras_swap, true) + ", 0.0, 1.0)"
		12: return "vec3(1.0)"
		13: return "vec3(0.5)"
		14: return KC.get(st.kc, "vec3(1.0)")
	return "vec3(0.0)"

static func _alpha_in(st: Dictionary, v: int) -> String:
	match v:
		0: return "prev.a"
		1: return "r0.a"
		2: return "r1.a"
		3: return "r2.a"
		4: return "ts." + _swz(st.tex_swap, 3)
		5: return "clamp(" + _ras(st) + "." + _swz(st.ras_swap, 3) + ", 0.0, 1.0)"
		6: return KA.get(st.ka, "1.0")
	return "0.0"

static func _op(bias: int, scale: int, sub: bool, clamp_on: bool, a: String, b: String, c: String, d: String, zero: String, is_color: bool) -> String:
	var e := ""
	if bias == 3:
		# compare ops (rare): approximate the per-component greater-than / equal
		if is_color:
			e = "((" + ("vec3(equal(" if sub else "vec3(greaterThan(") + a + ", " + b + "))) * " + c + ") + " + d
		else:
			e = "(((" + a + (" == " if sub else " > ") + b + ") ? " + c + " : " + zero + ") + " + d + ")"
	else:
		e = ("-" if sub else "") + "mix(" + a + ", " + b + ", " + c + ") + " + d
		if bias == 1: e = "(" + e + ") + 0.5"
		elif bias == 2: e = "(" + e + ") - 0.5"
		if scale == 1: e = "(" + e + ") * 2.0"
		elif scale == 2: e = "(" + e + ") * 4.0"
		elif scale == 3: e = "(" + e + ") * 0.5"
	if clamp_on:
		return "clamp(" + e + ", 0.0, 1.0)"
	return "clamp(" + e + ", -4.0, 4.0)"

const CMP := ["false", "o.a <  %s", "o.a == %s", "o.a <= %s", "o.a >  %s", "o.a != %s", "o.a >= %s", "true"]
const COMBINE := ["(%s) && (%s)", "(%s) || (%s)", "(%s) != (%s)", "(%s) == (%s)"]

static func _channel_expr(chan: Dictionary, i: int) -> String:
	var vtx := "COLOR" if i == 0 else "CUSTOM3"
	var mat := vtx if chan.mat_vtx else ("uMat%d" % i)
	var amb := vtx if chan.amb_vtx else ("uAmb%d" % i)
	if chan.light:
		return mat + " * clamp(" + amb + ", 0.0, 1.0)"
	return mat

## Godot blend render mode for the material's pixel-engine blend, or "" for opaque
static func blend_mode(mat: Dictionary) -> String:
	var b: Dictionary = mat.blend
	if not b.on:
		return ""
	if b.sub:
		return "blend_sub"
	var key := "%d,%d" % [b.src, b.dst]
	match key:
		"4,5": return "blend_mix"      # src alpha, 1 - src alpha
		"1,5": return "blend_premul_alpha"
		"1,1", "4,1": return "blend_add"
		"2,0", "0,2": return "blend_mul" # dst colour x src
		"1,0": return ""
		"0,1": return "blend_mix"      # keeps the destination: drawn fully transparent below
	return "blend_mix"

## Godot shader code for a parsed material (wii/brres.gd). wraps: sampler map -> [wrapS, wrapT]
static func source(mat: Dictionary, opts := {}) -> String:
	var n_gen: int = mat.num_tex_gens
	var lines := PackedStringArray()
	var modes := ["unshaded", "skip_vertex_transform", "fog_disabled", "specular_disabled", "shadows_disabled", "ambient_light_disabled"]
	var cull: int = mat.cull
	modes.append(["cull_disabled", "cull_front", "cull_back", "cull_disabled"][cull] if cull <= 3 else "cull_disabled")
	var bm := blend_mode(mat)
	if bm != "":
		modes.append(bm)
	if not mat.zmode.test:
		modes.append("depth_test_disabled")
	modes.append("depth_draw_always" if mat.zmode.write else "depth_draw_never")
	lines.append("shader_type spatial;")
	lines.append("render_mode " + ", ".join(modes) + ";")
	lines.append("varying vec4 vColor0;")
	lines.append("varying vec4 vColor1;")
	for i in n_gen:
		lines.append("varying vec3 vTex%d;" % i)
	lines.append("uniform mat4 uPost[8];")
	lines.append("uniform vec4 uMat0; uniform vec4 uMat1; uniform vec4 uAmb0; uniform vec4 uAmb1;")
	lines.append("uniform vec4 uK[4]; uniform vec4 uC[4];")
	lines.append("uniform vec4 uTint = vec4(1.0);")
	# samplers
	var used := {}
	for st in mat.tev:
		if st.tex_on:
			used[st.tex_map] = true
	for t in 8:
		if used.has(t):
			var smp = mat.samplers.get(t)
			var ws: int = smp.wrap_s if smp else 1
			var wt: int = smp.wrap_t if smp else 1
			var rep := "repeat_disable" if (ws == 0 and wt == 0) else "repeat_enable"
			lines.append("uniform sampler2D uTex%d : filter_linear_mipmap_anisotropic, %s;" % [t, rep])
	lines.append("""
float ovf(float a) { float x = a * 255.0; x = sign(x) * floor(abs(x)); return mod(x, 256.0) / 255.0; }
vec3 ovf3(vec3 a) { return vec3(ovf(a.r), ovf(a.g), ovf(a.b)); }
vec4 ovf4(vec4 a) { return vec4(ovf(a.r), ovf(a.g), ovf(a.b), ovf(a.a)); }
// clamp (0) / repeat (1) / mirrored repeat (2) on each axis
vec2 wrapUV(vec2 uv, int ws, int wt) {
	if (ws == 2) { uv.x = 1.0 - abs(mod(uv.x, 2.0) - 1.0); }
	if (wt == 2) { uv.y = 1.0 - abs(mod(uv.y, 2.0) - 1.0); }
	if (ws == 0) { uv.x = clamp(uv.x, 0.0, 1.0); }
	if (wt == 0) { uv.y = clamp(uv.y, 0.0, 1.0); }
	return uv;
}
void vertex() {
	vec4 viewPos = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 viewNrm = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	VERTEX = viewPos.xyz;
	NORMAL = viewNrm;""")
	for i in 2:
		var ch = mat.chans.get(i)
		if ch != null and i < max(mat.num_chans, 1):
			lines.append("\tvColor%d = vec4((%s).rgb, (%s).a);" % [i, _channel_expr(ch.color, i), _channel_expr(ch.alpha, i)])
		else:
			lines.append("\tvColor%d = vec4(0.0);" % i)
	for i in n_gen:
		var g: Dictionary = mat.tex_gens[i]
		var tm = mat.tex_mtx.get(i)
		var src := ""
		if g.row == 0: src = "vec4(VERTEX_MODEL, 1.0)"
		elif g.row == 1: src = "vec4(NORMAL_MODEL, 1.0)"
		elif g.row == 2: src = "vColor0"
		elif g.row >= 5: src = "vec4(" + TEXSRC[mini(g.row - 5, 7)] + ", 1.0, 1.0)"
		else: src = "vec4(0.0, 0.0, 1.0, 1.0)"
		var m := src + ".xyz"
		if g.matrix == "pnmtx": m = "viewPos.xyz"
		elif g.matrix == "nrmmtx": m = "viewNrm"
		var t := m if g.proj == 1 else ("vec3((" + m + ").xy, 1.0)")
		if g.normalize:
			t = "normalize(" + t + ")"
		var expr := "vec4(" + t + ", 1.0)"
		if tm != null and tm.map_mode == 2 and not g.has("const_uv"):
			# camera projection into 0..1 texture space (noclip texProjCameraSceneTex)
			expr = "texProj(PROJECTION_MATRIX) * " + expr
		lines.append("\tvTex%d = (uPost[%d] * %s).xyz;" % [i, i, expr])
	lines.append("}")
	# the projection helper must come before vertex(): insert it
	var helper := """
mat4 texProj(mat4 P) {
	// column-major: P[col][row]
	float sS = 0.5; float sT = -0.5; float tS = 0.5; float tT = 0.5;
	return mat4(vec4(P[0][0] * sS, 0.0, 0.0, 0.0), vec4(0.0, P[1][1] * sT, 0.0, 0.0),
		vec4(P[2][0] * sS + P[2][3] * tS, P[2][1] * sT + P[2][3] * tT, P[2][3], 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}"""
	# fragment: the TEV stages
	var f := PackedStringArray()
	f.append("void fragment() {")
	f.append("\tvec4 k0 = uK[0]; vec4 k1 = uK[1]; vec4 k2 = uK[2]; vec4 k3 = uK[3];")
	f.append("\tvec4 prev = uC[0]; vec4 r0 = uC[1]; vec4 r1 = uC[2]; vec4 r2 = uC[3];")
	f.append("\tvec4 ts = vec4(0.0); vec4 A; vec4 B; vec4 C; vec4 D;")
	for st in mat.tev:
		if st.tex_on and st.tex_coord < n_gen:
			var g: Dictionary = mat.tex_gens[st.tex_coord]
			var tc := "vTex%d.xy" % st.tex_coord
			if g.proj == 1:
				tc = "vTex%d.xy / vTex%d.z" % [st.tex_coord, st.tex_coord]
			var smp = mat.samplers.get(st.tex_map)
			var ws: int = smp.wrap_s if smp else 1
			var wt: int = smp.wrap_t if smp else 1
			if ws == 2 or wt == 2 or (ws == 0) != (wt == 0):
				tc = "wrapUV(%s, %d, %d)" % [tc, ws, wt]
			f.append("\tts = texture(uTex%d, %s);" % [st.tex_map, tc])
		else:
			f.append("\tts = vec4(1.0);")
		f.append("\tA = ovf4(vec4(%s, %s));" % [_color_in(st, st.cA), _alpha_in(st, st.aA)])
		f.append("\tB = ovf4(vec4(%s, %s));" % [_color_in(st, st.cB), _alpha_in(st, st.aB)])
		f.append("\tC = ovf4(vec4(%s, %s));" % [_color_in(st, st.cC), _alpha_in(st, st.aC)])
		f.append("\tD = vec4(%s, %s);" % [_color_in(st, st.cD), _alpha_in(st, st.aD)])
		f.append("\t%s.rgb = %s;" % [REG[st.c_reg], _op(st.c_bias, st.c_scale, st.c_sub, st.c_clamp, "A.rgb", "B.rgb", "C.rgb", "D.rgb", "vec3(0.0)", true)])
		f.append("\t%s.a = %s;" % [REG[st.a_reg], _op(st.a_bias, st.a_scale, st.a_sub, st.a_clamp, "A.a", "B.a", "C.a", "D.a", "0.0", false)])
	var out := "vColor0"
	if mat.tev.size() > 0:
		var last: Dictionary = mat.tev[-1]
		if last.c_reg == last.a_reg:
			out = REG[last.c_reg]
		else:
			out = "vec4(%s.rgb, %s.a)" % [REG[last.c_reg], REG[last.a_reg]]
	f.append("\tvec4 o = ovf4(%s) * uTint;" % out)
	var at: Dictionary = mat.alpha_test
	if not (at.op == 1 and (at.comp0 == 7 or at.comp1 == 7)):
		var ca: String = CMP[at.comp0] % ("%.6f" % (at.ref0 / 255.0)) if at.comp0 != 0 and at.comp0 != 7 else CMP[at.comp0]
		var cb: String = CMP[at.comp1] % ("%.6f" % (at.ref1 / 255.0)) if at.comp1 != 0 and at.comp1 != 7 else CMP[at.comp1]
		f.append("\tif (!(" + (COMBINE[at.op] % [ca, cb]) + ")) { discard; }")
	f.append("\tALBEDO = %s;" % ("o.rgb" if not opts.get("linear_out", false) else "pow(max(o.rgb, vec3(0.0)), vec3(2.2))"))
	if bm != "":
		f.append("\tALPHA = clamp(o.a, 0.0, 1.0);")
	f.append("}")
	var code := "\n".join(lines)
	# vertex() uses VERTEX_MODEL / NORMAL_MODEL for position / normal texgens: keep the model-space values
	code = code.replace("void vertex() {", helper + "\nvoid vertex() {\n\tvec3 VERTEX_MODEL = VERTEX;\n\tvec3 NORMAL_MODEL = NORMAL;")
	return code + "\n" + "\n".join(f) + "\n"

## the post matrices (texture SRT x effect x mode base) for the material's generators
static func post_matrices(mat: Dictionary) -> Array:
	var out := []
	for i in 8:
		var t = mat.tex_mtx.get(i)
		var g = mat.tex_gens.get(i)
		if t == null or g == null:
			out.append(Projection.IDENTITY)
			continue
		var m: Array = t.m
		# texture SRT with its translation on the third input (q = 1); Projection columns
		var S := Projection(Vector4(m[0], m[3], 0, 0), Vector4(m[1], m[4], 0, 0), Vector4(m[2], m[5], 1, 0), Vector4(0, 0, 0, 1))
		if t.map_mode == 2 and g.has("const_uv"):
			# projected through one of the game's own scene cameras (an overhead light camera):
			# the projected texture's lit value everywhere
			out.append(Projection(Vector4(0, 0, 0, 0), Vector4(0, 0, 0, 0), Vector4(g.const_uv.x, g.const_uv.y, 1, 0), Vector4(0, 0, 0, 1)))
		elif t.map_mode == 0:
			out.append(S)
		else:
			var base := Projection.IDENTITY
			if t.map_mode == 1 or t.map_mode == 3:
				base = Projection(Vector4(0.5, 0, 0, 0), Vector4(0, -0.5, 0, 0), Vector4(0, 0, 0, 0), Vector4(0.5, 0.5, 1, 1))
			var e: Array = t.effect
			var E := Projection(Vector4(e[0], e[4], e[8], 0), Vector4(e[1], e[5], e[9], 0), Vector4(e[2], e[6], e[10], 0), Vector4(e[3], e[7], e[11], 1))
			out.append(S * E * base)
	return out
