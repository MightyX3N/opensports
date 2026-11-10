## Open Sports: the screens (menus, the games) and what moves between them.
extends Node

const GAMES := ["bowling", "tennis"]

var menus: Menus
var hud: UICanvas         # the playing game's HUD
var huds := {}            # sport -> its HUD
var game: Node3D          # BowlingGame or TennisGame
var screen := "title"
var stack := []
var toast_text := ""
var toast_t := 0.0
var _toast_ui: UICanvas

func _ready() -> void:
	get_window().title = "Open Sports"
	Inputs.connected.connect(func(c): toast(c.name + " connected"))
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	menus = Menus.new()
	menus.app = self
	layer.add_child(menus)
	huds = {bowling = BowlingHud.new(), tennis = TennisHud.new()}
	for k in huds:
		huds[k].app = self
		huds[k].visible = false
		layer.add_child(huds[k])
	hud = huds.bowling
	_toast_ui = ToastUI.new()
	_toast_ui.app = self
	layer.add_child(_toast_ui)
	apply_setting("fullscreen", Settings.get_value("fullscreen"))
	apply_setting("quality", Settings.get_value("quality"))
	# a test can start straight in a game: OPENSPORTS_START=bowling / tennis
	match OS.get_environment("OPENSPORTS_START"):
		"bowling": start_bowling({physics = "arcade"})
		"tennis": start_tennis({games = 1, skill = "normal"})

func toast(s: String) -> void:
	toast_text = s
	toast_t = 2.0

func _switch(name: String) -> void:
	menus.clear_items()
	if screen in GAMES and name != screen and game != null:
		game.silence()
		game.visible = false
		game.set_process(false)
	screen = name
	var in_game := name in GAMES
	menus.visible = not in_game
	if in_game:
		hud = huds[name]
	for k in huds:
		huds[k].visible = in_game and k == name
	if in_game and game != null:
		game.visible = true
		game.set_process(true)
		game.camera.make_current()
	menus.screen = name
	if name == "pair":
		JoyCon2.scan(true)
	elif JoyCon2.scanning and not JoyCon2.background:
		JoyCon2.scan(false)

func go(name: String) -> void:
	if name == screen:
		return
	stack.append(screen)
	_switch(name)

func back() -> void:
	Snd.ui("back")
	if stack.is_empty():
		if screen != "title":
			_switch("title")
		return
	_switch(stack.pop_back())

func root(name: String) -> void:
	stack = [] if name == "title" else ["title"]
	if name == "modes":
		stack.append("sports")
	if game != null and not name in GAMES:
		game.silence()
		game.release_hall()
		game.queue_free()
		game = null
	_switch(name)

func start_bowling(opts: Dictionary) -> void:
	_start("bowling", BowlingGame.new(), opts)

func start_tennis(opts: Dictionary) -> void:
	_start("tennis", TennisGame.new(), opts)

func _start(sport: String, g: Node3D, opts: Dictionary) -> void:
	if game != null:
		game.silence()
		game.release_hall()
		game.queue_free()
	game = g
	game.opts = opts
	add_child(game)
	huds[sport].game = game
	stack = ["title", "sports", "modes"]
	menus.mode_sport = sport
	_switch(sport)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		JoyCon2.shutdown()

func apply_setting(k: String, v) -> void:
	match k:
		"fullscreen":
			get_window().mode = Window.MODE_FULLSCREEN if v else Window.MODE_WINDOWED
		"quality":
			get_viewport().msaa_3d = Viewport.MSAA_4X if v == "high" else Viewport.MSAA_DISABLED

## the disc, packs or upscaling changed: rebuild what uses textures
func textures_changed() -> void:
	TexturePacks.reset()
	WiiModel.clear_textures()
	Upscale.clear()
	if game != null:
		game.release_hall()
		game.queue_free()
		game = null
		for k in GAMES:
			stack.erase(k)
	Preload.restart()

func _process(dt: float) -> void:
	if toast_t > 0:
		toast_t -= dt
	# keep listening for saved Joy-Cons in the background (they connect when SYNC is pressed)
	if JoyCon2.available and screen != "pair":
		var want: bool = Settings.get_value("auto_connect") and not Settings.get_value("saved").is_empty()
		if want != JoyCon2.background:
			JoyCon2.listen(want)
	var nav := Inputs.take_nav()
	if nav.is_empty():
		pass
	elif screen in GAMES:
		hud.nav(nav)
	else:
		menus.nav(nav)
	# the throw button on a controller also starts from the title screen
	if screen == "title":
		for c in Inputs.list:
			if c.kind != "mouse" and c.pressed.get("b", false):
				go("sports")

func _unhandled_input(e: InputEvent) -> void:
	var playing := screen in GAMES
	var ui: UICanvas = hud if playing else menus
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		var p := ui.get_local_mouse_position()
		if e.pressed:
			if playing:
				hud.pointer_down(p)
			elif screen == "title":
				go("sports")
			else:
				menus.mouse_click(p)
		elif playing and game != null:
			game.pointer_up()
	elif e is InputEventMouseMotion:
		var p := ui.get_local_mouse_position()
		if playing:
			if game != null:
				game.pointer_move(p)
				if game.paused or game.phase == "over":
					hud.mouse_move(p)
		else:
			menus.mouse_move(p)
	elif e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_F11:
		Settings.set_value("fullscreen", not Settings.get_value("fullscreen"))
		apply_setting("fullscreen", Settings.get_value("fullscreen"))
