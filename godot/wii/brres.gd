## BRRES model archives (NW4R G3D) from the player's own Wii disc: MDL0 models, TEX0
## textures, PLT0 palettes, SCN0 cameras. A port of the parsing in noclip.website's
## src/rres/brres.ts and src/gx/gx_displaylist.ts (MIT): resource dictionaries, vertex
## buffers, the GPU display lists holding the triangles, bones and the draw list, and the
## material registers (textures, texture generation, colours, TEV stages, blending).
class_name Brres

const ATTR_POS := 9
const ATTR_NRM := 10
const ATTR_CLR0 := 11
const ATTR_CLR1 := 12
const ATTR_TEX0 := 13
const COMP_SIZE := [1, 1, 2, 2, 4]
const COLOR_BYTES := [2, 3, 4, 2, 3, 4]

static func _bit(v: int, shift: int, mask: int) -> int:
	return (v >> shift) & mask

## resource dictionary at absolute offset t: list of { name, offs }
static func res_dic(s: PackedByteArray, t: int) -> Array:
	if t == 0:
		return []
	var count := Bin.u32(s, t + 4)
	var out := []
	var idx := t + 8 + 0x10
	for i in count:
		out.append({name = Bin.cstr(s, t + Bin.u32(s, idx + 8)), offs = t + Bin.u32(s, idx + 12)})
		idx += 0x10
	return out

## GPU register state from a display list (only what we read)
static func new_regs() -> Dictionary:
	return {bp = {0xFE: 0xFFFFFF}, cp = {}, xf = {}, kcolor = {}}

static func run_regs(r: Dictionary, s: PackedByteArray, o: int, n: int) -> Dictionary:
	var i := o
	var e := mini(o + n, s.size())
	while i < e:
		var cmd := s[i]
		i += 1
		if cmd == 0x61: # BP
			var v := Bin.u32(s, i)
			i += 4
			var addr := v >> 24
			var mask: int = r.bp.get(0xFE, 0xFFFFFF)
			var old: int = r.bp.get(addr, 0)
			var val := ((v & mask) | (old & ~mask)) & 0xFFFFFF
			if addr != 0xFE:
				r.bp[0xFE] = 0xFFFFFF
			r.bp[addr] = val
			if addr >= 0xE0 and addr <= 0xE7:
				# TEV colour registers (bank 0) share addresses with the constant colours (bank 1)
				var bank := (val >> 23) & 1
				r.kcolor[bank * 8 + (addr - 0xE0)] = val
		elif cmd == 0x08: # CP
			r.cp[s[i]] = Bin.u32(s, i + 1)
			i += 5
		elif cmd == 0x10: # XF
			var cnt := Bin.u16(s, i) + 1
			var addr := Bin.u16(s, i + 2)
			i += 4
			for j in cnt:
				r.xf[addr + j] = Bin.u32(s, i)
				i += 4
		elif cmd == 0x00:
			pass
		else:
			break
	return r

## texture matrix (2x3: u' = a*u + b*v + c, v' = d*u + e*v + f) from SRT, per modelling tool
static func tex_mtx(mode: int, sS: float, sT: float, rot: float, tS: float, tT: float) -> Array:
	var th := deg_to_rad(rot)
	var sr := sin(th)
	var cr := cos(th)
	if mode == 0: # Maya
		return [sS * cr, sS * sr, sS * ((-0.5 * cr) - (0.5 * sr - 0.5) - tS),
			sT * -sr, sT * cr, sT * ((-0.5 * cr) + (0.5 * sr - 0.5) + tT) + 1]
	elif mode == 1: # XSI
		return [sS * cr, sS * -sr, (sS * sr) - (sS * cr * tS) - (sS * sr * tT),
			sT * sr, sT * cr, (sT * -cr) - (sT * sr * tS) + (sT * cr * tT) + 1]
	elif mode == 2: # 3ds Max
		return [sS * cr, sS * sr, sS * ((-cr * (tS + 0.5)) + (sr * (tT - 0.5))) + 0.5,
			sT * -sr, sT * cr, sT * ((sr * (tS + 0.5)) + (cr * (tT - 0.5))) + 0.5]
	return [sS * cr, sT * -sr, tS, sS * sr, sT * cr, tT] # basic

