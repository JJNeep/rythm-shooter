## Shared gib burst, used by the practice targets and the horde alike.
##
## Globally capped, because the chase phase kills a great many things and
## settled chunks still cost broadphase even once Jolt has slept them.
class_name Gibs
extends RefCounted

const GROUP := "gib"
const CAP := 130


static func burst(world: Node, origin: Vector3, dir: Vector3, power: float,
		colour: Color, count: int = 10, scale_mul: float = 1.0) -> void:
	if world == null or not world.is_inside_tree():
		return
	var tree := world.get_tree()

	# Cull oldest first so a big wave cannot blow the budget.
	var existing := tree.get_nodes_in_group(GROUP)
	var over := existing.size() + count - CAP
	for i in maxi(over, 0):
		if i < existing.size():
			existing[i].queue_free()

	var flat := Vector3(dir.x, 0.0, dir.z)
	flat = flat.normalized() if flat.length() > 0.01 else Vector3.FORWARD

	for i in count:
		var s := randf_range(0.10, 0.26) * scale_mul
		var size := Vector3(s, s * randf_range(0.7, 1.8), s * randf_range(0.7, 1.3))

		var box := BoxMesh.new()
		box.size = size
		var mat := StandardMaterial3D.new()
		mat.albedo_color = colour.darkened(randf_range(0.0, 0.45))
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var mi := MeshInstance3D.new()
		mi.mesh = box
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		var shape := BoxShape3D.new()
		shape.size = size
		var cs := CollisionShape3D.new()
		cs.shape = shape

		var rb := RigidBody3D.new()
		rb.mass = 0.35
		rb.add_to_group(GROUP)
		rb.add_child(mi)
		rb.add_child(cs)
		world.add_child(rb)

		rb.global_position = origin + Vector3(
			randf_range(-0.3, 0.3), randf_range(-0.7, 0.8), randf_range(-0.3, 0.3))
		var kick := flat * power \
			+ Vector3(randf_range(-3.0, 3.0), randf_range(2.0, 7.0), randf_range(-3.0, 3.0))
		rb.apply_central_impulse(kick * rb.mass)
		rb.angular_velocity = Vector3(
			randf_range(-14.0, 14.0), randf_range(-14.0, 14.0), randf_range(-14.0, 14.0))

		var tw := rb.create_tween()
		tw.tween_interval(2.5)
		tw.tween_property(mat, "albedo_color:a", 0.0, 1.0)
		tw.tween_callback(rb.queue_free)
