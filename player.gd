extends CharacterBody3D


const SPEED = 5.0
const JUMP_VELOCITY = 4.5

var mouse_sensitivity: float = 0.002

@onready var head: Node3D = $Head
@onready var gun: Node3D = $Head/Hand/Gun

var no_reloading = true
var shooting = false

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		
		# Rotate only the head/camera up and down (X-axis)
		head.rotate_x(-event.relative.y * mouse_sensitivity)
		
		# Clamp vertical look so the player can't flip their head upside down
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-85.0), deg_to_rad(85.0))

func _physics_process(delta: float) -> void:
	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle jump.
	if Input.is_action_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY
	
	#if Input.is_action_pressed("scope"):
	#	$Hand.rotation.x = head.rotation.x
	#else:
	#	$Hand.rotation.x = 0
	
	if Input.is_action_pressed("scope"):
		$Head/Camera3D.fov = lerpf($Head/Camera3D.fov,50.0,delta*10)
	else:
		$Head/Camera3D.fov = lerpf($Head/Camera3D.fov,75.0,delta*20)
	
	if Input.is_action_just_pressed("shoot") and gun.can_fire and not gun.current_ammo <= 0:
		gun.shoot()
		$Head/Hand/AnimationPlayer.stop()
		$Head/Hand/AnimationPlayer.play("shoot")
	
	#if Input.is_action_just_pressed("shoot"):
		#shooting = true
	#if shooting:
		#if not $Head/Hand/Gun.rotation_degrees.x > 19 and no_reloading:
			#$Head/Hand/Gun.rotation_degrees.x = lerpf($Head/Hand/Gun.rotation_degrees.x,20,delta*40)
		#else:
			#no_reloading = false
			#$Head/Hand/Gun.rotation_degrees.x = lerpf($Head/Hand/Gun.rotation_degrees.x,0,delta*20)
			#if $Head/Hand/Gun.rotation_degrees.x < 0.1:
				#no_reloading = true
				#shooting = false
	
	# Get the input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()
