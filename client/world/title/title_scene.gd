extends Node3D
## Title-screen 3D scene (WORLD agent, iteration 3): the PHONE REPAIR garage seen from the street at night, light
## rain, wet asphalt + puddles reflecting the flickering neon sign, warm light inside where three friends ("Telly"
## avatars) tinker, a slow camera dolly loop, the same lo-fi post FX as in game.
##
## Use: instance res://world/title/title_scene.tscn (best inside a SubViewport with own_world_3d, or alone in the tree
## while no company is loaded). It has its own camera (+ environment on the camera) and PostFX layer, everything sits
## far from the origin (SET_OFFSET) and has no collision, groups or Bus/Game coupling that could disturb the game.
## API:
##   set_company_sign(text, color)  — the sign shows a company lightbox; text "" = back to the neon "PHONE REPAIR"
##   set_shot(i)                    — 0 wide street / 1 low over the puddles / 2 close at the door; freezes the loop
##   resume_loop()                  — back to the slow dolly loop
##   use_post_fx (export)           — false if the host applies its own post-processing
##   apply_quality(q)               — "lo-fi" | "clean"

const PostFX := preload("res://fx/post_fx.gd")
const Garage := preload("res://world/levels/level_1_garage.gd")
const Rig := preload("res://world/actors/worker_rig.gd")
const Mats := preload("res://world/lib/mats.gd")
const Meshes := preload("res://world/lib/meshes.gd")
const Device := preload("res://world/live/broken_device.gd")
const Flicker := preload("res://fx/flicker.gd")

const SET_OFFSET := Vector3(3000, 0, 0)
## camera keyframes in garage space: [position, look target, fov]
const SHOTS := [
	[Vector3(3.6, 1.55, 14.8), Vector3(-1.0, 2.1, 3.6), 56.0],
	[Vector3(2.8, 0.42, 8.6), Vector3(-1.3, 1.9, 3.6), 60.0],
	[Vector3(0.9, 1.65, 6.4), Vector3(-1.3, 1.5, 1.2), 62.0],
]
const LOOP := [
	[Vector3(5.0, 1.6, 15.2), Vector3(-0.8, 2.0, 3.6), 54.0],
	[Vector3(2.4, 1.15, 12.4), Vector3(-1.0, 2.0, 3.6), 56.0],
	[Vector3(-0.6, 0.9, 10.2), Vector3(-1.3, 2.0, 3.6), 58.0],
	[Vector3(-3.6, 1.3, 11.6), Vector3(-1.2, 1.9, 3.6), 57.0],
	[Vector3(-1.2, 1.9, 13.8), Vector3(-1.0, 2.1, 3.6), 55.0],
	[Vector3(2.8, 1.8, 15.6), Vector3(-0.9, 2.1, 3.6), 54.0],
]
const LOOP_PERIOD := 72.0

@export var use_post_fx := true

var set_root: Node3D
var level: Node3D
var shop: Node3D
var cam: Camera3D
var env: Environment
var post: CanvasLayer
var friends: Array = []
var _t := 0.0
var _fixed := -1
var _carry: Node3D
var _carry_t := 0.0

func _ready() -> void:
	set_root = Node3D.new()
	set_root.name = "Set"
	set_root.position = SET_OFFSET
	add_child(set_root)
	_make_camera()
	if use_post_fx:
		post = PostFX.new()
		post.name = "PostFX"
		add_child(post)
	level = Node3D.new()
	level.set_script(Garage)
	level.name = "Garage"
	level.set("decor_only", true)
	set_root.add_child(level)
	level.build_level()
	shop = level.get("shop")
	_strip(level)
	_wet_ground()
	_backdrop()
	_rain()
	_friends()
	_extras()
	_place_camera(0.0)

# ------------------------------------------------------------------ public
func set_company_sign(text: String, color: Color = Color(0.31, 0.55, 1.0)) -> void:
	if shop == null:
		return
	if text == "":
		shop.set_sign_override("PHONE REPAIR", Color(1.0, 0.28, 0.62), "neon")
	else:
		shop.set_sign_override(text, color, "company", color.lerp(Color.WHITE, 0.5).inverted().lerp(color, 0.3))

func set_shot(i: int) -> void:
	_fixed = clampi(i, 0, SHOTS.size() - 1)
	var s: Array = SHOTS[_fixed]
	_aim(s[0], s[1], s[2])

