## The root of a level scene, and the keeper of its pacing contract.
##
## The contract, in one line: the pursuit wall leaves wall_back metres behind
## the START marker and arrives at the FINISH marker exactly as the song ends.
##
## Which means the wall's SPEED is derived, not chosen -- it is however fast it
## has to go to make that true. Move the finish further away and the wall
## speeds up; pull it closer and the wall slows down. "The song ends when the
## pink thing gets to the end" is therefore not something that needs tuning,
## it is true by construction for any level you build.
##
## The one number that can go wrong is the ratio of that derived speed to the
## player's top speed. Below about 0.55 the wall cannot catch anybody; above
## about 0.95 the level is longer than the song can carry. The report in the
## inspector -- and the readout floating over the start line -- tells you where
## you are, live, as you drag the finish marker around.
@tool
class_name LevelRoot
extends Node3D

## How far BEHIND the start marker the wall begins. Pure grace period: it still
## has to reach the finish on time, so this costs nothing but the first second.
const DEFAULT_WALL_BACK := 34.0

## Lane lights beyond this are switched off. They are saved nodes in the level
## like everything else; this only decides which of them are lit right now.
const LIGHT_RANGE := 72.0

const STRIP_MATERIAL := "res://blocks/materials/lane_strip.tres"

## A level is found by group, not by class: groups are saved in the .tscn, so
## any node at all can be the start or the finish and nothing has to carry a
## script to say so.
const GROUP_START := "level_start"
const GROUP_FINISH := "level_finish"
const GROUP_LIGHT := "lane_light"

@export var song: SongResource:
	set(v):
		song = v
		_dirty = true

## Kept in step with player.gd SPEED by hand. Only used to judge whether the
## derived wall speed is reasonable, never to drive anything.
@export var player_top_speed := 14.0:
	set(v):
		player_top_speed = maxf(v, 1.0)
		_dirty = true

@export var wall_back := DEFAULT_WALL_BACK:
	set(v):
		wall_back = v
		_dirty = true

## How many seconds of the track this level uses. 0 means all of it.
##
## The other half of the contract. The wall still arrives at the FINISH exactly
## as this runs out, so a level that wants the first forty seconds of a song is
## a forty-second run -- and the music washes out at the line instead of playing
## on into nothing. Shortening a level is therefore one number, not a re-chart.
@export var level_seconds := 0.0:
	set(v):
		level_seconds = maxf(v, 0.0)
		_dirty = true

@export_group("Design aids")
## The live readout floating above the start line. Editor only.
@export var show_report := true:
	set(v):
		show_report = v
		_dirty = true

## Numbered posts down the lane showing where each beat of the song lands in
## space. The single most useful thing for placing anything on a beat.
@export var show_beat_ruler := false:
	set(v):
		show_beat_ruler = v
		_dirty = true

@export_range(1, 64, 1) var ruler_every_beats := 8:
	set(v):
		ruler_every_beats = maxi(v, 1)
		_dirty = true

var _lights: Array[OmniLight3D] = []
var _strip_mat: StandardMaterial3D
var _ruler: Array[Node] = []
var _report_label: Label3D
var _player: Node3D
var _dirty := true
var _tick := 0.0
var _light_tick := 0.0


func _ready() -> void:
	if Engine.is_editor_hint():
		_dirty = true
		return
	# The lights are placed in the scene. All this does is collect them so the
	# distant ones can be switched off.
	for n in _collect(GROUP_LIGHT):
		if n is OmniLight3D:
			_lights.append(n as OmniLight3D)
	if ResourceLoader.exists(STRIP_MATERIAL):
		_strip_mat = load(STRIP_MATERIAL) as StandardMaterial3D


func bind(player: Node3D) -> void:
	_player = player


# ------------------------------------------------------------ the contract ---

func start_z() -> float:
	var m := _marker(GROUP_START)
	return m.global_position.z if m else 0.0


## Where the player is put at the top of the run.
func start_position() -> Vector3:
	var m := _marker(GROUP_START)
	return m.global_position if m else Vector3.ZERO


func finish_z() -> float:
	var m := _marker(GROUP_FINISH)
	return m.global_position.z if m else -100.0


func wall_start_z() -> float:
	return start_z() + wall_back


## Metres the wall has to cover. Always positive; forward is -Z.
func length() -> float:
	return maxf(wall_start_z() - finish_z(), 1.0)


## The run's length in seconds -- the slice of the track this level uses.
func song_seconds() -> float:
	if level_seconds > 0.0:
		return minf(level_seconds, track_seconds())
	return track_seconds()


## The whole track, however much of it the level takes.
func track_seconds() -> float:
	if song and song.stream:
		return maxf(song.stream.get_length(), 1.0)
	return 60.0


func sec_per_beat() -> float:
	return (60.0 / song.bpm) if song and song.bpm > 0.0 else 0.5


## Playable beats in the track, after its lead-in.
func total_beats() -> float:
	var off: float = song.first_beat_offset if song else 0.0
	return (song_seconds() - off) / sec_per_beat()


## Derived. The whole point of this file.
func wall_speed() -> float:
	return length() / song_seconds()


## Fraction of the player's flat-out speed the wall travels at. THE difficulty
## number: everything else about pacing follows from it.
func wall_fraction() -> float:
	return wall_speed() / player_top_speed


## Where the wall is, given how far through the song we are.
func wall_z(at_seconds: float) -> float:
	var t := clampf(at_seconds / song_seconds(), 0.0, 1.0)
	return lerpf(wall_start_z(), finish_z(), t)


## When the wall arrives at a given Z. This is a deadline for every part of the
## level, which is what makes it possible to design against.
func seconds_at_z(z: float) -> float:
	return (wall_start_z() - z) / wall_speed()


