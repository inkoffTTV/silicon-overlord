extends "res://world/levels/level_base.gd"
## HQ level 2+ — rented office. Level 2 = small office on the 2nd floor of an old building.
## Levels 3..7 reuse this builder (rough): the floor grows, more desks appear, and the street drops
## away below the windows (skyscraper floor at 7). Interior x[-hw,hw] z[-hd,hd], ceiling H.

const H := 2.8
const T := 0.2

var hw := 6.0
var hd := 4.5
var altitude := 4.0

func _build() -> void:
	var lv := clampi(level, 2, 7)
	hw = [6.0, 9.0, 11.0, 13.0, 14.0, 15.0][lv - 2]
	hd = [4.5, 6.0, 7.0, 8.0, 9.0, 9.0][lv - 2]
	altitude = [4.0, 8.0, 16.0, 30.0, 60.0, 120.0][lv - 2]
	_shell(lv)
	_city()
	_furniture(lv)
	_lights(lv)
	set_spawn(Vector3(hw - 1.6, 0.05, hd - 1.4), 40.0)
	kit.viewpoint(self, "overview", Vector3(hw - 0.6, 2.3, hd - 0.6), Vector3(-hw * 0.4, 0.6, -hd * 0.5), 76.0)
	kit.viewpoint(self, "windows", Vector3(0.0, 1.6, 0.5), Vector3(-hw, 1.2, -hd * 0.2), 74.0)

func _shell(lv: int) -> void:
	var g := kit.node(self, Vector3.ZERO, 0.0, "Shell")
	var carpet := Mats.m("carpet") if lv < 5 else Mats.m("floor_tiles", Color(0.8, 0.82, 0.85))
	kit.box(g, Vector3(2 * hw + 2 * T, 0.2, 2 * hd + 2 * T), Vector3(0, -0.1, 0), carpet, Vector3.ZERO, true, 0.0)
	kit.box(g, Vector3(2 * hw + 2 * T, 0.1, 2 * hd + 2 * T), Vector3(0, H + 0.05, 0), Mats.m("ceiling_tiles"), Vector3.ZERO, true, 0.0)
	var wall := Mats.m("plaster_cool") if lv < 5 else Mats.m("plaster", Color(0.9, 0.92, 0.95))
	# back, right and front walls solid; left wall (-X) is the window wall
	kit.box(g, Vector3(2 * hw + 2 * T, H, T), Vector3(0, H * 0.5, -hd - T * 0.5), wall, Vector3.ZERO, true, 0.0)
	kit.box(g, Vector3(2 * hw + 2 * T, H, T), Vector3(0, H * 0.5, hd + T * 0.5), wall, Vector3.ZERO, true, 0.0)
	kit.box(g, Vector3(T, H, 2 * hd), Vector3(hw + T * 0.5, H * 0.5, 0), wall, Vector3.ZERO, true, 0.0)
	# window wall: sill + header + mullions + glass
	var x := -hw - T * 0.5
	kit.box(g, Vector3(T, 0.75, 2 * hd), Vector3(x, 0.375, 0), wall, Vector3.ZERO, true, 0.0)
	kit.box(g, Vector3(T, 0.35, 2 * hd), Vector3(x, H - 0.175, 0), wall, Vector3.ZERO, true, 0.0)
	kit.box(g, Vector3(0.3, 0.05, 2 * hd), Vector3(-hw + 0.1, 0.77, 0), Mats.m("plastic_white"), Vector3.ZERO, true, 0.01)
	var n := int(hd * 2 / 1.5)
	for i in n + 1:
		var z := -hd + i * (2 * hd / n)
		kit.box(g, Vector3(0.12, H - 1.1, 0.08), Vector3(x + 0.04, 0.75 + (H - 1.1) * 0.5, z), Mats.m("steel_dark"), Vector3.ZERO, false, 0.01)
	kit.box(g, Vector3(0.01, H - 1.1, 2 * hd), Vector3(x, 0.75 + (H - 1.1) * 0.5, 0), Mats.glass(Color(0.5, 0.6, 0.7, 0.1)), Vector3.ZERO, true, 0.0, false).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# baseboards
	for s in [-1.0, 1.0]:
		kit.box(g, Vector3(2 * hw, 0.08, 0.02), Vector3(0, 0.04, s * (hd - 0.01)), Mats.m("plastic_grey"), Vector3.ZERO, false, 0.0)
	door_exit(g, Vector3(hw - 1.4, 0, hd - 0.005), 180.0, "office_door", Color(0.85, 0.9, 1.0))
	outlet(g, Vector3(hw, 0.3, 0.0), -90.0)

