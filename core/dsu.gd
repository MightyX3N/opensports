## DSU / cemuhook motion client: controllers served by DS4Windows, BetterJoy, SteamDeckGyroDSU,
## phone apps and the like (the same servers Dolphin and Cemu read). Asks the server for all
## pads every second over UDP and turns each connected slot into a full-motion controller.
## Protocol: https://v1993.github.io/cemuhook-protocol/
class_name DSU

const PROTOCOL := 1001
const MSG_PAD := 0x100002
const TIMEOUT := 3.0       # a slot with no data for this long is gone
const ASK_EVERY := 1.0     # servers stop sending after ~5 s without a request
## buttons byte 1 (offset 36) and 2 (37)
const B1 := {sclick = 0x02, plus = 0x08, up = 0x10, right = 0x20, down = 0x40, left = 0x80}
const B2 := {b = 0x02 | 0x08, a = 0x40, back = 0x20, recentre = 0x10}

static var udp: PacketPeerUDP
static var host := ""
static var port := 26760
static var id := 0
static var ask_t := 0.0
static var slots := {}     # slot -> { ctrl, last, ts }
static var status := ""
static var _crc_table := PackedInt64Array()

static func start(address: String) -> void:
	stop()
	if address == "":
		return
	var parts := address.split(":")
	host = parts[0]
	port = int(parts[1]) if parts.size() > 1 else 26760
	udp = PacketPeerUDP.new()
	var err := udp.connect_to_host(host, port)
	if err != OK:
		status = "Can't reach %s:%d" % [host, port]
		udp = null
		return
	id = randi()
	ask_t = 0.0
	status = "Listening to %s:%d" % [host, port]
	Log.write("DSU: " + status)

static func stop() -> void:
	if udp != null:
		udp.close()
	udp = null
	for s in slots.values():
		Inputs.remove(s.ctrl)
	slots = {}

static func crc32(b: PackedByteArray) -> int:
	if _crc_table.is_empty():
		_crc_table.resize(256)
		for i in 256:
			var c := i
			for k in 8:
				c = (0xEDB88320 ^ (c >> 1)) if (c & 1) else (c >> 1)
			_crc_table[i] = c
	var crc := 0xFFFFFFFF
	for x in b:
		crc = _crc_table[(crc ^ x) & 0xFF] ^ (crc >> 8)
	return crc ^ 0xFFFFFFFF

## a client packet: header, message type, body; the CRC covers it all with its own field zeroed
static func packet(msg: int, body: PackedByteArray) -> PackedByteArray:
	var p := PackedByteArray()
	p.resize(20)
	p.encode_u8(0, 0x44); p.encode_u8(1, 0x53); p.encode_u8(2, 0x55); p.encode_u8(3, 0x43) # "DSUC"
	p.encode_u16(4, PROTOCOL)
	p.encode_u16(6, 4 + body.size())
	p.encode_u32(8, 0)
	p.encode_u32(12, id)
	p.encode_u32(16, msg)
	p.append_array(body)
	p.encode_u32(8, crc32(p))
	return p

## one pad-data packet from the server -> { slot, connected, ts (us), accel (g), gyro (deg/s), b1, b2, stick } or {}
static func parse(p: PackedByteArray) -> Dictionary:
	if p.size() < 100 or p.slice(0, 4).get_string_from_ascii() != "DSUS" or p.decode_u32(16) != MSG_PAD:
		return {}
	var crc := p.decode_u32(8)
	var q := p.duplicate()
	q.encode_u32(8, 0)
	if crc32(q) != crc:
		return {}
	return {slot = p[20], connected = p[21] == 2 and p[31] == 1, ts = p.decode_u64(68),
		accel = Vector3(p.decode_float(76), p.decode_float(80), p.decode_float(84)),
		gyro = Vector3(p.decode_float(88), p.decode_float(92), p.decode_float(96)),
		b1 = p[36], b2 = p[37], stick = Vector2((p[40] - 128) / 127.0, (p[41] - 128) / 127.0),
		rstick = Vector2((p[42] - 128) / 127.0, (p[43] - 128) / 127.0), mac = p.slice(24, 30).hex_encode()}

## DSU accel (g) and gyro (deg/s: pitch, yaw, roll) -> the game's frame, as Dolphin reads them
static func to_game(acc: Vector3, gyr: Vector3) -> Array:
	var g := Vector3(gyr.x, -gyr.y, -gyr.z) * (PI / 180.0)
	var a := -acc * 9.80665
	return [g, a]

static func update(inputs, dt: float) -> void:
	if udp == null:
		return
	for s in slots.values():
		s.ctrl.pressed = {}
	ask_t -= dt
	if ask_t <= 0:
		ask_t = ASK_EVERY
		# all pads: registration flags 0, slot 0, no MAC
		udp.put_packet(packet(MSG_PAD, PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0])))
	var now := Time.get_ticks_msec() / 1000.0
	while udp.get_available_packet_count() > 0:
		var d := parse(udp.get_packet())
		if d.is_empty() or not d.connected:
			continue
		var s: Dictionary = slots.get(d.slot, {})
		if s.is_empty():
			var c = inputs.Ctrl.new()
			c.kind = "dsu"
			c.name = "Motion controller %d (DSU)" % (d.slot + 1)
			c.id = "dsu%d" % d.slot
			c.level = inputs.FULL
			c.has_gyro = true
			s = {ctrl = c, last = now, ts = d.ts}
			slots[d.slot] = s
			inputs.add(c)
			c.recentre()
			Log.write("DSU: slot %d connected" % d.slot)
		var c = s.ctrl
		var step: float = (d.ts - s.ts) / 1e6 if d.ts > s.ts else 0.0
		if step <= 0 or step > 0.1:
			step = 1.0 / 100
		s.ts = d.ts
		s.last = now
		var ga := to_game(d.accel, d.gyro)
		c.feed(step, ga[0], ga[1])
		for k in B1:
			c.set_button(k, (d.b1 & B1[k]) != 0)
		for k in B2:
			c.set_button(k, (d.b2 & B2[k]) != 0)
		c.stick = d.stick
		c.rstick = d.rstick
	for k in slots.keys():
		if now - slots[k].last > TIMEOUT:
			inputs.remove(slots[k].ctrl)
			Log.write("DSU: slot %d gone" % k)
			slots.erase(k)
	# menu navigation and handing the game to the controller that was pressed
	for s in slots.values():
		var c = s.ctrl
		for k in ["up", "down", "left", "right", "a"]:
			if c.pressed.get(k):
				inputs._nav[k] = true
		if c.pressed.get("back"):
			inputs._nav["b"] = true
		if c != inputs.current and (c.pressed.get("a") or c.pressed.get("b")):
			inputs.current = c
