extends Node3D
## Live whiteboard content (WORLD agent). Origin = centre of the board surface, board plane = local XY, +Z = room.
## Left: every tech in `research.active` hand-written with a marker-drawn progress bar and %. Right: sticky notes
## for the most recently finished techs. Empty: "nothing in research — pick a tech!".

const Mats := preload("res://world/lib/mats.gd")
const Meshes := preload("res://world/lib/meshes.gd")
const HQ := preload("res://world/live/hq_state.gd")

var size := Vector2(1.7, 1.05)
var rows_root: Node3D
var notes_root: Node3D
var _key := ""
const BLUE := Color(0.1, 0.18, 0.6)
const RED := Color(0.68, 0.1, 0.08)
const GREEN := Color(0.08, 0.42, 0.16)
const NOTE_COLS := [Color(1.0, 0.9, 0.3), Color(1.0, 0.55, 0.7), Color(0.6, 0.95, 0.6), Color(0.5, 0.8, 1.0), Color(1.0, 0.7, 0.35), Color(0.85, 0.7, 1.0)]

func _ready() -> void:
	var z := 0.0015
	_label(self, "R&D", Vector3(-size.x * 0.5 + 0.08, size.y * 0.5 - 0.09, z), 72, BLUE, HORIZONTAL_ALIGNMENT_LEFT)
	_label(self, "DONE!", Vector3(size.x * 0.5 - 0.34, size.y * 0.5 - 0.09, z), 48, GREEN, HORIZONTAL_ALIGNMENT_LEFT)
	# divider line drawn with the marker
	_line(self, Vector3(size.x * 0.5 - 0.47, -size.y * 0.5 + 0.08, z), Vector3(size.x * 0.5 - 0.47, size.y * 0.5 - 0.06, z), BLUE)
	_line(self, Vector3(-size.x * 0.5 + 0.08, size.y * 0.5 - 0.15, z), Vector3(-size.x * 0.5 + 0.38, size.y * 0.5 - 0.155, z), BLUE)
	rows_root = Node3D.new()
	add_child(rows_root)
	notes_root = Node3D.new()
	add_child(notes_root)
	Bus.state_changed.connect(func(keys: Array) -> void:
		if keys.has("research"):
			refresh(Game.state))
	refresh(Game.state)