func resume_loop() -> void:
	_fixed = -1

func apply_quality(q: String) -> void:
	if post:
		post.apply_quality(q)

# ------------------------------------------------------------------ build
func _make_camera() -> void:
	cam = Camera3D.new()
	cam.name = "TitleCam"
	cam.near = 0.05
	cam.far = 400.0
	cam.fov = 56.0
	add_child(cam)
	cam.current = true
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.015, 0.02, 0.06)
	psm.sky_horizon_color = Color(0.16, 0.12, 0.2)
	psm.sky_curve = 0.12
	psm.ground_bottom_color = Color(0.01, 0.01, 0.015)
	psm.ground_horizon_color = Color(0.1, 0.08, 0.12)
	psm.sun_angle_max = 0.0
	sky.sky_material = psm
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.34, 0.5)
	env.ambient_light_energy = 0.06
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.ssr_enabled = true
	env.ssr_max_steps = 56
	env.ssr_fade_in = 0.1
	env.ssr_fade_out = 1.6
	env.ssr_depth_tolerance = 0.4
	env.ssao_enabled = true
	env.ssao_radius = 0.9
	env.ssao_intensity = 1.6
	env.glow_enabled = true
	env.glow_intensity = 0.85
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 0.85
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.set_glow_level(1, 1.0)
	env.set_glow_level(2, 0.9)
	env.set_glow_level(3, 0.7)
	env.set_glow_level(4, 0.5)
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.03
	env.volumetric_fog_albedo = Color(0.8, 0.84, 0.95)
	env.volumetric_fog_anisotropy = 0.4
	env.volumetric_fog_length = 40.0
	env.volumetric_fog_ambient_inject = 0.2
	cam.environment = env

## Scenery only: no collision in the shared physics world, no groups the game looks for, props frozen.
func _strip(n: Node) -> void:
	for c in n.find_children("*", "", true, false):
		for g in ["interactable", "viewpoint", "grabbable", "ladder", "ship_crate", "repair_device", "customer", "stage"]:
			if c.is_in_group(g):
				c.remove_from_group(g)
		if c is RigidBody3D:
			(c as RigidBody3D).freeze = true
		if c is CollisionObject3D:
			c.process_mode = Node.PROCESS_MODE_DISABLED

func _wet(name: String, tint: Color) -> Material:
	return Mats.m(name, tint, {"roughness_base": 0.07, "roughness2": 0.03, "grime": 0.2, "speckle": 0.05})

func _wet_ground() -> void:
	var outside := level.get_node_or_null("Outside")
	if outside == null:
		return
	var swap := {
		Mats.m("concrete_floor", Color(0.9, 0.9, 0.95)): _wet("concrete_floor", Color(0.55, 0.55, 0.6)),
		Mats.m("sidewalk"): _wet("sidewalk", Color(0.6, 0.6, 0.65)),
		Mats.m("asphalt"): _wet("asphalt", Color(0.7, 0.7, 0.75)),
	}
	for mi in outside.find_children("*", "MeshInstance3D", true, false):
		var m: Material = (mi as MeshInstance3D).material_override
		if swap.has(m):
			(mi as MeshInstance3D).material_override = swap[m]
	# puddles: near-black mirror discs (SSR picks up the neon, the lit door and the lamps)
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.015, 0.017, 0.022)
	pm.roughness = 0.02
	pm.metallic_specular = 1.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for p in [Vector3(-1.6, 0.0, 5.2), Vector3(0.6, 0.0, 6.4), Vector3(-2.8, 0.0, 7.0), Vector3(1.6, 0.0, 8.0), Vector3(-0.4, 0.0, 9.6),
			Vector3(2.8, 0.0, 10.8), Vector3(-3.6, 0.0, 11.6), Vector3(-1.0, 0.0, 12.4), Vector3(4.2, 0.0, 12.9)]:
		var d := MeshInstance3D.new()
		d.mesh = Meshes.cyl(1.0, 0.004, 24)
		d.material_override = pm
		var y := -0.016 if p.z < 6.3 else (0.025 if p.z < 8.3 else -0.115)
		d.position = Vector3(p.x, y, p.z)
		d.scale = Vector3(rng.randf_range(0.5, 1.3), 1.0, rng.randf_range(0.35, 0.8))
		d.rotation.y = rng.randf() * PI
		d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		level.add_child(d)

