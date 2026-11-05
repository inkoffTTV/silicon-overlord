extends Node3D
## Second floor of the garage (WORLD agent) = room `AssemblyLine` (hq.rooms.AssemblyLine).
## The attic shell (floor, knee walls, roof, gable window) is static level geometry; this node owns what changes:
##  locked   — hatch in the garage ceiling boarded up, caution tape, cardboard "2ND FLOOR — FOR SALE" sign;
##             interactable `stairs_locked` ("Buy the second floor").
##  unlocked — hatch open, wooden ladder (group "ladder": the player climbs it with W/S), railing, loft lights,
##             one LineView per upstairs production line (max 3), or a taped "build a line here" spot
##             (interactable production_line with id "").
## All coordinates are in the level's local space (garage). FLOOR_Y = loft floor top.

const Mats := preload("res://world/lib/mats.gd")
const Meshes := preload("res://world/lib/meshes.gd")
const HQ := preload("res://world/live/hq_state.gd")
const LineView := preload("res://world/live/line_view.gd")

const FLOOR_Y := 3.16
const CEIL_Y := 3.0
const HOLE := Rect2(3.0, -2.0, 1.0, 1.7)        # x, z, size x, size z
const LADDER_B := Vector3(3.5, 0.0, -0.35)
const LADDER_T := Vector3(3.5, 3.2, -1.25)
const LINE_X := [-0.55, -2.55, 1.35]
const LINE_Z0 := -2.7
const LINE_LEN := 4.2

var level: Node3D
var unlocked := false
var _built_state := -1
var _lines_key := "?"
var dyn: Node3D          # rebuilt on lock/unlock
var lines_root: Node3D
var line_views: Array = []

func _ready() -> void:
	lines_root = Node3D.new()
	lines_root.name = "Lines"
	add_child(lines_root)
	Bus.state_changed.connect(func(keys: Array) -> void:
		if keys.has("hq") or keys.has("production"):
			refresh(Game.state))
	refresh(Game.state)

func refresh(s: Dictionary) -> void:
	unlocked = HQ.has_second_floor(s)
	if int(unlocked) != _built_state:
		_built_state = int(unlocked)
		if dyn:
			dyn.queue_free()
		dyn = Node3D.new()
		dyn.name = "Unlocked" if unlocked else "Locked"
		add_child(dyn)
		if unlocked:
			_build_unlocked()
		else:
			_build_locked()
		_lines_key = "?"
	var ups := HQ.upstairs_lines(s) if unlocked else []
	var key := ",".join(ups.map(func(l: Dictionary) -> String: return "%s:%s:%s" % [l.get("id", ""), l.get("kind", ""), l.get("level", 1)]))
	if key != _lines_key:
		_lines_key = key
		for c in lines_root.get_children():
			c.queue_free()
		line_views.clear()
		if unlocked:
			_build_lines(ups)

# ------------------------------------------------------------------ helpers
func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, bevel: float = 0.01, rot: Vector3 = Vector3.ZERO, shadow: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = Meshes.cbox(size, bevel)
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

