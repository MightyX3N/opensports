## Custom texture packs made for Dolphin (HD or AI-upscaled packs for Wii Sports): put the
## pack's folder in packs/textures/. Its tex1_*.png / tex1_*.dds files are used in place of
## the game's own textures, matched by the names Dolphin uses (wii/texname.gd). Subfolders
## are fine, as in Dolphin; folders named for other games are skipped. Read in place: nothing
## is copied.
class_name TexturePacks

## Game IDs of the discs that hold Wii Sports
const OURS := ["RSP", "SP2"]

static var _index = null # name (no extension, "_arb" taken out) -> absolute path
static var _images := {}
static var count := 0

static func enabled() -> bool:
	return Settings.get_value("texture_pack")

## a folder named like another game's ID (RSPE01 is ours, RMGE01 isn't)
static func _other_game(dir_name: String) -> bool:
	if dir_name.length() != 6:
		return false
	var re := RegEx.create_from_string("^[A-Z][A-Z0-9]{2}[A-Z][A-Z0-9]{2}$")
	return re.search(dir_name) != null and not dir_name.substr(0, 3) in OURS

static func _walk(dir: String, depth: int, out: Dictionary) -> void:
	if depth > 12:
		return
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		var ext := f.get_extension().to_lower()
		if f.begins_with("tex1_") and (ext == "png" or ext == "dds"):
			var key := f.get_basename()
			var arb := key.find("_arb")
			if arb >= 0:
				key = key.substr(0, arb) + key.substr(arb + 4)
			# the first one found wins, as in Dolphin; mipmap levels (_mip1…) are made by the GPU
			if not key.contains("_mip") and not out.has(key):
				out[key] = dir.path_join(f)
	var subs := d.get_directories()
	subs.sort()
	for sub in subs:
		if not _other_game(sub):
			_walk(dir.path_join(sub), depth + 1, out)

static func index() -> Dictionary:
	if _index == null:
		var idx := {}
		_walk(Paths.textures_dir(), 0, idx)
		_index = idx
		count = idx.size()
	return _index

static func reset() -> void:
	_index = null
	_images.clear()

static func _load(path: String) -> Texture2D:
	if _images.has(path):
		return _images[path]
	var img := Image.load_from_file(path)
	var tex: Texture2D = null
	if img != null and not img.is_empty():
		if not img.is_compressed() and not img.has_mipmaps():
			img.generate_mipmaps()
		tex = ImageTexture.create_from_image(img)
	else:
		push_warning("texture pack: could not load " + path)
	_images[path] = tex
	return tex

## the pack's texture for a TEX0 (wii/brres.gd), or null
static func find(tex: Dictionary, mipmapped: bool) -> Texture2D:
	var idx := index()
	if idx.is_empty():
		return null
	for n in TexName.candidates(tex, mipmapped):
		if idx.has(n):
			return _load(idx[n])
	return null
