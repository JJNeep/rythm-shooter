## Beat-locked hitscan gun with timing-driven aim assist.
##
## The mechanic: you click, the shot snaps to the nearest beat slot, and how far
## off the beat you were becomes how far wide the bullet lands. Aim is handled
## for you, so the only skill axis is timing -- and you read your own timing
## error as spatial drift.
class_name Gun
extends Node3D

signal shot_fired(grade: int, err_sec: float, did_hit: bool)
signal weapon_changed(index: int, weapon: GunResource)

enum Grade { PERFECT, GREAT, GOOD, WHIFF }

const GRADE_NAMES: Array[String] = ["PERFECT", "GREAT", "GOOD", "WHIFF"]
const GRADE_COLOURS: Array[Color] = [
	Color(1.00, 0.93, 0.35),   # PERFECT - gold
	Color(0.35, 1.00, 0.62),   # GREAT   - green
	Color(0.45, 0.76, 1.00),   # GOOD    - blue
	Color(1.00, 0.30, 0.34),   # WHIFF   - red
]

## A grading window may never exceed this fraction of the slot spacing, or the
## windows of adjacent slots would overlap and a single click could grade as
## two different things.
const WINDOW_CAP := 0.45

## Used when `weapons` is left empty. Slot order is the 1/2 key order.
const DEFAULT_LOADOUT: Array[String] = [
	"res://DefaultGun.tres",
	"res://RocketLauncher.tres",
]

## The active weapon. Kept as its own property so everything downstream still
## reads current_gun and knows nothing about the loadout.
@export var current_gun: GunResource

## Weapons available, in slot order. Falls back to [current_gun] if left empty.
@export var weapons: Array[GunResource] = []

var weapon_index: int = 0
var current_ammo: int = 0
var locked_target: Node3D = null

var _muzzle: Node3D
var _models: Array[Node3D] = []
var _muzzles: Array[Node3D] = []
## Per weapon, because the two weapons sit on different grids so a slot index
## means different things to each. Swapping therefore lets you fit a rocket
## between two deagle eighths -- a weapon-swap cancel, which is very much the
## genre and is being left in deliberately.
var _last_slots: Array[float] = []
var _pending: bool = false
var _pending_at: float = 0.0
var _pending_err: float = 0.0
var _pending_on_beat: bool = true
var _audio: AudioStreamPlayer3D


func _ready() -> void:
	# The original code instanced current_gun.gun_scene here while gun.tscn ALSO
	# had the Deagle as a child, so two models were stacked and get_child(0) was
	# grabbing whichever happened to come first. Only build one if the scene has
	# not already given us a model to work with.
	if find_child("Spawner", true, false) == null and current_gun and current_gun.gun_scene:
		add_child(current_gun.gun_scene.instantiate())

	var m := find_child("Spawner", true, false)
	var deagle_muzzle: Node3D = m as Node3D if m is Node3D else self
	var deagle_model := find_child("Deagle", false, false) as Node3D

	# Loaded by path rather than wired into gun.tscn as a typed-array export,
	# which serialises awkwardly for custom resource types. Override `weapons`
	# in the inspector and this is skipped.
	if weapons.is_empty():
		for path in DEFAULT_LOADOUT:
			if ResourceLoader.exists(path):
				var w := load(path) as GunResource
				if w != null:
					weapons.append(w)
	if weapons.is_empty() and current_gun:
		weapons = [current_gun]

	_models.resize(weapons.size())
	_muzzles.resize(weapons.size())
	_last_slots.resize(weapons.size())
	_last_slots.fill(-INF)

	for i in weapons.size():
		if weapons[i].weapon_kind == GunResource.Kind.ROCKET:
			var rl := _build_launcher(deagle_muzzle)
			_models[i] = rl
			_muzzles[i] = rl.get_node("Muzzle") as Node3D
		else:
			_models[i] = deagle_model
			_muzzles[i] = deagle_muzzle

	_audio = AudioStreamPlayer3D.new()
	_audio.unit_size = 8.0
	add_child(_audio)

	swap_to(0)


