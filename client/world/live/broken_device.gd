extends RigidBody3D
## A customer's broken gadget (WORLD agent, iteration 3): a grabbable physics prop tagged with its repair order.
## Built from the free-form order strings (device + fault, see story_state.gd): phone, tablet, watch, laptop, handheld,
## flip phone; faults show as a cracked screen, a swollen battery lifting the back, lint in the port, water drops, a
## missing button, a cracked lens. A paper repair ticket with the order number hangs off it. set_fixed(true) = clean
## glowing screen + green FIXED sticker. Lies flat with the screen on local +Y.
## repair_shop.gd owns it: sets meta kind/id/prompt (interactable) by order status + where it lies, snaps it into the
## bench holder (frozen) and hands it to the customer.

const Mats := preload("res://world/lib/mats.gd")
const Meshes := preload("res://world/lib/meshes.gd")
const Story := preload("res://world/live/story_state.gd")

const SIZES := {
	"phone": Vector3(0.105, 0.019, 0.212), "tablet": Vector3(0.29, 0.016, 0.205), "watch": Vector3(0.062, 0.022, 0.072),
	"laptop": Vector3(0.36, 0.03, 0.25), "handheld": Vector3(0.23, 0.035, 0.105), "flip": Vector3(0.07, 0.03, 0.135),
}
const MASS := {"phone": 0.25, "tablet": 0.5, "watch": 0.12, "laptop": 1.8, "handheld": 0.35, "flip": 0.16}
const BODY_COLS := [Color(0.08, 0.08, 0.09), Color(0.72, 0.73, 0.76), Color(0.85, 0.42, 0.55), Color(0.2, 0.35, 0.62),
	Color(0.85, 0.78, 0.6), Color(0.25, 0.55, 0.4), Color(0.9, 0.9, 0.9), Color(0.75, 0.22, 0.18)]

var order_id := ""
var device := "phone"
var fault := "screen"
var kind := "phone"
var fault_kind := "screen"
var fixed := false
var size := Vector3(0.105, 0.019, 0.212)
var vis: Node3D
var _broken: Node3D
var _fixed_vis: Node3D
var _screen_mat: ShaderMaterial
var _screen_node: MeshInstance3D
var _crack_root: Node3D
var _glitch_mat: ShaderMaterial
var ticket: Label3D
## where the shop wants it: "counter" | "bench" | "free" | "hand" | "gone"
var place := "free"
var _last_hit := 0.0

func setup(order: Dictionary) -> void:
	order_id = str(order.get("id", ""))
	device = str(order.get("device", "phone"))
	fault = str(order.get("fault", ""))
	kind = Story.device_kind(device)
	fault_kind = Story.fault_kind(fault, str(order.get("partId", "")))
	size = SIZES.get(kind, SIZES.phone)
	name = "Device_" + order_id.validate_node_name()
	add_to_group("grabbable")
	add_to_group("repair_device")
	set_meta("prop", "repair_device")
	set_meta("order_id", order_id)
	mass = MASS.get(kind, 0.3)
	continuous_cd = true
	angular_damp = 1.2
	linear_damp = 0.1
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	pm.bounce = 0.02
	physics_material_override = pm
	contact_monitor = true
	max_contacts_reported = 2
	body_entered.connect(_on_hit)
	_build(order)
	set_fixed(str(order.get("status", "")) in ["ready", "paid"])

func _rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash(order_id + device)
	return r

