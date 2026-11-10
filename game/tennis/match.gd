## A Wii-style doubles match: four players run to the ball by themselves; a team's swings
## come from a person (swing / toss) or from the computer. Owns the ball physics, the rally
## rules and the score; the game screen draws it and feeds input.
## Swing timing decides direction (early = pulled across, late = pushed the other way), swing
## speed decides pace and depth, the swing's shape decides the shot: flat (topspin),
## high-to-low (slice) or low-to-high (lob). Serve: toss, then swing; hit at the top of the
## toss for a fast serve.
class_name TennisMatch
extends RefCounted

const SUB := 1.0 / 240.0       # physics step
const RUN := 7.6               # player run speed (m/s)
const ACCEL := 28.0
const REACH := 0.75            # the ball passes this far to the side of the body
const EARLY := 0.36            # swing window around the contact time (s)
const LATE := 0.10
const CENTRE := -0.09          # swing offset that sends the ball straight
const TOSS_V := 5.3            # toss speed: peak ~1.4 m above the hand after ~0.54 s
const POINT_PAUSE := 2.0
const WIDE_AT := 1.25          # the outer 20 % of the timing window sends the ball wide

var rules: TennisRules
var humans := {1: true}
var skill := 0.5
var t := 0.0
var acc := 0.0
var events := []
var faults := 0
var rng := RandomNumberGenerator.new()
var players := []
var state := "serve"
var state_t := 0.0
var serve_team := 1
var serve_idx := 1
var server: Dictionary
var plan = null
var plan_for := 0
var last_hit := 0
var bounces := 0
var is_serve := false
var let_ := false
var net_t = null
var ball: TennisBall
var ball_live := false
var toss_peak_t := 0.0
var over := false

static func side_of(team: int) -> int: return 1 if team == 1 else -1   # near half z > 0
static func right_of(team: int) -> int: return 1 if team == 1 else -1  # +x is right facing -z

## opts: games (to win), humans = { 1: true }, skill (0..1 for the computer), seed
func _init(opts := {}) -> void:
	rules = TennisRules.new(opts.get("games", 1))
	humans = opts.get("humans", {1: true})
	skill = opts.get("skill", 0.5)
	if opts.has("seed"):
		rng.seed = opts.seed
	else:
		rng.randomize()
	for team in [1, 2]:
		for i in [1, 2]:
			players.append({team = team, idx = i, pos = Vector3.ZERO, vel = Vector2.ZERO, goal = Vector2.ZERO,
				state = "ready", state_t = 0.0, side = "fore", swing_side = "fore", swing_shape = "flat", name = "T%dP%d" % [team, i],
				role = "back", home_side = 1})
	new_point(true)

func player(team: int, i: int) -> Dictionary:
	return players[(team - 1) * 2 + i - 1]

func emit(e: Dictionary) -> void:
	e.t = t
	events.append(e)

func take_events() -> Array:
	var e := events
	events = []
	return e

func is_human(team: int) -> bool:
	return humans.get(team, false)

# ------------------------------------------------------------------ positions

## where everyone stands for a serve: "team:idx" -> Vector2(x, z)
func serve_positions() -> Dictionary:
	var s_ := rules.server()
	var st: int = s_[0]
	var si: int = s_[1]
	var r_ := rules.receiver()
	var rt: int = r_[0]
	var ri: int = r_[1]
	var deuce := rules.deuce_court()
	var pos := {}
	var s := side_of(st)
	var sx := right_of(st) * (1.0 if deuce else -1.0) * 1.1
	pos["%d:%d" % [st, si]] = Vector2(sx, s * (TennisCourt.HALF_LEN + 0.35))
	pos["%d:%d" % [st, 3 - si]] = Vector2(-sx * 2.4, s * 3.4)
	var r := side_of(rt)
	var rx := right_of(rt) * (1.0 if deuce else -1.0) * 3.0
	pos["%d:%d" % [rt, ri]] = Vector2(rx, r * (TennisCourt.HALF_LEN + 0.4))
	pos["%d:%d" % [rt, 3 - ri]] = Vector2(-rx * 0.85, r * 5.6)
	return pos