func _city() -> void:
	# cheap night city below/around the window wall
	var o := kit.node(self, Vector3(0, -altitude, 0), 0.0, "City")
	kit.box(o, Vector3(400, 0.2, 400), Vector3(-200, -0.1, 0), Mats.m("asphalt"), Vector3.ZERO, false, 0.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99 + level
	for i in 26:
		var bx := -hw - rng.randf_range(14, 120)
		var bz := rng.randf_range(-90, 90)
		var bh := rng.randf_range(6, 30) + altitude * rng.randf_range(0.2, 1.4)
		var bw := rng.randf_range(8, 18)
		var b := kit.node(o, Vector3(bx, 0, bz), 0.0)
		kit.box(b, Vector3(bw, bh, bw), Vector3(0, bh * 0.5, 0), Mats.m("plaster", Color(0.25, 0.27, 0.32)), Vector3.ZERO, false, 0.0)
		# a few rows of lit windows on the facade that faces us (+X)
		var rows := int(bh / 3.2)
		for r in rows:
			if rng.randf() < 0.45:
				continue
			var c := Color(1.0, 0.75, 0.45) if rng.randf() < 0.7 else Color(0.6, 0.8, 1.0)
			kit.box(b, Vector3(0.05, 1.1, bw * rng.randf_range(0.3, 0.9)), Vector3(bw * 0.5 + 0.03, 1.8 + r * 3.2, rng.randf_range(-1, 1)), Mats.glow(c, 1.6), Vector3.ZERO, false, 0.0, false)
	kit.omni(o, Vector3(-hw - 20, altitude + 6, 0), Color(0.5, 0.6, 1.0), 2.0, 40.0, false, 0.0)

func _furniture(lv: int) -> void:
	var g := kit.node(self, Vector3.ZERO, 0.0, "Furniture")
	# rows of desks facing the window wall
	var ndesk: int = [3, 6, 10, 14, 18, 22][lv - 2]
	var cols := maxi(1, int((2 * hd - 1.0) / 1.7))
	var placed := 0
	var row := 0
	while placed < ndesk and row < 8:
		var x := -hw + 2.2 + row * 2.4
		if x > hw - 2.5:
			break
		for c in cols:
			if placed >= ndesk:
				break
			var z := -hd + 1.2 + c * 1.7
			if placed == 0:
				desk_pc(g, Vector3(x, 0, z), -90.0, "office_pc", false)
			else:
				_plain_desk(g, Vector3(x, 0, z), -90.0, placed)
			prop("chair", Vector3(x - 0.75, 0.5, z), Vector3(0, 90, 0))
			placed += 1
		row += 1
	# back wall: whiteboard, shelf, board
	whiteboard(g, Vector3(-hw + 2.6, 0, -hd + 0.02), 0.0, "office_whiteboard")
	phone_shelf(g, Vector3(hw - 1.2, 0, -hd + 0.24), 0.0, "office_shelf")
	company_board(g, Vector3(hw - 0.01, 1.6, -0.6), -90.0, "office_board", Vector2(1.6, 0.9))
	wall_calendar(g, Vector3(hw - 0.01, 1.55, 1.2), -90.0)
	assembly_table(g, Vector3(hw - 2.6, 0, 1.0), 90.0, "office_line")
	poster(g, Vector3(0.6, 1.6, -hd + 0.01), 0.0, "THINK\nBIGGER", Color(0.1, 0.12, 0.2), Color(0.4, 0.8, 1.0), Vector2(0.5, 0.7))
	# water cooler + plant + lounge
	var wc := kit.node(g, Vector3(hw - 0.35, 0, hd - 2.6), 0.0)
	kit.box(wc, Vector3(0.32, 1.0, 0.32), Vector3(0, 0.5, 0), Mats.m("plastic_white"), Vector3.ZERO, true, 0.03)
	kit.cyl(wc, 0.14, 0.4, Vector3(0, 1.2, 0), Mats.glass(Color(0.4, 0.6, 0.9, 0.5)), Vector3.ZERO, 14)
	var plant := kit.node(g, Vector3(-hw + 0.4, 0, hd - 0.4), 0.0)
	kit.cyl(plant, 0.2, 0.4, Vector3(0, 0.2, 0), Mats.m("ceramic", Color(0.6, 0.4, 0.3)), Vector3.ZERO, 14, true)
	for i in 5:
		kit.mesh(plant, Meshes.sphere(0.25, 8), Vector3(sin(i * 1.3) * 0.15, 0.6 + i * 0.12, cos(i * 1.3) * 0.15), Mats.m("grass", Color(1.4, 2.0, 1.2), {"pattern": 0}), Vector3.ZERO)
	sofa(g, Vector3(1.0, 0, hd - 0.6), 180.0, Mats.m("fabric_blue"))
	# props
	for i in 6:
		prop(["box_m", "box_s", "box_l"][i % 3], Vector3(hw - 0.6 - (i % 2) * 0.6, 0.3 + (i / 2) * 0.0, hd - 0.8 - (i / 2) * 0.7), Vector3(0, i * 17, 0))
	prop("mug", Vector3(-hw + 2.0, 0.82, -hd + 1.0), Vector3.ZERO, 1)
	prop("phone_proto", Vector3(hw - 2.6, 0.96, 1.2), Vector3.ZERO, 1)
	prop("trash_bin", Vector3(-hw + 1.2, 0.2, hd - 1.0))
	prop("ball", Vector3(0.0, 0.2, 1.0))

func _plain_desk(g: Node3D, p: Vector3, rot: float, i: int) -> void:
	var d := kit.node(g, p, rot)
	kit.box(d, Vector3(1.4, 0.04, 0.7), Vector3(0, 0.74, 0), Mats.m("plastic_white"), Vector3.ZERO, true, 0.01)
	for x in [-0.65, 0.65]:
		kit.box(d, Vector3(0.05, 0.72, 0.6), Vector3(x, 0.36, 0), Mats.m("steel_dark"), Vector3.ZERO, true, 0.008)
	kit.box(d, Vector3(0.55, 0.33, 0.03), Vector3(0, 1.1, -0.2), Mats.m("plastic_black"), Vector3.ZERO, false, 0.01)
	kit.box(d, Vector3(0.04, 0.3, 0.03), Vector3(0, 0.9, -0.23), Mats.m("plastic_grey"), Vector3.ZERO, false, 0.005)
	kit.mesh(d, Meshes.quad(Vector2(0.52, 0.3)), Vector3(0, 1.1, -0.184), Mats.screen(i % 3, Color(0.4, 0.8, 1.0), 1.2, float(i)), Vector3.ZERO, false)
	kit.box(d, Vector3(0.42, 0.02, 0.14), Vector3(0, 0.77, 0.12), Mats.m("plastic_black"), Vector3.ZERO, false, 0.005)

func _lights(lv: int) -> void:
	var g := kit.node(self, Vector3.ZERO, 0.0, "Lights")
	# recessed fluorescent panels on a grid; shadows only on a couple
	var nx := maxi(2, int(hw / 3.0))
	var nz := maxi(2, int(hd / 3.0))
	var idx := 0
	for i in nx:
		for j in nz:
			var x := -hw + (i + 0.5) * (2 * hw / nx)
			var z := -hd + (j + 0.5) * (2 * hd / nz)
			kit.box(g, Vector3(1.2, 0.02, 0.6), Vector3(x, H - 0.005, z), Mats.glow(Color(0.85, 0.93, 1.0), 2.5), Vector3.ZERO, false, 0.0, false)
			var shadow := idx < 2
			var l := kit.spot(g, Vector3(x, H - 0.05, z), Vector3(x, 0, z + 0.001), Color(0.85, 0.93, 1.0), 4.5, 6.0, 80.0, shadow, 0.6)
			if idx == 3:
				var f := Flicker.new()
				f.light = l
				f.instability = 0.5
				g.add_child(f)
			idx += 1
	kit.omni(g, Vector3(0, 2.0, 0), Color(1.0, 0.8, 0.6), 1.2, 9.0, false, 0.3)
