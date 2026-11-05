extends Node3D
## Launch STAGE: dark hall, pedestal, truss spotlights with volumetric beams, neon accents, big screen.
## await play_launch(product_name, model) — running lights -> countdown 3-2-1 -> reveal -> back.
## world.gd hooks this to Bus.launch_show(product_id). Usable standalone (stage.tscn) for shots.

signal show_finished

const Mats := preload("res://world/lib/mats.gd")
const Meshes := preload("res://world/lib/meshes.gd")
const Kit := preload("res://world/lib/kit.gd")

const PEDESTAL_TOP := 0.62
const CYAN := Color(0.2, 0.85, 1.0)
const MAGENTA := Color(1.0, 0.2, 0.75)

var kit: Kit
var cam: Camera3D
var cam_env: Environment
var spots: Array[SpotLight3D] = []
var spot_rigs: Array[Node3D] = []
var neon_mats: Array[StandardMaterial3D] = []
var ring_mat: StandardMaterial3D
var screen_label: Label3D
var sub_label: Label3D
var count_label: Label3D
var turntable: Node3D
var model_slot: Node3D
var flash: OmniLight3D
var confetti: CPUParticles3D
var running := false
## current show phase: idle, lights, count3, count2, count1, reveal (read by tools/shot.gd)
var phase := "idle"
var _spin := 0.35
var _time := 0.0

func _ready() -> void:
	add_to_group("stage")
	kit = Kit.new(self)
	_build_hall()
	_build_pedestal()
	_build_rig()
	_build_screen()
	_build_camera()
	kit.viewpoint(self, "stage_wide", Vector3(0, 2.2, 9.5), Vector3(0, 1.6, 0), 60.0)
	kit.viewpoint(self, "stage_close", Vector3(1.6, 1.4, 3.6), Vector3(0, 1.3, 0), 55.0)
	_idle_state()

func _build_hall() -> void:
	var floor_mat := Mats.m("plastic_black", Color(1.4, 1.4, 1.6), {"roughness_base": 0.12, "grime": 0.25, "grime_scale": 0.6})
	kit.box(self, Vector3(30, 0.2, 30), Vector3(0, -0.1, 0), floor_mat, Vector3.ZERO, true, 0.0)
	var wall := Mats.m("plastic_black", Color(1.2, 1.2, 1.4), {"roughness_base": 0.7})
	kit.box(self, Vector3(30, 9, 0.3), Vector3(0, 4.5, -6), wall, Vector3.ZERO, true, 0.0)
	for s in [-1.0, 1.0]:
		kit.box(self, Vector3(0.3, 9, 24), Vector3(s * 11, 4.5, 4), wall, Vector3.ZERO, true, 0.0)
	kit.box(self, Vector3(30, 0.3, 30), Vector3(0, 9, 0), wall, Vector3.ZERO, false, 0.0)
	# stage platform
	kit.box(self, Vector3(12, 0.3, 6), Vector3(0, 0.15, -2.6), Mats.m("plastic_black", Color(2, 2, 2.3), {"roughness_base": 0.25}), Vector3.ZERO, true, 0.02)
	kit.box(self, Vector3(12, 0.02, 0.04), Vector3(0, 0.3, 0.4), _neon(CYAN, 3.0), Vector3.ZERO, false, 0.0, false)
	# neon accents on the back wall: two vertical tubes + a broken frame
	for s in [-1.0, 1.0]:
		kit.box(self, Vector3(0.06, 5.0, 0.06), Vector3(s * 5.2, 3.0, -5.8), _neon(MAGENTA if s < 0 else CYAN, 4.0), Vector3.ZERO, false, 0.0, false)
		kit.box(self, Vector3(1.8, 0.05, 0.05), Vector3(s * 4.3, 5.6, -5.8), _neon(MAGENTA if s < 0 else CYAN, 4.0), Vector3.ZERO, false, 0.0, false)
		kit.omni(self, Vector3(s * 5.2, 3.0, -5.2), MAGENTA if s < 0 else CYAN, 1.2, 5.0, false, 1.5)
	# audience rows (silhouettes)
	for r in 3:
		for i in 9:
			var x := -4.0 + i * 1.0 + (r % 2) * 0.5
			var z := 4.0 + r * 1.3
			kit.box(self, Vector3(0.55, 0.45, 0.5), Vector3(x, 0.22, z), Mats.m("fabric_blue", Color(0.4, 0.4, 0.5)), Vector3.ZERO, false, 0.04)
			kit.box(self, Vector3(0.55, 0.55, 0.1), Vector3(x, 0.7, z + 0.24), Mats.m("fabric_blue", Color(0.4, 0.4, 0.5)), Vector3.ZERO, false, 0.04)

