extends Node3D
## Base class for HQ levels. A level builds itself in build_level() (called by world.gd while in tree).
## Shared furniture builders live here so every HQ level reuses the same interactables.
## Furniture convention: builder(parent, pos, rot_y) — local front faces +Z, origin on the floor.

const Mats := preload("res://world/lib/mats.gd")
const Meshes := preload("res://world/lib/meshes.gd")
const Kit := preload("res://world/lib/kit.gd")
const Props := preload("res://world/props/props.gd")
const Flicker := preload("res://fx/flicker.gd")
const ResearchBoard := preload("res://world/live/research_board.gd")
const ProtoShelf := preload("res://world/live/proto_shelf.gd")
const JobBoard := preload("res://world/live/job_board.gd")
const Staff := preload("res://world/live/staff.gd")

const MONTHS := ["JANUARY", "FEBRUARY", "MARCH", "APRIL", "MAY", "JUNE", "JULY", "AUGUST", "SEPTEMBER", "OCTOBER", "NOVEMBER", "DECEMBER"]

var kit: Kit
var level := 1
var spawn_xform := Transform3D.IDENTITY
var props_root: Node3D
var board_labels: Array[Label3D] = []
var calendars: Array = [] # [{header, big, marks:Array[MeshInstance3D], ring}]
var monitor_lights: Array = []
var live_root: Node3D
var research_boards: Array = []
var proto_shelf: Node
var staff: Node3D
## station -> [{pos (level-local), yaw (radians, model faces +Z), pose, seat_h}]; see staff.gd
var _slots := {"design": [], "research": [], "assembly": [], "office": [], "overflow": []}

func build_level() -> void:
	kit = Kit.new(self)
	props_root = kit.node(self, Vector3.ZERO, 0.0, "Props")
	live_root = kit.node(self, Vector3.ZERO, 0.0, "Live")
	_build()
	staff = Staff.new()
	staff.name = "Staff"
	staff.level = self
	live_root.add_child(staff)

## Override in level scripts.
func _build() -> void:
	pass

## Staff slot (pos in level space; yaw_deg = direction the person faces, 0 = +Z).
func add_slot(station: String, pos: Vector3, yaw_deg: float, pose: String, seat_h: float = 0.47) -> void:
	_slots[station].append({"pos": pos, "yaw": deg_to_rad(yaw_deg), "pose": pose, "seat_h": seat_h})

## For staff.gd: global slots per station.
func staff_slots() -> Dictionary:
	var out := {}
	for k in _slots:
		out[k] = _slots[k].map(func(sl: Dictionary) -> Dictionary:
			var d := sl.duplicate()
			d.pos = global_transform * sl.pos
			d.yaw = float(sl.yaw) + global_rotation.y
			return d)
	return out

## Footstep surface under a level-space point: "concrete" | "wood" | "metal".
func surface_at(_p: Vector3) -> String:
	return "concrete"

## Ambient room tone for a level-space point (Sfx.ambient names).
func ambient_at(_p: Vector3) -> String:
	return "garage"

func set_spawn(pos: Vector3, yaw_deg: float) -> void:
	spawn_xform = Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), pos)

func prop(kind: String, pos: Vector3, rot: Vector3 = Vector3.ZERO, variant: int = 0) -> RigidBody3D:
	var p := Props.make(kind, pos, rot, variant)
	props_root.add_child(p)
	return p

# ---------------------------------------------------------------- shared data hooks
func set_board_lines(lines: Array) -> void:
	var text := "\n".join(lines.map(func(l: Variant) -> String: return str(l)))
	for l in board_labels:
		if is_instance_valid(l):
			l.text = text

func set_date(year: int, day: int) -> void:
	day = clampi(day, 1, 360)
	var month := (day - 1) / 30
	var dom := (day - 1) % 30 + 1
	for c in calendars:
		c["header"].text = "%s %d" % [MONTHS[month], year]
		c["big"].text = str(dom)
		var marks: Array = c["marks"]
		for i in marks.size():
			marks[i].visible = i < dom - 1
		var cell: Vector3 = c["cells"][dom - 1]
		c["ring"].position = cell + Vector3(0, 0, 0.002)

