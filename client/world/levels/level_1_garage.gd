extends "res://world/levels/level_base.gd"
## HQ level 1 — the starting GARAGE. Interior x[-4,4] z[-3.5,3.5] y[0,3]. Front (+Z) has the roll-up
## door (rolled up: the delivery van waits on the driveway) and a window onto an evening suburb street; back (-Z)
## has the door into the house. Above the ceiling: the attic = "second floor" (loft.gd), reached through a hatch
## + ladder in the right-front ceiling once `hq.rooms.AssemblyLine` is bought.

const W := 4.0   # half width
const D := 3.5   # half depth
const H := 3.0   # ceiling height
const T := 0.2   # wall thickness
const KNEE := 1.95   # loft knee-wall height above the loft floor
const RISE := 1.5    # roof rise from the knee walls to the ridge
const Loft := preload("res://world/live/loft.gd")
const ShipDock := preload("res://world/live/ship_dock.gd")
const Shipping := preload("res://world/live/shipping.gd")
const DevBench := preload("res://world/live/dev_bench.gd")
const BenchView := preload("res://world/live/bench_view.gd")
const HQ := preload("res://world/live/hq_state.gd")

var loft: Node3D
var dock: Node3D
var shipping: Node3D
var dev_bench: Node3D
var bench_view: Node3D

func _build() -> void:
	_shell()
	_outside()
	_lighting()
	_furniture()
	_clutter()
	_props()
	_attic()
	_live()
	_staff_slots()
	set_spawn(Vector3(0.9, 0.05, 2.3), 18.0)
	_viewpoints()

# ------------------------------------------------------------------ shell
func _shell() -> void:
	var wall := Mats.m("block_wall")
	var g := kit.node(self, Vector3.ZERO, 0.0, "Shell")
	# floor + ceiling
	kit.box(g, Vector3(2 * W + 2 * T, 0.2, 2 * D + 2 * T), Vector3(0, -0.1, 0), Mats.m("concrete_floor"), Vector3.ZERO, true, 0.0)
	# ceiling (= loft floor) with the hatch hole x[3,4] z[-2,-0.3]
	var hole: Rect2 = Loft.HOLE
	var hx0 := hole.position.x
	var hz0 := hole.position.y
	var hz1 := hole.position.y + hole.size.y
	_ceiling_piece(g, -W - T, hx0, -D - T, D + T)
	_ceiling_piece(g, hx0, W + T, -D - T, hz0)
	_ceiling_piece(g, hx0, W + T, hz1, D + T)
	# hatch frame trim
	for z in [hz0, hz1]:
		kit.box(g, Vector3(hole.size.x + 0.08, 0.06, 0.06), Vector3(hx0 + hole.size.x * 0.5, H - 0.03, z), Mats.m("wood", Color(1.2, 1.15, 1.1)), Vector3.ZERO, false, 0.008)
	kit.box(g, Vector3(0.06, 0.06, hole.size.y), Vector3(hx0, H - 0.03, (hz0 + hz1) * 0.5), Mats.m("wood", Color(1.2, 1.15, 1.1)), Vector3.ZERO, false, 0.008)
	# joists (the one over the hatch is cut)
	for i in 6:
		var x := -W + 0.6 + i * 1.36
		if x > hx0 and x < hx0 + hole.size.x:
			kit.box(g, Vector3(0.07, 0.2, hz0 + D), Vector3(x, H - 0.1, (-D + hz0) * 0.5), Mats.m("wood"), Vector3.ZERO, false, 0.006)
			kit.box(g, Vector3(0.07, 0.2, D - hz1), Vector3(x, H - 0.1, (hz1 + D) * 0.5), Mats.m("wood"), Vector3.ZERO, false, 0.006)
			continue
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
	# (they stop before the ladder and turn into the wall)
	kit.cyl(g, 0.03, D, Vector3(W - 0.12, H - 0.25, D * 0.5), Mats.m("metal", Color(0.8, 0.6, 0.45)), Vector3(90, 0, 0), 10)
	kit.cyl(g, 0.02, D, Vector3(W - 0.2, H - 0.32, D * 0.5), Mats.m("steel_dark"), Vector3(90, 0, 0), 8)
	kit.cyl(g, 0.03, 0.14, Vector3(W - 0.06, H - 0.25, 0.0), Mats.m("metal", Color(0.8, 0.6, 0.45)), Vector3(0, 0, 90), 10)
	kit.cyl(g, 0.02, 0.22, Vector3(W - 0.1, H - 0.32, 0.0), Mats.m("steel_dark"), Vector3(0, 0, 90), 8)
	# electrical panel + conduit near the house door
	kit.box(g, Vector3(0.4, 0.55, 0.1), Vector3(W - 0.05, 1.55, -2.4), Mats.m("metal", Color(0.85, 0.85, 0.8), {"metallic_base": 0.4}), Vector3(0, 90, 0), true, 0.012)
	kit.label(g, "!", Vector3(W - 0.11, 1.68, -2.4), 80, Color(0.8, 0.6, 0.0), Vector3(0, -90, 0), 0.0015, true)
	kit.cyl(g, 0.016, 1.15, Vector3(W - 0.04, 2.4, -2.4), Mats.m("metal"), Vector3.ZERO, 8)
	outlet(g, Vector3(-W, 0.35, -0.1), 90.0)
	outlet(g, Vector3(W, 0.35, 1.0), -90.0)
	outlet(g, Vector3(-1.5, 1.1, -D), 0.0)

