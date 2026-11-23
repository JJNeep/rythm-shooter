## Autoload: Score
extends Node

signal changed(score: int, combo: int, multiplier: int)
signal graded(grade: int, err_sec: float, points: int, did_hit: bool, on_beat: bool)
signal energy_changed(energy: float)
signal run_failed

const POINTS := [100, 60, 25, 0]        # PERFECT, GREAT, GOOD, WHIFF
const MULT_AT := [0, 4, 10, 20, 35]     # combo needed for x1..x5

## Beat Saber's energy model, and the reason clicking becomes a decision.
##
## A connected shot gives back a trickle; a miss costs roughly seven times as
## much. So spraying at the beat grid in the hope of catching something is not
## free, it is actively how you die, and you have to choose which beats are
## worth spending. Swarm contact and taking an enemy shot cost more again.
const ENERGY_START := 0.5

## Energy change for a shot that CONNECTS, indexed by grade:
##   PERFECT  GREAT  GOOD  WHIFF
##
## GOOD is exactly zero on purpose. It is the "keeping up" grade, so a run of
## GOODs neither drowns you nor carries you and the bar only climbs when your
## timing actually sharpens.
##
## Before this, every connected hit paid the same flat trickle whatever the
## grade, so good play and great play were worth the same -- and since a miss
## cost seven times a hit, the bar drained no matter how well you played. A
## 78% accuracy run ended on 8% energy, which is not a difficulty curve, it is
## a leak.
const ENERGY_BY_GRADE := [0.030, 0.015, 0.0, -0.030]

## A shot that connects with nothing at all. Firing into empty air is the real
## mistake, and this is what keeps spraying the grid expensive.
const ENERGY_MISS := 0.055
const ENERGY_SWARM := 0.10
const ENERGY_SHOT := 0.06

## Comeback curve. Below COMEBACK_UNTIL every connected shot is worth more, and
## the further down you are the more it pays, up to COMEBACK_BOOST times face
## value plus a flat COMEBACK_FLOOR trickle.
##
## Why: the flat economy above is fine while you are healthy and brutal once you
## are not. A run that went well up to one bad patch would sit at 15% and have
## to land thirty clean shots to get back, which is longer than most stretches
## of level -- so a single mistake quietly decided the run several spaces before
## it actually ended. The curve is identical to the old one at 60% and above, so
## nothing about playing well changes; it only puts a rope in the hole.
##
## The FLOOR is what makes a GOOD worth taking when you are in trouble. At full
## health GOOD is still exactly zero, which is the rule: good keeps it the same,
## better takes it up.
const COMEBACK_UNTIL := 0.60
const COMEBACK_BOOST := 2.5
const COMEBACK_FLOOR := 0.012

## Seconds of immunity after world damage -- swarm contact or an enemy shell.
##
## Not for fairness, for arithmetic: horde runners arrive as a group and each
## one spends itself on contact, so being clipped by the front of a pack used to
## charge four separate touches inside half a second and delete 40% of the bar
## before you could react. One touch costs full price, the rest of that moment
## is free, and the pack still dies.
const DAMAGE_GRACE := 0.6

var score: int = 0
var combo: int = 0
var best_combo: int = 0
var shots: int = 0
var hits: int = 0

## Per-grade counts of shots that CONNECTED, plus shots that hit nothing.
## Together they are what the end-of-run rank is computed from.
var grade_tally := [0, 0, 0, 0]
var missed: int = 0

## Running timing bias. Only shots within +/-150ms are counted, so a couple of
## wild clicks cannot drag the average -- what is wanted here is whether the
## player is SYSTEMATICALLY early or late, which is the signature of
## uncompensated audio latency rather than of bad rhythm.
var err_sum: float = 0.0
var err_count: int = 0

## Counted shots needed before the running bias is worth acting on. Below this
## it is a handful of clicks, not a measurement.
const BIAS_MIN_SHOTS := 12

var energy: float = ENERGY_START
var failed: bool = false
## Wall-clock seconds at the last world hit, for the grace window. Deliberately
## not song time: it has to work on the results screen and in the sandboxes too.
var _last_damage: float = -99.0
## Practice mode keeps the bar visible but never ends the run.
var practice: bool = false

