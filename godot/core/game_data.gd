## The player's own Wii Sports disc, read straight from the image in rom/ (no extracting).
## Nothing from the disc ships with the game; without it everything uses our own assets.
## Works with any region and with the Wii Sports + Wii Sports Resort disc: files are found
## by the end of their path inside the game's file system.
extends Node

## Wii Sports in every region, and the Wii Sports + Wii Sports Resort disc
const GAME_IDS := ["RSP", "SP2"]
## what we use, by the end of its path on the disc
const FILES := {
	bow_common = "Common/RPBowScene/common.carc",
}

var disc: WiiDisc
var status := "" # what the settings page shows
var _archives := {}

func _ready() -> void:
	Paths.ensure()
	scan()

## look in rom/ for a Wii Sports disc image
func scan() -> void:
	disc = null
	_archives.clear()
	var found := PackedStringArray()
	for p in Paths.walk(Paths.rom_dir()):
		var ext := p.get_extension().to_lower()
		if ext in ["wbfs", "iso"]:
			found.append(p)
		elif ext in ["rvz", "wia", "gcz", "ciso", "nkit"]:
			status = "%s isn't supported yet: use a .wbfs or .iso" % p.get_file()
	if found.is_empty():
		Log.write("disc: no image in " + Paths.rom_dir())
		if status == "":
			status = "No disc in the rom folder"
		return
	for p in found:
		var d := WiiDisc.open(p)
		if not d.ok():
			status = "%s: %s" % [p.get_file(), d.error if d.error != "" else "unreadable"]
			Log.write("disc: " + status)
			continue
		if not d.game_id.substr(0, 3) in GAME_IDS:
			status = "%s is %s, not Wii Sports" % [p.get_file(), d.title]
			continue
		disc = d
		status = "%s (%s)" % [d.title, d.game_id]
		Log.write("disc: %s, %d files, from %s" % [status, d.files.size(), p])
		return

func available() -> bool:
	return disc != null and Settings.get_value("real_look")

## a file from the disc by the end of its path, preferring the Wii Sports copy
func read(key: String) -> PackedByteArray:
	if disc == null:
		return PackedByteArray()
	var p := disc.find(FILES[key], "/sports/")
	return disc.read_file(p) if p != "" else PackedByteArray()

## U8 archives, decompressed once and kept
func archive(key: String) -> Dictionary:
	if _archives.has(key):
		return _archives[key]
	var data := read(key)
	if data.is_empty():
		return {}
	var files := WiiArchive.open(data)
	_archives[key] = files
	return files
