## Synthesised placeholder audio, so the prototype makes noise without you
## having to go and source samples first. Replace with real one-shots when you
## have them -- a gunshot sample does a lot of work here.
class_name Sfx
extends RefCounted


static func _wav(data: PackedByteArray, sr: int) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = sr
	w.stereo = false
	w.data = data
	return w


## Short pitched blip. Used as the tuner metronome.
static func click(freq: float = 1500.0, dur: float = 0.045, vol: float = 0.7) -> AudioStreamWAV:
	var sr := 44100
	var n := int(sr * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / float(sr)
		var env: float = exp(-t * 110.0)
		var s: float = sin(TAU * freq * t) * env * vol
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	return _wav(data, sr)


## Noise burst over a falling thump. Reads as a heavy pistol.
static func shot() -> AudioStreamWAV:
	var sr := 44100
	var dur := 0.20
	var n := int(sr * dur)
	var data := PackedByteArray()
	data.resize(n * 2)

	var rng := RandomNumberGenerator.new()
	rng.seed = 20260122          # fixed, so the shot sounds the same every time

	var phase := 0.0
	for i in n:
		var t := float(i) / float(sr)
		var crack: float = rng.randf_range(-1.0, 1.0) * exp(-t * 30.0)
		# Sweep the body down from 170Hz to 48Hz by integrating the phase, so
		# there is no discontinuity partway through.
		var f: float = lerpf(170.0, 48.0, minf(t * 7.0, 1.0))
		phase += TAU * f / float(sr)
		var body: float = sin(phase) * exp(-t * 15.0)
		var s: float = (crack * 0.5 + body * 0.7) * 0.85
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	return _wav(data, sr)


## A looping metronome track at an exact BPM, for the calibration screen.
##
## At 44100 Hz and 140 BPM a beat is exactly 18900 samples (44100 * 3/7), so a
## whole number of beats loops sample-perfectly and the click phase stays
## continuous across the loop point. That is what lets calibration measure tap
## error as a plain modulo of the playback position, with no beat bookkeeping.
static func click_track(bpm: float = 140.0, beats: int = 8, beats_per_bar: int = 4) -> AudioStreamWAV:
	var sr := 44100
	var per_beat := int(round((60.0 / bpm) * float(sr)))
	var n := per_beat * beats
	var data := PackedByteArray()
	data.resize(n * 2)

	var click_len := mini(int(0.04 * float(sr)), per_beat)
	for b in beats:
		var accent: bool = (b % beats_per_bar) == 0
		var freq: float = 2200.0 if accent else 1400.0
		var vol: float = 0.9 if accent else 0.5
		for i in click_len:
			var t := float(i) / float(sr)
			var s: float = sin(TAU * freq * t) * exp(-t * 120.0) * vol
			data.encode_s16((b * per_beat + i) * 2, int(clampf(s, -1.0, 1.0) * 32767.0))

	var w := _wav(data, sr)
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	return w
