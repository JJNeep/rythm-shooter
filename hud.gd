## Built entirely in code so there is no .tscn to keep in sync while the
## prototype is still moving around.
extends CanvasLayer

const HP_WIDTH := 240.0

var ring: Control

var _score_label: Label
var _combo_label: Label
var _grade_label: Label
var _ms_label: Label
var _hint_label: Label
var _status_label: Label
var _weapon_label: Label
var _banner_label: Label
var _banner_sub: Label
var _hp_back: ColorRect
var _hp_fill: ColorRect

var _grade_fade := 0.0
var _grade_colour := Color.WHITE
var _ms_fade := 0.0
var _banner_fade := 0.0
var _player: Node


func _ready() -> void:
	layer = 10

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	ring = Control.new()
	ring.set_script(load("res://beat_ring.gd"))
	ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(ring)

	# --- top left: score and combo ---
	_score_label = _make_label(root, 34, HORIZONTAL_ALIGNMENT_LEFT)
	_anchor(_score_label, 0.0, 0.0, 0.5, 0.0, 24, 18, 0, 60)

	_combo_label = _make_label(root, 22, HORIZONTAL_ALIGNMENT_LEFT)
	_anchor(_combo_label, 0.0, 0.0, 0.5, 0.0, 24, 60, 0, 95)

	# --- top right: phase and distance ---
	_status_label = _make_label(root, 20, HORIZONTAL_ALIGNMENT_RIGHT)
	_anchor(_status_label, 0.5, 0.0, 1.0, 0.0, 0, 22, -24, 56)

	# --- centre: grade popup and timing readout ---
	_grade_label = _make_label(root, 44, HORIZONTAL_ALIGNMENT_CENTER)
	_anchor(_grade_label, 0.0, 0.5, 1.0, 0.5, 0, 56, 0, 112)

	_ms_label = _make_label(root, 20, HORIZONTAL_ALIGNMENT_CENTER)
	_anchor(_ms_label, 0.0, 0.5, 1.0, 0.5, 0, 112, 0, 142)

	# --- centre, above: phase banner ---
	_banner_label = _make_label(root, 64, HORIZONTAL_ALIGNMENT_CENTER)
	_anchor(_banner_label, 0.0, 0.5, 1.0, 0.5, 0, -150, 0, -72)

	_banner_sub = _make_label(root, 20, HORIZONTAL_ALIGNMENT_CENTER)
	_anchor(_banner_sub, 0.0, 0.5, 1.0, 0.5, 0, -74, 0, -44)

	# --- bottom left: weapon and health ---
	_weapon_label = _make_label(root, 22, HORIZONTAL_ALIGNMENT_LEFT)
	_anchor(_weapon_label, 0.0, 1.0, 0.5, 1.0, 24, -98, 0, -66)

	_hp_back = ColorRect.new()
	_hp_back.color = Color(0, 0, 0, 0.45)
	_hp_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hp_back)
	_anchor(_hp_back, 0.0, 1.0, 0.0, 1.0, 24, -62, 24 + HP_WIDTH, -46)

	_hp_fill = ColorRect.new()
	_hp_fill.color = Color(0.35, 1.0, 0.6)
	_hp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hp_fill)
	_anchor(_hp_fill, 0.0, 1.0, 0.0, 1.0, 24, -62, 24 + HP_WIDTH, -46)

	# --- bottom: controls ---
	_hint_label = _make_label(root, 15, HORIZONTAL_ALIGNMENT_CENTER)
	_anchor(_hint_label, 0.0, 1.0, 1.0, 1.0, 0, -36, 0, -12)
	_hint_label.modulate.a = 0.5
	_hint_label.text = "WASD  ·  SHIFT dash  ·  SPACE jump  ·  CLICK on the beat  ·  1/2 or wheel weapon  ·  C calibrate  ·  R restart"

	Score.changed.connect(_on_score_changed)
	Score.graded.connect(_on_graded)
	_on_score_changed(0, 0, 1)
	set_health(100.0, 100.0)