## where a player drifts back to during a rally, shifted towards the ball
func home_for(p: Dictionary, bx: float) -> Vector2:
	var s := side_of(p.team)
	var front: bool = p.role == "front"
	var x: float = clampf(bx * 0.45, -2.5, 2.5) + (-1.0 if front else 1.0) * p.home_side * 1.6
	return Vector2(clampf(x, -TennisCourt.HALF_W + 0.5, TennisCourt.HALF_W - 0.5), s * (3.6 if front else TennisCourt.HALF_LEN + 0.8))

func new_point(first := false) -> void:
	state = "serve"
	state_t = 0.0
	var s_ := rules.server()
	serve_team = s_[0]
	serve_idx = s_[1]
	server = player(serve_team, serve_idx)
	plan = null
	last_hit = 0
	bounces = 0
	is_serve = false
	let_ = false
	var pos := serve_positions()
	for p in players:
		var g: Vector2 = pos["%d:%d" % [p.team, p.idx]]
		p.goal = g
		p.serve_spot = g
		p.role = "front" if absf(g.y) < 8 else "back"
		p.home_side = 1 if g.x >= 0 else -1
		if first:
			p.pos = Vector3(g.x, 0, g.y)
			p.vel = Vector2.ZERO
		p.state = "ready"
		p.state_t = 0.0
	hold_ball()

func hold_ball() -> void:
	var p := server
	var s := side_of(p.team)
	var r := right_of(p.team)
	ball = TennisBall.make(Vector3(p.pos.x - r * 0.25, 1.05, p.pos.z - s * 0.35))
	ball_live = false

# ------------------------------------------------------------------ serving

func toss() -> bool:
	if state != "serve" or moving():
		return false
	var p := server
	var s := side_of(p.team)
	var r := right_of(p.team)
	ball = TennisBall.make(Vector3(p.pos.x - r * 0.15, 1.3, p.pos.z - s * 0.45), Vector3(0, TOSS_V, 0))
	ball_live = true
	state = "toss"
	state_t = 0.0
	p.state = "toss"
	p.state_t = 0.0
	toss_peak_t = t + TOSS_V / TennisBall.G
	emit({kind = "toss", team = p.team})
	return true

func moving() -> bool:
	for p in players:
		if (p.goal - Vector2(p.pos.x, p.pos.z)).length_squared() > 0.04:
			return true
	return false

## strike the serve: quality 0..1 (1 = at the top of the toss), power 0..1, aim -1..1
func serve_hit(power: float, aim: float, quality: float) -> void:
	var p := server
	var rt: int = 3 - p.team
	var box := TennisCourt.service_box(side_of(rt), rules.deuce_court())
	var r := side_of(rt)
	var cx: float = (box[0] + box[1]) / 2.0
	var half: float = (box[1] - box[0]) / 2.0 - 0.45
	var wide := 1.0 if (box[0] + box[1]) > 0 else -1.0
	var tx: float = cx + wide * clampf(aim, -1, 1) * half
	var tz: float = r * (TennisCourt.SERVICE - 0.75)
	var fast := quality > 0.75
	var speed := 18.0 + 10.0 * power + (8.0 if fast else 0.0)
	if faults == 1:
		speed *= 0.85
	var margin := 0.08
	if quality < 0.15:
		margin = -0.25 # a badly timed toss hit (ball already low) can find the net
	launch(p, ball.p, Vector2(tx, tz), {speed = speed, top = 25.0, margin = margin})
	is_serve = true
	state = "rally"
	emit({kind = "serve", team = p.team, fast = fast, speed = speed})
	p.state = "serve"
	p.state_t = 0.0

# ------------------------------------------------------------------ hitting

func launch(p: Dictionary, from: Vector3, target: Vector2, opts: Dictionary) -> void:
	var sol := TennisShot.solve(from, target, opts)
	if sol.is_empty():
		# nothing reaches cleanly from here: a weak pop-up towards the other side
		sol = TennisShot.solve(from, Vector2(target.x * 0.5, target.y * 0.7), {speed = 11.0, lob = true, top = 0.0})
	var v: Vector3
	var w: Vector3
	if sol.is_empty():
		v = Vector3(0, 3, -side_of(p.team) * 8)
		w = Vector3.ZERO
	else:
		v = sol.v
		w = sol.w
	ball = TennisBall.make(from, v, w)
	ball_live = true
	last_hit = p.team
	bounces = 0
	let_ = false
	net_t = null
	plan = null
	plan_for = 0
	emit({kind = "hit", team = p.team, idx = p.idx, speed = v.length(), pos = from})

