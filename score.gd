## Autoload: Score
extends Node

signal changed(score: int, combo: int, multiplier: int)
signal graded(grade: int, err_sec: float, points: int, did_hit: bool, on_beat: bool)

const POINTS := [100, 60, 25, 0]        # PERFECT, GREAT, GOOD, WHIFF
const MULT_AT := [0, 4, 10, 20, 35]     # combo needed for x1..x5

var score: int = 0
var combo: int = 0
var best_combo: int = 0
var shots: int = 0
var hits: int = 0

var multiplier: int:
	get:
		var m := 1
		for i in MULT_AT.size():
			if combo >= MULT_AT[i]:
				m = i + 1
		return m


## A shot needs good timing AND a connection to build the meter. Hitting a wall
## perfectly on the beat should not reward you.
## Offbeats score exactly the same as downbeats -- every slot on the grid is
## equally valid. If you later want syncopation to feel special, this is the
## place to add a bonus for `not on_beat`.
func register(grade: int, err_sec: float, did_hit: bool, on_beat: bool = true) -> void:
	shots += 1
	var pts := 0
	if grade < 3 and did_hit:
		hits += 1
		combo += 1
		best_combo = maxi(best_combo, combo)
		pts = POINTS[grade] * multiplier
		score += pts
	else:
		combo = 0
	graded.emit(grade, err_sec, pts, did_hit, on_beat)
	changed.emit(score, combo, multiplier)


func reset() -> void:
	score = 0
	combo = 0
	best_combo = 0
	shots = 0
	hits = 0
	changed.emit(score, combo, multiplier)
