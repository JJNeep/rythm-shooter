extends Node3D

var bullet_scene = preload("res://bullet.tscn")

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
	print(current_ammo)
	
	if get_tree().get_nodes_in_group("bullet").size() > 10:
		get_tree().get_nodes_in_group("bullet")[0].queue_free()
	
	var inst : RigidBody3D = bullet_scene.instantiate()
	print(-global_transform.basis.z)
	get_tree().get_first_node_in_group("world").add_child(inst)
	inst.global_position = get_child(0).get_node("Spawner").global_position
	inst.apply_central_force(-global_transform.basis.z*current_gun.shoot_speed)
	
	await get_tree().create_timer(current_gun.fire_rate).timeout
	can_fire = true

func reload() -> void:
	await get_tree().create_timer(current_gun.reload_time).timeout
	current_ammo = current_gun.max_magazine
