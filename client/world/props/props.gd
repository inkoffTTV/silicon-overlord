extends RefCounted
## Grabbable physics props (RigidBody3D in group "grabbable"). Chunky, weighty, toy-like.
## Add a new prop: add a `match` branch in make() that builds meshes with _box/_cyl and returns mass.
## See docs/VISUAL_STYLE.md "How to add props".

const Mats := preload("res://world/lib/mats.gd")
const Meshes := preload("res://world/lib/meshes.gd")

const KINDS := ["box_s", "box_m", "box_l", "box_heavy", "mug", "can", "phone_proto", "phone_board", "wrench",
	"screwdriver", "hammer", "toolbox", "paint_can", "pizza_box", "book", "tape_roll", "cone", "bottle",
	"keyboard", "ball", "chair", "stool", "crate", "drill", "battery_pack", "router", "trash_bin"]

static var _pm: PhysicsMaterial

static func make(kind: String, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO, variant: int = 0) -> RigidBody3D:
	var rb := RigidBody3D.new()
	rb.name = "Prop_" + kind
	rb.position = pos
	rb.rotation_degrees = rot_deg
	rb.add_to_group("grabbable")
	rb.set_meta("prop", kind)
	if _pm == null:
		_pm = PhysicsMaterial.new()
		_pm.friction = 0.8
		_pm.bounce = 0.08
	rb.physics_material_override = _pm
	rb.can_sleep = true
	rb.angular_damp = 0.6
	rb.linear_damp = 0.05
	var mass := 1.0
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind) + variant * 7919
	match kind:
		"box_s", "box_m", "box_l", "box_heavy":
			var sizes := {"box_s": Vector3(0.32, 0.22, 0.26), "box_m": Vector3(0.5, 0.36, 0.4), "box_l": Vector3(0.7, 0.5, 0.55), "box_heavy": Vector3(0.6, 0.45, 0.5)}
			var s: Vector3 = sizes[kind] * (1.0 + rng.randf_range(-0.1, 0.1))
			var tint := Color(1, 1, 1).lerp(Color(0.8, 0.85, 0.75), rng.randf() * 0.6)
			_box(rb, s, Vector3.ZERO, Mats.m("cardboard", tint), 0.02)
			if kind == "box_heavy":
				_box(rb, Vector3(0.002, 0.12, 0.3), Vector3(s.x * 0.5 + 0.001, 0.05, 0), Mats.glow(Color(0.9, 0.25, 0.1), 0.2), 0.0, false)
			elif rng.randf() < 0.5:
				_box(rb, Vector3(0.002, 0.1, 0.14), Vector3(s.x * 0.5 + 0.001, 0.02, -s.z * 0.2), Mats.m("paper"), 0.0, false)
			_shape(rb, s, Vector3.ZERO)
			mass = {"box_s": 1.2, "box_m": 3.0, "box_l": 6.0, "box_heavy": 28.0}[kind]
		"crate":
			var s := Vector3(0.6, 0.4, 0.45)
			for y in [-0.12, 0.08]:
				for z in [-1, 1]:
					_box(rb, Vector3(s.x, 0.14, 0.03), Vector3(0, y, z * (s.z * 0.5 - 0.015)), Mats.m("plywood"), 0.006)
				for x in [-1, 1]:
					_box(rb, Vector3(0.03, 0.14, s.z), Vector3(x * (s.x * 0.5 - 0.015), y, 0), Mats.m("plywood"), 0.006)
			_box(rb, Vector3(s.x, 0.02, s.z), Vector3(0, -s.y * 0.5 + 0.01, 0), Mats.m("plywood"), 0.004)
			_shape(rb, s, Vector3.ZERO)
			mass = 5.0
		"mug":
			var cols := [Color(0.8, 0.79, 0.74), Color(0.55, 0.12, 0.1), Color(0.15, 0.3, 0.55), Color(0.85, 0.6, 0.1), Color(0.2, 0.2, 0.22)]
			var c: Color = cols[variant % cols.size()]
			_cyl(rb, 0.042, 0.1, Vector3.ZERO, Mats.m("ceramic", c * Color(1.15, 1.15, 1.15)))
			_cyl(rb, 0.036, 0.004, Vector3(0, 0.046, 0), Mats.m("wood_dark"), 12)
			_box(rb, Vector3(0.012, 0.06, 0.04), Vector3(0.05, 0.0, 0), Mats.m("ceramic", c * Color(1.15, 1.15, 1.15)), 0.005)
			_shape(rb, Vector3(0.085, 0.1, 0.085), Vector3.ZERO)
			mass = 0.35
		"can":
			var cols := [Color(0.75, 0.1, 0.08), Color(0.1, 0.45, 0.2), Color(0.85, 0.75, 0.15), Color(0.12, 0.25, 0.65)]
			_cyl(rb, 0.033, 0.12, Vector3.ZERO, Mats.m("metal_red", Color.WHITE, {"albedo": cols[variant % cols.size()]}))
			_cyl(rb, 0.03, 0.006, Vector3(0, 0.061, 0), Mats.m("metal"), 12)
			_cylshape(rb, 0.033, 0.12)
			mass = 0.33
		"bottle":
			_cyl(rb, 0.035, 0.2, Vector3(0, -0.02, 0), Mats.glass(Color(0.25, 0.45, 0.25, 0.55)), 12)
			_cyl(rb, 0.014, 0.07, Vector3(0, 0.11, 0), Mats.glass(Color(0.25, 0.45, 0.25, 0.55)), 10)
			_box(rb, Vector3(0.071, 0.08, 0.071), Vector3(0, -0.03, 0), Mats.m("paper", Color(0.9, 0.8, 0.5)), 0.0, false)
			_cylshape(rb, 0.035, 0.27)
			mass = 0.5
		"phone_proto":
			var s := Vector3(0.075, 0.012, 0.155)
			var cols := [Color(0.08, 0.08, 0.09), Color(0.7, 0.7, 0.72), Color(0.6, 0.45, 0.3), Color(0.15, 0.25, 0.45)]
			_box(rb, s, Vector3.ZERO, Mats.m("plastic_black", cols[variant % cols.size()] * Color(12, 12, 12)), 0.006)
			var scr := MeshInstance3D.new()
			scr.mesh = Meshes.quad(Vector2(0.066, 0.142))
			scr.material_override = Mats.screen(3 if variant % 2 == 0 else 0, Color(0.4, 0.7, 1.0), 0.9, variant)
			scr.rotation_degrees.x = -90
			scr.position = Vector3(0, s.y * 0.5 + 0.0012, 0)
			rb.add_child(scr)
			_box(rb, Vector3(0.022, 0.004, 0.022), Vector3(-0.018, -0.008, -0.055), Mats.m("plastic_black"), 0.003)
			_shape(rb, s, Vector3.ZERO)
			mass = 0.18
			rb.continuous_cd = true
		"phone_board":
			_box(rb, Vector3(0.07, 0.006, 0.15), Vector3.ZERO, Mats.m("metal_green", Color(0.6, 1.4, 0.7)), 0.002)
			for i in 6:
				_box(rb, Vector3(0.014, 0.006, 0.014), Vector3(rng.randf_range(-0.025, 0.025), 0.005, rng.randf_range(-0.06, 0.06)), Mats.m("plastic_black"), 0.002)
			_box(rb, Vector3(0.05, 0.008, 0.06), Vector3(0, -0.006, 0.03), Mats.m("metal"), 0.002)
			_shape(rb, Vector3(0.07, 0.016, 0.15), Vector3.ZERO)
			mass = 0.1
			rb.continuous_cd = true
		"wrench":
			_box(rb, Vector3(0.24, 0.012, 0.028), Vector3.ZERO, Mats.m("metal"), 0.005)
			_box(rb, Vector3(0.05, 0.014, 0.05), Vector3(0.13, 0, 0), Mats.m("metal"), 0.008)
			_cyl(rb, 0.022, 0.014, Vector3(-0.13, 0, 0), Mats.m("metal"), 12)
			_shape(rb, Vector3(0.3, 0.016, 0.05), Vector3.ZERO)
			mass = 0.4
			rb.continuous_cd = true
		"screwdriver":
			var c: Color = [Color(0.85, 0.25, 0.1), Color(0.95, 0.75, 0.1), Color(0.2, 0.4, 0.85)][variant % 3]
			_cyl(rb, 0.016, 0.1, Vector3(-0.05, 0, 0), Mats.m("plastic_orange", c * Color(1.2, 1.2, 1.2)), Vector3(0, 0, 90))
			_cyl(rb, 0.004, 0.11, Vector3(0.055, 0, 0), Mats.m("metal"), Vector3(0, 0, 90))
			_shape(rb, Vector3(0.21, 0.03, 0.03), Vector3.ZERO)
			mass = 0.12
			rb.continuous_cd = true
		"hammer":
			_box(rb, Vector3(0.3, 0.03, 0.025), Vector3.ZERO, Mats.m("wood"), 0.008)
			_box(rb, Vector3(0.04, 0.03, 0.12), Vector3(0.15, 0, 0), Mats.m("steel_dark"), 0.008)
			_shape(rb, Vector3(0.34, 0.032, 0.12), Vector3(0.0, 0, 0))
			mass = 0.7
		"drill":
			_box(rb, Vector3(0.2, 0.08, 0.06), Vector3(0, 0.08, 0), Mats.m("metal_yellow"), 0.02)
			_box(rb, Vector3(0.05, 0.14, 0.05), Vector3(-0.04, -0.02, 0), Mats.m("plastic_black"), 0.015)
			_box(rb, Vector3(0.09, 0.05, 0.07), Vector3(-0.04, -0.1, 0), Mats.m("plastic_black"), 0.015)
			_cyl(rb, 0.005, 0.07, Vector3(0.13, 0.08, 0), Mats.m("metal"), Vector3(0, 0, 90))
			_shape(rb, Vector3(0.22, 0.26, 0.07), Vector3(0, -0.01, 0))
			mass = 1.6
		"toolbox":
			var s := Vector3(0.5, 0.22, 0.24)
			_box(rb, s, Vector3.ZERO, Mats.m("metal_red"), 0.02)
			_box(rb, Vector3(s.x + 0.006, 0.02, s.z + 0.006), Vector3(0, 0.04, 0), Mats.m("metal_red", Color(0.7, 0.7, 0.7)), 0.006)
			_box(rb, Vector3(0.22, 0.025, 0.03), Vector3(0, s.y * 0.5 + 0.04, 0), Mats.m("plastic_black"), 0.01)
			_box(rb, Vector3(0.02, 0.05, 0.02), Vector3(-0.1, s.y * 0.5 + 0.015, 0), Mats.m("plastic_black"), 0.005)
			_box(rb, Vector3(0.02, 0.05, 0.02), Vector3(0.1, s.y * 0.5 + 0.015, 0), Mats.m("plastic_black"), 0.005)
			_shape(rb, s, Vector3.ZERO)
			mass = 9.0
		"paint_can":
			_cyl(rb, 0.085, 0.19, Vector3.ZERO, Mats.m("metal"), 20)
			_cyl(rb, 0.0855, 0.11, Vector3(0, -0.01, 0), Mats.m("paper", [Color(0.9, 0.4, 0.3), Color(0.4, 0.6, 0.9), Color(0.9, 0.9, 0.6)][variant % 3]), 20)
			_cylshape(rb, 0.085, 0.19)
			mass = 3.5
		"pizza_box":
			_box(rb, Vector3(0.4, 0.045, 0.4), Vector3.ZERO, Mats.m("cardboard", Color(1.15, 1.1, 1.0), {"pattern": 0}), 0.008)
			_box(rb, Vector3(0.18, 0.002, 0.12), Vector3(0.0, 0.023, 0.0), Mats.m("paper", Color(0.9, 0.2, 0.15)), 0.0, false)
			_shape(rb, Vector3(0.4, 0.045, 0.4), Vector3.ZERO)
			mass = 0.6
		"book":
			var c: Color = [Color(0.5, 0.1, 0.1), Color(0.12, 0.2, 0.4), Color(0.15, 0.35, 0.2), Color(0.55, 0.45, 0.2)][variant % 4]
			_box(rb, Vector3(0.17, 0.04, 0.24), Vector3.ZERO, Mats.m("fabric_blue", Color.WHITE, {"albedo": c, "pattern": 0}), 0.006)
			_box(rb, Vector3(0.16, 0.034, 0.005), Vector3(0.0, 0, 0.118), Mats.m("paper"), 0.0, false)
			_shape(rb, Vector3(0.17, 0.04, 0.24), Vector3.ZERO)
			mass = 0.5
		"tape_roll":
			_cyl(rb, 0.05, 0.05, Vector3.ZERO, Mats.m("cardboard", Color(1.3, 1.25, 1.1), {"pattern": 0, "roughness_base": 0.3}), Vector3(90, 0, 0), 16)
			_cyl(rb, 0.03, 0.052, Vector3.ZERO, Mats.m("cardboard"), Vector3(90, 0, 0), 12)
			_shape(rb, Vector3(0.1, 0.1, 0.05), Vector3.ZERO)
			mass = 0.25
		"cone":
			_cyl(rb, 0.13, 0.42, Vector3(0, 0.02, 0), Mats.m("plastic_orange"), Vector3.ZERO, 16, 0.025)
			_cyl(rb, 0.095, 0.06, Vector3(0, 0.06, 0), Mats.m("plastic_white"), Vector3.ZERO, 16, 0.075)
			_box(rb, Vector3(0.32, 0.03, 0.32), Vector3(0, -0.2, 0), Mats.m("plastic_orange", Color(0.8, 0.8, 0.8)), 0.01)
			_shape(rb, Vector3(0.3, 0.44, 0.3), Vector3(0, 0.0, 0))
			mass = 1.2
		"keyboard":
			_box(rb, Vector3(0.44, 0.03, 0.16), Vector3.ZERO, Mats.m("plastic_beige"), 0.01)
			for r in 4:
				_box(rb, Vector3(0.38 - r * 0.02, 0.012, 0.025), Vector3(0, 0.02, -0.05 + r * 0.032), Mats.m("plastic_beige", Color(0.85, 0.85, 0.85)), 0.003)
			_shape(rb, Vector3(0.44, 0.04, 0.16), Vector3.ZERO)
			mass = 0.9
		"ball":
			var sm := MeshInstance3D.new()
			sm.mesh = Meshes.sphere(0.12, 16)
			sm.material_override = Mats.m("plastic_orange", Color(0.9, 0.6, 0.4), {"roughness_base": 0.85, "pattern": 6})
			rb.add_child(sm)
			var cs := CollisionShape3D.new()
			var ss := SphereShape3D.new()
			ss.radius = 0.12
			cs.shape = ss
			rb.add_child(cs)
			var bpm := PhysicsMaterial.new()
			bpm.bounce = 0.7
			bpm.friction = 0.9
			rb.physics_material_override = bpm
			mass = 0.6
		"battery_pack":
			_box(rb, Vector3(0.12, 0.03, 0.07), Vector3.ZERO, Mats.m("plastic_grey"), 0.01)
			_box(rb, Vector3(0.008, 0.004, 0.03), Vector3(0.03, 0.017, 0), Mats.glow(Color(0.2, 1.0, 0.4), 2.0), 0.0, false)
			_shape(rb, Vector3(0.12, 0.03, 0.07), Vector3.ZERO)
			mass = 0.3
		"router":
			_box(rb, Vector3(0.22, 0.04, 0.15), Vector3.ZERO, Mats.m("plastic_white"), 0.012)
			for i in 4:
				_box(rb, Vector3(0.006, 0.003, 0.006), Vector3(-0.06 + i * 0.03, 0.021, 0.06), Mats.glow(Color(0.2, 1.0, 0.3) if i < 3 else Color(1, 0.6, 0.1), 4.0), 0.0, false)
			_box(rb, Vector3(0.008, 0.14, 0.008), Vector3(0.09, 0.08, -0.06), Mats.m("plastic_black"), 0.003)
			_shape(rb, Vector3(0.22, 0.04, 0.15), Vector3.ZERO)
			mass = 0.4
		"trash_bin":
			_cyl(rb, 0.15, 0.36, Vector3.ZERO, Mats.m("metal"), Vector3.ZERO, 16, 0.13)
			_box(rb, Vector3(0.2, 0.06, 0.2), Vector3(0, 0.16, 0), Mats.m("paper", Color(0.9, 0.9, 0.85)), 0.03)
			_cylshape(rb, 0.15, 0.36)
			mass = 2.0
		"chair":
			# rolling office chair: R.E.P.O-style physics toy
			_box(rb, Vector3(0.46, 0.08, 0.44), Vector3(0, 0.0, 0), Mats.m("fabric_blue"), 0.03)
			_box(rb, Vector3(0.44, 0.5, 0.07), Vector3(0, 0.3, -0.2), Mats.m("fabric_blue"), 0.03, true, Vector3(-8, 0, 0))
			_cyl(rb, 0.025, 0.36, Vector3(0, -0.22, 0), Mats.m("steel_dark"))
			for i in 5:
				var a := TAU * i / 5.0
				_box(rb, Vector3(0.05, 0.03, 0.28), Vector3(sin(a) * 0.14, -0.39, cos(a) * 0.14), Mats.m("plastic_black"), 0.01, true, Vector3(0, rad_to_deg(a), 0))
				_cyl(rb, 0.03, 0.03, Vector3(sin(a) * 0.27, -0.42, cos(a) * 0.27), Mats.m("rubber"), Vector3(90, rad_to_deg(a), 0), 8)
			_shape(rb, Vector3(0.48, 0.1, 0.46), Vector3(0, 0, 0))
			_shape(rb, Vector3(0.44, 0.5, 0.08), Vector3(0, 0.3, -0.2))
			_shape(rb, Vector3(0.1, 0.4, 0.1), Vector3(0, -0.22, 0))
			_shape(rb, Vector3(0.58, 0.05, 0.58), Vector3(0, -0.41, 0))
			mass = 9.0
		"stool":
			_cyl(rb, 0.17, 0.05, Vector3(0, 0.0, 0), Mats.m("wood"), Vector3.ZERO, 16)
			for i in 3:
				var a := TAU * i / 3.0
				_box(rb, Vector3(0.035, 0.6, 0.035), Vector3(sin(a) * 0.11, -0.3, cos(a) * 0.11), Mats.m("metal_green"), 0.01, true, Vector3(cos(a) * 6.0, 0, -sin(a) * 6.0))
			_shape(rb, Vector3(0.34, 0.05, 0.34), Vector3.ZERO)
			_shape(rb, Vector3(0.3, 0.6, 0.3), Vector3(0, -0.32, 0))
			mass = 3.0
		_:
			_box(rb, Vector3(0.2, 0.2, 0.2), Vector3.ZERO, Mats.m("cardboard"))
			_shape(rb, Vector3(0.2, 0.2, 0.2), Vector3.ZERO)
	rb.mass = mass
	if mass < 0.5:
		rb.angular_damp = 1.0
	return rb

static func _box(rb: Node3D, size: Vector3, pos: Vector3, mat: Material, bevel: float = 0.01, shadow: bool = true, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = Meshes.cbox(size, bevel)
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rb.add_child(mi)
	return mi

static func _cyl(rb: Node3D, r: float, h: float, pos: Vector3, mat: Material, rot: Variant = Vector3.ZERO, sides: int = 14, top_r: float = -1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = Meshes.cyl(r, h, sides, top_r)
	mi.material_override = mat
	mi.position = pos
	if rot is Vector3:
		mi.rotation_degrees = rot
	elif rot is int:
		# allow passing `sides` positionally in place of rot for brevity
		mi.mesh = Meshes.cyl(r, h, rot, top_r)
	rb.add_child(mi)
	return mi

static func _shape(rb: CollisionObject3D, size: Vector3, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = pos
	rb.add_child(cs)

static func _cylshape(rb: CollisionObject3D, r: float, h: float) -> void:
	var cs := CollisionShape3D.new()
	var c := CylinderShape3D.new()
	c.radius = r
	c.height = h
	cs.shape = c
	rb.add_child(cs)