func _ceiling_piece(g: Node3D, x0: float, x1: float, z0: float, z1: float) -> void:
	kit.box(g, Vector3(x1 - x0, 0.12, z1 - z0), Vector3((x0 + x1) * 0.5, H + 0.06, (z0 + z1) * 0.5), Mats.m("drywall"), Vector3.ZERO, true, 0.0)
	# loft floorboards on top
	var ix0 := maxf(x0, -W)
	var ix1 := minf(x1, W)
	var iz0 := maxf(z0, -D)
	var iz1 := minf(z1, D)
	kit.box(g, Vector3(ix1 - ix0, 0.04, iz1 - iz0), Vector3((ix0 + ix1) * 0.5, H + 0.14, (iz0 + iz1) * 0.5), Mats.m("wood_planks", Color(1.35, 1.15, 0.95), {"cell": Vector2(2.4, 0.15)}), Vector3.ZERO, true, 0.0)

func _wall_piece(g: Node3D, x0: float, x1: float, y0: float, y1: float, z: float, mat: Material) -> void:
	kit.box(g, Vector3(x1 - x0, y1 - y0, T), Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, z), mat, Vector3.ZERO, true, 0.0)

func _rollup_door(g: Node3D) -> void:
	var z := D + 0.02
	# the door is rolled up into its drum: only the bottom bar + a strip of slats show at the top
	kit.box(g, Vector3(4.2, 0.22, 0.05), Vector3(-1.5, 2.3, z + 0.05), Mats.m("rollup"), Vector3.ZERO, false, 0.0)
	kit.box(g, Vector3(4.2, 0.06, 0.08), Vector3(-1.5, 2.19, z + 0.02), Mats.m("steel_dark"), Vector3.ZERO, false, 0.01)
	kit.box(g, Vector3(0.2, 0.04, 0.05), Vector3(-1.5, 2.14, z - 0.0), Mats.m("metal"), Vector3.ZERO, false, 0.01)
	kit.cable(g, Vector3(-1.4, 2.14, z), Vector3(-1.3, 1.25, z - 0.02), 0.0, 1, 0.006, Mats.m("plastic_white"))
	for x in [-3.62, 0.62]:
		kit.box(g, Vector3(0.07, 2.45, 0.1), Vector3(x, 1.22, z - 0.02), Mats.m("steel_dark"), Vector3.ZERO, true, 0.01)
		kit.box(g, Vector3(0.05, 0.05, 2.6), Vector3(x, 2.5, z - 1.3), Mats.m("steel_dark"), Vector3.ZERO, false, 0.008)
	# drum housing (fat: the door is rolled up inside)
	kit.cyl(g, 0.26, 4.35, Vector3(-1.5, 2.66, z - 0.18), Mats.m("metal", Color(0.75, 0.75, 0.75)), Vector3(0, 0, 90), 14)
	# threshold strip + hazard tape on the floor edge
	kit.box(g, Vector3(4.2, 0.012, 0.12), Vector3(-1.5, 0.006, z), Mats.m("steel_dark"), Vector3.ZERO, false, 0.0, false)
	for i in 14:
		kit.box(g, Vector3(0.14, 0.004, 0.06), Vector3(-3.45 + i * 0.3, 0.012, z - 0.12), Mats.m("metal_yellow", Color.WHITE, {"metallic_base": 0.0}), Vector3(0, 35, 0), false, 0.0, false)

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
	# invisible bounds: the player can step out onto the driveway (van), not wander off down the street
	kit.shape(Vector3(0.2, 4.0, 6.0), Transform3D(Basis(), Vector3(-6.2, 2.0, D + 3.0)))
	kit.shape(Vector3(0.2, 4.0, 6.0), Transform3D(Basis(), Vector3(5.0, 2.0, D + 3.0)))
	kit.shape(Vector3(11.4, 4.0, 0.2), Transform3D(Basis(), Vector3(-0.6, 2.0, D + 5.9)))
	# flood lamp over the door, outside: lights the van's back
	var fl := kit.node(o, Vector3(-1.5, 2.95, D + 0.2), 0.0, "FloodLamp")
	kit.box(fl, Vector3(0.3, 0.16, 0.12), Vector3(0, 0, 0.06), Mats.m("steel_dark"), Vector3(-25, 0, 0), false, 0.02)
	kit.box(fl, Vector3(0.26, 0.12, 0.01), Vector3(0, -0.03, 0.12), Mats.glow(Color(1.0, 0.85, 0.6), 7.0), Vector3(-25, 0, 0), false, 0.0, false)
	var fs := kit.spot(fl, Vector3(0, -0.05, 0.14), Vector3(0, -2.9, 2.2), Color(1.0, 0.82, 0.58), 4.5, 7.0, 55.0, true, 1.1)
	fs.position = Vector3(0, -0.05, 0.14)
	# traffic cone by the driveway
	prop("cone", Vector3(0.4, 0.24, D + 2.6))
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
	kit.string_lights(g, Vector3(2.9, H - 0.12, -0.2), Vector3(0.8, H - 0.12, D - 0.25), 0.35, 10, warm)
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
	dev_bench = DevBench.new()
	dev_bench.name = "DevBench"
	dev_bench.position = Vector3(-2.6, 0.915, -D + 0.38)
	live_root.add_child(dev_bench)
	# prototype shelf
	phone_shelf(g, Vector3(-0.45, 0, -D + 0.24), 0.0, "garage_shelf")
	# assembly table, freestanding
	var at := assembly_table(g, Vector3(1.0, 0, -1.55), 0.0, "garage_line")
	bench_view = BenchView.new()
	bench_view.name = "BenchView"
	at.add_child(bench_view)
	# sofa facing the TV on the right wall
	sofa(g, Vector3(2.05, 0, 1.7), 90.0)
	company_board(g, Vector3(W - 0.01, 1.55, 1.7), -90.0, "garage_board")
	_tv_cabinet(g, Vector3(W - 0.25, 0, 1.7))
	# coffee table: a pallet with a crate
	_pallet_table(g, Vector3(2.95, 0, 1.45))
	fridge(g, Vector3(W - 0.36, 0, -D + 0.5), -90.0)
	_podium(g, Vector3(1.05, 0, D - 0.55))
	# spare desk under the window (a design hire works here on a laptop)
	_spare_desk(g, Vector3(3.05, 0, D - 0.48))
	# job board by the house door
	job_board(g, Vector3(1.75, 1.45, -D + 0.01), 0.0, "garage_jobs")
	# clip lamp over the job board
	var cl := kit.node(g, Vector3(1.75, 2.05, -D + 0.12), 0.0, "ClipLamp")
	kit.cyl(cl, 0.05, 0.09, Vector3(0, 0, 0.04), Mats.m("metal_red"), Vector3(-60, 0, 0), 12)
	kit.mesh(cl, Meshes.sphere(0.022, 8), Vector3(0, -0.03, 0.07), Mats.glow(Color(1.0, 0.75, 0.45), 8.0), Vector3.ZERO, false)
	var jl := kit.spot(cl, Vector3(0, -0.03, 0.08), Vector3(0, -0.6, -0.08), Color(1.0, 0.75, 0.45), 2.2, 1.6, 60.0, false, 0.4)
	jl.position = Vector3(0, -0.03, 0.08)
	# shipping corner: pallet + taped floor + stencil, inside the roll-up door on the left
	_shipping_corner(g)
	# rug
	kit.box(g, Vector3(1.8, 0.01, 2.2), Vector3(2.7, 0.005, 1.55), Mats.m("carpet", Color(1.6, 0.9, 0.7)), Vector3.ZERO, false, 0.0, false)

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

