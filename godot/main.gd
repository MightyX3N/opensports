## Open Sports: the screens (menus, the bowling game) and what moves between them.
extends Node

var menus: Menus
var hud: BowlingHud
var game: BowlingGame
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
	hud = BowlingHud.new()
	hud.app = self
	hud.visible = false
	layer.add_child(hud)
	_toast_ui = ToastUI.new()
	_toast_ui.app = self
	layer.add_child(_toast_ui)
	apply_setting("fullscreen", Settings.get_value("fullscreen"))
	apply_setting("quality", Settings.get_value("quality"))
	# a test can start straight in a game: OPENSPORTS_START=bowling
	if OS.get_environment("OPENSPORTS_START") == "bowling":
		start_bowling({physics = "arcade"})

func toast(s: String) -> void:
	toast_text = s
	toast_t = 2.0

func _switch(name: String) -> void:
	menus.clear_items()
	if screen == "bowling" and name != "bowling" and game != null:
		game.silence()
		game.visible = false
		game.set_process(false)
	screen = name
	var in_game := name == "bowling"
	menus.visible = not in_game
	hud.visible = in_game
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
	if game != null and name != "bowling":
		game.silence()
		game.release_hall()
		game.queue_free()
		game = null
	_switch(name)

func start_bowling(opts: Dictionary) -> void:
	if game != null:
		game.release_hall()
		game.queue_free()
	game = BowlingGame.new()
	game.opts = opts
	add_child(game)
	hud.game = game
	stack = ["title", "sports", "modes"]
	_switch("bowling")

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
		stack.erase("bowling")
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
	elif screen == "bowling":
		hud.nav(nav)
	else:
		menus.nav(nav)
	# the throw button on a controller also starts from the title screen
	if screen == "title":
		for c in Inputs.list:
			if c.kind != "mouse" and c.pressed.get("b", false):
				go("sports")

func _unhandled_input(e: InputEvent) -> void:
	var ui: UICanvas = hud if screen == "bowling" else menus
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		var p := ui.get_local_mouse_position()
		if e.pressed:
			if screen == "bowling":
				hud.pointer_down(p)
			elif screen == "title":
				go("sports")
			else:
				menus.mouse_click(p)
		elif screen == "bowling" and game != null:
			game.pointer_up()
	elif e is InputEventMouseMotion:
		var p := ui.get_local_mouse_position()
		if screen == "bowling":
			if game != null:
				game.pointer_move(p)
				if game.paused or game.phase == "over":
					hud.mouse_move(p)
		else:
			menus.mouse_move(p)
	elif e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_F11:
		Settings.set_value("fullscreen", not Settings.get_value("fullscreen"))
		apply_setting("fullscreen", Settings.get_value("fullscreen"))