## choose and play a rally shot: opts { power 0..1, dir -1..1 (hitter's left..right), shape,
## stretch, miss ("long" / "wide" / "net"), err_x, err_z, margin }
func hit(p: Dictionary, opts: Dictionary) -> void:
	var s := side_of(p.team)
	var from := Vector3(ball.p.x, maxf(ball.p.y, 0.15), ball.p.z)
	var power := clampf(opts.get("power", 0.5), 0, 1)
	var shape: String = opts.get("shape", "flat")
	var tx: float = clampf(opts.get("dir", 0.0), -1, 1) * (TennisCourt.HALF_W - 0.8) * right_of(p.team)
	var depth := 7.0 + 3.5 * power
	var o := {speed = 14.0 + 11.0 * power, top = 55.0 + 25.0 * power}
	if shape == "slice":
		o.top = -45.0
		o.speed *= 0.8
		depth -= 0.5
	elif shape == "lob":
		o.lob = true
		o.top = 25.0
		o.speed = 12.0 + 3.0 * power
		depth = 9.5 + power
	# close to the net: a volley, punched rather than swung
	if absf(from.z) < 4.5 and shape != "lob":
		depth = minf(depth, 6.0 + 3.0 * power)
		o.speed *= 0.75
		o.top = 15.0
		o.margin = 0.05
		tx *= 0.6
	if opts.get("stretch", false):
		o.speed *= 0.7
		depth *= 0.85
		tx *= 0.5
	var tz := -s * depth
	if opts.has("err_x"): tx += opts.err_x
	if opts.has("err_z"): tz -= s * opts.err_z
	if opts.has("margin"): o.margin = opts.margin
	tx = clampf(tx, -TennisCourt.HALF_W + 0.35, TennisCourt.HALF_W - 0.35)
	tz = -s * clampf(absf(tz), 2.5, TennisCourt.HALF_LEN - 0.35)
	var miss: String = opts.get("miss", "")
	if miss == "long":
		tz = -s * (TennisCourt.HALF_LEN + 0.6 + rng.randf() * 2.0)
	elif miss == "wide":
		var d: float = opts.get("dir", 0.0)
		var sgn := (1.0 if d * right_of(p.team) > 0 else -1.0) if d != 0 else (1.0 if tx >= 0 else -1.0)
		tx = sgn * (TennisCourt.HALF_W + 0.5 + rng.randf() * 1.8)
	launch(p, from, Vector2(tx, tz), o)
	p.swing_shape = shape
	if miss == "net":
		# same shot, struck too flat: it finds the net
		var h := TennisCourt.net_height(ball.p.x)
		var t_net := absf(ball.p.z) / maxf(1, absf(ball.v.z))
		ball.v.y = (h * 0.6 - ball.p.y) / t_net + 0.5 * TennisBall.G * t_net
	if p.state != "swing":
		p.state = "swing"
		p.state_t = 0.0

# ------------------------------------------------------------------ the computer

func _gauss() -> float:
	return (rng.randf() + rng.randf() + rng.randf() - 1.5) * 1.4

## a computer shot: aim away from the nearest opponent, with mistakes by skill
func cpu_hit(p: Dictionary) -> void:
	var sk := skill
	var opp := players.filter(func(q): return q.team != p.team)
	var gap_x := 0.0
	var best_gap := -1.0
	for cand in [-3.8, -1.5, 1.5, 3.8]:
		var d := 99.0
		for q in opp:
			d = minf(d, absf(q.pos.x - cand))
		if d > best_gap:
			best_gap = d
			gap_x = cand
	var dir := clampf(gap_x / (TennisCourt.HALF_W - 0.8), -1, 1) * right_of(p.team)
	var shape := "flat"
	var net_men := 0
	for q in opp:
		if absf(q.pos.z) < 5:
			net_men += 1
	var rr := rng.randf()
	if net_men >= 2 and absf(ball.p.z) > 8 and rr < 0.35:
		shape = "lob"
	elif ball.p.y < 0.55 and rr < 0.5:
		shape = "slice"
	var power := clampf(0.45 + 0.5 * sk + (rng.randf() - 0.5) * 0.5, 0.1, 1)
	var spread := 1.6 - 1.2 * sk
	var stretch: bool = plan != null and plan.get("stretch", false)
	var o := {power = power, dir = dir * (0.75 + 0.35 * sk), shape = shape, err_x = _gauss() * spread * 0.6,
		err_z = _gauss() * spread * 0.5, stretch = stretch}
	# unforced errors: likelier against pace, on reflex volleys, when stretched, and the less
	# skilled the player
	var incoming := ball.v.length()
	var volley := absf(ball.p.z) < 4.5
	var chance := 0.03 + 0.10 * (1 - sk) + (0.05 if incoming > 18 else 0.0) + (0.07 if volley else 0.0) + (0.12 if stretch else 0.0)
	if rng.randf() < chance:
		var k := rng.randf()
		o.miss = "net" if k < 0.4 else ("long" if k < 0.7 else "wide")
	hit(p, o)

