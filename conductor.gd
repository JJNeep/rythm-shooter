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
## The track reached its end. For a run this is a deadline, not a loop point.
signal song_ended

## Registered in project.godot under [shader_globals]. Any material can read
## `global uniform float beat_pulse;` and pulse with the music for free.
const PULSE_PARAM := "beat_pulse"

var song: SongResource
var running: bool = false
## Practice range only. A timed run never loops -- see _on_finished.
var loop: bool = false

## Player latency calibration, in seconds. Positive means their setup runs
## late, so we treat the music as having arrived earlier than reported.
## Bluetooth headphones can need 150-300ms here, which no amount of
## get_output_latency() will catch for you.
var user_offset: float = 0.0

## A bus of the game's own with a reverb on it, so a run can end on a tail
## instead of a cut. Built here rather than shipped as a bus layout file: the
## project has never had one, and a single bus is not worth the file.
const BUS := "Music"
const FADE_SECONDS := 3.4

var _player: AudioStreamPlayer
var _last_clock: float = 0.0
var _next_beat: int = 0
var _bus: int = 0
var _reverb: AudioEffectReverb
var _fading: bool = false
var _fade_tween: Tween

var sec_per_beat: float:
	get:
		return (60.0 / song.bpm) if song else 0.5


func _ready() -> void:
	_make_bus()
	_player = AudioStreamPlayer.new()
	_player.name = "Music"
	_player.bus = BUS
	add_child(_player)
	_player.finished.connect(_on_finished)


func _make_bus() -> void:
	_bus = AudioServer.get_bus_index(BUS)
	if _bus == -1:
		_bus = AudioServer.bus_count
		AudioServer.add_bus(_bus)
		AudioServer.set_bus_name(_bus, BUS)
		AudioServer.set_bus_send(_bus, "Master")
	_reverb = AudioEffectReverb.new()
	_reverb.room_size = 0.9
	_reverb.damping = 0.18
	_reverb.spread = 1.0
	_reverb.predelay_msec = 90.0
	# Dry at rest: the track must sound exactly as it did until a run ends.
	_reverb.wet = 0.0
	_reverb.dry = 1.0
	AudioServer.add_bus_effect(_bus, _reverb)


## A run is one song, so by default the end of the track ends the clock and
## says so. The alternative -- restarting from the top -- would teleport the
## pursuit wall back to the start of the level mid-run, which is worse than any
## bug it was guarding against.
##
## Looping is still available for the practice range, where there is no wall
## and no deadline. It is NOT seamless: 182.4s is 425.6 beats at 140 BPM, so
## the track holds no whole number of beats and no loop point lines up. You get
## a musical bump, but the beat grid stays exact.
func _on_finished() -> void:
	if not running:
		return
	if loop and song:
		start(song, true)
		return
	running = false
	song_ended.emit()


func start(s: SongResource, loop_it: bool = false) -> void:
	loop = loop_it
	song = s
	_player.stream = s.stream
	_last_clock = 0.0
	_next_beat = 0
	# A restart can land in the middle of the previous run's wash. Without
	# this, that tween would finish a second later and stop the new song.
	_kill_fade()
	running = true
	_player.play()
	song_started.emit()


func stop() -> void:
	running = false
	_kill_fade()
	_player.stop()


func _kill_fade() -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null
	_fading = false
	_dry()


## Wash the track out rather than cutting it: the reverb comes up as the level
## comes down, so the last thing you hear is the tail of the music over the
## tally. Most levels use a slice of their song and stop long before the track
## would, which without this ends a run on an audible chop.
##
## The clock keeps running through the fade on purpose -- the tally staggers
## itself on half beats, and it should assemble in time with what is still
## sounding.
func fade_out(seconds: float = FADE_SECONDS) -> void:
	if _fading or not _player.playing:
		return
	_fading = true
	_fade_tween = create_tween().set_parallel(true)
	_fade_tween.tween_method(_set_wet, 0.0, 0.9, seconds * 0.4)
	_fade_tween.tween_method(_set_level, 0.0, -42.0, seconds) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_fade_tween.chain().tween_callback(_end_fade)


func _set_wet(v: float) -> void:
	if _reverb:
		_reverb.wet = v
		_reverb.dry = 1.0 - v * 0.75


func _set_level(db: float) -> void:
	AudioServer.set_bus_volume_db(_bus, db)


func _end_fade() -> void:
	running = false
	_player.stop()
	_dry()
	_fading = false


func _dry() -> void:
	AudioServer.set_bus_volume_db(_bus, 0.0)
	_set_wet(0.0)


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