## Cardboard keynote podium by the roll-up door: "stage_launch" (launch event for a finished prototype).
func _podium(g: Node3D, p: Vector3) -> void:
	var ia := kit.interactable(g, "stage_launch", "garage_podium", "Launch event", p, 180.0)
	kit.box(ia, Vector3(0.6, 1.05, 0.45), Vector3(0, 0.525, 0), Mats.m("plywood"), Vector3.ZERO, false, 0.02)
	kit.box(ia, Vector3(0.7, 0.04, 0.5), Vector3(0, 1.08, 0.03), Mats.m("plywood", Color(0.85, 0.8, 0.75)), Vector3(-12, 0, 0), false, 0.01)
	kit.box(ia, Vector3(0.5, 0.36, 0.004), Vector3(0, 0.66, 0.227), Mats.m("paper", Color(0.15, 0.15, 0.18)), Vector3.ZERO, false, 0.0, false)
	kit.label(ia, "KEYNOTE", Vector3(0, 0.7, 0.231), 72, Color(0.95, 0.8, 0.25), Vector3.ZERO, 0.0016, true)
	kit.label(ia, "LAUNCH", Vector3(0, 0.6, 0.231), 40, Color(0.8, 0.8, 0.8), Vector3.ZERO, 0.0016, true)
	# goose-neck mic
	kit.box(ia, Vector3(0.012, 0.3, 0.012), Vector3(0.15, 1.24, 0.0), Mats.m("steel_dark"), Vector3(-25, 0, 0), false, 0.0)
	kit.cyl(ia, 0.022, 0.07, Vector3(0.15, 1.38, 0.07), Mats.m("plastic_black"), Vector3(-60, 0, 0), 8)
	kit.ia_shape(ia, Vector3(0.7, 1.15, 0.5), Vector3(0, 0.575, 0))

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
	# clock above the house door
	var clock := kit.node(g, Vector3(1.6, 2.45, -D + 0.02), 0.0)
	kit.cyl(clock, 0.16, 0.04, Vector3.ZERO, Mats.m("plastic_white"), Vector3(90, 0, 0), 20)
	kit.box(clock, Vector3(0.012, 0.1, 0.004), Vector3(0, 0.04, 0.022), Mats.m("plastic_black"), Vector3(0, 0, -40), false, 0.0)
	kit.box(clock, Vector3(0.012, 0.13, 0.004), Vector3(0.02, -0.03, 0.023), Mats.m("plastic_black"), Vector3(0, 0, 130), false, 0.0)

