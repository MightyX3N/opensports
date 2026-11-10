## The menus: title screen, sport select, bowling mode select, controllers, settings and
## the Wii Sports disc and textures page. Every screen works with a pointer, a D-pad or
## stick (focus moves to the nearest item in that direction), A to pick and B to go back.
class_name Menus
extends UICanvas

var app # Main
var screen := "title"
var tab := "all"
var disc_status := ""

const SPORTS := [
	{id = "bowling", name = "Bowling", group = "classic", tint = Color(0.87, 0.93, 0.99), ready = true},
	{id = "tennis", name = "Tennis", group = "classic", tint = Color(0.92, 0.97, 0.86)},
	{id = "tabletennis", name = "Table tennis", group = "island", tint = Color(0.99, 0.90, 0.90)},
	{id = "golf", name = "Golf", group = "classic", tint = Color(0.88, 0.96, 0.89)},
	{id = "baseball", name = "Baseball", group = "classic", tint = Color(0.97, 0.93, 0.87)},
	{id = "boxing", name = "Boxing", group = "classic", tint = Color(0.99, 0.89, 0.89)},
	{id = "archery", name = "Archery", group = "island", tint = Color(0.88, 0.92, 0.98)},
	{id = "swordplay", name = "Swordplay", group = "island", tint = Color(0.92, 0.90, 0.99)},
	{id = "frisbee", name = "Frisbee", group = "island", tint = Color(0.99, 0.93, 0.86)},
	{id = "basketball", name = "Basketball", group = "island", tint = Color(0.99, 0.92, 0.85)},
	{id = "cycling", name = "Cycling", group = "island", tint = Color(0.89, 0.96, 0.90)},
]
const TABS := [["all", "All"], ["classic", "Classic"], ["island", "Island"], ["addons", "Add-ons"]]

func _draw() -> void:
	var sr := screen_rect()
	draw_rect(sr, COL.bg)
	match screen:
		"title": _title()
		"sports": _sports()
		"modes": _modes()
		"settings": _settings()
		"wiidisc": _wiidisc()
		"controllers": _controllers()
		"pair": _pair()

func back_button(label := "Back") -> void:
	var r := back_button_shape(80, 640, label)
	item(r, "back", func(): app.back(), {r = 24})

func pill(label: String, x: float, y: float, style: String, fn: Callable, w := -1.0, id := "") -> Rect2:
	var r := pill_shape(label, x, y, style, false, w)
	item(r, id if id != "" else label, fn, {r = 24, default = style == "primary"})
	return r

func _chips(x: float, y: float, align_right: bool) -> void:
	var widths := []
	var total := 0.0
	for c in Inputs.list:
		var w := text_width(c.name, 13) + 44
		widths.append(w)
		total += w + 8
	var cx := (x - total + 8) if align_right else x
	var cols := [COL.blue, COL.red, COL.green, Color(0.95, 0.55, 0.15)]
	for i in Inputs.list.size():
		var c = Inputs.list[i]
		var w: float = widths[i]
		rect(cx, y, w, 30, 15, COL.card)
		circle(cx + 16, y + 15, 9, cols[i % 4])
		text(str(i + 1), cx + 8, y + 7, 12, COL.card, "center", 16)
		text(c.name, cx + 32, y + 7, 13, COL.ink)
		cx += w + 8

