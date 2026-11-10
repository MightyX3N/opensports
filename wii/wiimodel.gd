## Turns models from the player's own Wii disc (wii/brres.gd) into Godot meshes with the
## materials' own GPU stages as shaders (wii/gxshader.gd): rest-pose geometry in metres,
## vertex colours, up to eight texture coordinate sets, culling, blending, depth.
class_name WiiModel

const SCALE := 0.1 # Wii Sports units are 10 cm
const WRAP := [0, 1, 2]

static var _shader_cache := {}
static var _tex_cache := {} # texture dictionary -> { key -> Texture2D }

## the image for a sampler: a texture pack's replacement when there is one, else the
## game's own texture (upscaled when Settings ask for it)
static func texture(arch: Dictionary, sampler: Dictionary) -> Texture2D:
	var t = arch.textures.get(sampler.name)
	if t == null:
		return null
	var key := "%s:%d%d" % [sampler.name, sampler.wrap_s, sampler.wrap_t]
	var per: Dictionary = _tex_cache.get_or_add(t, {})
	if per.has(key):
		return per[key]
	var tex: Texture2D = null
	var mipmapped: bool = t.mips > 1 and sampler.min_filter >= 2
	if TexturePacks.enabled():
		tex = TexturePacks.find(t, mipmapped)
	if tex == null:
		var img := Image.create_from_data(t.w, t.h, false, Image.FORMAT_RGBA8, Brres.decode_texture(t))
		var factor := Upscale.factor()
		if factor > 1:
			var big := Upscale.image(img, factor, sampler.wrap_s, sampler.wrap_t, t)
			if big != null:
				img = big.duplicate()
		img.generate_mipmaps()
		tex = ImageTexture.create_from_image(img)
	per[key] = tex
	return tex

static func clear_textures() -> void:
	_tex_cache.clear()

## one ShaderMaterial for a GX material
static func material(arch: Dictionary, mat: Dictionary) -> ShaderMaterial:
	if mat.has("_godot"):
		return mat._godot
	# projections through the game's own scene cameras (ref_camera >= 0): we can't place those
	# cameras, so sample the projected texture at its brightest point
	for i in mat.num_tex_gens:
		var tm = mat.tex_mtx.get(i)
		var g = mat.tex_gens.get(i)
		if tm and g and tm.map_mode == 2 and tm.ref_camera >= 0:
			for st in mat.tev:
				if st.tex_on and st.tex_coord == i and mat.samplers.has(st.tex_map):
					var t = arch.textures.get(mat.samplers[st.tex_map].name)
					if t:
						var px := Brres.decode_texture(t)
						var best := -1
						var uv := Vector2(0.5, 0.5)
						for y in t.h:
							for x in t.w:
								var o: int = (y * t.w + x) * 4
								var l: int = px[o] + px[o + 1] + px[o + 2]
								if l > best:
									best = l
									uv = Vector2((x + 0.5) / t.w, (y + 0.5) / t.h)
						g.const_uv = uv
	var code := GXShader.source(mat, {linear_out = Gfx.LINEAR_OUT})
	var sh: Shader = _shader_cache.get(code)
	if sh == null:
		sh = Shader.new()
		sh.code = code
		_shader_cache[code] = sh
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("uPost", GXShader.post_matrices(mat))
	m.set_shader_parameter("uMat0", mat.mat_color[0])
	m.set_shader_parameter("uMat1", mat.mat_color[1])
	m.set_shader_parameter("uAmb0", mat.amb_color[0])
	m.set_shader_parameter("uAmb1", mat.amb_color[1])
	m.set_shader_parameter("uK", PackedColorArray(mat.konst))
	m.set_shader_parameter("uC", PackedColorArray(mat.reg_colors))
	for st in mat.tev:
		if st.tex_on and mat.samplers.has(st.tex_map):
			m.set_shader_parameter("uTex%d" % st.tex_map, texture(arch, mat.samplers[st.tex_map]))
	mat._godot = m
	return m