func swap_to(index: int) -> void:
	if weapons.is_empty():
		return
	weapon_index = clampi(index, 0, weapons.size() - 1)
	current_gun = weapons[weapon_index]
	current_ammo = current_gun.max_magazine

	var mz := _muzzles[weapon_index]
	_muzzle = mz if mz != null else self

	# The deagle and the launcher share the scene, so hide rather than rebuild.
	for j in _models.size():
		if _models[j] != null:
			_models[j].visible = (j == weapon_index)

	_audio.stream = current_gun.fire_sound if current_gun.fire_sound else Sfx.shot()
	# Same sample, dropped an octave: cheap way to make the launcher sound heavy.
	_audio.pitch_scale = 0.62 if current_gun.weapon_kind == GunResource.Kind.ROCKET else 1.0
	weapon_changed.emit(weapon_index, current_gun)


func next_weapon(step: int = 1) -> void:
	if weapons.size() > 1:
		swap_to(posmod(weapon_index + step, weapons.size()))


## Built in code because there is no launcher model in the project. Its muzzle
## is placed exactly where the deagle's already is, so swapping weapons does
## not make the shot origin jump around on screen.
func _build_launcher(ref_muzzle: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = "RocketLauncher"
	add_child(root)

	var local := Vector3.ZERO
	if ref_muzzle != null and ref_muzzle != self and is_inside_tree():
		local = global_transform.affine_inverse() * ref_muzzle.global_position

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.21, 0.19, 0.23)
	mat.metallic = 0.6
	mat.roughness = 0.45

	var tube := CylinderMesh.new()
	tube.top_radius = 0.075
	tube.bottom_radius = 0.085
	tube.height = 0.80
	tube.radial_segments = 12
	var tube_mi := MeshInstance3D.new()
	tube_mi.mesh = tube
	tube_mi.material_override = mat
	tube_mi.rotation_degrees = Vector3(-90.0, 0.0, 0.0)   # +Y round onto -Z
	tube_mi.position = local + Vector3(0.0, 0.0, 0.40)
	root.add_child(tube_mi)

	var grip := BoxMesh.new()
	grip.size = Vector3(0.07, 0.18, 0.13)
	var grip_mi := MeshInstance3D.new()
	grip_mi.mesh = grip
	grip_mi.material_override = mat
	grip_mi.position = local + Vector3(0.0, -0.14, 0.62)
	root.add_child(grip_mi)

	var muzzle := Node3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = local
	root.add_child(muzzle)
	return root


func _process(_delta: float) -> void:
	locked_target = _find_target()

	# An early shot is held until the beat actually arrives. Timed against the
	# Conductor audio clock rather than a Timer, so hit-stop cannot shift it.
	if _pending and Conductor.clock() >= _pending_at:
		_pending = false
		_fire(_pending_err, _pending_on_beat)

	if current_gun.fire_mode == GunResource.FireMode.AUTOMATIC \
			and Input.is_action_pressed("shoot"):
		try_shoot(true)


## Call this the instant the mouse goes down, from _input -- not from
## _physics_process, where the timestamp resolution would be 16.7ms, a quarter
## of the whole grading window gone before you start.
func try_shoot(held: bool = false) -> void:
	if not Conductor.running:
		return
	if not current_gun.infinite_ammo and current_ammo <= 0:
		return
	if _pending:
		return

	var iv: float = current_gun.grid_beats
	var b := Conductor.beat_pos()
	var slot := Conductor.nearest_slot(iv, b)
	if slot == _last_slots[weapon_index]:
		return                                  # one shot per slot, per weapon
	_last_slots[weapon_index] = slot

	var err := (b - slot * iv) * Conductor.sec_per_beat
	var on_beat := slot_is_on_beat(slot)

	# Held auto-fire never reaches the top grades. Tapping on the beat earns the
	# aura; holding the button is spray-and-pray.
	if held:
		err = maxf(absf(err), _windows().y)

	if err < 0.0 and -err <= current_gun.max_hold:
		# Early: hold the shot so muzzle flash, report and bullet all land
		# together on the beat. This is why the gunfire sits in the mix instead
		# of fighting it.
		_pending = true
		_pending_at = Conductor.slot_time(iv, slot)
		_pending_err = err
		_pending_on_beat = on_beat
	else:
		_fire(err, on_beat)


func _slot_seconds() -> float:
	return current_gun.grid_beats * Conductor.sec_per_beat


