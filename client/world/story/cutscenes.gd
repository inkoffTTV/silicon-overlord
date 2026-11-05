extends Node3D
## Story cutscenes (WORLD agent, iteration 3). world.gd plays them on Bus.story_cutscene(id); captions are the UI's
## (story JSON cutscenes.<id>.captions, timed over DURATION[id] seconds). Camera paths over the garage level, the
## local player is frozen and its camera restored (smooth blend) at the end; then world.cutscene_finished(id).
##   intro     — rainy-ish night street -> the dark "PHONE REPAIR" sign sputters and dies -> push in through the window
##               to the friends' spot by the house door.
##   investor  — headlights sweep the garage, a long dark car pulls up, a figure in a hat walks up the driveway and
##               tips the hat at the door (then walks back and drives off after the cutscene).
##   sign_swap — the neon dies, the old sign drops away, the company lightbox comes down into place and lights up
##               (sparks), then the counter turns into a reception.

const Mats := preload("res://world/lib/mats.gd")
const Meshes := preload("res://world/lib/meshes.gd")
const Customer := preload("res://world/actors/customer_npc.gd")
const Story := preload("res://world/live/story_state.gd")

const DURATION := {"intro": 12.0, "investor": 12.5, "sign_swap": 12.0}

signal finished(id: String)

var world: Node3D
var cam: Camera3D
var running := ""
## > 1 speeds everything up (tests)
var speed := 1.0
var _look_at := Vector3.ZERO

func _ready() -> void:
	name = "Cutscenes"
	cam = Camera3D.new()
	cam.name = "CutsceneCam"
	cam.near = 0.03
	cam.far = 300.0
	cam.fov = 60.0
	add_child(cam)

func is_running() -> bool:
	return running != ""

func play(id: String) -> void:
	if running != "" or not DURATION.has(id):
		return
	var lv: Node3D = world.get_level() if world else null
	var shop: Node3D = lv.get("shop") if lv else null
	if lv == null or shop == null:
		finished.emit(id)
		return
	running = id
	var player := get_tree().get_first_node_in_group("local_player") as Node3D
	if player and player.has_method("set_controls_enabled"):
		player.set_controls_enabled(false)
	cam.make_current()
	match id:
		"intro":
			await _intro(lv, shop)
		"investor":
			await _investor(lv, shop)
		"sign_swap":
			await _sign_swap(lv, shop)
	# blend back into the player's eyes
	if player and is_instance_valid(player) and player.get("cam"):
		var pc: Camera3D = player.cam
		var to := pc.global_transform
		await _move(cam.global_transform.origin, to.origin, cam.global_transform.origin - cam.global_basis.z * 2.0, to.origin - to.basis.z * 2.0, 0.8, pc.fov)
		pc.make_current()
		if player.has_method("set_controls_enabled"):
			player.set_controls_enabled(true)
	running = ""
	finished.emit(id)

# ------------------------------------------------------------------ helpers
func _wait(t: float) -> void:
	await get_tree().create_timer(t / speed).timeout

func _aim(from: Vector3, at: Vector3) -> void:
	cam.global_position = from
	if not from.is_equal_approx(at):
		cam.global_basis = Basis.looking_at(at - from, Vector3.UP)

## Dolly from a to b while the look target goes from la to lb (sine ease). Awaitable.
func _move(a: Vector3, b: Vector3, la: Vector3, lb: Vector3, t: float, fov: float = -1.0) -> void:
	var f0 := cam.fov
	var tw := create_tween()
	tw.tween_method(func(k: float) -> void:
		var e := 0.5 - 0.5 * cos(k * PI)
		_aim(a.lerp(b, e), la.lerp(lb, e))
		if fov > 0.0:
			cam.fov = lerpf(f0, fov, e), 0.0, 1.0, t / speed)
	await tw.finished

func _shot(lv: Node3D, a: Vector3, b: Vector3, la: Vector3, lb: Vector3, t: float, fov: float) -> void:
	cam.fov = fov
	await _move(lv.to_global(a), lv.to_global(b), lv.to_global(la), lv.to_global(lb), t)

