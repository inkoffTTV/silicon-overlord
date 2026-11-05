extends RigidBody3D
## A shipping crate from `production.crates` (WORLD agent): a taped cardboard carton with the product colour band,
## a printed label (product + units) and FRAGILE stamps. Grabbable (LMB or E) and interactable (kind "crate").
## State machine used by shipping.gd: idle -> shipping (in the van, waiting for the server) -> shipped / back to idle.

const Mats := preload("res://world/lib/mats.gd")
const Meshes := preload("res://world/lib/meshes.gd")
const SIZE := Vector3(0.52, 0.36, 0.4)

var crate_id := ""
var product_id := ""
var product_name := ""
var units := 0
var colour := Color(0.5, 0.5, 0.5)
var ship_state := "idle"     # idle | shipping | shipped | vanishing
var gone_from_state := false
var labels: Array[Label3D] = []
var vis: Node3D
var _last_hit := 0.0

func setup(c: Dictionary, pname: String, col: Color) -> void:
	crate_id = str(c.get("id", ""))
	product_id = str(c.get("productId", ""))
	product_name = pname
	colour = col
	units = int(c.get("units", 0))
	name = "Crate_" + crate_id.validate_node_name()
	add_to_group("grabbable")
	add_to_group("interactable")
	add_to_group("ship_crate")
	set_meta("kind", "crate")
	set_meta("id", crate_id)
	set_meta("prompt", "Carry to the van")
	set_meta("prop", "ship_crate")
	set_meta("e_grabs", true)
	mass = 6.0
	angular_damp = 0.8
	linear_damp = 0.05
	var pm := PhysicsMaterial.new()
	pm.friction = 0.85
	pm.bounce = 0.05
	physics_material_override = pm
	contact_monitor = true
	max_contacts_reported = 2
	body_entered.connect(_on_hit)
	_build()
	set_units(units)

func _build() -> void:
	vis = Node3D.new()
	vis.name = "Vis"
	add_child(vis)
	var s := SIZE
	var card := Mats.m("cardboard", Color(1.0, 0.97, 0.92))
	_box(s, Vector3.ZERO, card, 0.02)
	# product colour band around the box
	var band := Mats.m("plastic_white", Color.WHITE, {"albedo": colour, "albedo2": colour.darkened(0.2), "roughness_base": 0.7, "grime": 0.3})
	_box(Vector3(s.x + 0.004, 0.07, s.z + 0.004), Vector3(0, -s.y * 0.5 + 0.07, 0), band, 0.0, false)
	# brown tape across the top
	_box(Vector3(0.07, 0.003, s.z + 0.006), Vector3(0, s.y * 0.5 + 0.001, 0), Mats.m("plastic_orange", Color(0.75, 0.55, 0.32), {"roughness_base": 0.25}), 0.0, false)
	_box(Vector3(0.07, s.y * 0.35, 0.003), Vector3(0, s.y * 0.32, s.z * 0.5 + 0.001), Mats.m("plastic_orange", Color(0.75, 0.55, 0.32), {"roughness_base": 0.25}), 0.0, false)
	_box(Vector3(0.07, s.y * 0.35, 0.003), Vector3(0, s.y * 0.32, -s.z * 0.5 - 0.001), Mats.m("plastic_orange", Color(0.75, 0.55, 0.32), {"roughness_base": 0.25}), 0.0, false)
	# shipping labels on the two long sides + one end
	for side in [[Vector3(0, 0.015, s.z * 0.5 + 0.002), 0.0], [Vector3(0, 0.015, -s.z * 0.5 - 0.002), 180.0], [Vector3(s.x * 0.5 + 0.002, 0.015, 0), 90.0]]:
		var g := Node3D.new()
		g.position = side[0]
		g.rotation_degrees.y = side[1]
		vis.add_child(g)
		var paper := MeshInstance3D.new()
		paper.mesh = Meshes.cbox(Vector3(0.24, 0.13, 0.002), 0.0)
		paper.material_override = Mats.m("paper", Color(1.1, 1.1, 1.05))
		paper.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		paper.position = Vector3(-0.07 if side[1] != 90.0 else 0.0, 0.02, 0)
		g.add_child(paper)
		var l := Label3D.new()
		l.font_size = 40
		l.pixel_size = 0.0011
		l.modulate = Color(0.08, 0.08, 0.1)
		l.shaded = true
		l.outline_size = 0
		l.position = paper.position + Vector3(0, 0, 0.0016)
		l.width = 200.0
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.line_spacing = -6.0
		if ResourceLoader.exists("res://ui/fonts/Inter-Bold.ttf"):
			l.font = load("res://ui/fonts/Inter-Bold.ttf")
		g.add_child(l)
		labels.append(l)
		if side[1] != 90.0:
			# red FRAGILE stamp + "this way up" arrows
			var st := Label3D.new()
			st.text = "FRAGILE"
			st.font_size = 44
			st.pixel_size = 0.0011
			st.modulate = Color(0.75, 0.1, 0.08)
			st.shaded = true
			st.rotation_degrees.z = 12
			st.position = Vector3(0.15, 0.05, 0.0016)
			if ResourceLoader.exists("res://ui/fonts/Inter-Bold.ttf"):
				st.font = load("res://ui/fonts/Inter-Bold.ttf")
			g.add_child(st)
			var ar := Label3D.new()
			ar.text = "↑↑"
			ar.font_size = 64
			ar.pixel_size = 0.0011
			ar.modulate = Color(0.1, 0.1, 0.1)
			ar.shaded = true
			ar.position = Vector3(0.16, -0.035, 0.0016)
			g.add_child(ar)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = s
	cs.shape = bs
	add_child(cs)

func set_units(n: int) -> void:
	units = n
	var pn := product_name.to_upper()
	if pn.length() > 14:
		pn = pn.substr(0, 13) + "."
	for l in labels:
		l.text = "%s\n× %s" % [pn, _fmt(n)]

static func _fmt(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out

func _box(size: Vector3, pos: Vector3, mat: Material, bevel: float, shadow: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = Meshes.cbox(size, bevel)
	mi.material_override = mat
	mi.position = pos
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	vis.add_child(mi)
	return mi

func _on_hit(_other: Node) -> void:
	var now := Time.get_ticks_msec() * 0.001
	if now - _last_hit < 0.25 or linear_velocity.length() < 1.2:
		return
	_last_hit = now
	Sfx.play("impact_cardboard", global_position, clampf(linear_velocity.length() * 3.0 - 14.0, -14.0, 0.0))

## Shrink + fade away (auto-shipped or gone). Frees itself.
func vanish() -> void:
	if ship_state == "vanishing":
		return
	ship_state = "vanishing"
	freeze = true
	collision_layer = 0
	collision_mask = 0
	remove_from_group("interactable")
	remove_from_group("grabbable")
	var tw := create_tween()
	tw.tween_property(vis, "scale", Vector3(1.08, 1.08, 1.08), 0.12)
	tw.tween_property(vis, "scale", Vector3(0.02, 0.02, 0.02), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)