# ------------------------------------------------------------------ icons
func _icon(id: String, x: float, y: float) -> void:
	match id:
		"bowling":
			ellipse(x - 14, y + 2, 11.5, 22.5, Color(0.55, 0.62, 0.70)); circle(x - 14, y - 22, 8.5, Color(0.55, 0.62, 0.70))
			draw_rect(Rect2(x - 18.5, y - 22, 9, 12), Color(0.55, 0.62, 0.70))
			ellipse(x - 14, y + 2, 10, 21, Color(0.99, 0.99, 0.99)); circle(x - 14, y - 22, 7, Color(0.99, 0.99, 0.99))
			draw_rect(Rect2(x - 17, y - 22, 6, 12), Color(0.99, 0.99, 0.99))
			draw_rect(Rect2(x - 18, y - 15, 8, 3), COL.red)
			circle(x + 10, y + 6, 17, COL.blue)
			var hc := Color(0.08, 0.2, 0.45)
			circle(x + 6, y + 1, 2.6, hc); circle(x + 13, y, 2.6, hc); circle(x + 10, y + 7, 3, hc)
		"tennis":
			circle(x, y, 22, Color(0.80, 0.90, 0.18))
			arc(x - 26, y, 20, -0.9, 0.9, Color(1, 1, 1), 3); arc(x + 26, y, 20, PI - 0.9, PI + 0.9, Color(1, 1, 1), 3)
		"tabletennis":
			draw_set_transform(Vector2(x + 8, y + 12), -0.6, Vector2.ONE)
			rect(-4, 0, 8, 22, 3, Color(0.45, 0.28, 0.16))
			draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
			circle(x - 2, y - 6, 18, COL.red); circle(x + 18, y + 14, 5, Color(1, 1, 1))
		"golf":
			ellipse(x, y + 18, 26, 8, Color(0.36, 0.70, 0.32))
			draw_rect(Rect2(x - 1, y - 24, 3, 42), Color(0.35, 0.35, 0.38))
			poly([Vector2(x + 2, y - 24), Vector2(x + 22, y - 17), Vector2(x + 2, y - 10)], COL.red)
		"baseball":
			circle(x, y, 23.5, Color(0.55, 0.62, 0.70)); circle(x, y, 22, Color(0.99, 0.99, 0.98))
			arc(x - 30, y, 22, -0.7, 0.7, Color(0.86, 0.25, 0.24), 2.5); arc(x + 30, y, 22, PI - 0.7, PI + 0.7, Color(0.86, 0.25, 0.24), 2.5)
		"boxing":
			ellipse(x + 2, y - 4, 20, 18, Color(0.86, 0.18, 0.20)); ellipse(x - 14, y + 2, 9, 11, Color(0.86, 0.18, 0.20))
			rect(x - 12, y + 12, 26, 12, 4, Color(0.96, 0.96, 0.96))
		"archery":
			var cols := [Color(0.98, 0.98, 0.98), Color(0.10, 0.12, 0.18), Color(0.20, 0.50, 0.90), Color(0.90, 0.25, 0.22), Color(0.98, 0.82, 0.20)]
			for i in cols.size():
				circle(x, y, 24 - i * 5, cols[i])
		"swordplay":
			draw_set_transform(Vector2(x, y), 0.7, Vector2.ONE)
			rect(-4, -28, 8, 38, 3, Color(0.36, 0.55, 0.95)); draw_rect(Rect2(-2, -26, 3, 32), Color(0.98, 0.98, 1))
			rect(-12, 10, 24, 5, 2, Color(0.25, 0.30, 0.40)); rect(-3, 14, 6, 12, 2, Color(0.25, 0.30, 0.40))
			draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		"frisbee":
			ellipse(x, y, 26, 12, Color(0.93, 0.48, 0.18)); ellipse(x, y - 2, 18, 7, Color(0.98, 0.66, 0.35))
		"basketball":
			circle(x, y, 22, Color(0.93, 0.48, 0.14))
			var lc := Color(0.35, 0.18, 0.08)
			draw_line(Vector2(x - 22, y), Vector2(x + 22, y), lc, 2); draw_line(Vector2(x, y - 22), Vector2(x, y + 22), lc, 2)
			arc(x - 26, y, 18, -1.0, 1.0, lc, 2); arc(x + 26, y, 18, PI - 1.0, PI + 1.0, lc, 2)
		"cycling":
			var gc := Color(0.18, 0.45, 0.30)
			arc(x - 15, y + 8, 12, 0, TAU, gc, 3.5); arc(x + 15, y + 8, 12, 0, TAU, gc, 3.5)
			line([Vector2(x - 15, y + 8), Vector2(x - 3, y - 10), Vector2(x + 9, y - 10), Vector2(x + 15, y + 8), Vector2(x, y + 8), Vector2(x - 3, y - 10)], gc, 3.5)
		"more":
			circle(x, y, 18, COL.blue)
			rect(x - 9, y - 2, 18, 4, 2, Color(1, 1, 1)); rect(x - 2, y - 9, 4, 18, 2, Color(1, 1, 1))

