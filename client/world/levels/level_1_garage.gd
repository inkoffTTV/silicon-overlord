extends "res://world/levels/level_base.gd"
## HQ level 1 — the starting GARAGE. Interior x[-4,4] z[-3.5,3.5] y[0,3]. Front (+Z) has the roll-up
## door and a window onto an evening suburb street; back (-Z) has the door into the house.

const W := 4.0   # half width
const D := 3.5   # half depth
const H := 3.0   # ceiling height
const T := 0.2   # wall thickness

func _build() -> void:
	_shell()
	_outside()
	_lighting()
	_furniture()
	_clutter()
	_props()
	set_spawn(Vector3(0.9, 0.05, 2.3), 18.0)
	_viewpoints()

# ------------------------------------------------------------------ shell
func _shell() -> void:
	var wall := Mats.m("block_wall")
	var g := kit.node(self, Vector3.ZERO, 0.0, "Shell")
	# floor + ceiling
	kit.box(g, Vector3(2 * W + 2 * T, 0.2, 2 * D + 2 * T), Vector3(0, -0.1, 0), Mats.m("concrete_floor"), Vector3.ZERO, true, 0.0)
	kit.box(g, Vector3(2 * W + 2 * T, 0.12, 2 * D + 2 * T), Vector3(0, H + 0.06, 0), Mats.m("drywall"), Vector3.ZERO, true, 0.0)
	# joists
	for i in 6:
		var x := -W + 0.6 + i * 1.36
		kit.box(g, Vector3(0.07, 0.2, 2 * D), Vector3(x, H - 0.1, 0), Mats.m("wood"), Vector3.ZERO, false, 0.006)
	kit.box(g, Vector3(2 * W, 0.22, 0.12), Vector3(0, H - 0.11, 0.2), Mats.m("wood", Color(0.9, 0.85, 0.8)), Vector3.ZERO, false, 0.008)
	# side walls
	kit.box(g, Vector3(T, H + 0.2, 2 * D + 2 * T), Vector3(-W - T * 0.5, H * 0.5, 0), wall, Vector3.ZERO, true, 0.0)
	kit.box(g, Vector3(T, H + 0.2, 2 * D + 2 * T), Vector3(W + T * 0.5, H * 0.5, 0), wall, Vector3.ZERO, true, 0.0)
	# back wall with house door opening x[2.4,3.3]
	var bz := -D - T * 0.5
	_wall_piece(g, -W, 2.4, 0.0, H, bz, wall)
	_wall_piece(g, 3.3, W, 0.0, H, bz, wall)
	_wall_piece(g, 2.4, 3.3, 2.08, H, bz, wall)
	# front wall: roll-up opening x[-3.6,0.6] h 2.4, window x[1.6,3.2] y[1.0,2.1]
	var fz := D + T * 0.5
	_wall_piece(g, -W, -3.6, 0.0, H, fz, wall)
	_wall_piece(g, 0.6, 1.5, 0.0, H, fz, wall)
	_wall_piece(g, 3.3, W, 0.0, H, fz, wall)
	_wall_piece(g, -3.6, 0.6, 2.4, H, fz, wall)
	_wall_piece(g, 1.5, 3.3, 0.0, 0.9, fz, wall)
	_wall_piece(g, 1.5, 3.3, 2.2, H, fz, wall)
	# painted stripe + baseboard-ish curb
	for s in [-1.0, 1.0]:
		kit.box(g, Vector3(0.012, 0.07, 2 * D), Vector3(s * (W - 0.006), 1.0, 0), Mats.m("metal_yellow", Color(0.6, 0.6, 0.6), {"metallic_base": 0.0, "roughness_base": 0.7}), Vector3.ZERO, false, 0.0, false)
	# yellow guide line on the floor (taped)
	kit.box(g, Vector3(0.08, 0.004, 4.4), Vector3(-1.0, 0.002, 0.8), Mats.m("metal_yellow", Color.WHITE, {"metallic_base": 0.0, "roughness_base": 0.6, "grime": 0.7, "grime_scale": 3.0}), Vector3.ZERO, false, 0.0, false)
	# oil stain decal near the roll-up door
	kit.mesh(g, Meshes.cyl(0.55, 0.003, 20), Vector3(-1.6, 0.0015, 2.3), Mats.m("concrete_floor", Color(0.62, 0.6, 0.58), {"roughness_base": 0.18, "pattern": 0, "grime": 0.9, "grime_scale": 3.0}), Vector3(0, 0, 0), false).scale = Vector3(1.4, 1, 0.8)
	_rollup_door(g)
	_window(g)
	door_exit(g, Vector3(2.85, 0.0, -D + 0.005), 0.0, "garage_house_door")
	# pipes along the right wall top
	kit.cyl(g, 0.03, 2 * D, Vector3(W - 0.12, H - 0.25, 0), Mats.m("metal", Color(0.8, 0.6, 0.45)), Vector3(90, 0, 0), 10)
	kit.cyl(g, 0.02, 2 * D, Vector3(W - 0.2, H - 0.32, 0), Mats.m("steel_dark"), Vector3(90, 0, 0), 8)
	# electrical panel + conduit near the house door
	kit.box(g, Vector3(0.4, 0.55, 0.1), Vector3(W - 0.05, 1.55, -2.4), Mats.m("metal", Color(0.85, 0.85, 0.8), {"metallic_base": 0.4}), Vector3(0, 90, 0), true, 0.012)
	kit.label(g, "!", Vector3(W - 0.11, 1.68, -2.4), 80, Color(0.8, 0.6, 0.0), Vector3(0, -90, 0), 0.0015, true)
	kit.cyl(g, 0.016, 1.15, Vector3(W - 0.04, 2.4, -2.4), Mats.m("metal"), Vector3.ZERO, 8)
	outlet(g, Vector3(-W, 0.35, -0.1), 90.0)
	outlet(g, Vector3(W, 0.35, 1.0), -90.0)
	outlet(g, Vector3(-1.5, 1.1, -D), 0.0)

