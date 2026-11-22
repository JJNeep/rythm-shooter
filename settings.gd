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


func _apply() -> void:
	Conductor.user_offset = audio_offset_ms * 0.001