## who on `team` takes the ball and where: the first point of the flight a player can reach
## in time at a comfortable height
func make_plan(team: int):
	var s := side_of(team)
	var samples := ball.predict(4.0, SUB, 3)
	var best = null
	for p in players:
		if p.team != team:
			continue
		var hmax := 2.3 if p.role == "front" else 1.7
		for sm in samples:
			var on_side: bool = sm.z * s > 0.4
			var legal: bool = (not is_serve or sm.bounces >= 1) and sm.bounces <= 1
			if on_side and legal and sm.y > 0.28 and sm.y < hmax and absf(sm.x) < TennisCourt.HALF_W + 3:
				# stand beside the ball: forehand (ball on the right) or backhand, whichever is nearer
				var r := right_of(team)
				var fx: float = sm.x - r * REACH
				var bx: float = sm.x + r * REACH
				var use_fore := absf(fx - p.pos.x) <= absf(bx - p.pos.x) + 0.3
				var sx := fx if use_fore else bx
				var sz: float = sm.z + s * 0.15
				# each player keeps to their part of the court: nobody hugs the net
				var zone_ok := absf(sz) >= (2.4 if p.role == "front" else 4.5)
				var d := Vector2(sx - p.pos.x, sz - p.pos.z).length()
				var need := d / RUN + 0.12
				var stretch: bool = need > sm.t
				if zone_ok and need <= sm.t + 0.08:
					if best == null or sm.t < best.dt - (0.0 if p.role == "front" else 0.05):
						best = {player = p, dt = sm.t, tc = t + sm.t, sample = sm, stand = Vector2(sx, sz),
							side = "fore" if use_fore else "back", stretch = stretch, leave = false, swing = null, done = false}
					break
	# will it land out? a good computer player lets it go
	if best != null and not is_human(team):
		var first_bounce = null
		for sm in samples:
			if sm.bounces >= 1:
				first_bounce = sm
				break
		if first_bounce != null and best.sample.bounces == 0 and not TennisCourt.in_court(first_bounce.x, first_bounce.z, s, TennisBall.R):
			if rng.randf() < 0.55 + 0.4 * skill:
				best.leave = true
	return best

# ------------------------------------------------------------------ a person's swing

## sw = { power 0..1, shape "flat" / "slice" / "lob", aim -1..1 }. Returns "toss", "early",
## "serve", "hit" or "miss"
func swing(team: int, sw: Dictionary) -> String:
	if not is_human(team):
		return ""
	if state == "serve" and serve_team == team and not moving():
		toss() # a swing before tossing tosses first
		return "toss"
	if state == "toss" and serve_team == team:
		if ball.p.y < 1.7:
			return "early"
		var q := 1.0 - clampf(absf(t - toss_peak_t) / 0.25, 0, 1)
		serve_hit(sw.get("power", 0.5), sw.get("aim", 0.0), q)
		return "serve"
	if state == "rally" and plan != null and plan.player.team == team and plan.swing == null:
		var o: float = t - plan.tc
		if o >= -EARLY and o <= LATE:
			plan.swing = {o = o, power = sw.get("power", 0.5), shape = sw.get("shape", "flat")}
			plan.player.state = "swing"
			plan.player.state_t = minf(0.0, o) # the racket meets the ball at state_t = 0
			plan.player.swing_side = plan.side
			plan.player.swing_shape = sw.get("shape", "flat")
			if o >= 0:
				human_hit(plan)
			return "hit"
	# swinging at nothing: the nearest player of the team swings anyway
	var p: Dictionary = plan.player if (plan != null and plan.player.team == team) else player(team, 1)
	if p.state != "swing":
		p.state = "swing"
		p.state_t = 0.0
	emit({kind = "whiff", team = team})
	return "miss"