func _wall_piece(g: Node3D, x0: float, x1: float, y0: float, y1: float, z: float, mat: Material) -> void:
	kit.box(g, Vector3(x1 - x0, y1 - y0, T), Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, z), mat, Vector3.ZERO, true, 0.0)

func _rollup_door(g: Node3D) -> void:
	var z := D + 0.02
	kit.box(g, Vector3(4.2, 2.4, 0.05), Vector3(-1.5, 1.2, z + 0.05), Mats.m("rollup"), Vector3.ZERO, true, 0.0)
	for x in [-3.62, 0.62]:
		kit.box(g, Vector3(0.07, 2.45, 0.1), Vector3(x, 1.22, z - 0.02), Mats.m("steel_dark"), Vector3.ZERO, true, 0.01)
		kit.box(g, Vector3(0.05, 0.05, 2.6), Vector3(x, 2.5, z - 1.3), Mats.m("steel_dark"), Vector3.ZERO, false, 0.008)
	# drum housing
	kit.cyl(g, 0.2, 4.35, Vector3(-1.5, 2.65, z - 0.15), Mats.m("metal", Color(0.75, 0.75, 0.75)), Vector3(0, 0, 90), 14)
	# bottom bar + handle
	kit.box(g, Vector3(4.2, 0.06, 0.08), Vector3(-1.5, 0.03, z + 0.02), Mats.m("steel_dark"), Vector3.ZERO, false, 0.01)
	kit.box(g, Vector3(0.2, 0.04, 0.05), Vector3(-1.5, 0.35, z - 0.0), Mats.m("metal"), Vector3.ZERO, false, 0.01)
	# cold gap of street light under the door
	kit.box(g, Vector3(4.0, 0.008, 0.03), Vector3(-1.5, 0.004, z + 0.1), Mats.glow(Color(0.5, 0.6, 0.9), 2.0), Vector3.ZERO, false, 0.0, false)

func _window(g: Node3D) -> void:
	var z := D + T * 0.5
	var frame := Mats.m("plaster", Color(1.15, 1.15, 1.1), {"edge_wear": 0.3, "edge_color": Color(0.5, 0.45, 0.4)})
	kit.box(g, Vector3(1.9, 0.06, 0.28), Vector3(2.4, 0.88, z - 0.05), frame, Vector3.ZERO, true, 0.012)
	kit.box(g, Vector3(1.8, 0.05, 0.08), Vector3(2.4, 2.18, z), frame, Vector3.ZERO, false, 0.008)
	for x in [1.52, 2.4, 3.28]:
		kit.box(g, Vector3(0.05, 1.3, 0.08), Vector3(x, 1.55, z), frame, Vector3.ZERO, false, 0.008)
	kit.box(g, Vector3(1.8, 0.04, 0.06), Vector3(2.4, 1.55, z), frame, Vector3.ZERO, false, 0.008)
	var glass := kit.box(g, Vector3(1.76, 1.26, 0.006), Vector3(2.4, 1.55, z + 0.01), Mats.glass(Color(0.55, 0.62, 0.7, 0.10)), Vector3.ZERO, true, 0.0, false)
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# venetian blinds, half lowered, slats tilted -> striped light shafts
	var bz := z - 0.12
	kit.box(g, Vector3(1.82, 0.05, 0.06), Vector3(2.4, 2.17, bz), Mats.m("plastic_white"), Vector3.ZERO, false, 0.01)
	for i in 9:
		var y := 2.12 - i * 0.045
		kit.box(g, Vector3(1.76, 0.004, 0.045), Vector3(2.4, y, bz), Mats.m("plastic_white", Color(0.95, 0.92, 0.85)), Vector3(32, 0, 0), false, 0.0)
	kit.box(g, Vector3(1.78, 0.02, 0.05), Vector3(2.4, 2.12 - 9 * 0.045, bz), Mats.m("plastic_white"), Vector3(0, 0, -2), false, 0.005)
	for x in [1.8, 3.0]:
		kit.cable(g, Vector3(x, 2.15, bz + 0.03), Vector3(x, 1.2, bz + 0.03), 0.0, 1, 0.003, Mats.m("plastic_white"))
	# stuff on the sill
	kit.box(g, Vector3(0.1, 0.12, 0.1), Vector3(2.0, 0.97, z - 0.1), Mats.m("cardboard", Color(0.7, 0.5, 0.4), {"pattern": 0}), Vector3(0, 20, 0), false, 0.01)
	kit.mesh(g, Meshes.sphere(0.08, 8), Vector3(2.0, 1.07, z - 0.1), Mats.m("grass", Color(1.6, 2.0, 1.4)), Vector3.ZERO)

