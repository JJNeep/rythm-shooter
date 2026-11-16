extends Node3D

@export var current_gun: GunResource

var current_ammo: int = 0
var can_fire: bool = true

func _ready() -> void:
	current_ammo = current_gun.max_magazine
	if current_gun.gun_scene:
		var model = current_gun.gun_scene.instantiate()
		add_child(model)

func shoot() -> void:
	if not can_fire or current_ammo <= 0:
		return
		
	current_ammo -= 1
	can_fire = false
	
	# Add raycast or projectile logic here using current_gun.damage and current_gun.bullets_per_shot
	
	await get_tree().create_timer(current_gun.fire_rate).timeout
	can_fire = true