## Is this slot a downbeat (a whole beat), or one of the offbeats between them?
func slot_is_on_beat(slot: float) -> bool:
	var frac := fposmod(slot * current_gun.grid_beats, 1.0)
	return minf(frac, 1.0 - frac) < 0.001


## The three grading windows in seconds, clamped so neighbouring slots cannot
## overlap. Returned as a Vector3 of (perfect, great, good).
func _windows() -> Vector3:
	var cap := _slot_seconds() * WINDOW_CAP
	var p := minf(current_gun.perfect_ms * 0.001, cap)
	var g := maxf(minf(current_gun.great_ms * 0.001, cap), p)
	var o := maxf(minf(current_gun.good_ms * 0.001, cap), g)
	return Vector3(p, g, o)


func _grade_of(err_abs: float, w: Vector3) -> Grade:
	if err_abs <= w.x:
		return Grade.PERFECT
	if err_abs <= w.y:
		return Grade.GREAT
	if err_abs <= w.z:
		return Grade.GOOD
	return Grade.WHIFF


func _fire(err_sec: float, on_beat: bool = true) -> void:
	if not current_gun.infinite_ammo:
		current_ammo -= 1

	var w := _windows()
	var grade := _grade_of(absf(err_sec), w)

	# Normalised against the GOOD boundary, so 1.0 means "right on the edge".
	# Deliberately not clamped at the top: a really bad click should spray wider
	# still, which is the mechanic working as advertised.
	var norm := err_sec / w.z

	var cam := get_viewport().get_camera_3d()
	var from: Vector3 = _muzzle.global_position
	var target := locked_target
	var aim_point: Vector3
	if target:
		aim_point = target.global_position
	elif cam:
		aim_point = cam.global_position - cam.global_basis.z * 30.0
	else:
		aim_point = from - global_basis.z * 30.0

	var dir := _aim_dir(from, aim_point, norm)

	if current_gun.weapon_kind == GunResource.Kind.ROCKET:
		_launch_rocket(from, dir, grade, err_sec, on_beat)
		_muzzle_flash(grade)
		if _audio.stream:
			_audio.play()
		# Scoring is deferred to the blast -- a rocket has not hit anything yet,
		# and the grade popup arriving WITH the explosion is the better feel.
		shot_fired.emit(grade, err_sec, false)
		return

	var hit := _hitscan(from, dir)

	var did_hit := false
	var end_point: Vector3 = from + dir * current_gun.range_metres
	if hit:
		end_point = hit.position
		var body: Object = hit.collider
		if body and body.has_method("take_damage"):
			var mult := 0.0
			if grade < current_gun.grade_damage.size():
				mult = current_gun.grade_damage[grade]
			body.take_damage(current_gun.damage * mult, dir, grade)
			did_hit = true

	_tracer(from, end_point, grade)
	_muzzle_flash(grade)
	if _audio.stream:
		_audio.play()
	if grade == Grade.PERFECT and did_hit:
		_hit_stop()

	Score.register(grade, err_sec, did_hit, on_beat)
	shot_fired.emit(grade, err_sec, did_hit)


## Offset the aim point in the plane perpendicular to the shot, at the target
## distance. Doing it in metres-at-the-target rather than as an angle means
## miss_at_good_edge reads the same at 5m and at 50m.
func _aim_dir(from: Vector3, target_point: Vector3, norm: float) -> Vector3:
	var to_t := target_point - from
	var dist := to_t.length()
	if dist < 0.01:
		return -global_basis.z

	var dir := to_t / dist
	var right := dir.cross(Vector3.UP)
	if right.length_squared() < 1e-5:          # shooting straight up or down
		right = dir.cross(Vector3.RIGHT)
	right = right.normalized()
	var up := right.cross(dir).normalized()

	var miss: float = minf(
		current_gun.miss_at_good_edge * pow(absf(norm), current_gun.miss_curve),
		current_gun.max_miss)

	# Early drifts left, late drifts right -- deterministic, so "I keep missing
	# left" teaches the player they are rushing. Random scatter would destroy
	# that signal and occasionally reward a bad click with a lucky hit.
	var lateral := signf(norm) * miss
	var vertical := randf_range(-0.3, 0.3) * miss
	return (to_t + right * lateral + up * vertical).normalized()