# ------------------------------------------------------------------ intro
func _intro(lv: Node3D, shop: Node3D) -> void:
	Sfx.ambient("outdoor")
	var lit: bool = shop.lights_are_on()
	cam.fov = 58.0
	await _shot(lv, Vector3(4.8, 1.55, 15.5), Vector3(3.2, 1.45, 12.8), Vector3(-0.6, 2.2, 3.5), Vector3(-0.8, 2.0, 3.6), 4.0, 58.0)
	# the old sign sputters... and dies (it's chapter 0: nothing works yet)
	var sputter := create_tween()
	sputter.tween_interval(0.5 / speed)
	for i in 6:
		sputter.tween_callback(func() -> void:
			shop.set_sign_lit(i % 2 == 0)
			if i % 2 == 0:
				Sfx.play("switch", shop.sign_node().global_position, -12.0))
		sputter.tween_interval((0.12 + 0.1 * (i % 3)) / speed)
	sputter.tween_callback(func() -> void: shop.set_sign_lit(lit))
	await _shot(lv, Vector3(-0.6, 2.0, 9.0), Vector3(-1.0, 2.5, 7.2), Vector3(-1.5, 3.3, 3.7), Vector3(-1.5, 3.4, 3.7), 3.6, 50.0)
	# push in through the window to the friends' spot by the house door
	var spawn: Transform3D = lv.get("spawn_xform")
	var eye := spawn.origin + Vector3(0, 1.55, 0)
	await _shot(lv, Vector3(2.4, 1.6, 6.5), Vector3(2.4, 1.55, 3.0), Vector3(2.4, 1.5, 0.0), Vector3(2.6, 1.3, -1.5), 3.4, 62.0)
	await _move(cam.global_position, lv.to_global(eye + Vector3(0, 0.05, 0.6)), cam.global_position - cam.global_basis.z, lv.to_global(eye + Vector3(0, -0.1, 3.0)), 1.0, 70.0)
	world.set("_amb", "")

