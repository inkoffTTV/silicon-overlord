extends Node3D
## Another player's avatar: "Telly" — a chunky worker with an old CRT monitor for a head (glowing face), a hard hat
## and work shirt in the player's colour, rabbit-ear antenna, name tag. Original design (see docs/VISUAL_STYLE.md).
## Root sits at the player's feet (CharacterBody3D origin). Fed by world.gd from Bus.peers_changed:
##   apply_state({userId, name, color, p:[x,y,z], yaw, pitch, anim})
## anim: idle | walk | run | crouch | carry | air | sit | climb (others fall back to the velocity).
## talk(seconds, text) — jaw/screen-mouth animation + speech bubble (spoken chat).

const Rig := preload("res://world/actors/worker_rig.gd")
const Bubble := preload("res://world/actors/speech_bubble.gd")

var target_pos := Vector3.ZERO
var target_yaw := 0.0
var target_pitch := 0.0
var anim := "idle"
var color := Color(0.3, 0.6, 1.0)
var display_name := ""

var rig: Node3D
var name_label: Label3D
var bubble: Node3D

var _has_state := false
var _yaw := 0.0
var _pitch := 0.0
var _speed := 0.0
var _dirty_colour := false

func _ready() -> void:
	rig = Rig.new()
	rig.name = "Rig"
	rig.head_style = "crt"
	rig.shirt = color
	rig.hat_color = color
	rig.pants = Color(0.17, 0.2, 0.27)
	add_child(rig)
	name_label = Label3D.new()
	name_label.name = "NameTag"
	name_label.position = Vector3(0, 2.02, 0)
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.font_size = 44
	name_label.pixel_size = 0.0036
	name_label.outline_size = 14
	name_label.outline_modulate = Color(0, 0, 0, 0.85)
	name_label.text = display_name
	name_label.modulate = color.lightened(0.55)
	if ResourceLoader.exists("res://ui/fonts/Inter-Bold.ttf"):
		name_label.font = load("res://ui/fonts/Inter-Bold.ttf")
	add_child(name_label)
	bubble = Bubble.new()
	bubble.name = "Bubble"
	bubble.position = Vector3(0, 2.18, 0)
	add_child(bubble)

static func parse_color(c: Variant) -> Color:
	if c is Color:
		return c
	if c is String:
		var s: String = c
		if s.is_valid_html_color():
			return Color.html(s)
		return Color.from_string(s, Color(0.3, 0.6, 1.0))
	if c is Array and c.size() >= 3:
		var r := float(c[0])
		var g := float(c[1])
		var b := float(c[2])
		if r > 1.0 or g > 1.0 or b > 1.0:
			return Color8(int(r), int(g), int(b))
		return Color(r, g, b)
	return Color(0.3, 0.6, 1.0)

func apply_state(e: Dictionary) -> void:
	var p: Variant = e.get("p", null)
	if p is Array and p.size() >= 3:
		target_pos = Vector3(float(p[0]), float(p[1]), float(p[2]))
	target_yaw = float(e.get("yaw", target_yaw))
	target_pitch = float(e.get("pitch", target_pitch))
	anim = str(e.get("anim", anim))
	var new_name := str(e.get("name", display_name))
	if new_name != display_name:
		display_name = new_name
		if name_label:
			name_label.text = display_name
	var c := parse_color(e.get("color", color))
	if not c.is_equal_approx(color):
		color = c
		_dirty_colour = true
	if not _has_state:
		_has_state = true
		global_position = target_pos
		_yaw = target_yaw
		_pitch = target_pitch

## Spoken chat: mouth anim for `seconds` + a speech bubble with `text` ("" = mouth only).
func talk(seconds: float, text: String = "") -> void:
	if rig:
		rig.talk(seconds)
	if bubble and text != "":
		bubble.say(text, seconds + 1.5)

func _apply_color() -> void:
	_dirty_colour = false
	rig.shirt = color
	rig.hat_color = color
	rig.build()
	if name_label:
		name_label.modulate = color.lightened(0.55)

func _process(delta: float) -> void:
	if _dirty_colour and rig:
		_apply_color()
	if not _has_state:
		return
	var prev := global_position
	var k := 1.0 - exp(-12.0 * delta)
	var gp := global_position.lerp(target_pos, k)
	if gp.distance_to(target_pos) > 6.0:
		gp = target_pos
	global_position = gp
	_yaw = lerp_angle(_yaw, target_yaw, k)
	_pitch = lerpf(_pitch, target_pitch, k)
	rotation.y = _yaw + PI  # model faces +Z, player yaw 0 faces -Z
	var horiz: float = Vector2(gp.x - prev.x, gp.z - prev.z).length() / maxf(delta, 0.0001)
	_speed = lerpf(_speed, horiz, 1.0 - exp(-8.0 * delta))
	rig.move_speed = _speed
	var pose := anim
	if pose not in ["idle", "walk", "run", "crouch", "carry", "air", "sit", "sit_type", "climb"]:
		pose = "walk" if _speed > 0.4 else "idle"
	if pose == "idle" and _speed > 0.4:
		pose = "walk"
	rig.pose = pose
	rig.look_pitch = _pitch if pose != "sit_type" else 0.0
