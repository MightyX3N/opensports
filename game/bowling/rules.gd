## Standard ten-pin game: 10 frames, strikes and spares, up to three balls in the 10th frame.
class_name BowlingRules
extends RefCounted

var frames := [] # list of lists of pins knocked down
var frame := 1
var ball := 1
var pin_count := 10
var over := false

## record a ball that knocked down n pins; returns what happened:
## { strike, spare, gutter, rerack, frame_done, game_over }
func record(n: int) -> Dictionary:
	while frames.size() < frame:
		frames.append([])
	var f: Array = frames[frame - 1]
	f.append(n)
	var P := pin_count
	var res := {pins = n, strike = false, spare = false, gutter = false, rerack = false, frame_done = false, game_over = false}
	if frame < 10:
		if f.size() == 1 and n == P:
			res.strike = true; res.frame_done = true
		elif f.size() == 2:
			if f[0] + f[1] == P: res.spare = true
			res.frame_done = true
	else:
		var k := f.size()
		var fresh: bool = k == 1 or f[k - 2] == P or (k == 3 and f[0] < P and f[0] + f[1] == P)
		if fresh and n == P: res.strike = true
		if not fresh and f[k - 2] + n == P: res.spare = true
		if k == 3 or (k == 2 and f[0] < P and f[0] + n < P):
			res.frame_done = true
		else:
			res.rerack = res.strike or res.spare
	if n == 0 and f.size() == 1:
		res.gutter = true
	if res.frame_done:
		res.rerack = true
		if frame == 10:
			over = true
			res.game_over = true
		else:
			frame += 1
		ball = 1
	else:
		ball = f.size() + 1
	return res

## running totals per frame (only as far as known)
func totals() -> Array:
	var P := pin_count
	var r := []
	var idx := []
	for f in frames:
		idx.append(r.size())
		r.append_array(f)
	var out := []
	var total := 0
	for fi in frames.size():
		var f: Array = frames[fi]
		var i: int = idx[fi]
		var score = null
		if fi < 9:
			if f.size() >= 1 and f[0] == P:
				if r.size() > i + 2: score = P + r[i + 1] + r[i + 2]
			elif f.size() >= 2:
				if f[0] + f[1] == P:
					if r.size() > i + 2: score = P + r[i + 2]
				else:
					score = f[0] + f[1]
		else:
			var need := 3 if (f.size() >= 1 and (f[0] == P or (f.size() >= 2 and f[0] + f[1] == P))) else 2
			if f.size() >= need:
				score = 0
				for x in f: score += x
		if score == null:
			break
		total += score
		out.append(total)
	return out

func total() -> int:
	var t := totals()
	return t[-1] if t.size() > 0 else 0

## scorecard marks for one frame (1-based): "X", "/", "-", digits
func marks(fi: int) -> Array:
	var P := pin_count
	if fi > frames.size():
		return []
	var f: Array = frames[fi - 1]
	var out := []
	for i in f.size():
		var n: int = f[i]
		var mark := ""
		if fi < 10:
			if i == 0 and n == P: mark = "X"
			elif i == 1 and f[0] + n == P: mark = "/"
		else:
			var prev = f[i - 1] if i > 0 else null
			var fresh: bool = i == 0 or prev == P or (i == 2 and f[0] + f[1] == P and f[0] < P)
			if fresh and n == P: mark = "X"
			elif not fresh and prev != null and prev + n == P: mark = "/"
		out.append(mark if mark != "" else ("-" if n == 0 else str(n)))
	return out
