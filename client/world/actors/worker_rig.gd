extends Node3D
## Chunky procedural worker rig (WORLD agent) shared by player avatars and NPC employees. Original design.
## Feet at the origin, faces +Z. Two-segment arms and legs so it can sit, type, scribble, carry and climb.
##   head_style "crt"  — players: "Telly", an old CRT monitor head with a glowing face, a hard hat in the player's
##                       colour with a little headlamp, rabbit-ear antenna. Mouth on the screen opens when talking.
##   head_style "bean" — NPC staff: round putty head, googly eyes, hair or cap, a mouth that opens when talking.
## Drive it with: pose (String), move_speed (m/s), talk(seconds). Poses: idle walk run crouch carry air climb
## sit sit_type sit_idle stand_scribble stand_think stand_assemble.

const Mats := preload("res://world/lib/mats.gd")
const Meshes := preload("res://world/lib/meshes.gd")

var head_style := "crt"
var shirt := Color(0.3, 0.6, 1.0)
var pants := Color(0.16, 0.2, 0.3)
var hat_color: Variant = null       # Color → hard hat
var skin := Color(0.85, 0.66, 0.5)
var hair := Color(0.18, 0.12, 0.08)
var hair_style := 0                 # 0 short, 1 bun, 2 cap, 3 bald
var accessory := ""                 # "vest" | "coat" | "tie" | "headset" | ""
var seat_h := 0.47

var pose := "idle"
var move_speed := 0.0
## extra head pitch (radians, + = look up), e.g. from the network
var look_pitch := 0.0

var pelvis: Node3D
var spine: Node3D
var head: Node3D
var thigh_l: Node3D
var thigh_r: Node3D
var shin_l: Node3D
var shin_r: Node3D
var uarm_l: Node3D
var uarm_r: Node3D
var farm_l: Node3D
var farm_r: Node3D
var mouth: MeshInstance3D
var eyes: Array[MeshInstance3D] = []
var face_mat: StandardMaterial3D

var _phase := 0.0
var _t := 0.0
var _talk := 0.0
var _blink := 2.0
var _cur := {}
var _rng := RandomNumberGenerator.new()
var _seed := 0.0
var _built := false

func _ready() -> void:
	_rng.seed = hash(name) + get_instance_id()
	_seed = _rng.randf() * 100.0
	if not _built:
		build()

