## The names Dolphin gives a Wii texture when it dumps it, and so the names custom texture
## packs use: tex1_{width}x{height}[_m]_{texture hash}[_{palette hash}]_{format}
## (Dolphin's VideoCommon/TextureInfo.cpp, CalculateTextureName). The texture hash is XXH64
## of the top level's bytes; for palette formats the palette hash covers only the palette
## entries the texture actually uses.
class_name TexName

## tex = a TEX0 from wii/brres.gd; returns { exact, wild_tlut, wild_tex } or {}
static func names_for(tex: Dictionary, mipmapped: bool) -> Dictionary:
	var size := GXTex.size(tex.fmt, tex.w, tex.h)
	var s: PackedByteArray = tex.src
	var o: int = tex.data_offs
	if o + size > s.size():
		return {}
	var tex_hash := XXHash64.hex(s, o, size)
	var tlut_hash := ""
	var pal = tex.palette
	if pal != null and (tex.fmt == GXTex.C4 or tex.fmt == GXTex.C8 or tex.fmt == GXTex.C14X2):
		var lo := 0xFFFF
		var hi := 0
		if tex.fmt == GXTex.C4:
			for i in range(o, o + size):
				var b := s[i]
				lo = mini(lo, mini(b & 15, b >> 4))
				hi = maxi(hi, maxi(b & 15, b >> 4))
		elif tex.fmt == GXTex.C8:
			for i in range(o, o + size):
				lo = mini(lo, s[i])
				hi = maxi(hi, s[i])
		else:
			# Dolphin byte-swaps a single byte here (Common::swap16(m_data[i])): only the low 6
			# bits of each even byte count, shifted up 8. Copied as is so the names match.
			for i in range(o, o + size, 2):
				var v := (s[i] << 8) & 0x3FFF
				lo = mini(lo, v)
				hi = maxi(hi, v)
		var pd: PackedByteArray = pal.data
		var off: int = pal.offset + 2 * lo
		var n := 2 * (hi + 1 - lo)
		if off + n > pd.size():
			n = maxi(0, pd.size() - off)
		tlut_hash = XXHash64.hex(pd, off, n)
	var base := "tex1_%dx%d%s" % [tex.w, tex.h, "_m" if mipmapped else ""]
	var tlut_part := ("_" + tlut_hash) if tlut_hash != "" else ""
	return {
		exact = "%s_%s%s_%d" % [base, tex_hash, tlut_part, tex.fmt],
		wild_tlut = ("%s_%s_$_%d" % [base, tex_hash, tex.fmt]) if tlut_hash != "" else "",
		wild_tex = "%s_$%s_%d" % [base, tlut_part, tex.fmt],
	}

## names to look for, most specific first (as Dolphin searches), with and without "_m",
## the predicted one first (whether the game turns mipmaps on is set at run time)
static func candidates(tex: Dictionary, mipmapped: bool) -> PackedStringArray:
	var out := PackedStringArray()
	for m in [mipmapped, not mipmapped]:
		var n := names_for(tex, m)
		if n.is_empty():
			continue
		out.append(n.exact)
		if n.wild_tlut != "":
			out.append(n.wild_tlut)
		out.append(n.wild_tex)
	return out
