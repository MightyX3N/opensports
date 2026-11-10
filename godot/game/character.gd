## The bowler: the CC0 KayKit robot (assets/characters/robot) with its animations, which
## come in separate files and are added to the robot's AnimationPlayer. Bones can be aimed
## on top of the animation (the throwing arm follows the controller).
class_name Character
extends Node3D

const DIR := "res://assets/characters/robot/"
const ANIMS := ["anim_general.glb", "anim_movementbasic.glb", "anim_simulation.glb"]

var skeleton: Skeleton3D
var player: AnimationPlayer
var current := ""
var _aims := [] # this frame's { bone, child, dir (model space), weight }

func _init() -> void:
	var scene: PackedScene = load(DIR + "robot.glb")
	var model := scene.instantiate()
	add_child(model)
	skeleton = _find(model, "Skeleton3D")
	player = _find(model, "AnimationPlayer")
	if player == null:
		player = AnimationPlayer.new()
		model.add_child(player)
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for f in ANIMS:
		var s: PackedScene = load(DIR + f)
		if s == null:
			continue
		var inst := s.instantiate()
		var ap: AnimationPlayer = _find(inst, "AnimationPlayer")
		if ap != null:
			for lib_name in ap.get_animation_library_list():
				var lib := ap.get_animation_library(lib_name)
				for an in lib.get_animation_list():
					var mine: AnimationLibrary
					if player.has_animation_library(""):
						mine = player.get_animation_library("")
					else:
						mine = AnimationLibrary.new()
						player.add_animation_library("", mine)
					if not mine.has_animation(an):
						mine.add_animation(an, lib.get_animation(an))
		inst.free()

func _find(n: Node, cls: String) -> Node:
	if n.get_class() == cls:
		return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r != null:
			return r
	return null

## play an animation; opts: loop (default true), restart, fade, rate
func play(anim: String, opts := {}) -> void:
	if not player.has_animation(anim):
		return
	if anim == current and not opts.get("restart", false):
		return
	current = anim
	var a := player.get_animation(anim)
	a.loop_mode = Animation.LOOP_LINEAR if opts.get("loop", true) else Animation.LOOP_NONE
	player.play(anim, opts.get("fade", 0.2), opts.get("rate", 1.0))
	if opts.get("restart", false):
		player.seek(0, true)

func is_done() -> bool:
	return not player.is_playing()

## aim a bone so that the line to its child joint points along dir (model space), blended
func aim(bone: String, child: String, dir: Vector3, weight: float) -> void:
	_aims.append({bone = bone, child = child, dir = dir, weight = weight})

func advance(dt: float) -> void:
	player.advance(dt)
	if skeleton == null:
		_aims.clear()
		return
	for a in _aims:
		var bi := skeleton.find_bone(a.bone)
		var ci := skeleton.find_bone(a.child)
		if bi < 0 or ci < 0 or a.weight <= 0.001:
			continue
		var g := skeleton.get_bone_global_pose(bi)
		var gc := skeleton.get_bone_global_pose(ci)
		var cur: Vector3 = (gc.origin - g.origin).normalized()
		# model space -> skeleton space
		var want: Vector3 = (skeleton.transform.basis.inverse() * a.dir).normalized()
		if cur.length() < 0.5:
			continue
		var full := Quaternion(cur, want)
		var q := Quaternion.IDENTITY.slerp(full, clampf(a.weight, 0, 1))
		var ng := Transform3D(Basis(q) * g.basis, g.origin)
		skeleton.set_bone_global_pose(bi, ng)
	_aims.clear()

func joint_world(bone: String) -> Vector3:
	var bi := skeleton.find_bone(bone)
	if bi < 0:
		return global_position
	return skeleton.global_transform * skeleton.get_bone_global_pose(bi).origin
