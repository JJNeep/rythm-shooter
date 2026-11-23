## Autoload: Settings
##
## Persists the one setting a rhythm game genuinely cannot do without: how late
## this player's audio actually reaches their ears. Declared AFTER Conductor in
## project.godot so the Conductor node exists by the time we push the offset in.
extends Node

const PATH := "user://settings.cfg"

## Positive means the player's setup runs late, so the Conductor treats the
## music as having arrived earlier than the engine reports.
var audio_offset_ms: float = 0.0

## Set once calibration has actually been run, so the game can tell the
## difference between a measured 0ms and never having measured at all.
var calibrated: bool = false


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		_apply()
		return
	audio_offset_ms = float(cfg.get_value("audio", "offset_ms", 0.0))
	calibrated = bool(cfg.get_value("audio", "calibrated", false))
	_apply()


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "offset_ms", audio_offset_ms)
	cfg.set_value("audio", "calibrated", calibrated)
	cfg.save(PATH)


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