# ------------------------------------------------------------------ grabbable props
func _props() -> void:
	# on the desk
	prop("keyboard", Vector3(-3.45, 0.8, -0.75), Vector3(0, 90, 0))
	prop("mug", Vector3(-3.7, 0.82, -0.2), Vector3.ZERO, 0)
	prop("can", Vector3(-3.45, 0.83, -1.35), Vector3.ZERO, 0)
	prop("phone_board", Vector3(-3.4, 0.79, -0.35), Vector3(0, 30, 0))
	# workbench (the right half is the prototype build area, see dev_bench.gd)
	prop("toolbox", Vector3(-3.55, 1.05, -3.2))
	prop("drill", Vector3(-1.55, 1.06, -3.25), Vector3(0, 30, 0))
	prop("screwdriver", Vector3(-2.9, 0.94, -2.85), Vector3(0, 70, 0), 1)
	prop("screwdriver", Vector3(-1.75, 0.94, -2.9), Vector3(0, 50, 0), 2)
	prop("tape_roll", Vector3(-1.5, 0.97, -2.95))
	prop("wrench", Vector3(-3.6, 0.94, -2.9), Vector3(0, 20, 0))
	prop("hammer", Vector3(-3.25, 0.25, -3.2), Vector3(0, -40, 0))
	prop("paint_can", Vector3(-3.3, 0.35, -3.0), Vector3.ZERO, 0)
	prop("paint_can", Vector3(-3.05, 0.35, -3.05), Vector3.ZERO, 1)
	prop("paint_can", Vector3(-2.2, 0.35, -3.0), Vector3.ZERO, 2)
	# assembly table
	prop("phone_proto", Vector3(0.6, 0.95, -1.35), Vector3(0, 10, 0), 0)
	prop("phone_board", Vector3(-0.3, 0.95, -1.45), Vector3(0, 40, 0))
	prop("battery_pack", Vector3(0.3, 0.95, -1.3))
	prop("mug", Vector3(1.75, 0.96, -1.25), Vector3.ZERO, 2)
	prop("stool", Vector3(-0.35, 0.68, -0.75))
	# prototype shelf: loose phones on the bottom shelves
	prop("phone_proto", Vector3(0.0, 0.16, -3.15), Vector3(0, 80, 0), 2)
	prop("box_s", Vector3(-0.8, 0.27, -3.25))
	prop("box_s", Vector3(-0.35, 0.27, -3.25), Vector3(0, 10, 0))
	# coffee table + sofa corner
	prop("pizza_box", Vector3(2.95, 0.2, 1.25), Vector3(0, 12, 0))
	prop("can", Vector3(2.85, 0.24, 1.8), Vector3.ZERO, 1)
	prop("can", Vector3(3.15, 0.2, 1.9), Vector3(90, 0, 30), 2)
	prop("mug", Vector3(3.1, 0.2, 0.95), Vector3.ZERO, 3)
	prop("router", Vector3(W - 0.25, 0.55, 1.2), Vector3(0, 90, 0))
	prop("ball", Vector3(-0.6, 0.15, 0.5))
	# boxes (junk) around
	prop("box_m", Vector3(-0.9, 0.2, 0.9), Vector3(0, 30, 0))
	prop("box_l", Vector3(2.3, 0.26, -2.75), Vector3(0, 12, 0))
	prop("box_m", Vector3(2.35, 0.75, -2.75), Vector3(0, -8, 0))
	prop("box_heavy", Vector3(-1.9, 0.25, -0.05), Vector3(0, 5, 0))
	prop("crate", Vector3(-3.4, 0.22, 0.3), Vector3(0, -10, 0))
	prop("trash_bin", Vector3(-1.95, 0.2, -0.75))
	prop("bottle", Vector3(-1.9, 1.0, -2.9))
	prop("book", Vector3(-3.6, 0.8, -1.25), Vector3(0, 80, 0), 1)
	prop("book", Vector3(-3.62, 0.84, -1.25), Vector3(0, 95, 0), 2)
	prop("can", Vector3(W - 0.36, 1.82, -D + 0.5), Vector3.ZERO, 3)
	prop("box_s", Vector3(W - 0.36, 1.86, -D + 0.8))
	prop("phone_proto", Vector3(3.0, 0.8, D - 0.45), Vector3(0, -20, 0), 1)

