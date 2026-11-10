## Reads files straight from the player's own Wii disc image: .iso (plain 1:1 image) and
## .wbfs (the USB-loader format). Follows Dolphin's DiscIO (GPL-2.0-or-later):
## WbfsBlob.cpp for the WBFS block table, VolumeWii.cpp for the partition table and the
## AES-encrypted 0x8000-byte clusters, FileSystemGCWii.cpp for the file table.
class_name WiiDisc
extends RefCounted

const WII_SECTOR_SIZE := 0x8000
const WII_SECTOR_COUNT := 143432 * 2
const BLOCK_HEADER_SIZE := 0x400
const BLOCK_DATA_SIZE := 0x7C00

## The Wii's common keys, as Dolphin has them (Core/IOS/IOSC.cpp): retail, Korean
const COMMON_KEYS := [
	[0xeb, 0xe4, 0x2a, 0x22, 0x5e, 0x85, 0x93, 0xe4, 0x48, 0xd9, 0xc5, 0x45, 0x73, 0x81, 0xaa, 0xf7],
	[0x63, 0xb8, 0x2b, 0xb4, 0xf4, 0x61, 0x4e, 0x2e, 0x13, 0xf2, 0xfe, 0xfb, 0xba, 0x4c, 0x9b, 0x7e],
]

var path := ""
var error := ""
var game_id := ""
var title := ""
var files := {} # path in the game's file system -> [partition offset, size]

var _f: FileAccess
var _wbfs := false
var _wbfs_shift := 0
var _wlba := PackedInt32Array()
var _part_data := 0 # where the game partition's encrypted data starts in the image
var _encrypted := true
var _key := PackedByteArray()
var _last_block := -1
var _last_data := PackedByteArray()

## open an image; check `error` afterwards ("" = fine)
static func open(p: String) -> WiiDisc:
	var d := WiiDisc.new()
	d.path = p
	d._open()
	return d

func _open() -> void:
	_f = FileAccess.open(path, FileAccess.READ)
	if _f == null:
		error = "could not open the file"
		return
	var head := _f.get_buffer(16)
	if head.size() >= 4 and head.slice(0, 4).get_string_from_ascii() == "WBFS":
		if not _open_wbfs():
			return
	var disc_head := raw_read(0, 0x100)
	if disc_head.size() < 0x100 or Bin.u32(disc_head, 0x18) != 0x5D1C9EA3:
		error = "not a Wii disc image"
		return
	game_id = disc_head.slice(0, 6).get_string_from_ascii()
	title = Bin.cstr(disc_head, 0x20)
	_has_hashes_and_encryption(disc_head)
	if not _find_game_partition():
		return
	_read_file_table()

func _has_hashes_and_encryption(h: PackedByteArray) -> void:
	_encrypted = h[0x61] == 0

## WBFS: a header, then a table that maps each block of the disc to a block in the file
func _open_wbfs() -> bool:
	_f.seek(0)
	var h := _f.get_buffer(12)
	var hd_shift := h[8]
	_wbfs_shift = h[9]
	var hd_size := 1 << hd_shift
	var wbfs_size := 1 << _wbfs_shift
	if wbfs_size < WII_SECTOR_SIZE:
		error = "unsupported WBFS file"
		return false
	_f.seek(12)
	if _f.get_8() == 0:
		error = "this WBFS file holds no game"
		return false
	var blocks := (WII_SECTOR_COUNT * WII_SECTOR_SIZE + wbfs_size - 1) / wbfs_size
	_f.seek(hd_size + 0x100)
	var t := _f.get_buffer(blocks * 2)
	_wlba.resize(blocks)
	for i in blocks:
		_wlba[i] = (t[i * 2] << 8) | t[i * 2 + 1]
	_wbfs = true
	return true

## bytes from the disc as the Wii sees it (before decryption)
func raw_read(off: int, n: int) -> PackedByteArray:
	if not _wbfs:
		_f.seek(off)
		return _f.get_buffer(n)
	var out := PackedByteArray()
	var size := 1 << _wbfs_shift
	while n > 0:
		var blk := off >> _wbfs_shift
		var inside := off & (size - 1)
		var take := mini(n, size - inside)
		var mapped := _wlba[blk] if blk < _wlba.size() else 0
		if mapped == 0:
			# a block the disc never uses (WBFS leaves it out): zeros
			var z := PackedByteArray()
			z.resize(take)
			out.append_array(z)
		else:
			_f.seek(mapped * size + inside)
			out.append_array(_f.get_buffer(take))
		off += take
		n -= take
	return out