# ---------------------------------------------------------------- furniture
func desk_pc(parent: Node3D, pos: Vector3, rot_y: float, id: String = "pc_1", crt: bool = true, chair: bool = true) -> StaticBody3D:
	var ia := kit.interactable(parent, "pc_design", id, "Design a phone", pos, rot_y)
	if chair:
		office_chair(ia, Vector3(-0.05, 0, 0.62), 180.0, "pc_challenge", id, "Sit at the PC (challenge)")
	var top_mat := Mats.m("wood_dark") if crt else Mats.m("plastic_white")
	kit.box(ia, Vector3(1.5, 0.05, 0.75), Vector3(0, 0.735, 0), top_mat, Vector3.ZERO, false, 0.012)
	for x in [-0.7, 0.7]:
		for z in [-0.33, 0.33]:
			if x > 0.0:
				continue
			kit.box(ia, Vector3(0.05, 0.71, 0.05), Vector3(x, 0.355, z), Mats.m("steel_dark"), Vector3.ZERO, false, 0.008)
	# drawer unit
	kit.box(ia, Vector3(0.42, 0.71, 0.68), Vector3(0.52, 0.355, 0.0), Mats.m("wood_dark"), Vector3.ZERO, false, 0.01)
	for i in 3:
		kit.box(ia, Vector3(0.38, 0.2, 0.02), Vector3(0.52, 0.12 + i * 0.225, 0.345), Mats.m("wood", Color(0.8, 0.8, 0.8)), Vector3.ZERO, false, 0.008)
		kit.box(ia, Vector3(0.12, 0.018, 0.025), Vector3(0.52, 0.17 + i * 0.225, 0.36), Mats.m("metal"), Vector3.ZERO, false, 0.005)
	kit.box(ia, Vector3(1.0, 0.5, 0.02), Vector3(-0.2, 0.45, -0.34), Mats.m("wood_dark"), Vector3.ZERO, false, 0.005)
	if crt:
		# chunky beige CRT
		var mon := kit.node(ia, Vector3(-0.05, 0.76, -0.1), 0.0, "Monitor")
		kit.box(mon, Vector3(0.24, 0.03, 0.2), Vector3(0, 0.015, 0), Mats.m("plastic_beige"), Vector3.ZERO, false, 0.01)
		kit.box(mon, Vector3(0.44, 0.38, 0.32), Vector3(0, 0.24, 0.0), Mats.m("plastic_beige"), Vector3.ZERO, false, 0.035)
		kit.box(mon, Vector3(0.32, 0.27, 0.2), Vector3(0, 0.23, -0.24), Mats.m("plastic_beige", Color(0.9, 0.9, 0.9)), Vector3.ZERO, false, 0.04)
		kit.box(mon, Vector3(0.37, 0.3, 0.02), Vector3(0, 0.25, 0.155), Mats.m("plastic_black", Color(3, 3, 3)), Vector3.ZERO, false, 0.01)
		var scr := kit.mesh(mon, Meshes.quad(Vector2(0.33, 0.26)), Vector3(0, 0.25, 0.167), Mats.screen(1, Color(0.35, 0.85, 1.0), 1.7, 1.0), Vector3.ZERO, false)
		scr.mesh = Meshes.quad(Vector2(0.33, 0.26))
		kit.box(mon, Vector3(0.012, 0.012, 0.004), Vector3(0.16, 0.07, 0.161), Mats.glow(Color(0.3, 1.0, 0.3), 4.0), Vector3.ZERO, false, 0.0, false)
		# sticky notes on the bezel
		for i in 3:
			var c: Color = [Color(1.0, 0.9, 0.3), Color(1.0, 0.55, 0.7), Color(0.6, 0.95, 0.6)][i]
			kit.box(mon, Vector3(0.06, 0.06, 0.002), Vector3(0.2 + (i % 2) * 0.01, 0.38 - i * 0.065, 0.15), Mats.m("paper", c), Vector3(0, 25, -6 + i * 7), false, 0.0, false)
		var gl := kit.omni(ia, Vector3(-0.05, 1.05, 0.35), Color(0.45, 0.7, 1.0), 0.7, 2.4, false, 0.4)
		monitor_lights.append(gl)
		# beige tower under the desk
		kit.box(ia, Vector3(0.2, 0.42, 0.46), Vector3(-0.45, 0.21, -0.08), Mats.m("plastic_beige"), Vector3.ZERO, false, 0.02)
		kit.box(ia, Vector3(0.14, 0.03, 0.005), Vector3(-0.45, 0.33, 0.152), Mats.m("plastic_black"), Vector3.ZERO, false, 0.0)
		kit.box(ia, Vector3(0.01, 0.01, 0.005), Vector3(-0.4, 0.38, 0.152), Mats.glow(Color(1, 0.6, 0.1), 5.0), Vector3.ZERO, false, 0.0, false)
	else:
		var mon := kit.node(ia, Vector3(-0.05, 0.76, -0.15), 0.0, "Monitor")
		kit.box(mon, Vector3(0.2, 0.02, 0.16), Vector3(0, 0.01, 0), Mats.m("plastic_grey"), Vector3.ZERO, false, 0.008)
		kit.box(mon, Vector3(0.04, 0.3, 0.03), Vector3(0, 0.16, -0.02), Mats.m("plastic_grey"), Vector3.ZERO, false, 0.008)
		kit.box(mon, Vector3(0.62, 0.38, 0.03), Vector3(0, 0.38, 0.0), Mats.m("plastic_black"), Vector3.ZERO, false, 0.01)
		kit.mesh(mon, Meshes.quad(Vector2(0.59, 0.34)), Vector3(0, 0.38, 0.0155), Mats.screen(1, Color(0.4, 0.8, 1.0), 1.5, 2.0), Vector3.ZERO, false)
		monitor_lights.append(kit.omni(ia, Vector3(-0.05, 1.15, 0.35), Color(0.45, 0.7, 1.0), 0.6, 2.2, false, 0.4))
	# mousepad + mouse
	kit.box(ia, Vector3(0.24, 0.004, 0.2), Vector3(0.32, 0.762, 0.18), Mats.m("fabric_blue"), Vector3.ZERO, false, 0.0)
	kit.box(ia, Vector3(0.06, 0.025, 0.1), Vector3(0.32, 0.775, 0.18), Mats.m("plastic_beige" if crt else "plastic_black"), Vector3.ZERO, false, 0.012)
	# paper mess
	for i in 4:
		kit.box(ia, Vector3(0.21, 0.003, 0.297), Vector3(-0.55 + i * 0.05, 0.762 + i * 0.003, 0.15 - i * 0.03), Mats.m("paper"), Vector3(0, -15 + i * 11, 0), false, 0.0, false)
	ia.set_meta("anchor", true)
	kit.ia_shape(ia, Vector3(1.5, 0.76, 0.75), Vector3(0, 0.38, 0))
	kit.ia_shape(ia, Vector3(0.48, 0.42, 0.45), Vector3(-0.05, 0.97, -0.17))
	return ia

