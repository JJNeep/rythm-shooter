## Autoload: Conductor
##
## The single source of musical time. Nothing else in the game is allowed to
## measure time for gameplay purposes -- everything reads from here.
##
## The clock is derived from the audio stream itself rather than from frame
## deltas or Timer nodes. That is the whole trick: accumulated delta drifts,
## and a drifting rhythm game is a broken rhythm game. It also means slow-mo
## and hit-stop cannot desync the beat grid, because Engine.time_scale has no
## effect on the audio hardware's playhead.
extends Node

signal beat(index: int)
signal bar(index: int)
signal song_started

## Registered in project.godot under [shader_globals]. Any material can read
## `global uniform float beat_pulse;` and pulse with the music for free.
const PULSE_PARAM := "beat_pulse"

var song: SongResource
var running: bool = false

## Player latency calibration, in seconds. Positive means their setup runs
## late, so we treat the music as having arrived earlier than reported.
## Bluetooth headphones can need 150-300ms here, which no amount of
## get_output_latency() will catch for you.
var user_offset: float = 0.0

var _player: AudioStreamPlayer
var _last_clock: float = 0.0
var _next_beat: int = 0

var sec_per_beat: float:
	get:
		return (60.0 / song.bpm) if song else 0.5


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.name = "Music"
	add_child(_player)
	_player.finished.connect(_on_finished)


## When the stream ends, the playhead stops and clock() freezes -- which would
## leave the gun silently unable to fire, since the slot index never changes
## again. Restart from the top instead.
##
## Note this is NOT a seamless loop. The track is 182.4s, which is 425.6 beats
## at 140 BPM, so it does not contain a whole number of beats and no loop point
## will line up. You get a musical bump here but the beat grid stays exact. For
## a real loop, cut the audio to a whole number of bars and re-measure.
func _on_finished() -> void:
	if running and song:
		start(song)


func start(s: SongResource) -> void:
	song = s
	_player.stream = s.stream
	_last_clock = 0.0
	_next_beat = 0
	running = true
	_player.play()
	song_started.emit()


func stop() -> void:
	running = false
	_player.stop()


## Monotonic, latency-compensated song position in seconds.
func clock() -> float:
	if not running or not _player.playing:
		return _last_clock

	var t: float = _player.get_playback_position() \
		+ AudioServer.get_time_since_last_mix() \
		- AudioServer.get_output_latency() \
		- user_offset

	# get_playback_position() only advances once per audio mix block, so on its
	# own it is a staircase ~11ms wide; get_time_since_last_mix() fills the gaps.
	# The sum can step backwards by a hair at a block boundary, which would make
	# beat_pos() stutter, so hold instead -- but let a real seek or loop through.
	if t < _last_clock and _last_clock - t < 0.1:
		t = _last_clock
	_last_clock = t
	return t


## Continuous beat position, e.g. 12.37
func beat_pos() -> float:
	if not song:
		return 0.0
	return (clock() - song.first_beat_offset) / sec_per_beat


## 0..1 ramp through the current beat. 0.0 is exactly on it.
func beat_phase() -> float:
	return fposmod(beat_pos(), 1.0)


## The nearest valid firing slot to a beat position.
## interval_beats: 1.0 = quarter notes, 0.5 = eighths, 0.25 = sixteenths.
func nearest_slot(interval_beats: float, at: float) -> float:
	return roundf(at / interval_beats)


## Signed seconds from `at` to its nearest slot. Negative means early.
func slot_error(interval_beats: float, at: float) -> float:
	var slot := nearest_slot(interval_beats, at)
	return (at - slot * interval_beats) * sec_per_beat


## Song time, in seconds, at which a given slot lands.
func slot_time(interval_beats: float, slot: float) -> float:
	if not song:
		return 0.0
	return song.first_beat_offset + slot * interval_beats * sec_per_beat


func _process(_delta: float) -> void:
	if not running:
		return

	var b := beat_pos()
	# A `while`, not an `if`: one long frame must fire every beat it passed over
	# rather than silently swallowing them.
	while b >= float(_next_beat):
		beat.emit(_next_beat)
		if song and _next_beat % song.beats_per_bar == 0:
			bar.emit(_next_beat / song.beats_per_bar)
		_next_beat += 1

	# One line that makes the entire level breathe: 1.0 on the beat, decaying
	# to 0 before the next one.
	RenderingServer.global_shader_parameter_set(PULSE_PARAM, pow(1.0 - beat_phase(), 3.0))
