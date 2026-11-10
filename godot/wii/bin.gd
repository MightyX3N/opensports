## Big-endian readers over a PackedByteArray (Wii data is big-endian). Offsets are 0-based.
class_name Bin

static func u8(b: PackedByteArray, o: int) -> int:
	return b[o]

static func s8(b: PackedByteArray, o: int) -> int:
	var v := b[o]
	return v - 256 if v >= 128 else v

static func u16(b: PackedByteArray, o: int) -> int:
	return (b[o] << 8) | b[o + 1]

static func s16(b: PackedByteArray, o: int) -> int:
	var v := (b[o] << 8) | b[o + 1]
	return v - 65536 if v >= 32768 else v

static func u24(b: PackedByteArray, o: int) -> int:
	return (b[o] << 16) | (b[o + 1] << 8) | b[o + 2]

static func u32(b: PackedByteArray, o: int) -> int:
	return (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3]

static func s32(b: PackedByteArray, o: int) -> int:
	var v := u32(b, o)
	return v - 4294967296 if v >= 2147483648 else v

static func f32(b: PackedByteArray, o: int) -> float:
	var t := PackedByteArray([b[o + 3], b[o + 2], b[o + 1], b[o]])
	return t.decode_float(0)

## zero-terminated string at o
static func cstr(b: PackedByteArray, o: int) -> String:
	var e := o
	var n := b.size()
	while e < n and b[e] != 0:
		e += 1
	return b.slice(o, e).get_string_from_ascii()

static func magic(b: PackedByteArray, o: int) -> String:
	return b.slice(o, o + 4).get_string_from_ascii()