## Static office chair. With a kind it is an interactable "seat": the player sits down (camera to the seat).
func office_chair(parent: Node3D, pos: Vector3, rot_y: float, kind: String = "", id: String = "", prompt: String = "") -> Node3D:
	var g: Node3D
	if kind != "":
		g = kit.interactable(parent, kind, id, prompt, pos, rot_y)
		# seat meta in the chair's frame: feet a bit in front of the backrest, looking over the chair's front (+Z)
		g.set_meta("seat", {"pos": Vector3(0, 0, 0.0), "yaw": 180.0, "eye": 1.14, "pitch": -6.0, "pose": "sit"})
	else:
		g = kit.node(parent, pos, rot_y, "Chair")
	var fab := Mats.m("fabric_blue", Color(1.3, 0.75, 0.7))
	kit.box(g, Vector3(0.48, 0.09, 0.46), Vector3(0, 0.47, 0), fab, Vector3.ZERO, false, 0.035)
	kit.box(g, Vector3(0.44, 0.5, 0.08), Vector3(0, 0.78, -0.21), fab, Vector3(-8, 0, 0), false, 0.035)
	kit.cyl(g, 0.025, 0.36, Vector3(0, 0.26, 0), Mats.m("steel_dark"))
	for i in 5:
		var a := TAU * i / 5.0
		kit.box(g, Vector3(0.05, 0.03, 0.28), Vector3(sin(a) * 0.14, 0.06, cos(a) * 0.14), Mats.m("plastic_black"), Vector3(0, rad_to_deg(a), 0), false, 0.01)
		kit.cyl(g, 0.03, 0.03, Vector3(sin(a) * 0.27, 0.03, cos(a) * 0.27), Mats.m("rubber"), Vector3(90, rad_to_deg(a), 0), 8)
	for sx in [-1.0, 1.0]:
		kit.box(g, Vector3(0.05, 0.2, 0.3), Vector3(sx * 0.24, 0.6, 0.0), Mats.m("plastic_black"), Vector3.ZERO, false, 0.015)
	if g is StaticBody3D:
		kit.ia_shape(g, Vector3(0.55, 0.55, 0.5), Vector3(0, 0.28, 0))
		kit.ia_shape(g, Vector3(0.46, 0.5, 0.1), Vector3(0, 0.78, -0.21))
	return g

func desk_lamp(parent: Node3D, pos: Vector3, rot_y: float, color: Color = Color(1.0, 0.72, 0.42)) -> SpotLight3D:
	var g := kit.node(parent, pos, rot_y, "DeskLamp")
	kit.cyl(g, 0.08, 0.025, Vector3(0, 0.012, 0), Mats.m("metal_green"))
	kit.box(g, Vector3(0.025, 0.36, 0.025), Vector3(0, 0.19, -0.04), Mats.m("metal_green"), Vector3(-15, 0, 0), false, 0.006)
	kit.box(g, Vector3(0.025, 0.3, 0.025), Vector3(0, 0.38, 0.06), Mats.m("metal_green"), Vector3(-70, 0, 0), false, 0.006)
	var shade := kit.cyl(g, 0.1, 0.13, Vector3(0, 0.4, 0.2), Mats.m("metal_green"), Vector3(-35, 0, 0), 16)
	shade.mesh = Meshes.cyl(0.1, 0.13, 16, 0.045)
	kit.mesh(g, Meshes.sphere(0.03, 8), Vector3(0, 0.37, 0.22), Mats.glow(color, 8.0), Vector3.ZERO, false)
	var l := kit.spot(g, Vector3(0, 0.36, 0.23), Vector3(0, -0.5, 0.75), color, 6.0, 3.2, 55.0, true, 0.8)
	l.position = Vector3(0, 0.36, 0.23)
	l.look_at(g.to_global(Vector3(0, -0.2, 0.5)), Vector3.UP)
	return l

func whiteboard(parent: Node3D, pos: Vector3, rot_y: float, id: String = "wb_1") -> StaticBody3D:
	var ia := kit.interactable(parent, "whiteboard_research", id, "Research", pos, rot_y)
	var w := 1.7
	var h := 1.05
	var cy := 1.5
	kit.box(ia, Vector3(w, h, 0.025), Vector3(0, cy, 0.012), Mats.m("whiteboard"), Vector3.ZERO, false, 0.004)
	for s in [-1.0, 1.0]:
		kit.box(ia, Vector3(w + 0.04, 0.03, 0.04), Vector3(0, cy + s * (h * 0.5 + 0.01), 0.02), Mats.m("metal"), Vector3.ZERO, false, 0.008)
		kit.box(ia, Vector3(0.03, h + 0.04, 0.04), Vector3(s * (w * 0.5 + 0.01), cy, 0.02), Mats.m("metal"), Vector3.ZERO, false, 0.008)
	# live content: active research with progress bars + sticky notes for finished techs
	var rb := ResearchBoard.new()
	rb.name = "ResearchBoard"
	rb.size = Vector2(w, h)
	rb.position = Vector3(0, cy, 0.0255)
	ia.add_child(rb)
	research_boards.append(rb)
	kit.ia_shape(ia, Vector3(w + 0.06, h * 0.78, 0.12), Vector3(0, cy + h * 0.11, 0.05))
	# marker tray = the brainstorm challenge (stand at the board)
	var ch := kit.interactable(ia, "whiteboard_challenge", id, "Brainstorm at the board (challenge)", Vector3(0, 0, 0), 0.0)
	kit.box(ch, Vector3(w * 0.6, 0.02, 0.07), Vector3(0, cy - h * 0.5 - 0.02, 0.05), Mats.m("metal"), Vector3.ZERO, false, 0.006)
	for i in 3:
		var c: Color = [Color(0.1, 0.2, 0.7), Color(0.75, 0.1, 0.1), Color(0.05, 0.05, 0.05)][i]
		kit.cyl(ch, 0.009, 0.12, Vector3(-0.2 + i * 0.14, cy - h * 0.5 - 0.005, 0.06), Mats.m("plastic_white", c * Color(1.4, 1.4, 1.4)), Vector3(0, 0, 90), 8)
	kit.box(ch, Vector3(0.09, 0.05, 0.03), Vector3(0.32, cy - h * 0.5 - 0.0, 0.06), Mats.m("plastic_white", Color(0.5, 0.5, 0.55)), Vector3(0, 0, 0), false, 0.008)
	var tag := kit.label(ch, "? BRAINSTORM", Vector3(-0.42, cy - h * 0.5 + 0.06, 0.027), 30, Color(0.7, 0.1, 0.08), Vector3.ZERO, 0.0016, true)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	kit.ia_shape(ch, Vector3(w + 0.06, h * 0.22 + 0.1, 0.14), Vector3(0, cy - h * 0.5 + h * 0.11 - 0.05, 0.05))
	ch.set_meta("seat", {"pos": Vector3(0, 0, 0.8), "yaw": 0.0, "eye": 1.58, "pitch": -2.0, "pose": "stand"})
	return ia

