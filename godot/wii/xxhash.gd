## XXH64 (Yann Collet's xxHash, 64-bit, BSD-2): the hash Dolphin names custom textures with,
## so texture packs made for Dolphin find the same textures here. GDScript ints are 64-bit
## and wrap on overflow; right shifts are made logical by masking.
class_name XXHash64

const P1 := (0x9E3779B1 << 32) | 0x85EBCA87
const P2 := (0xC2B2AE3D << 32) | 0x27D4EB4F
const P3 := (0x165667B1 << 32) | 0x9E3779F9
const P4 := (0x85EBCA77 << 32) | 0xC2B2AE63
const P5 := (0x27D4EB2F << 32) | 0x165667C5

static func _shr(x: int, n: int) -> int:
	return (x >> n) & ((1 << (64 - n)) - 1)

static func _rol(x: int, r: int) -> int:
	return (x << r) | _shr(x, 64 - r)

static func _round(acc: int, input: int) -> int:
	acc = acc + input * P2
	acc = _rol(acc, 31)
	return acc * P1

static func _merge(acc: int, v: int) -> int:
	acc = acc ^ _round(0, v)
	return acc * P1 + P4

## hash `n` bytes of `s` from `off`
static func digest(s: PackedByteArray, off := 0, n := -1, seed := 0) -> int:
	if n < 0:
		n = s.size() - off
	var p := off
	var end := off + n
	var h := 0
	if n >= 32:
		var v1 := seed + P1 + P2
		var v2 := seed + P2
		var v3 := seed
		var v4 := seed - P1
		var limit := end - 32
		while p <= limit:
			v1 = _round(v1, s.decode_s64(p))
			v2 = _round(v2, s.decode_s64(p + 8))
			v3 = _round(v3, s.decode_s64(p + 16))
			v4 = _round(v4, s.decode_s64(p + 24))
			p += 32
		h = _rol(v1, 1) + _rol(v2, 7) + _rol(v3, 12) + _rol(v4, 18)
		h = _merge(h, v1); h = _merge(h, v2); h = _merge(h, v3); h = _merge(h, v4)
	else:
		h = seed + P5
	h += n
	while p + 8 <= end:
		h = h ^ _round(0, s.decode_s64(p))
		h = _rol(h, 27) * P1 + P4
		p += 8
	if p + 4 <= end:
		h = h ^ (s.decode_u32(p) * P1)
		h = _rol(h, 23) * P2 + P3
		p += 4
	while p < end:
		h = h ^ (s[p] * P5)
		h = _rol(h, 11) * P1
		p += 1
	h = h ^ _shr(h, 33); h = h * P2
	h = h ^ _shr(h, 29); h = h * P3
	h = h ^ _shr(h, 32)
	return h

## 16 lower-case hex digits, as Dolphin writes it into file names
static func hex(s: PackedByteArray, off := 0, n := -1) -> String:
	var h := digest(s, off, n)
	return "%08x%08x" % [_shr(h, 32), h & 0xFFFFFFFF]