# ------------------------------------------------------------------ new furniture (iteration 2)
func _spare_desk(g: Node3D, p: Vector3) -> void:
	var d := kit.node(g, p, 0.0, "SpareDesk")
	# folding table + laptop, chair in front (faces the window)
	kit.box(d, Vector3(1.15, 0.035, 0.6), Vector3(0, 0.72, 0), Mats.m("plastic_white", Color(0.9, 0.9, 0.85)), Vector3.ZERO, true, 0.01)
	for sx in [-1.0, 1.0]:
		kit.box(d, Vector3(0.03, 0.7, 0.5), Vector3(sx * 0.52, 0.36, 0), Mats.m("steel_dark"), Vector3(0, 0, sx * 4.0), true, 0.006)
	var lap := kit.node(d, Vector3(0.05, 0.74, -0.02), 180.0, "Laptop")
	kit.box(lap, Vector3(0.34, 0.018, 0.24), Vector3(0, 0.009, 0), Mats.m("plastic_grey", Color(1.6, 1.6, 1.7)), Vector3.ZERO, false, 0.006)
	var lid := kit.node(lap, Vector3(0, 0.018, 0.12), 0.0)
	lid.rotation_degrees.x = -105
	kit.box(lid, Vector3(0.34, 0.01, 0.23), Vector3(0, 0, -0.115), Mats.m("plastic_grey", Color(1.6, 1.6, 1.7)), Vector3.ZERO, false, 0.006)
	kit.mesh(lid, Meshes.quad(Vector2(0.3, 0.19)), Vector3(0, 0.006, -0.115), Mats.screen(0, Color(0.45, 0.85, 1.0), 1.4, 7.0), Vector3(-90, 0, 0), false)
	monitor_lights.append(kit.omni(d, Vector3(0.05, 1.0, -0.25), Color(0.45, 0.7, 1.0), 0.35, 1.6, false, 0.3))
	kit.box(d, Vector3(0.08, 0.1, 0.08), Vector3(-0.4, 0.79, 0.1), Mats.m("ceramic", Color(0.2, 0.3, 0.6)), Vector3.ZERO, false, 0.01)
	office_chair(d, Vector3(0.05, 0, -0.62), 0.0)
	add_slot("design", p + Vector3(0.05, 0, -0.66), 0.0, "sit_type", 0.5)