# ------------------------------------------------------------------ outside (seen through the window)
func _outside() -> void:
	var o := kit.node(self, Vector3.ZERO, 0.0, "Outside")
	kit.box(o, Vector3(40, 0.2, 6), Vector3(0, -0.12, D + 3.2), Mats.m("concrete_floor", Color(0.9, 0.9, 0.95)), Vector3.ZERO, false, 0.0)
	kit.box(o, Vector3(60, 0.2, 2), Vector3(0, -0.08, 7.3), Mats.m("sidewalk"), Vector3.ZERO, false, 0.0)
	kit.box(o, Vector3(60, 0.2, 8), Vector3(0, -0.22, 12.3), Mats.m("asphalt"), Vector3.ZERO, false, 0.0)
	for i in 10:
		kit.box(o, Vector3(1.5, 0.01, 0.12), Vector3(-14 + i * 3.4, -0.115, 12.3), Mats.m("paper", Color(1.0, 0.9, 0.5), {"grime": 0.6}), Vector3.ZERO, false, 0.0, false)
	kit.box(o, Vector3(60, 0.2, 2), Vector3(0, -0.08, 17.3), Mats.m("sidewalk"), Vector3.ZERO, false, 0.0)
	kit.box(o, Vector3(80, 0.2, 30), Vector3(0, -0.12, 33.3), Mats.m("grass"), Vector3.ZERO, false, 0.0)
	# lawns either side of the driveway
	for s in [-1.0, 1.0]:
		kit.box(o, Vector3(16, 0.2, 3), Vector3(s * 12.5, -0.1, 5.0), Mats.m("grass"), Vector3.ZERO, false, 0.0)
	# houses across the street
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 6:
		var x := -22.0 + i * 9.5 + rng.randf_range(-1, 1)
		_house(o, Vector3(x, 0, 24.0 + rng.randf_range(-1.0, 1.5)), rng)
	# neighbour garage wall at the side, fence
	kit.box(o, Vector3(0.1, 1.4, 6), Vector3(5.5, 0.7, 6.8), Mats.m("wood_planks", Color(0.7, 0.7, 0.7), {"cell": Vector2(0.15, 1.6)}), Vector3(0, 0, 0), false, 0.0)
	# street lamps
	_street_lamp(o, Vector3(5.2, 0, 9.6), true)
	_street_lamp(o, Vector3(-11.0, 0, 8.6), false)
	_street_lamp(o, Vector3(16.0, 0, 16.2), false)
	# parked car across the street
	_car(o, Vector3(1.2, 0, 15.6), Color(0.35, 0.1, 0.1))
	# trees and power line
	for p in [Vector3(-6, 0, 20.5), Vector3(8.5, 0, 21), Vector3(14, 0, 5.5), Vector3(-8.5, 0, 6.0)]:
		_tree(o, p, rng)
	for x in [-14.0, 10.0]:
		kit.box(o, Vector3(0.2, 8, 0.2), Vector3(x, 4, 18.5), Mats.m("wood_dark"), Vector3.ZERO, false, 0.02)
		kit.box(o, Vector3(1.8, 0.12, 0.12), Vector3(x, 7.4, 18.5), Mats.m("wood_dark"), Vector3.ZERO, false, 0.01)
	for dx in [-0.8, 0.0, 0.8]:
		kit.cable(o, Vector3(-14.0 + dx, 7.45, 18.5), Vector3(10.0 + dx, 7.45, 18.5), 0.9, 12, 0.025)
		kit.cable(o, Vector3(10.0 + dx, 7.45, 18.5), Vector3(34.0 + dx, 7.45, 18.5), 0.9, 12, 0.025)

func _house(o: Node3D, p: Vector3, rng: RandomNumberGenerator) -> void:
	var g := kit.node(o, p, 0.0)
	var w := rng.randf_range(7.0, 8.5)
	var h := rng.randf_range(3.2, 5.6)
	var sid := Mats.m("siding" if rng.randf() < 0.5 else "siding_warm", Color(1, 1, 1).lerp(Color(0.7, 0.8, 1.0), rng.randf()))
	kit.box(g, Vector3(w, h, 7), Vector3(0, h * 0.5, 3.5), sid, Vector3.ZERO, false, 0.0)
	# gable roof
	var rw := w * 0.5 + 0.4
	for s in [-1.0, 1.0]:
		kit.box(g, Vector3(rw / cos(deg_to_rad(32.0)), 0.15, 7.6), Vector3(s * rw * 0.5, h + rw * 0.5 * tan(deg_to_rad(32.0)), 3.5), Mats.m("roof"), Vector3(0, 0, -s * 32.0), false, 0.0)
	var front := Vector3(w, 1.0, 0)
	# windows: some lit warm, some dark, some TV-blue
	for i in 3:
		var wx := -w * 0.5 + 1.3 + i * (w - 2.6) * 0.5
		for fl in (2 if h > 4.6 else 1):
			var r := rng.randf()
			var c := Color(1.0, 0.68, 0.35) if r < 0.45 else (Color(0.35, 0.5, 1.0) if r < 0.6 else Color(0.03, 0.035, 0.05))
			var e := 2.2 if r < 0.6 else 0.0
			var wy := 1.5 + fl * 2.3
			if wy > h - 0.6:
				continue
			kit.box(g, Vector3(1.0, 1.1, 0.05), Vector3(wx, wy, -0.01), Mats.glow(c, e) if e > 0 else Mats.m("tv_black"), Vector3.ZERO, false, 0.0, false)
			kit.box(g, Vector3(1.15, 0.08, 0.1), Vector3(wx, wy - 0.6, -0.04), Mats.m("plastic_white"), Vector3.ZERO, false, 0.0, false)
	# door + porch light
	kit.box(g, Vector3(0.95, 2.1, 0.05), Vector3(w * 0.25, 1.05, -0.02), Mats.m("wood_dark"), Vector3.ZERO, false, 0.0, false)
	kit.mesh(g, Meshes.sphere(0.09, 8), Vector3(w * 0.25 + 0.75, 2.2, -0.12), Mats.glow(Color(1.0, 0.7, 0.4), 10.0), Vector3.ZERO, false)
	# hedge
	kit.box(g, Vector3(w * 0.6, 0.8, 0.8), Vector3(-w * 0.15, 0.4, -0.8), Mats.m("grass", Color(1.2, 1.4, 1.0)), Vector3.ZERO, false, 0.25)

