extends CharacterBody3D

const SPEED := 10.0           # 5.0 was walking pace; an Ultrakill-like wants pace
const JUMP_VELOCITY := 5.5
const DASH_MIN := 14.0        # dash speed for a badly timed dash
const DASH_MAX := 34.0        # ... and for one right on the beat
const DASH_TIME := 0.16

@export var mouse_sensitivity: float = 0.002

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var gun: Gun = $Head/Hand/Gun
@onready var anim: AnimationPlayer = $Head/Hand/AnimationPlayer

var _cam_base_y := 0.0
var _dash_left := 0.0
var _dash_dir := Vector3.ZERO
var _dash_speed := 0.0
var _last_dash_slot := -INF


func _ready() -> void:
	add_to_group("player")           # the gun excludes us from its own raycasts
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_cam_base_y = camera.position.y
	# The player scene ships its own crosshair; the HUD replaces it.
	var old_ui := get_node_or_null("UI")
	if old_ui:
		old_ui.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		rotate_y(-mm.relative.x * mouse_sensitivity)
		head.rotate_x(-mm.relative.y * mouse_sensitivity)
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-85.0), deg_to_rad(85.0))

	# Shooting is timestamped HERE, not in _physics_process. At 60Hz physics the
	# timestamp resolution would be 16.7ms -- a quarter of the whole grading
	# window thrown away before the player has done anything wrong.
	if event.is_action_pressed("shoot") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		gun.try_shoot()
		if anim.has_animation("shoot"):
			anim.stop()
			anim.play("shoot")

	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		match key.physical_keycode:
			KEY_SHIFT:
				_try_dash()
			KEY_R:
				_restart()


## Movement is on the grid too. Dashing on the beat carries you much further,
## which is the other half of the aura: you are not just shooting in time, you
## are moving in time.
func _try_dash() -> void:
	if not Conductor.running:
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


func _restart() -> void:
	Score.reset()
	get_tree().reload_current_scene()


func _process(delta: float) -> void:
	if Input.is_action_pressed("scope"):
		camera.fov = lerpf(camera.fov, 50.0, delta * 10.0)
	else:
		camera.fov = lerpf(camera.fov, 75.0, delta * 20.0)

	# A barely-there camera dip on each beat. Subtle on purpose -- enough to
	# feel the pulse, not enough to fight your aim.
	var pulse := pow(1.0 - Conductor.beat_phase(), 5.0) if Conductor.running else 0.0
	camera.position.y = _cam_base_y - pulse * 0.025


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	if Input.is_action_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	if _dash_left > 0.0:
		_dash_left -= delta
		velocity.x = _dash_dir.x * _dash_speed
		velocity.z = _dash_dir.z * _dash_speed
	else:
		var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
		var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
		if direction:
			velocity.x = direction.x * SPEED
			velocity.z = direction.z * SPEED
		else:
			velocity.x = move_toward(velocity.x, 0.0, SPEED)
			velocity.z = move_toward(velocity.z, 0.0, SPEED)

	move_and_slide()
