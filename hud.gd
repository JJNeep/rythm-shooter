## Built entirely in code so there is no .tscn to keep in sync while the
## prototype is still moving around.
extends CanvasLayer

const BAR_WIDTH := 300.0
const CHARGE_WIDTH := 160.0
const TALLY_W := 660.0
const TALLY_H := 424.0

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
var _energy_label: Label
var _practice_label: Label
var _bias_label: Label

var _energy_back: ColorRect
var _energy_fill: ColorRect
var _charge_back: ColorRect
var _charge_fill: ColorRect
var _danger: ColorRect

var _tally_panel: ColorRect
var _tally_root: Control
var _tally_score: Label

var _grade_fade := 0.0
var _grade_colour := Color.WHITE
var _ms_fade := 0.0
var _banner_fade := 0.0
var _danger_amount := 0.0


func _ready() -> void:
	layer = 10
	add_to_group("hud")              # the player looks us up to report a fix

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	ring = Control.new()
	ring.set_script(load("res://beat_ring.gd"))
	ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(ring)

	# Screen tint that rises as the wall closes. Added before the text so it
	# never washes out the readouts.
	_danger = ColorRect.new()
	_danger.color = Color(0.9, 0.1, 0.35, 0.0)
	_danger.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_danger.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_danger)

	_score_label = _make_label(root, 34, HORIZONTAL_ALIGNMENT_LEFT)
	_anchor(_score_label, 0.0, 0.0, 0.5, 0.0, 24, 18, 0, 60)

	_combo_label = _make_label(root, 22, HORIZONTAL_ALIGNMENT_LEFT)
	_anchor(_combo_label, 0.0, 0.0, 0.5, 0.0, 24, 60, 0, 95)

	_status_label = _make_label(root, 20, HORIZONTAL_ALIGNMENT_RIGHT)
	_anchor(_status_label, 0.5, 0.0, 1.0, 0.0, 0, 22, -24, 56)

	_practice_label = _make_label(root, 16, HORIZONTAL_ALIGNMENT_RIGHT)
	_anchor(_practice_label, 0.5, 0.0, 1.0, 0.0, 0, 56, -24, 82)
	_practice_label.modulate = Color(0.5, 0.9, 1.0, 0.85)

	_grade_label = _make_label(root, 44, HORIZONTAL_ALIGNMENT_CENTER)
	_anchor(_grade_label, 0.0, 0.5, 1.0, 0.5, 0, 56, 0, 112)

	_ms_label = _make_label(root, 20, HORIZONTAL_ALIGNMENT_CENTER)
	_anchor(_ms_label, 0.0, 0.5, 1.0, 0.5, 0, 112, 0, 142)

	_banner_label = _make_label(root, 64, HORIZONTAL_ALIGNMENT_CENTER)
	_anchor(_banner_label, 0.0, 0.5, 1.0, 0.5, 0, -160, 0, -82)

	_banner_sub = _make_label(root, 20, HORIZONTAL_ALIGNMENT_CENTER)
	_anchor(_banner_sub, 0.0, 0.5, 1.0, 0.5, 0, -84, 0, -54)

	# --- bottom left: timing, weapon, charges, energy ---
	# The running timing bias, live. Until now it only appeared on the results
	# screen, which is the one moment it is too late to act on: a player whose
	# audio is 40ms late spends the entire run believing the grading is wrong.
	_bias_label = _make_label(root, 15, HORIZONTAL_ALIGNMENT_LEFT)
	_anchor(_bias_label, 0.0, 1.0, 0.6, 1.0, 24, -158, 0, -134)

	_weapon_label = _make_label(root, 22, HORIZONTAL_ALIGNMENT_LEFT)
	_anchor(_weapon_label, 0.0, 1.0, 0.5, 1.0, 24, -132, 0, -100)

	_charge_back = _bar(root, Color(0, 0, 0, 0.45), -96, -86, CHARGE_WIDTH)
	_charge_fill = _bar(root, Color(1.0, 0.62, 0.26), -96, -86, CHARGE_WIDTH)

	_energy_label = _make_label(root, 17, HORIZONTAL_ALIGNMENT_LEFT)
	_anchor(_energy_label, 0.0, 1.0, 0.5, 1.0, 24, -82, 0, -60)

	_energy_back = _bar(root, Color(0, 0, 0, 0.45), -58, -40, BAR_WIDTH)
	_energy_fill = _bar(root, Color(0.35, 1.0, 0.60), -58, -40, BAR_WIDTH)

	_hint_label = _make_label(root, 15, HORIZONTAL_ALIGNMENT_CENTER)
	_anchor(_hint_label, 0.0, 1.0, 1.0, 1.0, 0, -32, 0, -10)
	_hint_label.modulate.a = 0.5
	_hint_label.text = "WASD  ·  SHIFT dash  ·  CLICK on the beat  ·  1/2 weapon  ·  LOOK DOWN + rocket to launch  ·  F fix timing  ·  C calibrate  ·  T tutorial  ·  P practice  ·  R restart  ·  F11 window"

	# --- finish tally, hidden until the run ends ---
	# Sized explicitly and laid out by hand rather than with a VBoxContainer:
	# a container re-positions its children every layout pass, which fights
	# the slide-in tweens for ownership of the same property.
	_tally_panel = ColorRect.new()
	_tally_panel.color = Color(0.03, 0.02, 0.06, 0.86)
	_tally_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tally_panel.visible = false
	root.add_child(_tally_panel)
	_anchor(_tally_panel, 0.5, 0.5, 0.5, 0.5,
		-TALLY_W * 0.5, -TALLY_H * 0.5, TALLY_W * 0.5, TALLY_H * 0.5)

	_tally_root = Control.new()
	_tally_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tally_panel.add_child(_tally_root)
	_tally_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	Score.changed.connect(_on_score_changed)
	Score.graded.connect(_on_graded)
	Score.energy_changed.connect(set_energy)
	_on_score_changed(0, 0, 1)
	set_energy(Score.energy)