func _street_lamp(o: Node3D, p: Vector3, beam: bool) -> void:
	var g := kit.node(o, p, 0.0)
	kit.cyl(g, 0.08, 5.4, Vector3(0, 2.7, 0), Mats.m("steel_dark"), Vector3.ZERO, 10)
	kit.box(g, Vector3(0.08, 0.08, 1.3), Vector3(0, 5.35, -0.6), Mats.m("steel_dark"), Vector3.ZERO, false, 0.02)
	kit.box(g, Vector3(0.35, 0.14, 0.6), Vector3(0, 5.3, -1.25), Mats.m("steel_dark"), Vector3.ZERO, false, 0.04)
	var lc := Color(0.65, 0.78, 1.0) if beam else Color(1.0, 0.62, 0.3)
	kit.box(g, Vector3(0.28, 0.02, 0.5), Vector3(0, 5.22, -1.25), Mats.glow(lc, 14.0), Vector3.ZERO, false, 0.0, false)
	kit.omni(g, Vector3(0, 4.9, -1.25), lc, 2.5, 6.0, false, 0.6)
	if beam:
		# sodium beam through the garage window (shadowed: blinds + window bars become light shafts)
		var t := to_global(Vector3(1.2, 0.0, 1.5))
		var l := kit.spot(g, Vector3(0, 5.1, -1.25), g.to_local(t), Color(0.62, 0.74, 1.0), 40.0, 18.0, 14.0, true, 1.4)
		l.shadow_blur = 0.6

func _car(o: Node3D, p: Vector3, c: Color) -> void:
	var g := kit.node(o, p, 90.0)
	var paint := Mats.m("metal_red", Color.WHITE, {"albedo": c, "metallic_base": 0.5, "roughness_base": 0.35})
	kit.box(g, Vector3(1.8, 0.7, 4.3), Vector3(0, 0.6, 0), paint, Vector3.ZERO, false, 0.12)
	kit.box(g, Vector3(1.6, 0.6, 2.2), Vector3(0, 1.2, -0.2), paint, Vector3.ZERO, false, 0.15)
	kit.box(g, Vector3(1.62, 0.45, 2.0), Vector3(0, 1.22, -0.2), Mats.glass(Color(0.05, 0.07, 0.1, 0.85)), Vector3.ZERO, false, 0.1)
	for x in [-0.85, 0.85]:
		for z in [-1.35, 1.35]:
			kit.cyl(g, 0.33, 0.24, Vector3(x, 0.33, z), Mats.m("rubber"), Vector3(0, 0, 90), 14)
	for x in [-0.6, 0.6]:
		kit.box(g, Vector3(0.3, 0.1, 0.03), Vector3(x, 0.7, -2.15), Mats.glow(Color(0.9, 0.05, 0.03), 0.6), Vector3.ZERO, false, 0.0, false)

func _tree(o: Node3D, p: Vector3, rng: RandomNumberGenerator) -> void:
	var g := kit.node(o, p, rng.randf() * 360.0)
	kit.cyl(g, 0.2, 3.0, Vector3(0, 1.5, 0), Mats.m("wood_dark"), Vector3.ZERO, 8)
	for i in 4:
		var s := rng.randf_range(1.2, 2.0)
		kit.mesh(g, Meshes.sphere(s, 8), Vector3(rng.randf_range(-1, 1), 3.6 + rng.randf_range(0, 1.6), rng.randf_range(-1, 1)), Mats.m("grass", Color(0.8, 1.1, 0.9), {"pattern": 0, "speckle": 0.5}), Vector3.ZERO)

# ------------------------------------------------------------------ lights
func _lighting() -> void:
	var g := kit.node(self, Vector3.ZERO, 0.0, "Lights")
	# key: bare bulb in the middle of the room
	ceiling_bulb(g, Vector3(0.3, H, 0.9), 0.5, Color(1.0, 0.66, 0.36), 2.4, 8.5, true)
	# dying fluorescent tube over the workbench
	fluorescent(g, Vector3(-2.6, H - 0.22, -2.9), 0.0, 0.35)
	# string lights: along the front wall, and zig-zag across the sofa corner
	var warm := [Color(1.0, 0.55, 0.2), Color(1.0, 0.75, 0.35), Color(1.0, 0.4, 0.25), Color(0.95, 0.8, 0.5)]
	kit.string_lights(g, Vector3(-3.9, H - 0.12, D - 0.25), Vector3(3.9, H - 0.12, D - 0.25), 0.25, 18, warm)
	kit.string_lights(g, Vector3(3.9, H - 0.12, -1.0), Vector3(0.8, H - 0.12, D - 0.25), 0.35, 12, warm)
	kit.string_lights(g, Vector3(-3.9, H - 0.12, -3.2), Vector3(-3.9, H - 0.12, 3.2), 0.3, 14, warm)
	kit.omni(g, Vector3(-1.0, 2.35, 2.9), Color(1.0, 0.6, 0.3), 0.55, 3.5, false, 0.6)
	kit.omni(g, Vector3(2.6, 2.3, 1.0), Color(1.0, 0.6, 0.3), 0.55, 3.5, false, 0.6)
	kit.omni(g, Vector3(-3.5, 2.35, 0.5), Color(1.0, 0.6, 0.3), 0.4, 3.0, false, 0.6)