# ------------------------------------------------------------------ investor
func _investor(lv: Node3D, _shop: Node3D) -> void:
	var stage := Node3D.new()
	stage.name = "InvestorScene"
	lv.add_child(stage)
	var car := _make_car(Color(0.06, 0.09, 0.08))
	stage.add_child(car)
	car.position = Vector3(-26, 0, 11.0)
	car.rotation_degrees.y = 90.0
	var who: Node3D = Customer.new()
	stage.add_child(who)
	who.setup({"id": "investor", "customer": "office"})
	_hat(who)
	who.visible = false
	# 1) inside the garage: headlights sweep across the doorway
	var drive := create_tween()
	drive.tween_property(car, "position:x", 0.9, 5.5 / speed).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	Sfx.play("van_start", lv.to_global(Vector3(-8, 1, 11)), -6.0)
	await _shot(lv, Vector3(-0.6, 1.45, 1.4), Vector3(-0.4, 1.4, 2.2), Vector3(0.5, 1.0, 11.0), Vector3(0.6, 1.0, 11.0), 3.3, 64.0)
	# 2) low on the sidewalk: the car rolls in and stops, reflections
	await _shot(lv, Vector3(-4.6, 0.45, 8.4), Vector3(-3.9, 0.5, 8.6), Vector3(-2.0, 0.6, 11.0), Vector3(0.9, 0.7, 11.0), 2.6, 52.0)
	# 3) the figure gets out and walks up the driveway
	Sfx.play("door_open", car.global_position + Vector3(0, 1, 0), -4.0)
	who.visible = true
	who.global_position = lv.to_global(Vector3(1.4, 0, 9.6))
	who.walk([lv.to_global(Vector3(0.3, 0, 7.3)), lv.to_global(Vector3(0.3, 0, 4.3))], func() -> void:
		who.face(PI + lv.global_rotation.y)
		who.set_pose("tip_hat"), 1.25)
	await _shot(lv, Vector3(-0.3, 1.5, 2.4), Vector3(-0.2, 1.45, 2.6), Vector3(0.6, 1.2, 9.0), Vector3(0.35, 1.35, 5.0), 4.2, 46.0)
	# 4) close: a tip of the hat at the door
	await _shot(lv, Vector3(-0.15, 1.55, 2.9), Vector3(-0.1, 1.6, 3.15), Vector3(0.3, 1.5, 4.3), Vector3(0.3, 1.6, 4.3), 2.2, 40.0)
	# afterwards (not blocking): a short wave, back to the car, drive off
	get_tree().create_timer(4.0).timeout.connect(func() -> void:
		if not is_instance_valid(who):
			return
		who.set_pose("wave")
		get_tree().create_timer(1.5).timeout.connect(func() -> void:
			if not is_instance_valid(who):
				return
			who.walk([lv.to_global(Vector3(0.3, 0, 7.3)), lv.to_global(Vector3(1.4, 0, 9.6))], func() -> void:
				who.visible = false
				Sfx.play("van_start", car.global_position, -6.0)
				var away := car.create_tween()
				away.tween_property(car, "position:x", 30.0, 4.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
				away.tween_callback(stage.queue_free))))

func _hat(who: Node3D) -> void:
	var h: Node3D = who.rig.head
	var m := Mats.m("fabric", Color.WHITE, {"albedo": Color(0.08, 0.08, 0.1)})
	var brim := MeshInstance3D.new()
	brim.mesh = Meshes.cyl(0.3, 0.02, 20)
	brim.material_override = m
	brim.position = Vector3(0, 0.36, 0)
	h.add_child(brim)
	var crown := MeshInstance3D.new()
	crown.mesh = Meshes.cyl(0.17, 0.16, 16, 0.15)
	crown.material_override = m
	crown.position = Vector3(0, 0.45, 0)
	h.add_child(crown)
	var band := MeshInstance3D.new()
	band.mesh = Meshes.cyl(0.172, 0.035, 16)
	band.material_override = Mats.m("fabric", Color.WHITE, {"albedo": Color(0.5, 0.1, 0.12)})
	band.position = Vector3(0, 0.39, 0)
	h.add_child(band)

## Long dark sedan, original shape; headlights + taillights. Faces +Z.
func _make_car(c: Color) -> Node3D:
	var g := Node3D.new()
	g.name = "InvestorCar"
	var paint := Mats.m("metal_red", Color.WHITE, {"albedo": c, "metallic_base": 0.7, "roughness_base": 0.18, "grime": 0.05, "edge_wear": 0.3, "edge_color": Color(0.6, 0.65, 0.6)})
	var chrome := Mats.m("metal", Color(1.4, 1.4, 1.4), {"roughness_base": 0.12})
	_b(g, Vector3(1.9, 0.62, 4.9), Vector3(0, 0.58, 0), paint, 0.12)
	_b(g, Vector3(1.7, 0.5, 2.4), Vector3(0, 1.12, -0.25), paint, 0.16)
	_b(g, Vector3(1.72, 0.38, 2.2), Vector3(0, 1.13, -0.25), Mats.glass(Color(0.04, 0.05, 0.07, 0.9)), 0.12)
	_b(g, Vector3(1.92, 0.05, 4.92), Vector3(0, 0.58, 0), chrome, 0.02)
	for x in [-0.85, 0.85]:
		for z in [-1.5, 1.55]:
			var w := MeshInstance3D.new()
			w.mesh = Meshes.cyl(0.36, 0.26, 16)
			w.material_override = Mats.m("rubber")
			w.position = Vector3(x, 0.36, z)
			w.rotation_degrees.z = 90
			g.add_child(w)
			var hub := MeshInstance3D.new()
			hub.mesh = Meshes.cyl(0.2, 0.27, 12)
			hub.material_override = chrome
			hub.position = w.position
			hub.rotation_degrees.z = 90
			g.add_child(hub)
	for x in [-0.65, 0.65]:
		_b(g, Vector3(0.36, 0.1, 0.04), Vector3(x, 0.72, 2.45), Mats.glow(Color(1.0, 0.95, 0.85), 8.0), 0.0)
		_b(g, Vector3(0.36, 0.08, 0.04), Vector3(x, 0.74, -2.45), Mats.glow(Color(1.0, 0.08, 0.05), 3.0), 0.0)
		var hl := SpotLight3D.new()
		hl.light_color = Color(1.0, 0.94, 0.82)
		hl.light_energy = 6.0
		hl.spot_range = 22.0
		hl.spot_angle = 26.0
		hl.light_volumetric_fog_energy = 1.4
		hl.position = Vector3(x, 0.72, 2.5)
		hl.rotation_degrees = Vector3(-4, 0, 0)
		hl.basis = Basis.looking_at(Vector3(0, -0.08, 1.0), Vector3.UP)
		g.add_child(hl)
	_b(g, Vector3(0.9, 0.12, 0.05), Vector3(0, 0.62, 2.47), chrome, 0.02)
	return g

func _b(p: Node3D, size: Vector3, pos: Vector3, mat: Material, bevel: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = Meshes.cbox(size, bevel)
	mi.material_override = mat
	mi.position = pos
	p.add_child(mi)
	return mi

# ------------------------------------------------------------------ sign swap
func _sign_swap(lv: Node3D, shop: Node3D) -> void:
	var s: Dictionary = Game.state
	var nm := Story.company_name(s)
	if nm == "":
		nm = "MY COMPANY"
	var cols := Story.company_colors(s)
	var shape := Story.company_shape(s)
	shop.set_sign_override("PHONE REPAIR", Color(1.0, 0.28, 0.62), "neon")
	shop.set_sign_lit(true)
	var sign: Node3D = shop.sign_node()
	var home := sign.position
	cam.fov = 55.0
	_aim(lv.to_global(Vector3(-1.5, 1.7, 8.2)), lv.to_global(Vector3(-1.5, 3.2, 3.7)))
	# 1) the neon dies, the old sign tilts and drops away
	var dying := create_tween()
	dying.tween_interval(0.9 / speed)
	for i in 5:
		dying.tween_callback(func() -> void: shop.set_sign_lit(i % 2 == 1))
		dying.tween_interval(0.12 / speed)
	dying.tween_callback(func() -> void:
		shop.set_sign_lit(false)
		Sfx.play("ship_fail", sign.global_position, -8.0))
	dying.tween_interval(0.3 / speed)
	dying.tween_property(sign, "rotation_degrees:z", -14.0, 0.35 / speed).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	dying.tween_property(sign, "position:y", home.y - 4.0, 0.7 / speed).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	dying.tween_callback(func() -> void: Sfx.play("impact_metal", lv.to_global(Vector3(-1.5, 0.2, 4.5)), 0.0))
	await _move(lv.to_global(Vector3(-1.5, 1.7, 8.2)), lv.to_global(Vector3(-1.5, 1.9, 7.4)), lv.to_global(Vector3(-1.5, 3.2, 3.7)), lv.to_global(Vector3(-1.5, 3.1, 3.7)), 3.2)
	# 2) the new company sign comes down into place, dark, then lights up
	shop.set_sign_override(nm, cols[0], "company", cols[1], shape)
	shop.set_sign_lit(false)
	sign.rotation_degrees = Vector3.ZERO
	sign.position = home + Vector3(0, 2.5, 0)
	var come := create_tween()
	come.tween_property(sign, "position:y", home.y, 1.4 / speed).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	come.tween_interval(0.5 / speed)
	for i in 4:
		come.tween_callback(func() -> void:
			shop.set_sign_lit(i % 2 == 0 or i == 3)
			Sfx.play("switch", sign.global_position, -8.0))
		come.tween_interval(0.14 / speed)
	come.tween_callback(func() -> void:
		shop.set_sign_lit(true)
		_sparks(sign.global_position + Vector3(0, 0.0, 0.3), cols[0])
		Sfx.play("level_up", sign.global_position, 0.0))
	await _move(lv.to_global(Vector3(-1.5, 1.9, 7.4)), lv.to_global(Vector3(-1.2, 2.3, 6.2)), lv.to_global(Vector3(-1.5, 3.1, 3.7)), lv.to_global(Vector3(-1.5, 3.4, 3.7)), 3.6, 48.0)
	await _wait(0.8)
	# 3) inside: the counter becomes a reception
	_aim(lv.to_global(Vector3(-0.4, 1.65, 3.1)), lv.to_global(Vector3(-0.9, 1.1, 1.1)))
	cam.fov = 55.0
	await _wait(0.6)
	_sparks(lv.to_global(Vector3(-0.9, 1.2, 1.4)), cols[1])
	Sfx.play("confetti", lv.to_global(Vector3(-0.9, 1.2, 1.4)), -4.0)
	shop._set_hanging(false, nm, cols[0])
	shop._set_dress(false)
	await _move(cam.global_position, lv.to_global(Vector3(-0.6, 1.55, 2.6)), lv.to_global(Vector3(-0.9, 1.1, 1.1)), lv.to_global(Vector3(-0.9, 1.25, 1.1)), 2.6, 50.0)
	shop.clear_sign_override()
	shop.set_sign_lit(shop.lights_are_on())

func _sparks(at: Vector3, c: Color) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 70
	p.lifetime = 1.2
	p.explosiveness = 0.9
	p.direction = Vector3(0, 1, 0.4)
	p.spread = 80.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 3.5
	p.gravity = Vector3(0, -6, 0)
	var qm := QuadMesh.new()
	qm.size = Vector2(0.03, 0.03)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_color = c.lerp(Color(1, 0.9, 0.6), 0.5) * 3.0
	qm.material = m
	p.mesh = qm
	add_child(p)
	p.global_position = at
	p.emitting = true
	get_tree().create_timer(2.5).timeout.connect(p.queue_free)
