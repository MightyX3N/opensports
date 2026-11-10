## Headless tests: godot --headless --path godot -s tests/run_tests.gd
## (OPENSPORTS_TEST_DISC=<image> also checks reading a disc image)
extends SceneTree

var passes := 0
var fails := 0

func ok(cond: bool, what: String) -> void:
	if cond:
		passes += 1
	else:
		fails += 1
		print("FAIL: ", what)

func _init() -> void:
	test_archive()
	test_xxhash()
	test_rules()
	test_sim()
	var img := OS.get_environment("OPENSPORTS_TEST_DISC")
	if img != "":
		test_disc(img)
	print("%d passed, %d failed" % [passes, fails])
	quit(1 if fails > 0 else 0)

func be32(v: int) -> PackedByteArray:
	return PackedByteArray([(v >> 24) & 255, (v >> 16) & 255, (v >> 8) & 255, v & 255])

func test_archive() -> void:
	# Yaz0: 3 literals, a back-reference (distance 3, 6 bytes), 1 literal
	var body := PackedByteArray([0xE8]) + "abc".to_ascii_buffer() + PackedByteArray([0x40, 0x02]) + "X".to_ascii_buffer()
	var yaz := "Yaz0".to_ascii_buffer() + be32(10) + be32(0) + be32(0) + body
	ok(WiiArchive.yaz0(yaz).get_string_from_ascii() == "abcabcabcX", "Yaz0 literals and back-references")
	var yaz2 := "Yaz0".to_ascii_buffer() + be32(21) + be32(0) + be32(0) + PackedByteArray([0x80]) + "z".to_ascii_buffer() + PackedByteArray([0, 0, 20 - 0x12])
	ok(WiiArchive.yaz0(yaz2).get_string_from_ascii() == "z".repeat(21), "Yaz0 long run")
	# GX texture sizes and a CMPR block
	ok(GXTex.size(GXTex.CMPR, 64, 64) == 64 * 64 / 2 and GXTex.size(GXTex.RGBA8, 4, 4) == 64, "texture sizes")
	var sub := PackedByteArray([0xFF, 0xFF, 0, 0, 0, 0, 0, 0])
	var cm := GXTex.decode(GXTex.CMPR, sub + sub + sub + sub, 0, 8, 8)
	ok(cm[0] == 255 and cm[64 * 4 - 4] == 255, "CMPR decodes")
	var i4 := GXTex.decode(GXTex.I4, PackedByteArray([0xF0]) + PackedByteArray(range(31).map(func(_x): return 0)), 0, 8, 8)
	ok(i4[0] == 255 and i4[4] == 0, "I4 nibble order")

func test_xxhash() -> void:
	ok(XXHash64.hex(PackedByteArray()) == "ef46db3751d8e999", "XXH64 empty")
	ok(XXHash64.hex("abc".to_ascii_buffer()) == "44bc2cf5ad770999", "XXH64 abc")
	var b := PackedByteArray()
	for k in 3:
		for i in 256:
			b.append(i)
	ok(XXHash64.hex(b) == "8e03c838c596036f", "XXH64 long input")
	var d := PackedByteArray()
	for i in 32:
		d.append((i * 7) % 256)
	ok(XXHash64.hex("xx".to_ascii_buffer() + d + "yy".to_ascii_buffer(), 2, 32) == "91b0cb0931a8c629", "XXH64 slice")
	var tex := {w = 8, h = 4, fmt = GXTex.I8, mips = 1, src = "pad".to_ascii_buffer() + d, data_offs = 3, palette = null}
	var n := TexName.names_for(tex, false)
	ok(n.exact == "tex1_8x4_91b0cb0931a8c629_1", "texture name " + str(n.get("exact")))
	ok(TexName.names_for(tex, true).exact == "tex1_8x4_m_91b0cb0931a8c629_1", "mipmapped name")
	var pal := PackedByteArray()
	for i in 32:
		pal.append(i)
	var c4src := PackedByteArray()
	for i in 16:
		c4src.append_array([0x23, 0x45])
	var c4 := {w = 8, h = 8, fmt = GXTex.C4, mips = 1, src = c4src, data_offs = 0, palette = {data = pal, offset = 0, count = 16, fmt = 1}}
	var c := TexName.names_for(c4, false)
	ok(c.exact == "tex1_8x8_e308f512e568c015_6ac8c5a2eb076b8a_8", "palette texture name " + str(c.get("exact")))

func test_rules() -> void:
	var r := BowlingRules.new()
	for i in 12:
		r.record(10)
	ok(r.total() == 300 and r.over, "perfect game is 300")
	r = BowlingRules.new()
	for i in 21:
		r.record(5)
	ok(r.total() == 150 and r.over, "all fives with spares is 150")
	r = BowlingRules.new()
	r.record(3); r.record(4)
	ok(r.marks(1) == ["3", "4"] and r.total() == 7, "open frame")

func test_sim() -> void:
	var sim := BowlingSim.new(BowlingTuning.get_profile("arcade"))
	ok(sim.standing_count() == 10, "rack of ten")
	sim.throw({x = 0.06, angle = 0.0, speed = 8.0, hook = 0.0})
	var t0 := Time.get_ticks_msec()
	var left := sim.run_to_end()
	var ms := Time.get_ticks_msec() - t0
	print("  straight 8 m/s ball: %d standing, %.1f s simulated in %d ms" % [left, sim.t, ms])
	ok(left <= 6, "a straight ball into the pocket knocks pins down")
	ok(ms < sim.t * 1000.0 * 0.6, "the simulation runs faster than real time (%d ms for %.1f s)" % [ms, sim.t])
	sim = BowlingSim.new(BowlingTuning.get_profile("arcade"))
	sim.throw({x = 0.45, angle = -0.03, speed = 6.0, hook = 0.0})
	left = sim.run_to_end()
	ok(left == 10 and sim.gutter != 0, "gutter ball")

func test_disc(path: String) -> void:
	var t0 := Time.get_ticks_msec()
	var d := WiiDisc.open(path)
	ok(d.ok(), "disc opens: " + d.error)
	if not d.ok():
		return
	print("  %s %s, %d files (%d ms)" % [d.game_id, d.title, d.files.size(), Time.get_ticks_msec() - t0])
	var p := d.find("Common/RPBowScene/common.carc", "/sports/")
	ok(p != "", "bowling archive found")
	t0 = Time.get_ticks_msec()
	var arc := WiiArchive.open(d.read_file(p))
	print("  %s: %d files (%d ms)" % [p, arc.size(), Time.get_ticks_msec() - t0])
	ok(arc.has("/G3D/bwg_field.brres"), "alley model in the archive")
	t0 = Time.get_ticks_msec()
	var field := Brres.parse(arc["/G3D/bwg_field.brres"])
	print("  bwg_field: %d models, %d textures (%d ms)" % [field.models.size(), field.textures.size(), Time.get_ticks_msec() - t0])
	ok(field.models.has("bwg_field"), "alley model parsed")
	var names := 0
	for tn in field.textures:
		var n := TexName.names_for(field.textures[tn], false)
		if n.get("exact", "") != "":
			names += 1
	ok(names == field.textures.size(), "every texture gets a Dolphin name")
	var tex = field.textures.get("arrow_00")
	if tex != null:
		ok(TexName.names_for(tex, false).exact == "tex1_128x128_f24d8fe0188d32c2_3", "arrow texture matches Dolphin's name")
