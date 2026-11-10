## Wii (GX) texture decoding to RGBA8 bytes. Ported from noclip.website's
## rust/src/gx_texture.rs (MIT): the tiled formats I4, I8, IA4, IA8, RGB565, RGB5A3, RGBA8,
## CMPR and the palette formats C4, C8, C14X2.
class_name GXTex

const I4 := 0
const I8 := 1
const IA4 := 2
const IA8 := 3
const RGB565 := 4
const RGB5A3 := 5
const RGBA8 := 6
const C4 := 8
const C8 := 9
const C14X2 := 10
const CMPR := 14

## block size in texels for each format
const BLOCK := {0: [8, 8], 1: [8, 4], 2: [8, 4], 3: [4, 4], 4: [4, 4], 5: [4, 4], 6: [4, 4],
	8: [8, 8], 9: [8, 4], 10: [4, 4], 14: [8, 8]}

## size in bytes of one level (whole 32-byte blocks)
static func size(fmt: int, w: int, h: int) -> int:
	var b: Array = BLOCK.get(fmt, [4, 4])
	var nx := (w + b[0] - 1) / b[0]
	var ny := (h + b[1] - 1) / b[1]
	return nx * ny * (64 if fmt == RGBA8 else 32)

static func x5(v: int) -> int: return (v << 3) | (v >> 2)
static func x6(v: int) -> int: return (v << 2) | (v >> 4)
static func x3(v: int) -> int: return (v << 5) | (v << 2) | (v >> 1)

static func rgb565(p: int) -> Array:
	return [x5((p >> 11) & 31), x6((p >> 5) & 63), x5(p & 31), 255]

static func rgb5a3(p: int) -> Array:
	if p & 0x8000:
		return [x5((p >> 10) & 31), x5((p >> 5) & 31), x5(p & 31), 255]
	return [((p >> 8) & 15) * 17, ((p >> 4) & 15) * 17, (p & 15) * 17, x3((p >> 12) & 7)]

static func palette(pfmt: int, s: PackedByteArray, o: int, count: int) -> Array:
	var pal := []
	pal.resize(count)
	for i in count:
		var p := (s[o + i * 2] << 8) | s[o + i * 2 + 1] if o + i * 2 + 1 < s.size() else 0
		if pfmt == 0:
			pal[i] = [p & 255, p & 255, p & 255, p >> 8]
		elif pfmt == 1:
			pal[i] = rgb565(p)
		else:
			pal[i] = rgb5a3(p)
	return pal

## decode one level at byte offset o; pal = { fmt, data, offset, count } for palette formats
static func decode(fmt: int, s: PackedByteArray, o: int, w: int, h: int, pal_info = null) -> PackedByteArray:
	var px := PackedByteArray()
	px.resize(w * h * 4)
	var pal := []
	if pal_info != null:
		pal = palette(pal_info.fmt, pal_info.data, pal_info.offset, pal_info.count)
	if fmt == RGBA8:
		var so := o
		for yy in range(0, h, 4):
			for xx in range(0, w, 4):
				for y in 4:
					for x in 4:
						if xx + x < w and yy + y < h:
							var d := ((yy + y) * w + xx + x) * 4
							px[d + 3] = s[so]
							px[d] = s[so + 1]
						so += 2
				for y in 4:
					for x in 4:
						if xx + x < w and yy + y < h:
							var d := ((yy + y) * w + xx + x) * 4
							px[d + 1] = s[so]
							px[d + 2] = s[so + 1]
						so += 2
	elif fmt == CMPR:
		var so := o
		for yy in range(0, h, 8):
			for xx in range(0, w, 8):
				for yb in [0, 4]:
					for xb in [0, 4]:
						var c1 := (s[so] << 8) | s[so + 1]
						var c2 := (s[so + 2] << 8) | s[so + 3]
						var a := rgb565(c1)
						var b := rgb565(c2)
						var t := [a, b, null, null]
						if c1 > c2:
							t[2] = [(b[0] * 3 + a[0] * 5) >> 3, (b[1] * 3 + a[1] * 5) >> 3, (b[2] * 3 + a[2] * 5) >> 3, 255]
							t[3] = [(a[0] * 3 + b[0] * 5) >> 3, (a[1] * 3 + b[1] * 5) >> 3, (a[2] * 3 + b[2] * 5) >> 3, 255]
						else:
							t[2] = [(a[0] + b[0]) >> 1, (a[1] + b[1]) >> 1, (a[2] + b[2]) >> 1, 255]
							t[3] = [t[2][0], t[2][1], t[2][2], 0]
						for y in 4:
							var bits := s[so + 4 + y]
							var Y: int = yy + yb + y
							for x in 4:
								var X: int = xx + xb + x
								if X < w and Y < h:
									var c: Array = t[(bits >> 6) & 3]
									var d := (Y * w + X) * 4
									px[d] = c[0]
									px[d + 1] = c[1]
									px[d + 2] = c[2]
									px[d + 3] = c[3]
								bits = (bits << 2) & 255
						so += 8
	else:
		var b: Array = BLOCK[fmt]
		var bw: int = b[0]
		var bh: int = b[1]
		var idx := 0
		for yy in range(0, h, bh):
			for xx in range(0, w, bw):
				for y in bh:
					for x in bw:
						var X: int = xx + x
						var Y: int = yy + y
						if X < w and Y < h:
							var r := 0
							var g := 0
							var bb := 0
							var a := 0
							match fmt:
								I4, C4:
									var v := s[o + (idx >> 1)]
									var n := (v & 15) if (idx & 1) else (v >> 4)
									if fmt == I4:
										r = n * 17; g = r; bb = r; a = r
									else:
										var c: Array = pal[n] if n < pal.size() else [0, 0, 0, 0]
										r = c[0]; g = c[1]; bb = c[2]; a = c[3]
								I8:
									r = s[o + idx]; g = r; bb = r; a = r
								C8:
									var n := s[o + idx]
									var c: Array = pal[n] if n < pal.size() else [0, 0, 0, 0]
									r = c[0]; g = c[1]; bb = c[2]; a = c[3]
								IA4:
									var v := s[o + idx]
									r = (v & 15) * 17; g = r; bb = r; a = (v >> 4) * 17
								IA8:
									a = s[o + idx * 2]; r = s[o + idx * 2 + 1]; g = r; bb = r
								RGB565:
									var c := rgb565((s[o + idx * 2] << 8) | s[o + idx * 2 + 1])
									r = c[0]; g = c[1]; bb = c[2]; a = c[3]
								RGB5A3:
									var c := rgb5a3((s[o + idx * 2] << 8) | s[o + idx * 2 + 1])
									r = c[0]; g = c[1]; bb = c[2]; a = c[3]
								C14X2:
									var n := ((s[o + idx * 2] << 8) | s[o + idx * 2 + 1]) & 0x3FFF
									var c: Array = pal[n] if n < pal.size() else [0, 0, 0, 0]
									r = c[0]; g = c[1]; bb = c[2]; a = c[3]
							var d := (Y * w + X) * 4
							px[d] = r
							px[d + 1] = g
							px[d + 2] = bb
							px[d + 3] = a
						idx += 1
	return px
