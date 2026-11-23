## A linear level in three phases, built procedurally so there is no handmade
## geometry to keep in sync while the design is still moving.
##
##   WARMUP  0-55m    static targets, learn the grid, nothing chasing you
##   RUN     55-195m  the horde spawns BEHIND you and surges on the beat.
##                    Stop moving and it catches you. Rockets clear it.
##   STAND   195-262m last stretch, they come from every side
##
## The floor strips are spaced 6m apart, which is how far you travel in one
## beat at full sprint -- so at speed you pass exactly one per beat and the
## level itself keeps time for you.
extends Node3D

enum Phase { WARMUP, RUN, STAND, CLEARED, FAILED }

const SONG_PATH := "res://Aftermath.tres"
const TARGET_PATH := "res://target.tscn"
const HORDE_PATH := "res://horde_enemy.tscn"
const HUD_PATH := "res://hud.gd"

const HALF_WIDTH := 11.0
const LENGTH := 280.0
const RUN_AT := 55.0
const STAND_AT := 195.0
const FINISH_AT := 262.0

const STRIP_SPACING := 6.0
const MAX_HORDE := 55
const SPAWN_BEHIND := 26.0

var phase: int = Phase.WARMUP
var progress: float = 0.0

var _player: Node3D
var _hud
var _horde_scene: PackedScene
var _lights: Array[OmniLight3D] = []
var _strip_mat: StandardMaterial3D
var _announced_rockets := false


func _ready() -> void:
	add_to_group("world")
	randomize()
	_horde_scene = load(HORDE_PATH)

	_build_corridor()
	_build_strips()
	_build_pillars()
	_build_lights()
	_build_warmup_targets()

	_hud = CanvasLayer.new()
	_hud.set_script(load(HUD_PATH))
	add_child(_hud)

	_player = get_node_or_null("Player")
	if _player:
		if _hud.ring:
			_hud.ring.gun = _player.gun
		_hud.bind_player(_player)
	# Survival moved from player health to Score.energy, so failure is reported
	# there now. This older procedural level is kept only as a sandbox.
	Score.run_failed.connect(_on_player_died)

	Conductor.beat.connect(_on_beat)
	Conductor.start(load(SONG_PATH), true)

	_hud.show_banner("GET MOVING", "click on the beat  ·  shift to dash")


# ---------------------------------------------------------------- geometry ---

func _solid(centre: Vector3, size: Vector3, colour: Color, emissive: float = 0.0,
		shared_mat: StandardMaterial3D = null) -> StaticBody3D:
	var mesh := BoxMesh.new()
	mesh.size = size

	var mat := shared_mat
	if mat == null:
		mat = StandardMaterial3D.new()
		mat.albedo_color = colour
		mat.roughness = 0.85
		if emissive > 0.0:
			mat.emission_enabled = true
			mat.emission = colour
			mat.emission_energy_multiplier = emissive

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat

	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape

	var body := StaticBody3D.new()
	body.add_child(mi)
	body.add_child(cs)
	add_child(body)
	body.position = centre
	return body


func _decor(centre: Vector3, size: Vector3, mat: StandardMaterial3D) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.position = centre


func _build_corridor() -> void:
	var mid := -LENGTH * 0.5
	_solid(Vector3(0, -0.5, mid), Vector3(HALF_WIDTH * 2.0, 1.0, LENGTH),
		Color(0.11, 0.10, 0.14))
	_solid(Vector3(-HALF_WIDTH, 4.0, mid), Vector3(1.0, 9.0, LENGTH),
		Color(0.16, 0.14, 0.20))
	_solid(Vector3(HALF_WIDTH, 4.0, mid), Vector3(1.0, 9.0, LENGTH),
		Color(0.16, 0.14, 0.20))
	# Back wall, so you cannot simply reverse away from the chase.
	_solid(Vector3(0, 4.0, 5.0), Vector3(HALF_WIDTH * 2.0, 9.0, 1.0),
		Color(0.16, 0.14, 0.20))
	# End wall past the finish line.
	_solid(Vector3(0, 4.0, -LENGTH - 1.0), Vector3(HALF_WIDTH * 2.0, 9.0, 1.0),
		Color(0.16, 0.14, 0.20))


## One shared material for every strip, so pulsing them all costs a single
## property write per frame rather than one per strip.
func _build_strips() -> void:
	_strip_mat = StandardMaterial3D.new()
	_strip_mat.albedo_color = Color(0.40, 0.75, 1.0)
	_strip_mat.emission_enabled = true
	_strip_mat.emission = Color(0.40, 0.75, 1.0)
	_strip_mat.emission_energy_multiplier = 1.0
	_strip_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var n := int(LENGTH / STRIP_SPACING)
	for i in n:
		_decor(Vector3(0.0, 0.015, -float(i) * STRIP_SPACING),
			Vector3(HALF_WIDTH * 2.0 - 2.0, 0.03, 0.18), _strip_mat)


