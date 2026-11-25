## Referees a run. It does not build anything any more.
##
## The level is a scene: open levels/aftermath.tscn, drag blocks around, save,
## press F5. Everything that used to be generated from chart.gd now exists as
## nodes you can select, and the pacing contract lives on the level root --
## see blocks/level_root.gd.
##
## What is left in here is the job of a referee: place the player, start the
## music, watch for the three ways a run can end, and tally it up.
extends Node3D

enum State { RUNNING, FINISHED, FAILED }

const SONG_PATH := "res://Aftermath.tres"
const HUD_PATH := "res://hud.gd"
const DEFAULT_LEVEL := "res://levels/aftermath.tscn"

## How close to the finish marker counts as finishing. Small, because the
## marker is drawn as a gate and crossing it should be what ends the run.
const FINISH_MARGIN := 3.0
const KILL_Y := -28.0

## Swap this to play a different level. A level is any scene whose root has
## blocks/level_root.gd on it, holding a START marker and a FINISH marker.
@export var level_scene: PackedScene

var state: int = State.RUNNING

# Untyped: the player carries members CharacterBody3D does not declare.
var _player
var _hud
var _level: LevelRoot
var _pursuit: Pursuit
var _best_z := 0.0
var _finish_time := 0.0


func _ready() -> void:
	add_to_group("world")
	randomize()

	_level = _load_level()
	if _level == null:
		push_error("No level to run. Set level_scene, or restore %s." % DEFAULT_LEVEL)
		return

	_hud = CanvasLayer.new()
	_hud.set_script(load(HUD_PATH))
	add_child(_hud)

	_player = get_node_or_null("Player")
	if _player:
		# The START marker is the spawn, so moving it in the editor moves the
		# spawn. 1.8 lifts the capsule centre onto the floor it is standing on.
		_player.global_position = _level.start_position() + Vector3(0.0, 1.8, 0.0)
		_player.velocity = Vector3.ZERO
		_level.bind(_player)

	_pursuit = Pursuit.new()
	add_child(_pursuit)
	if _player:
		_pursuit.bind(_player, _level)
		if _hud.ring:
			_hud.ring.gun = _player.gun
		_hud.bind_player(_player)
	_pursuit.caught.connect(_on_caught)
	Score.run_failed.connect(_on_failed)
	# Not a loop: the end of the track is the deadline, so it has to be heard.
	Conductor.song_ended.connect(_on_song_ended)

	Score.reset()
	Conductor.start(load(SONG_PATH))
	if Settings.calibrated:
		_hud.show_banner("GO", "stay ahead of the wall  ·  2 to launch yourself")
	else:
		# Uncalibrated audio reads exactly like bad rhythm, so say so up front
		# rather than letting the player conclude the grading is broken.
		_hud.show_banner("GO", "audio not calibrated yet — press C to fix late hits")


## A level already placed in this scene wins, so you can drop one in as a child
## to look at it in the editor. Otherwise the exported scene is instanced.
func _load_level() -> LevelRoot:
	var existing := get_node_or_null("Level")
	if existing is LevelRoot:
		return existing as LevelRoot

	var scene := level_scene
	if scene == null and ResourceLoader.exists(DEFAULT_LEVEL):
		scene = load(DEFAULT_LEVEL)
	if scene == null:
		return null

	var node := scene.instantiate()
	if not (node is LevelRoot):
		push_error("%s is not a level: its root needs blocks/level_root.gd."
			% scene.resource_path)
		node.free()
		return null
	node.name = "Level"
	add_child(node)
	return node as LevelRoot


# -------------------------------------------------------------- refereeing ---

func _on_caught() -> void:
	if state != State.RUNNING:
		return
	if Score.practice:
		_pursuit.disarm()        # stop it rather than let it swallow the camera
		_hud.show_banner("PASSED", "practice mode, carry on")
		return
	_fail("CAUGHT", "the wall got you")


func _on_failed() -> void:
	if state != State.RUNNING:
		return
	_fail("BURNED OUT", "energy hit zero")


