## Headless tests: godot --headless --path godot res://tests/run_tests.tscn
## (OPENSPORTS_TEST_DISC=<image> also checks reading a disc image)
extends Node

var passes := 0
var fails := 0

func ok(cond: bool, what: String) -> void:
	if cond:
		passes += 1
	else:
		fails += 1
		print("FAIL: ", what)

func _ready() -> void:
	test_archive()
	test_xxhash()
	test_rules()
	test_sim()
	test_jc2_log()
	test_swings()
	var img := OS.get_environment("OPENSPORTS_TEST_DISC")
	if img != "":
		test_disc(img)
	print("%d passed, %d failed" % [passes, fails])
	get_tree().quit(1 if fails > 0 else 0)

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

## a real Joy-Con 2 (R) recording through the same decode + fusion the game uses: level at
## rest, ~4 s rolled a quarter turn left and held, ~6.5 s back, ~7 s nose up to the ceiling
func test_jc2_log() -> void:
	var c = Inputs.Ctrl.new()
	var prev_ts := -1
	var at := []
	for line in FileAccess.get_file_as_string("res://tests/data/jc2-right-ceiling-twist.txt").split("\n"):
		if line == "" or line.begins_with("#"):
			continue
		var parts := line.split(" ", false)
		var h := PackedByteArray()
		var hex: String = parts[2]
		for i in hex.length() / 2:
			h.append(hex.substr(i * 2, 2).hex_to_int())
		var ga := JoyCon2.to_game(Vector3(JoyCon2._s16(h, 0x36), JoyCon2._s16(h, 0x38), JoyCon2._s16(h, 0x3A)),
			Vector3(JoyCon2._s16(h, 0x30), JoyCon2._s16(h, 0x32), JoyCon2._s16(h, 0x34)))
		var ts := JoyCon2._u32(h, 0x2A)
		var dt := (ts - prev_ts) / 1e6 if prev_ts >= 0 else 0.03
		prev_ts = ts
		c.feed(dt, ga[0], ga[1])
		at.append([float(parts[0]), c.orient])
	var angles_at := func(t: float) -> Vector3:
		var best = at[0]
		for v in at:
			if absf(v[0] - t) < absf(best[0] - t):
				best = v
		var a: Vector3 = Inputs.angles(best[1])
		return Vector3(rad_to_deg(a.x), rad_to_deg(a.y), rad_to_deg(a.z))
	var a0: Vector3 = angles_at.call(1.0)
	ok(absf(a0.y) < 20 and absf(a0.z) < 20, "Joy-Con 2: start roughly level (%s)" % a0)
	var a1: Vector3 = angles_at.call(5.0)
	ok(a1.z < -65 and absf(a1.y) < 25, "Joy-Con 2: quarter roll left (%s)" % a1)
	var a2: Vector3 = angles_at.call(7.0)
	ok(absf(a2.z) < 20 and absf(a2.y) < 25, "Joy-Con 2: back to level (%s)" % a2)
	var a3: Vector3 = angles_at.call(9.5)
	ok(a3.y > 75, "Joy-Con 2: nose to the ceiling (%s)" % a3)

## real Joy-Con 2 swings from the game's throw log, replayed through the throw reader: each
## must come out as a throw with the power and spin the original read
func test_swings() -> void:
	var swings := []
	var cur = null
	for line in FileAccess.get_file_as_string("res://tests/data/throwlog-jc2.txt").split("\n"):
		if line.begins_with("throw "):
			var info := {}
			for kv in line.split(" "):
				if kv.contains("="):
					var p := kv.split("=")
					info[p[0]] = p[1]
			cur = {info = info, samples = []}
			swings.append(cur)
		elif cur != null and line.strip_edges() != "":
			var f := line.strip_edges().split(" ", false)
			cur.samples.append({t = float(f[0]), gyro = Vector3(float(f[2]), float(f[3]), float(f[4])),
				orient = Quaternion(float(f[7]), float(f[8]), float(f[9]), float(f[6]))})
	var good := 0
	var tested := 0
	for sw in swings:
		if sw.samples.size() < 5 or not sw.info.has("power"):
			continue
		tested += 1
		var c = Inputs.Ctrl.new()
		c.level = 1
		c.buttons = {b = true}
		var r := ThrowReader.new(c, BowlingTuning.get_profile("arcade"))
		r.phase = "ready"
		var ev := {}
		for s in sw.samples:
			c.history = [s]
			c.t = s.t
			var e := r.update()
			if e.get("type", "") == "throw":
				ev = e
		c.buttons = {b = false}
		var e2 := r.update()
		if e2.get("type", "") == "throw":
			ev = e2
		# the power formula has been retuned since the log was made: compare what was read
		if not ev.is_empty() and absf(ev.info.peak - float(sw.info.peak)) < 0.01 and absf(ev.info.twist - float(sw.info.twist)) < 0.01:
			good += 1
		elif tested <= 3:
			print("  swing: wanted peak %s twist %s, got %s" % [sw.info.peak, sw.info.twist, str(ev)])
	ok(tested > 0 and good == tested, "recorded Joy-Con 2 swings read as the same throws (%d of %d)" % [good, tested])

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