# ------------------------------------------------------------------ furniture
func _furniture() -> void:
	var g := kit.node(self, Vector3.ZERO, 0.0, "Furniture")
	# desk + PC on the left wall, facing +X
	var desk := desk_pc(g, Vector3(-W + 0.38, 0, -0.8), 90.0, "garage_pc")
	desk_lamp(desk, Vector3(0.38, 0.76, -0.2), -50.0)
	wall_calendar(g, Vector3(-W + 0.01, 1.62, 0.05), 90.0)
	poster(g, Vector3(-W + 0.01, 1.75, -1.75), 90.0, "SHIP\nIT.", Color(0.15, 0.15, 0.18), Color(0.95, 0.85, 0.3), Vector2(0.42, 0.6))
	# whiteboard on the left wall, nearer the front
	whiteboard(g, Vector3(-W + 0.02, 0, 1.7), 90.0, "garage_whiteboard")
	# workbench + pegboard along the back wall
	_workbench(g, Vector3(-2.6, 0, -D + 0.35))
	# prototype shelf
	phone_shelf(g, Vector3(-0.45, 0, -D + 0.24), 0.0, "garage_shelf")
	# assembly table, freestanding
	assembly_table(g, Vector3(1.0, 0, -1.55), 0.0, "garage_line")
	# sofa facing the TV on the right wall
	sofa(g, Vector3(2.05, 0, 1.7), 90.0)
	company_board(g, Vector3(W - 0.01, 1.55, 1.7), -90.0, "garage_board")
	_tv_cabinet(g, Vector3(W - 0.25, 0, 1.7))
	# coffee table: a pallet with a crate
	_pallet_table(g, Vector3(2.95, 0, 1.7))
	fridge(g, Vector3(W - 0.36, 0, -1.25), -90.0)
	_water_heater(g, Vector3(W - 0.35, 0, -D + 0.35))
	# rug
	kit.box(g, Vector3(1.8, 0.01, 2.4), Vector3(2.7, 0.005, 1.7), Mats.m("carpet", Color(1.6, 0.9, 0.7)), Vector3.ZERO, false, 0.0, false)

func _workbench(g: Node3D, p: Vector3) -> void:
	var b := kit.node(g, p, 0.0, "Workbench")
	var w := 2.5
	kit.box(b, Vector3(w, 0.07, 0.7), Vector3(0, 0.88, 0), Mats.m("wood_planks", Color(1.1, 1.0, 0.9), {"cell": Vector2(2.6, 0.14)}), Vector3.ZERO, true, 0.01)
	for x in [-1.0, 1.0]:
		for z in [-1.0, 1.0]:
			kit.box(b, Vector3(0.08, 0.85, 0.08), Vector3(x * (w * 0.5 - 0.06), 0.425, z * 0.28), Mats.m("wood"), Vector3.ZERO, true, 0.01)
	kit.box(b, Vector3(w - 0.1, 0.03, 0.62), Vector3(0, 0.22, 0), Mats.m("plywood"), Vector3.ZERO, true, 0.006)
	# vise
	var v := kit.node(b, Vector3(w * 0.5 - 0.15, 0.915, 0.3), 0.0)
	kit.box(v, Vector3(0.16, 0.1, 0.18), Vector3(0, 0.05, 0), Mats.m("metal_blue"), Vector3.ZERO, false, 0.015)
	kit.box(v, Vector3(0.16, 0.08, 0.04), Vector3(0, 0.08, 0.13), Mats.m("metal_blue"), Vector3.ZERO, false, 0.012)
	kit.cyl(v, 0.012, 0.2, Vector3(0, 0.05, 0.22), Mats.m("metal"), Vector3(90, 0, 0), 8)
	# pegboard + tools hanging
	kit.box(b, Vector3(w - 0.1, 1.0, 0.02), Vector3(0, 1.55, -0.33), Mats.m("pegboard"), Vector3.ZERO, false, 0.004)
	var tools := kit.node(b, Vector3(0, 1.55, -0.31), 0.0)
	for i in 5:
		kit.box(tools, Vector3(0.025, 0.18 + i * 0.03, 0.01), Vector3(-1.0 + i * 0.09, 0.15 - i * 0.015, 0.01), Mats.m("metal"), Vector3.ZERO, false, 0.004)
	kit.box(tools, Vector3(0.04, 0.3, 0.02), Vector3(-0.45, 0.05, 0.015), Mats.m("wood"), Vector3.ZERO, false, 0.006)
	kit.box(tools, Vector3(0.14, 0.04, 0.035), Vector3(-0.45, 0.2, 0.02), Mats.m("steel_dark"), Vector3.ZERO, false, 0.006)
	kit.box(tools, Vector3(0.5, 0.12, 0.006), Vector3(0.1, 0.25, 0.01), Mats.m("metal"), Vector3(0, 0, -3), false, 0.0)
	kit.box(tools, Vector3(0.12, 0.1, 0.03), Vector3(-0.17, 0.25, 0.015), Mats.m("wood"), Vector3.ZERO, false, 0.01)
	for i in 4:
		var c: Color = [Color(0.85, 0.25, 0.1), Color(0.95, 0.75, 0.1), Color(0.2, 0.4, 0.85), Color(0.1, 0.6, 0.3)][i]
		kit.cyl(tools, 0.014, 0.1, Vector3(0.55 + i * 0.07, -0.05, 0.02), Mats.m("plastic_orange", c * Color(1.2, 1.2, 1.2)), Vector3.ZERO, 8)
		kit.cyl(tools, 0.003, 0.1, Vector3(0.55 + i * 0.07, -0.15, 0.02), Mats.m("metal"), Vector3.ZERO, 6)
	kit.cable(tools, Vector3(0.6, 0.3, 0.02), Vector3(0.9, 0.3, 0.02), 0.25, 8, 0.012, Mats.m("plastic_orange"))
	# shelf above
	kit.box(b, Vector3(w - 0.1, 0.03, 0.3), Vector3(0, 2.2, -0.2), Mats.m("plywood"), Vector3.ZERO, true, 0.006)
	for x in [-1.0, 1.0]:
		kit.box(b, Vector3(0.03, 0.15, 0.25), Vector3(x * 1.0, 2.12, -0.22), Mats.m("steel_dark"), Vector3.ZERO, false, 0.004)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var x := -1.1
	while x < 1.0:
		var s := Vector3(rng.randf_range(0.2, 0.36), rng.randf_range(0.14, 0.3), 0.26)
		kit.box(b, s, Vector3(x + s.x * 0.5, 2.215 + s.y * 0.5, -0.2), Mats.m("cardboard", Color(1, 1, 1).lerp(Color(0.8, 0.8, 0.7), rng.randf())), Vector3(0, rng.randf_range(-4, 4), 0), false, 0.015)
		x += s.x + 0.04
	# clamp light / power strip
	kit.box(b, Vector3(0.4, 0.04, 0.06), Vector3(-0.6, 0.92, -0.28), Mats.m("plastic_white"), Vector3.ZERO, false, 0.01)
	kit.box(b, Vector3(0.01, 0.01, 0.004), Vector3(-0.43, 0.94, -0.25), Mats.glow(Color(1, 0.2, 0.1), 5.0), Vector3.ZERO, false, 0.0, false)