## The track ran out with the player still on the course. The wall is timed to
## reach the finish exactly here, so this is the same loss as being caught --
## it just means the wall ran out of level before it ran out of you.
func _on_song_ended() -> void:
	if state != State.RUNNING:
		return
	if Score.practice:
		return
	_fail("OUT OF TIME", "the song finished without you")


func _fail(title: String, sub: String) -> void:
	state = State.FAILED
	_pursuit.disarm()
	_hud.set_danger(0.0)
	# A death gets the track switched off, not the song's ending -- that is the
	# reward for reaching the line.
	Conductor.fade_out()
	if _player:
		_player.freeze()
	_hud.show_banner(title, "%s  ·  R to restart" % sub)


func _finish() -> void:
	state = State.FINISHED
	_pursuit.disarm()
	_hud.set_danger(0.0)
	_finish_time = Conductor.clock()
	if _player:
		_player.freeze()
	# The music is deliberately NOT cut here. A good run crosses the line
	# several seconds early -- that early arrival is what the slack is for --
	# and washing the track out mid-phrase at whatever second you happened to
	# finish sounds like a mistake. It plays on to the end of the level's slice,
	# which is chosen to be a break in the music, and washes out there. See
	# _process.

	var acc := 0.0
	if Score.shots > 0:
		acc = 100.0 * float(Score.hits) / float(Score.shots)
	# How much song was left. The level is cut so that even a very good run
	# lands with some outro still playing, which is the results screen.
	var spare := _level.song_seconds() - _finish_time

	# Timing bias is reported whether or not it is bad, because a player who
	# feels like they are on the beat and keeps getting WHIFF has no other way
	# to discover that their audio is simply arriving late.
	var bias := Score.mean_error() * 1000.0
	var timing := "%+.0f ms" % bias
	if absf(bias) > 25.0:
		timing += "   consistently %s — press C" % ("late" if bias > 0.0 else "early")

	# Score and rank are handed over apart from the rows so each gets a moment.
	_hud.show_tally([
		["TIME", "%.1fs   (%.1fs of song spare)" % [_finish_time, spare]],
		["ACCURACY", "%.0f%%   (%d / %d)" % [acc, Score.hits, Score.shots]],
		["TIMING", timing],
		["BEST COMBO", "%d" % Score.best_combo],
		["ENERGY LEFT", "%.0f%%" % (Score.energy * 100.0)],
	], Score.score, Score.rank(), Score.rank_colour())


func _process(_delta: float) -> void:
	# The outro. After the line the track carries on to the end of the level's
	# slice and stops there. level_seconds is a break in the music, and for
	# Aftermath it is the bottom of a long decay, so what the player hears is
	# the song running itself out while the tally goes up. Cross the line late
	# and it stops at once, which is the same thing.
	if state == State.FINISHED and Conductor.running \
			and Conductor.clock() >= _level.song_seconds():
		Conductor.fade_out(Conductor.STOP_SECONDS)

	if _player == null or _level == null or state != State.RUNNING:
		return

	var pz: float = _player.global_position.z
	_best_z = minf(_best_z, pz)

	# Off the level. In practice mode you get put back on your feet just ahead
	# of the wall instead of losing the run.
	if _player.global_position.y < KILL_Y:
		if Score.practice:
			_player.global_position = Vector3(0.0, 2.0, _pursuit.wall_z - 8.0)
			_player.velocity = Vector3.ZERO
		else:
			_fail("FELL", "mind the gaps")
			return

	if pz <= _level.finish_z() + FINISH_MARGIN:
		_finish()
		return

	# The deadline is the level's own slice of the track, not the end of the
	# file. Checked after the finish line so crossing it on the last beat is a
	# win and not a dead heat.
	#
	# Mostly a backstop: a player still on the course when the clock runs out
	# has normally been caught already, since the wall arrives here at the same
	# moment. Practice mode has no deadline, the same way it has no wall.
	if not Score.practice and Conductor.running \
			and Conductor.clock() >= _level.song_seconds():
		_fail("OUT OF TIME", "the wall reached the end without you")
		return

	var lead := _pursuit.lead(pz)
	_hud.set_status("%dm / %dm    wall %+.0fm" % [
		int(-pz), int(-_level.finish_z()), lead])
	_hud.set_danger(clampf(1.0 - lead / 26.0, 0.0, 1.0))
