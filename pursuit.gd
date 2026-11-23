## The wall of runners chasing you down the level.
##
## Its position is not a timer and not relative to the player -- it is
## LevelRoot.wall_z(song time), which means the wall IS the song's playhead
## drawn into the world. Sync is therefore guaranteed by construction rather
## than tuned, and "fastest possible time" becomes a real thing: you are racing
## the track itself. Dawdle and the music catches you.
class_name Pursuit
extends Node3D

const SPAWN_EVERY_BEATS := 2
const MAX_LIVE := 38
# Big enough to read as a wall in the widest room in the level, and tall
# enough that it still looks like it is coming for you on a 22m catwalk -- it
# tracks the player's height rather than sitting at ground level, because the
# catch test is purely a Z comparison and the visual has to say so.
const WIDTH := 26.0
const HEIGHT := 18.0

signal caught

var wall_z: float = 6.0

var _player: Node3D
var _level: LevelRoot
var _horde_scene: PackedScene
var _mat: StandardMaterial3D
var _mesh: MeshInstance3D
var _light: OmniLight3D
var _armed := true
var _stopped := false


func _ready() -> void:
	_horde_scene = load("res://horde_enemy.tscn")

	# A translucent slab so you can always see exactly where the deadline is,
	# even when the runners in front of it have been cleared.
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.albedo_color = Color(0.85, 0.18, 0.65, 0.33)
	_mat.emission_enabled = true
	_mat.emission = Color(0.95, 0.25, 0.75)
	_mat.emission_energy_multiplier = 2.5
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var box := BoxMesh.new()
	box.size = Vector3(WIDTH, HEIGHT, 0.6)
	_mesh = MeshInstance3D.new()
	_mesh.mesh = box
	_mesh.material_override = _mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	_mesh.position = Vector3(0, HEIGHT * 0.5 - 1.4, 0)

	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.3, 0.8)
	_light.omni_range = 34.0
	_light.light_energy = 4.0
	_light.shadow_enabled = false
	add_child(_light)
	_light.position = Vector3(0, 4, 2)

	Conductor.beat.connect(_on_beat)


func _on_beat(index: int) -> void:
	if not _armed or index % SPAWN_EVERY_BEATS != 0:
		return
	if _player == null:
		return
	# Only bother spawning runners the player could plausibly see.
	if absf(wall_z - _player.global_position.z) > 70.0:
		return

	var live := get_tree().get_nodes_in_group("horde").size()
	if live >= MAX_LIVE:
		return

	for i in mini(4, MAX_LIVE - live):
		var e := _horde_scene.instantiate() as Node3D
		get_parent().add_child(e)
		e.global_position = Vector3(
			randf_range(-6.4, 6.4),
			_player.global_position.y + 0.9,
			wall_z + randf_range(0.5, 6.0))


func bind(player: Node3D, level: LevelRoot) -> void:
	_player = player
	_level = level
	wall_z = level.wall_start_z()
	global_position = Vector3(0.0, 0.0, wall_z)


## Stops the wall where it stands and fades it out.
##
## Without this it kept advancing after the run ended, caught up with the
## player standing on the finish pad, and -- since the slab is CULL_DISABLED --
## filled the entire screen with magenta from the inside.
func disarm() -> void:
	_armed = false
	if _stopped:
		return
	_stopped = true
	var tw := create_tween()
	tw.tween_property(_mat, "albedo_color:a", 0.0, 0.5)
	tw.parallel().tween_property(_light, "light_energy", 0.0, 0.5)
	tw.tween_callback(hide)


func _process(_delta: float) -> void:
	if _stopped or _level == null or not Conductor.running:
		return

	wall_z = _level.wall_z(Conductor.clock())
	global_position = Vector3(0.0, 0.0, wall_z)

	var pulse := pow(1.0 - Conductor.beat_phase(), 3.0)
	_mat.emission_energy_multiplier = 1.4 + pulse * 5.0
	_light.light_energy = 2.0 + pulse * 6.0

	if _player == null:
		return
	# Ride at the player's height. The level climbs to 24m and drops back to
	# the floor, and a slab parked at y=0 would be invisible up on the narrows.
	var py := _player.global_position.y
	_mesh.position.y = py + HEIGHT * 0.5 - 1.4
	_light.position.y = py + 4.0

	if not _armed:
		return
	# Forward is -Z, so the wall is behind while its z is the LARGER value.
	# Once it is equal or smaller, it has gone past you.
	if wall_z <= _player.global_position.z:
		_armed = false
		caught.emit()


## Metres of daylight between you and the deadline. Negative means it is past
## you and the run is already over.
func lead(player_z: float) -> float:
	return wall_z - player_z