func _find_game_partition() -> bool:
	var table := raw_read(0x40000, 32)
	for group in 4:
		var count := Bin.u32(table, group * 8)
		var tab_off := Bin.u32(table, group * 8 + 4) << 2
		if count == 0 or count > 64:
			continue
		var entries := raw_read(tab_off, count * 8)
		for i in count:
			var part_off := Bin.u32(entries, i * 8) << 2
			var kind := Bin.u32(entries, i * 8 + 4)
			if kind == 0: # the game itself (1 = update, 2 = channel)
				return _open_partition(part_off)
	error = "no game partition on the disc"
	return false

func _open_partition(part_off: int) -> bool:
	var ticket := raw_read(part_off, 0x2C0)
	var key_index := ticket[0x1F1]
	if key_index >= COMMON_KEYS.size():
		error = "unknown disc key"
		return false
	# the title key is encrypted with the common key; the IV is the title ID + 8 zero bytes
	var iv := ticket.slice(0x1DC, 0x1E4)
	iv.resize(16)
	var aes := AESContext.new()
	aes.start(AESContext.MODE_CBC_DECRYPT, PackedByteArray(COMMON_KEYS[key_index]), iv)
	_key = aes.update(ticket.slice(0x1BF, 0x1CF))
	aes.finish()
	_part_data = part_off + (Bin.u32(ticket, 0x2B8) << 2)
	return true

## bytes from inside the game partition (decrypted)
func read(off: int, n: int) -> PackedByteArray:
	var out := PackedByteArray()
	while n > 0:
		var blk := off / BLOCK_DATA_SIZE
		var inside := off % BLOCK_DATA_SIZE
		var take := mini(n, BLOCK_DATA_SIZE - inside)
		var data := _block(blk)
		out.append_array(data.slice(inside, inside + take))
		off += take
		n -= take
	return out

func _block(blk: int) -> PackedByteArray:
	if blk == _last_block:
		return _last_data
	var raw := raw_read(_part_data + blk * WII_SECTOR_SIZE, WII_SECTOR_SIZE)
	var data: PackedByteArray
	if _encrypted:
		var aes := AESContext.new()
		aes.start(AESContext.MODE_CBC_DECRYPT, _key, raw.slice(0x3D0, 0x3E0))
		data = aes.update(raw.slice(BLOCK_HEADER_SIZE, WII_SECTOR_SIZE))
		aes.finish()
	else:
		data = raw.slice(BLOCK_HEADER_SIZE, WII_SECTOR_SIZE)
	_last_block = blk
	_last_data = data
	return data

## the file system table (FST): every file's place in the partition
func _read_file_table() -> void:
	var boot := read(0, 0x440)
	var fst_off := Bin.u32(boot, 0x424) << 2
	var fst_size := Bin.u32(boot, 0x428) << 2
	if fst_size <= 0 or fst_size > 64 * 1024 * 1024:
		error = "could not read the disc (wrong key or damaged image)"
		return
	var fst := read(fst_off, fst_size)
	var total := Bin.u32(fst, 8)
	if total <= 0 or total * 12 > fst.size():
		error = "could not read the disc's file table"
		return
	var names := total * 12
	var stack := [[total, ""]]
	for i in range(1, total):
		while stack.size() > 1 and i >= stack[-1][0]:
			stack.pop_back()
		var o := i * 12
		var is_dir := fst[o] == 1
		var name := Bin.cstr(fst, names + Bin.u24(fst, o + 1))
		var full: String = stack[-1][1] + "/" + name
		if is_dir:
			stack.append([Bin.u32(fst, o + 8), full])
		else:
			files[full] = [Bin.u32(fst, o + 4) << 2, Bin.u32(fst, o + 8)]

func ok() -> bool:
	return error == "" and not files.is_empty()

func has_file(p: String) -> bool:
	return files.has(p)

func read_file(p: String) -> PackedByteArray:
	var e = files.get(p)
	if e == null:
		return PackedByteArray()
	return read(e[0], e[1])

## the first file whose path ends with `suffix`, preferring paths that contain `prefer`
func find(suffix: String, prefer := "") -> String:
	var best := ""
	for p in files:
		if p.ends_with(suffix) and (best == "" or (prefer != "" and p.contains(prefer) and not best.contains(prefer))):
			best = p
	return best