func human_hit(pl: Dictionary) -> void:
	var sw: Dictionary = pl.swing
	# timing to direction: early pulls across the body, late pushes the other way; mirrored
	# for a backhand. The very edges of the window are mistimed: the ball flies wide
	var u: float
	if sw.o < CENTRE:
		u = (sw.o - CENTRE) / (EARLY + CENTRE)
	else:
		u = (sw.o - CENTRE) / (LATE - CENTRE)
	u = clampf(u * WIDE_AT, -WIDE_AT, WIDE_AT)
	var dir := u if pl.side == "fore" else -u
	var o := {power = sw.power, dir = clampf(dir, -1, 1), shape = sw.shape, stretch = pl.stretch}
	if absf(u) > 1:
		o.miss = "wide"
	hit(pl.player, o)

# ------------------------------------------------------------------ rules

func point_to(team: int, reason: String) -> void:
	if state == "point" or state == "over":
		return
	var res := rules.point(team)
	state = "point"
	state_t = 0.0
	ball_live = false
	plan = null
	faults = 0
	for p in players:
		p.state = "cheer" if p.team == team else "sad"
		p.state_t = 0.0
	emit({kind = "point", team = team, reason = reason, game = res.game, match = res.match,
		call = "" if res.game != 0 else rules.call_text()})
	if res.match != 0:
		over = true

func fault() -> void:
	faults += 1
	if faults >= 2:
		emit({kind = "fault", double = true})
		faults = 0
		point_to(3 - serve_team, "double fault")
		return
	emit({kind = "fault", double = false})
	state = "fault"
	state_t = 0.0
	ball_live = false

func on_bounce(ev: Dictionary) -> void:
	var side := 1 if ev.z > 0 else 2 # team whose half it bounced in
	var hitter := last_hit
	if hitter == 0:
		return
	if is_serve:
		var rt := 3 - hitter
		var box := TennisCourt.service_box(side_of(rt), rules.deuce_court())
		if side == rt and TennisCourt.in_box(ev.x, ev.z, box, TennisBall.R):
			if let_:
				emit({kind = "let"})
				state = "fault" # replay the serve, no fault counted
				state_t = 0.0
				faults -= 1
				ball_live = false
				return
			is_serve = false
			bounces = 1
			emit({kind = "bounce", x = ev.x, z = ev.z, inn = true})
		else:
			emit({kind = "bounce", x = ev.x, z = ev.z, inn = false})
			fault()
		return
	if side == hitter:
		emit({kind = "bounce", x = ev.x, z = ev.z, inn = false})
		point_to(3 - hitter, "net")
		return
	bounces += 1
	if bounces == 1:
		var inn := TennisCourt.in_court(ev.x, ev.z, side_of(side), TennisBall.R)
		emit({kind = "bounce", x = ev.x, z = ev.z, inn = inn})
		if not inn:
			point_to(side, "out")
	else:
		emit({kind = "bounce", x = ev.x, z = ev.z, inn = true})
		point_to(hitter, "winner")

# ------------------------------------------------------------------ update

func _approach(p: Dictionary, g: Vector2, dt: float, speed: float) -> void:
	var d := g - Vector2(p.pos.x, p.pos.z)
	var dl := d.length()
	var want := Vector2.ZERO
	if dl > 0.02:
		want = d / dl * minf(speed, dl * 6) # slow down on arrival
	var a: Vector2 = want - p.vel
	var lim := ACCEL * dt
	if a.length() > lim:
		a = a.normalized() * lim
	p.vel += a
	p.pos.x += p.vel.x * dt
	p.pos.z += p.vel.y * dt
	if dl < 0.02:
		p.pos.x = g.x
		p.pos.z = g.y
		p.vel = Vector2.ZERO

