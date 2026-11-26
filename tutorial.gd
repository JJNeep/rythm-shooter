## Teaches the game by getting in the way.
##
## Every station is an obstacle that exactly one mechanic clears, and the text
## only ever tells you which button and how its timing works. It never says
## "you need the rocket launcher" -- there is an eight metre wall with no stairs
## on it, which has already said that more convincingly than a line of text can.
##
## So the level is the teacher and this script is only the narrator. It watches
## for the player reaching each station, puts up that station's prompt, and
## watches for the one thing that counts as having solved it. The only station
## that needs help from code is the first shooting one, where nothing physical
## can tell whether you hit anything -- so that one has a literal gate, and the
## referee drops it once you have landed your shots.
##
## Nothing here can fail. Falling puts you back at the top of the station you
## are on, energy never ends the run, and ENTER leaves for a real run at any
## point. Being stuck is the only thing a tutorial must never do.
extends Node3D

const SONG_PATH := "res://Aftermath.tres"
const HUD_PATH := "res://hud.gd"
const DEFAULT_LEVEL := "res://levels/tutorial.tscn"
const RUN_SCENE := "res://run_level.tscn"

const KILL_Y := -24.0
const WALL_SPEED := 9.6          # 69% of top speed: visible, losable, survivable
const WALL_BEHIND := 34.0

## Hits needed to open the gate at the shooting station. Low enough that a
## player who cannot find the beat at all still gets through after a while.
const GATE_HITS := 4

@export var level_scene: PackedScene

## One entry per station, in order. `at` is filled in from the level's own
## markers, so moving a space in the editor moves its prompt with it.
##
## `goal` is what counts as done:
##   "walk"   reached the next station on foot
##   "hits"   landed GATE_HITS shots that connected and were on time
##   "reach"  got to the next station, which the geometry made the lesson
##   "up"     got onto the high platform, which only the rocket reaches
##   "finish" crossed the line
var _steps := [
	{
		"name": "T1_Move",
		"title": "MOVE",
		"how": "WASD to walk, mouse to look.\nFollow the lane markers -- they are one beat apart at a sprint.",
		"goal": "walk",
		"spawn": Vector3(0.0, 2.0, -6.0),
	},
	{
		"name": "T2_Shoot",
		"title": "SHOOT ON THE BEAT",
		"how": "Click. The gun will not fire off the beat -- it fires on the nearest one, and how late you were is how far it misses.\nThe ring closes on the beat. Click as it lands.",
		"goal": "hits",
		"spawn": Vector3(0.0, 2.0, -50.0),
	},
	{
		"name": "T3_Jump",
		"title": "JUMP",
		"how": "SPACE. Height is fixed -- there is no charging it.\nPERFECT and GREAT shots fill the energy bar, WHIFF empties it. Keep an eye on it.",
		"goal": "reach",
		"spawn": Vector3(0.0, 3.8, -100.0),
	},
	{
		"name": "T4_Dash",
		"title": "DASH ON THE BEAT",
		"how": "SHIFT dashes you forward. ON the beat it throws you twice as far as off it -- that is the whole difference between clearing this and not.\nJump first, then dash.",
		"goal": "reach",
		"spawn": Vector3(0.0, 3.8, -134.0),
	},
	{
		"name": "T5_Rocket",
		"title": "THE ROCKET LAUNCHER",
		"how": "Press 2. It fires on whole beats and reloads over four.\nThe blast throws whatever is near it, including you. Point it at your own feet and fire.",
		"goal": "up",
		"spawn": Vector3(0.0, 3.8, -180.0),
	},
	{
		"name": "T6_Gunners",
		"title": "READ THE TELEGRAPH",
		"how": "These shoot back. Each one flashes a beat before it fires, and the shell lands a beat after that.\nTwo beats of warning, both on the grid. Shoot them or be elsewhere.",
		"goal": "reach",
		"spawn": Vector3(0.0, 11.8, -196.0),
	},
	{
		"name": "T7_Wall",
		"title": "THE WALL",
		"how": "It is behind you now. The wall is the song's playhead drawn into the level, so it never stops and it cannot be fought.\nRun. The finish line is ahead.",
		"goal": "finish",
		"spawn": Vector3(0.0, 11.8, -262.0),
	},
]