func _shipping_corner(g: Node3D) -> void:
	var c := kit.node(g, Vector3(-2.7, 0, 2.92), 0.0, "ShippingCorner")
	for i in 2:
		var pal := kit.node(c, Vector3(-0.32 + i * 0.86, 0, 0), 0.0)
		for k in 5:
			kit.box(pal, Vector3(0.8, 0.022, 0.13), Vector3(0, 0.125, -0.36 + k * 0.18), Mats.m("plywood", Color(0.85, 0.8, 0.7)), Vector3(0, rng_off(k + i), 0), false, 0.005)
		for z in [-0.35, 0.0, 0.35]:
			kit.box(pal, Vector3(0.8, 0.1, 0.09), Vector3(0, 0.06, z), Mats.m("plywood", Color(0.75, 0.7, 0.6)), Vector3.ZERO, false, 0.008)
		kit.shape(Vector3(0.8, 0.14, 0.85), pal.global_transform.translated_local(Vector3(0, 0.07, 0)))
	var tape := Mats.m("metal_yellow", Color.WHITE, {"metallic_base": 0.0, "roughness_base": 0.6, "grime": 0.6, "grime_scale": 3.0})
	for sz in [-1.0, 1.0]:
		kit.box(c, Vector3(1.9, 0.004, 0.06), Vector3(0.1, 0.002, sz * 0.5), tape, Vector3.ZERO, false, 0.0, false)
	for sx in [-1.0, 1.0]:
		kit.box(c, Vector3(0.06, 0.004, 1.0), Vector3(0.1 + sx * 0.95, 0.002, 0), tape, Vector3.ZERO, false, 0.0, false)
	kit.label(c, "SHIPPING", Vector3(1.38, 0.006, -0.1), 120, Color(0.95, 0.8, 0.2, 0.85), Vector3(-90, 90, 0), 0.0018, true)
	# clipboard on the wall + hand truck
	kit.box(c, Vector3(0.24, 0.32, 0.015), Vector3(-1.29, 1.45, -0.6), Mats.m("plywood"), Vector3(0, 90, 0), false, 0.004)
	kit.box(c, Vector3(0.2, 0.26, 0.004), Vector3(-1.28, 1.43, -0.6), Mats.m("paper"), Vector3(0, 90, 0), false, 0.0, false)
	kit.label(c, "SHIP\nTO VAN\n->", Vector3(-1.275, 1.44, -0.6), 40, Color(0.15, 0.15, 0.2), Vector3(0, 90, 0), 0.0012, true)

# ------------------------------------------------------------------ attic (second floor shell)
func _attic() -> void:
	var g := kit.node(self, Vector3.ZERO, 0.0, "Attic")
	var y0 := H + 0.1                  # top of the garage walls
	var fy: float = Loft.FLOOR_Y
	var kh := fy + KNEE - y0           # knee wall height above the garage walls
	var ytop := y0 + kh
	var wall := Mats.m("siding_warm", Color(0.85, 0.85, 0.85))
	for sx in [-1.0, 1.0]:
		kit.box(g, Vector3(T, kh, 2 * D + 2 * T), Vector3(sx * (W + T * 0.5), y0 + kh * 0.5, 0), wall, Vector3.ZERO, true, 0.0)
	for sz in [-1.0, 1.0]:
		kit.box(g, Vector3(2 * W + 2 * T, kh, T), Vector3(0, y0 + kh * 0.5, sz * (D + T * 0.5)), wall, Vector3.ZERO, true, 0.0)
		_gable_triangle(g, sz * (D + T * 0.5), ytop, wall)
	# roof: two slabs + inner plywood sheathing + rafters
	var half := W + T + 0.35
	var ang := atan2(RISE, W + T)
	var slab_len := half / cos(ang)
	for sx in [-1.0, 1.0]:
		var cx: float = sx * half * 0.5
		var cy := ytop + RISE * 0.5 - (0.35 * tan(ang)) * 0.5 + 0.08
		kit.box(g, Vector3(slab_len, 0.14, 2 * D + 2 * T + 0.5), Vector3(cx, cy, 0), Mats.m("roof"), Vector3(0, 0, -sx * rad_to_deg(ang)), true, 0.0)
		kit.box(g, Vector3(slab_len - 0.3, 0.03, 2 * D), Vector3(cx * 0.92, cy - 0.1, 0), Mats.m("plywood", Color(0.8, 0.75, 0.7)), Vector3(0, 0, -sx * rad_to_deg(ang)), false, 0.0)
		for i in 7:
			var z := -D + 0.4 + i * (2 * D - 0.8) / 6.0
			kit.box(g, Vector3(slab_len - 0.4, 0.14, 0.07), Vector3(cx * 0.9, cy - 0.18, z), Mats.m("wood"), Vector3(0, 0, -sx * rad_to_deg(ang)), false, 0.006)
	kit.box(g, Vector3(0.12, 0.18, 2 * D), Vector3(0, ytop + RISE - 0.05, 0), Mats.m("wood"), Vector3.ZERO, false, 0.01)  # ridge beam
	# gable windows (front shows the street, back is dark): frame + glass glow
	for sz in [-1.0, 1.0]:
		var wz: float = sz * (D + T * 0.5)
		for side in [-1.0, 1.0]:
			var fz: float = wz + side * (T * 0.5 + 0.005)
			kit.box(g, Vector3(0.9, 0.62, 0.02), Vector3(0, fy + 1.55, fz), Mats.m("plaster", Color(1.15, 1.15, 1.1)), Vector3.ZERO, false, 0.006)
			var gc := Color(0.25, 0.35, 0.6) if side * sz > 0 else Color(0.12, 0.16, 0.3)
			kit.box(g, Vector3(0.78, 0.5, 0.01), Vector3(0, fy + 1.55, fz + side * 0.008), Mats.glow(gc, 0.6 if sz > 0 else 0.25), Vector3.ZERO, false, 0.0, false)
			kit.box(g, Vector3(0.04, 0.5, 0.012), Vector3(0, fy + 1.55, fz + side * 0.012), Mats.m("plaster", Color(1.15, 1.15, 1.1)), Vector3.ZERO, false, 0.0, false)
	# junk that used to clutter the garage
	_water_heater(g, Vector3(-W + 0.45, fy, -D + 0.45))
	for i in 3:
		kit.cyl(g, 0.32, 0.2, Vector3(-W + 0.5, fy + 0.1 + i * 0.21, D - 0.6), Mats.m("rubber", Color(1.3, 1.3, 1.3), {"pattern": 6}), Vector3(0, i * 20, 0), 18, i == 0)
	kit.box(g, Vector3(0.8, 0.55, 0.6), Vector3(W - 0.6, fy + 0.275, D - 0.5), Mats.m("cardboard", Color(0.9, 0.85, 0.8)), Vector3(0, 4, 0), true, 0.02)
	kit.box(g, Vector3(0.7, 0.45, 0.55), Vector3(W - 0.55, fy + 0.78, D - 0.48), Mats.m("cardboard"), Vector3(0, -6, 0), true, 0.02)
	kit.label(g, "XMAS", Vector3(W - 0.55, fy + 0.8, D - 0.765), 60, Color(0.1, 0.1, 0.1), Vector3(0, 174, 0), 0.0016, true)
	# old bicycle leaning in the attic (just a frame silhouette)
	var bike := kit.node(g, Vector3(-1.2, Loft.FLOOR_Y + 0.33, D - 0.35), 0.0)
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
	# old armchair under a dust sheet
	kit.box(g, Vector3(0.9, 0.85, 0.85), Vector3(W - 0.7, fy + 0.42, 1.0), Mats.m("fabric", Color(2.2, 2.2, 2.1)), Vector3(0, -12, 0), true, 0.15)