## Researcher text on every whiteboard of this level (tests).
func whiteboard_text() -> String:
	var out := []
	for rb in research_boards:
		if is_instance_valid(rb):
			out.append(rb.written_text())
	return "\n".join(out)

func assembly_table(parent: Node3D, pos: Vector3, rot_y: float, id: String = "line_1") -> StaticBody3D:
	var ia := kit.interactable(parent, "workbench_production", id, "Production", pos, rot_y)
	var w := 1.8
	var d := 0.85
	var top := 0.9
	var frame := Mats.m("steel_dark")
	kit.box(ia, Vector3(w, 0.05, d), Vector3(0, top - 0.025, 0), Mats.m("plywood"), Vector3.ZERO, false, 0.01)
	kit.box(ia, Vector3(w - 0.1, 0.006, d - 0.12), Vector3(0, top + 0.003, 0.02), Mats.m("rubber", Color.WHITE, {"albedo": Color(0.08, 0.22, 0.24), "roughness_base": 0.75}), Vector3.ZERO, false, 0.003)
	for x in [-1.0, 1.0]:
		for z in [-1.0, 1.0]:
			kit.box(ia, Vector3(0.05, top - 0.05, 0.05), Vector3(x * (w * 0.5 - 0.05), (top - 0.05) * 0.5, z * (d * 0.5 - 0.05)), frame, Vector3.ZERO, false, 0.008)
	kit.box(ia, Vector3(w - 0.08, 0.025, d - 0.08), Vector3(0, 0.2, 0), Mats.m("plywood", Color(0.8, 0.8, 0.8)), Vector3.ZERO, false, 0.006)
	# uprights + top shelf with parts bins + LED bar
	for x in [-1.0, 1.0]:
		kit.box(ia, Vector3(0.04, 0.75, 0.04), Vector3(x * (w * 0.5 - 0.05), top + 0.375, -d * 0.5 + 0.06), frame, Vector3.ZERO, false, 0.008)
	kit.box(ia, Vector3(w - 0.04, 0.025, 0.28), Vector3(0, top + 0.62, -d * 0.5 + 0.16), frame, Vector3.ZERO, false, 0.006)
	var bin_cols := [Color(0.85, 0.25, 0.15), Color(0.15, 0.4, 0.8), Color(0.95, 0.75, 0.1), Color(0.2, 0.6, 0.3)]
	for i in 10:
		kit.box(ia, Vector3(0.14, 0.09, 0.2), Vector3(-0.75 + i * 0.165, top + 0.68, -d * 0.5 + 0.17), Mats.m("plastic_white", bin_cols[i % 4]), Vector3.ZERO, false, 0.012)
	kit.box(ia, Vector3(w - 0.2, 0.012, 0.03), Vector3(0, top + 0.6, -d * 0.5 + 0.24), Mats.glow(Color(0.85, 0.95, 1.0), 3.0), Vector3.ZERO, false, 0.0, false)
	var led := kit.spot(ia, Vector3(0, top + 0.58, -d * 0.5 + 0.26), Vector3(0, top, 0.15), Color(0.8, 0.9, 1.0), 1.4, 2.0, 70.0, false, 0.3)
	led.position = Vector3(0, top + 0.58, -d * 0.5 + 0.26)
	# magnifier lamp
	var mg := kit.node(ia, Vector3(0.65, top, -0.2), -30.0)
	kit.cyl(mg, 0.06, 0.03, Vector3(0, 0.015, 0), frame)
	kit.box(mg, Vector3(0.02, 0.35, 0.02), Vector3(0, 0.19, 0), frame, Vector3(0, 0, 12), false, 0.005)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.075
	tm.outer_radius = 0.1
	tm.rings = 16
	tm.ring_segments = 8
	ring.mesh = tm
	ring.material_override = Mats.glow(Color(0.9, 0.95, 1.0), 2.5)
	ring.position = Vector3(-0.08, 0.36, 0.12)
	ring.rotation_degrees = Vector3(-30, 0, 0)
	mg.add_child(ring)
	kit.mesh(mg, Meshes.cyl(0.075, 0.006, 16), Vector3(-0.08, 0.36, 0.12), Mats.glass(Color(0.8, 0.9, 1.0, 0.2)), Vector3(-30, 0, 0), false)
	# soldering station
	kit.box(ia, Vector3(0.18, 0.1, 0.16), Vector3(-0.65, top + 0.05, -0.2), Mats.m("metal_blue"), Vector3.ZERO, false, 0.012)
	kit.box(ia, Vector3(0.06, 0.025, 0.004), Vector3(-0.65, top + 0.07, -0.118), Mats.glow(Color(1.0, 0.25, 0.1), 4.0), Vector3.ZERO, false, 0.0, false)
	kit.cyl(ia, 0.012, 0.18, Vector3(-0.48, top + 0.08, -0.22), Mats.m("plastic_black"), Vector3(0, 0, -50), 8)
	kit.cable(ia, Vector3(-0.58, top + 0.05, -0.2), Vector3(-0.42, top + 0.02, -0.2), 0.05, 4, 0.008)
	# phone shells in progress
	for i in 4:
		var x := -0.35 + i * 0.2
		kit.box(ia, Vector3(0.078, 0.01, 0.158), Vector3(x, top + 0.011, 0.15), Mats.m("plastic_grey", Color(1.3, 1.3, 1.4)), Vector3(0, 4 - i * 3, 0), false, 0.006)
		kit.box(ia, Vector3(0.066, 0.004, 0.14), Vector3(x, top + 0.018, 0.15), Mats.m("metal_green", Color(0.6, 1.5, 0.7)), Vector3(0, 4 - i * 3, 0), false, 0.002)
	# small parts tray
	kit.box(ia, Vector3(0.25, 0.03, 0.15), Vector3(0.25, top + 0.015, -0.2), Mats.m("plastic_black"), Vector3.ZERO, false, 0.008)
	kit.ia_shape(ia, Vector3(w, top, d), Vector3(0, top * 0.5, 0))
	kit.ia_shape(ia, Vector3(w, 0.15, 0.3), Vector3(0, top + 0.68, -d * 0.5 + 0.16))
	return ia

