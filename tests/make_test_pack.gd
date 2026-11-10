## Makes a small texture pack laid out like Dolphin's Load/Textures from the disc in rom/:
## the alley's textures re-coloured at 4x size, named the way Dolphin names them (half of
## them under the other "_m" choice), plus a folder for another game that must be skipped.
##   OPENSPORTS_HOME=<home> godot --headless --path godot -s tests/make_test_pack.gd
extends SceneTree

func _init() -> void:
	var home := OS.get_environment("OPENSPORTS_HOME")
	var d: WiiDisc = null
	for p in Paths.walk(home.path_join("rom")):
		d = WiiDisc.open(p)
		if d.ok():
			break
	var arc := WiiArchive.open(d.read_file(d.find("Common/RPBowScene/common.carc", "/sports/")))
	var root := home.path_join("packs/textures/RSPE01/alley")
	DirAccess.make_dir_recursive_absolute(root)
	DirAccess.make_dir_recursive_absolute(home.path_join("packs/textures/RMGE01"))
	var n := 0
	var names := {}
	for f in ["/G3D/bwg_field.brres", "/G3D/bwg_Pin.brres", "/G3D/bwg_ball.brres"]:
		var b := Brres.parse(arc[f])
		for tn in b.textures:
			var t: Dictionary = b.textures[tn]
			var src := Image.create_from_data(t.w, t.h, false, Image.FORMAT_RGBA8, Brres.decode_texture(t))
			var big := Image.create(t.w * 4, t.h * 4, false, Image.FORMAT_RGBA8)
			for y in t.h * 4:
				for x in t.w * 4:
					var c := src.get_pixel(x / 4, y / 4)
					var grid := 0.25 if (x % 8 == 0 or y % 8 == 0) else 0.0
					big.set_pixel(x, y, Color(minf(1, c.r * 0.6 + 0.4), minf(1, c.g * 0.7 + grid), c.b * 0.5, c.a))
			var nm: String = TexName.names_for(t, (n % 2) == 0).exact
			if not names.has(nm):
				big.save_png(root.path_join(nm + ".png"))
				names[nm] = true
			n += 1
	Image.create(8, 8, false, Image.FORMAT_RGBA8).save_png(home.path_join("packs/textures/RMGE01/tex1_8x8_0123456789abcdef_1.png"))
	print("made %d files for %d textures" % [names.size(), n])
	quit(0)
