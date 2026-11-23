class_name GunResource
extends Resource

enum FireMode { SINGLE, AUTOMATIC }
enum Kind { HITSCAN, ROCKET }

@export_group("General")
@export var gun_name: String = "Default Gun"
@export var fire_mode: FireMode = FireMode.SINGLE
@export var weapon_kind: Kind = Kind.HITSCAN
@export var gun_scene: PackedScene

@export_group("Rocket")
## Only used when weapon_kind is ROCKET.
@export var projectile_speed: float = 46.0
@export var blast_radius: float = 5.5

## How hard the blast throws the shooter. This is the whole reason the rocket
## is traversal equipment: aim at your feet and it launches you.
@export var self_knockback: float = 27.0

@export_group("Charges")
## 0 means unlimited. Above 0, firing spends a charge and charges come back
## one per `reload_beats` -- so the launcher is a budget measured in bars, and
## every rocket is a decision between crossing a gap and clearing a crowd.
@export var charges: int = 0
@export var reload_beats: float = 4.0

@export_group("Rhythm")
## The subdivision you are allowed to play on. One shot per slot, so this
## doubles as the fire-rate limit.
##   1.0  = quarter notes only, downbeats
##   0.5  = eighths, so the offbeat between each pair of beats counts too
##   0.25 = sixteenths
@export var grid_beats: float = 0.5

## Grading windows in MILLISECONDS -- absolute, not a fraction of the slot.
##
## Fractions were a mistake here. Halving the subdivision to allow offbeats
## also halved every window, so adding valid slots would have made the timing
## HARDER rather than more forgiving. Real rhythm games use fixed millisecond
## windows for exactly this reason.
##
## Each is clamped to WINDOW_CAP of the slot spacing at runtime so neighbouring
## slots can never overlap, which is what compresses them on tight
## subdivisions -- a sixteenth-note gun still gets brutal windows, but because
## the slots are genuinely close together rather than as an accident.
@export var perfect_ms: float = 32.0
@export var great_ms: float = 62.0
@export var good_ms: float = 95.0

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