func phone_shelf(parent: Node3D, pos: Vector3, rot_y: float, id: String = "shelf_1") -> StaticBody3D:
	var ia := kit.interactable(parent, "phone_shelf", id, "Prototypes", pos, rot_y)
	var w := 1.4
	var d := 0.45
	var post := Mats.m("metal_blue", Color(0.6, 0.6, 0.6))
	for x in [-1.0, 1.0]:
		for z in [-1.0, 1.0]:
			kit.box(ia, Vector3(0.035, 2.0, 0.035), Vector3(x * (w * 0.5 - 0.02), 1.0, z * (d * 0.5 - 0.02)), post, Vector3.ZERO, false, 0.006)
	var ys := [0.12, 0.6, 1.08, 1.56, 1.96]
	for y in ys:
		kit.box(ia, Vector3(w, 0.025, d), Vector3(0, y, 0), Mats.m("plywood"), Vector3.ZERO, false, 0.006)
		kit.box(ia, Vector3(w, 0.04, 0.02), Vector3(0, y - 0.02, d * 0.5 - 0.01), post, Vector3.ZERO, false, 0.004)
		kit.ia_shape(ia, Vector3(w, 0.025, d), Vector3(0, y, 0))
		if y > 0.2 and y < 1.9:
			kit.box(ia, Vector3(w - 0.1, 0.008, 0.015), Vector3(0, y + 0.43, 0.1), Mats.glow(Color(0.55, 0.8, 1.0), 2.2), Vector3.ZERO, false, 0.0, false)
	# displayed prototypes on little stands (static); loose ones are props spawned by the level
	var cols := [Color(0.08, 0.08, 0.09), Color(0.6, 0.6, 0.63), Color(0.55, 0.42, 0.3), Color(0.15, 0.25, 0.45)]
	if proto_shelf == null:
		proto_shelf = ProtoShelf.new()
		proto_shelf.name = "ProtoShelf"
		live_root.add_child(proto_shelf)
	var stands := []
	for si in 3:
		var y: float = ys[si + 1]
		for k in 4:
			if (si + k) % 3 == 2:
				continue
			var x := -0.5 + k * 0.32
			kit.box(ia, Vector3(0.09, 0.015, 0.07), Vector3(x, y + 0.02, 0.05), Mats.m("plastic_black"), Vector3.ZERO, false, 0.005)
			var ph := kit.node(ia, Vector3(x, y + 0.1, 0.04), 0.0)
			ph.rotation_degrees.x = -12
			kit.box(ph, Vector3(0.075 + si * 0.004, 0.15 + si * 0.006, 0.011), Vector3.ZERO, Mats.m("plastic_black", cols[(si + k) % 4] * Color(12, 12, 12)), Vector3.ZERO, false, 0.006)
			kit.mesh(ph, Meshes.quad(Vector2(0.065 + si * 0.004, 0.135 + si * 0.006)), Vector3(0, 0, 0.0062), Mats.screen(3 if k % 2 == 0 else 0, Color(0.4, 0.75, 1.0) if k % 2 == 0 else Color(1.0, 0.6, 0.3), 1.0, si * 4.0 + k), Vector3.ZERO, false)
			var tg := kit.label(ia, "v0.%d" % (si * 4 + k + 1), Vector3(x, y + 0.02, d * 0.5 + 0.002), 28, Color(0.1, 0.1, 0.1), Vector3.ZERO, 0.0012, true)
			# anchor for a real finished prototype (proto_shelf.gd): the model's origin is its centre
			var anchor := kit.node(ia, Vector3(x, y + 0.1, 0.04), 0.0, "Stand")
			anchor.rotation_degrees.x = -12
			stands.append({"anchor": anchor, "placeholder": ph, "tag": tg, "default_tag": tg.text, "order": absi(si - 1) * 10 + (si == 0 as int) * 5 + k})
	# fill eye-level shelves first
	stands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.order < b.order)
	proto_shelf.stands.append_array(stands)
	kit.label(ia, "PROTOTYPES", Vector3(0, 1.94, d * 0.5 + 0.003), 40, Color(0.12, 0.12, 0.14), Vector3.ZERO, 0.0015, true)
	kit.box(ia, Vector3(0.3, 0.035, 0.002), Vector3(0, 1.94, d * 0.5 + 0.001), Mats.m("paper", Color(1, 0.95, 0.75)), Vector3.ZERO, false, 0.0, false)
	kit.omni(ia, Vector3(0, 1.3, 0.45), Color(0.5, 0.75, 1.0), 0.35, 1.8, false, 0.3)
	for x in [-1.0, 1.0]:
		kit.ia_shape(ia, Vector3(0.04, 2.0, d), Vector3(x * (w * 0.5 - 0.02), 1.0, 0))
	kit.ia_shape(ia, Vector3(w, 2.0, 0.02), Vector3(0, 1.0, -d * 0.5 + 0.01))
	return ia

