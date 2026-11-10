## Sound effects: one-shots from a pool of voices (picking a random variant when a sound has
## _1, _2 ... files) and named loops (rolling ball, hall ambience). Sounds are placed in the
## world: the ears are at the camera, every hit plays where it happened, with the room's
## echo (an "Room" bus with reverb); recordings that already hold the hall play dry.
extends Node

const ROOT := "res://assets/sounds/"
const NEAR := 7.0
const FAR := 80.0
const MAX_VOICES := 40
const VOLUMES := {high = 1.0, medium = 0.6, low = 0.3, off = 0.0}

var _variants := {}
var _voices: Array[AudioStreamPlayer3D] = []
var _flat: Array[AudioStreamPlayer] = []
var _loops := {}
var _last_ui := {}
var listener: AudioListener3D

func _ready() -> void:
	# the room's echo for placed sounds
	if AudioServer.get_bus_index("Room") < 0:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, "Room")
		AudioServer.set_bus_send(i, "Master")
		var rv := AudioEffectReverb.new()
		rv.room_size = 0.55
		rv.damping = 0.5
		rv.wet = 0.2
		rv.dry = 1.0
		rv.spread = 0.9
		AudioServer.add_bus_effect(i, rv)
	listener = AudioListener3D.new()
	add_child(listener)

func master() -> float:
	return VOLUMES.get(Settings.get_value("volume"), 1.0)

func _streams(name: String) -> Array:
	if _variants.has(name):
		return _variants[name]
	var v := []
	if ResourceLoader.exists(ROOT + name + ".ogg"):
		v.append(load(ROOT + name + ".ogg"))
	else:
		var i := 1
		while ResourceLoader.exists(ROOT + name + "_%d.ogg" % i):
			v.append(load(ROOT + name + "_%d.ogg" % i))
			i += 1
	_variants[name] = v
	return v

func preload_sounds(names: Array) -> void:
	for n in names:
		_streams(n)

func _voice3d() -> AudioStreamPlayer3D:
	for v in _voices:
		if not v.playing:
			return v
	if _voices.size() < MAX_VOICES:
		var v := AudioStreamPlayer3D.new()
		v.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		v.unit_size = NEAR
		v.max_distance = FAR
		v.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		add_child(v)
		_voices.append(v)
		return v
	return _voices[0]

func _voice_flat() -> AudioStreamPlayer:
	for v in _flat:
		if not v.playing:
			return v
	var v := AudioStreamPlayer.new()
	add_child(v)
	_flat.append(v)
	return v

static func _db(vol: float) -> float:
	return linear_to_db(maxf(vol, 0.0001))

## play a one-shot. vol 0..1, pitch, pos (Vector3) or null for straight to the ears;
## opts: near (full volume within), dry (no room echo)
func play(name: String, vol := 1.0, pitch := 1.0, pos = null, opts := {}) -> Node:
	var m := master()
	if m <= 0.0:
		return null
	var v := _streams(name)
	if v.is_empty():
		return null
	var stream: AudioStream = v[randi() % v.size()]
	if pos == null:
		var f := _voice_flat()
		f.stream = stream
		f.volume_db = _db(clampf(vol * m, 0, 1))
		f.pitch_scale = pitch
		f.play()
		return f
	var p := _voice3d()
	p.stop()
	p.stream = stream
	p.global_position = pos
	p.unit_size = opts.get("near", NEAR)
	p.volume_db = _db(clampf(vol * m, 0, 1))
	p.pitch_scale = pitch
	p.bus = "Master" if opts.get("dry", false) else "Room"
	p.play()
	return p

func set_volume(player: Node, vol: float) -> void:
	if player != null and is_instance_valid(player):
		player.volume_db = _db(clampf(vol * master(), 0, 1))

## a looping sound kept by name: call every frame; vol 0 pauses it
func loop(name: String, vol: float, pitch := 1.0, pos = null) -> void:
	var p = _loops.get(name)
	var vv := vol * master()
	if p == null:
		if vv <= 0.001:
			return
		var v := _streams(name)
		if v.is_empty():
			return
		var stream: AudioStream = v[0].duplicate()
		if stream is AudioStreamOggVorbis:
			stream.loop = true
		if pos == null:
			p = AudioStreamPlayer.new()
		else:
			p = AudioStreamPlayer3D.new()
			p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
			p.unit_size = NEAR
			p.max_distance = FAR
			p.bus = "Room"
		p.stream = stream
		add_child(p)
		_loops[name] = p
	if vv <= 0.001:
		if p.playing:
			p.stream_paused = true
		return
	p.volume_db = _db(minf(1.0, vv))
	p.pitch_scale = maxf(0.1, pitch)
	if pos != null and p is AudioStreamPlayer3D:
		p.global_position = pos
	if not p.playing:
		p.play()
	p.stream_paused = false

## the ears: at the camera, looking at its target
func set_listener(pos: Vector3, target: Vector3) -> void:
	if (target - pos).length() < 1e-6:
		return
	listener.global_transform = Transform3D.IDENTITY.looking_at(target - pos, Vector3.UP).translated(pos)
	listener.make_current()

func stop_loops() -> void:
	for p in _loops.values():
		p.stop()

## UI sounds, with a short guard so a held key doesn't machine-gun them
func ui(kind: String, vol := 1.0) -> void:
	var now := Time.get_ticks_msec()
	if _last_ui.has(kind) and now - _last_ui[kind] < 40:
		return
	_last_ui[kind] = now
	play("ui/" + kind, vol * 0.7)