## scale, rotation (XYZ Euler, degrees), translation -> Transform3D (noclip's computeModelMatrixSRT)
static func srt(sc: Vector3, rot: Vector3, tr: Vector3) -> Transform3D:
	var rx := deg_to_rad(rot.x)
	var ry := deg_to_rad(rot.y)
	var rz := deg_to_rad(rot.z)
	var sX := sin(rx); var cX := cos(rx)
	var sY := sin(ry); var cY := cos(ry)
	var sZ := sin(rz); var cZ := cos(rz)
	var bx := Vector3(cY * cZ, sZ * cY, -sY) * sc.x
	var by := Vector3(sX * cZ * sY - cX * sZ, sX * sZ * sY + cX * cZ, sX * cY) * sc.y
	var bz := Vector3(cX * cZ * sY + sX * sZ, cX * sZ * sY - sX * cZ, cY * cX) * sc.z
	return Transform3D(Basis(bx, by, bz), tr)

static func m34(s: PackedByteArray, at: int) -> Transform3D:
	var m := []
	for k in 12:
		m.append(Bin.f32(s, at + k * 4))
	# row-major 3x4 -> columns
	return Transform3D(Basis(Vector3(m[0], m[4], m[8]), Vector3(m[1], m[5], m[9]), Vector3(m[2], m[6], m[10])),
		Vector3(m[3], m[7], m[11]))

# ---------------------------------------------------------------- textures

static func _parse_plt0(s: PackedByteArray, o: int) -> Dictionary:
	return {name = Bin.cstr(s, o + Bin.u32(s, o + 0x14)), fmt = Bin.u32(s, o + 0x18), count = Bin.u16(s, o + 0x1C),
		data = s, offset = o + Bin.u32(s, o + 0x10)}

static func _parse_tex0(s: PackedByteArray, o: int) -> Dictionary:
	return {name = Bin.cstr(s, o + Bin.u32(s, o + 0x14)), w = Bin.u16(s, o + 0x1C), h = Bin.u16(s, o + 0x1E),
		fmt = Bin.u32(s, o + 0x20), mips = Bin.u32(s, o + 0x24), data_offs = o + Bin.u32(s, o + 0x10), src = s,
		palette = null}

## a texture's top level as RGBA8 bytes (kept on the texture)
static func decode_texture(tex: Dictionary) -> PackedByteArray:
	if tex.has("rgba"):
		return tex.rgba
	tex.rgba = GXTex.decode(tex.fmt, tex.src, tex.data_offs, tex.w, tex.h, tex.palette)
	return tex.rgba

# ---------------------------------------------------------------- MDL0

static func _parse_vtx_buffer(s: PackedByteArray, o: int, kind: String) -> Dictionary:
	var b := {data_offs = o + Bin.u32(s, o + 0x08), name = Bin.cstr(s, o + Bin.u32(s, o + 0x0C)),
		comp_cnt = Bin.u32(s, o + 0x14), comp_type = Bin.u32(s, o + 0x18), shift = s[o + 0x1C], stride = s[o + 0x1D],
		count = Bin.u16(s, o + 0x1E), kind = kind}
	if kind == "clr":
		b.stride = b.shift
		b.shift = 0
	return b

static func _read_comp(s: PackedByteArray, o: int, ctype: int, scale: float) -> float:
	match ctype:
		0: return s[o] * scale
		1: return Bin.s8(s, o) * scale
		2: return Bin.u16(s, o) * scale
		3: return Bin.s16(s, o) * scale
	return Bin.f32(s, o)

## colour in any of the GX colour formats -> Color (0..1)
static func _read_color(s: PackedByteArray, o: int, ctype: int) -> Color:
	match ctype:
		0:
			var c := GXTex.rgb565(Bin.u16(s, o))
			return Color8(c[0], c[1], c[2], 255)
		1, 2:
			return Color8(s[o], s[o + 1], s[o + 2], 255)
		3:
			var p := Bin.u16(s, o)
			return Color8(((p >> 12) & 15) * 17, ((p >> 8) & 15) * 17, ((p >> 4) & 15) * 17, (p & 15) * 17)
		4:
			var p := Bin.u24(s, o)
			return Color8(GXTex.x6((p >> 18) & 63), GXTex.x6((p >> 12) & 63), GXTex.x6((p >> 6) & 63), GXTex.x6(p & 63))
	return Color8(s[o], s[o + 1], s[o + 2], s[o + 3])