## Cork job board with pinned CVs (employees.candidates) -> UI Employees screen.
func job_board(parent: Node3D, pos: Vector3, rot_y: float, id: String = "jobs_1") -> StaticBody3D:
	var ia := kit.interactable(parent, "job_board", id, "Job board: hire staff", pos, rot_y)
	var sz := Vector2(0.95, 0.68)
	kit.box(ia, Vector3(sz.x + 0.06, sz.y + 0.06, 0.03), Vector3(0, 0, 0.015), Mats.m("wood", Color(1.2, 1.1, 1.0)), Vector3.ZERO, false, 0.008)
	kit.box(ia, Vector3(sz.x, sz.y, 0.02), Vector3(0, 0, 0.022), Mats.m("cork"), Vector3.ZERO, false, 0.0)
	var jb := JobBoard.new()
	jb.name = "JobBoard"
	jb.size = sz
	jb.position = Vector3(0, 0, 0.033)
	ia.add_child(jb)
	kit.ia_shape(ia, Vector3(sz.x + 0.06, sz.y + 0.06, 0.1), Vector3(0, 0, 0.04))
	return ia

func company_board(parent: Node3D, pos: Vector3, rot_y: float, id: String = "board_1", size: Vector2 = Vector2(1.25, 0.72)) -> StaticBody3D:
	var ia := kit.interactable(parent, "board_company", id, "Company", pos, rot_y)
	kit.box(ia, Vector3(size.x + 0.06, size.y + 0.06, 0.07), Vector3(0, 0, 0.035), Mats.m("tv_black"), Vector3.ZERO, false, 0.015)
	kit.box(ia, Vector3(0.3, 0.2, 0.05), Vector3(0, 0, -0.01), Mats.m("steel_dark"), Vector3.ZERO, false, 0.005)
	kit.mesh(ia, Meshes.quad(size), Vector3(0, 0, 0.0705), Mats.screen(2, Color(0.35, 0.95, 0.6), 0.55, 3.0), Vector3.ZERO, false)
	kit.box(ia, Vector3(0.012, 0.012, 0.004), Vector3(size.x * 0.5 - 0.02, -size.y * 0.5 - 0.018, 0.07), Mats.glow(Color(1, 0.15, 0.1), 5.0), Vector3.ZERO, false, 0.0, false)
	var l := kit.label(ia, "", Vector3(-size.x * 0.5 + 0.05, size.y * 0.5 - 0.11, 0.073), 44, Color(0.75, 1.0, 0.8), Vector3.ZERO, 0.0019)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	l.line_spacing = 4.0
	l.width = size.x / 0.0019
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["DejaVu Sans Mono", "Liberation Mono", "Courier New", "monospace"])
	l.font = mono
	l.modulate = Color(0.75, 1.0, 0.8) * 2.2
	board_labels.append(l)
	kit.omni(ia, Vector3(0, 0, 0.45), Color(0.4, 0.9, 0.6), 0.45, 2.5, false, 0.4)
	kit.ia_shape(ia, Vector3(size.x + 0.06, size.y + 0.06, 0.12), Vector3(0, 0, 0.05))
	return ia

func wall_calendar(parent: Node3D, pos: Vector3, rot_y: float) -> void:
	var g := kit.node(parent, pos, rot_y, "Calendar")
	var w := 0.36
	kit.box(g, Vector3(w, 0.52, 0.006), Vector3(0, 0, 0.003), Mats.m("paper"), Vector3.ZERO, false, 0.0)
	kit.box(g, Vector3(w - 0.02, 0.2, 0.002), Vector3(0, 0.14, 0.007), Mats.m("paper", Color(0.35, 0.5, 0.75)), Vector3.ZERO, false, 0.0, false)
	kit.box(g, Vector3(w - 0.02, 0.08, 0.002), Vector3(0, 0.08, 0.0075), Mats.m("paper", Color(0.25, 0.35, 0.25)), Vector3.ZERO, false, 0.0, false)
	kit.box(g, Vector3(0.05, 0.05, 0.002), Vector3(0.09, 0.19, 0.0075), Mats.m("paper", Color(1.1, 0.8, 0.4)), Vector3.ZERO, false, 0.0, false)
	kit.cyl(g, 0.006, 0.02, Vector3(0, 0.255, 0.01), Mats.m("metal"), Vector3(90, 0, 0), 6)
	var header := kit.label(g, "MONTH", Vector3(0, 0.015, 0.008), 34, Color(0.6, 0.08, 0.06), Vector3.ZERO, 0.0011, true)
	var big := kit.label(g, "1", Vector3(0.12, 0.13, 0.009), 90, Color(1, 1, 1), Vector3.ZERO, 0.0012, true)
	big.outline_size = 8
	big.outline_modulate = Color(0, 0, 0, 0.5)
	var marks := []
	var cells := []
	for i in 30:
		var cx := -w * 0.5 + 0.035 + (i % 6) * 0.058
		var cy := -0.035 - (i / 6) * 0.043
		kit.box(g, Vector3(0.05, 0.036, 0.001), Vector3(cx, cy, 0.0065), Mats.m("paper", Color(0.93, 0.93, 0.9)), Vector3.ZERO, false, 0.0, false)
		var mk := kit.box(g, Vector3(0.04, 0.005, 0.001), Vector3(cx, cy, 0.0072), Mats.unlit(Color(0.15, 0.15, 0.2)), Vector3(0, 0, 35), false, 0.0, false)
		marks.append(mk)
		cells.append(Vector3(cx, cy, 0.007))
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.022
	tm.outer_radius = 0.027
	tm.rings = 16
	tm.ring_segments = 4
	ring.mesh = tm
	ring.material_override = Mats.unlit(Color(0.8, 0.05, 0.04))
	ring.rotation_degrees.x = 90
	ring.scale = Vector3(1.0, 1.0, 0.75)
	g.add_child(ring)
	calendars.append({"header": header, "big": big, "marks": marks, "cells": cells, "ring": ring})
	set_date(2016, 1)

