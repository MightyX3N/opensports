## Tennis scoring, Wii Sports style: doubles, love / 15 / 30 / 40 / deuce / advantage, matches
## of 1 game, best of 3 or best of 5. The serve rotates between the four players game by
## game and alternates between the deuce and advantage courts point by point.
class_name TennisRules
extends RefCounted

const CALLS := ["Love", "15", "30", "40"]

var to_win := 1
var points := [0, 0]
var games := [0, 0]
var game_no := 1
var over := false
var winner := 0
var history := []

func _init(games_to_win := 1) -> void:
	to_win = games_to_win

## who serves this game: [team, player] (team 1 p1, team 2 p1, team 1 p2, team 2 p2)
func server() -> Array:
	var k := (game_no - 1) % 4
	return [(k % 2) + 1, 1 if k < 2 else 2]

func deuce_court() -> bool:
	return (points[0] + points[1]) % 2 == 0

func receiver() -> Array:
	return [3 - server()[0], 1 if deuce_court() else 2]

## score a point for team t (1 or 2): { game = team or 0, match = team or 0 }
func point(t: int) -> Dictionary:
	if over:
		return {game = 0, match = 0}
	var o := 3 - t
	points[t - 1] += 1
	var res := {game = 0, match = 0}
	if points[t - 1] >= 4 and points[t - 1] - points[o - 1] >= 2:
		games[t - 1] += 1
		history.append({p = points.duplicate(), winner = t})
		res.game = t
		points = [0, 0]
		game_no += 1
		if games[t - 1] >= to_win:
			over = true
			winner = t
			res.match = t
	return res

## the umpire's call for the score, server first: "15-love", "30 all", "Deuce", "Advantage server"
func call_text(server_team := 0) -> String:
	var s: int = server_team if server_team > 0 else server()[0]
	var a: int = points[s - 1]
	var b: int = points[2 - s]
	if a >= 3 and b >= 3:
		if a == b: return "Deuce"
		return "Advantage server" if a > b else "Advantage receiver"
	if a == b:
		return "Love all" if a == 0 else CALLS[a] + " all"
	return CALLS[a] + "-" + CALLS[b].to_lower()

## points as the scoreboard shows them per team ("0", "15", "30", "40", "AD")
func board() -> Array:
	var out := []
	for t in 2:
		var a: int = points[t]
		var b: int = points[1 - t]
		if a >= 3 and b >= 3:
			out.append("AD" if a > b else "40")
		else:
			out.append(["0", "15", "30", "40"][mini(a, 3)])
	return out