## the per-vertex layout in a display list from the VCD / VAT registers
static func _vertex_layout(r: Dictionary) -> Array:
	var vl: int = r.cp.get(0x50, 0)
	var vh: int = r.cp.get(0x60, 0)
	var vat_a: int = r.cp.get(0x70, 0)
	var vat_b: int = r.cp.get(0x80, 0)
	var vat_c: int = r.cp.get(0x90, 0)
	var types := {}
	for a in 9:
		types[a] = _bit(vl, a, 1)
	types[ATTR_POS] = _bit(vl, 9, 3)
	types[ATTR_NRM] = _bit(vl, 11, 3)
	types[ATTR_CLR0] = _bit(vl, 13, 3)
	types[ATTR_CLR1] = _bit(vl, 15, 3)
	for t in 8:
		types[ATTR_TEX0 + t] = _bit(vh, t * 2, 3)
	var fmt := {}
	fmt[ATTR_POS] = {cnt = _bit(vat_a, 0, 1), type = _bit(vat_a, 1, 7), shift = _bit(vat_a, 4, 31)}
	fmt[ATTR_NRM] = {cnt = 2 if _bit(vat_a, 31, 1) == 1 else _bit(vat_a, 9, 1), type = _bit(vat_a, 10, 7), shift = 0}
	fmt[ATTR_CLR0] = {cnt = _bit(vat_a, 13, 1), type = _bit(vat_a, 14, 7), shift = 0}
	fmt[ATTR_CLR1] = {cnt = _bit(vat_a, 17, 1), type = _bit(vat_a, 18, 7), shift = 0}
	fmt[ATTR_TEX0] = {cnt = _bit(vat_a, 21, 1), type = _bit(vat_a, 22, 7), shift = _bit(vat_a, 25, 31)}
	fmt[ATTR_TEX0 + 1] = {cnt = _bit(vat_b, 0, 1), type = _bit(vat_b, 1, 7), shift = _bit(vat_b, 4, 31)}
	fmt[ATTR_TEX0 + 2] = {cnt = _bit(vat_b, 9, 1), type = _bit(vat_b, 10, 7), shift = _bit(vat_b, 13, 31)}
	fmt[ATTR_TEX0 + 3] = {cnt = _bit(vat_b, 18, 1), type = _bit(vat_b, 19, 7), shift = _bit(vat_b, 22, 31)}
	fmt[ATTR_TEX0 + 4] = {cnt = _bit(vat_b, 27, 1), type = _bit(vat_b, 28, 7), shift = _bit(vat_c, 0, 31)}
	fmt[ATTR_TEX0 + 5] = {cnt = _bit(vat_c, 5, 1), type = _bit(vat_c, 6, 7), shift = _bit(vat_c, 9, 31)}
	fmt[ATTR_TEX0 + 6] = {cnt = _bit(vat_c, 14, 1), type = _bit(vat_c, 15, 7), shift = _bit(vat_c, 18, 31)}
	fmt[ATTR_TEX0 + 7] = {cnt = _bit(vat_c, 23, 1), type = _bit(vat_c, 24, 7), shift = _bit(vat_c, 27, 31)}
	return [types, fmt]

## a decoded array value (indexed attribute) as up to 3 floats or a Color
static func _array_value(s: PackedByteArray, buf: Dictionary, attr: int, i: int):
	if attr == ATTR_CLR0 or attr == ATTR_CLR1:
		var stride: int = buf.stride if buf.stride > 0 else COLOR_BYTES[buf.comp_type]
		return _read_color(s, buf.data_offs + i * stride, buf.comp_type)
	var n := 0
	if attr == ATTR_POS:
		n = 3 if buf.comp_cnt == 1 else 2
	elif attr == ATTR_NRM:
		n = 3
	else:
		n = 2 if buf.comp_cnt == 1 else 1
	var cs: int = COMP_SIZE[buf.comp_type]
	var stride: int = buf.stride if buf.stride > 0 else n * cs
	var shift: int = buf.shift
	if attr == ATTR_NRM:
		shift = 6 if cs == 1 else 14
	var scale := 1.0 / float(1 << shift)
	var o: int = buf.data_offs + i * stride
	var v := Vector3.ZERO
	for k in n:
		v[k] = _read_comp(s, o + k * cs, buf.comp_type, scale)
	return v

static func _direct_size(attr: int, f: Dictionary) -> int:
	if attr <= 8:
		return 1
	if attr == ATTR_CLR0 or attr == ATTR_CLR1:
		return COLOR_BYTES[f.type]
	var n := 0
	if attr == ATTR_POS:
		n = 3 if f.cnt == 1 else 2
	elif attr == ATTR_NRM:
		n = 9 if f.cnt == 1 else 3
	else:
		n = 2 if f.cnt == 1 else 1
	return n * COMP_SIZE[f.type]

