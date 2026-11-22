## Crosshair, approach ring and lock bracket.
##
## The approach ring is the important part: it contracts and meets the inner
## ring at the exact moment of the next beat, so the beat is readable with the
## sound off. Borrowed straight from osu's approach circles, and it is the
## difference between "I cannot tell when to click" and "oh, obviously now".
extends Control

const R_INNER := 17.0
const R_OUTER := 62.0

var gun: Gun = null


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5

	# --- crosshair ---
	var white := Color(1, 1, 1, 0.9)
	for d in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		draw_line(c + d * 6.0, c + d * 13.0, white, 2.0)
	draw_circle(c, 1.6, white)

	if not Conductor.running:
		return

	# Follow the gun's grid, not the beat. On an eighth-note grid the ring has
	# to contract twice per beat, or the offbeats are playable but invisible.
	var grid := 1.0
	if gun and gun.current_gun:
		grid = maxf(gun.current_gun.grid_beats, 0.01)

	var slot_pos := Conductor.beat_pos() / grid
	var ph := fposmod(slot_pos, 1.0)
	var flash := pow(1.0 - ph, 6.0)

	# Downbeats get gold and a wider approach, offbeats blue and a tighter one,
	# so you can still feel the bar through the subdivision.
	var on_beat := true
	if gun and gun.current_gun:
		on_beat = gun.slot_is_on_beat(ceilf(slot_pos))
	var tint := Color(1.0, 0.93, 0.35) if on_beat else Color(0.45, 0.80, 1.00)
	var outer := R_OUTER if on_beat else R_OUTER * 0.72

	# --- approach ring: lands on the inner ring exactly on the next slot ---
	draw_arc(c, lerpf(outer, R_INNER, ph), 0.0, TAU, 48,
		Color(tint.r, tint.g, tint.b, 0.16 + 0.42 * ph), 2.0, true)

	# --- inner reference ring, pops on the slot ---
	draw_arc(c, R_INNER, 0.0, TAU, 48,
		Color(tint.r, tint.g, tint.b, 0.30 + 0.70 * flash), 2.0 + 2.5 * flash, true)

	# --- lock bracket, so the aim assist never feels arbitrary ---
	if gun and gun.locked_target and is_instance_valid(gun.locked_target):
		var cam := get_viewport().get_camera_3d()
		if not cam:
			return
		var wp: Vector3 = gun.locked_target.global_position
		if cam.is_position_behind(wp):
			return
		var p := cam.unproject_position(wp)
		var s := 24.0
		var arm := 8.0
		var col := Color(1.0, 0.93, 0.35, 0.55 + 0.35 * flash)
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				var corner := p + Vector2(sx * s, sy * s)
				draw_line(corner, corner - Vector2(sx * arm, 0.0), col, 2.0)
				draw_line(corner, corner - Vector2(0.0, sy * arm), col, 2.0)
