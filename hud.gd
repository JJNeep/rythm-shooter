## Built entirely in code so there is no .tscn to keep in sync while the
## prototype is still moving around.
extends CanvasLayer

var ring: Control

var _score_label: Label
var _combo_label: Label
var _grade_label: Label
var _ms_label: Label
var _hint_label: Label
var _grade_fade := 0.0
var _grade_colour := Color.WHITE
var _ms_fade := 0.0


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

	# --- centre: grade popup and timing readout ---
	_grade_label = _make_label(root, 44, HORIZONTAL_ALIGNMENT_CENTER)
	_anchor(_grade_label, 0.0, 0.5, 1.0, 0.5, 0, 56, 0, 112)

	_ms_label = _make_label(root, 20, HORIZONTAL_ALIGNMENT_CENTER)
	_anchor(_ms_label, 0.0, 0.5, 1.0, 0.5, 0, 112, 0, 142)

	# --- bottom: controls ---
	_hint_label = _make_label(root, 15, HORIZONTAL_ALIGNMENT_CENTER)
	_anchor(_hint_label, 0.0, 1.0, 1.0, 1.0, 0, -40, 0, -14)
	_hint_label.modulate.a = 0.5
	_hint_label.text = "WASD move  ·  SHIFT dash  ·  SPACE jump  ·  CLICK on the beat  ·  R restart  ·  ESC release mouse"

	Score.changed.connect(_on_score_changed)
	Score.graded.connect(_on_graded)
	_on_score_changed(0, 0, 1)


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


func _on_graded(grade: int, err_sec: float, points: int, did_hit: bool) -> void:
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
	_ms_label.text = "%+.0f ms  %s   %s" % [ms, word, ("+%d" % points) if points > 0 else ""]
	_ms_fade = 1.0


func _process(delta: float) -> void:
	_grade_fade = maxf(_grade_fade - delta * 1.6, 0.0)
	_ms_fade = maxf(_ms_fade - delta * 1.1, 0.0)

	# Pop the grade out and let it settle, rather than just fading it.
	var pop := 1.0 + pow(_grade_fade, 6.0) * 0.35
	_grade_label.scale = Vector2(pop, pop)
	_grade_label.pivot_offset = _grade_label.size * 0.5
	_grade_label.modulate = Color(
		_grade_colour.r, _grade_colour.g, _grade_colour.b, _grade_fade)
	_ms_label.modulate.a = _ms_fade * 0.9