# ------------------------------------------------------------------ 1 title
func _title() -> void:
	begin_items("title")
	var sr := screen_rect()
	draw_rect(sr, Color(0.80, 0.90, 0.98))
	draw_rect(Rect2(-200, -100, W + 400, 380), Color(0.86, 0.93, 0.99))
	for cl in [[220, 100, 1.0], [1050, 70, 1.2], [1110, 190, 0.7], [640, 40, 0.6]]:
		var cx: float = cl[0]; var cy: float = cl[1]; var s: float = cl[2]
		ellipse(cx, cy, 90 * s, 26 * s, Color(1, 1, 1)); ellipse(cx - 40 * s, cy + 8 * s, 60 * s, 22 * s, Color(1, 1, 1))
		ellipse(cx + 50 * s, cy + 6 * s, 70 * s, 20 * s, Color(1, 1, 1))
	ellipse(980, 470, 420, 190, Color(0.55, 0.80, 0.50))
	ellipse(1200, 500, 300, 150, Color(0.62, 0.85, 0.55))
	ellipse(200, 520, 380, 120, Color(0.45, 0.72, 0.42))
	draw_rect(Rect2(958, 300, 4, 70), Color(0.35, 0.35, 0.38))
	poly([Vector2(962, 300), Vector2(1000, 312), Vector2(962, 324)], COL.red)
	draw_rect(Rect2(sr.position.x, 520, sr.size.x, sr.end.y - 520), Color(0.42, 0.72, 0.92))
	draw_rect(Rect2(sr.position.x, 650, sr.size.x, sr.end.y - 650), Color(0.94, 0.86, 0.66))
	for i in 6:
		rect(120 + i * 190, 560 + (i % 2) * 30, 70, 3, 1.5, Color(1, 1, 1, 0.55))
	rect(370, 128, 540, 176, 32, COL.shadow)
	rect(370, 120, 540, 176, 32, COL.card)
	text("Open Sports", 370, 146, 72, COL.blue, "center", 540)
	text("O P E N - S O U R C E   M O T I O N   S P O R T S", 370, 244, 15, COL.sub, "center", 540)
	var label := "Press A or click to start"
	var w := text_width(label, 19) + 84
	var x := 640 - w / 2
	var y := 410.0
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * 3)
	rect(x, y, w, 56, 28, Color(COL.ink, 0.92))
	circle(x + 32, y + 28, 15, Color(1, 1, 1, 0.85 + 0.15 * pulse))
	text("A", x + 20, y + 16, 17, COL.ink, "center", 24)
	text(label, x + 58, y + 16, 19, COL.card)
	item(Rect2(0, 0, W, H), "start", func(): app.go("sports"), {no_ring = true, default = true})
	_chips(40, 670, false)
	text("v0.2 · GPL-3.0", 1000, 676, 13, COL.sub, "right", 240)
	# what is loading in the background (the disc, the alley)
	var st: String = Preload.status
	if st != "":
		var sw := text_width(st, 14) + 40
		rect(640 - sw / 2, 484, sw, 32, 16, Color(1, 1, 1, 0.85))
		text(st, 640 - sw / 2, 491, 14, COL.blue_dark if not Preload.loading else COL.sub, "center", sw)