var _level: LevelRoot
var _hud
var _player
var _pursuit: Pursuit
var _at := -1
var _hits := 0
var _whiffs := 0
var _done := false
var _panel: CanvasLayer
var _title: Label
var _how: Label
var _goal: Label


func _ready() -> void:
	add_to_group("world")
	randomize()

	_level = _load_level()
	if _level == null:
		push_error("No tutorial level. Restore %s." % DEFAULT_LEVEL)
		return
	_read_station_positions()

	_hud = CanvasLayer.new()
	_hud.set_script(load(HUD_PATH))
	add_child(_hud)
	_build_panel()

	_player = get_node_or_null("Player")
	if _player:
		_level.bind(_player)
		if _hud.ring:
			_hud.ring.gun = _player.gun
		_hud.bind_player(_player)

	# Nothing in a tutorial may end a run, and the track loops so the beat is
	# always there to practise against.
	Score.reset()
	Score.practice = true
	Conductor.start(load(SONG_PATH), true)
	Score.graded.connect(_on_graded)

	_enter(0)


func _exit_tree() -> void:
	# Practice mode is global and the real run must not inherit it.
	Score.practice = false


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
		push_error("%s is not a level." % scene.resource_path)
		node.free()
		return null
	node.name = "Level"
	add_child(node)
	return node as LevelRoot


## Each station's trigger is a marker inside its own space, so the level file
## decides where the prompts land rather than a table of numbers in here.
func _read_station_positions() -> void:
	for s in _steps:
		var space := _level.get_node_or_null(str(s["name"]))
		var marker: Node3D = space.get_node_or_null("At") if space else null
		s["z"] = marker.global_position.z if marker else 0.0


# ------------------------------------------------------------------- prompt ---

func _build_panel() -> void:
	_panel = CanvasLayer.new()
	_panel.layer = 11
	add_child(_panel)

	var back := ColorRect.new()
	back.color = Color(0.03, 0.02, 0.06, 0.74)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.anchor_left = 0.0
	back.anchor_top = 0.0
	back.anchor_right = 1.0
	back.anchor_bottom = 0.0
	back.offset_left = 0.0
	back.offset_top = 0.0
	back.offset_right = 0.0
	back.offset_bottom = 150.0
	_panel.add_child(back)

	_title = _label(28, HORIZONTAL_ALIGNMENT_CENTER, 10.0, 46.0)
	_title.modulate = Color(1.0, 0.86, 0.35)
	_how = _label(18, HORIZONTAL_ALIGNMENT_CENTER, 48.0, 110.0)
	_goal = _label(17, HORIZONTAL_ALIGNMENT_CENTER, 112.0, 142.0)
	_goal.modulate = Color(0.45, 0.95, 1.0)


func _label(size_px: int, align: int, top: float, bottom: float) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.anchor_right = 1.0
	l.offset_left = 80.0
	l.offset_right = -80.0
	l.offset_top = top
	l.offset_bottom = bottom
	_panel.add_child(l)
	return l


func _enter(index: int) -> void:
	if index <= _at or index >= _steps.size():
		return
	_at = index
	var s: Dictionary = _steps[index]
	_title.text = "%d / %d   %s" % [index + 1, _steps.size(), str(s["title"])]
	_how.text = str(s["how"])
	_hits = 0
	_whiffs = 0
	_refresh_goal()
	if str(s["goal"]) == "finish":
		_start_chase()


