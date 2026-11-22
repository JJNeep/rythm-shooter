class_name GunResource
extends Resource

enum FireMode { SINGLE, AUTOMATIC }

@export_group("General")
@export var gun_name: String = "Default Gun"
@export var fire_mode: FireMode = FireMode.SINGLE
@export var gun_scene: PackedScene

@export_group("Rhythm")
## The beat grid IS the fire-rate limiter -- one shot per slot, no timers.
## 1.0 = quarter notes, 0.5 = eighths, 0.25 = sixteenths.
@export var fire_interval_beats: float = 1.0

## Grading windows, as fractions of the slot interval rather than fixed
## milliseconds. Expressing them this way means a sixteenth-note gun gets
## brutally tight windows automatically, which is the right difficulty curve.
## None of these may reach 0.5 or neighbouring slots would overlap.
@export_range(0.01, 0.45) var perfect_window: float = 0.07
@export_range(0.01, 0.45) var great_window: float = 0.14
@export_range(0.01, 0.45) var good_window: float = 0.22

## Longest we will delay an early shot so it lands exactly on the beat.
## Past about 100ms the player starts to feel it as input lag.
@export var max_hold: float = 0.10

@export_group("Aim Assist")
@export var lock_range: float = 60.0
@export var lock_angle_deg: float = 40.0

## How far wide (metres, measured at the target) a shot lands when its timing
## sits right on the edge of the GOOD window.
@export var miss_at_good_edge: float = 1.3

## Shape of the error -> distance curve. Higher is more forgiving near perfect
## and harsher once you are sloppy, which is what you want: tiny timing errors
## should not be punished, but visibly bad ones should spray.
@export var miss_curve: float = 2.5
@export var max_miss: float = 4.0

@export_group("Ballistics")
@export var damage: float = 100.0

## Damage multiplier per grade: PERFECT, GREAT, GOOD, WHIFF.
## Keep these clear of the target's health rather than exactly on it: 0.7 is
## 0.69999998 in float32, so 100 * 0.7 against 70 HP left a sliver behind and
## GREAT silently stopped one-shotting. PERFECT kills a 70 HP target, GREAT
## deliberately needs two, which is what makes PERFECT worth chasing.
@export var grade_damage := PackedFloat32Array([1.0, 0.6, 0.45, 0.2])
@export var range_metres: float = 200.0

@export_group("Ammo")
@export var max_magazine: int = 12
@export var reload_time: float = 1.5
@export var infinite_ammo: bool = true

@export_group("Audio")
@export var fire_sound: AudioStream
@export var reload_sound: AudioStream
@export var empty_sound: AudioStream
