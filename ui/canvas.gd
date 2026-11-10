## Immediate-mode drawing in a fixed 1280x720 design space (scaled to any screen with a
## small safe margin), with the menus' look: rounded cards, pills, the focus ring. Screens
## register their interactive items every frame; focus moves with the D-pad / stick to the
## nearest item in that direction, the pointer hovers and clicks.
class_name UICanvas
extends Control

const W := 1280.0
const H := 720.0
const SAFE := 0.03

const COL := {
	bg = Color(0.933, 0.953, 0.973), card = Color(1, 1, 1), soft = Color(0.953, 0.969, 0.984),
	ink = Color(0.106, 0.165, 0.227), sub = Color(0.290, 0.357, 0.424), line = Color(0.890, 0.922, 0.953),
	blue = Color(0.184, 0.490, 0.882), blue_dark = Color(0.106, 0.373, 0.722), blue_soft = Color(0.863, 0.922, 0.984),
	red = Color(0.886, 0.275, 0.247), green = Color(0.231, 0.667, 0.420), green_ink = Color(0.180, 0.490, 0.310),
	green_soft = Color(0.875, 0.953, 0.902), warn = Color(0.631, 0.361, 0), warn_soft = Color(1, 0.941, 0.839),
	shadow = Color(0.827, 0.871, 0.914),
}

static var _fonts := {}
static var _boxes := {}

var items := []
var focus_id := ""
var _screen := ""

static func font(weight: String) -> Font:
	if not _fonts.has(weight):
		var path: String = {bold = "res://assets/fonts/Nunito-Bold.ttf", extra = "res://assets/fonts/Nunito-ExtraBold.ttf",
			black = "res://assets/fonts/Nunito-Black.ttf"}[weight]
		var f: Font = load(path)
		_fonts[weight] = f if f != null else ThemeDB.fallback_font
	return _fonts[weight]

## weight from role: big text is black, secondary text is bold, the rest extra-bold
static func weight_for(size: float, color) -> String:
	if size >= 22: return "black"
	if color == COL.sub: return "bold"
	return "extra"

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_dt: float) -> void:
	# fill the screen, then place the design area in its middle
	var vs := get_viewport_rect().size
	var s := minf(vs.x * (1 - 2 * SAFE) / W, vs.y * (1 - 2 * SAFE) / H)
	scale = Vector2(s, s)
	size = Vector2(W, H)
	position = (vs - Vector2(W, H) * s) / 2
	queue_redraw()

## the visible screen in design coordinates (it runs past the design area on wide screens)
func screen_rect() -> Rect2:
	var vs := get_viewport_rect().size
	return Rect2(-position / scale.x, vs / scale.x)

# ------------------------------------------------------------------ drawing

func rect(x: float, y: float, w: float, h: float, r: float, color: Color) -> void:
	var key := "%d|%s" % [int(r), color.to_html()]
	var sb: StyleBoxFlat = _boxes.get(key)
	if sb == null:
		sb = StyleBoxFlat.new()
		sb.bg_color = color
		sb.set_corner_radius_all(int(r))
		sb.corner_detail = 12
		sb.anti_aliasing = true
		_boxes[key] = sb
	draw_style_box(sb, Rect2(x, y, w, h))

func outline(x: float, y: float, w: float, h: float, r: float, color: Color, width: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.border_color = color
	sb.set_border_width_all(int(width))
	sb.set_corner_radius_all(int(r))
	sb.corner_detail = 12
	sb.anti_aliasing = true
	draw_style_box(sb, Rect2(x, y, w, h))

## text with its top at y; align "left" / "center" / "right" within w (wraps when w is given)
func text(s: String, x: float, y: float, size: float, color = null, align := "", w := 400.0) -> void:
	if color == null:
		color = COL.ink
	var f := font(weight_for(size, color))
	var fs := int(round(size))
	var asc := f.get_ascent(fs)
	if align == "":
		draw_string(f, Vector2(x, y + asc), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)
		return
	var ha: HorizontalAlignment = {left = HORIZONTAL_ALIGNMENT_LEFT, center = HORIZONTAL_ALIGNMENT_CENTER, right = HORIZONTAL_ALIGNMENT_RIGHT}[align]
	if f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= w:
		draw_string(f, Vector2(x, y + asc), s, ha, w, fs, color)
	else:
		draw_multiline_string(f, Vector2(x, y + asc), s, ha, w, fs, -1, color)

func text_width(s: String, size: float, color = null) -> float:
	return font(weight_for(size, color)).get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, int(round(size))).x

func circle(x: float, y: float, r: float, color: Color) -> void:
	draw_circle(Vector2(x, y), r, color, true, -1.0, true)

