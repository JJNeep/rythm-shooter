## A song plus the two numbers that define its beat grid.
## Measure these once per track with the tuner scene, then never think about
## them again. They are specific to this exact encode of the file -- re-encoding
## (mp3 -> ogg, say) changes the padding, so re-measure if you convert.
class_name SongResource
extends Resource

@export var title: String = ""
@export var stream: AudioStream

## Beats per minute. Measure it, never guess it.
@export var bpm: float = 140.0

## Seconds into the file where beat 0 lands. Never 0.0 in practice -- every
## track has a lead-in, and the decoder adds a little padding of its own.
@export var first_beat_offset: float = 0.0

@export var beats_per_bar: int = 4
