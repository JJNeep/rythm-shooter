## Rocket projectile.
##
## Steps itself forward and raycasts the step each frame rather than being a
## RigidBody, so it cannot tunnel through thin level geometry at 45 m/s.
##
## The blast falloff is deliberately shallow: a rocket is the horde-clearing
## tool, so catching something at the edge of the radius should still kill it.
## That is also what makes the weapon forgiving in SPACE while staying strict
## in TIME -- its slow quarter-note cadence is the real cost.
class_name Rocket
extends Node3D

const BLAST_COLOUR := Color(1.0, 0.62, 0.26)
const EDGE_DAMAGE := 0.45       # fraction of full damage at the blast edge

var speed: float = 46.0
var blast_radius: float = 5.5
## How close an enemy has to get before the fuse trips.
var proximity: float = 1.5
## How hard the blast throws the player who fired it.
var self_knockback: float = 27.0
var damage: float = 140.0
var grade: int = 0

var _dir := Vector3.FORWARD
var _life := 6.0
var _exploded := false
var _exclude: Array[RID] = []
var _light: OmniLight3D
var _err_sec: float = 0.0
var _on_beat: bool = true


func launch(from: Vector3, dir: Vector3, spd: float, radius: float,
		dmg: float, shot_grade: int, err_sec: float, on_beat: bool,
		exclude: Array[RID]) -> void:
	global_position = from
	_dir = dir.normalized()
	speed = spd
	blast_radius = radius
	damage = dmg
	grade = shot_grade
	_err_sec = err_sec
	_on_beat = on_beat
	_exclude = exclude
	# Oriented here rather than in _ready, because _ready runs on add_child
	# before the direction has been handed over.
	if _dir.length_squared() > 0.0001 and absf(_dir.dot(Vector3.UP)) < 0.99:
		look_at(global_position + _dir, Vector3.UP)


func _ready() -> void:
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.11
	mesh.height = 0.52
	mesh.radial_segments = 8

	var mat := StandardMaterial3D.new()
	mat.albedo_color = BLAST_COLOUR
	mat.emission_enabled = true
	mat.emission = BLAST_COLOUR
	mat.emission_energy_multiplier = 5.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# CapsuleMesh runs along +Y; bring it round onto the direction of travel.
	mi.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	add_child(mi)

	_light = OmniLight3D.new()
	_light.light_color = BLAST_COLOUR
	_light.light_energy = 3.0
	_light.omni_range = 7.0
	_light.shadow_enabled = false
	add_child(_light)


func _physics_process(delta: float) -> void:
	if _exploded:
		return

	_life -= delta
	if _life <= 0.0:
		_explode(global_position)
		return

	# Proximity fuse, checked BEFORE the ray.
	#
	# The step raycast is infinitely thin, and runners surge sideways at up to
	# 20 m/s, so a rocket fired into a crowd would regularly slip between two of
	# them and sail on to detonate against a wall 200m away. Verified: firing
	# point-blank into 21 runners scored zero. For an area weapon that is the
	# worst possible failure, so detonate on getting close instead of trusting
	# the ray to catch anything.
	for e in get_tree().get_nodes_in_group("enemy"):
		if not (e is Node3D):
			continue
		var n := e as Node3D
		if n.has_method("is_alive") and not n.call("is_alive"):
			continue
		if n.global_position.distance_to(global_position) <= proximity:
			_explode(global_position)
			return

	var step := speed * delta
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(
		global_position, global_position + _dir * step)
	q.collide_with_areas = false
	q.exclude = _exclude
	var hit := space.intersect_ray(q)
	if hit:
		_explode(hit.position)
	else:
		global_position += _dir * step


func _explode(at: Vector3) -> void:
	if _exploded:
		return
	_exploded = true

	var world := get_tree().current_scene
	var caught := 0
	for e in get_tree().get_nodes_in_group("enemy"):
		if not (e is Node3D):
			continue
		var n := e as Node3D
		if n.has_method("is_alive") and not n.call("is_alive"):
			continue
		var d: float = n.global_position.distance_to(at)
		if d > blast_radius:
			continue
		var falloff: float = lerpf(1.0, EDGE_DAMAGE, clampf(d / blast_radius, 0.0, 1.0))
		var away := n.global_position - at
		away = away.normalized() if away.length() > 0.01 else Vector3.UP
		if n.has_method("take_damage"):
			n.call("take_damage", damage * falloff, away, grade)
			caught += 1

	# Blast jump. No self-damage on purpose: the charge is already the cost,
	# and adding damage on top would muddy the jump-or-kill decision that the
	# whole weapon exists to pose.
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player != null and player.has_method("apply_blast"):
		var d := player.global_position - at
		var dist := d.length()
		if dist <= blast_radius:
			var away := d.normalized() if dist > 0.05 else Vector3.UP
			var near := 1.0 - clampf(dist / blast_radius, 0.0, 1.0)
			player.call("apply_blast", away, self_knockback * lerpf(0.4, 1.0, near))

	_flash(world, at)
	Gibs.burst(world, at, Vector3.UP, 6.0, BLAST_COLOUR, 6, 0.7)

	# Credited on impact, not on launch, so the grade popup lands with the
	# explosion and a rocket fired into open space scores nothing.
	Score.register(grade, _err_sec, caught > 0, _on_beat)
	queue_free()


func _flash(world: Node, at: Vector3) -> void:
	if world == null:
		return

	var light := OmniLight3D.new()
	light.light_color = BLAST_COLOUR
	light.light_energy = 20.0
	light.omni_range = blast_radius * 3.2
	light.shadow_enabled = false
	world.add_child(light)
	light.global_position = at
	var lt := light.create_tween()
	lt.tween_property(light, "light_energy", 0.0, 0.32)
	lt.tween_callback(light.queue_free)

	var sphere := SphereMesh.new()
	sphere.radius = blast_radius
	sphere.height = blast_radius * 2.0
	sphere.radial_segments = 16
	sphere.rings = 8

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(BLAST_COLOUR.r, BLAST_COLOUR.g, BLAST_COLOUR.b, 0.5)
	mat.emission_enabled = true
	mat.emission = BLAST_COLOUR
	mat.emission_energy_multiplier = 3.0

	var mi := MeshInstance3D.new()
	mi.mesh = sphere
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mi)
	mi.global_position = at
	mi.scale = Vector3.ONE * 0.25

	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE, 0.18)
	tw.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.26)
	tw.tween_callback(mi.queue_free)