func ellipse(x: float, y: float, rx: float, ry: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in 40:
		var a := i / 40.0 * TAU
		pts.append(Vector2(x + cos(a) * rx, y + sin(a) * ry))
	draw_colored_polygon(pts, color)

func poly(pts: Array, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array(pts), color)

func line(pts: Array, color: Color, width := 1.0) -> void:
	draw_polyline(PackedVector2Array(pts), color, width, true)

func arc(x: float, y: float, r: float, a0: float, a1: float, color: Color, width := 1.0) -> void:
	draw_arc(Vector2(x, y), r, a0, a1, 24, color, width, true)

func header(kicker: String, title: String) -> void:
	text(kicker, 80, 36, 15, COL.sub)
	text(title, 80, 56, 40, COL.ink)

## focus ring for D-pad navigation
func focus_ring(x: float, y: float, w: float, h: float, r: float) -> void:
	var c: Color = COL.blue
	outline(x - 8, y - 8, w + 16, h + 16, r + 8, Color(c, 0.18), 8)
	outline(x, y, w, h, r, c, 4)

## "this one is chosen" outline
func selected(x: float, y: float, w: float, h: float, r: float) -> void:
	outline(x, y, w, h, r, COL.blue, 3)

## pill button; style "" or "primary". Returns its rect.
func pill_shape(label: String, x: float, y: float, style := "", focused := false, w := -1.0) -> Rect2:
	if w < 0:
		w = text_width(label, 18) + 48
	var primary := style == "primary"
	rect(x, y + 4, w, 48, 24, COL.blue_dark if primary else COL.shadow)
	rect(x, y, w, 48, 24, COL.blue if primary else COL.card)
	text(label, x, y + 13, 18, COL.card if primary else COL.ink, "center", w)
	if focused:
		focus_ring(x, y, w, 48, 24)
	return Rect2(x, y, w, 48)

func back_button_shape(x: float, y: float, label := "Back") -> Rect2:
	var w := text_width(label, 18) + 80
	rect(x, y + 4, w, 48, 24, COL.shadow)
	rect(x, y, w, 48, 24, COL.card)
	circle(x + 28, y + 24, 16, COL.ink)
	text("B", x + 12, y + 13, 16, COL.card, "center", 32)
	text(label, x + 56, y + 13, 18)
	return Rect2(x, y, w, 48)

# ------------------------------------------------------------------ items and focus

func begin_items(name: String) -> void:
	if name != _screen:
		_screen = name
		focus_id = ""
	items = []

## register an item: opts { default, left: Callable, right: Callable, r, no_ring }
func item(r: Rect2, id: String, fn: Callable, opts := {}) -> void:
	items.append({rect = r, id = id, fn = fn, opts = opts})
	if focus_id == "" and opts.get("default", false):
		focus_id = id

func clear_items() -> void:
	items = []

func draw_focus() -> void:
	for it in items:
		if it.id == focus_id and not it.opts.get("no_ring", false):
			var r: Rect2 = it.rect
			focus_ring(r.position.x, r.position.y, r.size.x, r.size.y, it.opts.get("r", 20))

func find_item(id: String):
	for it in items:
		if it.id == id:
			return it
	return null

func move_focus(dx: int, dy: int) -> void:
	var cur = find_item(focus_id)
	if cur == null:
		if items.size() > 0:
			focus_id = items[0].id
		return
	var cr: Rect2 = cur.rect
	var c := cr.get_center()
	var best = null
	var best_score := INF
	var wide = null
	var wide_score := INF
	for it in items:
		if it == cur:
			continue
		var ir: Rect2 = it.rect
		var d := ir.get_center() - c
		var along := d.x * dx + d.y * dy
		if along <= 4:
			continue
		var lined := false
		if dx != 0:
			lined = ir.position.y < cr.end.y and ir.end.y > cr.position.y
		else:
			lined = ir.position.x < cr.end.x and ir.end.x > cr.position.x
		var score := along + (absf(d.x * dy) + absf(d.y * dx)) * 2.5
		if lined:
			if score < best_score: best = it; best_score = score
		elif score < wide_score:
			wide = it; wide_score = score
	if best == null:
		best = wide
	if best != null:
		focus_id = best.id
		Snd.ui("move")

func pick(it: Dictionary) -> void:
	if it.id != "back":
		Snd.ui("select")
	it.fn.call()

## D-pad / keyboard: nav = { up, down, left, right, a, b }
func nav_items(nav: Dictionary) -> void:
	if nav.get("up"): move_focus(0, -1)
	if nav.get("down"): move_focus(0, 1)
	var cur = find_item(focus_id)
	if nav.get("left"):
		if cur != null and cur.opts.has("left"):
			Snd.ui("toggle"); cur.opts.left.call()
		else:
			move_focus(-1, 0)
	if nav.get("right"):
		if cur != null and cur.opts.has("right"):
			Snd.ui("toggle"); cur.opts.right.call()
		else:
			move_focus(1, 0)
	if nav.get("a") and cur != null:
		pick(cur)

func item_at(p: Vector2):
	for i in range(items.size() - 1, -1, -1):
		if items[i].rect.has_point(p):
			return items[i]
	return null

func mouse_move(p: Vector2) -> void:
	var it = item_at(p)
	if it != null and it.id != focus_id:
		focus_id = it.id
		Snd.ui("move", 0.6)

func mouse_click(p: Vector2) -> bool:
	var it = item_at(p)
	if it != null:
		focus_id = it.id
		pick(it)
		return true
	return false