func bind_player(player: Node) -> void:
	var gun = player.get("gun")
	if gun and gun.has_signal("weapon_changed"):
		gun.weapon_changed.connect(_on_weapon_changed)
		gun.charges_changed.connect(set_charges)
		_on_weapon_changed(gun.weapon_index, gun.current_gun)
		set_charges(gun.charge(), gun.current_gun.charges)


func show_banner(title: String, sub: String = "") -> void:
	_banner_label.text = title
	_banner_sub.text = sub
	_banner_fade = 1.0


func set_status(text: String) -> void:
	# Frame rate, but only once it is low enough to matter. A shot is stamped
	# when its input event is processed, so a sagging frame rate is a TIMING
	# problem and not merely an ugly one -- worth seeing before concluding the
	# grading has drifted.
	var fps := Engine.get_frames_per_second()
	if fps < 90.0:
		text += "    %d fps" % int(fps)
	_status_label.text = text


func set_danger(amount: float) -> void:
	_danger_amount = clampf(amount, 0.0, 1.0)


func set_energy(energy: float) -> void:
	var ratio := clampf(energy, 0.0, 1.0)
	_energy_fill.offset_right = _energy_fill.offset_left + BAR_WIDTH * ratio
	# Beat Saber turns the bar red as it empties; the colour IS the warning,
	# since you have no time to read a number mid-run.
	if ratio < 0.25:
		_energy_fill.color = Color(1.0, 0.22, 0.26)
	elif ratio < 0.5:
		_energy_fill.color = Color(1.0, 0.68, 0.25)
	else:
		_energy_fill.color = Color(0.35, 1.0, 0.60)
	# Saying the comeback bonus is live turns a hidden kindness into a readable
	# instruction: you are low, so keep connecting and the bar will come back.
	var tail := ""
	if ratio > 0.0 and Score.deficit() > 0.05:
		tail = "   RECOVERY x%.1f" % (1.0 + Score.deficit() * (Score.COMEBACK_BOOST - 1.0))
	_energy_label.text = "ENERGY %.0f%%%s" % [ratio * 100.0, tail]


