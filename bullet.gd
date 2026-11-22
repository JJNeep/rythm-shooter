extends RigidBody3D

@onready var timer = get_tree().create_timer(20)

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	timer.timeout.connect(on_timout)

func on_timout() -> void:
	queue_free()