## Rebuilds the meshes (call after changing colours / style).
func build() -> void:
	for c in get_children():
		if c.has_meta("rig_part"):
			c.queue_free()
	eyes.clear()
	_built = true
	var shirt_m := Mats.m("fabric", Color.WHITE, {"albedo": shirt, "albedo2": shirt.darkened(0.25)})
	var pants_m := Mats.m("fabric_blue", Color.WHITE, {"albedo": pants, "albedo2": pants.darkened(0.3)})
	var boot_m := Mats.m("rubber", Color(5, 4.2, 3.4))
	var glove_m := Mats.m("rubber", Color(14, 12, 9)) if head_style == "crt" else Mats.m("plastic_beige", Color.WHITE, {"albedo": skin, "albedo2": skin.darkened(0.1), "roughness_base": 0.7})
	pelvis = Node3D.new()
	pelvis.name = "Pelvis"
	pelvis.set_meta("rig_part", true)
	pelvis.position = Vector3(0, 0.52, 0)
	add_child(pelvis)
	_box(pelvis, Vector3(0.46, 0.16, 0.3), Vector3(0, 0.0, 0), pants_m, 0.06)
	# legs: thigh (hip pivot) + shin (knee pivot) + boot
	for s in [-1.0, 1.0]:
		var th := _pivot(pelvis, Vector3(s * 0.12, -0.02, 0))
		_box(th, Vector3(0.17, 0.27, 0.18), Vector3(0, -0.13, 0), pants_m, 0.07)
		var sh := _pivot(th, Vector3(0, -0.26, 0))
		_box(sh, Vector3(0.155, 0.2, 0.165), Vector3(0, -0.1, 0), pants_m, 0.06)
		_box(sh, Vector3(0.19, 0.1, 0.28), Vector3(0, -0.21, 0.04), boot_m, 0.045)
		if s < 0:
			thigh_l = th
			shin_l = sh
		else:
			thigh_r = th
			shin_r = sh
	# torso
	spine = _pivot(pelvis, Vector3(0, 0.05, 0))
	spine.name = "Spine"
	_box(spine, Vector3(0.52, 0.5, 0.33), Vector3(0, 0.26, 0), shirt_m, 0.11)
	_box(spine, Vector3(0.5, 0.06, 0.32), Vector3(0, 0.02, 0), Mats.m("plastic_black", Color(3, 2.6, 2.2)), 0.02)  # belt
	_box(spine, Vector3(0.07, 0.05, 0.02), Vector3(0, 0.02, 0.165), Mats.m("metal"), 0.008)  # buckle
	_box(spine, Vector3(0.13, 0.12, 0.02), Vector3(-0.12, 0.33, 0.165), Mats.m("fabric", Color.WHITE, {"albedo": shirt.darkened(0.2)}), 0.01)  # pocket
	_box(spine, Vector3(0.3, 0.07, 0.26), Vector3(0, 0.5, -0.0), Mats.m("fabric", Color.WHITE, {"albedo": shirt.darkened(0.15)}), 0.03)  # collar
	match accessory:
		"vest":
			var vest := Mats.m("plastic_orange", Color.WHITE, {"albedo": Color(1.0, 0.55, 0.05), "roughness_base": 0.7})
			for s in [-1.0, 1.0]:
				_box(spine, Vector3(0.17, 0.44, 0.35), Vector3(s * 0.15, 0.25, 0), vest, 0.08)
				_box(spine, Vector3(0.175, 0.035, 0.355), Vector3(s * 0.15, 0.18, 0), Mats.glow(Color(0.9, 0.95, 0.8), 0.6), 0.0)
		"coat":
			var coat := Mats.m("fabric", Color.WHITE, {"albedo": Color(0.9, 0.9, 0.88), "albedo2": Color(0.75, 0.75, 0.72)})
			for s in [-1.0, 1.0]:
				_box(spine, Vector3(0.24, 0.72, 0.35), Vector3(s * 0.135, 0.16, 0.0), coat, 0.07)
			_box(spine, Vector3(0.04, 0.12, 0.02), Vector3(0.16, 0.34, 0.18), Mats.m("plastic_white", Color(0.3, 0.4, 1.4)), 0.005)  # pen
		"tie":
			_box(spine, Vector3(0.06, 0.3, 0.02), Vector3(0, 0.3, 0.168), Mats.m("fabric", Color.WHITE, {"albedo": Color(0.6, 0.1, 0.12)}), 0.01)
		"headset":
			pass
	# arms: upper (shoulder pivot) + forearm (elbow pivot) + mitten
	for s in [-1.0, 1.0]:
		var ua := _pivot(spine, Vector3(s * 0.33, 0.45, 0))
		_box(ua, Vector3(0.14, 0.26, 0.15), Vector3(0, -0.11, 0), shirt_m, 0.06)
		var fa := _pivot(ua, Vector3(0, -0.24, 0))
		var sleeve := shirt_m if accessory != "coat" else Mats.m("fabric", Color.WHITE, {"albedo": Color(0.9, 0.9, 0.88)})
		_box(fa, Vector3(0.125, 0.2, 0.135), Vector3(0, -0.09, 0), sleeve, 0.055)
		_box(fa, Vector3(0.15, 0.14, 0.15), Vector3(0, -0.24, 0.01), glove_m, 0.06)
		if s < 0:
			uarm_l = ua
			farm_l = fa
		else:
			uarm_r = ua
			farm_r = fa
	head = _pivot(spine, Vector3(0, 0.55, 0))
	head.name = "Head"
	if head_style == "crt":
		_crt_head()
	else:
		_bean_head()

func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var p := Node3D.new()
	p.position = pos
	parent.add_child(p)
	return p

func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, bevel: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = Meshes.cbox(size, bevel)
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi

