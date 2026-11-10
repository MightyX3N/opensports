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
	test_tennis_ball()
	test_tennis_rules()
	test_tennis_matches()
	test_tennis_timing()
	test_dsu()
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

# ------------------------------------------------------------------ tennis

func _first_bounce(b: TennisBall) -> Dictionary:
	for i in 4000:
		var ev := b.step(1.0 / 240)
		if ev.get("kind", "") == "bounce":
			return ev
	return {}

func _range(top: float) -> Array:
	var v := Vector3(0, 4, -20)
	var b := TennisBall.make(Vector3(0, 1, 11), v, TennisBall.spin_for(v, top, 0))
	var ev := _first_bounce(b)
	return [11 - ev.z, b]

func test_tennis_ball() -> void:
	var b := TennisBall.make(Vector3(0, 2.54, 5))
	_first_bounce(b)
	var top := 0.0
	for i in 400:
		b.step(1.0 / 240)
		top = maxf(top, b.p.y)
	ok(top > 1.2 and top < 1.6, "tennis drop test bounce height %.2f m" % top)
	var flat: float = _range(0)[0]
	var topspin: float = _range(80)[0]
	var slice: float = _range(-60)[0]
	ok(topspin < flat and slice > flat, "topspin dips (%.1f), slice floats (%.1f) vs flat %.1f" % [topspin, slice, flat])
	var bt: TennisBall = _range(80)[1]
	var bs: TennisBall = _range(-60)[1]
	ok(bt.v.y > bs.v.y, "topspin bounces higher than slice")
	var b3 := TennisBall.make(Vector3(0, 0.5, 5), Vector3(0, 0, -20))
	var hit_net := false
	for i in 200:
		if b3.step(1.0 / 240).get("kind", "") == "net":
			hit_net = true
			break
	ok(hit_net and b3.p.z > 0, "a low ball is stopped by the net on the hitter's side")
	var cases := [
		[Vector3(0.5, 1.0, 11.5), Vector2(-3, -9), {speed = 22.0, top = 60.0}],
		[Vector3(0, 0.8, 11.5), Vector2(2, -8), {speed = 18.0, top = -50.0}],
		[Vector3(0, 1.0, 3), Vector2(0, -10), {speed = 14.0, top = 30.0, lob = true}],
		[Vector3(1, 2.7, 12.2), Vector2(-2.5, -6.0), {speed = 30.0, top = 20.0, margin = 0.08}],
		[Vector3(0, 1.0, -11.5), Vector2(3, 9), {speed = 22.0, top = 60.0}],
	]
	var good := 0
	for c in cases:
		var sol := TennisShot.solve(c[0], c[1], c[2])
		if not sol.is_empty():
			var ev := _first_bounce(TennisBall.make(c[0], sol.v, sol.w))
			if not ev.is_empty() and absf(ev.x - c[1].x) < 0.3 and absf(ev.z - c[1].y) < 0.3:
				good += 1
	ok(good == cases.size(), "shot solver lands within 30 cm of the target (%d/%d)" % [good, cases.size()])

func test_tennis_rules() -> void:
	var r := TennisRules.new(2)
	ok(r.call_text() == "Love all", "new game: love all (" + r.call_text() + ")")
	r.point(1); ok(r.call_text() == "15-love", "15-love")
	r.point(2); r.point(2); ok(r.call_text() == "15-30", "15-30")
	r.point(1); r.point(1); r.point(2); ok(r.call_text() == "Deuce", "deuce")
	r.point(1); ok(r.call_text() == "Advantage server", "advantage server")
	var bd := r.board(); ok(bd[0] == "AD" and bd[1] == "40", "board shows AD")
	r.point(2); ok(r.call_text() == "Deuce", "back to deuce")
	r.point(1); var res := r.point(1)
	ok(res.game == 1 and r.games[0] == 1 and r.points[0] == 0, "game to team 1")
	var sv := r.server()
	ok(sv[0] == 2 and sv[1] == 1, "serve passes to the other team")
	ok(r.deuce_court(), "first point of a game is served to the deuce court")
	r.point(2); ok(not r.deuce_court(), "then the advantage court")
	for i in 4: r.point(1)
	ok(r.over and r.winner == 1, "best of 3: two games wins")
	var box := TennisCourt.service_box(-1, true)
	ok(box[1] <= 0 and box[2] < 0, "far deuce box is on the far player's right (-x)")

