extends CharacterBody3D

const SPEED := 14.0           # 5.0 was walking pace; this is a movement shooter
const JUMP_VELOCITY := 6.2
const GROUND_ACCEL := 140.0   # snappy on the floor
const AIR_ACCEL := 32.0       # ... but momentum is preserved in the air, which
							  # is what makes a blast jump feel like anything
const DASH_MIN := 18.0        # dash speed for a badly timed dash
const DASH_MAX := 42.0        # ... and for one right on the beat
const DASH_TIME := 0.16
const MAX_FALL := 40.0        # terminal velocity, so a long drop stays readable

@export var mouse_sensitivity: float = 0.002

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var gun: Gun = $Head/Hand/Gun
@onready var anim: AnimationPlayer = $Head/Hand/AnimationPlayer

## Survival now lives in Score.energy rather than here. Health and energy were
## two bars measuring the same thing, and Beat Saber's single bar -- which a
## miss drains far faster than a hit refills -- is what turns clicking into a
## decision instead of a reflex.
var dead := false
## Set once the run has ended. Harder than `dead`: no movement at all, and the
## camera stops with it.
var frozen := false

var _cam_base_y := 0.0
var _dash_left := 0.0
var _dash_dir := Vector3.ZERO
var _dash_speed := 0.0
var _last_dash_slot := -INF
var _hurt := 0.0
var _kick := 0.0


func _ready() -> void:
	add_to_group("player")           # the gun excludes us from its own raycasts
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	# Godot coalesces input events and delivers them once per frame by default,
	# which puts a whole frame of slop on the timestamp a shot is graded with.
	# At 60fps that is 16ms of a 32ms PERFECT window spent before the player has
	# done anything wrong, and it gets worse the harder the scene is to draw.
	Input.use_accumulated_input = false
	_cam_base_y = camera.position.y
	Score.run_failed.connect(_on_run_failed)
	# The player scene ships its own crosshair; the HUD replaces it.
	var old_ui := get_node_or_null("UI")
	if old_ui:
		old_ui.visible = false


func _on_run_failed() -> void:
	freeze()


## The run is over, win or lose. Stop dead: no input, no momentum, and the
## mouse comes back so the tally can be read without the camera swinging about
## or the player wandering off the finish platform while the score goes up.
func freeze() -> void:
	if frozen:
		return
	frozen = true
	dead = true
	_dash_left = 0.0
	velocity = Vector3.ZERO
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _input(event: InputEvent) -> void:
	if not frozen and event is InputEventMouseMotion \
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		rotate_y(-mm.relative.x * mouse_sensitivity)
		head.rotate_x(-mm.relative.y * mouse_sensitivity)
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-89.0), deg_to_rad(85.0))

	# Shooting is timestamped HERE, not in _physics_process. At 60Hz physics the
	# timestamp resolution would be 16.7ms -- a quarter of the whole grading
	# window thrown away before the player has done anything wrong.
	if not dead and event.is_action_pressed("shoot") \
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		gun.try_shoot()
		if anim.has_animation("shoot"):
			anim.stop()
			anim.play("shoot")

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			gun.next_weapon(-1)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			gun.next_weapon(1)

	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).physical_keycode:
			KEY_SHIFT:
				_try_dash()
			KEY_1:
				gun.swap_to(0)
			KEY_2:
				gun.swap_to(1)
			KEY_Q:
				gun.next_weapon()
			KEY_P:
				Score.practice = not Score.practice
			KEY_R:
				_restart()
			KEY_C:
				get_tree().change_scene_to_file("res://calibration.tscn")
			KEY_F:
				_fix_timing()


