class_name GunResource
extends Resource

enum FireMode { SINGLE, AUTOMATIC, BURST }

@export_group("General")
@export var gun_name: String = "Default Gun"
@export var fire_mode: FireMode = FireMode.SINGLE
@export var fire_rate: float = 0.2 # Seconds between shots
@export var gun_scene: PackedScene # The 2D or 3D visual model/scene

@export_group("Ballistics")
@export var damage: float = 10.0
@export var bullet_spread: float = 0.0
@export var bullets_per_shot: int = 1
@export var max_range: float = 100.0

@export_group("Ammo")
@export var max_magazine: int = 12
@export var reload_time: float = 1.5

@export_group("Audio")
@export var fire_sound: AudioStream
@export var reload_sound: AudioStream
@export var empty_sound: AudioStream