func door_exit(parent: Node3D, pos: Vector3, rot_y: float, id: String = "door_1", leak: Color = Color(1.0, 0.75, 0.45)) -> StaticBody3D:
	var ia := kit.interactable(parent, "door_exit", id, "Leave", pos, rot_y)
	var w := 0.88
	var h := 2.04
	kit.box(ia, Vector3(w, h, 0.045), Vector3(0, h * 0.5 + 0.012, 0), Mats.m("plaster", Color(0.95, 0.95, 1.0), {"edge_wear": 0.3, "edge_color": Color(0.5, 0.45, 0.4)}), Vector3.ZERO, false, 0.008)
	for r in 2:
		for c in 2:
			kit.box(ia, Vector3(0.3, 0.75 if r == 0 else 0.5, 0.02), Vector3(-0.19 + c * 0.38, 0.55 + r * 0.95, 0.025), Mats.m("plaster", Color(0.95, 0.95, 1.0)), Vector3.ZERO, false, 0.012)
	kit.mesh(ia, Meshes.sphere(0.03, 10), Vector3(0.36, 1.0, 0.06), Mats.m("metal", Color(1.2, 1.0, 0.6)))
	kit.box(ia, Vector3(0.04, 0.12, 0.01), Vector3(0.36, 1.0, 0.03), Mats.m("metal", Color(1.2, 1.0, 0.6)), Vector3.ZERO, false, 0.004)
	# frame
	for s in [-1.0, 1.0]:
		kit.box(ia, Vector3(0.07, h + 0.07, 0.03), Vector3(s * (w * 0.5 + 0.035), (h + 0.07) * 0.5, 0.05), Mats.m("wood", Color(1.4, 1.4, 1.4)), Vector3.ZERO, false, 0.008)
	kit.box(ia, Vector3(w + 0.14, 0.07, 0.03), Vector3(0, h + 0.05, 0.05), Mats.m("wood", Color(1.4, 1.4, 1.4)), Vector3.ZERO, false, 0.008)
	# warm light leaking under the door
	kit.box(ia, Vector3(w - 0.04, 0.012, 0.02), Vector3(0, 0.006, -0.01), Mats.glow(leak, 6.0), Vector3.ZERO, false, 0.0, false)
	kit.omni(ia, Vector3(0, 0.08, 0.2), leak, 0.35, 1.2, false, 1.5)
	kit.ia_shape(ia, Vector3(w, h, 0.08), Vector3(0, h * 0.5, 0))
	return ia

func sofa(parent: Node3D, pos: Vector3, rot_y: float, mat: Material = null) -> Node3D:
	if mat == null:
		mat = Mats.m("fabric")
	var g := kit.node(parent, pos, rot_y, "Sofa")
	var w := 2.0
	kit.box(g, Vector3(w, 0.3, 0.85), Vector3(0, 0.22, 0), mat, Vector3.ZERO, true, 0.06)
	kit.box(g, Vector3(w, 0.55, 0.22), Vector3(0, 0.62, -0.33), mat, Vector3(-8, 0, 0), true, 0.08)
	for s in [-1.0, 1.0]:
		kit.box(g, Vector3(0.2, 0.55, 0.85), Vector3(s * (w * 0.5 - 0.1), 0.38, 0), mat, Vector3.ZERO, true, 0.08)
		for z in [-1.0, 1.0]:
			kit.box(g, Vector3(0.05, 0.07, 0.05), Vector3(s * (w * 0.5 - 0.08), 0.035, z * 0.36), Mats.m("wood_dark"), Vector3.ZERO, false, 0.01)
	for i in 2:
		kit.box(g, Vector3(0.79, 0.14, 0.62), Vector3(-0.4 + i * 0.8, 0.43, 0.08), mat, Vector3(-3 + i * 4, i * 2, 1 - i * 2), false, 0.06)
	# throw blanket
	kit.box(g, Vector3(0.5, 0.02, 0.95), Vector3(0.62, 0.52, 0.0), Mats.m("fabric_blue", Color(1.6, 0.8, 0.6)), Vector3(-10, 0, 5), false, 0.01)
	kit.box(g, Vector3(0.5, 0.4, 0.02), Vector3(0.62, 0.32, 0.45), Mats.m("fabric_blue", Color(1.6, 0.8, 0.6)), Vector3(0, 0, 0), false, 0.01)
	# pillow
	kit.box(g, Vector3(0.4, 0.38, 0.14), Vector3(-0.68, 0.62, -0.12), Mats.m("fabric", Color(0.6, 0.9, 1.3)), Vector3(-20, 15, 8), false, 0.06)
	return g

