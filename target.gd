## A dummy enemy that pulses with the music and comes apart when shot.
##
## Deliberately gibs rather than ragdolls. A rigged Skeleton3D +
## PhysicalBoneSimulator3D ragdoll is a day of setup and reads as floppy; a
## handful of RigidBody3D chunks is twenty minutes and reads as violent.
## Ultrakill mostly explodes its enemies too.
extends StaticBody3D

const GIB_GROUP := "gib"
const GIB_CAP := 90          # across the whole scene, oldest culled first

@export var max_health: float = 70.0
@export var respawn_after: float = 2.0
@export var gib_count: int = 11
@export var base_colour := Color(0.92, 0.26, 0.36)

## Impulse per unit of grade quality. A perfectly timed shot sends them across
## the room; a sloppy one just crumples them. Instant readable feedback with no
## UI involved at all.
@export var kick_min: float = 4.0
@export var kick_max: float = 26.0

var health: float

var _mesh: MeshInstance3D
var _shape: CollisionShape3D
var _mat: StandardMaterial3D
var _alive := true
var _flash := 0.0
var _base_scale := Vector3.ONE


func _ready() -> void:
	add_to_group("enemy")
	health = max_health
	_mesh = find_child("MeshInstance3D", false, false) as MeshInstance3D
	_shape = find_child("CollisionShape3D", false, false) as CollisionShape3D
	_base_scale = scale

	if _mesh:
		_mat = StandardMaterial3D.new()
		_mat.albedo_color = base_colour
		_mat.emission_enabled = true
		_mat.emission = base_colour
		_mat.emission_energy_multiplier = 0.4
		_mesh.material_override = _mat


func is_alive() -> bool:
	return _alive


func _process(delta: float) -> void:
	if not _alive:
		return

	# Pulse on the beat, so the grid is visible in the world and not only
	# audible. Players who cannot hear the kick can still play.
	var pulse := pow(1.0 - Conductor.beat_phase(), 4.0) if Conductor.running else 0.0
	scale = _base_scale * (1.0 + pulse * 0.10)

	_flash = maxf(_flash - delta * 6.0, 0.0)
	if _mat:
		_mat.emission_energy_multiplier = 0.4 + pulse * 1.6 + _flash * 6.0
		_mat.albedo_color = base_colour.lerp(Color.WHITE, _flash)


func take_damage(amount: float, dir: Vector3, grade: int) -> void:
	if not _alive:
		return
	health -= amount
	_flash = 1.0
	if health <= 0.0:
		_die(dir, grade)


func _die(dir: Vector3, grade: int) -> void:
	_alive = false
	if _mesh:
		_mesh.visible = false
	if _shape:
		_shape.disabled = true

	# grade 0 (PERFECT) gets the full kick, 3 (WHIFF) the least.
	var quality := 1.0 - clampf(float(grade) / 3.0, 0.0, 1.0)
	_spawn_gibs(dir, lerpf(kick_min, kick_max, quality))

	await get_tree().create_timer(respawn_after).timeout
	if not is_inside_tree():
		return
	health = max_health
	_alive = true
	scale = _base_scale
	if _mesh:
		_mesh.visible = true
	if _shape:
		_shape.disabled = false


func _spawn_gibs(dir: Vector3, power: float) -> void:
	var world := get_tree().current_scene
	if not world:
		return

	# Keep the total bounded. Settled bodies are cheap but constraint-free
	# chunks still cost broadphase, and this scene respawns forever.
	var existing := get_tree().get_nodes_in_group(GIB_GROUP)
	var over := existing.size() + gib_count - GIB_CAP
	for i in maxi(over, 0):
		if i < existing.size():
			existing[i].queue_free()

	var flat := Vector3(dir.x, 0.0, dir.z)
	flat = flat.normalized() if flat.length() > 0.01 else Vector3.FORWARD

	for i in gib_count:
		var s := randf_range(0.10, 0.26)
		var size := Vector3(s, s * randf_range(0.7, 1.8), s * randf_range(0.7, 1.3))

		var box := BoxMesh.new()
		box.size = size
		var mat := StandardMaterial3D.new()
		mat.albedo_color = base_colour.darkened(randf_range(0.0, 0.45))
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var mi := MeshInstance3D.new()
		mi.mesh = box
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		var shape := BoxShape3D.new()
		shape.size = size
		var cs := CollisionShape3D.new()
		cs.shape = shape

		var rb := RigidBody3D.new()
		rb.mass = 0.35
		rb.add_to_group(GIB_GROUP)
		rb.add_child(mi)
		rb.add_child(cs)
		world.add_child(rb)

		rb.global_position = global_position + Vector3(
			randf_range(-0.3, 0.3), randf_range(-0.7, 0.8), randf_range(-0.3, 0.3))
		var kick := flat * power \
			+ Vector3(randf_range(-3.0, 3.0), randf_range(2.0, 7.0), randf_range(-3.0, 3.0))
		rb.apply_central_impulse(kick * rb.mass)
		rb.angular_velocity = Vector3(
			randf_range(-14.0, 14.0), randf_range(-14.0, 14.0), randf_range(-14.0, 14.0))

		var tw := rb.create_tween()
		tw.tween_interval(3.0)
		tw.tween_property(mat, "albedo_color:a", 0.0, 1.2)
		tw.tween_callback(rb.queue_free)
