## The real tennis court, net, ball and racket from the player's own Wii Sports disc (rom/),
## built once. The ball and racket are kept as part lists so the game can place copies.
class_name TennisDiscCourt
extends RefCounted

var field: Node3D        # the stadium, court and net
var ball_parts := []
var racket_parts := []
var error := ""

static func build(tree: SceneTree) -> TennisDiscCourt:
	var d := TennisDiscCourt.new()
	var data: Dictionary = await DiscAlley.in_thread(tree, func():
		var common := GameData.archive("tns_common")
		var stage := GameData.archive("tns_field")
		if common.is_empty() or stage.is_empty():
			return {}
		var out := {field = Brres.parse(stage["/G3D/tns_Field_a.brres"]), net = Brres.parse(stage["/G3D/tns_net_a.brres"]),
			ball = Brres.parse(common["/G3D/tns_ball_a.brres"]), racket = Brres.parse(common["/G3D/tns_racket.brres"])}
		for k in out:
			for t in out[k].textures.values():
				Brres.decode_texture(t)
		return out)
	if data.is_empty():
		d.error = "no tennis files on the disc"
		return null
	var all_tex := []
	for k in data:
		all_tex.append_array(data[k].textures.values())
	await Upscale.prepare(tree, all_tex)
	var parts: Dictionary = await DiscAlley.in_thread(tree, func():
		return {field = WiiModel.build(data.field, "tns_Field_a") + WiiModel.build(data.net, "tns_net_a"),
			ball = WiiModel.build(data.ball, "tns_ball_a", {local_space = true}),
			racket = WiiModel.build(data.racket, "tns_racket")})
	d.field = Node3D.new()
	d.field.name = "DiscCourt"
	WiiModel.instance(parts.field, d.field)
	d.ball_parts = parts.ball
	d.racket_parts = parts.racket
	return d

const BALL_SCALE := 0.13    # the disc's ball is 1 unit across: drawn 13 cm so it reads from the baseline
const RACKET_SCALE := 0.42  # the disc's racket is drawn for Miis; 0.68 m like a real one

## a ball 10 cm across, centred
func make_ball() -> Node3D:
	return _make(ball_parts, BALL_SCALE)

## grip at the origin, the head up +y, the strings in the x-y plane
func make_racket() -> Node3D:
	return _make(racket_parts, RACKET_SCALE)

func _make(parts: Array, sc: float) -> Node3D:
	var root := Node3D.new()
	var holder := Node3D.new()
	holder.scale = Vector3.ONE * sc
	root.add_child(holder)
	for p in parts:
		var mi := MeshInstance3D.new()
		mi.mesh = p.mesh
		mi.material_override = p.material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mi)
	return root
