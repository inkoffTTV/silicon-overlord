extends Node3D
## Another player's avatar: "Telly" — a chunky little worker with an old CRT monitor for a head,
## rabbit-ear antenna and a hoodie tinted with the player's color. Original design.
## Root sits at the player's feet (CharacterBody3D origin). Fed by world.gd from Bus.peers_changed:
##   apply_state({userId, name, color, p:[x,y,z], yaw, pitch, anim})

const Mats := preload("res://world/lib/mats.gd")
const Meshes := preload("res://world/lib/meshes.gd")

var target_pos := Vector3.ZERO
var target_yaw := 0.0
var target_pitch := 0.0
var anim := "idle"
var color := Color(0.3, 0.6, 1.0)
var display_name := ""

var _has_state := false
var _yaw := 0.0
var _pitch := 0.0
var _phase := 0.0
var _speed := 0.0
var _blink := 0.0
var _crouch := 0.0

var body: Node3D
var torso: MeshInstance3D
var head: Node3D
var leg_l: Node3D
var leg_r: Node3D
var arm_l: Node3D
var arm_r: Node3D
var eyes: Array[MeshInstance3D] = []
var name_label: Label3D
var hoodie_mat: ShaderMaterial
var face_mat: StandardMaterial3D

func _ready() -> void:
	_build()
	_apply_color()

func _build() -> void:
	hoodie_mat = (Mats.m("fabric", Color.WHITE, {"albedo": color}) as ShaderMaterial).duplicate()
	var pants := Mats.m("fabric_blue", Color(0.5, 0.5, 0.5))
	var shell := Mats.m("plastic_beige")
	body = Node3D.new()
	body.name = "Body"
	add_child(body)
	# legs (pivot at hip)
	leg_l = _limb(body, Vector3(-0.12, 0.5, 0), Vector3(0.15, 0.42, 0.17), pants, Vector3(0.17, 0.09, 0.26), Mats.m("rubber", Color(4, 4, 4)))
	leg_r = _limb(body, Vector3(0.12, 0.5, 0), Vector3(0.15, 0.42, 0.17), pants, Vector3(0.17, 0.09, 0.26), Mats.m("rubber", Color(4, 4, 4)))
	# torso (hoodie)
	torso = _box(body, Vector3(0.5, 0.52, 0.32), Vector3(0, 0.78, 0), hoodie_mat, 0.1)
	_box(body, Vector3(0.3, 0.12, 0.02), Vector3(0, 0.66, 0.16), hoodie_mat, 0.03).scale = Vector3(1, 1, 1)
	_box(body, Vector3(0.36, 0.1, 0.24), Vector3(0, 1.06, -0.02), hoodie_mat, 0.05)  # hood roll
	# arms (pivot at shoulder) with mitten hands
	arm_l = _limb(body, Vector3(-0.31, 0.98, 0), Vector3(0.13, 0.4, 0.14), hoodie_mat, Vector3(0.14, 0.13, 0.14), shell)
	arm_r = _limb(body, Vector3(0.31, 0.98, 0), Vector3(0.13, 0.4, 0.14), hoodie_mat, Vector3(0.14, 0.13, 0.14), shell)
	# CRT head (pivot at neck)
	head = Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 1.12, 0)
	body.add_child(head)
	_box(head, Vector3(0.12, 0.06, 0.12), Vector3(0, 0.02, 0), Mats.m("plastic_grey"), 0.02)
	_box(head, Vector3(0.46, 0.38, 0.36), Vector3(0, 0.24, 0.02), shell, 0.06)
	_box(head, Vector3(0.32, 0.26, 0.16), Vector3(0, 0.23, -0.2), shell, 0.06)
	_box(head, Vector3(0.38, 0.29, 0.02), Vector3(0, 0.245, 0.195), Mats.m("plastic_black", Color(2, 2, 2)), 0.015)
	face_mat = StandardMaterial3D.new()
	face_mat.albedo_color = Color(0.02, 0.03, 0.05)
	face_mat.emission_enabled = true
	face_mat.emission = Color(0.05, 0.1, 0.15)
	face_mat.emission_energy_multiplier = 1.0
	var scr := MeshInstance3D.new()
	scr.mesh = Meshes.quad(Vector2(0.34, 0.25))
	scr.material_override = face_mat
	scr.position = Vector3(0, 0.245, 0.207)
	head.add_child(scr)
	for s in [-1.0, 1.0]:
		var e := _box(head, Vector3(0.05, 0.08, 0.004), Vector3(s * 0.075, 0.27, 0.209), Mats.glow(Color.WHITE, 4.0), 0.0)
		e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		eyes.append(e)
	var mouth := _box(head, Vector3(0.09, 0.018, 0.004), Vector3(0, 0.19, 0.209), Mats.glow(Color.WHITE, 3.0), 0.0)
	mouth.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	eyes.append(mouth)
	# rabbit-ear antenna
	for s in [-1.0, 1.0]:
		var rod := _box(head, Vector3(0.012, 0.3, 0.012), Vector3(s * 0.07, 0.56, -0.05), Mats.m("metal"), 0.0)
		rod.rotation_degrees = Vector3(0, 0, -s * 22.0)
		var tip := MeshInstance3D.new()
		tip.mesh = Meshes.sphere(0.022, 8)
		tip.position = Vector3(s * 0.13, 0.7, -0.05)
		tip.material_override = Mats.m("metal")
		head.add_child(tip)
	_box(head, Vector3(0.1, 0.03, 0.06), Vector3(0, 0.44, -0.05), Mats.m("plastic_black"), 0.01)
	# name tag
	name_label = Label3D.new()
	name_label.position = Vector3(0, 2.0, 0)
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.font_size = 48
	name_label.pixel_size = 0.004
	name_label.outline_size = 12
	name_label.outline_modulate = Color(0, 0, 0, 0.8)
	name_label.no_depth_test = false
	name_label.fixed_size = false
	if ResourceLoader.exists("res://ui/fonts/Inter-Bold.ttf"):
		name_label.font = load("res://ui/fonts/Inter-Bold.ttf")
	add_child(name_label)