func beat_at_z(z: float) -> float:
	var off: float = song.first_beat_offset if song else 0.0
	return (seconds_at_z(z) - off) / sec_per_beat()


func z_at_beat(b: float) -> float:
	var off: float = song.first_beat_offset if song else 0.0
	return wall_start_z() - (off + b * sec_per_beat()) * wall_speed()


## How long the level takes flat out, ignoring every jump, climb and fight.
func sprint_seconds() -> float:
	return length() / player_top_speed


## The entire budget for mistakes, climbs and standing still. If this is
## negative the level cannot be finished by anyone.
func slack_seconds() -> float:
	return song_seconds() - sprint_seconds()


func verdict() -> String:
	var f := wall_fraction()
	if f > 0.99:
		return "IMPOSSIBLE - longer than the song"
	if f > 0.95:
		return "brutal - one mistake ends the run"
	if f > 0.86:
		return "tough but fair"
	if f > 0.72:
		return "firm"
	if f > 0.55:
		return "gentle"
	return "the wall cannot catch anyone"


func report() -> String:
	var title: String = song.title if song else "no song set"
	var bpm: float = song.bpm if song else 0.0
	var slice := ""
	if level_seconds > 0.0:
		slice = "   (first %.0fs of %.0fs)" % [song_seconds(), track_seconds()]
	var lines := [
		"%s   %.1fs   %.0f BPM   %.0f beats%s" % [
			title, song_seconds(), bpm, total_beats(), slice],
		"level     %.0f m    start %+.0f  to  finish %.0f" % [
			length(), wall_start_z(), finish_z()],
		"wall      %.2f m/s   =  %.0f%% of top speed" % [
			wall_speed(), wall_fraction() * 100.0],
		"sprint    %.1fs flat out    slack %+.1fs" % [
			sprint_seconds(), slack_seconds()],
		"verdict   %s" % verdict(),
	]
	return "\n".join(lines)


# ----------------------------------------------------------------- editor ---

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		_tick += delta
		if _tick < 0.2:
			return
		_tick = 0.0
		_editor_refresh()
		return

	if Conductor.running:
		var pulse := pow(1.0 - Conductor.beat_phase(), 3.0)
		if _strip_mat:
			_strip_mat.emission_energy_multiplier = 0.5 + pulse * 5.0
		for l in _lights:
			if l.visible:
				l.light_energy = 1.4 + pulse * 4.0

	_light_tick += delta
	if _light_tick > 0.2 and _player:
		_light_tick = 0.0
		var pz := _player.global_position.z
		for l in _lights:
			l.visible = absf(l.position.z - pz) < LIGHT_RANGE


## Polled rather than signalled: dragging the FINISH marker changes the whole
## contract and nothing tells this node about it, so it just looks.
func _editor_refresh() -> void:
	var text := report() if show_report else ""
	if _report_label == null and show_report:
		_report_label = Label3D.new()
		_report_label.font_size = 28
		_report_label.outline_size = 8
		_report_label.modulate = Color(0.55, 0.95, 1.0)
		_report_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_report_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		add_child(_report_label, false, Node.INTERNAL_MODE_BACK)
	if _report_label:
		_report_label.visible = show_report
		if _report_label.text != text:
			_report_label.text = text
			notify_property_list_changed()
		_report_label.position = Vector3(-7.0, 12.0, start_z() + 6.0)

	if _dirty:
		_dirty = false
		_rebuild_ruler()


func _rebuild_ruler() -> void:
	for n in _ruler:
		if is_instance_valid(n):
			n.free()
	_ruler.clear()
	if not show_beat_ruler or song == null:
		return

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.3, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var post := BoxMesh.new()
	post.size = Vector3(0.12, 4.0, 0.12)

	var beats := int(total_beats())
	var b := 0
	while b <= beats:
		var z := z_at_beat(float(b))
		if z > wall_start_z():
			b += ruler_every_beats
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = post
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi, false, Node.INTERNAL_MODE_BACK)
		mi.position = Vector3(-8.8, 2.0, z)
		_ruler.append(mi)

		var l := Label3D.new()
		l.text = "b%d  %.1fs" % [b, seconds_at_z(z)]
		l.font_size = 24
		l.outline_size = 6
		l.modulate = Color(1.0, 0.85, 0.3)
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(l, false, Node.INTERNAL_MODE_BACK)
		l.position = Vector3(-8.8, 4.6, z)
		_ruler.append(l)
		b += ruler_every_beats


# ----------------------------------------------------------------- lookup ---

## First node of the level in a given group. Walks the level's own subtree
## rather than asking the SceneTree, so it answers in the editor too -- where
## the level is open but not running and groups are not registered.
func _marker(group: String) -> Node3D:
	var found := _collect(group, true)
	return found[0] as Node3D if not found.is_empty() else null


func _collect(group: String, first_only: bool = false) -> Array[Node]:
	var out: Array[Node] = []
	_walk(self, group, out, first_only)
	return out


func _walk(n: Node, group: String, out: Array[Node], first_only: bool) -> void:
	for c in n.get_children():
		if c.is_in_group(group):
			out.append(c)
			if first_only:
				return
		_walk(c, group, out, first_only)
		if first_only and not out.is_empty():
			return


# The read-only report box in the inspector. The floating label in the
# viewport is the live one; this refreshes whenever that label's text changes.
func _get_property_list() -> Array:
	return [{
		"name": "report",
		"type": TYPE_STRING,
		"usage": PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY,
		"hint": PROPERTY_HINT_MULTILINE_TEXT,
	}]


func _get(property: StringName) -> Variant:
	if property == &"report":
		return report()
	return null
