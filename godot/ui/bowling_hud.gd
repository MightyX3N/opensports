## The bowling HUD: scorecard, pin diagram, controller chip, move / turn helper, the
## instruction belt, result messages, the pause menu and game over.
class_name BowlingHud
extends UICanvas

const PAUSE := [["Resume", "resume"], ["Restart", "restart"], ["Settings", "settings"], ["Quit to sport select", "sports"]]
const OVER := [["Play again", "restart"], ["Sport select", "sports"]]

var game: BowlingGame
var app # Main
var menu_sel := 0

func _draw() -> void:
	var g := game
	if g == null:
		return
	begin_items("bowling" + ("_pause" if g.paused else "") + ("_over" if g.phase == "over" else ""))
	if g.loading:
		var sr := screen_rect()
		draw_rect(sr, COL.bg)
		text("Loading the bowling alley…", 0, 330, 28, COL.ink, "center", W)
		text("Reading your Wii Sports disc" if GameData.available() else "", 0, 372, 16, COL.sub, "center", W)
		return
	var c = g.ctrl
	var lb := _labels(c)
	if g.phase != "over":
		scorecard(24, 18, false)
		_pin_diagram(1106, 18)
		text("FRAME %d · BALL %d" % [mini(g.rules.frame, 10), g.rules.ball], 26, 96, 13, COL.sub)
	var nw := text_width(c.name, 13) + 26
	rect(24, 118, nw, 28, 14, COL.card)
	text(c.name, 24, 124, 13, COL.ink, "center", nw)
	if g.phase == "aim" and not g.paused:
		var y := 560.0
		rect(24, y, 300, 108, 20, COL.card)
		text("MOVING" if g.mode == "move" else "TURNING", 40, y + 12, 12, COL.blue)
		_key_chip(40, y + 32, lb.move, "Move" if g.mode == "move" else "Turn")
		_key_chip(40, y + 68, lb.toggle, "Switch to turn" if g.mode == "move" else "Switch to move")
		var txt := _instruction(lb)
		var tw := text_width(txt, 18) + 60
		rect(640 - tw / 2 + 170, 628, tw, 52, 26, COL.blue)
		text(txt, 640 - tw / 2 + 170, 644, 18, COL.card, "center", tw)
	if g.msg != "":
		var t := g.msg_t
		var s := (0.6 + 1.6 * t) if t < 0.25 else 1.0
		var big := g.msg == "Strike!" or g.msg == "Spare!"
		var size := 96.0 if big else 64.0
		var cy := 210.0
		draw_set_transform(Vector2(640, cy) * (1 - s), 0, Vector2(s, s))
		text(g.msg, 4, cy - size / 2 + 5, size, COL.shadow, "center", W)
		text(g.msg, 0, cy - size / 2, size, COL.blue if big else COL.ink, "center", W)
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		if not g.last_throw.is_empty():
			var lt: Dictionary = g.last_throw
			var spin := int(round(absf(lt.hook) * 100))
			var aim_deg := rad_to_deg(lt.aim)
			var sp := "%.0f km/h  ·  spin %s  ·  aim %s" % [lt.speed * 3.6,
				"none" if spin == 0 else "%d%% %s" % [spin, "right" if lt.hook > 0 else "left"],
				"straight" if absf(aim_deg) < 0.05 else "%.1f° %s" % [absf(aim_deg), "left" if aim_deg > 0 else "right"]]
			var sw := text_width(sp, 16) + 32
			rect(640 - sw / 2, cy + size / 2 + 14, sw, 32, 16, COL.card)
			text(sp, 640 - sw / 2, cy + size / 2 + 21, 16, COL.ink, "center", sw)
	if g.toast_t > 0 and g.toast_text != "":
		var tw := text_width(g.toast_text, 16) + 40
		rect(640 - tw / 2, 170, tw, 40, 20, COL.ink)
		text(g.toast_text, 640 - tw / 2, 180, 16, COL.card, "center", tw)
	if g.phase == "over":
		draw_rect(screen_rect(), Color(0.106, 0.165, 0.227, 0.35))
		text("GAME OVER", 0, 120, 15, COL.card, "center", W)
		text(str(g.rules.total()), 0, 140, 72, COL.card, "center", W)
		var w := 120 + 84 * 10.5
		scorecard(640 - w / 2, 250, true)
		var x := 640 - (OVER.size() * 220 + (OVER.size() - 1) * 16) / 2.0
		for i in OVER.size():
			var it: Array = OVER[i]
			var r := pill_shape(it[0], x + i * 236, 400, "primary" if i == 0 else "", false, 220)
			item(r, it[1], _action.bind(it[1]), {r = 24, default = i == 0})
		draw_focus()
	elif g.paused:
		_menu(PAUSE, "Paused", "BOWLING · FRAME %d" % mini(g.rules.frame, 10))

