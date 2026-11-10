## Player settings, saved in the save folder (settings.cfg)
extends Node

const FILE := "user://settings.cfg"
const DEFAULTS := {
	fullscreen = false,
	quality = "high",      # "high" = smooth edges (MSAA), "low" = faster
	volume = "high",       # "high", "medium", "low", "off"
	swing = "normal",      # swing strength needed for a fast ball: "light", "normal", "strong"
	aim_line = true,       # dotted aim guide on the lane
	physics = "arcade",
	texture_pack = true,   # use texture packs in packs/textures
	upscale = "off",       # enlarge the disc's own textures with xBRZ: "off", "2x", "4x"
	real_look = true,      # use the Wii Sports disc in rom/ when it's there
}
const CHOICES := {
	fullscreen = [false, true],
	quality = ["high", "low"],
	volume = ["high", "medium", "low", "off"],
	swing = ["light", "normal", "strong"],
	aim_line = [true, false],
	texture_pack = [true, false],
	upscale = ["off", "2x", "4x"],
	real_look = [true, false],
}

signal changed(key: String, value)

var data := {}

func _ready() -> void:
	load_file()

func load_file() -> void:
	data = DEFAULTS.duplicate()
	var cf := ConfigFile.new()
	if cf.load(FILE) == OK:
		for k in DEFAULTS:
			if cf.has_section_key("settings", k):
				data[k] = cf.get_value("settings", k)

func save_file() -> void:
	var cf := ConfigFile.new()
	for k in data:
		cf.set_value("settings", k, data[k])
	cf.save(FILE)

func get_value(k: String):
	return data.get(k, DEFAULTS.get(k))

func set_value(k: String, v) -> void:
	data[k] = v
	save_file()
	changed.emit(k, v)

## step a setting to its next (dir = 1) or previous (-1) choice; returns the new value
func cycle(k: String, dir := 1):
	var list: Array = CHOICES[k]
	var i := maxi(0, list.find(get_value(k)))
	i = posmod(i + dir, list.size())
	set_value(k, list[i])
	return list[i]
