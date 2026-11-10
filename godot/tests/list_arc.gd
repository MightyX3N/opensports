extends SceneTree
func _init() -> void:
	for path in OS.get_cmdline_user_args():
		var f := FileAccess.get_file_as_bytes(path)
		var files := WiiArchive.open(f)
		print("== ", path)
		for k in files.keys():
			var d: PackedByteArray = files[k]
			print("  ", k, "  ", d.size())
			if k.ends_with(".brres"):
				var b := Brres.parse(d)
				for sec in b.keys():
					if b[sec] is Dictionary:
						for n in b[sec].keys():
							var extra := ""
							if sec == "models":
								var m: Dictionary = b[sec][n]
								extra = " shapes=%d mats=%d" % [m.get("shapes", []).size(), m.get("materials", []).size()]
								var mn := []
								for mt in m.get("materials", []):
									mn.append(mt.get("name", ""))
								extra += " " + str(mn)
							print("     ", sec, ": ", n, extra)
	quit()
