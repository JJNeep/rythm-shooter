## Latency calibration: measures how late this machine's audio actually
## reaches the player, and saves it so every grade afterwards is honest.
##
## Why this has to exist: AudioServer.get_output_latency() knows about the
## engine's own buffers and nothing else. It cannot see the display pipeline, a
## soundbar, or Bluetooth headphones, which can be 150-300ms out. Without this
## screen a player on wireless headphones concludes the game is broken, and
## they are not wrong.
##
## Method: play a sample-exact click track, have them tap along, take the
## MEDIAN of the errors rather than the mean. One fumbled tap drags a mean
## badly; the median shrugs it off. The first few taps are discarded because
## nobody is in time before they have heard a couple of beats.
extends Control

const BPM := 140.0
const WARMUP := 4           # taps thrown away while the player settles
const NEEDED := 18          # taps collected before the result is trusted

var _player: AudioStreamPlayer
var _taps: Array[float] = []
var _spb := 60.0 / BPM
var _flash := 0.0

var _count_label: Label
var _result_label: Label
var _hint_label: Label


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	_player = AudioStreamPlayer.new()
	_player.stream = Sfx.click_track(BPM, 8, 4)
	add_child(_player)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.offset_left = -340
	box.offset_right = 340
	box.offset_top = -40
	box.offset_bottom = 190
	box.add_theme_constant_override("separation", 12)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	_label(box, 30).text = "Latency calibration"
	_label(box, 16).text = "Click on every beat. The first few do not count."
	_count_label = _label(box, 22)
	_result_label = _label(box, 20)
	_hint_label = _label(box, 14)
	_hint_label.modulate.a = 0.65

	_refresh()
	_player.play()


func _label(parent: Control, size_px: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


## Raw, uncompensated audio time. Deliberately does NOT subtract
## Settings.audio_offset_ms, because that is the very thing being measured.
func _raw_time() -> float:
	if not _player.playing:
		return 0.0
	return _player.get_playback_position() \
		+ AudioServer.get_time_since_last_mix() \
		- AudioServer.get_output_latency()


## 0..1 through the current beat. Safe across the loop point because the track
## is a whole number of beats long.
func _phase() -> float:
	return fposmod(_raw_time(), _spb) / _spb


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_tap()
		return

	if not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
	match (event as InputEventKey).physical_keycode:
		KEY_SPACE:
			_tap()
		KEY_ENTER, KEY_KP_ENTER:
			_accept()
		KEY_R:
			_taps.clear()
			_refresh()
		KEY_LEFT:
			Settings.set_offset_ms(Settings.audio_offset_ms - 1.0)
			_refresh()
		KEY_RIGHT:
			Settings.set_offset_ms(Settings.audio_offset_ms + 1.0)
			_refresh()
		KEY_ESCAPE:
			_leave()


func _tap() -> void:
	var err := fposmod(_raw_time(), _spb)
	# Fold into -half..+half so a tap just before a beat reads as early.
	if err > _spb * 0.5:
		err -= _spb
	_taps.append(err)
	_flash = 1.0
	_refresh()


## Median plus mean-absolute-deviation. MAD is the honest spread figure here:
## it tells the player whether their taps were consistent enough to trust.
func _stats() -> Array:
	var v := _taps.slice(WARMUP)
	if v.is_empty():
		return [0.0, 0.0, 0]
	v.sort()
	var n := v.size()
	var median: float = v[n / 2] if n % 2 == 1 else (v[n / 2 - 1] + v[n / 2]) * 0.5
	var dev := 0.0
	for x in v:
		dev += absf(float(x) - median)
	return [median, dev / float(n), n]


func _refresh() -> void:
	var st := _stats()
	var usable: int = st[2]
	var median: float = st[0]
	var dev: float = st[1]

	_count_label.text = "taps: %d / %d" % [_taps.size(), NEEDED]

	if usable <= 0:
		_result_label.text = "saved offset: %+.0f ms%s" % [
			Settings.audio_offset_ms, "" if Settings.calibrated else "   (never measured)"]
	else:
		var verdict := "good"
		if dev * 1000.0 > 45.0:
			verdict = "very scattered, try again"
		elif dev * 1000.0 > 25.0:
			verdict = "a bit scattered"
		_result_label.text = "measured %+.0f ms   spread %.0f ms   (%s)" % [
			median * 1000.0, dev * 1000.0, verdict]

	if _taps.size() < NEEDED:
		_hint_label.text = "keep tapping  ·  R restart  ·  ESC back to the level"
	else:
		_hint_label.text = "ENTER to save %+.0f ms  ·  LEFT/RIGHT nudge 1 ms  ·  R restart  ·  ESC back" % [
			median * 1000.0]


func _accept() -> void:
	var st := _stats()
	if int(st[2]) <= 0:
		return
	Settings.set_offset_ms(float(st[0]) * 1000.0)
	_hint_label.text = "saved %+.0f ms  ·  ESC back to the level" % Settings.audio_offset_ms
	_result_label.text = "saved. positive means your audio runs late."


func _leave() -> void:
	if ResourceLoader.exists("res://level.tscn"):
		get_tree().change_scene_to_file("res://level.tscn")
	else:
		get_tree().quit()


func _process(delta: float) -> void:
	_flash = maxf(_flash - delta * 5.0, 0.0)
	queue_redraw()


func _draw() -> void:
	var c := Vector2(size.x * 0.5, size.y * 0.5 - 150.0)
	var ph := _phase()
	var pulse := pow(1.0 - ph, 6.0)

	# Approach ring contracting onto the target ring, same language as the HUD.
	draw_arc(c, lerpf(96.0, 34.0, ph), 0.0, TAU, 56,
		Color(1, 1, 1, 0.14 + 0.4 * ph), 2.0, true)
	draw_arc(c, 34.0, 0.0, TAU, 56,
		Color(1.0, 0.93, 0.35, 0.3 + 0.7 * pulse), 2.0 + 3.0 * pulse, true)
	if _flash > 0.0:
		draw_circle(c, 22.0 * _flash, Color(0.4, 0.85, 1.0, 0.5 * _flash))
