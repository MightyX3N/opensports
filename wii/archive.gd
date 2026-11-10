## Nintendo archive formats: Yaz0 compression and U8 archives (.carc / .arc / .szs).
## Layouts as documented on wiki.tockdom.com and implemented in noclip.website (MIT).
class_name WiiArchive

## Yaz0: run-length / back-reference compression
static func yaz0(s: PackedByteArray) -> PackedByteArray:
	assert(Bin.magic(s, 0) == "Yaz0", "not Yaz0 data")
	var size := Bin.u32(s, 4)
	var out := PackedByteArray()
	out.resize(size)
	var si := 16
	var di := 0
	while di < size:
		var code := s[si]
		si += 1
		for _k in 8:
			if di >= size:
				break
			if code & 0x80:
				out[di] = s[si]
				di += 1
				si += 1
			else:
				var b1 := s[si]
				var b2 := s[si + 1]
				si += 2
				var dist := ((b1 & 15) << 8 | b2) + 1
				var n := b1 >> 4
				if n == 0:
					n = s[si] + 0x12
					si += 1
				else:
					n += 2
				var from := di - dist
				if dist >= n:
					# no overlap: copy a slice at once
					var end_ := mini(di + n, size)
					var chunk := out.slice(from, from + (end_ - di))
					for k in chunk.size():
						out[di + k] = chunk[k]
					di = end_
				else:
					for k in n:
						if di >= size:
							break
						out[di] = out[from + k]
						di += 1
			code = (code << 1) & 0xFF
	return out

## U8 archive: returns { path: PackedByteArray } with paths like "/G3D/bwg_field.brres"
static func u8(s: PackedByteArray) -> Dictionary:
	assert(s[0] == 0x55 and s[1] == 0xAA and s[2] == 0x38 and s[3] == 0x2D, "not a U8 archive")
	var root := Bin.u32(s, 4)
	var total := Bin.u32(s, root + 8)
	var strtab := root + total * 12
	var files := {}
	var stack := [[total, ""]]
	for i in range(1, total):
		while stack.size() > 1 and i >= stack[-1][0]:
			stack.pop_back()
		var o := root + i * 12
		var t := s[o]
		var name_off := Bin.u24(s, o + 1)
		var a := Bin.u32(s, o + 4)
		var b := Bin.u32(s, o + 8)
		var path: String = stack[-1][1] + "/" + Bin.cstr(s, strtab + name_off)
		if t == 1:
			stack.append([b, path])
		else:
			files[path] = s.slice(a, a + b)
	return files

## decompress if needed, then list the files
static func open(data: PackedByteArray) -> Dictionary:
	if data.size() >= 4 and Bin.magic(data, 0) == "Yaz0":
		data = yaz0(data)
	return u8(data)