## Weight of each grade towards the rank. A GOOD is worth about a third of a
## PERFECT, so "S is every beat perfect" holds: you cannot coast to an S on
## volume alone.
const GRADE_WEIGHT := [1.0, 0.7, 0.35, 0.0]
const RANK_AT := [[0.95, "SS"], [0.86, "S"], [0.75, "A"],
	[0.62, "B"], [0.48, "C"], [0.32, "D"]]
const RANK_COLOUR := {
	"SS": Color(1.0, 0.85, 0.35), "S": Color(1.0, 0.78, 0.30),
	"A": Color(0.40, 1.0, 0.65), "B": Color(0.45, 0.80, 1.0),
	"C": Color(0.80, 0.80, 0.90), "D": Color(1.0, 0.65, 0.35),
	"E": Color(1.0, 0.35, 0.40),
}


## 0..1. Every shot you took, weighted by how cleanly it landed.
func quality() -> float:
	if shots <= 0:
		return 0.0
	var q := 0.0
	for g in 4:
		q += GRADE_WEIGHT[g] * float(grade_tally[g])
	return q / float(shots)


func rank() -> String:
	var q := quality()
	for r in RANK_AT:
		if q >= float(r[0]):
			return str(r[1])
	return "E"


func rank_colour() -> Color:
	return RANK_COLOUR.get(rank(), Color.WHITE)


## Signed seconds. Positive means consistently late.
func mean_error() -> float:
	return err_sum / float(maxi(err_count, 1))


## Forget the timing bias measured so far, without touching score or accuracy.
## Called after the offset has been corrected mid-run: the shots before the
## correction were graded against a different grid and no longer describe it.
func clear_timing() -> void:
	err_sum = 0.0
	err_count = 0


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
	if did_hit:
		grade_tally[grade] += 1
	else:
		missed += 1
	if absf(err_sec) < 0.15:
		err_sum += err_sec
		err_count += 1

	var pts := 0
	if grade < 3 and did_hit:
		hits += 1
		combo += 1
		best_combo = maxi(best_combo, combo)
		pts = POINTS[grade] * multiplier
		score += pts
		_add_energy(_gain(grade))
	else:
		combo = 0
		# A connected-but-sloppy shot is only a small loss; a shot that hit
		# nothing is the expensive one.
		_add_energy(_gain(grade) if did_hit else -ENERGY_MISS)
	graded.emit(grade, err_sec, pts, did_hit, on_beat)
	changed.emit(score, combo, multiplier)


## 0 when healthy, rising to 1 as the bar empties. Drives the comeback curve and
## the HUD's recovery readout.
func deficit() -> float:
	return clampf((COMEBACK_UNTIL - energy) / COMEBACK_UNTIL, 0.0, 1.0)


## What a connected shot is actually worth. Face value while healthy, face value
## plus the comeback curve once you are below COMEBACK_UNTIL. A sloppy shot is
## never helped -- only the grades that already paid get paid more.
func _gain(grade: int) -> float:
	var base: float = ENERGY_BY_GRADE[grade]
	if base < 0.0:
		return base
	var d := deficit()
	return base * (1.0 + d * (COMEBACK_BOOST - 1.0)) + d * COMEBACK_FLOOR


## Damage from the world rather than from a bad click. Honours the grace window,
## so one moment of contact costs once however many bodies were in it.
func drain(amount: float) -> void:
	combo = 0
	var now := Time.get_ticks_msec() * 0.001
	if now - _last_damage < DAMAGE_GRACE:
		changed.emit(score, combo, multiplier)
		return
	_last_damage = now
	_add_energy(-amount)
	changed.emit(score, combo, multiplier)


func _add_energy(delta: float) -> void:
	if failed:
		return
	energy = clampf(energy + delta, 0.0, 1.0)
	energy_changed.emit(energy)
	if energy <= 0.0 and not practice:
		failed = true
		run_failed.emit()


func reset() -> void:
	score = 0
	combo = 0
	best_combo = 0
	shots = 0
	hits = 0
	grade_tally = [0, 0, 0, 0]
	missed = 0
	err_sum = 0.0
	err_count = 0
	energy = ENERGY_START
	failed = false
	_last_damage = -99.0
	energy_changed.emit(energy)
	changed.emit(score, combo, multiplier)