func _tv_cabinet(g: Node3D, p: Vector3) -> void:
	var c := kit.node(g, p, -90.0)
	kit.box(c, Vector3(1.4, 0.5, 0.4), Vector3(0, 0.25, 0), Mats.m("wood_dark"), Vector3.ZERO, true, 0.015)
	kit.box(c, Vector3(0.66, 0.4, 0.01), Vector3(-0.34, 0.25, 0.2), Mats.m("wood", Color(0.7, 0.7, 0.7)), Vector3.ZERO, false, 0.004)
	kit.box(c, Vector3(0.66, 0.4, 0.01), Vector3(0.34, 0.25, 0.2), Mats.m("wood", Color(0.7, 0.7, 0.7)), Vector3.ZERO, false, 0.004)
	# old game console
	kit.box(c, Vector3(0.3, 0.07, 0.24), Vector3(0.35, 0.535, 0.0), Mats.m("plastic_grey", Color(1.4, 1.4, 1.4)), Vector3.ZERO, false, 0.015)
	kit.box(c, Vector3(0.008, 0.008, 0.004), Vector3(0.25, 0.54, 0.12), Mats.glow(Color(0.2, 1.0, 0.3), 5.0), Vector3.ZERO, false, 0.0, false)
	kit.cable(c, Vector3(0.3, 0.52, -0.1), Vector3(0.3, 1.2, -0.18), 0.05, 4, 0.008)

func _pallet_table(g: Node3D, p: Vector3) -> void:
	var t := kit.node(g, p, 90.0, "Pallet")
	for i in 5:
		kit.box(t, Vector3(1.2, 0.025, 0.14), Vector3(0, 0.135, -0.36 + i * 0.18), Mats.m("plywood", Color(0.85, 0.8, 0.7)), Vector3(0, rng_off(i), 0), false, 0.006)
	for z in [-0.35, 0.0, 0.35]:
		kit.box(t, Vector3(1.2, 0.1, 0.09), Vector3(0, 0.07, z), Mats.m("plywood", Color(0.75, 0.7, 0.6)), Vector3.ZERO, false, 0.01)
	kit.shape(Vector3(1.2, 0.15, 0.85), t.global_transform.translated_local(Vector3(0, 0.075, 0)))

func rng_off(i: int) -> float:
	return [1.5, -1.0, 0.5, -2.0, 1.0][i % 5]

func _water_heater(g: Node3D, p: Vector3) -> void:
	var h := kit.node(g, p, 0.0, "WaterHeater")
	kit.cyl(h, 0.28, 1.5, Vector3(0, 0.8, 0), Mats.m("plastic_white", Color(0.9, 0.9, 0.85), {"grime": 0.6}), Vector3.ZERO, 18, true)
	kit.cyl(h, 0.24, 0.05, Vector3(0, 1.57, 0), Mats.m("metal"), Vector3.ZERO, 16)
	kit.cyl(h, 0.04, 1.4, Vector3(0, 2.3, 0), Mats.m("metal", Color(0.8, 0.6, 0.45)), Vector3.ZERO, 8)
	kit.box(h, Vector3(0.14, 0.18, 0.06), Vector3(0, 0.35, 0.27), Mats.m("metal_red"), Vector3.ZERO, false, 0.01)
	kit.mesh(h, Meshes.sphere(0.012, 6), Vector3(0.03, 0.38, 0.305), Mats.glow(Color(0.3, 0.6, 1.0), 6.0), Vector3.ZERO, false)

