## An incoming shot that detonates exactly on a beat.
##
## It does not have a speed. It has a launch time and a DETONATION time, and
## interpolates between two points so it arrives on the beat no matter how far
## it had to travel. That is what makes enemy fire part of the rhythm instead
## of noise on top of it: every explosion in the level lands on the grid, and
## you can hear when to be somewhere else.
##
## Lobbed on an arc, so a volley is readable at a glance and you can judge
## where it will land rather than only when.
class_name EnemyShot
extends Node3D

const COLOUR := Color(1.0, 0.35, 0.45)

var blast_radius: float = 3.4
var arc_height: float = 3.0

var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _t0 := 0.0
var _t1 := 1.0
var _done := false
var _mat: StandardMaterial3D


func launch(from: Vector3, to: Vector3, detonate_at: float) -> void:
	_from = from
	_to = to
	_t0 = Conductor.clock()
	_t1 = maxf(detonate_at, _t0 + 0.05)
	global_position = from
	# A longer flight gets a taller arc, so distant volleys read as distant.
	arc_height = clampf(from.distance_to(to) * 0.12, 1.0, 5.0)


func _ready() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 0.26
	mesh.height = 0.52
	mesh.radial_segments = 10
	mesh.rings = 6

	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = COLOUR
	_mat.emission_enabled = true
	_mat.emission = COLOUR
	_mat.emission_energy_multiplier = 5.0

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

	var light := OmniLight3D.new()
	light.light_color = COLOUR
	light.light_energy = 2.2
	light.omni_range = 5.0
	light.shadow_enabled = false
	add_child(light)


func _process(_delta: float) -> void:
	if _done:
		return

	var now := Conductor.clock()
	var t := clampf((now - _t0) / maxf(_t1 - _t0, 0.001), 0.0, 1.0)

	var p := _from.lerp(_to, t)
	p.y += sin(t * PI) * arc_height
	global_position = p

	# Swells as it closes, so the last fraction of a beat is unmistakable.
	if _mat:
		_mat.emission_energy_multiplier = 4.0 + t * t * 9.0

	if t >= 1.0:
		_detonate()


func _detonate() -> void:
	if _done:
		return
	_done = true

	var at := global_position
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player and player.global_position.distance_to(at) <= blast_radius:
		Score.drain(Score.ENERGY_SHOT)
		if player.has_method("on_hit"):
			player.call("on_hit")

	_flash(at)
	queue_free()


func _flash(at: Vector3) -> void:
	var world := get_tree().current_scene
	if world == null:
		return

	var light := OmniLight3D.new()
	light.light_color = COLOUR
	light.light_energy = 11.0
	light.omni_range = blast_radius * 3.0
	light.shadow_enabled = false
	world.add_child(light)
	light.global_position = at
	var lt := light.create_tween()
	lt.tween_property(light, "light_energy", 0.0, 0.25)
	lt.tween_callback(light.queue_free)

	var sphere := SphereMesh.new()
	sphere.radius = blast_radius
	sphere.height = blast_radius * 2.0
	sphere.radial_segments = 14
	sphere.rings = 7

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(COLOUR.r, COLOUR.g, COLOUR.b, 0.45)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var mi := MeshInstance3D.new()
	mi.mesh = sphere
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mi)
	mi.global_position = at
	mi.scale = Vector3.ONE * 0.3

	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE, 0.16)
	tw.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.24)
	tw.tween_callback(mi.queue_free)