func _build(order: Dictionary) -> void:
	vis = Node3D.new()
	vis.name = "Vis"
	add_child(vis)
	var rng := _rng()
	var col: Color = BODY_COLS[rng.randi() % BODY_COLS.size()]
	var body_m := Mats.m("plastic_black", Color.WHITE, {"albedo": col, "albedo2": col.darkened(0.2), "roughness_base": 0.35, "grime": 0.45, "edge_wear": 0.5, "edge_color": col.lightened(0.4)})
	var s := size
	_screen_mat = Mats.screen(3, Color(0.4, 0.8, 1.0), 1.2, rng.randf() * 10.0)
	match kind:
		"laptop":
			_box(vis, Vector3(s.x, 0.02, s.z), Vector3(0, -0.005, 0), body_m, 0.006)
			_box(vis, Vector3(s.x * 0.9, 0.002, s.z * 0.45), Vector3(0, 0.006, 0.04), Mats.m("plastic_black", Color(1.6, 1.6, 1.6)), 0.0)  # keys
			# lid on a hinge at the back edge: -105 deg = open (a "button" fault = a wobbly half-shut hinge)
			var ang := -105.0 if fault_kind != "button" else -62.0
			var lid := Node3D.new()
			lid.position = Vector3(0, 0.005, -s.z * 0.5)
			lid.rotation_degrees.x = ang
			vis.add_child(lid)
			_box(lid, Vector3(s.x, 0.012, s.z), Vector3(0, 0.006, s.z * 0.5), body_m, 0.006)
			_screen_on(lid, Vector2(s.x * 0.92, s.z * 0.86), Vector3(0, -0.0008, s.z * 0.5), Vector3(90, 0, 0))
			_shape(Vector3(s.x, 0.02, s.z), Vector3(0, -0.005, 0))
			var lc: Vector3 = lid.position + Basis(Vector3.RIGHT, deg_to_rad(ang)) * Vector3(0, 0.006, s.z * 0.5)
			_shape(Vector3(s.x, 0.012, s.z), lc, Vector3(ang, 0, 0))
		"watch":
			_box(vis, Vector3(0.05, 0.016, 0.058), Vector3.ZERO, body_m, 0.008)
			var strap := Mats.m("rubber", Color(4, 4, 4), {"albedo": col.darkened(0.5)})
			for sz in [-1.0, 1.0]:
				_box(vis, Vector3(0.036, 0.006, 0.07), Vector3(0, -0.004, sz * 0.06), strap, 0.002)
			_screen_on(vis, Vector2(0.042, 0.048), Vector3(0, 0.0085, 0), Vector3(-90, 0, 0))
			_shape(Vector3(0.05, 0.02, 0.16), Vector3.ZERO)
		"handheld":
			_box(vis, Vector3(s.x, s.y, s.z), Vector3.ZERO, body_m, 0.02)
			_screen_on(vis, Vector2(s.x * 0.45, s.z * 0.7), Vector3(0, s.y * 0.5 + 0.001, 0), Vector3(-90, 0, 0))
			var btn := Mats.m("plastic_white", Color(1.2, 1.2, 1.2))
			_box(vis, Vector3(0.03, 0.008, 0.01), Vector3(-s.x * 0.36, s.y * 0.5 + 0.003, 0), Mats.m("plastic_black"), 0.002)
			_box(vis, Vector3(0.01, 0.008, 0.03), Vector3(-s.x * 0.36, s.y * 0.5 + 0.003, 0), Mats.m("plastic_black"), 0.002)
			for i in 2:
				if fault_kind == "button" and i == 1:
					continue
				_cyl(vis, 0.008, 0.008, Vector3(s.x * 0.33 + i * 0.022, s.y * 0.5 + 0.003, -0.01 + i * 0.02), Mats.m("metal_red", Color(1.4, 1.4, 1.4)))
			_box(vis, Vector3(0.012, 0.004, 0.006), Vector3(0, s.y * 0.5 + 0.002, s.z * 0.42), btn, 0.001)
			_shape(s, Vector3.ZERO)
		"flip":
			_box(vis, Vector3(s.x, s.y * 0.5, s.z), Vector3(0, -s.y * 0.25, 0), body_m, 0.01)
			_box(vis, Vector3(s.x, s.y * 0.5, s.z), Vector3(0, s.y * 0.25 + 0.001, 0), body_m, 0.01)
			_box(vis, Vector3(s.x * 0.6, 0.002, s.z * 0.3), Vector3(0, s.y * 0.5 + 0.002, -s.z * 0.18), Mats.m("plastic_black"), 0.0)
			_screen_on(vis, Vector2(s.x * 0.5, s.z * 0.22), Vector3(0, s.y * 0.5 + 0.0035, -s.z * 0.18), Vector3(-90, 0, 0))
			_cyl(vis, 0.006, 0.03, Vector3(s.x * 0.3, s.y * 0.2, -s.z * 0.5 - 0.012), body_m, Vector3(90, 0, 0))  # antenna stub
			_shape(s, Vector3.ZERO)
		_:  # phone, tablet
			_box(vis, s, Vector3.ZERO, body_m, 0.008 if kind == "phone" else 0.01)
			var sc := Vector2(s.x * 0.88, s.z * (0.9 if kind == "phone" else 0.86))
			_box(vis, Vector3(s.x * 0.95, 0.002, s.z * 0.96), Vector3(0, s.y * 0.5, 0), Mats.m("plastic_black", Color(0.8, 0.8, 0.8)), 0.003)
			_screen_on(vis, sc, Vector3(0, s.y * 0.5 + 0.0015, 0), Vector3(-90, 0, 0))
			# camera bump on the back
			_box(vis, Vector3(0.034, 0.005, 0.034), Vector3(-s.x * 0.28, -s.y * 0.5 - 0.002, -s.z * 0.36), Mats.m("plastic_black"), 0.004)
			var lens_m := Mats.m("tv_black", Color.WHITE, {"roughness_base": 0.05})
			_cyl(vis, 0.008, 0.004, Vector3(-s.x * 0.28, -s.y * 0.5 - 0.005, -s.z * 0.33), lens_m, Vector3(180, 0, 0))
			_shape(s, Vector3.ZERO)
	_broken = Node3D.new()
	_broken.name = "Broken"
	vis.add_child(_broken)
	_build_fault()
	_fixed_vis = Node3D.new()
	_fixed_vis.name = "Fixed"
	vis.add_child(_fixed_vis)
	var top := _top_y()
	# green FIXED sticker
	_box(_fixed_vis, Vector3(0.05, 0.002, 0.022), Vector3(s.x * 0.18, top + 0.002, s.z * 0.38), Mats.glow(Color(0.2, 0.85, 0.35), 0.6), 0.0)
	var fl := _lbl(_fixed_vis, "FIXED", Vector3(s.x * 0.18, top + 0.0035, s.z * 0.38), 22, Color(0.02, 0.15, 0.04), Vector3(-90, 0, 0))
	fl.pixel_size = 0.0008
	# paper ticket on a string: "#12 SCREEN"
	var t := Node3D.new()
	t.name = "Ticket"
	t.position = Vector3(s.x * 0.5 + 0.03, top - s.y * 0.5, -s.z * 0.3)
	t.rotation_degrees.y = -25
	vis.add_child(t)
	_box(t, Vector3(0.05, 0.0015, 0.032), Vector3.ZERO, Mats.m("paper", Color(1.1, 1.05, 0.85)), 0.0)
	_box(t, Vector3(0.035, 0.001, 0.002), Vector3(-0.035, 0.0, 0.0), Mats.m("plastic_white", Color(0.6, 0.15, 0.1)), 0.0)
	var num := order_id.get_slice("_", order_id.get_slice_count("_") - 1)
	if num.length() > 4:
		num = num.right(4)
	ticket = _lbl(t, "#%s\n%s" % [num, fault_kind.to_upper()], Vector3(0, 0.0012, 0), 20, Color(0.1, 0.1, 0.15), Vector3(-90, 0, 0))
	ticket.pixel_size = 0.0007
	ticket.line_spacing = -4.0