## Triangular top of a gable wall (extruded along z), with collision.
func _gable_triangle(g: Node3D, z: float, base_y: float, mat: Material) -> void:
	var hw := W + T
	var pts := [Vector3(-hw, base_y, 0), Vector3(hw, base_y, 0), Vector3(0, base_y + RISE, 0)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hz := T * 0.5
	var f := pts.map(func(p: Vector3) -> Vector3: return p + Vector3(0, 0, hz))
	var b := pts.map(func(p: Vector3) -> Vector3: return p - Vector3(0, 0, hz))
	var tris := [[f[0], f[1], f[2]], [b[0], b[2], b[1]],
		[f[0], f[2], b[2]], [f[0], b[2], b[0]], [f[1], b[1], b[2]], [f[1], b[2], f[2]], [f[0], b[0], b[1]], [f[0], b[1], f[1]]]
	for t in tris:
		var n: Vector3 = (t[2] - t[0]).cross(t[1] - t[0]).normalized()
		for v in t:
			st.set_normal(n)
			st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.position = Vector3(0, 0, z)
	g.add_child(mi)
	var cs := CollisionShape3D.new()
	var cp := ConvexPolygonShape3D.new()
	cp.points = PackedVector3Array(f + b)
	cs.shape = cp
	kit.body.add_child(cs)
	cs.global_transform = mi.global_transform

# ------------------------------------------------------------------ live (state-driven) parts
func _live() -> void:
	loft = Loft.new()
	loft.name = "Loft"
	loft.level = self
	live_root.add_child(loft)
	dock = ShipDock.new()
	dock.name = "Van"
	dock.style = "van"
	dock.dock_id = "garage_van"
	dock.position = Vector3(-1.5, 0, D + 1.5)
	var nm := str(Game.state.get("name", "")).to_upper()
	if nm != "":
		dock.brand = nm.substr(0, 18)
	var logo: Dictionary = Game.state.get("logo", {}) if Game.state.get("logo") is Dictionary else {}
	if str(logo.get("colorA", "")).is_valid_html_color():
		dock.brand_col = Color.html(str(logo.colorA))
	live_root.add_child(dock)
	shipping = Shipping.new()
	shipping.name = "Shipping"
	shipping.dock = dock
	shipping.zone = Transform3D(Basis(), Vector3(-3.25, 0.14, 2.7))
	live_root.add_child(shipping)

func _staff_slots() -> void:
	# design: spare desk (added in _spare_desk) + the prototype workbench
	add_slot("design", Vector3(-2.15, 0, -2.42), 180.0, "stand_assemble")
	add_slot("design", Vector3(-3.15, 0, -2.42), 180.0, "stand_assemble")
	# research: at the whiteboard on the left wall
	add_slot("research", Vector3(-3.5, 0, 1.4), -90.0, "stand_scribble")
	add_slot("research", Vector3(-3.0, 0, 2.3), -115.0, "stand_think")
	# assembly: hand-assembly bench (upstairs line operators are added by staff_slots())
	add_slot("assembly", Vector3(0.6, 0, -0.88), 180.0, "stand_assemble")
	add_slot("assembly", Vector3(1.4, 0, -0.88), 180.0, "stand_assemble")
	# office: the sofa
	add_slot("office", Vector3(2.12, 0, 2.05), 90.0, "sit_idle", 0.5)
	add_slot("office", Vector3(2.12, 0, 1.3), 90.0, "sit_idle", 0.5)
	# overflow: sit on boxes
	add_slot("overflow", Vector3(-2.45, 0, 0.75), -70.0, "sit_idle", 0.44)
	add_slot("overflow", Vector3(-0.2, 0, 1.55), 160.0, "sit_idle", 0.44)
	add_slot("overflow", Vector3(0.75, 0, -2.6), 200.0, "sit_idle", 0.44)
	add_slot("overflow", Vector3(2.75, 0, -1.9), -120.0, "sit_idle", 0.44)

func staff_slots() -> Dictionary:
	var out := super.staff_slots()
	if loft and loft.unlocked:
		out["assembly"] = loft.staff_slots() + out["assembly"]
	return out

func surface_at(p: Vector3) -> String:
	if p.y > H - 0.2:
		return "wood"
	if p.z > D + 0.2 and p.y > 0.25 and absf(p.x + 1.5) < 1.1:
		return "metal"
	return "concrete"

func ambient_at(p: Vector3) -> String:
	if p.y > H - 0.2:
		return "loft"
	if p.z > D + 0.3:
		return "outdoor"
	return "garage"

func _viewpoints() -> void:
	kit.viewpoint(self, "overview", Vector3(-3.3, 2.35, 2.6), Vector3(1.6, 0.7, -1.4), 76.0)
	kit.viewpoint(self, "spawn", Vector3(0.9, 1.6, 2.3), Vector3(0.9 - sin(deg_to_rad(18.0)) * 3.0, 1.35, 2.3 - cos(deg_to_rad(18.0)) * 3.0), 75.0)
	kit.viewpoint(self, "desk", Vector3(-2.35, 1.55, 0.45), Vector3(-3.7, 0.95, -1.0), 70.0)
	kit.viewpoint(self, "workbench", Vector3(-1.1, 1.65, -1.0), Vector3(-2.7, 1.2, -3.4), 70.0)
	kit.viewpoint(self, "sofa", Vector3(-0.6, 1.65, -0.6), Vector3(3.0, 0.9, 2.2), 72.0)
	kit.viewpoint(self, "window", Vector3(0.9, 1.55, 0.2), Vector3(2.6, 1.45, 3.6), 70.0)
	kit.viewpoint(self, "beam", Vector3(-0.8, 1.7, -0.5), Vector3(1.6, 0.4, 2.2), 75.0)
	kit.viewpoint(self, "back", Vector3(-1.5, 1.6, -2.4), Vector3(1.5, 1.0, 3.0), 75.0)
	kit.viewpoint(self, "build", Vector3(-1.3, 1.5, -1.75), Vector3(-2.6, 0.95, -3.2), 60.0)
	kit.viewpoint(self, "whiteboard", Vector3(-1.75, 1.75, 1.0), Vector3(-4.0, 1.4, 1.75), 66.0)
	kit.viewpoint(self, "loft", Vector3(3.3, H + 1.85, -2.6), Vector3(-1.5, H + 0.6, 1.2), 74.0)
	kit.viewpoint(self, "van", Vector3(-0.4, 1.7, 1.2), Vector3(-1.6, 0.9, 5.4), 72.0)
	kit.viewpoint(self, "staff", Vector3(2.6, 2.45, 3.25), Vector3(-1.2, 0.6, -1.2), 80.0)
	kit.viewpoint(self, "hatch", Vector3(1.7, 1.6, 0.35), Vector3(3.5, 2.5, -1.15), 70.0)
	kit.viewpoint(self, "jobs", Vector3(1.75, 1.5, -2.2), Vector3(1.75, 1.45, -3.5), 60.0)