func _play_cpu(sd: int, games: int, skill: float) -> Array:
	var m := TennisMatch.new({games = games, humans = {}, skill = skill, seed = sd})
	var hits := 0
	var points := 0
	while m.state != "over" and m.t < 1800:
		m.update(1.0 / 60)
		for e in m.take_events():
			if e.kind == "hit": hits += 1
			elif e.kind == "point": points += 1
	return [m, hits, points]

func _play_human(offset: Callable, seconds: float, power := 0.6) -> Dictionary:
	var m := TennisMatch.new({games = 3, humans = {1: true}, skill = 0.5, seed = 7})
	var st := {hits = 0, points = [0, 0], swings = 0, tosses = 0, serves = 0}
	var swung_at = null
	var want = null
	while m.t < seconds and m.state != "over":
		m.update(1.0 / 60)
		if m.state == "serve" and m.serve_team == 1 and not m.moving() and m.state_t > 0.5:
			if m.toss(): st.tosses += 1
		elif m.state == "toss" and m.serve_team == 1 and m.t >= m.toss_peak_t - 0.01:
			if m.swing(1, {power = 0.7}) == "serve": st.serves += 1
		var dt = m.contact_in(1)
		if dt != null and swung_at != m.plan:
			if want == null: want = offset.call()
			if dt <= want:
				swung_at = m.plan
				want = null
				st.swings += 1
				m.swing(1, {power = power, shape = "flat"})
		for e in m.take_events():
			if e.kind == "hit" and e.team == 1: st.hits += 1
			if e.kind == "point": st.points[e.team - 1] += 1
	return st

func test_tennis_matches() -> void:
	var t0 := Time.get_ticks_msec()
	var finished := 0
	var avg := 0.0
	for sd in range(1, 7):
		var r := _play_cpu(sd, 2, 0.5)
		var m: TennisMatch = r[0]
		if m.state == "over" and m.rules.winner != 0: finished += 1
		avg += float(r[1]) / maxi(1, r[2])
	avg /= 6
	ok(finished == 6, "computer vs computer: every best-of-3 match finishes (%d/6)" % finished)
	ok(avg > 3 and avg < 25, "rallies have a sensible length (%.1f hits a point)" % avg)
	var st := _play_human(func(): return 0.08, 240)
	ok(st.serves > 0 and st.tosses >= st.serves, "a person can toss and serve")
	ok(st.hits > st.serves + 10, "well-timed swings return the ball (%d hits)" % st.hits)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var st3 := _play_human(func(): return rng.randf() * 0.55 - 0.08, 400)
	ok(st3.points[0] > 0 and st3.points[1] > 0, "with uneven timing both teams win points (%d-%d)" % [st3.points[0], st3.points[1]])
	print("tennis matches took %d ms" % (Time.get_ticks_msec() - t0))

func _rally_setup(sd: int) -> TennisMatch:
	var m := TennisMatch.new({games = 1, humans = {1: true}, skill = 0.5, seed = sd})
	m.state = "rally"
	m.last_hit = 2
	m.is_serve = false
	m.players[0].pos = Vector3(0, 0, 11)
	m.ball = TennisBall.make(Vector3(1.5, 1.0, -10), Vector3(0, 4, 17))
	m.plan = m.make_plan(1)
	m.plan_for = 2
	return m

