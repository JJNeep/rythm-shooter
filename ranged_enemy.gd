## A gunner on a platform. Fires on its own beat of the bar.
##
## Timing: it flashes a telegraph on beat N-1, launches on beat N, and the shot
## detonates on beat N+1. Two beats of warning, all of it on the grid, so the
## level's threats can be read by ear. Give several of them different `offset`
## values and they alternate, which keeps one volley in the air at all times
## without ever stacking two.
##
## Tougher than a horde runner on purpose: it takes two clean deagle hits, so
## it is a decision about how many of your beats a given gunner is worth.
extends StaticBody3D

const COLOUR := Color(1.0, 0.45, 0.28)
const SIGHT := 70.0

@export var period: int = 4        # beats between volleys
@export var offset: int = 0        # which beat of the cycle it fires on
@export var max_health: float = 160.0

var health: float
var _alive := true
var _telegraph := 0.0
var _hurt := 0.0
var _mesh: MeshInstance3D
var _mat: StandardMaterial3D
var _base_scale := Vector3.ONE
var _player: Node3D
var _near := false
var _range_tick := 0.0


func _ready() -> void:
	add_to_group("enemy")
	add_to_group("gunner")
	health = max_health
	_base_scale = scale

	_mesh = find_child("MeshInstance3D", false, false) as MeshInstance3D
	if _mesh:
		_mat = StandardMaterial3D.new()
		_mat.albedo_color = COLOUR
		_mat.emission_enabled = true
		_mat.emission = COLOUR
		_mat.emission_energy_multiplier = 0.5
		_mesh.material_override = _mat

	Conductor.beat.connect(_on_beat)


func is_alive() -> bool:
	return _alive


func _on_beat(index: int) -> void:
	if not _alive:
		return
	if posmod(index - offset, period) == 0:
		_fire(index)
	elif posmod(index + 1 - offset, period) == 0:
		_telegraph = 1.0


func _fire(index: int) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return

	var muzzle := global_position + Vector3(0.0, 0.7, 0.0)
	var target := player.global_position
	if muzzle.distance_to(target) > SIGHT:
		return

	# Do not lob shots through the level at someone who cannot see you coming.
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(muzzle, target)
	q.collide_with_areas = false
	q.exclude = [get_rid()]
	var blocked := space.intersect_ray(q)
	if blocked:
		var c: Object = blocked.collider
		if c != player:
			return

	var shot := EnemyShot.new()
	var world := get_tree().current_scene
	if world == null:
		return
	world.add_child(shot)
	# Lands on the NEXT beat, so flight time is exactly one beat.
	shot.launch(muzzle, target, Conductor.slot_time(1.0, float(index + 1)))
	_telegraph = 0.45


func take_damage(amount: float, dir: Vector3, grade: int) -> void:
	if not _alive:
		return
	health -= amount
	_hurt = 1.0
	if health <= 0.0:
		_die(dir, grade)


func _die(dir: Vector3, grade: int) -> void:
	_alive = false
	var quality := 1.0 - clampf(float(grade) / 3.0, 0.0, 1.0)
	Gibs.burst(get_tree().current_scene, global_position + Vector3(0, 0.5, 0), dir,
		lerpf(6.0, 26.0, quality), COLOUR, 9, 1.1)
	queue_free()


func _process(delta: float) -> void:
	if not _alive:
		return

	# A full-length level holds about seventy of these. Only the ones close
	# enough to be seen need their pulse and telegraph updated every frame;
	# _fire does its own SIGHT check, so the distant ones stay harmless too.
	_range_tick += delta
	if _range_tick > 0.25:
		_range_tick = 0.0
		if _player == null or not is_instance_valid(_player):
			_player = get_tree().get_first_node_in_group("player") as Node3D
		_near = _player != null and (
			global_position.distance_squared_to(_player.global_position) < SIGHT * SIGHT)
	if not _near:
		return

	_telegraph = maxf(_telegraph - delta * 2.4, 0.0)
	_hurt = maxf(_hurt - delta * 5.0, 0.0)

	var pulse := pow(1.0 - Conductor.beat_phase(), 4.0) if Conductor.running else 0.0

	# The telegraph has to out-shout the ordinary beat pulse, or you cannot
	# tell "about to fire" from "existing".
	scale = _base_scale * (1.0 + pulse * 0.06 + _telegraph * 0.3)
	if _mat:
		_mat.emission_energy_multiplier = 0.5 + pulse * 1.0 + _telegraph * 7.0 + _hurt * 5.0
		_mat.albedo_color = COLOUR.lerp(Color.WHITE, maxf(_telegraph * 0.6, _hurt))
