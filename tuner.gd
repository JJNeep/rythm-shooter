## Throwaway scene for measuring a song's BPM and offset by ear.
##
## Procedure, and the order matters:
##   1. Fix BPM first. Listen over 30+ seconds. If the click slowly DRIFTS away
##      from the kick, the BPM is wrong. Nudge until it holds.
##   2. Then fix the offset. If the click is consistently a hair early or late
##      but never drifts, the offset is wrong.
## Chasing the offset while the BPM is wrong will waste your afternoon.
##
## Note there is no get_output_latency() compensation here, deliberately: the
## click and the music both leave through the same output, so the latency
## cancels. In gameplay you DO subtract it, because there you are comparing a
## sound against a physical mouse click.
extends Control

const SONG_PATH := "res://Aftermath.tres"

var _music: AudioStreamPlayer
var _click: AudioStreamPlayer
var _bpm: HSlider
var _offset: HSlider
var _readout: Label
var _next_beat := 0
var _bar := 0


func _ready() -> void:
	var song: SongResource = load(SONG_PATH)

	_music = AudioStreamPlayer.new()
	_music.stream = song.stream
	add_child(_music)

	_click = AudioStreamPlayer.new()
	_click.stream = Sfx.click()
	add_child(_click)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.offset_left = -300
	box.offset_right = 300
	box.offset_top = -110
	box.offset_bottom = 110
	box.add_theme_constant_override("separation", 10)
	add_child(box)

	_readout = _label(box, 26)
	_label(box, 14).text = "BPM  (fix this first -- drift means it is wrong)"
	_bpm = _slider(box, 60.0, 200.0, 0.1, song.bpm)
	_label(box, 14).text = "Offset, seconds  (constant lead or lag means it is wrong)"
	_offset = _slider(box, -1.0, 2.0, 0.001, song.first_beat_offset)

	var hint := _label(box, 13)
	hint.text = "Arrow keys nudge a focused slider.  ESC quits."
	hint.modulate.a = 0.6

	_bpm.value_changed.connect(_resync)
	_offset.value_changed.connect(_resync)
	_music.play()


func _label(parent: Control, size_px: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size_px)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(l)
	return l


func _slider(parent: Control, lo: float, hi: float, step: float, val: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = val
	s.custom_minimum_size = Vector2(0, 26)
	parent.add_child(s)
	return s


func _resync(_v: float) -> void:
	_next_beat = ceili(_beat_pos())


func _beat_pos() -> float:
	var t := _music.get_playback_position() + AudioServer.get_time_since_last_mix()
	return (t - _offset.value) / (60.0 / _bpm.value)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()


func _process(_delta: float) -> void:
	var b := _beat_pos()
	while b >= float(_next_beat):
		# Accent the downbeat so you can hear the bar, not just the pulse.
		_click.pitch_scale = 1.6 if _next_beat % 4 == 0 else 1.0
		_click.play()
		_bar = _next_beat / 4
		_next_beat += 1

	_readout.text = "bpm = %.2f      first_beat_offset = %.4f\nbeat %d   bar %d" % [
		_bpm.value, _offset.value, maxi(_next_beat - 1, 0), _bar]