func _build_pillars() -> void:
	var z := -24.0
	var side := 1.0
	while z > -STAND_AT:
		var h := randf_range(3.0, 5.5)
		var w := randf_range(1.2, 2.0)
		_solid(Vector3(side * randf_range(3.5, HALF_WIDTH - 2.0), h * 0.5, z),
			Vector3(w, h, w), Color(0.19, 0.17, 0.23))
		side = -side
		z -= randf_range(18.0, 26.0)


func _build_lights() -> void:
	var n := int(LENGTH / 26.0)
	for i in n + 1:
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.42, 0.72) if i % 2 == 0 else Color(0.38, 0.68, 1.0)
		light.omni_range = 36.0
		light.light_energy = 3.0
		light.shadow_enabled = false
		add_child(light)
		light.position = Vector3(
			(HALF_WIDTH - 2.0) * (1.0 if i % 2 == 0 else -1.0), 6.0, -float(i) * 26.0)
		_lights.append(light)


func _build_warmup_targets() -> void:
	var scene: PackedScene = load(TARGET_PATH)
	var spots := [
		Vector3(-5.0, 0.9, -16.0), Vector3(5.5, 0.9, -24.0),
		Vector3(-6.5, 0.9, -33.0), Vector3(4.0, 0.9, -42.0),
		Vector3(0.0, 0.9, -50.0),
	]
	for p in spots:
		var t := scene.instantiate() as Node3D
		add_child(t)
		t.position = p


# ------------------------------------------------------------------- phases ---

func _on_beat(index: int) -> void:
	match phase:
		Phase.RUN:
			# Every other beat, so there is a gap to shoot into.
			if index % 2 == 0:
				_spawn_behind(5)
		Phase.STAND:
			if index % 2 == 0:
				_spawn_around(7)


func _spawn_behind(count: int) -> void:
	if _player == null:
		return
	var live := get_tree().get_nodes_in_group("horde").size()
	if live >= MAX_HORDE:
		return
	count = mini(count, MAX_HORDE - live)
	var pz: float = _player.global_position.z
	for i in count:
		var e := _horde_scene.instantiate() as Node3D
		add_child(e)
		e.global_position = Vector3(
			randf_range(-HALF_WIDTH + 1.6, HALF_WIDTH - 1.6),
			0.85,
			pz + randf_range(SPAWN_BEHIND, SPAWN_BEHIND + 14.0))


func _spawn_around(count: int) -> void:
	if _player == null:
		return
	var live := get_tree().get_nodes_in_group("horde").size()
	if live >= MAX_HORDE:
		return
	count = mini(count, MAX_HORDE - live)
	var p: Vector3 = _player.global_position
	for i in count:
		var a := randf() * TAU
		var r := randf_range(17.0, 27.0)
		var e := _horde_scene.instantiate() as Node3D
		add_child(e)
		e.global_position = Vector3(
			clampf(p.x + cos(a) * r, -HALF_WIDTH + 1.6, HALF_WIDTH - 1.6),
			0.85,
			clampf(p.z + sin(a) * r, -LENGTH + 2.0, 3.0))


func _set_phase(next: int) -> void:
	if phase == next:
		return
	phase = next
	match phase:
		Phase.RUN:
			_hud.show_banner("RUN", "they surge on the beat  ·  2 for rockets")
			_announced_rockets = true
		Phase.STAND:
			_hud.show_banner("HOLD", "from every side now")
		Phase.CLEARED:
			_hud.show_banner("LEVEL CLEAR", "score %d  ·  best combo %d" % [
				Score.score, Score.best_combo])
		Phase.FAILED:
			_hud.show_banner("WIPED OUT", "R to restart")


func _on_player_died() -> void:
	_set_phase(Phase.FAILED)


func _process(delta: float) -> void:
	if Conductor.running:
		# One write, every strip. The level keeps time with the music.
		var pulse := pow(1.0 - Conductor.beat_phase(), 3.0)
		if _strip_mat:
			_strip_mat.emission_energy_multiplier = 0.5 + pulse * 5.0
		for l in _lights:
			l.light_energy = 1.4 + pulse * 4.0

	if _player == null or phase == Phase.CLEARED or phase == Phase.FAILED:
		return

	progress = clampf(-_player.global_position.z, 0.0, FINISH_AT)

	if progress >= FINISH_AT:
		_set_phase(Phase.CLEARED)
	elif progress >= STAND_AT:
		_set_phase(Phase.STAND)
	elif progress >= RUN_AT:
		_set_phase(Phase.RUN)

	_hud.set_status("%s   %dm / %dm" % [
		_phase_name(), int(progress), int(FINISH_AT)])


func _phase_name() -> String:
	match phase:
		Phase.WARMUP: return "WARM-UP"
		Phase.RUN: return "THE RUN"
		Phase.STAND: return "LAST STAND"
		Phase.CLEARED: return "CLEAR"
		Phase.FAILED: return "DOWN"
	return ""