func _shape(body: CollisionObject3D, size: Vector3, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = pos
	cs.rotation_degrees = rot
	body.add_child(cs)

func _label(parent: Node3D, text: String, pos: Vector3, px: int, col: Color, rot: Vector3 = Vector3.ZERO, ps: float = 0.0016) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.rotation_degrees = rot
	l.font_size = px
	l.pixel_size = ps
	l.modulate = col
	l.shaded = true
	l.outline_size = 0
	if ResourceLoader.exists("res://ui/fonts/Inter-Bold.ttf"):
		l.font = load("res://ui/fonts/Inter-Bold.ttf")
	parent.add_child(l)
	return l

func hole_center() -> Vector3:
	return Vector3(HOLE.position.x + HOLE.size.x * 0.5, CEIL_Y, HOLE.position.y + HOLE.size.y * 0.5)

# ------------------------------------------------------------------ locked
func _build_locked() -> void:
	var c := hole_center()
	var ia := StaticBody3D.new()
	ia.name = "IA_stairs_locked"
	ia.add_to_group("interactable")
	ia.set_meta("kind", "stairs_locked")
	ia.set_meta("id", "AssemblyLine")
	ia.set_meta("prompt", "Buy the second floor")
	ia.position = Vector3(c.x, 0, c.z)
	dyn.add_child(ia)
	var plank := Mats.m("wood_planks", Color(0.95, 0.9, 0.85), {"cell": Vector2(1.3, 0.16)})
	# boards nailed across the hatch (seen from below)
	for i in 5:
		var z := -HOLE.size.y * 0.5 + 0.17 + i * 0.34
		_box(ia, Vector3(HOLE.size.x + 0.25, 0.025, 0.15), Vector3(0, CEIL_Y - 0.03 - (i % 2) * 0.012, z), plank, 0.004, Vector3(0, (i % 3 - 1) * 4.0, 0))
	for sx in [-1.0, 1.0]:
		_box(ia, Vector3(0.12, 0.03, HOLE.size.y + 0.25), Vector3(sx * 0.3, CEIL_Y - 0.075, 0), plank, 0.004, Vector3(0, sx * 6.0, 0))
	# caution tape X
	var tape := Mats.m("metal_yellow", Color.WHITE, {"metallic_base": 0.0, "roughness_base": 0.4, "pattern": 1, "cell": Vector2(0.12, 0.05), "albedo2": Color(0.05, 0.05, 0.05), "gap": 0.0})
	for sgn in [-1.0, 1.0]:
		_box(ia, Vector3(0.06, 0.004, 2.0), Vector3(0, CEIL_Y - 0.1, 0), tape, 0.0, Vector3(0, sgn * 30.0, 0), false)
	# hanging cardboard sign
	var sign := Node3D.new()
	sign.position = Vector3(-0.05, CEIL_Y - 0.62, HOLE.size.y * 0.5 - 0.1)
	ia.add_child(sign)
	for sx in [-1.0, 1.0]:
		_box(sign, Vector3(0.006, 0.5, 0.006), Vector3(sx * 0.2, 0.35, 0), Mats.m("plastic_white"), 0.0, Vector3(0, 0, -sx * 8.0), false)
	_box(sign, Vector3(0.62, 0.38, 0.012), Vector3(0, 0, 0), Mats.m("cardboard", Color(1.05, 1.0, 0.95)), 0.004)
	for side in [1.0, -1.0]:
		var rot := Vector3(0, 0 if side > 0 else 180, 0)
		_label(sign, "2ND FLOOR", Vector3(0, 0.09, side * 0.008), 64, Color(0.12, 0.1, 0.1), rot)
		_label(sign, "FOR SALE", Vector3(0, -0.01, side * 0.008), 64, Color(0.75, 0.1, 0.06), rot)
		_label(sign, "room for production lines", Vector3(0, -0.11, side * 0.008), 30, Color(0.2, 0.18, 0.15), rot)
	# blocks the hole + the hit volume under it for the prompt
	_shape(ia, Vector3(HOLE.size.x + 0.1, 0.2, HOLE.size.y + 0.1), Vector3(0, CEIL_Y + 0.05, 0))
	_shape(ia, Vector3(HOLE.size.x, 0.55, HOLE.size.y), Vector3(0, CEIL_Y - 0.33, 0))
	_shape(ia, Vector3(0.64, 0.4, 0.06), sign.position)
	# a dusty light leak through the boards
	var l := OmniLight3D.new()
	l.position = Vector3(c.x, CEIL_Y + 0.4, c.z)
	l.light_color = Color(1.0, 0.75, 0.45)
	l.light_energy = 0.0
	dyn.add_child(l)

# ------------------------------------------------------------------ unlocked
func _build_unlocked() -> void:
	var c := hole_center()
	var wood := Mats.m("wood", Color(1.15, 1.1, 1.0))
	# ladder: two rails from the floor through the hatch + handrails above the loft floor
	var lad := Node3D.new()
	lad.name = "Ladder"
	lad.add_to_group("ladder")
	dyn.add_child(lad)
	var d := LADDER_T - LADDER_B
	var top_ext := LADDER_T + d.normalized() * 1.0
	for sx in [-0.24, 0.24]:
		var a := LADDER_B + Vector3(sx, 0, 0)
		var b := top_ext + Vector3(sx, 0, 0)
		var rail := _box(lad, Vector3(0.06, 0.09, (b - a).length()), (a + b) * 0.5, wood, 0.01)
		rail.transform = Transform3D(Basis.looking_at(b - a, Vector3.UP), (a + b) * 0.5)
	var nr := int(d.length() / 0.3)
	for i in range(1, nr + 1):
		var p := LADDER_B.lerp(LADDER_T, float(i) / (nr + 0.4))
		_box(lad, Vector3(0.5, 0.04, 0.07), p, wood, 0.01)
	lad.set_meta("bottom_local", LADDER_B)
	lad.set_meta("top_local", LADDER_T)
	# hatch lid hanging open from the -Z edge + pull cord
	var lid := _box(dyn, Vector3(HOLE.size.x - 0.04, 0.9, 0.04), Vector3(c.x, CEIL_Y - 0.45, HOLE.position.y + 0.02), Mats.m("plywood"), 0.01)
	lid.rotation_degrees.x = 4
	_box(dyn, Vector3(0.006, 0.4, 0.006), Vector3(c.x, CEIL_Y - 1.1, HOLE.position.y + 0.04), Mats.m("plastic_white"), 0.0)
	# railing around the hole upstairs (open on the -Z side = where you step off)
	var rail_body := StaticBody3D.new()
	rail_body.name = "Railing"
	dyn.add_child(rail_body)
	var x0 := HOLE.position.x
	var z1 := HOLE.position.y + HOLE.size.y
	var rm := Mats.m("metal_yellow")
	_box(rail_body, Vector3(0.05, 0.05, HOLE.size.y), Vector3(x0 - 0.03, FLOOR_Y + 1.0, HOLE.position.y + HOLE.size.y * 0.5), rm, 0.01)
	_box(rail_body, Vector3(HOLE.size.x, 0.05, 0.05), Vector3(x0 + HOLE.size.x * 0.5, FLOOR_Y + 1.0, z1 + 0.03), rm, 0.01)
	for p in [Vector3(x0 - 0.03, 0, HOLE.position.y), Vector3(x0 - 0.03, 0, z1 + 0.03), Vector3(4.0, 0, z1 + 0.03)]:
		_box(rail_body, Vector3(0.05, 1.0, 0.05), Vector3(p.x, FLOOR_Y + 0.5, p.z), rm, 0.01)
	_shape(rail_body, Vector3(0.08, 1.1, HOLE.size.y), Vector3(x0 - 0.03, FLOOR_Y + 0.55, HOLE.position.y + HOLE.size.y * 0.5))
	_shape(rail_body, Vector3(HOLE.size.x, 1.1, 0.08), Vector3(x0 + HOLE.size.x * 0.5, FLOOR_Y + 0.55, z1 + 0.03))
	# warm light spilling down through the hatch
	var spill := OmniLight3D.new()
	spill.position = Vector3(c.x, FLOOR_Y + 1.2, c.z)
	spill.light_color = Color(0.85, 0.93, 1.0)
	spill.light_energy = 0.9
	spill.omni_range = 4.5
	spill.light_volumetric_fog_energy = 1.4
	dyn.add_child(spill)
	# loft lights: fluorescent tubes hanging from the ridge, one flickers; a work lamp near the hatch
	if level and level.has_method("fluorescent"):
		level.fluorescent(dyn, Vector3(-1.0, FLOOR_Y + 2.75, -1.2), 0.0, 0.0)
		level.fluorescent(dyn, Vector3(-1.0, FLOOR_Y + 2.75, 1.4), 0.0, 0.55)
		level.fluorescent(dyn, Vector3(1.4, FLOOR_Y + 2.6, 0.2), 90.0, 0.0)
		for z in [-1.2, 1.4]:
			level.kit.cable(dyn, Vector3(-1.0, FLOOR_Y + 3.3, z), Vector3(-1.0, FLOOR_Y + 2.78, z), 0.0, 1, 0.008)
	# a bare warm bulb near the gable window: the attic's warm key against the cold tubes
	if level and level.has_method("ceiling_bulb"):
		level.ceiling_bulb(dyn, Vector3(1.6, FLOOR_Y + 3.0, 2.4), 0.7, Color(1.0, 0.66, 0.36), 1.8, 6.0, false)
	var amb := OmniLight3D.new()
	amb.position = Vector3(0, FLOOR_Y + 1.5, 0)
	amb.light_color = Color(0.75, 0.7, 0.75)
	amb.light_energy = 0.3
	amb.omni_range = 7.0
	amb.light_volumetric_fog_energy = 0.2
	dyn.add_child(amb)

func _build_lines(ups: Array) -> void:
	if ups.is_empty():
		# taped empty bay + sign: the production screen builds lines
		var ia := StaticBody3D.new()
		ia.name = "IA_production_line"
		ia.add_to_group("interactable")
		ia.set_meta("kind", "production_line")
		ia.set_meta("id", "")
		ia.set_meta("prompt", "Production lines")
		ia.position = Vector3(LINE_X[0], FLOOR_Y, LINE_Z0 + LINE_LEN * 0.5)
		lines_root.add_child(ia)
		var tape := Mats.m("metal_yellow", Color.WHITE, {"metallic_base": 0.0, "roughness_base": 0.6})
		for sx in [-1.0, 1.0]:
			_box(ia, Vector3(0.06, 0.004, LINE_LEN), Vector3(sx * 0.55, 0.002, 0), tape, 0.0, Vector3.ZERO, false)
			_box(ia, Vector3(1.16, 0.004, 0.06), Vector3(0, 0.002, sx * LINE_LEN * 0.5), tape, 0.0, Vector3.ZERO, false)
		_label(ia, "LINE 1", Vector3(0, 0.006, 0.6), 160, Color(0.95, 0.8, 0.2), Vector3(-90, 0, 0), 0.003)
		var easel := Node3D.new()
		easel.position = Vector3(0, 0, -LINE_LEN * 0.5 + 0.4)
		easel.rotation_degrees.y = 180
		ia.add_child(easel)
		_box(easel, Vector3(0.7, 0.5, 0.02), Vector3(0, 1.05, 0), Mats.m("cardboard"), 0.005, Vector3(-8, 0, 0))
		for sx in [-1.0, 1.0]:
			_box(easel, Vector3(0.04, 1.1, 0.04), Vector3(sx * 0.3, 0.55, 0.05), Mats.m("wood"), 0.005, Vector3(-8, 0, 0))
		_label(easel, "BUILD A\nPRODUCTION LINE\nHERE", Vector3(0, 1.06, 0.03), 44, Color(0.15, 0.12, 0.1), Vector3(-8, 0, 0))
		_shape(ia, Vector3(1.2, 1.4, LINE_LEN), Vector3(0, 0.7, 0))
		return
	for i in mini(ups.size(), LINE_X.size()):
		var lv: Node3D = LineView.new()
		lv.length = LINE_LEN
		lv.setup(ups[i])
		lv.position = Vector3(LINE_X[i], FLOOR_Y, LINE_Z0)
		lines_root.add_child(lv)
		line_views.append(lv)

## Operator slots for staff.gd (global).
func staff_slots() -> Array:
	var out := []
	for lv in line_views:
		if is_instance_valid(lv) and lv.is_inside_tree():
			out.append(lv.operator_slot())
	return out
