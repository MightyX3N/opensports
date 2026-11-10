## The tennis HUD: the scoreboard (games and points, who serves), the calls ("15-love",
## "Fault", "Out"), what to do next, the pause menu and the end of the match.
class_name TennisHud
extends UICanvas

const PAUSE := [["Resume", "resume"], ["Connect Joy-Con 2", "pair"], ["Restart", "restart"], ["Settings", "settings"], ["Quit to sport select", "sports"]]
const OVER := [["Play again", "restart"], ["Sport select", "sports"]]

var game: TennisGame
var app # Main

func _draw() -> void:
	var g := game
	if g == null:
		return
	begin_items("tennis" + ("_pause" if g.paused else "") + ("_over" if g.phase == "over" else ""))
	if g.loading:
		draw_rect(screen_rect(), COL.bg)
		text("Loading the tennis court…", 0, 330, 28, COL.ink, "center", W)
		text(Preload.status, 0, 372, 16, COL.sub, "center", W)
		return
	var m := g.match_
	if g.phase != "over":
		_scoreboard(24, 18)
		var c = g.ctrl
		var nw := text_width(c.name, 13) + 26
		rect(24, 136, nw, 28, 14, COL.card)
		text(c.name, 24, 142, 13, COL.ink, "center", nw)
		if not g.paused:
			_instruction(m)
	if g.msg != "" and g.phase != "over":
		var t := g.msg_t
		var s := (0.6 + 1.6 * t) if t < 0.25 else 1.0
		var a := clampf((2.2 - t) / 0.3, 0, 1)
		var size := 72.0
		var cy := 200.0
		draw_set_transform(Vector2(640, cy) * (1 - s), 0, Vector2(s, s))
		text(g.msg, 4, cy - size / 2 + 5, size, Color(COL.shadow, a * 0.6), "center", W)
		text(g.msg, 0, cy - size / 2, size, Color(COL.ink, a), "center", W)
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		if g.msg_sub != "":
			var sw := text_width(g.msg_sub, 18) + 36
			rect(640 - sw / 2, cy + size / 2 + 12, sw, 36, 18, Color(g.msg_col, a))
			text(g.msg_sub, 640 - sw / 2, cy + size / 2 + 20, 18, Color(COL.card, a), "center", sw)
	if g.toast_t > 0 and g.toast_text != "":
		var tw := text_width(g.toast_text, 16) + 40
		rect(640 - tw / 2, 120, tw, 40, 20, COL.ink)
		text(g.toast_text, 640 - tw / 2, 130, 16, COL.card, "center", tw)
	if g.phase == "over":
		draw_rect(screen_rect(), Color(0.106, 0.165, 0.227, 0.35))
		var won: bool = m.rules.winner == 1
		text("MATCH OVER", 0, 110, 15, COL.card, "center", W)
		text("You win!" if won else "The computer wins", 0, 132, 60, COL.card, "center", W)
		_scoreboard(640 - 210, 230, true)
		text("Your team's shots: %d   ·   winners: %d" % [g.stats.hits, g.stats.winners], 0, 370, 16, COL.card, "center", W)
		var x := 640 - (OVER.size() * 220 + (OVER.size() - 1) * 16) / 2.0
		for i in OVER.size():
			var it: Array = OVER[i]
			var r := pill_shape(it[0], x + i * 236, 420, "primary" if i == 0 else "", false, 220)
			item(r, it[1], _action.bind(it[1]), {r = 24, default = i == 0})
		draw_focus()
	elif g.paused:
		_menu(PAUSE, "Paused", "TENNIS · GAME %d" % m.rules.game_no)

func _scoreboard(x: float, y: float, big := false) -> void:
	var m := game.match_
	var r := m.rules
	var w := 420.0
	var rowh := 44.0
	var h := 24 + rowh * 2
	rect(x, y + 4, w, h, 18, COL.shadow)
	rect(x, y, w, h, 18, COL.card)
	var board := r.board()
	var st: int = r.server()[0]
	var names := ["You & partner", "Computer"]
	var cols := [Color(0.25, 0.55, 0.95), Color(0.92, 0.30, 0.28)]
	text("GAMES", x + w - 150, y + 6, 10, COL.sub, "center", 60)
	text("POINTS", x + w - 82, y + 6, 10, COL.sub, "center", 70)
	for i in 2:
		var ry := y + 20 + i * rowh
		circle(x + 22, ry + rowh / 2, 7, cols[i])
		text(names[i], x + 38, ry + 12, 18, COL.ink)
		if st == i + 1 and m.state != "over":
			# the ball by the serving team
			circle(x + 38 + text_width(names[i], 18) + 16, ry + rowh / 2, 6, Color(0.86, 0.95, 0.20))
			arc(x + 38 + text_width(names[i], 18) + 16, ry + rowh / 2, 6, 0, TAU, Color(0.4, 0.45, 0.1), 1.2)
		text(str(r.games[i]), x + w - 150, ry + 8, 24, COL.ink, "center", 60)
		rect(x + w - 82, ry + 6, 70, rowh - 12, 10, COL.blue_soft)
		text(str(board[i]), x + w - 82, ry + 10, 20, COL.blue, "center", 70)
	var to_win := r.to_win
	var label := "1 GAME" if to_win == 1 else "BEST OF %d" % (to_win * 2 - 1)
	if not big:
		text(label, x + 16, y + h + 8, 11, COL.sub)

func _instruction(m: TennisMatch) -> void:
	var txt := ""
	var c = game.ctrl
	var motion: bool = game.reader.motion()
	var mouse: bool = c.kind == "mouse"
	if m.state == "serve" and m.serve_team == 1 and not m.moving():
		if motion: txt = "Swing to toss the ball up"
		elif mouse: txt = "Click (or flick the mouse) to toss the ball up"
		else: txt = "Flick the stick, or press %s, to toss" % _swing_key(c)
	elif m.state == "toss" and m.serve_team == 1:
		txt = "Now swing — hit it at the top of the toss for a fast serve"
	elif m.state == "rally" or m.state == "serve" or m.state == "toss":
		var cin = m.contact_in(1)
		if cin != null and cin > -0.1 and cin < 0.6:
			# a swing hint for the incoming ball
			var k := clampf(1.0 - cin / 0.6, 0, 1)
			var r := 30.0 + 26 * (1 - k)
			arc(640, 560, r, 0, TAU, Color(COL.card, 0.4 + 0.6 * k), 4)
			circle(640, 560, 24, Color(COL.blue, 0.85))
			text("SWING", 590, 553, 13, COL.card, "center", 100)
		if game.t < 12:
			if motion: txt = "Swing like a racket · early = across, late = down the line · up = lob, down = slice"
			elif mouse: txt = "Hold the button and flick · up = lob, down = slice · or just click"
			else: txt = "Flick the stick: sideways = drive, up = lob, down = slice"
	if txt != "":
		var tw := text_width(txt, 17) + 60
		rect(640 - tw / 2, 640, tw, 48, 24, COL.blue)
		text(txt, 640 - tw / 2, 654, 17, COL.card, "center", tw)

func _swing_key(c) -> String:
	if c.kind == "joycon2": return "ZR"
	if c.name.contains("Pro Controller"): return "ZR"
	return "RT"

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
		"restart": game.new_match(game.opts)
		"settings": game.resume(); app.go("settings")
		"pair": game.resume(); app.go("pair")
		"sports": game.resume(); app.root("sports")

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

func pointer_down(p: Vector2) -> void:
	if game.paused or game.phase == "over":
		mouse_click(p)
		return
	game.pointer_down(p)
