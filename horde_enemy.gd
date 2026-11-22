## A horde runner.
##
## The whole point: it SURGES on the beat and coasts between, with a hop at the
## peak. A hundred of these bouncing in unison turns the threat itself into the
## metronome -- you can see and hear the beat in the thing chasing you, which
## is the readability win that makes shooting backwards while sprinting
## possible at all.
extends CharacterBody3D

const GIB_COLOUR := Color(0.80, 0.33, 0.95)

@export var max_health: float = 1.0
@export var drift_speed: float = 6.5      # between beats
@export var surge_speed: float = 20.0     # on the beat
@export var hop_velocity: float = 4.2
@export var touch_damage: float = 11.0
@export var touch_range: float = 1.5

var health: float
var _alive := true
var _surge := 0.0
var _player: Node3D
var _mesh: MeshInstance3D
var _mat: StandardMaterial3D


func _ready() -> void:
	add_to_group("enemy")
	add_to_group("horde")
	health = max_health

	_mesh = find_child("MeshInstance3D", false, false) as MeshInstance3D
	if _mesh:
		_mat = StandardMaterial3D.new()
		_mat.albedo_color = GIB_COLOUR
		_mat.emission_enabled = true
		_mat.emission = GIB_COLOUR
		_mat.emission_energy_multiplier = 0.6
		_mesh.material_override = _mat

	# Stagger the surge slightly per enemy, or the horde moves as one rigid
	# block and reads as a single object rather than a crowd.
	_surge = randf() * 0.3

	if Conductor.has_signal("beat"):
		Conductor.beat.connect(_on_beat)


func is_alive() -> bool:
	return _alive


func _on_beat(_index: int) -> void:
	if _alive:
		_surge = 1.0


func _physics_process(delta: float) -> void:
	if not _alive:
		return

	_surge = maxf(_surge - delta * 3.6, 0.0)

	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if _player == null:
			return

	var to_p: Vector3 = _player.global_position - global_position
	var flat := Vector3(to_p.x, 0.0, to_p.z)
	var dist := flat.length()
	var dir := (flat / dist) if dist > 0.01 else Vector3.ZERO

	var spd: float = lerpf(drift_speed, surge_speed, pow(_surge, 1.5))
	velocity.x = dir.x * spd
	velocity.z = dir.z * spd

	if is_on_floor():
		velocity.y = 0.0
		if _surge > 0.86:
			velocity.y = hop_velocity
	else:
		velocity += get_gravity() * delta

	move_and_slide()

	# Squash and stretch on the surge, so the beat is visible at a distance
	# even when the hop is hidden behind other runners.
	if _mesh:
		_mesh.scale = Vector3(
			1.0 - _surge * 0.16, 1.0 + _surge * 0.26, 1.0 - _surge * 0.16)
	if _mat:
		_mat.emission_energy_multiplier = 0.6 + _surge * 2.2

	if dist < touch_range:
		_touch()


func _touch() -> void:
	if _player and _player.has_method("take_damage"):
		_player.call("take_damage", touch_damage)
	# Consumed on contact, so a swarm trades itself for chip damage rather
	# than grinding you down while standing on your head.
	_die(Vector3.UP, 3)


func take_damage(amount: float, dir: Vector3, grade: int) -> void:
	if not _alive:
		return
	health -= amount
	if health <= 0.0:
		_die(dir, grade)


func _die(dir: Vector3, grade: int) -> void:
	if not _alive:
		return
	_alive = false
	var quality := 1.0 - clampf(float(grade) / 3.0, 0.0, 1.0)
	Gibs.burst(get_tree().current_scene, global_position, dir,
		lerpf(5.0, 24.0, quality), GIB_COLOUR, 7, 0.9)
	queue_free()