func _neon(c: Color, e: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = e
	neon_mats.append(m)
	m.set_meta("base", e)
	return m

func _build_pedestal() -> void:
	var p := kit.node(self, Vector3(0, 0.3, -1.2), 0.0, "Pedestal")
	kit.cyl(p, 1.1, 0.2, Vector3(0, 0.1, 0), Mats.m("steel_dark", Color(0.8, 0.8, 0.9)), Vector3.ZERO, 32, true)
	kit.cyl(p, 0.9, 0.12, Vector3(0, 0.26, 0), Mats.m("metal", Color(0.5, 0.5, 0.55)), Vector3.ZERO, 32, true)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.08
	tm.outer_radius = 1.14
	tm.rings = 48
	tm.ring_segments = 6
	ring.mesh = tm
	ring_mat = _neon(CYAN, 5.0)
	ring.material_override = ring_mat
	ring.position = Vector3(0, 0.2, 0)
	p.add_child(ring)
	turntable = kit.node(p, Vector3(0, 0.32, 0), 0.0, "Turntable")
	kit.cyl(turntable, 0.85, 0.02, Vector3.ZERO, Mats.m("plastic_black", Color(3, 3, 3), {"roughness_base": 0.2}), Vector3.ZERO, 32)
	model_slot = kit.node(turntable, Vector3(0, 0.01, 0), 0.0, "ModelSlot")
	flash = kit.omni(p, Vector3(0, 1.4, 0.8), Color(0.9, 0.95, 1.0), 0.0, 6.0, false, 2.0)
	kit.omni(p, Vector3(0, 0.5, 0), CYAN, 0.8, 2.2, false, 1.0)

func _build_rig() -> void:
	# truss with 4 moving heads; 2 cast shadows
	var truss := kit.node(self, Vector3(0, 6.2, 0.5), 0.0, "Truss")
	kit.box(truss, Vector3(10, 0.25, 0.25), Vector3.ZERO, Mats.m("metal"), Vector3.ZERO, false, 0.02)
	kit.box(truss, Vector3(10, 0.25, 0.25), Vector3(0, 0, -3.0), Mats.m("metal"), Vector3.ZERO, false, 0.02)
	var xs := [-3.6, -1.2, 1.2, 3.6]
	for i in xs.size():
		var rig := kit.node(truss, Vector3(xs[i], -0.25, -1.5 + (i % 2) * 1.5 - 0.0), 0.0, "Head%d" % i)
		kit.box(rig, Vector3(0.3, 0.35, 0.3), Vector3(0, -0.1, 0), Mats.m("plastic_black"), Vector3.ZERO, false, 0.05)
		var l := kit.spot(rig, Vector3(0, -0.3, 0), Vector3(0, -5, 0.01), Color(1, 1, 1), 0.0, 14.0, 11.0, i == 1 or i == 2, 14.0)
		l.position = Vector3(0, -0.3, 0)
		l.spot_angle_attenuation = 0.4
		spots.append(l)
		spot_rigs.append(rig)
		_aim_rig(i, Vector3(0, 0, -1.2))

func _build_screen() -> void:
	var scr := kit.node(self, Vector3(0, 4.2, -5.82), 0.0, "Screen")
	kit.box(scr, Vector3(7.2, 2.6, 0.08), Vector3.ZERO, Mats.m("tv_black"), Vector3.ZERO, false, 0.02)
	kit.mesh(scr, Meshes.quad(Vector2(7.0, 2.4)), Vector3(0, 0, 0.045), Mats.screen(3, Color(0.15, 0.25, 0.5), 0.35, 5.0), Vector3.ZERO, false)
	screen_label = kit.label(scr, "", Vector3(0, -0.15, 0.06), 200, Color(1, 1, 1), Vector3.ZERO, 0.006)
	screen_label.outline_size = 0
	sub_label = kit.label(scr, "", Vector3(0, 0.75, 0.06), 90, CYAN * 1.5, Vector3.ZERO, 0.006)
	count_label = kit.label(self, "", Vector3(0, 2.4, -1.0), 400, Color(1.0, 0.95, 0.8) * 2.0, Vector3.ZERO, 0.004)
	count_label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	confetti = CPUParticles3D.new()
	confetti.position = Vector3(0, 6.0, -1.2)
	confetti.emitting = false
	confetti.one_shot = true
	confetti.amount = 160
	confetti.lifetime = 4.0
	confetti.explosiveness = 0.85
	confetti.direction = Vector3(0, -1, 0)
	confetti.spread = 70.0
	confetti.initial_velocity_min = 1.5
	confetti.initial_velocity_max = 4.0
	confetti.gravity = Vector3(0, -2.5, 0)
	confetti.angular_velocity_min = -360
	confetti.angular_velocity_max = 360
	confetti.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	confetti.emission_box_extents = Vector3(3, 0.2, 1.5)
	var qm := QuadMesh.new()
	qm.size = Vector2(0.06, 0.035)
	var cm := StandardMaterial3D.new()
	cm.vertex_color_use_as_albedo = true
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.cull_mode = BaseMaterial3D.CULL_DISABLED
	cm.emission_enabled = true
	cm.emission = Color(0.3, 0.3, 0.3)
	qm.material = cm
	confetti.mesh = qm
	var grad := Gradient.new()
	grad.set_color(0, CYAN)
	grad.set_color(1, MAGENTA)
	grad.add_point(0.5, Color(1.0, 0.85, 0.2))
	confetti.color_initial_ramp = grad
	add_child(confetti)

func _build_camera() -> void:
	cam = Camera3D.new()
	cam.name = "StageCam"
	cam.fov = 55.0
	cam.near = 0.05
	add_child(cam)
	cam.transform = Transform3D(Basis.looking_at(Vector3(0, 1.4, -1.2) - Vector3(0, 2.0, 8.0), Vector3.UP), Vector3(0, 2.0, 8.0))
	cam_env = Environment.new()
	cam_env.background_mode = Environment.BG_COLOR
	cam_env.background_color = Color(0.0, 0.0, 0.01)
	cam_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	cam_env.ambient_light_color = Color(0.3, 0.3, 0.5)
	cam_env.ambient_light_energy = 0.05
	cam_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	cam_env.glow_enabled = true
	cam_env.glow_intensity = 0.9
	cam_env.glow_bloom = 0.05
	cam_env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	cam_env.ssao_enabled = true
	cam_env.ssr_enabled = false
	cam_env.volumetric_fog_enabled = true
	cam_env.volumetric_fog_density = 0.022
	cam_env.volumetric_fog_albedo = Color(0.9, 0.9, 1.0)
	cam_env.volumetric_fog_anisotropy = 0.5
	cam_env.volumetric_fog_length = 30.0
	cam.environment = cam_env

func _aim_rig(i: int, target_local: Vector3) -> void:
	var l: SpotLight3D = spots[i]
	var from := l.global_position
	var tgt := to_global(target_local)
	if from.distance_to(tgt) < 0.01:
		return
	l.global_basis = Basis.looking_at(tgt - from, Vector3.FORWARD if absf((tgt - from).normalized().y) > 0.98 else Vector3.UP)

func _idle_state() -> void:
	for l in spots:
		l.light_energy = 0.0
	screen_label.text = ""
	sub_label.text = ""
	count_label.text = ""
	spots[1].light_energy = 3.0
	spots[1].light_color = Color(0.7, 0.8, 1.0)
	_aim_rig(1, Vector3(0, 0.6, -1.2))

func _process(dt: float) -> void:
	_time += dt
	turntable.rotation.y += _spin * dt
	ring_mat.emission_energy_multiplier = 4.0 + sin(_time * 3.0) * 1.2

# ------------------------------------------------------------------ show
## Generic phone from the UI agent's parametric builder (if present).
func _builder_model(product_name: String) -> Node3D:
	const BUILDER := "res://phone/phone_builder.gd"
	if not ResourceLoader.exists(BUILDER):
		return null
	var res: Variant = load(BUILDER).call("build", {"name": product_name, "colorway": "graphite", "lenses": 3, "companyInitial": product_name.substr(0, 1)})
	return res if res is Node3D else null

func make_default_model() -> Node3D:
	var n := Node3D.new()
	n.name = "DefaultPhone"
	var body := MeshInstance3D.new()
	body.mesh = Meshes.cbox(Vector3(0.72, 1.5, 0.09), 0.035)
	body.material_override = Mats.m("metal", Color(0.45, 0.47, 0.55), {"roughness_base": 0.25, "edge_wear": 0.6, "edge_color": Color(0.9, 0.9, 0.95)})
	body.position.y = 0.75
	n.add_child(body)
	var scr := MeshInstance3D.new()
	scr.mesh = Meshes.quad(Vector2(0.66, 1.42))
	scr.material_override = Mats.screen(3, CYAN, 1.4, 1.0)
	scr.position = Vector3(0, 0.75, 0.0455)
	n.add_child(scr)
	var bump := MeshInstance3D.new()
	bump.mesh = Meshes.cbox(Vector3(0.22, 0.22, 0.03), 0.04)
	bump.material_override = Mats.m("plastic_black")
	bump.position = Vector3(-0.18, 1.28, -0.055)
	n.add_child(bump)
	return n

func _fit_model(model: Node3D) -> void:
	for c in model_slot.get_children():
		c.queue_free()
	model_slot.add_child(model)
	# scale the model so it stands ~1.5 m tall on the turntable
	var aabb := AABB()
	var first := true
	for mi in model.find_children("*", "VisualInstance3D", true, false):
		var bb: AABB = (model.global_transform.affine_inverse() * mi.global_transform) * mi.get_aabb()
		aabb = bb if first else aabb.merge(bb)
		first = false
	if not first and aabb.size.y > 0.001:
		var s := 2.1 / maxf(aabb.size.y, aabb.size.x)
		model.scale = Vector3.ONE * s
		model.position = Vector3(-aabb.get_center().x * s, -aabb.position.y * s, -aabb.get_center().z * s)

func play_launch(product_name: String, model: Node3D = null) -> void:
	if running:
		return
	running = true
	var prev_cam := get_viewport().get_camera_3d()
	cam.make_current()
	# finer froxels so the narrow spot beams read as shafts (global setting, restored after the show)
	RenderingServer.environment_set_volumetric_fog_volume_size(192, 96)
	if model == null:
		model = _builder_model(product_name)
	if model == null:
		model = make_default_model()
	_fit_model(model)
	model_slot.position.y = -1.6
	model_slot.visible = false
	_idle_state()
	spots[1].light_energy = 0.0
	screen_label.text = ""
	sub_label.text = "LIVE"
	_spin = 0.35
	cam.transform = Transform3D(Basis.looking_at(Vector3(0, 1.6, -1.2) - Vector3(0, 2.6, 10.0), Vector3.UP), Vector3(0, 2.6, 10.0))
	var dolly := create_tween()
	dolly.tween_property(cam, "position", Vector3(0.0, 1.75, 4.6), 9.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# 1) running lights: beams sweep the hall in alternating colours
	phase = "lights"
	var t := 0.0
	while t < 2.6:
		for i in spots.size():
			var l: SpotLight3D = spots[i]
			l.light_color = CYAN if (i + int(t * 3.0)) % 2 == 0 else MAGENTA
			l.light_energy = 14.0
			var a := t * 2.2 + i * 1.7
			_aim_rig(i, Vector3(sin(a) * 6.0, 0.0, 2.0 + cos(a * 0.8) * 4.0))
		for m in neon_mats:
			m.emission_energy_multiplier = float(m.get_meta("base")) * (0.3 if randf() < 0.15 else 1.0)
		await get_tree().process_frame
		t += get_process_delta_time()

	# 2) countdown 3-2-1: beams converge on the pedestal
	for n in [3, 2, 1]:
		phase = "count%d" % n
		count_label.text = str(n)
		screen_label.text = ""
		sub_label.text = "LAUNCHING IN"
		for i in spots.size():
			spots[i].light_color = Color(1.0, 0.95, 0.85)
			spots[i].light_energy = 4.0 + (3 - n) * 4.0
			_aim_rig(i, Vector3(0, PEDESTAL_TOP, -1.2) + Vector3((i - 1.5) * 0.6 * n, 0, 0))
		var tw := create_tween()
		count_label.scale = Vector3.ONE * 1.6
		tw.tween_property(count_label, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		await get_tree().create_timer(1.0).timeout
	count_label.text = ""

	# 3) reveal: flash, model rises and spins, name on the screen, confetti
	phase = "reveal"
	model_slot.visible = true
	flash.light_energy = 12.0
	var ft := create_tween()
	ft.tween_property(flash, "light_energy", 1.2, 1.2)
	var rise := create_tween()
	rise.tween_property(model_slot, "position:y", 0.01, 1.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_spin = 3.5
	var sp := create_tween()
	sp.tween_property(self, "_spin", 0.5, 2.5)
	for i in spots.size():
		spots[i].light_energy = 10.0
		spots[i].light_color = CYAN if i % 2 == 0 else MAGENTA
		_aim_rig(i, Vector3(0, 1.2, -1.2))
	screen_label.text = product_name
	sub_label.text = "INTRODUCING"
	confetti.restart()
	confetti.emitting = true
	await get_tree().create_timer(4.5).timeout

	# 4) wrap up
	phase = "idle"
	running = false
	RenderingServer.environment_set_volumetric_fog_volume_size(128, 64)
	if prev_cam and is_instance_valid(prev_cam):
		prev_cam.make_current()
	show_finished.emit()