func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, bevel: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = Meshes.cbox(size, bevel)
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi

## A limb pivoting at `pivot`, hanging down, with an end piece (foot / mitten).
func _limb(parent: Node3D, pivot: Vector3, size: Vector3, mat: Material, end_size: Vector3, end_mat: Material) -> Node3D:
	var p := Node3D.new()
	p.position = pivot
	parent.add_child(p)
	_box(p, size, Vector3(0, -size.y * 0.5, 0), mat, min(size.x, size.z) * 0.45)
	var end_off := Vector3(0, -size.y - end_size.y * 0.3, end_size.z * 0.25 if end_size.z > end_size.x * 1.3 else 0.0)
	_box(p, end_size, end_off, end_mat, min(end_size.x, end_size.y) * 0.4)
	return p

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
		_apply_color()
	if not _has_state:
		_has_state = true
		global_position = target_pos
		_yaw = target_yaw
		_pitch = target_pitch

func _apply_color() -> void:
	if hoodie_mat:
		hoodie_mat.set_shader_parameter("albedo", color)
		hoodie_mat.set_shader_parameter("albedo2", color.darkened(0.3))
	if face_mat:
		face_mat.emission = color.darkened(0.6)
	for e in eyes:
		e.material_override = Mats.glow(color.lightened(0.5), 5.0)
	if name_label:
		name_label.modulate = color.lightened(0.55)

func _process(delta: float) -> void:
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
	head.rotation.x = clampf(_pitch, -0.9, 0.9) * 0.6
	var horiz: float = Vector2(gp.x - prev.x, gp.z - prev.z).length() / maxf(delta, 0.0001)
	_speed = lerpf(_speed, horiz, 1.0 - exp(-8.0 * delta))
	var moving := clampf(_speed / 3.0, 0.0, 1.6)
	if anim in ["walk", "run"] and moving < 0.15:
		moving = 0.5 if anim == "walk" else 1.0
	_phase += delta * (6.0 + _speed * 2.2) * (1.0 if moving > 0.05 else 0.0)
	var swing := sin(_phase) * 0.6 * minf(moving, 1.2)
	leg_l.rotation.x = swing
	leg_r.rotation.x = -swing
	arm_l.rotation.x = -swing * 0.8
	arm_r.rotation.x = swing * 0.8
	if anim == "carry":
		arm_l.rotation.x = -1.3
		arm_r.rotation.x = -1.3
	arm_l.rotation.z = -0.12
	arm_r.rotation.z = 0.12
	_crouch = lerpf(_crouch, 1.0 if anim == "crouch" else 0.0, 1.0 - exp(-10.0 * delta))
	body.position.y = absf(cos(_phase)) * 0.05 * minf(moving, 1.0) - _crouch * 0.3
	body.rotation.x = _crouch * 0.25 + minf(moving, 1.0) * 0.06
	leg_l.scale.y = 1.0 - _crouch * 0.4
	leg_r.scale.y = 1.0 - _crouch * 0.4
	torso.rotation.z = sin(_phase * 0.5) * 0.04 * moving
	# idle sway + blinking face
	head.rotation.z = sin(Time.get_ticks_msec() * 0.0015) * 0.04
	_blink -= delta
	var eye_scale := 1.0
	if _blink < 0.0:
		eye_scale = 0.1
		if _blink < -0.12:
			_blink = randf_range(2.0, 5.0)
	for i in 2:
		eyes[i].scale.y = eye_scale