## The family house next door, a backyard, trees and a far skyline so no void shows around the garage.
func _backdrop() -> void:
	var b := Node3D.new()
	b.name = "Backdrop"
	level.add_child(b)
	_box(b, Vector3(60, 0.2, 40), Vector3(0, -0.15, -22.0), Mats.m("grass", Color(0.6, 0.7, 0.6)))
	_box(b, Vector3(14, 0.2, 6), Vector3(-11.5, -0.13, 1.0), Mats.m("grass", Color(0.7, 0.8, 0.7)))
	_box(b, Vector3(14, 0.2, 6), Vector3(11.5, -0.13, 1.0), Mats.m("grass", Color(0.7, 0.8, 0.7)))
	# house to the left of the garage: two storeys, porch light, a couple of warm windows
	var h := Node3D.new()
	h.position = Vector3(-10.4, 0, -1.5)
	b.add_child(h)
	var sid := Mats.m("siding_warm", Color(0.7, 0.72, 0.8))
	_box(h, Vector3(12.0, 6.0, 9.0), Vector3(0, 3.0, 0), sid)
	for s in [-1.0, 1.0]:
		var r := _box(h, Vector3(7.4, 0.2, 10.0), Vector3(s * 3.1, 7.6, 0), Mats.m("roof"))
		r.rotation_degrees.z = -s * 35.0
	for i in 4:
		for fl in 2:
			var lit := (i + fl) % 3 == 0 or (i == 2 and fl == 1)
			var c := Color(1.0, 0.68, 0.36) if lit else Color(0.03, 0.035, 0.05)
			_box(h, Vector3(1.1, 1.2, 0.06), Vector3(-4.3 + i * 2.6, 1.6 + fl * 2.7, 4.52), Mats.glow(c, 2.4) if lit else Mats.m("tv_black"))
			_box(h, Vector3(1.25, 0.08, 0.14), Vector3(-4.3 + i * 2.6, 0.95 + fl * 2.7, 4.55), Mats.m("plastic_white"))
	_box(h, Vector3(1.0, 2.15, 0.06), Vector3(3.6, 1.07, 4.52), Mats.m("wood_dark"))
	var porch := MeshInstance3D.new()
	porch.mesh = Meshes.sphere(0.1, 8)
	porch.material_override = Mats.glow(Color(1.0, 0.7, 0.4), 9.0)
	porch.position = Vector3(4.4, 2.3, 4.65)
	h.add_child(porch)
	var pl := OmniLight3D.new()
	pl.light_color = Color(1.0, 0.68, 0.4)
	pl.light_energy = 1.2
	pl.omni_range = 5.0
	pl.omni_attenuation = 1.6
	pl.position = Vector3(4.4, 2.2, 5.1)
	h.add_child(pl)
	# hedges + trees behind
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	for i in 9:
		var t := Node3D.new()
		t.position = Vector3(-18.0 + i * 4.6 + rng.randf_range(-1, 1), 0, -9.0 - rng.randf_range(0, 6))
		b.add_child(t)
		_cyl(t, 0.22, 3.2, Vector3(0, 1.6, 0), Mats.m("wood_dark"))
		for k in 3:
			var s := MeshInstance3D.new()
			s.mesh = Meshes.sphere(rng.randf_range(1.6, 2.4), 8)
			s.material_override = Mats.m("grass", Color(0.45, 0.6, 0.55), {"pattern": 0, "speckle": 0.4})
			s.position = Vector3(rng.randf_range(-1, 1), 3.8 + k * 1.1, rng.randf_range(-1, 1))
			t.add_child(s)
	_box(b, Vector3(0.9, 1.1, 7.0), Vector3(4.9, 0.55, -0.5), Mats.m("grass", Color(0.8, 1.0, 0.8)))
	# far skyline: dark blocks with a few lit windows + a red aircraft light
	var city := Node3D.new()
	city.position = Vector3(0, 0, -70)
	b.add_child(city)
	for i in 16:
		var w := rng.randf_range(6, 14)
		var hh := rng.randf_range(10, 34)
		var bx := _box(city, Vector3(w, hh, w), Vector3(-60 + i * 8.5 + rng.randf_range(-2, 2), hh * 0.5 - 2.0, rng.randf_range(-12, 8)), Mats.m("plaster", Color(0.12, 0.13, 0.17)))
		for k in 6:
			if rng.randf() < 0.55:
				_box(bx, Vector3(w * rng.randf_range(0.1, 0.25), 0.9, 0.1), Vector3(rng.randf_range(-0.35, 0.35) * w, rng.randf_range(-0.4, 0.4) * hh, w * 0.5 + 0.05),
					Mats.glow(Color(1.0, 0.75, 0.45) if rng.randf() < 0.7 else Color(0.55, 0.75, 1.0), 1.4))
		if i % 5 == 2:
			var red := MeshInstance3D.new()
			red.mesh = Meshes.sphere(0.35, 6)
			red.material_override = Mats.glow(Color(1.0, 0.1, 0.05), 8.0)
			red.position = Vector3(0, hh * 0.5 + 0.4, 0)
			bx.add_child(red)