# ------------------------------------------------------------------ 2 sport select
func _sports() -> void:
	begin_items("sports")
	text("Choose a sport", 104, 34, 40)
	var x := 104.0
	for t in TABS:
		var on: bool = tab == t[0]
		var w := text_width(t[1], 15) + 36
		rect(x, 96, w, 34, 17, COL.blue if on else COL.card)
		text(t[1], x, 104, 15, COL.card if on else COL.ink, "center", w)
		item(Rect2(x, 96, w, 34), "tab_" + t[0], func(): tab = t[0], {r = 17})
		x += w + 10
	_chips(1176, 40, true)
	var list := []
	for s in SPORTS:
		if tab == "all" or tab == s.group:
			list.append(s)
	if tab == "all" or tab == "addons":
		list.append({id = "more", name = "More sports", more = true})
	var tw := 252.0
	var th := 140.0
	var gap := 22.0
	for i in list.size():
		var s: Dictionary = list[i]
		var tx := 104 + (i % 4) * (tw + gap)
		var ty := 150 + (i / 4) * (th + gap)
		if s.get("more", false):
			outline(tx, ty, tw, th, 22, COL.line, 3)
			_icon("more", tx + tw / 2, ty + 52)
			text("More sports", tx, ty + 82, 18, COL.ink, "center", tw)
			text("From add-ons", tx, ty + 106, 13, COL.sub, "center", tw)
			item(Rect2(tx, ty, tw, th), "sport_more", func(): app.toast("Add-on sports aren't available yet"), {r = 22})
		else:
			rect(tx, ty + 4, tw, th, 22, COL.shadow)
			rect(tx, ty, tw, th, 22, COL.card)
			rect(tx, ty, tw, th - 40, 22, s.tint)
			draw_rect(Rect2(tx, ty + 60, tw, th - 100), s.tint)
			_icon(s.id, tx + tw / 2, ty + 50)
			text(s.name, tx, ty + th - 31, 18, COL.ink, "center", tw)
			if not s.get("ready", false):
				rect(tx, ty, tw, th, 22, Color(COL.bg, 0.55))
				var lw := text_width("Coming soon", 12) + 20
				rect(tx + tw - lw - 12, ty + 12, lw, 24, 12, COL.card)
				text("Coming soon", tx + tw - lw - 12, ty + 17, 12, COL.sub, "center", lw)
			var sid: String = s.id
			var sname: String = s.name
			var ready: bool = s.get("ready", false)
			item(Rect2(tx, ty, tw, th), "sport_" + sid, _pick_sport.bind(ready, sname), {r = 22, default = sid == "bowling"})
	back_button()
	var rx := 1176.0
	var w2 := text_width("Settings", 18) + 48
	pill("Settings", rx - w2, 640, "", func(): app.go("settings"), w2)
	var w1 := text_width("Controllers", 18) + 48
	pill("Controllers", rx - w2 - 12 - w1, 640, "", func(): app.go("controllers"), w1)
	draw_focus()

# ------------------------------------------------------------------ 3 bowling mode select
func _lane_art(x: float, y: float, w: float, h: float) -> void:
	rect(x, y, w, h, 24, Color(0.86, 0.92, 0.98))
	var cx := x + w / 2
	poly([Vector2(cx - 30, y + 20), Vector2(cx + 30, y + 20), Vector2(cx + 150, y + h - 12), Vector2(cx - 150, y + h - 12)], Color(0.70, 0.78, 0.88))
	poly([Vector2(cx - 22, y + 20), Vector2(cx + 22, y + 20), Vector2(cx + 118, y + h - 12), Vector2(cx - 118, y + h - 12)], Color(0.93, 0.78, 0.55))
	for row in range(3, -1, -1):
		for i in row + 1:
			ellipse(cx + (i - row / 2.0) * 9, y + 44 - row * 3, 3, 7, Color(0.97, 0.97, 0.97))
	circle(cx, y + h - 70, 30, COL.blue)
	var hc := Color(0.08, 0.2, 0.45)
	circle(cx - 8, y + h - 78, 4, hc); circle(cx + 7, y + h - 80, 4, hc); circle(cx, y + h - 68, 4.5, hc)

