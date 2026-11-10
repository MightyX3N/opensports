## Where the player's own files live: folders next to OpenSports.exe
##   rom/              the Wii Sports disc image (.wbfs or .iso)
##   packs/textures/   texture packs made for Dolphin (Load/Textures/<game ID>/...)
##   packs/addons/     add-ons
## When running from the source (the editor or tests), it is the project folder itself,
## or OPENSPORTS_HOME when set.
class_name Paths

static func home() -> String:
	var env := OS.get_environment("OPENSPORTS_HOME")
	if env != "":
		return env
	if OS.has_feature("editor") or not OS.has_feature("template"):
		return ProjectSettings.globalize_path("res://").get_base_dir() # the project folder itself
	return OS.get_executable_path().get_base_dir()

static func rom_dir() -> String: return home().path_join("rom")
static func packs_dir() -> String: return home().path_join("packs")
static func textures_dir() -> String: return packs_dir().path_join("textures")
static func addons_dir() -> String: return packs_dir().path_join("addons")

## make the folders so players can see where things go
static func ensure() -> void:
	for d in [rom_dir(), textures_dir(), addons_dir()]:
		DirAccess.make_dir_recursive_absolute(d)

## every file under a folder (recursive), as absolute paths
static func walk(dir: String, depth := 0, out := PackedStringArray()) -> PackedStringArray:
	if depth > 12:
		return out
	var d := DirAccess.open(dir)
	if d == null:
		return out
	d.include_hidden = false
	for f in d.get_files():
		out.append(dir.path_join(f))
	for sub in d.get_directories():
		walk(dir.path_join(sub), depth + 1, out)
	return out