func _rain() -> void:
	var r := CPUParticles3D.new()
	r.name = "Rain"
	r.amount = 2600
	r.lifetime = 1.1
	r.preprocess = 1.2
	r.position = Vector3(-0.5, 10.0, 9.0)
	r.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	r.emission_box_extents = Vector3(13.0, 0.5, 9.0)
	r.direction = Vector3(0.12, -1, 0.05)
	r.spread = 2.0
	r.gravity = Vector3(0, -4, 0)
	r.initial_velocity_min = 10.0
	r.initial_velocity_max = 13.0
	var q := QuadMesh.new()
	q.size = Vector2(0.016, 0.42)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.albedo_color = Color(0.55, 0.62, 0.8, 0.32)
	m.disable_receive_shadows = true
	q.material = m
	r.mesh = q
	level.add_child(r)
	# splashes on the ground
	var sp := CPUParticles3D.new()
	sp.name = "Splashes"
	sp.amount = 420
	sp.lifetime = 0.28
	sp.position = Vector3(-0.5, 0.03, 8.5)
	sp.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	sp.emission_box_extents = Vector3(10.0, 0.0, 6.0)
	sp.direction = Vector3(0, 1, 0)
	sp.spread = 35.0
	sp.gravity = Vector3(0, -9.0, 0)
	sp.initial_velocity_min = 0.6
	sp.initial_velocity_max = 1.3
	var sq := QuadMesh.new()
	sq.size = Vector2(0.022, 0.022)
	var sm := m.duplicate() as StandardMaterial3D
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	sm.albedo_color = Color(0.6, 0.68, 0.85, 0.45)
	sq.material = sm
	sp.mesh = sq
	level.add_child(sp)
	# drips off the garage gutter
	var dr := CPUParticles3D.new()
	dr.name = "Drips"
	dr.amount = 40
	dr.lifetime = 0.8
	dr.position = Vector3(-0.5, 4.95, 3.95)
	dr.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dr.emission_box_extents = Vector3(4.2, 0.0, 0.05)
	dr.direction = Vector3(0, -1, 0)
	dr.spread = 0.0
	dr.gravity = Vector3(0, -9.8, 0)
	var dq := QuadMesh.new()
	dq.size = Vector2(0.02, 0.12)
	dq.material = m
	dr.mesh = dq
	level.add_child(dr)