func set_charges(amount: float, maximum: int) -> void:
	if maximum <= 0:
		_charge_back.visible = false
		_charge_fill.visible = false
		return
	_charge_back.visible = true
	_charge_fill.visible = true
	var ratio := clampf(amount / float(maximum), 0.0, 1.0)
	_charge_fill.offset_right = _charge_fill.offset_left + CHARGE_WIDTH * ratio
	# Dim until at least one whole charge is banked, so a half-full bar never
	# reads as "ready".
	_charge_fill.color = Color(1.0, 0.62, 0.26) if amount >= 1.0 else Color(0.55, 0.35, 0.18)


## rows is an array of [label, value] string pairs. Score and rank are passed
## apart from them so each gets a moment of its own.
##
## Everything staggers on HALF BEATS, so the results assemble in time with the
## outro that is still playing. A results screen that ignored the track it is
## summarising would be a strange thing in this game.
func show_tally(rows: Array, final_score: int, rank: String = "",
		rank_colour: Color = Color.WHITE) -> void:
	for c in _tally_root.get_children():
		c.queue_free()

	_tally_panel.visible = true
	_tally_panel.pivot_offset = Vector2(TALLY_W * 0.5, TALLY_H * 0.5)
	_tally_panel.modulate.a = 0.0
	_tally_panel.scale = Vector2(0.9, 0.9)
	var pt := _tally_panel.create_tween()
	pt.tween_property(_tally_panel, "modulate:a", 1.0, 0.16)
	var ps := pt.parallel().tween_property(_tally_panel, "scale", Vector2.ONE, 0.36)
	ps.set_trans(Tween.TRANS_BACK)
	ps.set_ease(Tween.EASE_OUT)

	var step: float = (Conductor.sec_per_beat * 0.5) if Conductor.running else 0.22

	var title := _make_label(_tally_root, 38, HORIZONTAL_ALIGNMENT_CENTER)
	title.text = "RUN COMPLETE"
	_anchor(title, 0.0, 0.0, 1.0, 0.0, 40, 26, -40, 80)
	_slide_in(title, 0.06, -34.0)

	for i in rows.size():
		var row: Array = rows[i]
		var y := 104.0 + float(i) * 34.0
		var lab := _make_label(_tally_root, 19, HORIZONTAL_ALIGNMENT_LEFT)
		lab.text = str(row[0])
		_anchor(lab, 0.0, 0.0, 1.0, 0.0, 48, y, -48, y + 30)
		var val := _make_label(_tally_root, 19, HORIZONTAL_ALIGNMENT_RIGHT)
		val.text = str(row[1])
		_anchor(val, 0.0, 0.0, 1.0, 0.0, 48, y, -48, y + 30)
		# Label from the left, value from the right, so each row closes inward.
		_slide_in(lab, 0.16 + step * float(i), -56.0)
		_slide_in(val, 0.20 + step * float(i), 56.0)

	var tail := 104.0 + float(rows.size()) * 34.0
	var n := float(rows.size())

	# Score on the left, rank on the right, sharing the bottom band.
	var cap := _make_label(_tally_root, 15, HORIZONTAL_ALIGNMENT_LEFT)
	cap.text = "SCORE"
	_anchor(cap, 0.0, 0.0, 0.58, 0.0, 48, tail + 16, 0, tail + 38)
	_slide_in(cap, 0.18 + step * n, -40.0)

	_tally_score = _make_label(_tally_root, 50, HORIZONTAL_ALIGNMENT_LEFT)
	_tally_score.text = "0"
	_tally_score.modulate.a = 0.0
	_anchor(_tally_score, 0.0, 0.0, 0.58, 0.0, 48, tail + 36, 0, tail + 100)
	var st := _tally_score.create_tween()
	st.tween_interval(0.22 + step * n)
	st.tween_property(_tally_score, "modulate:a", 1.0, 0.12)
	var counter := st.parallel().tween_method(
		_set_tally_score, 0.0, float(final_score), step * 4.0)
	counter.set_trans(Tween.TRANS_CUBIC)
	counter.set_ease(Tween.EASE_OUT)

	if rank != "":
		var rk := _make_label(_tally_root, 82, HORIZONTAL_ALIGNMENT_RIGHT)
		rk.text = rank
		rk.add_theme_color_override("font_color", rank_colour)
		_anchor(rk, 0.58, 0.0, 1.0, 0.0, 0, tail + 8, -48, tail + 106)
		# Lands last and hits hardest -- it is the only number that summarises
		# the whole run in one glyph.
		_pop_in(rk, 0.34 + step * (n + 4.0), 1.9, Vector2(130.0, 49.0))

	var foot := _make_label(_tally_root, 15, HORIZONTAL_ALIGNMENT_CENTER)
	foot.text = "R to run it again"
	_anchor(foot, 0.0, 1.0, 1.0, 1.0, 40, -34, -40, -10)
	_slide_in(foot, 0.42 + step * (n + 5.0), 0.0)