## build meshes for one model: a list of { mesh, material, name, mat_name, translucent }
## in the game's draw order (its opaque list, then its translucent list).
## opts: scale, shape (only that shape), local_space (ignore bone matrices),
## filter: Callable(mat_name, shape_name) -> false to skip
static func build(arch: Dictionary, model_name: String, opts := {}) -> Array:
	var model: Dictionary = arch.models[model_name]
	var sc: float = opts.get("scale", SCALE)
	var mtx := Brres.rest_matrices(model)
	var out := []
	for list in [["DrawOpa", false], ["DrawXlu", true]]:
		for op in model.code.get(list[0], []):
			if op.op != "draw":
				continue
			var mat: Dictionary = model.materials[op.mat]
			var shp: Dictionary = model.shapes[op.shp]
			if opts.has("shape") and shp.name != opts.shape:
				continue
			if opts.has("filter") and opts.filter.call(mat.name, shp.name) == false:
				continue
			var mesh := _mesh(shp, mtx, sc, opts.get("local_space", false))
			if mesh == null:
				continue
			out.append({mesh = mesh, material = material(arch, mat), name = shp.name, mat_name = mat.name, translucent = list[1]})
	return out

static func _mesh(shp: Dictionary, mtx: Dictionary, sc: float, local_space: bool) -> ArrayMesh:
	var n: int = shp.pos.size()
	if n == 0 or shp.tris.size() == 0:
		return null
	var single = null
	if local_space:
		single = Transform3D.IDENTITY
	elif shp.mtx_idx >= 0:
		single = mtx.get(shp.mtx_idx, Transform3D.IDENTITY)
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	pos.resize(n)
	nrm.resize(n)
	for i in n:
		var m: Transform3D
		if single != null:
			m = single
		else:
			m = mtx.get(shp.mtx[i], Transform3D.IDENTITY)
		pos[i] = (m * shp.pos[i]) * sc
		nrm[i] = (m.basis * shp.nrm[i]).normalized()
	var uv: Array = shp.uv
	var c0 := PackedFloat32Array()
	var c1 := PackedFloat32Array()
	var c2 := PackedFloat32Array()
	var c3 := PackedFloat32Array()
	c0.resize(n * 4); c1.resize(n * 4); c2.resize(n * 4); c3.resize(n * 4)
	for i in n:
		var a: Vector2 = uv[2][i]; var b: Vector2 = uv[3][i]
		c0[i * 4] = a.x; c0[i * 4 + 1] = a.y; c0[i * 4 + 2] = b.x; c0[i * 4 + 3] = b.y
		a = uv[4][i]; b = uv[5][i]
		c1[i * 4] = a.x; c1[i * 4 + 1] = a.y; c1[i * 4 + 2] = b.x; c1[i * 4 + 3] = b.y
		a = uv[6][i]; b = uv[7][i]
		c2[i * 4] = a.x; c2[i * 4 + 1] = a.y; c2[i * 4 + 2] = b.x; c2[i * 4 + 3] = b.y
		var k: Color = shp.clr1[i]
		c3[i * 4] = k.r; c3[i * 4 + 1] = k.g; c3[i * 4 + 2] = k.b; c3[i * 4 + 3] = k.a
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pos
	arrays[Mesh.ARRAY_NORMAL] = nrm
	arrays[Mesh.ARRAY_COLOR] = shp.clr0
	arrays[Mesh.ARRAY_TEX_UV] = uv[0]
	arrays[Mesh.ARRAY_TEX_UV2] = uv[1]
	arrays[Mesh.ARRAY_CUSTOM0] = c0
	arrays[Mesh.ARRAY_CUSTOM1] = c1
	arrays[Mesh.ARRAY_CUSTOM2] = c2
	arrays[Mesh.ARRAY_CUSTOM3] = c3
	arrays[Mesh.ARRAY_INDEX] = shp.tris
	var fmt := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) \
		| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT) \
		| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT) \
		| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM3_SHIFT)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, fmt)
	return mesh

## put built parts under a node, in draw order (render priority keeps the game's order)
static func instance(parts: Array, parent: Node3D, first_priority := -100) -> Array:
	var nodes := []
	var pri := first_priority
	for p in parts:
		var mi := MeshInstance3D.new()
		mi.name = p.name
		mi.mesh = p.mesh
		var m: ShaderMaterial = p.material.duplicate() if p.has("own_material") else p.material
		mi.material_override = m
		mi.sorting_offset = 0.0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
		nodes.append(mi)
		pri += 1
	return nodes