func _mesh(parent: Node3D, m: Mesh, pos: Vector3, mat: Material, scale_v: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	mi.scale = scale_v
	parent.add_child(mi)
	return mi

func _crt_head() -> void:
	var shell := Mats.m("plastic_beige")
	_box(head, Vector3(0.13, 0.07, 0.13), Vector3(0, 0.02, 0), Mats.m("plastic_grey"), 0.02)
	_box(head, Vector3(0.48, 0.39, 0.37), Vector3(0, 0.245, 0.02), shell, 0.07)
	_box(head, Vector3(0.33, 0.27, 0.17), Vector3(0, 0.235, -0.21), shell, 0.06)
	_box(head, Vector3(0.4, 0.3, 0.02), Vector3(0, 0.25, 0.2), Mats.m("plastic_black", Color(2, 2, 2)), 0.015)
	face_mat = StandardMaterial3D.new()
	face_mat.albedo_color = Color(0.02, 0.03, 0.05)
	face_mat.emission_enabled = true
	face_mat.emission = shirt.darkened(0.65)
	face_mat.emission_energy_multiplier = 1.0
	_mesh(head, Meshes.quad(Vector2(0.35, 0.26)), Vector3(0, 0.25, 0.2115), face_mat)
	var eye_m := Mats.glow(shirt.lightened(0.6), 5.0)
	for s in [-1.0, 1.0]:
		var e := _box(head, Vector3(0.055, 0.085, 0.004), Vector3(s * 0.078, 0.28, 0.214), eye_m, 0.0)
		e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		eyes.append(e)
	mouth = _box(head, Vector3(0.1, 0.02, 0.004), Vector3(0, 0.19, 0.214), eye_m, 0.0)
	mouth.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# side knobs
	for i in 2:
		_mesh(head, Meshes.cyl(0.018, 0.02, 8), Vector3(0.17, 0.12 + i * 0.045, 0.205), Mats.m("plastic_black"), Vector3.ONE).rotation_degrees.x = 90
	# hard hat in the player's colour + headlamp
	var hc: Color = hat_color if hat_color is Color else shirt
	var hat_m := Mats.m("plastic_white", Color.WHITE, {"albedo": hc, "albedo2": hc.darkened(0.2), "roughness_base": 0.35, "grime": 0.25})
	var hat := _pivot(head, Vector3(0, 0.44, 0.0))
	hat.rotation_degrees = Vector3(-4, 0, 5)
	_mesh(hat, Meshes.sphere(0.235, 16), Vector3(0, 0.0, 0), hat_m, Vector3(1.0, 0.72, 0.95))
	_mesh(hat, Meshes.cyl(0.255, 0.025, 20), Vector3(0, -0.005, 0.03), hat_m, Vector3(1.0, 1.0, 1.1))
	_box(hat, Vector3(0.05, 0.14, 0.36), Vector3(0, 0.12, 0), hat_m, 0.02)  # ridge
	_box(hat, Vector3(0.09, 0.06, 0.04), Vector3(0, 0.06, 0.235), Mats.m("plastic_black"), 0.012)
	var lamp := _mesh(hat, Meshes.cyl(0.022, 0.012, 10), Vector3(0, 0.06, 0.258), Mats.glow(Color(1.0, 0.92, 0.7), 6.0))
	lamp.rotation_degrees.x = 90
	lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# rabbit-ear antenna poking out of the hat
	for s in [-1.0, 1.0]:
		var rod := _box(head, Vector3(0.012, 0.3, 0.012), Vector3(s * 0.12, 0.62, -0.1), Mats.m("metal"), 0.0)
		rod.rotation_degrees = Vector3(-12, 0, -s * 26.0)
		_mesh(head, Meshes.sphere(0.022, 8), Vector3(s * 0.19, 0.76, -0.13), Mats.glow(hc.lightened(0.3), 2.0))

func _bean_head() -> void:
	var skin_m := Mats.m("plastic_beige", Color.WHITE, {"albedo": skin, "albedo2": skin.darkened(0.08), "roughness_base": 0.75, "grime": 0.1})
	_mesh(head, Meshes.cyl(0.07, 0.08, 10), Vector3(0, 0.03, 0), skin_m)
	_mesh(head, Meshes.sphere(0.2, 18), Vector3(0, 0.22, 0.01), skin_m, Vector3(1.0, 1.08, 0.95))
	# ears
	for s in [-1.0, 1.0]:
		_mesh(head, Meshes.sphere(0.045, 8), Vector3(s * 0.195, 0.21, 0.0), skin_m, Vector3(0.6, 1.0, 0.9))
	# googly eyes
	var white := Mats.m("ceramic", Color(1.15, 1.15, 1.15))
	var pupil := Mats.m("plastic_black")
	for s in [-1.0, 1.0]:
		_mesh(head, Meshes.sphere(0.052, 10), Vector3(s * 0.075, 0.25, 0.165), white, Vector3(1.0, 1.15, 0.6))
		var p := _mesh(head, Meshes.sphere(0.026, 8), Vector3(s * 0.07, 0.245, 0.196), pupil, Vector3(1.0, 1.0, 0.5))
		eyes.append(p)
		var brow := _box(head, Vector3(0.07, 0.016, 0.02), Vector3(s * 0.075, 0.325, 0.17), Mats.m("plastic_black", Color.WHITE, {"albedo": hair.darkened(0.2)}), 0.005)
		brow.rotation_degrees.z = s * -8.0
	_mesh(head, Meshes.sphere(0.032, 8), Vector3(0, 0.2, 0.2), Mats.m("plastic_beige", Color.WHITE, {"albedo": skin.darkened(0.08), "roughness_base": 0.75}))  # nose
	mouth = _box(head, Vector3(0.09, 0.018, 0.03), Vector3(0, 0.13, 0.17), Mats.m("plastic_black", Color(6, 1.6, 1.6)), 0.006)
	var hair_m := Mats.m("fabric", Color.WHITE, {"albedo": hair, "albedo2": hair.darkened(0.3), "roughness_base": 0.9})
	match hair_style:
		0:
			_mesh(head, Meshes.sphere(0.21, 16), Vector3(0, 0.28, -0.03), hair_m, Vector3(1.0, 0.72, 0.95))
			_box(head, Vector3(0.3, 0.06, 0.08), Vector3(0, 0.37, 0.12), hair_m, 0.03)
		1:
			_mesh(head, Meshes.sphere(0.21, 16), Vector3(0, 0.28, -0.03), hair_m, Vector3(1.0, 0.72, 0.95))
			_mesh(head, Meshes.sphere(0.08, 10), Vector3(0, 0.42, -0.12), hair_m)
		2:
			var cap_c: Color = hat_color if hat_color is Color else shirt
			var cap_m := Mats.m("fabric", Color.WHITE, {"albedo": cap_c, "albedo2": cap_c.darkened(0.2)})
			_mesh(head, Meshes.sphere(0.21, 16), Vector3(0, 0.3, -0.01), cap_m, Vector3(1.0, 0.62, 1.0))
			_box(head, Vector3(0.26, 0.02, 0.14), Vector3(0, 0.3, 0.2), cap_m, 0.008)
		_:
			pass
	if hat_color is Color and hair_style != 2:
		var hm := Mats.m("plastic_white", Color.WHITE, {"albedo": hat_color, "roughness_base": 0.35})
		_mesh(head, Meshes.sphere(0.225, 16), Vector3(0, 0.32, 0), hm, Vector3(1.0, 0.6, 1.0))
		_mesh(head, Meshes.cyl(0.27, 0.02, 18), Vector3(0, 0.31, 0.02), hm)
	if accessory == "headset":
		var hs := Mats.m("plastic_black")
		_box(head, Vector3(0.44, 0.03, 0.05), Vector3(0, 0.43, 0), hs, 0.01)
		for s in [-1.0, 1.0]:
			_box(head, Vector3(0.05, 0.1, 0.1), Vector3(s * 0.21, 0.24, 0), hs, 0.02)

## Mouth flaps / screen mouth for `seconds`.
func talk(seconds: float) -> void:
	_talk = maxf(_talk, seconds)

func is_talking() -> bool:
	return _talk > 0.0

# ------------------------------------------------------------------ animation
func _process(delta: float) -> void:
	if not _built or pelvis == null:
		return
	_t += delta
	var moving := clampf(move_speed / 3.0, 0.0, 1.6)
	if pose in ["walk", "run", "carry", "climb"] and moving < 0.15:
		moving = 0.5 if pose != "run" else 1.0
	if moving > 0.05 or pose == "climb":
		_phase += delta * (5.5 + move_speed * 2.2)
	var a := _target(moving)
	var k := 1.0 - exp(-12.0 * delta)
	for key in a:
		_cur[key] = lerpf(float(_cur.get(key, a[key])), float(a[key]), k)
	pelvis.position.y = float(_cur.py)
	pelvis.rotation.x = float(_cur.pr)
	spine.rotation = Vector3(float(_cur.sx), float(_cur.sy), float(_cur.sz))
	thigh_l.rotation.x = float(_cur.tl)
	thigh_r.rotation.x = float(_cur.tr)
	shin_l.rotation.x = float(_cur.kl)
	shin_r.rotation.x = float(_cur.kr)
	uarm_l.rotation = Vector3(float(_cur.al), 0, -float(_cur.az) + float(_cur.alz))
	uarm_r.rotation = Vector3(float(_cur.ar), 0, float(_cur.az) + float(_cur.arz))
	farm_l.rotation.x = float(_cur.el)
	farm_r.rotation.x = float(_cur.er)
	head.rotation = Vector3(float(_cur.hx) - clampf(look_pitch, -0.9, 0.9) * 0.5, float(_cur.hy), float(_cur.hz))
	_face(delta)

func _target(moving: float) -> Dictionary:
	var t := _t + _seed
	var a := {"py": 0.52, "pr": 0.0, "sx": 0.0, "sy": 0.0, "sz": 0.0, "tl": 0.0, "tr": 0.0, "kl": 0.0, "kr": 0.0,
		"al": 0.0, "ar": 0.0, "az": 0.1, "alz": 0.0, "arz": 0.0, "el": -0.15, "er": -0.15,
		"hx": 0.0, "hy": 0.0, "hz": 0.0}
	var sw := sin(_phase) * 0.55 * minf(moving, 1.2)
	var breathe := sin(t * 1.7) * 0.02
	match pose:
		"walk", "run", "carry", "idle", "air":
			a.tl = sw
			a.tr = -sw
			a.kl = maxf(0.0, -sin(_phase)) * 0.7 * minf(moving, 1.0)
			a.kr = maxf(0.0, sin(_phase)) * 0.7 * minf(moving, 1.0)
			a.al = -sw * 0.8
			a.ar = sw * 0.8
			a.py = 0.52 + absf(cos(_phase)) * 0.04 * minf(moving, 1.0)
			a.sx = 0.06 * minf(moving, 1.0) + breathe
			a.sz = sin(_phase * 0.5) * 0.04 * moving
			if moving < 0.05:
				a.hy = sin(t * 0.37) * 0.25
				a.hz = sin(t * 0.9) * 0.03
				a.al = 0.04
				a.ar = 0.04
			if pose == "carry":
				a.al = -1.15
				a.ar = -1.15
				a.el = -0.35
				a.er = -0.35
				a.az = -0.05
			if pose == "air":
				a.tl = -0.5
				a.tr = -0.2
				a.kl = 0.8
				a.kr = 0.5
				a.al = -0.4
				a.ar = -0.4
				a.az = 0.5
		"crouch":
			a.py = 0.3
			a.tl = -1.0 + sw * 0.4
			a.tr = -1.0 - sw * 0.4
			a.kl = 1.55
			a.kr = 1.55
			a.sx = 0.35
			a.hx = -0.25
			a.al = -0.45 - sw * 0.3
			a.ar = -0.45 + sw * 0.3
			a.el = -0.6
			a.er = -0.6
		"climb":
			var c := sin(_phase)
			a.tl = -0.7 + c * 0.45
			a.tr = -0.7 - c * 0.45
			a.kl = 1.0 - c * 0.4
			a.kr = 1.0 + c * 0.4
			a.al = -2.4 - c * 0.4
			a.ar = -2.4 + c * 0.4
			a.el = -0.4
			a.er = -0.4
			a.sx = 0.15
			a.hx = -0.35
		"sit", "sit_type", "sit_idle":
			a.py = seat_h + 0.06
			a.tl = -1.5
			a.tr = -1.45
			a.kl = 1.45
			a.kr = 1.5
			a.sx = -0.05 + breathe
			a.al = -0.35
			a.ar = -0.35
			a.el = -0.9
			a.er = -0.9
			if pose == "sit_type":
				a.sx = 0.12
				a.al = -0.55 + sin(t * 23.0) * 0.05
				a.ar = -0.55 + sin(t * 19.0 + 1.0) * 0.05
				a.el = -0.95 + maxf(0.0, sin(t * 17.0)) * 0.12
				a.er = -0.95 + maxf(0.0, sin(t * 21.0 + 2.0)) * 0.12
				a.hx = 0.12 + sin(t * 0.5) * 0.03
				a.hy = sin(t * 0.21) * 0.08
				if fmod(t, 9.0) > 7.6:  # pause, lean back, stretch
					a.sx = -0.15
					a.al = -0.25
					a.ar = -0.25
					a.hx = -0.15
			elif pose == "sit_idle":
				# phone in the right hand, thumb scrolling
				a.ar = -0.9
				a.er = -1.3 + sin(t * 3.0) * 0.05
				a.arz = -0.35
				a.hx = 0.35
				a.hy = -0.15 + sin(t * 0.3) * 0.1
				if fmod(t, 14.0) > 11.0:  # look up and around
					a.hx = -0.05
					a.hy = sin(t * 0.8) * 0.5
		"stand_scribble":
			var phase_c := fmod(t, 8.0)
			a.ar = -2.0 + sin(t * 9.0) * 0.12
			a.arz = cos(t * 9.0) * 0.12
			a.er = -0.5 + sin(t * 4.5) * 0.08
			a.al = -0.25
			a.el = -0.9
			a.hy = sin(t * 0.6) * 0.1
			a.hz = 0.06
			a.sx = -0.05 + breathe
			if phase_c > 6.0:  # step back, look at the board, hand on chin
				a.ar = -0.6
				a.er = -2.2
				a.arz = -0.2
				a.hx = -0.1
				a.hz = -0.08
		"stand_think":
			a.al = -0.65
			a.ar = -0.65
			a.el = -1.6
			a.er = -1.6
			a.alz = 0.55
			a.arz = -0.55
			a.hz = sin(t * 0.4) * 0.12
			a.hx = -0.08
			a.sx = -0.05 + breathe
			if fmod(t, 11.0) > 9.2:  # scratch head
				a.ar = -2.6
				a.er = -1.9
				a.arz = -0.3
		"stand_assemble":
			a.sx = 0.22
			a.hx = 0.4
			a.al = -0.85 + sin(t * 6.0) * 0.08
			a.ar = -0.8 + sin(t * 7.3 + 1.2) * 0.1
			a.el = -0.75 + maxf(0.0, sin(t * 6.0)) * 0.2
			a.er = -0.7 + maxf(0.0, sin(t * 7.3 + 1.2)) * 0.25
			a.alz = 0.25
			a.arz = -0.25
			a.hy = sin(t * 0.7) * 0.15
			if fmod(t, 12.0) > 10.5:  # hold a part up to the light
				a.ar = -1.7
				a.er = -0.9
				a.hx = -0.2
				a.hy = 0.25
	# talking: nod
	if _talk > 0.0:
		a.hx = float(a.hx) + sin(t * 11.0) * 0.05
	return a

func _face(delta: float) -> void:
	_blink -= delta
	var eye_scale := 1.0
	if _blink < 0.0:
		eye_scale = 0.12
		if _blink < -0.12:
			_blink = _rng.randf_range(2.0, 5.5)
	for e in eyes:
		if is_instance_valid(e):
			e.scale.y = eye_scale if head_style == "crt" else maxf(eye_scale, 0.2)
	if mouth:
		var open := 0.0
		if _talk > 0.0:
			_talk -= delta
			# syllable-ish rhythm with a little noise
			open = clampf(0.5 + 0.5 * sin(_t * 17.0) * sin(_t * 5.3 + 1.0) + _rng.randf_range(-0.2, 0.2), 0.0, 1.0)
		if head_style == "crt":
			mouth.scale = Vector3(1.0 - open * 0.45, 1.0 + open * 3.0, 1.0)
			if face_mat:
				face_mat.emission_energy_multiplier = 1.0 + open * 0.8
		else:
			mouth.scale = Vector3(1.0 - open * 0.3, 1.0 + open * 3.0, 1.0)