## One-key calibration from the run you are already in.
##
## The end-of-run tally has always reported how late or early you were; this
## folds that straight into the saved offset, mid-run, using shots you have
## already taken. It measures the real path -- this machine's audio, the mp3,
## the chart, the frame rate -- rather than a click track in another scene, so
## it is the more honest of the two and costs one keypress.
func _fix_timing() -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	var applied := Settings.apply_measured_bias()
	if hud == null:
		return
	if is_zero_approx(applied):
		hud.show_banner("NOT ENOUGH SHOTS",
			"land about a dozen first, then press F  ·  C for the full screen")
	else:
		hud.show_banner("TIMING FIXED", "%+.0f ms applied  ·  now %+.0f ms total" % [
			applied, Settings.audio_offset_ms])


## Movement is on the grid too. Dashing on the beat carries you much further,
## which is the other half of the aura: you are not just shooting in time, you
## are moving in time.
func _try_dash() -> void:
	if dead or not Conductor.running:
		return
	var at := Conductor.beat_pos()
	var slot := Conductor.nearest_slot(1.0, at)
	if slot == _last_dash_slot:
		return                                   # one dash per beat
	_last_dash_slot = slot

	var frac := absf(Conductor.slot_error(1.0, at)) / Conductor.sec_per_beat
	var quality := clampf(1.0 - frac / 0.22, 0.0, 1.0)

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var dir := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y))
	if dir.length() < 0.1:
		dir = -global_basis.z                    # no stick input: dash forward
	_dash_dir = Vector3(dir.x, 0.0, dir.z).normalized()
	_dash_speed = lerpf(DASH_MIN, DASH_MAX, quality)
	_dash_left = DASH_TIME


## Thrown by a rocket blast. Cancels the dash so a blast always wins over
## whatever you were doing, which is what makes the launch feel decisive.
func apply_blast(dir: Vector3, force: float) -> void:
	_dash_left = 0.0
	velocity += dir * force
	velocity.y = minf(velocity.y, 34.0)
	_kick = 1.0


func on_hit() -> void:
	_hurt = 1.0


func _restart() -> void:
	Score.reset()
	get_tree().reload_current_scene()


func _process(delta: float) -> void:
	if Input.is_action_pressed("scope"):
		camera.fov = lerpf(camera.fov, 50.0, delta * 10.0)
	else:
		camera.fov = lerpf(camera.fov, 75.0, delta * 20.0)

	_hurt = maxf(_hurt - delta * 2.2, 0.0)
	_kick = maxf(_kick - delta * 3.0, 0.0)

	# A barely-there camera dip on each beat, plus a bigger one when something
	# throws you. Subtle on purpose -- enough to feel, not enough to fight aim.
	var pulse := pow(1.0 - Conductor.beat_phase(), 5.0) if Conductor.running else 0.0
	camera.position.y = _cam_base_y - pulse * 0.025 - _kick * 0.12


func _physics_process(delta: float) -> void:
	if frozen:
		# Gravity still applies until the feet are down, so crossing the line
		# in mid-air sets you on the platform instead of leaving you hanging
		# there. Everything horizontal is gone, so you land where you crossed.
		velocity.x = 0.0
		velocity.z = 0.0
		if is_on_floor():
			velocity.y = 0.0
		else:
			velocity += get_gravity() * delta
			velocity.y = maxf(velocity.y, -MAX_FALL)
		move_and_slide()
		return

	var grounded := is_on_floor()

	if not grounded:
		velocity += get_gravity() * delta
		velocity.y = maxf(velocity.y, -MAX_FALL)

	if not dead and Input.is_action_pressed("jump") and grounded:
		velocity.y = JUMP_VELOCITY

	if _dash_left > 0.0:
		_dash_left -= delta
		velocity.x = _dash_dir.x * _dash_speed
		velocity.z = _dash_dir.z * _dash_speed
	else:
		var want := Vector3.ZERO
		if not dead:
			var input_dir := Input.get_vector(
				"move_left", "move_right", "move_forward", "move_backward")
			want = (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
		var target := want * SPEED
		var accel := GROUND_ACCEL if grounded else AIR_ACCEL
		velocity.x = move_toward(velocity.x, target.x, accel * delta)
		velocity.z = move_toward(velocity.z, target.z, accel * delta)

	move_and_slide()