# ------------------------------------------------------------------ static clutter
func _clutter() -> void:
	var g := kit.node(self, Vector3.ZERO, 0.0, "Clutter")
	# tire stack near the roll-up door
	for i in 3:
		kit.cyl(g, 0.32, 0.2, Vector3(-3.45, 0.1 + i * 0.21, 3.0), Mats.m("rubber", Color(1.3, 1.3, 1.3), {"pattern": 6}), Vector3(0, i * 20, 0), 18, i == 0)
	kit.shape(Vector3(0.64, 0.63, 0.64), Transform3D(Basis(), Vector3(-3.45, 0.315, 3.0)))
	# broom + shop vac
	kit.box(g, Vector3(0.025, 1.3, 0.025), Vector3(-3.9, 0.7, -1.95), Mats.m("wood"), Vector3(0, 0, -12), false, 0.006)
	kit.box(g, Vector3(0.3, 0.08, 0.06), Vector3(-3.78, 0.05, -1.95), Mats.m("plastic_orange", Color(1.2, 0.8, 0.5)), Vector3(0, 90, 0), false, 0.02)
	kit.cyl(g, 0.2, 0.45, Vector3(-1.1, 0.25, -2.75), Mats.m("plastic_yellow" if false else "metal_yellow", Color.WHITE, {"metallic_base": 0.0}), Vector3.ZERO, 14, true)
	kit.cyl(g, 0.21, 0.08, Vector3(-1.1, 0.5, -2.75), Mats.m("plastic_black"), Vector3.ZERO, 14)
	kit.cable(g, Vector3(-1.0, 0.5, -2.65), Vector3(-0.6, 0.05, -2.4), 0.1, 6, 0.03, Mats.m("plastic_black"))
	# floor cables: desk -> outlet, extension cord across to the assembly table
	kit.floor_cable(g, [Vector3(-3.5, 0, -0.5), Vector3(-3.8, 0, -0.3), Vector3(-3.95, 0, -0.1)])
	kit.floor_cable(g, [Vector3(-3.3, 0, -0.95), Vector3(-2.2, 0, -1.0), Vector3(-0.6, 0, -1.2), Vector3(0.15, 0, -1.5)], 0.008, 0.018, Mats.m("plastic_orange"))
	kit.floor_cable(g, [Vector3(3.9, 0, 1.0), Vector3(3.7, 0, 1.25), Vector3(3.75, 0, 1.6)])
	# extension reel
	kit.cyl(g, 0.16, 0.12, Vector3(-0.4, 0.06, -1.25), Mats.m("plastic_orange", Color(0.7, 0.7, 0.7)), Vector3(0, 0, 0), 14)
	kit.cyl(g, 0.17, 0.02, Vector3(-0.4, 0.13, -1.25), Mats.m("plastic_black"), Vector3.ZERO, 14)
	# old bicycle hanging on the left wall front (just a frame silhouette)
	var bike := kit.node(g, Vector3(-W + 0.18, 1.7, 2.9), 90.0)
	for s in [-0.45, 0.45]:
		var wheel := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.28
		tm.outer_radius = 0.31
		tm.rings = 20
		tm.ring_segments = 6
		wheel.mesh = tm
		wheel.material_override = Mats.m("rubber")
		wheel.position = Vector3(s, 0, 0)
		wheel.rotation_degrees.x = 90
		bike.add_child(wheel)
	kit.box(bike, Vector3(0.9, 0.03, 0.03), Vector3(0, 0.12, 0), Mats.m("metal_blue", Color(1.4, 1.4, 1.4)), Vector3(0, 0, -8), false, 0.008)
	kit.box(bike, Vector3(0.03, 0.45, 0.03), Vector3(-0.05, 0.0, 0), Mats.m("metal_blue", Color(1.4, 1.4, 1.4)), Vector3(0, 0, 25), false, 0.008)
	kit.box(bike, Vector3(0.6, 0.03, 0.03), Vector3(0.1, -0.12, 0), Mats.m("metal_blue", Color(1.4, 1.4, 1.4)), Vector3(0, 0, 30), false, 0.008)
	# clock above the house door
	var clock := kit.node(g, Vector3(1.6, 2.45, -D + 0.02), 0.0)
	kit.cyl(clock, 0.16, 0.04, Vector3.ZERO, Mats.m("plastic_white"), Vector3(90, 0, 0), 20)
	kit.box(clock, Vector3(0.012, 0.1, 0.004), Vector3(0, 0.04, 0.022), Mats.m("plastic_black"), Vector3(0, 0, -40), false, 0.0)
	kit.box(clock, Vector3(0.012, 0.13, 0.004), Vector3(0.02, -0.03, 0.023), Mats.m("plastic_black"), Vector3(0, 0, 130), false, 0.0)
	# boxes stacked against the roll-up door (static base so the heap reads as "stored")
	kit.box(g, Vector3(0.8, 0.55, 0.6), Vector3(-2.6, 0.275, 3.05), Mats.m("cardboard", Color(0.9, 0.85, 0.8)), Vector3(0, 4, 0), true, 0.02)
	kit.box(g, Vector3(0.7, 0.45, 0.55), Vector3(-2.55, 0.78, 3.07), Mats.m("cardboard"), Vector3(0, -6, 0), true, 0.02)
	kit.label(g, "XMAS", Vector3(-2.55, 0.8, 2.785), 60, Color(0.1, 0.1, 0.1), Vector3(0, 174, 0), 0.0016, true)

