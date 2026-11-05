extends Node3D
## Second floor of the garage (WORLD agent) = room `AssemblyLine` (hq.rooms.AssemblyLine).
## The attic shell (floor, knee walls, roof, gable window) is static level geometry; this node owns what changes:
##  locked   — hatch in the garage ceiling boarded up, caution tape, cardboard "2ND FLOOR — FOR SALE" sign;
##             interactable `stairs_locked` ("Buy the second floor").
##  unlocked — hatch open, wooden ladder (group "ladder": the player climbs it with W/S), railing, loft lights,
##             three taped floor bays numbered by UPSTAIRS line (1..3), one LineView per upstairs line, and an easel
##             "Build a production line" on the first free bay (interactable production_line with id "").
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
	Bus.settings_changed.connect(func() -> void:
		# the language may have changed: rebuild the localized "build a line" easel
		_lines_key = "?"
		refresh(Game.state))
	refresh(Game.state)

func refresh(s: Dictionary) -> void:
	unlocked = HQ.has_second_floor(s)
	if int(unlocked) != _built_state:
		if _built_state == 0 and unlocked:
			Sfx.play("door_open", to_global(hole_center()))
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
	var key := ",".join(ups.map(func(l: Dictionary) -> String: return "%s:%s:%s:%s" % [l.get("id", ""), l.get("kind", ""), l.get("level", 1), l.get("process", "")]))
	if key != _lines_key:
		_lines_key = key
		for c in lines_root.get_children():
			lines_root.remove_child(c)   # free the names now: the new bays reuse "Bay1", "IA_production_line", ...
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

## Upstairs bays: always LINE_X.size() taped floor bays numbered 1..3 = the order of the UPSTAIRS lines (the garage
## bench is not one of them, so a fresh loft never says "LINE 1" while line_1 is the workbench downstairs).
## Bays with a line get a LineView (`bay` = its number); the first free bay gets an easel "Build a production line"
## (localized) and an interactable production_line with id "" (opens the production screen).
func _build_lines(ups: Array) -> void:
	var n := mini(ups.size(), LINE_X.size())
	for b in LINE_X.size():
		_bay_marking(b)
	for i in n:
		var lv: Node3D = LineView.new()
		lv.length = LINE_LEN
		lv.bay = i + 1
		lv.setup(ups[i])
		lv.position = Vector3(LINE_X[i], FLOOR_Y, LINE_Z0)
		lines_root.add_child(lv)
		line_views.append(lv)
	if n < LINE_X.size():
		_free_bay(n)

## Taped outline + a big stencilled bay number on the floor in front of the bay (language-neutral).
func _bay_marking(b: int) -> void:
	var m := Node3D.new()
	m.name = "Bay%d" % (b + 1)
	m.position = Vector3(LINE_X[b], FLOOR_Y, LINE_Z0 + LINE_LEN * 0.5 + 0.2)
	lines_root.add_child(m)
	var tape := Mats.m("metal_yellow", Color.WHITE, {"metallic_base": 0.0, "roughness_base": 0.7, "grime": 0.6})
	var bl := LINE_LEN + 0.6
	for sx in [-1.0, 1.0]:
		_box(m, Vector3(0.06, 0.004, bl), Vector3(sx * 0.6, 0.002, 0), tape, 0.0, Vector3.ZERO, false)
		_box(m, Vector3(1.26, 0.004, 0.06), Vector3(0, 0.002, sx * bl * 0.5), tape, 0.0, Vector3.ZERO, false)
	var num := _label(m, str(b + 1), Vector3(0, 0.006, bl * 0.5 - 0.3), 150, Color(0.95, 0.8, 0.2, 0.85), Vector3(-90, 0, 0), 0.0028)
	num.name = "BayNumber"
	m.set_meta("bay", b + 1)

func _free_bay(b: int) -> void:
	var ia := StaticBody3D.new()
	ia.name = "IA_production_line"
	ia.add_to_group("interactable")
	ia.set_meta("kind", "production_line")
	ia.set_meta("id", "")
	ia.set_meta("prompt", "Build a production line")
	ia.set_meta("bay", b + 1)
	ia.position = Vector3(LINE_X[b], FLOOR_Y, LINE_Z0 + LINE_LEN * 0.5)
	lines_root.add_child(ia)
	var easel := Node3D.new()
	easel.name = "Easel"
	easel.position = Vector3(0, 0, LINE_LEN * 0.5 - 0.5)
	ia.add_child(easel)
	_box(easel, Vector3(0.7, 0.5, 0.02), Vector3(0, 1.05, 0), Mats.m("cardboard"), 0.005, Vector3(-8, 0, 0))
	for sx in [-1.0, 1.0]:
		_box(easel, Vector3(0.04, 1.1, 0.04), Vector3(sx * 0.3, 0.55, -0.05), Mats.m("wood"), 0.005, Vector3(-8, 0, 0))
	var txt := _label(easel, hint_text(), Vector3(0, 1.09, 0.016), 54, Color(0.15, 0.12, 0.1), Vector3(-8, 0, 0), 0.00105)
	txt.name = "Hint"
	txt.font = _hint_font()
	txt.autowrap_mode = TextServer.AUTOWRAP_WORD
	txt.width = 620.0     # 0.65 m of the 0.7 m board
	_fit_words(txt)
	var arrow := _label(easel, "↓", Vector3(0, 0.875, 0.04), 56, Color(0.75, 0.1, 0.06), Vector3(-8, 0, 0))
	arrow.font = _hint_font()
	_shape(ia, Vector3(1.2, 1.4, LINE_LEN), Vector3(0, 0.7, 0))

## "BUILD A PRODUCTION LINE" in the current UI language (ui/lib/loc.gd when present).
static func hint_text() -> String:
	var t := "Build a production line"
	if ResourceLoader.exists("res://ui/lib/loc.gd"):
		t = str(load("res://ui/lib/loc.gd").t(t))
	return t.to_upper()

## Shrinks the font until the longest word fits on one line (no "ПРОИЗВОДСТВЕ/ННУЮ" breaks) and the text fits 4 lines.
static func _fit_words(l: Label3D) -> void:
	var words := l.text.split(" ", false)
	while l.font_size > 28:
		var widest := 0.0
		for w in words:
			widest = maxf(widest, l.font.get_string_size(w, HORIZONTAL_ALIGNMENT_LEFT, -1, l.font_size).x)
		var total := l.font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.font_size).x
		if widest <= l.width - 8.0 and total <= l.width * 3.2:
			return
		l.font_size -= 2

static func _hint_font() -> Font:
	if ResourceLoader.exists("res://ui/lib/uit.gd"):
		return load("res://ui/lib/uit.gd").font("bold")   # Inter Bold + CJK fallback
	return load("res://ui/fonts/Inter-Bold.ttf")

## Operator slots for staff.gd (global).
func staff_slots() -> Array:
	var out := []
	for lv in line_views:
		if is_instance_valid(lv) and lv.is_inside_tree():
			out.append(lv.operator_slot())
	return out
