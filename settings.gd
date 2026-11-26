## Autoload: Settings
##
## Persists the handful of things a player should only ever have to say once:
## how late their audio reaches their ears, and whether they want a window.
## Declared AFTER Conductor in project.godot so the Conductor node exists by the
## time we push the offset in.
##
## It also owns the two global hotkeys, because they have to work in every
## scene -- the run, the calibration screen and both sandboxes.
extends Node

const PATH := "user://settings.cfg"

## Optional. Defined in project.godot's input map if you want a rebindable key
## on top of the built-in F11 and alt+enter.
const ACTION := "fullscreen"

## Positive means the player's setup runs late, so the Conductor treats the
## music as having arrived earlier than the engine reports.
var audio_offset_ms: float = 0.0

## Set once calibration has actually been run, so the game can tell the
## difference between a measured 0ms and never having measured at all.
var calibrated: bool = false

## Remembered like the offset. Someone who plays in a window, so they can watch
## the song in another app or keep an eye on a frame counter, should not have to
## say so every launch.
var fullscreen: bool = true

## Set once the tutorial has been finished. Only used to decide whether to
## mention it on the start banner -- it is never forced on anyone, and T opens
## it again whenever you like.
var tutorial_done: bool = false


func _ready() -> void:
	load_settings()


## F11 is the convention; alt+enter is the one Windows players reach for
## without being told. Handled here rather than in the player so it also works
## on the calibration screen and the results screen.
##
## The project's own "fullscreen" action is honoured too, and checked first, so
## the key can be rebound in the editor's input map without touching code. The
## two built-ins stay regardless -- a player on someone else's build should not
## have to go looking for the binding.
func _input(event: InputEvent) -> void:
	if InputMap.has_action(ACTION) and event.is_action_pressed(ACTION):
		_toggle()
		return
	if not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
	var key := event as InputEventKey
	if key.physical_keycode == KEY_F11 \
			or (key.physical_keycode == KEY_ENTER and key.alt_pressed):
		_toggle()


func _toggle() -> void:
	set_fullscreen(not fullscreen)
	get_viewport().set_input_as_handled()


## Borderless fullscreen rather than exclusive, on purpose: it alt-tabs without
## a display mode switch, which matters when calibration sends someone off to
## look at their audio device.
func set_fullscreen(on: bool) -> void:
	fullscreen = on
	# A window mode switch can drop mouse capture, which mid-run would silently
	# stop both aiming and shooting -- the shoot handler is gated on capture.
	# Deferred because the mode change does not take effect within this call.
	var mouse := Input.mouse_mode
	_apply_window()
	Input.set_mouse_mode.call_deferred(mouse)
	save_settings()


func _apply_window() -> void:
	var want := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen \
		else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != want:
		DisplayServer.window_set_mode(want)


func is_fullscreen() -> bool:
	var m := DisplayServer.window_get_mode()
	return m == DisplayServer.WINDOW_MODE_FULLSCREEN \
		or m == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


func load_settings() -> void:
	var cfg := ConfigFile.new()
	var loaded := cfg.load(PATH) == OK
	# With nothing saved yet, take whatever the project opened with, so the very
	# first press of F11 changes something instead of re-asserting the mode.
	fullscreen = is_fullscreen()
	if loaded:
		audio_offset_ms = float(cfg.get_value("audio", "offset_ms", 0.0))
		calibrated = bool(cfg.get_value("audio", "calibrated", false))
		fullscreen = bool(cfg.get_value("video", "fullscreen", fullscreen))
		tutorial_done = bool(cfg.get_value("play", "tutorial_done", false))
	_apply()
	# Applied without saving: a plain launch should not rewrite the file, and
	# this only touches the window when the saved choice differs from how the
	# project opened it.
	_apply_window()


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "offset_ms", audio_offset_ms)
	cfg.set_value("audio", "calibrated", calibrated)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("play", "tutorial_done", tutorial_done)
	cfg.save(PATH)


func set_tutorial_done() -> void:
	if tutorial_done:
		return
	tutorial_done = true
	save_settings()


func set_offset_ms(ms: float, mark_calibrated: bool = true) -> void:
	audio_offset_ms = ms
	if mark_calibrated:
		calibrated = true
	_apply()
	save_settings()


## Fold the bias measured during actual play into the saved offset.
##
## The calibration screen measures a click track; this measures the thing you
## are really playing -- the same decode, the same chart, the same frame timing
## -- using shots you have already taken. So when a run feels late, the fix is
## one keypress rather than a trip to another scene.
##
## Returns the correction applied in ms, or 0.0 if there were not enough shots
## to trust. A handful of clicks is noise; this wants a sample.
func apply_measured_bias(min_shots: int = Score.BIAS_MIN_SHOTS) -> float:
	if Score.err_count < min_shots:
		return 0.0
	# Score counts a shot as LATE when it lands after its slot. Raising the
	# offset tells the Conductor the music reached the player even later than
	# that, which pulls the whole grid back under them.
	var bias := Score.mean_error() * 1000.0
	set_offset_ms(audio_offset_ms + bias)
	# The old bias must go with it, or the readout keeps reporting the error
	# that has just been corrected.
	Score.clear_timing()
	return bias


func _apply() -> void:
	Conductor.user_offset = audio_offset_ms * 0.001