# ------------------------------------------------------------------ grabbable props
func _props() -> void:
	# on the desk
	prop("keyboard", Vector3(-3.45, 0.8, -0.75), Vector3(0, 90, 0))
	prop("mug", Vector3(-3.7, 0.82, -0.2), Vector3.ZERO, 0)
	prop("can", Vector3(-3.45, 0.83, -1.35), Vector3.ZERO, 0)
	prop("phone_board", Vector3(-3.4, 0.79, -0.35), Vector3(0, 30, 0))
	prop("chair", Vector3(-2.95, 0.5, -0.75), Vector3(0, -90, 0))
	# workbench
	prop("toolbox", Vector3(-3.3, 1.05, -3.1))
	prop("drill", Vector3(-2.5, 1.06, -3.0), Vector3(0, 30, 0))
	prop("wrench", Vector3(-2.1, 0.94, -2.85), Vector3(0, 20, 0))
	prop("hammer", Vector3(-1.85, 0.95, -3.05), Vector3(0, -40, 0))
	prop("screwdriver", Vector3(-2.9, 0.94, -2.8), Vector3(0, 70, 0), 1)
	prop("screwdriver", Vector3(-2.75, 0.94, -2.85), Vector3(0, 50, 0), 2)
	prop("tape_roll", Vector3(-1.6, 0.97, -2.85))
	prop("paint_can", Vector3(-3.3, 0.35, -3.0), Vector3.ZERO, 0)
	prop("paint_can", Vector3(-3.05, 0.35, -3.05), Vector3.ZERO, 1)
	prop("paint_can", Vector3(-2.2, 0.35, -3.0), Vector3.ZERO, 2)
	# assembly table
	prop("phone_proto", Vector3(0.6, 0.95, -1.35), Vector3(0, 10, 0), 0)
	prop("phone_proto", Vector3(1.4, 0.95, -1.3), Vector3(0, -20, 0), 1)
	prop("phone_board", Vector3(1.6, 0.95, -1.45), Vector3(0, 40, 0))
	prop("battery_pack", Vector3(0.3, 0.95, -1.3))
	prop("mug", Vector3(1.75, 0.96, -1.25), Vector3.ZERO, 2)
	prop("stool", Vector3(1.0, 0.68, -0.75))
	# prototype shelf: loose phones on the bottom shelves
	prop("phone_proto", Vector3(0.0, 0.16, -3.15), Vector3(0, 80, 0), 2)
	prop("phone_proto", Vector3(-1.0, 0.64, -3.12), Vector3(0, 10, 0), 3)
	prop("box_s", Vector3(-0.8, 0.27, -3.25))
	prop("box_s", Vector3(-0.35, 0.27, -3.25), Vector3(0, 10, 0))
	# coffee table + sofa corner
	prop("pizza_box", Vector3(2.95, 0.2, 1.5), Vector3(0, 12, 0))
	prop("can", Vector3(2.85, 0.24, 2.05), Vector3.ZERO, 1)
	prop("can", Vector3(3.15, 0.2, 2.15), Vector3(90, 0, 30), 2)
	prop("mug", Vector3(3.1, 0.2, 1.2), Vector3.ZERO, 3)
	prop("router", Vector3(W - 0.25, 0.55, 1.2), Vector3(0, 90, 0))
	prop("ball", Vector3(3.3, 0.15, 3.0))
	# boxes near the roll-up door
	prop("box_l", Vector3(-1.4, 0.26, 2.8), Vector3(0, 12, 0))
	prop("box_m", Vector3(-1.45, 0.75, 2.85), Vector3(0, -8, 0))
	prop("box_m", Vector3(-0.6, 0.2, 3.0), Vector3(0, 30, 0))
	prop("box_heavy", Vector3(-3.3, 0.25, 2.1), Vector3(0, 5, 0))
	prop("box_s", Vector3(-2.55, 1.15, 3.05), Vector3(0, 20, 0))
	prop("crate", Vector3(-3.3, 0.22, 1.2), Vector3(0, -10, 0))
	prop("cone", Vector3(-0.2, 0.24, 2.4))
	prop("trash_bin", Vector3(-1.95, 0.2, -0.3))
	prop("bottle", Vector3(-1.9, 1.0, -2.9))
	prop("book", Vector3(-3.6, 0.8, -1.25), Vector3(0, 80, 0), 1)
	prop("book", Vector3(-3.62, 0.84, -1.25), Vector3(0, 95, 0), 2)
	prop("can", Vector3(W - 0.36, 1.82, -1.1), Vector3.ZERO, 3)
	prop("box_s", Vector3(W - 0.36, 1.86, -1.4))

func _viewpoints() -> void:
	kit.viewpoint(self, "overview", Vector3(3.5, 2.45, 3.1), Vector3(-1.3, 0.7, -1.6), 74.0)
	kit.viewpoint(self, "spawn", Vector3(0.9, 1.6, 2.3), Vector3(0.9 - sin(deg_to_rad(18.0)) * 3.0, 1.35, 2.3 - cos(deg_to_rad(18.0)) * 3.0), 75.0)
	kit.viewpoint(self, "desk", Vector3(-2.35, 1.55, 0.45), Vector3(-3.7, 0.95, -1.0), 70.0)
	kit.viewpoint(self, "workbench", Vector3(-1.1, 1.65, -1.0), Vector3(-2.7, 1.2, -3.4), 70.0)
	kit.viewpoint(self, "sofa", Vector3(-0.6, 1.65, -0.6), Vector3(3.0, 0.9, 2.2), 72.0)
	kit.viewpoint(self, "window", Vector3(0.9, 1.55, 0.2), Vector3(2.6, 1.45, 3.6), 70.0)
	kit.viewpoint(self, "beam", Vector3(-0.8, 1.7, -0.5), Vector3(1.6, 0.4, 2.2), 75.0)
	kit.viewpoint(self, "back", Vector3(-1.5, 1.6, -2.4), Vector3(1.5, 1.0, 3.0), 75.0)