func _refresh_goal() -> void:
	if _done:
		return
	match str(_steps[_at]["goal"]):
		"hits":
			if _hits >= GATE_HITS:
				_goal.text = "the gate is open -- go through"
				return
			_goal.text = "land %d shots to open the gate      %d / %d" % [
				GATE_HITS, _hits, GATE_HITS]
			# Someone whose audio is late reads as someone with no rhythm, and
			# will believe the second explanation. Offer the first one.
			if _whiffs >= 6:
				_goal.text += "      feels off? press F to correct your timing"
		"up":
			_goal.text = "get onto the platform"
		"finish":
			_goal.text = "reach the finish line"
		_:
			_goal.text = "keep going"


func _on_graded(grade: int, _err: float, _pts: int, did_hit: bool, _on_beat: bool) -> void:
	if _done or _at < 0 or str(_steps[_at]["goal"]) != "hits":
		return
	if did_hit and grade < 3:
		_hits += 1
		if _hits >= GATE_HITS:
			_open_gate()
	else:
		_whiffs += 1
	_refresh_goal()


## Drops the one obstacle the geometry cannot judge for itself.
func _open_gate() -> void:
	for g in get_tree().get_nodes_in_group("tutorial_gate"):
		var body := g as StaticBody3D
		if body == null:
			continue
		body.collision_layer = 0
		var tw := create_tween()
		tw.tween_property(body, "position:y", body.position.y - 9.5, 0.45) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tw.tween_callback(body.hide)


func _start_chase() -> void:
	if _pursuit != null or _player == null:
		return
	_pursuit = Pursuit.new()
	add_child(_pursuit)
	_pursuit.chase_from(_player, _player.global_position.z + WALL_BEHIND, WALL_SPEED)
	_pursuit.caught.connect(_on_caught)


## Being caught in the tutorial is a lesson, not a loss: it says so and puts
## you back at the start of the sprint with the wall reset behind you.
func _on_caught() -> void:
	if _done:
		return
	_hud.show_banner("CAUGHT", "that is how a run ends  ·  try again")
	_respawn()
	if _pursuit:
		_pursuit.queue_free()
		_pursuit = null
	_start_chase()


func _respawn() -> void:
	if _player == null or _at < 0:
		return
	_player.global_position = _steps[_at]["spawn"]
	_player.velocity = Vector3.ZERO


func _finish() -> void:
	_done = true
	if _pursuit:
		_pursuit.disarm()
	_title.text = "THAT IS ALL OF IT"
	_how.text = "A run is one song. The wall leaves the start line when the music does and arrives at the finish as the music ends, so the level is a race against the track itself."
	_goal.text = "ENTER for a real run      ·      R to run the tutorial again"
	_hud.show_banner("TUTORIAL COMPLETE", "ENTER for a real run")
	Settings.set_tutorial_done()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
	var key := event as InputEventKey
	if key.alt_pressed:
		return
	if key.physical_keycode == KEY_ENTER or key.physical_keycode == KEY_KP_ENTER:
		get_tree().change_scene_to_file(RUN_SCENE)


func _process(_delta: float) -> void:
	if _player == null or _level == null:
		return

	if _player.global_position.y < KILL_Y:
		_respawn()
		_hud.show_banner("", "back to the top of this one")
		return

	if _done:
		return

	var pz: float = _player.global_position.z

	# Reaching the next station is itself the proof that the last one was
	# solved, because the only way forward was through it.
	if _at + 1 < _steps.size() and pz <= float(_steps[_at + 1]["z"]):
		_enter(_at + 1)

	if str(_steps[_at]["goal"]) == "up" and _player.global_position.y > 8.0:
		_goal.text = "up there. now the gunners"

	if pz <= _level.finish_z() + 3.0:
		_finish()
		return

	_hud.set_status("%dm / %dm" % [int(-pz), int(-_level.finish_z())])
	if _pursuit:
		var lead := _pursuit.lead(pz)
		_hud.set_danger(clampf(1.0 - lead / 26.0, 0.0, 1.0))