func _step_players(dt: float) -> void:
	var bx := ball.p.x
	for p in players:
		p.state_t += dt
		if (p.state == "swing" or p.state == "serve") and p.state_t > 0.55:
			p.state = "ready"
		if p.state == "toss" and state != "toss" and p.state_t > 0.2 and state != "rally":
			p.state = "ready"
		var g: Vector2
		if state == "serve" or state == "point" or state == "fault":
			g = p.goal
		elif state == "toss":
			g = Vector2(p.pos.x, p.pos.z)
		elif plan != null and plan.player == p and not plan.leave:
			g = plan.stand
		else:
			g = home_for(p, bx)
		_approach(p, g, dt, RUN * 0.6 if (state == "point" or state == "fault") else RUN)

func step_once() -> void:
	var dt := SUB
	t += dt
	state_t += dt
	match state:
		"serve":
			hold_ball()
			if state_t >= 0.3 and not moving() and not is_human(serve_team) and state_t > 1.0:
				toss()
		"toss":
			ball.step(dt)
			if not is_human(serve_team) and t >= toss_peak_t + (rng.randf() - 0.5) * 0.02:
				serve_hit(clampf(0.45 + 0.4 * skill + (rng.randf() - 0.5) * 0.3, 0, 1), rng.randf() * 2 - 1, 0.6 + 0.4 * rng.randf())
				# the computer's serve can go out: nudge the landing by its accuracy
				if rng.randf() < 0.18 - 0.12 * skill:
					ball.v.z *= 1.08
			elif ball.p.y < 1.15 and ball.v.y < 0:
				# caught it: toss again
				state = "serve"
				state_t = 0.3
				server.state = "ready"
				emit({kind = "catch"})
		"rally":
			_step_rally(dt)
		"fault":
			ball.step(dt)
			if state_t > 1.2:
				state = "serve"
				state_t = 0.0
				hold_ball()
		"point":
			ball.step(dt)
			if state_t > POINT_PAUSE:
				if rules.over:
					state = "over"
				else:
					new_point()
	_step_players(dt)

func _step_rally(dt: float) -> void:
	var ev := ball.step(dt)
	match ev.get("kind", ""):
		"bounce": on_bounce(ev)
		"net":
			emit({kind = "net"})
			net_t = t
		"cord":
			emit({kind = "cord"})
			if is_serve:
				let_ = true
	if state != "rally":
		return
	# whose ball is it?
	var toward := 1 if ball.v.z > 0 else 2
	if last_hit != 0 and toward != last_hit and (plan == null or plan_for != last_hit):
		plan = make_plan(toward)
		plan_for = last_hit
	var pl = plan
	if pl != null and not pl.leave:
		var team: int = pl.player.team
		if is_human(team):
			if pl.swing != null and t >= pl.tc and not pl.done:
				pl.done = true
				human_hit(pl)
			elif pl.swing == null and t > pl.tc + LATE:
				pl.missed = true
				plan = null
		elif t >= pl.tc:
			pl.player.swing_side = pl.side
			cpu_hit(pl.player)
		elif t >= pl.tc - 0.3 and pl.player.state != "swing":
			pl.player.state = "swing" # start the swing a little early
			pl.player.state_t = -0.3
			pl.player.swing_side = pl.side
	# a ball that died in the net, or stopped bouncing and rolls, ends the point
	var b := ball
	var dead: bool = (net_t != null and t - net_t > 1.2) or (b.p.y <= TennisBall.R + 1e-4 and absf(b.v.y) < 1e-6 and last_hit != 0)
	if state == "rally" and dead:
		var side := 1 if b.p.z > 0 else 2
		if is_serve: fault()
		elif side == last_hit: point_to(3 - last_hit, "net")
		elif bounces >= 1: point_to(last_hit, "winner")
		else: point_to(side, "out")
	# a ball that's gone far away is done
	if state == "rally" and (absf(b.p.z) > TennisCourt.HALF_LEN + 12 or absf(b.p.x) > TennisCourt.HALF_W + 10):
		var side := 1 if b.p.z > 0 else 2
		if side != last_hit:
			point_to(side, "out")

## advance real time dt
func update(dt: float) -> void:
	acc = minf(acc + dt, 0.1)
	while acc >= SUB:
		acc -= SUB
		step_once()

## time until the team's next contact (for "swing now" hints), or null
func contact_in(team: int):
	if plan != null and plan.player.team == team and not plan.leave:
		return plan.tc - t
	return null