func _menu(list: Array, title: String, sub: String) -> void:
	draw_rect(screen_rect(), Color(0.106, 0.165, 0.227, 0.45))
	var w := 420.0
	var h := 120.0 + list.size() * 62
	var x := 640 - w / 2
	var y := 360 - h / 2
	rect(x, y + 6, w, h, 28, COL.shadow)
	rect(x, y, w, h, 28, COL.card)
	text(sub, x + 30, y + 26, 13, COL.sub)
	text(title, x + 30, y + 44, 34)
	for i in list.size():
		var it: Array = list[i]
		var r := pill_shape(it[0], x + 30, y + 100 + i * 62, "primary" if i == 0 else "", false, w - 60)
		item(r, it[1], _action.bind(it[1]), {r = 24, default = i == 0})
	draw_focus()

func _action(a: String) -> void:
	match a:
		"resume": game.resume()
		"restart": game.new_game(game.opts)
		"settings": game.resume(); app.go("settings")
		"sports": game.resume(); app.root("sports")

func _key_chip(x: float, y: float, key: String, label: String) -> float:
	var kw := maxf(36, text_width(key, 14) + 20)
	rect(x, y, kw, 30, 15, COL.ink)
	text(key, x, y + 7, 14, COL.card, "center", kw)
	text(label, x + kw + 8, y + 6, 15, COL.ink)
	return kw + 16 + text_width(label, 15)

func _labels(c) -> Dictionary:
	if c.kind == "mouse":
		return {throw = "Drag down, then flick up", move = "Arrow keys", toggle = "Space", mouse = true}
	if c.name.contains("Pro Controller"):
		return {throw = "ZR", move = "Stick / D-pad", toggle = "A"}
	return {throw = "R2 / RT", move = "Stick / D-pad", toggle = "A"}

func _instruction(lb: Dictionary) -> String:
	if lb.get("mouse", false):
		return "Drag the mouse down, then flick it up to throw · sideways at the end = spin"
	return "Hold %s, pull the stick back, then push it forward" % lb.throw

func scorecard(x: float, y: float, big: bool) -> float:
	var rules: BowlingRules = game.rules
	var totals := rules.totals()
	var cw := 84.0 if big else 62.0
	var ch := 92.0 if big else 66.0
	var w := 120 + cw * 9 + cw * 1.5
	rect(x, y + 4, w, ch, 18, COL.shadow)
	rect(x, y, w, ch, 18, COL.card)
	text("P1", x + 16, y + (18 if big else 10), 26 if big else 20)
	text(str(rules.total()), x + 16, y + (52 if big else 38), 20 if big else 15, COL.sub)
	for fi in range(1, 11):
		var fx := x + 120 + (fi - 1) * cw
		var fw := cw * 1.5 if fi == 10 else cw
		if fi == rules.frame and not rules.over:
			rect(fx + 2, y + 4, fw - 4, ch - 8, 10, COL.blue_soft)
		draw_line(Vector2(fx, y + 10), Vector2(fx, y + ch - 10), COL.line, 2)
		text(str(fi), fx + 6, y + 6, 11, COL.sub)
		var marks := rules.marks(fi)
		var slots := 3 if fi == 10 else 2
		var sw := fw / (slots + 0.4)
		for i in marks.size():
			var mk: String = marks[i]
			var mx := fx + fw - (slots - i) * sw
			text(mk, mx, y + (10 if big else 6), 18 if big else 15, COL.blue if (mk == "X" or mk == "/") else COL.ink, "center", sw)
		if fi <= totals.size():
			text(str(totals[fi - 1]), fx, y + ch * 0.5, 24 if big else 18, COL.ink, "center", fw)
	return w

func _pin_diagram(x: float, y: float) -> void:
	rect(x, y + 4, 150, 130, 18, COL.shadow)
	rect(x, y, 150, 130, 18, COL.card)
	var mask := game.sim.standing_mask()
	var spots := BowlingSetup.pins()
	for i in spots.size():
		var spot: Vector2 = spots[i]
		var px := x + 75 + spot.x / 0.3048 * 32
		var py := y + 104 + (spot.y + BowlingSetup.LENGTH) / 0.264 * 25
		var st: bool = mask[i] if i < mask.size() else false
		circle(px, py, 11, COL.ink if st else COL.line)
		if st:
			circle(px, py, 4, Color(1, 1, 1))

func nav(n: Dictionary) -> void:
	var g := game
	if g.paused or g.phase == "over":
		if n.get("b") and g.paused:
			g.resume()
			Snd.ui("back")
			return
		nav_items(n)
		return
	if n.get("b"):
		g.open_pause()
	elif n.get("a") and g.phase == "aim" and g.ctrl.kind == "mouse":
		g.mode = "turn" if g.mode == "move" else "move"
		Snd.ui("toggle")

func pointer_down(p: Vector2) -> void:
	if game.paused or game.phase == "over":
		mouse_click(p)
		return
	game.pointer_down(p)