func _modes() -> void:
	begin_items("modes")
	rect(80, 64, 360, 556, 28, COL.card)
	_lane_art(96, 80, 328, 290)
	text("Bowling", 104, 390, 34)
	text("PHYSICS", 104, 440, 13, COL.sub)
	var phys: String = Settings.get_value("physics")
	for i in 2:
		var p: Array = [["arcade", "Arcade"], ["realistic", "Realistic"]][i]
		var bx := 104 + i * 156
		var on: bool = phys == p[0]
		rect(bx, 462, 150, 40, 20, COL.blue if on else COL.soft)
		text(p[1], bx, 472, 16, COL.card if on else COL.ink, "center", 150)
		item(Rect2(bx, 462, 150, 40), "phys_" + p[0], func(): Settings.set_value("physics", p[0]),
			{r = 20, left = func(): Settings.set_value("physics", "arcade"), right = func(): Settings.set_value("physics", "realistic")})
	text("Forgiving: lighter pins that scatter more, like the original." if phys == "arcade"
		else "Real pin weight and friction: you have to earn your strikes.", 104, 516, 14, COL.sub, "left", 312)
	text("CHOOSE A MODE", 476, 64, 13, COL.sub)
	var modes := [["standard", "Standard game", "10 frames, classic scoring", "1 player", true],
		["pinparty", "Pin party", "Pick any number of pins and a layout", "Coming soon", false],
		["training", "Training", "Spin control, power throws, spare pick-ups", "Coming soon", false]]
	for i in modes.size():
		var md: Array = modes[i]
		var y := 88 + i * 96
		rect(476, y, 724, 82, 20, COL.card)
		text(md[1], 500, y + 16, 20, COL.ink if md[4] else COL.sub)
		text(md[2], 500, y + 46, 14, COL.sub)
		text(md[3], 1000, y + 30, 14, COL.ink if md[4] else COL.sub, "right", 176)
		if md[4]:
			selected(476, y, 724, 82, 20)
		var ok: bool = md[4]
		var mname: String = md[1]
		item(Rect2(476, y, 724, 82), "mode_" + md[0], _pick_mode.bind(ok, mname), {r = 20})
	back_button()
	var w := text_width("Start", 18) + 80
	pill("Start", 1200 - w, 640, "primary", func(): app.start_bowling({physics = Settings.get_value("physics")}), w)
	draw_focus()

# ------------------------------------------------------------------ controllers
func _controllers() -> void:
	begin_items("controllers")
	header("SETUP", "Controllers")
	for i in Inputs.list.size():
		var c = Inputs.list[i]
		var y := 128 + i * 64
		rect(80, y, 560, 54, 18, COL.card)
		text(c.name, 110, y + 9, 16)
		text(Inputs.LEVEL_NAMES.get(c.level, ""), 110, y + 30, 12, COL.sub)
		var st := "In play" if c == Inputs.current else "Ready"
		text(st, 500, y + 19, 13, COL.blue_dark if c == Inputs.current else COL.green_ink, "right", 120)
		item(Rect2(80, y, 560, 54), "ctrl_%d" % i, func(): Inputs.current = c, {r = 18, default = c == Inputs.current})
	text("Plug in a gamepad, or connect Joy-Con 2 here. A controller that sends motion bowls with full motion.",
		700, 140, 15, COL.sub, "left", 480)
	pill("Connect Joy-Con 2", 700, 220, "primary", func(): app.go("pair"), 300)
	back_button()
	draw_focus()

