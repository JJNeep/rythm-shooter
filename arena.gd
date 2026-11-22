## Prototype arena. Spawns the practice range, builds the HUD and starts the
## song. Everything here is deliberately procedural so the scene file stays
## tiny while the design is still moving.
extends Node3D

const SONG_PATH := "res://Aftermath.tres"
const TARGET_PATH := "res://target.tscn"
const HUD_PATH := "res://hud.gd"

@export var target_count: int = 8
@export var ring_radius: float = 15.0
@export var pillar_count: int = 4

var _lights: Array[OmniLight3D] = []
var _light_base: Array[float] = []


func _ready() -> void:
	add_to_group("world")
	randomize()

	_build_pillars()
	_build_targets()
	_build_lights()

	# Left untyped on purpose: the script attached below adds members that
	# CanvasLayer does not have, and a static type would reject reaching them.
	var hud = CanvasLayer.new()
	hud.set_script(load(HUD_PATH))
	add_child(hud)

	# Children run _ready before their parent, so the player (and its gun)
	# already exist by the time we get here.
	var player = get_node_or_null("Player")
	if player and hud.ring:
		hud.ring.gun = player.gun

	Conductor.start(load(SONG_PATH))


func _process(_delta: float) -> void:
	if not Conductor.running:
		return
	# The arena breathes with the track. Cheap, and it means the beat is
	# readable from anywhere on screen rather than only at the crosshair.
	var pulse := pow(1.0 - Conductor.beat_phase(), 3.0)
	for i in _lights.size():
		_lights[i].light_energy = _light_base[i] * (0.45 + pulse * 1.5)


func _build_targets() -> void:
	var scene: PackedScene = load(TARGET_PATH)
	for i in target_count:
		var t := scene.instantiate() as Node3D
		add_child(t)
		# Index 0 sits dead ahead with no jitter, so you spawn looking straight
		# at something to shoot rather than at empty floor.
		var a := _target_bearing(float(i))
		if i != 0:
			a += randf_range(-0.10, 0.10)
		var r := ring_radius + randf_range(-4.0, 5.0)
		t.position = Vector3(cos(a) * r, 0.9, sin(a) * r)


## Targets sit on this ring of bearings; -PI/2 is straight ahead of the spawn.
func _target_bearing(index: float) -> float:
	return -PI * 0.5 + TAU * index / float(target_count)


## Cover, so the line-of-sight check on the aim assist actually matters and the
## player has to move to open an angle rather than standing still.
##
## Placed on the BISECTORS between target bearings. Putting pillars on their own
## independent ring looks fine and then silently occludes targets wherever the
## two spacings happen to coincide -- which is exactly what 6 pillars and 8
## targets did, both landing on TAU * 0.75.
func _build_pillars() -> void:
	var n := mini(pillar_count, target_count / 2)
	for i in n:
		var a := _target_bearing(float(i) * 2.0 + 0.5)
		var r := ring_radius * 0.5
		var h := randf_range(2.5, 4.5)
		var w := randf_range(0.9, 1.5)

		var mesh := BoxMesh.new()
		mesh.size = Vector3(w, h, w)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.16, 0.15, 0.20)
		mat.roughness = 0.8
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat

		var shape := BoxShape3D.new()
		shape.size = mesh.size
		var cs := CollisionShape3D.new()
		cs.shape = shape

		var body := StaticBody3D.new()
		body.add_child(mi)
		body.add_child(cs)
		add_child(body)
		body.position = Vector3(cos(a) * r, h * 0.5, sin(a) * r)


func _build_lights() -> void:
	for i in 4:
		var a := TAU * float(i) / 4.0 + PI * 0.25
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.45, 0.75) if i % 2 == 0 else Color(0.4, 0.7, 1.0)
		light.omni_range = 34.0
		light.light_energy = 3.0
		light.shadow_enabled = false
		add_child(light)
		light.position = Vector3(cos(a) * ring_radius * 0.8, 5.5, sin(a) * ring_radius * 0.8)
		_lights.append(light)
		_light_base.append(3.0)