## Three friends ("Telly" avatars) at work inside, plus one walking a box back and forth.
func _friends() -> void:
	var spec := [
		[Color(1.0, 0.42, 0.24), Vector3(-0.9, 0, 0.5), 0.0, "stand_assemble"],    # behind the counter, facing the street
		[Color(0.24, 0.78, 1.0), Vector3(-3.45, 0, 1.45), -90.0, "stand_scribble"], # at the whiteboard
		[Color(0.7, 1.0, 0.24), Vector3(-2.3, 0, -2.75), 180.0, "stand_assemble"],  # at the back workbench
	]
	for f in spec:
		var r: Node3D = Rig.new()
		r.head_style = "crt"
		r.shirt = f[0]
		r.hat_color = f[0]
		r.pants = Color(0.17, 0.2, 0.27)
		r.pose = f[3]
		level.add_child(r)
		r.position = f[1]
		r.rotation_degrees.y = f[2]
		friends.append(r)
	# a phone being fixed on the counter in front of the first friend
	var dev: RigidBody3D = Device.new()
	dev.setup({"id": "title_1", "device": "phone", "fault": "cracked_screen", "status": "inRepair"})
	dev.freeze = true
	level.add_child(dev)
	dev.position = Vector3(-0.85, 1.04, 0.95)
	dev.rotation_degrees.y = 160.0
	dev.process_mode = Node.PROCESS_MODE_DISABLED
	# the fourth friend carries a box between the shelf and the counter
	var r4: Node3D = Rig.new()
	r4.head_style = "crt"
	r4.shirt = Color(0.85, 0.4, 1.0)
	r4.hat_color = r4.shirt
	r4.pants = Color(0.17, 0.2, 0.27)
	r4.pose = "carry"
	level.add_child(r4)
	var box := MeshInstance3D.new()
	box.mesh = Meshes.cbox(Vector3(0.42, 0.3, 0.34), 0.02)
	box.material_override = Mats.m("cardboard")
	box.position = Vector3(0, 1.05, 0.42)
	r4.add_child(box)
	_carry = r4
	friends.append(r4)

func _extras() -> void:
	# one street lamp buzzes like it should have been replaced years ago
	var lamps: Array = level.find_children("*", "OmniLight3D", true, false).filter(func(l: Node) -> bool:
		return (l as Node3D).position.y > 4.5 and (l as Node3D).get_parent().get_parent() != null and str((l as Node3D).get_parent().get_parent().name) == "Outside")
	if not lamps.is_empty():
		var f := Flicker.new()
		f.light = lamps[0]
		f.instability = 0.55
		level.add_child(f)
	if shop:
		shop.set_sign_lit(true)

# ------------------------------------------------------------------ camera
func _aim(p: Vector3, at: Vector3, fov: float) -> void:
	var gp := set_root.global_transform * (level.transform * p)
	var ga := set_root.global_transform * (level.transform * at)
	cam.global_transform = Transform3D(Basis.looking_at(ga - gp, Vector3.UP), gp)
	cam.fov = fov

func _cr(a: Vector3, b: Vector3, c: Vector3, d: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * b) + (-a + c) * t + (2.0 * a - 5.0 * b + 4.0 * c - d) * t2 + (-a + 3.0 * b - 3.0 * c + d) * t3)

func _place_camera(dt: float) -> void:
	if _fixed >= 0:
		return
	var n := LOOP.size()
	var u := fmod(_t / LOOP_PERIOD, 1.0) * n
	var i := int(u)
	var f := u - i
	var k := [LOOP[(i - 1 + n) % n], LOOP[i % n], LOOP[(i + 1) % n], LOOP[(i + 2) % n]]
	var p := _cr(k[0][0], k[1][0], k[2][0], k[3][0], f)
	var at := _cr(k[0][1], k[1][1], k[2][1], k[3][1], f)
	var fov := lerpf(float(k[1][2]), float(k[2][2]), f)
	# hand-held sway
	p += Vector3(sin(_t * 0.37) * 0.05, sin(_t * 0.53) * 0.035, 0.0)
	_aim(p, at, fov)

func _process(dt: float) -> void:
	_t += dt
	_place_camera(dt)
	if _carry:
		_carry_t += dt
		# shelf corner -> counter and back, 7 s each way
		var k := fmod(_carry_t / 14.0, 1.0)
		var a := Vector3(-0.4, 0, -2.4)
		var b := Vector3(0.1, 0, 0.35)
		var going := k < 0.5
		var s := k * 2.0 if going else (k - 0.5) * 2.0
		var e := clampf((s - 0.1) / 0.8, 0.0, 1.0)
		var p := a.lerp(b, e) if going else b.lerp(a, e)
		_carry.position = p
		var dir := (b - a) if going else (a - b)
		_carry.rotation.y = atan2(dir.x, dir.z)
		_carry.set("move_speed", 1.1 if e > 0.0 and e < 1.0 else 0.0)

func _box(p: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = Meshes.cbox(size, 0.0)
	mi.material_override = mat
	mi.position = pos
	p.add_child(mi)
	return mi

func _cyl(p: Node3D, r: float, h: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = Meshes.cyl(r, h, 8)
	mi.material_override = mat
	mi.position = pos
	p.add_child(mi)
	return mi