# ------------------------------------------------------------------ Joy-Con 2 pairing
func _pair() -> void:
	begin_items("pair")
	header("SETUP · BLUETOOTH", "Connect Joy-Con 2")
	rect(80, 130, 540, 480, 32, COL.card)
	text("Press the SYNC button", 110, 160, 26)
	text("It's the small round button on the flat rail side of each Joy-Con 2 (or next to the USB port on a Pro Controller 2). The lights will run back and forth.",
		110, 200, 16, COL.sub, "left", 480)
	rect(150, 300, 400, 120, 22, COL.soft)
	rect(200, 340, 300, 40, 20, COL.red)
	rect(200, 340, 300, 12, 6, Color(0.949, 0.416, 0.384))
	circle(282, 360, 8, COL.ink)
	for i in 4:
		circle(380 + i * 22, 360, 6, COL.green if i == 1 else COL.line)
	arc(282, 360, 18, 0, TAU, COL.blue, 3)
	text("SYNC", 252, 392, 13, COL.blue_dark, "center", 60)
	text("Windows doesn't list Joy-Con 2 under Bluetooth settings: the game connects to them directly. After the first time it's saved: just press SYNC on it on any screen.",
		110, 446, 14, COL.sub, "left", 480)
	text("CONTROLLERS NEARBY", 652, 130, 16, COL.sub)
	if not JoyCon2.available:
		rect(652, 160, 548, 90, 20, COL.warn_soft)
		text(JoyCon2.reason if JoyCon2.reason != "" else "Bluetooth isn't available", 676, 180, 17, COL.warn, "left", 500)
	else:
		if JoyCon2.found.is_empty():
			rect(652, 160, 548, 64, 20, COL.card)
			text(JoyCon2.status if JoyCon2.status != "" else "Searching…", 676, 182, 15, COL.sub, "left", 500)
		for i in JoyCon2.found.size():
			var e: Dictionary = JoyCon2.found[i]
			var y := 160 + i * 76
			rect(652, y, 548, 64, 20, COL.card)
			text(e.name, 676, y + 12, 17)
			var st: String = {found = "Press A to connect", connecting = e.status_text if e.status_text != "" else "Connecting…",
				connected = "Connected", failed = e.status_text if e.status_text != "" else "Failed: press SYNC and try again",
				lost = "Disconnected"}.get(e.state, e.state)
			text(st, 676, y + 34, 14, COL.green_ink if e.state == "connected" else (COL.warn if e.state == "failed" else COL.sub), "left", 380)
			text("%d dBm" % e.rssi, 1050, y + 22, 14, COL.sub, "right", 130)
			item(Rect2(652, y, 548, 64), "pad_%d" % i, JoyCon2.connect_entry.bind(e), {r = 20, default = i == 0})
	back_button("Done")
	pill("Search again", 1176 - 180, 640, "", func(): JoyCon2.scan(true), 180)
	draw_focus()

# ------------------------------------------------------------------ settings
const ROWS := [
	{section = "SCREEN AND SOUND"},
	{key = "fullscreen", label = "Fullscreen", sub = "Fill the whole screen"},
	{key = "quality", label = "Graphics", sub = "Smooth edges look nicer; Faster helps slower PCs"},
	{key = "volume", label = "Sound", sub = "Volume of the game's sounds"},
	{section = "BOWLING"},
	{key = "swing", label = "Swing strength", sub = "How hard you need to swing for the fastest ball"},
	{key = "aim_line", label = "Aim line", sub = "The dotted guide on the lane"},
	{section = "CONTROLLERS"},
	{key = "auto_connect", label = "Connect saved Joy-Cons by themselves", sub = "Press SYNC on a saved Joy-Con on any screen"},
	{action = "controllers", label = "Controllers", sub = "Connected controllers and which one is in play"},
	{section = "YOUR WII SPORTS DISC"},
	{action = "wiidisc", label = "Wii Sports disc and textures", sub = "The real Wii Sports look, texture packs and upscaling"},
]
const DISC_ROWS := [
	{section = "YOUR WII SPORTS DISC"},
	{disc = true, label = "Real Wii Sports look", sub = "Put your .wbfs or .iso in the rom folder next to OpenSports.exe"},
	{key = "real_look", label = "Use the disc", sub = "Off: Open Sports' own alley"},
	{section = "TEXTURES"},
	{packs = true, label = "Texture packs", sub = "Packs made for Dolphin go in packs/textures"},
	{key = "texture_pack", label = "Use texture packs", sub = "Show the packs' textures in place of the disc's own"},
	{key = "upscale", label = "Upscale textures", sub = "Sharpen the disc's own textures (xBRZ). Packs look better"},
]

static func value_label(k: String, v) -> String:
	match k:
		"quality": return "Smooth" if v == "high" else "Faster"
		"volume": return {high = "Loud", medium = "Medium", low = "Quiet", off = "Off"}.get(v, str(v))
		"swing": return {light = "Light", normal = "Normal", strong = "Strong"}.get(v, str(v))
		"upscale": return {"off": "Off", "2x": "2×", "4x": "4×"}.get(v, str(v))
	if v is bool:
		return "On" if v else "Off"
	return str(v)