func _dir_for(o: float) -> Array:
	var m := _rally_setup(3)
	var plan: Dictionary = m.plan
	while m.t < plan.tc + o - 1e-6: m.step_once()
	m.swing(1, {power = 0.6})
	while m.last_hit == 2 and m.t < plan.tc + 0.2: m.step_once()
	return [m.ball.v.x, plan.side]

func test_tennis_timing() -> void:
	var m := _rally_setup(5)
	ok(m.plan != null, "a plan for the incoming ball")
	if m.plan == null:
		return
	var plan: Dictionary = m.plan
	while m.t < plan.tc - 0.6: m.step_once()
	ok(m.swing(1, {power = 0.6}) == "miss", "a swing 0.6 s early misses")
	while m.t < plan.tc - 0.1: m.step_once()
	ok(m.swing(1, {power = 0.6}) == "hit", "a swing 0.1 s early hits")
	var e := _dir_for(-0.3)
	var l := _dir_for(0.08)
	if e[1] == "fore":
		ok(e[0] < l[0], "forehand: early goes left (vx %.1f), late goes right (vx %.1f)" % [e[0], l[0]])
	else:
		ok(e[0] > l[0], "backhand: early goes right (vx %.1f), late goes left (vx %.1f)" % [e[0], l[0]])

# ------------------------------------------------------------------ DSU

## a server's pad-data packet, the way DS4Windows builds it
static func dsu_server_packet(slot: int, ts: int, acc: Vector3, gyr: Vector3, b2 := 0) -> PackedByteArray:
	var p := PackedByteArray()
	p.resize(100)
	p.encode_u8(0, 0x44); p.encode_u8(1, 0x53); p.encode_u8(2, 0x55); p.encode_u8(3, 0x53) # "DSUS"
	p.encode_u16(4, 1001)
	p.encode_u16(6, 84)
	p.encode_u32(12, 1234)
	p.encode_u32(16, 0x100002)
	p.encode_u8(20, slot); p.encode_u8(21, 2); p.encode_u8(22, 2); p.encode_u8(23, 1)
	p.encode_u8(31, 1)
	p.encode_u8(37, b2)
	for i in 4: p.encode_u8(40 + i, 128)
	p.encode_u64(68, ts)
	p.encode_float(76, acc.x); p.encode_float(80, acc.y); p.encode_float(84, acc.z)
	p.encode_float(88, gyr.x); p.encode_float(92, gyr.y); p.encode_float(96, gyr.z)
	p.encode_u32(8, DSU.crc32(p))
	return p

func test_dsu() -> void:
	ok(DSU.crc32("123456789".to_ascii_buffer()) == 0xCBF43926, "CRC-32 check value")
	var req := DSU.packet(DSU.MSG_PAD, PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0]))
	var z := req.duplicate()
	z.encode_u32(8, 0)
	ok(req.size() == 28 and req.decode_u16(6) == 12 and DSU.crc32(z) == req.decode_u32(8), "DSU request: length and CRC")
	var d := DSU.parse(dsu_server_packet(1, 5000, Vector3(0, 0, -1), Vector3(10, 20, 30), 0x40))
	ok(not d.is_empty() and d.slot == 1 and d.connected and d.ts == 5000 and is_equal_approx(d.gyro.y, 20.0) and d.b2 == 0x40, "DSU pad data parses")
	var bad := dsu_server_packet(0, 1, Vector3.ZERO, Vector3.ZERO)
	bad[90] ^= 0xFF
	ok(DSU.parse(bad).is_empty(), "a corrupted DSU packet is dropped")
	# lying flat and still (the DSU frame: gravity on -z... as the server reports it) gives 1 g
	var ga := DSU.to_game(Vector3(0, 1, 0), Vector3(0, 90, 0))
	ok(is_equal_approx(ga[1].length(), 9.80665) and is_equal_approx(absf(ga[0].y), PI / 2), "DSU units: g and deg/s")