func refresh(s: Dictionary) -> void:
	var act := HQ.active_research(s)
	var done := HQ.finished_research(s, 6)
	var key := str(act.map(func(r: Dictionary) -> String: return "%s:%d" % [r.techId, int(r.progress * 100)])) + str(done.map(func(r: Dictionary) -> String: return r.techId))
	if key == _key:
		return
	_key = key
	for c in rows_root.get_children():
		c.queue_free()
	for c in notes_root.get_children():
		c.queue_free()
	var z := 0.0015
	var x0 := -size.x * 0.5 + 0.08
	var bar_w := 0.62
	if act.is_empty():
		_label(rows_root, "nothing in research...\npick a tech!  ->", Vector3(x0, 0.12, z), 44, RED, HORIZONTAL_ALIGNMENT_LEFT)
	for i in mini(act.size(), 4):
		var r: Dictionary = act[i]
		var y := size.y * 0.5 - 0.26 - i * 0.2
		var nm := str(r.name)
		if nm.length() > 26:
			nm = nm.substr(0, 25) + "."
		_label(rows_root, nm, Vector3(x0, y, z), 38, BLUE, HORIZONTAL_ALIGNMENT_LEFT)
		var by := y - 0.075
		# hand-drawn bar outline (slightly wobbly) + hatched fill
		var wob := 0.004 * sin(i * 3.1)
		_line(rows_root, Vector3(x0, by + 0.025, z), Vector3(x0 + bar_w, by + 0.025 + wob, z), BLUE)
		_line(rows_root, Vector3(x0, by - 0.025, z), Vector3(x0 + bar_w, by - 0.025 - wob, z), BLUE)
		_line(rows_root, Vector3(x0, by - 0.027, z), Vector3(x0, by + 0.027, z), BLUE)
		_line(rows_root, Vector3(x0 + bar_w, by - 0.027, z), Vector3(x0 + bar_w, by + 0.027, z), BLUE)
		var fw: float = bar_w * float(r.progress)
		var col := GREEN if float(r.progress) >= 0.66 else (Color(0.75, 0.45, 0.05) if float(r.progress) >= 0.33 else RED)
		if fw > 0.01:
			var fill := _rect(rows_root, Vector2(fw - 0.008, 0.036), Vector3(x0 + fw * 0.5, by, z * 0.8), Color(col.r, col.g, col.b, 0.55))
			fill.name = "Bar_%s" % str(r.techId).validate_node_name()
			var n := int(fw / 0.03)
			for k in n:
				var hx := x0 + 0.012 + k * 0.03
				_line(rows_root, Vector3(hx, by - 0.018, z), Vector3(hx + 0.02, by + 0.018, z), col, 0.0035)
		_label(rows_root, "%d%%" % int(round(float(r.progress) * 100.0)), Vector3(x0 + bar_w + 0.04, by, z), 36, col, HORIZONTAL_ALIGNMENT_LEFT)
	# sticky notes, 2 columns x 3 rows
	for i in done.size():
		var d: Dictionary = done[i]
		var nx := size.x * 0.5 - 0.33 + (i % 2) * 0.17
		var ny := size.y * 0.5 - 0.26 - (i / 2) * 0.24
		var note := Node3D.new()
		note.position = Vector3(nx, ny, 0.002)
		note.rotation_degrees.z = [-6.0, 4.0, -2.0, 7.0, 3.0, -5.0][i % 6]
		notes_root.add_child(note)
		var nc: Color = NOTE_COLS[(hash(str(d.techId)) % NOTE_COLS.size() + NOTE_COLS.size()) % NOTE_COLS.size()]
		var mi := MeshInstance3D.new()
		mi.mesh = Meshes.cbox(Vector3(0.15, 0.15, 0.002), 0.0)
		mi.material_override = Mats.m("paper", nc)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		note.add_child(mi)
		var l := _label(note, _wrap(str(d.name), 13), Vector3(0, 0.0, 0.0016), 22, Color(0.12, 0.12, 0.15), HORIZONTAL_ALIGNMENT_CENTER)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_line(note, Vector3(-0.05, -0.055, 0.0016), Vector3(-0.035, -0.065, 0.0016), GREEN, 0.004)
		_line(note, Vector3(-0.035, -0.065, 0.0016), Vector3(-0.01, -0.04, 0.0016), GREEN, 0.004)

static func _wrap(t: String, n: int) -> String:
	var words := t.split(" ")
	var lines := []
	var cur := ""
	for w in words:
		if cur.length() + w.length() + 1 > n and cur != "":
			lines.append(cur)
			cur = w
		else:
			cur = w if cur == "" else cur + " " + w
	if cur != "":
		lines.append(cur)
	return "\n".join(lines.slice(0, 4))

func _label(parent: Node3D, text: String, pos: Vector3, px: int, col: Color, align: HorizontalAlignment) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.font_size = px
	l.pixel_size = 0.0016 if px > 30 else 0.0011
	l.modulate = col
	l.outline_size = 0
	l.shaded = true
	l.double_sided = false
	l.horizontal_alignment = align
	l.line_spacing = -2.0
	if ResourceLoader.exists("res://ui/fonts/Inter-SemiBold.ttf"):
		l.font = load("res://ui/fonts/Inter-SemiBold.ttf")
	parent.add_child(l)
	return l

func _line(parent: Node3D, a: Vector3, b: Vector3, col: Color, w: float = 0.005) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var d := b - a
	mi.mesh = Meshes.cbox(Vector3(d.length() + w, w, 0.0008), 0.0)
	mi.material_override = Mats.unlit(col)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = (a + b) * 0.5
	mi.rotation.z = atan2(d.y, d.x)
	parent.add_child(mi)
	return mi

func _rect(parent: Node3D, sz: Vector2, pos: Vector3, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = Meshes.quad(sz)
	mi.material_override = Mats.unlit(col)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	parent.add_child(mi)
	return mi

## Text currently written on the board (tests).
func written_text() -> String:
	var out := []
	for l in rows_root.find_children("*", "Label3D", true, false):
		out.append((l as Label3D).text)
	for l in notes_root.find_children("*", "Label3D", true, false):
		out.append((l as Label3D).text.replace("\n", " "))
	return "\n".join(out)