func _rows(rows: Array, first_default: String) -> void:
	var y := 112.0
	for row in rows:
		if row.has("section"):
			text(row.section, 80, y + 4, 13, COL.sub)
			y += 22
			continue
		rect(80, y, 1120, 50, 18, COL.card)
		text(row.label, 104, y + 5, 17)
		text(row.sub, 104, y + 28, 12, COL.sub)
		if row.has("key"):
			var k: String = row.key
			var w := 200.0
			var bx := 1176 - w
			rect(bx, y + 6, w, 38, 19, COL.soft)
			text("<", bx + 10, y + 13, 16, COL.sub, "left", 20)
			text(">", bx + w - 30, y + 13, 16, COL.sub, "right", 20)
			text(value_label(k, Settings.get_value(k)), bx, y + 14, 16, COL.ink, "center", w)
			item(Rect2(80, y, 1120, 50), "set_" + k, func(): change(k, 1),
				{r = 18, default = k == first_default, left = func(): change(k, -1), right = func(): change(k, 1)})
		elif row.has("action"):
			var a: String = row.action
			text("Open  >", 1000, y + 15, 16, COL.blue, "right", 176)
			item(Rect2(80, y, 1120, 50), "set_" + a, func(): app.go(a), {r = 18})
		elif row.get("disc", false):
			var have: bool = GameData.disc != null
			text(GameData.status if GameData.status != "" else "Not added", 560, y + 15, 15, COL.blue if have else COL.sub, "right", 616)
			item(Rect2(80, y, 1120, 50), "set_disc", _rescan_disc, {r = 18, default = first_default == "disc"})
		elif row.get("packs", false):
			var n := TexturePacks.index().size()
			text(("%d textures found  ·  Look again" % n) if n > 0 else "None found  ·  Look again", 560, y + 15, 15,
				COL.blue if n > 0 else COL.sub, "right", 616)
			item(Rect2(80, y, 1120, 50), "set_packs", _rescan_packs, {r = 18})
		y += 54

func _pick_sport(ready: bool, sname: String) -> void:
	if ready:
		app.go("modes")
	else:
		app.toast(sname + " is coming soon")

func _pick_mode(ok: bool, mname: String) -> void:
	if ok:
		app.start_bowling({physics = Settings.get_value("physics")})
	else:
		app.toast(mname + " is coming soon")

func _rescan_disc() -> void:
	GameData.scan()
	if GameData.disc != null:
		app.toast("Found " + GameData.status)
	else:
		app.toast(GameData.status + " · put your disc image in the rom folder")
	app.textures_changed()

func _rescan_packs() -> void:
	TexturePacks.reset()
	app.textures_changed()
	var m := TexturePacks.index().size()
	app.toast(("%d texture pack images found" % m) if m > 0 else "No texture packs in packs/textures")

func change(k: String, dir: int) -> void:
	var v = Settings.cycle(k, dir)
	app.apply_setting(k, v)
	if k in ["texture_pack", "upscale", "real_look"]:
		app.textures_changed()

func _settings() -> void:
	begin_items("settings")
	header("OPTIONS", "Settings")
	_rows(ROWS, "fullscreen")
	text("Open Sports v0.2 · GPL-3.0 · Bowler: KayKit by Kay Lousberg (CC0) · Bowling sounds: juskiddink (CC-BY-SA 3.0), qubodup (CC0)",
		1200 - 860, 656, 12, COL.sub, "right", 860)
	back_button()
	draw_focus()

func _wiidisc() -> void:
	begin_items("wiidisc")
	header("OPTIONS", "Wii Sports disc and textures")
	_rows(DISC_ROWS, "disc")
	text("Folders: " + Paths.home(), 80, 520, 13, COL.sub, "left", 1120)
	text("rom/  ·  packs/textures/  ·  packs/addons/", 80, 540, 13, COL.sub, "left", 1120)
	text("Texture packs use Dolphin's names, so packs for Wii Sports (RSPE01, RSPP01…) work here. Upscaling uses xBRZ by Zenju (GPL-3.0).",
		1200 - 900, 656, 12, COL.sub, "right", 900)
	back_button()
	draw_focus()

func nav(n: Dictionary) -> void:
	if screen == "title":
		if n.get("a"):
			Snd.ui("start")
			app.go("sports")
		elif n.get("b"):
			get_tree().quit()
		return
	if n.get("b"):
		app.back()
		return
	nav_items(n)