func _top_y() -> float:
	return size.y * 0.5 if kind != "laptop" else 0.005

func _build_fault() -> void:
	var s := size
	var top := _top_y()
	var rng := _rng()
	match fault_kind:
		"screen", "other", "camera", "speaker":
			if fault_kind in ["screen", "other"] and _screen_node:
				# star crack on the screen glass (screen quad frame: XY plane, facing +Z)
				var qs: Vector2 = (_screen_node.mesh as QuadMesh).size
				var cr := Node3D.new()
				cr.position = Vector3(rng.randf_range(-0.25, 0.25) * qs.x, rng.randf_range(-0.25, 0.3) * qs.y, 0.0007)
				_screen_node.add_child(cr)
				_crack_root = cr
				var crack := Mats.unlit(Color(0.85, 0.92, 1.0, 0.85))
				var reach := minf(qs.x, qs.y) * 0.95
				for i in 9:
					var a := TAU * i / 9.0 + rng.randf_range(-0.25, 0.25)
					var l := reach * rng.randf_range(0.35, 1.0)
					var mi := _box(cr, Vector3(0.0018, l, 0.0005), Vector3(sin(a), cos(a), 0) * l * 0.5, crack, 0.0)
					mi.rotation.z = -a
				_box(cr, Vector3(0.012, 0.012, 0.0007), Vector3.ZERO, Mats.unlit(Color(0.95, 0.97, 1.0)), 0.0).rotation.z = 0.6
			if fault_kind == "camera":
				_box(_broken, Vector3(0.02, 0.001, 0.0015), Vector3(-s.x * 0.28, -s.y * 0.5 - 0.0075, -s.z * 0.33), Mats.unlit(Color(0.9, 0.95, 1.0)), 0.0).rotation.y = 0.7
			if fault_kind == "speaker":
				_box(_broken, Vector3(s.x * 0.5, 0.003, 0.008), Vector3(0, top + 0.003, s.z * 0.45), Mats.m("cardboard"), 0.0)  # taped-over grille
		"glitch":
			# software glitch: the screen shows stripy garbage (screen material tinted magenta, code mode)
			if _screen_node:
				var gm := Mats.screen(0, Color(1.0, 0.3, 0.8), 0.9, 7.0)
				_glitch_mat = gm
		"battery":
			# swollen battery: the back cover bulges and pops open on one side
			var bulge := MeshInstance3D.new()
			bulge.mesh = Meshes.sphere(0.5, 12)
			bulge.scale = Vector3(s.x * 0.8, 0.03, s.z * 0.7)
			bulge.position = Vector3(0, -s.y * 0.5, 0)
			bulge.material_override = Mats.m("metal", Color(1.1, 1.1, 1.15))
			_broken.add_child(bulge)
			var back := _box(_broken, Vector3(s.x * 0.96, 0.003, s.z * 0.96), Vector3(0, -s.y * 0.5 - 0.012, 0), Mats.m("plastic_black", Color(1.4, 1.4, 1.4)), 0.003)
			back.rotation_degrees = Vector3(0, 0, 4)
		"port":
			_box(_broken, Vector3(0.016, 0.006, 0.01), Vector3(0, 0, s.z * 0.5 + 0.004), Mats.m("fabric", Color(1.6, 1.4, 1.1)), 0.003)  # lint ball
			var bent := _box(_broken, Vector3(0.012, 0.004, 0.03), Vector3(0, 0, s.z * 0.5 + 0.018), Mats.m("plastic_white"), 0.002)
			bent.rotation_degrees = Vector3(0, 35, 0)  # stuck cable plug
		"water":
			var drop := Mats.glass(Color(0.55, 0.75, 1.0, 0.55))
			for i in 6:
				var d := MeshInstance3D.new()
				d.mesh = Meshes.sphere(rng.randf_range(0.004, 0.008), 6)
				d.material_override = drop
				d.scale = Vector3(1, 0.45, 1)
				d.position = Vector3(rng.randf_range(-0.4, 0.4) * s.x, top + 0.002, rng.randf_range(-0.45, 0.45) * s.z)
				_broken.add_child(d)
			_box(_broken, Vector3(0.02, 0.006, 0.006), Vector3(s.x * 0.2, top + 0.004, -s.z * 0.2), Mats.m("plastic_orange", Color(0.6, 1.4, 0.4)), 0.002)  # a noodle
		"button":
			_box(_broken, Vector3(0.004, 0.012, 0.03), Vector3(s.x * 0.5 + 0.004, 0, -s.z * 0.15), Mats.m("plastic_orange", Color(1.2, 1.0, 0.7)), 0.001)  # tape

