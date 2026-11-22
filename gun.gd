## Beat-locked hitscan gun with timing-driven aim assist.
##
## The mechanic: you click, the shot snaps to the nearest beat slot, and how far
## off the beat you were becomes how far wide the bullet lands. Aim is handled
## for you, so the only skill axis is timing -- and you read your own timing
## error as spatial drift.
class_name Gun
extends Node3D

signal shot_fired(grade: int, err_sec: float, did_hit: bool)

enum Grade { PERFECT, GREAT, GOOD, WHIFF }

const GRADE_NAMES: Array[String] = ["PERFECT", "GREAT", "GOOD", "WHIFF"]
const GRADE_COLOURS: Array[Color] = [
	Color(1.00, 0.93, 0.35),   # PERFECT - gold
	Color(0.35, 1.00, 0.62),   # GREAT   - green
	Color(0.45, 0.76, 1.00),   # GOOD    - blue
	Color(1.00, 0.30, 0.34),   # WHIFF   - red
]

@export var current_gun: GunResource

var current_ammo: int = 0
var locked_target: Node3D = null

var _muzzle: Node3D
var _last_slot: float = -INF
var _pending: bool = false
var _pending_at: float = 0.0
var _pending_err: float = 0.0
var _audio: AudioStreamPlayer3D


func _ready() -> void:
	current_ammo = current_gun.max_magazine

	# The original code instanced current_gun.gun_scene here while gun.tscn ALSO
	# had the Deagle as a child, so two models were stacked and get_child(0) was
	# grabbing whichever happened to come first. Only build one if the scene has
	# not already given us a model to work with.
	if find_child("Spawner", true, false) == null and current_gun.gun_scene:
		add_child(current_gun.gun_scene.instantiate())

	var m := find_child("Spawner", true, false)
	_muzzle = m as Node3D if m is Node3D else self

	_audio = AudioStreamPlayer3D.new()
	_audio.stream = current_gun.fire_sound if current_gun.fire_sound else Sfx.shot()
	_audio.unit_size = 8.0
	add_child(_audio)


func _process(_delta: float) -> void:
	locked_target = _find_target()

	# An early shot is held until the beat actually arrives. Timed against the
	# Conductor audio clock rather than a Timer, so hit-stop cannot shift it.
	if _pending and Conductor.clock() >= _pending_at:
		_pending = false
		_fire(_pending_err)

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

	var iv: float = current_gun.fire_interval_beats
	var b := Conductor.beat_pos()
	var slot := Conductor.nearest_slot(iv, b)
	if slot == _last_slot:
		return                                  # one shot per slot
	_last_slot = slot

	var err := (b - slot * iv) * Conductor.sec_per_beat

	# Held auto-fire never reaches the top grades. Tapping on the beat earns the
	# aura; holding the button is spray-and-pray.
	if held:
		err = maxf(absf(err), current_gun.great_window * _slot_seconds())

	if err < 0.0 and -err <= current_gun.max_hold:
		# Early: hold the shot so muzzle flash, report and bullet all land
		# together on the beat. This is why the gunfire sits in the mix instead
		# of fighting it.
		_pending = true
		_pending_at = Conductor.slot_time(iv, slot)
		_pending_err = err
	else:
		_fire(err)


func _slot_seconds() -> float:
	return current_gun.fire_interval_beats * Conductor.sec_per_beat


func _grade_of(frac: float) -> Grade:
	if frac <= current_gun.perfect_window:
		return Grade.PERFECT
	if frac <= current_gun.great_window:
		return Grade.GREAT
	if frac <= current_gun.good_window:
		return Grade.GOOD
	return Grade.WHIFF


func _fire(err_sec: float) -> void:
	if not current_gun.infinite_ammo:
		current_ammo -= 1

	var slot_sec := _slot_seconds()
	var grade := _grade_of(absf(err_sec) / slot_sec)

	# Normalised against the GOOD boundary, so 1.0 means "right on the edge".
	# Deliberately not clamped at the top: a really bad click should spray wider
	# still, which is the mechanic working as advertised.
	var norm := err_sec / (current_gun.good_window * slot_sec)

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

	Score.register(grade, err_sec, did_hit)
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