## Punches a control in from oversized, for the one element that should feel
## like an announcement rather than a line of a table.
func _pop_in(c: Control, delay: float, from_scale: float, pivot: Vector2) -> void:
	c.modulate.a = 0.0
	c.pivot_offset = pivot
	c.scale = Vector2(from_scale, from_scale)
	var tw := c.create_tween()
	tw.tween_interval(maxf(delay, 0.0))
	var sc := tw.tween_property(c, "scale", Vector2.ONE, 0.45)
	sc.set_trans(Tween.TRANS_BACK)
	sc.set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(c, "modulate:a", 1.0, 0.22)


## Slides a control in from `dx` pixels away while fading up. Both offsets move
## together, so it works whether the label is left- or right-aligned.
func _slide_in(c: Control, delay: float, dx: float) -> void:
	var ol := c.offset_left
	var orr := c.offset_right
	c.modulate.a = 0.0
	c.offset_left = ol + dx
	c.offset_right = orr + dx
	var tw := c.create_tween()
	tw.tween_interval(maxf(delay, 0.0))
	var a := tw.tween_property(c, "offset_left", ol, 0.34)
	a.set_trans(Tween.TRANS_CUBIC)
	a.set_ease(Tween.EASE_OUT)
	var b := tw.parallel().tween_property(c, "offset_right", orr, 0.34)
	b.set_trans(Tween.TRANS_CUBIC)
	b.set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(c, "modulate:a", 1.0, 0.26)


func _set_tally_score(v: float) -> void:
	if is_instance_valid(_tally_score):
		_tally_score.text = "%d" % roundi(v)


func _bar(parent: Control, colour: Color, top: float, bottom: float,
		width: float) -> ColorRect:
	var r := ColorRect.new()
	r.color = colour
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	_anchor(r, 0.0, 1.0, 0.0, 1.0, 24, top, 24 + width, bottom)
	return r


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

	var pop := 1.0 + pow(_grade_fade, 6.0) * 0.35
	_grade_label.scale = Vector2(pop, pop)
	_grade_label.pivot_offset = _grade_label.size * 0.5
	_grade_label.modulate = Color(
		_grade_colour.r, _grade_colour.g, _grade_colour.b, _grade_fade)
	_ms_label.modulate.a = _ms_fade * 0.9

	var ba := minf(_banner_fade * 3.0, 1.0)
	_banner_label.modulate.a = ba
	_banner_sub.modulate.a = ba * 0.8

	# Pulse the danger tint on the beat so a closing wall feels like the music
	# is closing in, which it literally is.
	var beat := pow(1.0 - Conductor.beat_phase(), 3.0) if Conductor.running else 0.0
	_danger.color.a = _danger_amount * (0.10 + beat * 0.14)

	_practice_label.text = "PRACTICE" if Score.practice else ""

	# Live timing bias. Amber once it is past the PERFECT window, red once it
	# is past GREAT: at that point no amount of good rhythm can produce the top
	# grade, and the player should be told it is the offset and not them.
	if Score.err_count < Score.BIAS_MIN_SHOTS:
		_bias_label.text = ""
	else:
		var bias := Score.mean_error() * 1000.0
		var mag := absf(bias)
		if mag < 10.0:
			_bias_label.text = "timing %+.0f ms" % bias
			_bias_label.modulate = Color(0.6, 1.0, 0.78, 0.4)
		else:
			_bias_label.text = "timing %+.0f ms %s   ·   F to correct" % [
				bias, "late" if bias > 0.0 else "early"]
			_bias_label.modulate = Color(1.0, 0.45, 0.45, 1.0) if mag > 62.0 \
				else Color(1.0, 0.76, 0.32, 0.85)