func _launch_rocket(from: Vector3, dir: Vector3, grade: int,
		err_sec: float, on_beat: bool) -> void:
	var world := get_tree().current_scene
	if world == null:
		return
	var r := Rocket.new()
	world.add_child(r)
	# launch() after add_child, so it can orient itself in world space.
	r.launch(from, dir, current_gun.projectile_speed, current_gun.blast_radius,
		current_gun.damage, grade, err_sec, on_beat, _exclusions())


func _exclusions() -> Array[RID]:
	var out: Array[RID] = []
	var pl := get_tree().get_first_node_in_group("player")
	if pl is CollisionObject3D:
		out.append((pl as CollisionObject3D).get_rid())
	return out


func _hitscan(from: Vector3, dir: Vector3) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(
		from, from + dir * current_gun.range_metres)
	q.collide_with_areas = false
	q.exclude = _exclusions()
	return space.intersect_ray(q)


## Soft lock: nearest-to-crosshair enemy inside the cone, with line of sight.
func _find_target() -> Node3D:
	var cam := get_viewport().get_camera_3d()
	if not cam:
		return null

	var fwd := -cam.global_basis.z
	var cos_lim := cos(deg_to_rad(current_gun.lock_angle_deg))
	var space := get_world_3d().direct_space_state
	var excl := _exclusions()

	var best: Node3D = null
	var best_dot := -1.0
	for e in get_tree().get_nodes_in_group("enemy"):
		if not (e is Node3D):
			continue
		var n := e as Node3D
		if n.has_method("is_alive") and not n.call("is_alive"):
			continue

		var to_e: Vector3 = n.global_position - cam.global_position
		var d := to_e.length()
		if d > current_gun.lock_range or d < 0.01:
			continue
		var dot := fwd.dot(to_e / d)
		if dot < cos_lim or dot <= best_dot:
			continue

		var q := PhysicsRayQueryParameters3D.create(cam.global_position, n.global_position)
		q.collide_with_areas = false
		q.exclude = excl
		var blocked := space.intersect_ray(q)
		if blocked:
			var c: Object = blocked.collider
			if c != n and not (c is Node and n.is_ancestor_of(c as Node)):
				continue                        # a wall is in the way

		best_dot = dot
		best = n
	return best


func _tracer(from: Vector3, to: Vector3, grade: Grade) -> void:
	var length := from.distance_to(to)
	if length < 0.05:
		return

	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.015
	mesh.bottom_radius = 0.015
	mesh.height = length
	mesh.radial_segments = 6
	mesh.rings = 0

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = GRADE_COLOURS[grade]
	mat.emission_enabled = true
	mat.emission = GRADE_COLOURS[grade]
	mat.emission_energy_multiplier = 6.0

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(mi)

	mi.global_position = (from + to) * 0.5
	var axis := (to - from).normalized()
	var up_hint := Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	mi.look_at(to, up_hint)
	# CylinderMesh runs along +Y, while look_at points -Z at the target, so
	# bring +Y round onto -Z.
	mi.rotate_object_local(Vector3.RIGHT, -PI * 0.5)

	var tw := mi.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.10)
	tw.parallel().tween_property(mat, "emission_energy_multiplier", 0.0, 0.10)
	tw.tween_callback(mi.queue_free)


func _muzzle_flash(grade: Grade) -> void:
	var light := OmniLight3D.new()
	light.light_color = GRADE_COLOURS[grade]
	light.light_energy = 6.0
	light.omni_range = 5.0
	light.shadow_enabled = false
	_muzzle.add_child(light)
	var tw := light.create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.08)
	tw.tween_callback(light.queue_free)


## A few frames of near-freeze on a perfect kill. Costs nothing, and it is most
## of the reason a hit feels like it landed.
func _hit_stop() -> void:
	Engine.time_scale = 0.05
	# ignore_time_scale = true, or the timer would itself be slowed by the very
	# thing it exists to undo.
	await get_tree().create_timer(0.045, true, false, true).timeout
	Engine.time_scale = 1.0


func reload() -> void:
	await get_tree().create_timer(current_gun.reload_time).timeout
	current_ammo = current_gun.max_magazine