func fridge(parent: Node3D, pos: Vector3, rot_y: float) -> Node3D:
	var g := kit.node(parent, pos, rot_y, "Fridge")
	if Sfx.has_method("loop"):
		Sfx.loop("fridge", g, -16.0)
	var m := Mats.m("plastic_white", Color(0.95, 0.93, 0.85), {"grime": 0.5, "edge_wear": 0.2, "edge_color": Color(0.5, 0.45, 0.35)})
	kit.box(g, Vector3(0.7, 1.72, 0.66), Vector3(0, 0.88, 0), m, Vector3.ZERO, true, 0.05)
	kit.box(g, Vector3(0.68, 0.012, 0.01), Vector3(0, 1.28, 0.33), Mats.m("plastic_grey"), Vector3.ZERO, false, 0.0)
	kit.box(g, Vector3(0.03, 0.3, 0.04), Vector3(-0.28, 1.0, 0.35), Mats.m("metal"), Vector3.ZERO, false, 0.01)
	kit.box(g, Vector3(0.03, 0.2, 0.04), Vector3(-0.28, 1.45, 0.35), Mats.m("metal"), Vector3.ZERO, false, 0.01)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in 7:
		var c := Color.from_hsv(rng.randf(), 0.7, 0.85)
		kit.box(g, Vector3(0.04, 0.04, 0.012), Vector3(rng.randf_range(-0.2, 0.25), rng.randf_range(0.6, 1.6), 0.336), Mats.m("plastic_white", c), Vector3(0, 0, rng.randf_range(-20, 20)), false, 0.008)
	kit.box(g, Vector3(0.12, 0.16, 0.002), Vector3(0.12, 1.45, 0.334), Mats.m("paper", Color(0.6, 0.75, 0.9)), Vector3(0, 0, 4), false, 0.0, false)
	kit.box(g, Vector3(0.15, 0.2, 0.002), Vector3(0.05, 0.9, 0.334), Mats.m("paper"), Vector3(0, 0, -3), false, 0.0, false)
	return g

func ceiling_bulb(parent: Node3D, pos: Vector3, drop: float, color: Color = Color(1.0, 0.68, 0.38), energy: float = 2.2, rng: float = 8.0, shadow: bool = true) -> OmniLight3D:
	kit.cable(parent, pos, pos - Vector3(0, drop, 0), 0.0, 1, 0.01)
	kit.cyl(parent, 0.025, 0.06, pos - Vector3(0, drop + 0.02, 0), Mats.m("plastic_black"), Vector3.ZERO, 10).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	kit.mesh(parent, Meshes.sphere(0.05, 12), pos - Vector3(0, drop + 0.09, 0), Mats.glow(color, 12.0), Vector3.ZERO, false)
	return kit.omni(parent, pos - Vector3(0, drop + 0.16, 0), color, energy, rng, shadow, 1.0)

func fluorescent(parent: Node3D, pos: Vector3, rot_y: float, flicker: float = 0.0, color: Color = Color(0.82, 0.95, 1.0)) -> Node3D:
	var g := kit.node(parent, pos, rot_y, "Tube")
	kit.box(g, Vector3(1.3, 0.05, 0.14), Vector3(0, 0.0, 0), Mats.m("metal", Color(1.1, 1.1, 1.1), {"metallic_base": 0.3}), Vector3.ZERO, false, 0.01)
	var tube_mat := StandardMaterial3D.new()
	tube_mat.albedo_color = color
	tube_mat.emission_enabled = true
	tube_mat.emission = color
	tube_mat.emission_energy_multiplier = 5.0
	var t := kit.cyl(g, 0.016, 1.2, Vector3(0, -0.04, 0), tube_mat, Vector3(0, 0, 90), 8)
	t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var l := kit.spot(g, Vector3(0, -0.08, 0), Vector3(0, -2, 0.001), color, 2.6, 4.5, 75.0, true, 1.0)
	l.position = Vector3(0, -0.08, 0)
	l.rotation_degrees = Vector3(-90, 0, 0)
	if flicker > 0.0:
		if Sfx.has_method("loop"):
			Sfx.loop("fluorescent", g, -14.0)
		var f := Flicker.new()
		f.light = l
		f.material = tube_mat
		f.base_emission = 5.0
		f.instability = flicker
		g.add_child(f)
	return g

func outlet(parent: Node3D, pos: Vector3, rot_y: float) -> void:
	var g := kit.node(parent, pos, rot_y)
	kit.box(g, Vector3(0.08, 0.12, 0.012), Vector3(0, 0, 0.006), Mats.m("plastic_white"), Vector3.ZERO, false, 0.004)
	for y in [-0.025, 0.025]:
		kit.box(g, Vector3(0.03, 0.03, 0.004), Vector3(0, y, 0.013), Mats.m("plastic_beige", Color(0.8, 0.8, 0.8)), Vector3.ZERO, false, 0.003)

func poster(parent: Node3D, pos: Vector3, rot_y: float, text: String, bg: Color, fg: Color, size: Vector2 = Vector2(0.5, 0.7)) -> void:
	var g := kit.node(parent, pos, rot_y)
	kit.box(g, Vector3(size.x, size.y, 0.003), Vector3(0, 0, 0.002), Mats.m("paper", bg), Vector3.ZERO, false, 0.0, false)
	kit.label(g, text, Vector3(0, 0, 0.005), 128, fg, Vector3.ZERO, size.x / 420.0, true)
	for s in [Vector2(-1, 1), Vector2(1, 1), Vector2(-1, -1), Vector2(1, -1)]:
		kit.box(g, Vector3(0.05, 0.015, 0.001), Vector3(s.x * (size.x * 0.5 - 0.01), s.y * (size.y * 0.5 - 0.01), 0.005), Mats.m("paper", Color(1.1, 1.05, 0.8), {"roughness_base": 0.3}), Vector3(0, 0, s.x * s.y * 45), false, 0.0, false)