## run a shape's primitive display list into packed vertex arrays and triangle indices
static func _decode_primitives(s: PackedByteArray, o: int, n: int, types: Dictionary, fmt: Dictionary, arrays: Dictionary) -> Dictionary:
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var clr0 := PackedColorArray()
	var clr1 := PackedColorArray()
	var uvs := []
	for t in 8:
		uvs.append(PackedVector2Array())
	var mtx := PackedInt32Array()
	var tris := PackedInt32Array()
	var pos_table := {}
	var i := o
	var e := o + n
	var white := Color(1, 1, 1, 1)
	var attrs := []
	for a in range(0, 21):
		if types.get(a, 0) > 0:
			attrs.append(a)
	while i < e:
		var cmd := s[i]
		if cmd == 0:
			break
		if cmd == 0x20 or cmd == 0x28 or cmd == 0x30 or cmd == 0x38:
			if cmd == 0x20:
				var idx := Bin.u16(s, i + 1)
				var addr_len := Bin.u16(s, i + 3)
				pos_table[(addr_len & 0xFFF) / 12] = idx
			i += 5
			continue
		var prim := cmd & 0xF8
		var cnt := Bin.u16(s, i + 1)
		i += 3
		var first := pos.size()
		for _v in cnt:
			var p := Vector3.ZERO
			var nm := Vector3(0, 1, 0)
			var c0 := white
			var c1 := white
			var uv := [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
			var slot := -1
			for a in attrs:
				var t: int = types[a]
				if a <= 8:
					var val := s[i]
					i += 1
					if a == 0:
						slot = val / 3
				elif t == 1:
					var f: Dictionary = fmt[a]
					var sz := _direct_size(a, f)
					if a == ATTR_CLR0:
						c0 = _read_color(s, i, f.type)
					elif a == ATTR_CLR1:
						c1 = _read_color(s, i, f.type)
					else:
						var cs: int = COMP_SIZE[f.type]
						var sh: int = (6 if cs == 1 else 14) if a == ATTR_NRM else f.shift
						var sc := 1.0 / float(1 << sh)
						var vv := Vector3.ZERO
						for k in mini(sz / cs, 3):
							vv[k] = _read_comp(s, i + k * cs, f.type, sc)
						if a == ATTR_POS:
							p = vv
						elif a == ATTR_NRM:
							nm = vv
						else:
							uv[a - ATTR_TEX0] = Vector2(vv.x, vv.y)
					i += sz
				else:
					var idx := 0
					if t == 2:
						idx = s[i]
						i += 1
					else:
						idx = Bin.u16(s, i)
						i += 2
					var buf = arrays.get(a)
					if buf != null:
						var val = _array_value(s, buf, a, idx)
						if a == ATTR_POS:
							p = val
						elif a == ATTR_NRM:
							nm = val
						elif a == ATTR_CLR0:
							c0 = val
						elif a == ATTR_CLR1:
							c1 = val
						else:
							uv[a - ATTR_TEX0] = Vector2(val.x, val.y)
			pos.append(p)
			nrm.append(nm)
			clr0.append(c0)
			clr1.append(c1)
			for k in 8:
				uvs[k].append(uv[k])
			mtx.append(pos_table.get(slot, -1) if slot >= 0 else -1)
		# topology to triangles
		if prim == 0x90:
			for k in range(0, cnt - 2, 3):
				tris.append_array([first + k, first + k + 1, first + k + 2])
		elif prim == 0x98:
			for k in range(2, cnt):
				if k % 2 == 0:
					tris.append_array([first + k - 2, first + k - 1, first + k])
				else:
					tris.append_array([first + k - 2, first + k, first + k - 1])
		elif prim == 0xA0:
			for k in range(2, cnt):
				tris.append_array([first, first + k - 1, first + k])
		elif prim == 0x80 or prim == 0x88:
			for k in range(0, cnt - 3, 4):
				tris.append_array([first + k, first + k + 1, first + k + 2, first + k, first + k + 2, first + k + 3])
	return {pos = pos, nrm = nrm, clr0 = clr0, clr1 = clr1, uv = uvs, mtx = mtx, tris = tris}

static func _parse_shape(s: PackedByteArray, o: int, inputs: Dictionary) -> Dictionary:
	var pre_size := Bin.u32(s, o + 0x18)
	var pre_offs := o + 0x18 + Bin.u32(s, o + 0x20)
	var prim_size := Bin.u32(s, o + 0x24)
	var prim_offs := o + 0x24 + Bin.u32(s, o + 0x2C)
	var shp := {mtx_idx = Bin.s32(s, o + 0x08), name = Bin.cstr(s, o + Bin.u32(s, o + 0x38)), id = Bin.u32(s, o + 0x3C)}
	var arrays := {}
	var id := Bin.s16(s, o + 0x48)
	if id >= 0: arrays[ATTR_POS] = inputs.pos[id]
	id = Bin.s16(s, o + 0x4A)
	if id >= 0: arrays[ATTR_NRM] = inputs.nrm[id]
	id = Bin.s16(s, o + 0x4C)
	if id >= 0: arrays[ATTR_CLR0] = inputs.clr[id]
	id = Bin.s16(s, o + 0x4E)
	if id >= 0: arrays[ATTR_CLR1] = inputs.clr[id]
	for t in 8:
		id = Bin.s16(s, o + 0x50 + t * 2)
		if id >= 0 and id < inputs.txc.size():
			arrays[ATTR_TEX0 + t] = inputs.txc[id]
	var r := run_regs(new_regs(), s, pre_offs, pre_size)
	var lay := _vertex_layout(r)
	shp.merge(_decode_primitives(s, prim_offs, prim_size, lay[0], lay[1], arrays))
	shp.has_nrm = lay[0][ATTR_NRM] > 0
	shp.has_clr = lay[0][ATTR_CLR0] > 0
	return shp

static func _parse_material(s: PackedByteArray, o: int, version: int) -> Dictionary:
	var m := {name = Bin.cstr(s, o + Bin.u32(s, o + 0x08)), index = Bin.u32(s, o + 0x0C),
		translucent = Bin.u32(s, o + 0x10) >= 0x80000000,
		num_tex_gens = s[o + 0x14], num_chans = s[o + 0x15], num_tevs = s[o + 0x16],
		cull = Bin.u32(s, o + 0x18), light_set = Bin.s8(s, o + 0x1D), fog = Bin.s8(s, o + 0x1E)}
	var tev_offs := o + Bin.u32(s, o + 0x28)
	var num_tex := Bin.u32(s, o + 0x2C)
	var tex_offs := o + Bin.u32(s, o + 0x30)
	var eoh := 0x34 + (4 if version >= 0x0A else 0) + 4
	var r := new_regs()
	run_regs(r, s, o + Bin.u32(s, o + eoh), 32 + 128 + 64 + 160)
	run_regs(r, s, tev_offs + 0x20, 480)
	# samplers by texture map id
	var samplers := {}
	for i in num_tex:
		var t := tex_offs + i * 0x34
		var pn := Bin.u32(s, t + 4)
		samplers[Bin.u32(s, t + 0x10)] = {name = Bin.cstr(s, t + Bin.u32(s, t)), palette = Bin.cstr(s, t + pn) if pn != 0 else "",
			wrap_s = Bin.u32(s, t + 0x18), wrap_t = Bin.u32(s, t + 0x1C), min_filter = Bin.u32(s, t + 0x20), mag_filter = Bin.u32(s, t + 0x24)}
	m.samplers = samplers
	# texture coordinate generators (XF 0x1040 + i)
	var gens := {}
	for i in m.num_tex_gens:
		var v: int = r.xf.get(0x1040 + i, 0)
		var row := _bit(v, 7, 15) # 0 POS, 1 NRM, 2 COLOR, 5 = TEX0 ... 12 = TEX7
		var dv: int = r.xf.get(0x1050 + i, 0)
		gens[i] = {src = row - 5 if row >= 5 else -1, row = row, type = _bit(v, 4, 7), proj = _bit(v, 1, 1),
			post = _bit(dv, 0, 255), normalize = _bit(dv, 8, 1) == 1, matrix = "identity"}
	m.tex_gens = gens
	# texture SRT matrices
	var srt_flags := Bin.u32(s, o + eoh + 0x16C)
	var mode := Bin.s32(s, o + eoh + 0x170)
	var srt0 := o + eoh + 0x174
	var mtx0 := o + eoh + 0x214
	var mtxs := {}
	for i in 8:
		var fl := _bit(srt_flags, i * 4, 15)
		var sS := 1.0 if (fl & 2) else Bin.f32(s, srt0 + i * 0x14)
		var sT := 1.0 if (fl & 2) else Bin.f32(s, srt0 + i * 0x14 + 4)
		var rot := 0.0 if (fl & 4) else Bin.f32(s, srt0 + i * 0x14 + 8)
		var tS := 0.0 if (fl & 8) else Bin.f32(s, srt0 + i * 0x14 + 12)
		var tT := 0.0 if (fl & 8) else Bin.f32(s, srt0 + i * 0x14 + 16)
		var mo := mtx0 + i * 0x34
		var eff := []
		for k in 12:
			eff.append(Bin.f32(s, mo + 4 + k * 4))
		var tm := {m = tex_mtx(mode, sS, sT, rot, tS, tT), ref_camera = Bin.s8(s, mo), ref_light = Bin.s8(s, mo + 1),
			map_mode = Bin.s8(s, mo + 2), effect = eff}
		mtxs[i] = tm
		if gens.has(i):
			if tm.map_mode == 2:
				gens[i].matrix = "pnmtx" # projection: position in view space
			elif tm.map_mode == 1 or tm.map_mode == 3:
				gens[i].matrix = "nrmmtx" # environment: normal in view space
	m.tex_mtx = mtxs
	# material / ambient colours of the two lighting channels
	var lc := o + eoh + 0x3B4
	var mat_color := {}
	var amb_color := {}
	var chans := {}
	for i in 2:
		mat_color[i] = Color8(s[lc + 4], s[lc + 5], s[lc + 6], s[lc + 7])
		amb_color[i] = Color8(s[lc + 8], s[lc + 9], s[lc + 10], s[lc + 11])
		chans[i] = {color = _chan(Bin.u32(s, lc + 12)), alpha = _chan(Bin.u32(s, lc + 16))}
		lc += 0x14
	m.mat_color = mat_color
	m.amb_color = amb_color
	m.chans = chans
	# blending, alpha test, depth (pixel engine registers)
	var blend: int = r.bp.get(0x41, 0)
	m.blend = {on = _bit(blend, 0, 1) == 1, logic = _bit(blend, 1, 1) == 1, src = _bit(blend, 8, 7), dst = _bit(blend, 5, 7), sub = _bit(blend, 11, 1) == 1,
		color_update = _bit(blend, 3, 1) == 1, alpha_update = _bit(blend, 4, 1) == 1}
	var ac: int = r.bp.get(0xF3, 0)
	m.alpha_test = {ref0 = _bit(ac, 0, 255), ref1 = _bit(ac, 8, 255), comp0 = _bit(ac, 16, 7), comp1 = _bit(ac, 19, 7), op = _bit(ac, 22, 3)}
	var z: int = r.bp.get(0x40, 0)
	m.zmode = {test = _bit(z, 0, 1) == 1, func = _bit(z, 1, 7), write = _bit(z, 4, 1) == 1}
	# TEV colour registers (prev, c0, c1, c2) and constant colours (k0..k3)
	var reg_colors := []
	var konst := []
	for i in 8:
		var vl: int = r.kcolor.get(i * 2, 0)
		var vh: int = r.kcolor.get(i * 2 + 1, 0)
		var c := Color(_bit(vl, 0, 2047) / 255.0, _bit(vh, 12, 2047) / 255.0, _bit(vh, 0, 2047) / 255.0, _bit(vl, 12, 2047) / 255.0)
		if i < 4:
			reg_colors.append(c)
		else:
			konst.append(c)
	m.reg_colors = reg_colors
	m.konst = konst
	# TEV stages
	var tev := []
	for i in m.num_tevs:
		var order: int = r.bp.get(0x28 + i / 2, 0)
		var odd := i % 2 == 1
		var st := {tex_map = _bit(order, 12 if odd else 0, 7), tex_coord = _bit(order, 15 if odd else 3, 7),
			tex_on = _bit(order, 18 if odd else 6, 1) == 1, channel = _bit(order, 19 if odd else 7, 7)}
		var c: int = r.bp.get(0xC0 + i * 2, 0)
		st.cD = _bit(c, 0, 15); st.cC = _bit(c, 4, 15); st.cB = _bit(c, 8, 15); st.cA = _bit(c, 12, 15)
		st.c_bias = _bit(c, 16, 3); st.c_sub = _bit(c, 18, 1) == 1; st.c_clamp = _bit(c, 19, 1) == 1
		st.c_scale = _bit(c, 20, 3); st.c_reg = _bit(c, 22, 3)
		var a: int = r.bp.get(0xC1 + i * 2, 0)
		st.rswap = _bit(a, 0, 3); st.tswap = _bit(a, 2, 3)
		st.aD = _bit(a, 4, 7); st.aC = _bit(a, 7, 7); st.aB = _bit(a, 10, 7); st.aA = _bit(a, 13, 7)
		st.a_bias = _bit(a, 16, 3); st.a_sub = _bit(a, 18, 1) == 1; st.a_clamp = _bit(a, 19, 1) == 1
		st.a_scale = _bit(a, 20, 3); st.a_reg = _bit(a, 22, 3)
		var ks: int = r.bp.get(0xF6 + i / 2, 0)
		st.kc = _bit(ks, 14 if odd else 4, 31)
		st.ka = _bit(ks, 19 if odd else 9, 31)
		st.ras_swap = _swap(r, st.rswap)
		st.tex_swap = _swap(r, st.tswap)
		tev.append(st)
	m.tev = tev
	return m

static func _swap(r: Dictionary, n: int) -> Array:
	var rg: int = r.bp.get(0xF6 + n * 2, 0)
	var ba: int = r.bp.get(0xF6 + n * 2 + 1, 0)
	return [_bit(rg, 0, 3), _bit(rg, 2, 3), _bit(ba, 0, 3), _bit(ba, 2, 3)]

static func _chan(v: int) -> Dictionary:
	return {mat_vtx = _bit(v, 0, 1) == 1, light = _bit(v, 1, 1) == 1, mask = _bit(v, 2, 15) + _bit(v, 11, 15) * 16,
		amb_vtx = _bit(v, 6, 1) == 1, diffuse = _bit(v, 7, 3), attn = _bit(v, 9, 1) == 1}

static func _parse_node(s: PackedByteArray, o: int, node_base: int) -> Dictionary:
	var n := {name = Bin.cstr(s, o + Bin.u32(s, o + 0x08)), id = Bin.u32(s, o + 0x0C), mtx_id = Bin.u32(s, o + 0x10),
		flags = Bin.u32(s, o + 0x14), billboard = Bin.u32(s, o + 0x18),
		scale = Vector3(Bin.f32(s, o + 0x20), Bin.f32(s, o + 0x24), Bin.f32(s, o + 0x28)),
		rot = Vector3(Bin.f32(s, o + 0x2C), Bin.f32(s, o + 0x30), Bin.f32(s, o + 0x34)),
		trans = Vector3(Bin.f32(s, o + 0x38), Bin.f32(s, o + 0x3C), Bin.f32(s, o + 0x40))}
	n.visible = _bit(n.flags, 8, 1) == 1
	n.local = srt(n.scale, n.rot, n.trans)
	var to_parent := Bin.s32(s, o + 0x5C)
	n.parent = (o + to_parent - node_base) / 0xD0 if to_parent != 0 else -1
	n.bind = m34(s, o + 0x70)
	n.inv_bind = m34(s, o + 0xA0)
	return n

static func _parse_byte_code(s: PackedByteArray, o: int) -> Array:
	var ops := []
	var i := o
	while i < s.size():
		var op := s[i]
		if op == 0x01:
			break
		elif op == 0x00:
			i += 1
		elif op == 0x02:
			ops.append({op = "node", node = Bin.u16(s, i + 1), parent_mtx = Bin.u16(s, i + 3)}); i += 5
		elif op == 0x06:
			ops.append({op = "dup", to = Bin.u16(s, i + 1), from = Bin.u16(s, i + 3)}); i += 5
		elif op == 0x05:
			ops.append({op = "evp", mtx = Bin.u16(s, i + 1), node = Bin.u16(s, i + 3)}); i += 5
		elif op == 0x03:
			var dst := Bin.u16(s, i + 1)
			var n := s[i + 3]
			i += 4
			var blend := []
			for _k in n:
				blend.append({mtx = Bin.u16(s, i), w = Bin.f32(s, i + 2)})
				i += 6
			ops.append({op = "mix", dst = dst, blend = blend})
		elif op == 0x04:
			ops.append({op = "draw", mat = Bin.u16(s, i + 1), shp = Bin.u16(s, i + 3), node = Bin.u16(s, i + 5)}); i += 8
		else:
			break
	return ops

static func _parse_mdl0(s: PackedByteArray, o: int) -> Dictionary:
	assert(Bin.magic(s, o) == "MDL0")
	var version := Bin.u32(s, o + 8)
	var p := o + 0x10
	var dics := []
	var ndic := 11 + (2 if version >= 0x0A else 0)
	for k in ndic:
		var off := Bin.u32(s, p)
		dics.append(res_dic(s, o + off if off > 0 else 0))
		p += 4
	var byte_code: Array = dics[0]
	var nodes: Array = dics[1]
	var vpos: Array = dics[2]
	var vnrm: Array = dics[3]
	var vclr: Array = dics[4]
	var vtxc: Array = dics[5]
	var base := 8 if version >= 0x0A else 6
	var mats: Array = dics[base]
	var shps: Array = dics[base + 2]
	p += 4 if version >= 0x0B else 0
	var model := {name = Bin.cstr(s, o + Bin.u32(s, p)), version = version}
	var info := p + 4
	model.tex_mtx_mode = Bin.u32(s, info + 0x0C)
	var inputs := {pos = [], nrm = [], clr = [], txc = []}
	for e in vpos: inputs.pos.append(_parse_vtx_buffer(s, e.offs, "pos"))
	for e in vnrm: inputs.nrm.append(_parse_vtx_buffer(s, e.offs, "nrm"))
	for e in vclr: inputs.clr.append(_parse_vtx_buffer(s, e.offs, "clr"))
	for e in vtxc: inputs.txc.append(_parse_vtx_buffer(s, e.offs, "txc"))
	model.materials = []
	for e in mats: model.materials.append(_parse_material(s, e.offs, version))
	model.shapes = []
	for e in shps: model.shapes.append(_parse_shape(s, e.offs, inputs))
	model.nodes = []
	var node_base: int = nodes[0].offs if nodes.size() > 0 else 0
	for e in nodes: model.nodes.append(_parse_node(s, e.offs, node_base))
	model.code = {}
	for e in byte_code: model.code[e.name] = _parse_byte_code(s, e.offs)
	return model

# ---------------------------------------------------------------- SCN0 (scene: cameras)

## a float track: constant, or the first key of a hermite track (static scenes)
static func _track(s: PackedByteArray, o: int, constant: bool) -> float:
	if constant:
		return Bin.f32(s, o)
	var t := o + Bin.u32(s, o)
	if t + 12 < s.size() and Bin.u16(s, t) > 0:
		return Bin.f32(s, t + 8 + 4)
	return 0.0

static func _parse_scn0_camera(s: PackedByteArray, o: int) -> Dictionary:
	var flags := Bin.u32(s, o + 0x18)
	var c := func(b: int) -> bool: return _bit(flags, b, 1) == 1
	return {name = Bin.cstr(s, o + Bin.u32(s, o + 0x08)), ref_number = Bin.u32(s, o + 0x10),
		proj_type = Bin.u32(s, o + 0x14), camera_type = _bit(flags, 0, 1),
		pos = Vector3(_track(s, o + 0x20, c.call(17)), _track(s, o + 0x24, c.call(18)), _track(s, o + 0x28, c.call(19))),
		aspect = _track(s, o + 0x2C, c.call(20)), near = _track(s, o + 0x30, c.call(21)), far = _track(s, o + 0x34, c.call(22)),
		rot = Vector3(_track(s, o + 0x38, c.call(29)), _track(s, o + 0x3C, c.call(30)), _track(s, o + 0x40, c.call(31))),
		aim = Vector3(_track(s, o + 0x44, c.call(25)), _track(s, o + 0x48, c.call(26)), _track(s, o + 0x4C, c.call(27))),
		twist = _track(s, o + 0x50, c.call(28)), fovy = _track(s, o + 0x54, c.call(23)), ortho_height = _track(s, o + 0x58, c.call(24))}

static func _parse_scn0(s: PackedByteArray, o: int) -> Dictionary:
	var scn := {cameras = []}
	for e in res_dic(s, o + Bin.u32(s, o + 0x10)):
		if e.name == "Cameras(NW4R)":
			for c in res_dic(s, e.offs):
				scn.cameras.append(_parse_scn0_camera(s, c.offs))
	return scn

# ---------------------------------------------------------------- the archive

## parse a .brres: { models: name -> model, textures: name -> tex, palettes, groups, scenes }
static func parse(s: PackedByteArray) -> Dictionary:
	assert(Bin.magic(s, 0) == "bres", "not a BRRES file")
	var root_offs := Bin.u16(s, 0x0C)
	var out := {models = {}, textures = {}, palettes = {}, groups = {}, scenes = {}}
	for g in res_dic(s, root_offs + 8):
		var items := res_dic(s, g.offs)
		out.groups[g.name] = items
		if g.name == "Palettes(NW4R)":
			for e in items:
				out.palettes[e.name] = _parse_plt0(s, e.offs)
	for e in out.groups.get("Textures(NW4R)", []):
		var t := _parse_tex0(s, e.offs)
		t.palette = out.palettes.get(e.name)
		out.textures[e.name] = t
	for e in out.groups.get("3DModels(NW4R)", []):
		out.models[e.name] = _parse_mdl0(s, e.offs)
	for e in out.groups.get("AnmScn(NW4R)", []):
		out.scenes[e.name] = _parse_scn0(s, e.offs)
	return out

# ---------------------------------------------------------------- rest pose

## world matrices for every matrix id in the rest pose (node tree; envelopes at bind pose)
static func rest_matrices(model: Dictionary) -> Dictionary:
	var node_world := {}
	var mtx := {}
	for op in model.code.get("NodeTree", []):
		if op.op == "node":
			var n: Dictionary = model.nodes[op.node]
			var w: Transform3D = n.local
			if n.parent >= 0 and node_world.has(n.parent):
				w = node_world[n.parent] * n.local
			node_world[op.node] = w
			mtx[n.mtx_id] = w
		elif op.op == "dup":
			mtx[op.to] = mtx.get(op.from, Transform3D.IDENTITY)
	for op in model.code.get("NodeMix", []):
		if op.op == "evp":
			var n: Dictionary = model.nodes[op.node]
			mtx[op.mtx] = node_world.get(op.node, Transform3D.IDENTITY) * n.inv_bind
		elif op.op == "mix":
			mtx[op.dst] = Transform3D.IDENTITY
	return mtx