func _screen_on(parent: Node3D, sz: Vector2, pos: Vector3, rot: Vector3) -> void:
	var mi := MeshInstance3D.new()
	_screen_node = mi
	mi.name = "Screen"
	mi.mesh = Meshes.quad(sz)
	mi.material_override = _screen_mat
	mi.position = pos
	mi.rotation_degrees = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)

func set_fixed(on: bool) -> void:
	fixed = on
	if _broken:
		_broken.visible = not on
	if _crack_root:
		_crack_root.visible = not on
	if _fixed_vis:
		_fixed_vis.visible = on
	if _glitch_mat and _screen_node:
		_screen_node.material_override = _screen_mat if on else _glitch_mat
	if _screen_mat:
		# broken: dark glass with a faint dead glow; fixed: bright home screen
		_screen_mat.set_shader_parameter("energy", 1.5 if on else 0.08)
		_screen_mat.set_shader_parameter("tint", Color(0.45, 0.85, 1.0) if on else Color(0.3, 0.3, 0.35))

## Interactable metadata (the shop decides): kind "" = not interactable.
func set_interact(ia_kind: String, prompt: String, e_grabs: bool) -> void:
	if ia_kind == "":
		if is_in_group("interactable"):
			remove_from_group("interactable")
		return
	set_meta("kind", ia_kind)
	set_meta("id", order_id)
	set_meta("prompt", prompt)
	set_meta("e_grabs", e_grabs)
	if not is_in_group("interactable"):
		add_to_group("interactable")

func _on_hit(_other: Node) -> void:
	var now := Time.get_ticks_msec() * 0.001
	if now - _last_hit < 0.25 or linear_velocity.length() < 1.0:
		return
	_last_hit = now
	Sfx.play("impact_soft" if kind != "laptop" else "impact_metal", global_position, clampf(linear_velocity.length() * 3.0 - 16.0, -16.0, -2.0))

# ------------------------------------------------------------------ helpers
func _box(parent: Node3D, sz: Vector3, pos: Vector3, mat: Material, bevel: float = 0.004) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = Meshes.cbox(sz, bevel)
	mi.material_override = mat
	mi.position = pos
	if sz.y < 0.004 or sz.x < 0.004:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

func _cyl(parent: Node3D, r: float, h: float, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = Meshes.cyl(r, h, 10)
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot
	parent.add_child(mi)
	return mi

func _lbl(parent: Node3D, text: String, pos: Vector3, px: int, col: Color, rot: Vector3) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.rotation_degrees = rot
	l.font_size = px
	l.pixel_size = 0.001
	l.modulate = col
	l.shaded = true
	l.outline_size = 0
	if ResourceLoader.exists("res://ui/fonts/Inter-Bold.ttf"):
		l.font = load("res://ui/fonts/Inter-Bold.ttf")
	parent.add_child(l)
	return l

func _shape(sz: Vector3, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = sz
	cs.shape = bs
	cs.position = pos
	cs.rotation_degrees = rot
	add_child(cs)
