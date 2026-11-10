## A plain log next to the game (opensports.log), so problems on a player's PC can be read.
class_name Log

static var _started := false

static func write(s: String) -> void:
	var path := Paths.home().path_join("opensports.log")
	var f: FileAccess
	if not _started:
		_started = true
		f = FileAccess.open(path, FileAccess.WRITE)
		if f:
			f.store_line("Open Sports %s · Godot %s · %s" % ["0.2", Engine.get_version_info().string, OS.get_name()])
	else:
		f = FileAccess.open(path, FileAccess.READ_WRITE)
		if f:
			f.seek_end()
	if f:
		f.store_line("%s  %s" % [Time.get_time_string_from_system(), s])
		f.close()
	print(s)