## Wired up by the level once the player exists, so the HUD never has to go
## hunting for it.
func bind_player(player: Node) -> void:
	_player = player
	if player.has_signal("health_changed"):
		player.health_changed.connect(set_health)
	if "max_health" in player and "health" in player:
		set_health(player.health, player.max_health)
	var gun = player.get("gun")
	if gun and gun.has_signal("weapon_changed"):
		gun.weapon_changed.connect(_on_weapon_changed)
		_on_weapon_changed(gun.weapon_index, gun.current_gun)


func show_banner(title: String, sub: String = "") -> void:
	_banner_label.text = title
	_banner_sub.text = sub
	_banner_fade = 1.0


func set_status(text: String) -> void:
	_status_label.text = text


func set_health(health: float, max_health: float) -> void:
	var ratio := clampf(health / maxf(max_health, 0.001), 0.0, 1.0)
	_hp_fill.offset_right = _hp_fill.offset_left + HP_WIDTH * ratio
	_hp_fill.color = Color(0.95, 0.25, 0.30).lerp(Color(0.35, 1.0, 0.60), ratio)


func _on_weapon_changed(index: int, weapon: GunResource) -> void:
	if weapon == null:
		return
	# Naming the subdivision matters as much as naming the weapon: the two guns
	# are distinguished mainly by the rhythm they want from you.
	var sub := "1/4 notes"
	if is_equal_approx(weapon.grid_beats, 0.5):
		sub = "1/8 notes"
	elif is_equal_approx(weapon.grid_beats, 0.25):
		sub = "1/16 notes"
	_weapon_label.text = "%d · %s   (%s)" % [index + 1, weapon.gun_name, sub]


func _make_label(parent: Control, font_size: int, align: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_constant_override("outline_size", 7)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _anchor(c: Control, al: float, at: float, ar: float, ab: float,
		ol: float, ot: float, orr: float, ob: float) -> void:
	c.anchor_left = al
	c.anchor_top = at
	c.anchor_right = ar
	c.anchor_bottom = ab
	c.offset_left = ol
	c.offset_top = ot
	c.offset_right = orr
	c.offset_bottom = ob


func _on_score_changed(score: int, combo: int, multiplier: int) -> void:
	_score_label.text = "%d" % score
	var acc := 0.0
	if Score.shots > 0:
		acc = 100.0 * float(Score.hits) / float(Score.shots)
	_combo_label.text = "x%d   combo %d   best %d   acc %.0f%%" % [
		multiplier, combo, Score.best_combo, acc]


func _on_graded(grade: int, err_sec: float, points: int, did_hit: bool, on_beat: bool) -> void:
	_grade_colour = Gun.GRADE_COLOURS[grade]
	var label := Gun.GRADE_NAMES[grade]
	if grade < 3 and not did_hit:
		label += "  (no hit)"
	_grade_label.text = label
	_grade_fade = 1.0

	var ms := err_sec * 1000.0
	var word := "EARLY" if ms < 0.0 else "LATE"
	if absf(ms) < 6.0:
		word = "DEAD ON"
	# Naming the slot matters: without it, a shot snapped to an offbeat looks
	# identical to one snapped to a downbeat, and you cannot tell whether the
	# game read you the way you meant it.
	var slot_name := "on beat" if on_beat else "offbeat"
	_ms_label.text = "%+.0f ms  %s  ·  %s   %s" % [
		ms, word, slot_name, ("+%d" % points) if points > 0 else ""]
	_ms_fade = 1.0


func _process(delta: float) -> void:
	_grade_fade = maxf(_grade_fade - delta * 1.6, 0.0)
	_ms_fade = maxf(_ms_fade - delta * 1.1, 0.0)
	_banner_fade = maxf(_banner_fade - delta * 0.42, 0.0)

	# Pop the grade out and let it settle, rather than just fading it.
	var pop := 1.0 + pow(_grade_fade, 6.0) * 0.35
	_grade_label.scale = Vector2(pop, pop)
	_grade_label.pivot_offset = _grade_label.size * 0.5
	_grade_label.modulate = Color(
		_grade_colour.r, _grade_colour.g, _grade_colour.b, _grade_fade)
	_ms_label.modulate.a = _ms_fade * 0.9

	# Banner holds at full opacity before fading, so it is readable at speed.
	var ba := minf(_banner_fade * 3.0, 1.0)
	_banner_label.modulate.a = ba
	_banner_sub.modulate.a = ba * 0.8
