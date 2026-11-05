extends Node3D
## Cork job board content (WORLD agent): pinned CVs of `employees.candidates` (name, role, skill dots, salary)
## and a "TEAM n" card for the hired staff. Origin = centre of the cork surface (local XY, +Z = room).

const Mats := preload("res://world/lib/mats.gd")
const Meshes := preload("res://world/lib/meshes.gd")
const HQ := preload("res://world/live/hq_state.gd")

var size := Vector2(0.95, 0.68)
var cvs_root: Node3D
var team_label: Label3D
var _key := ""
const PINS := [Color(0.9, 0.15, 0.1), Color(0.15, 0.45, 0.9), Color(0.95, 0.8, 0.1), Color(0.2, 0.7, 0.3)]

func _ready() -> void:
	var hdr := Node3D.new()
	hdr.position = Vector3(-size.x * 0.5 + 0.17, size.y * 0.5 - 0.07, 0.002)
	hdr.rotation_degrees.z = 3
	add_child(hdr)
	_paper(hdr, Vector2(0.28, 0.09), Color(0.15, 0.15, 0.18))
	_text(hdr, "WE'RE HIRING", Vector3(0, 0, 0.0016), 34, Color(1.0, 0.85, 0.3))
	_pin(hdr, Vector3(0, 0.035, 0.004), PINS[0])
	var team := Node3D.new()
	team.position = Vector3(size.x * 0.5 - 0.13, size.y * 0.5 - 0.08, 0.002)
	team.rotation_degrees.z = -4
	add_child(team)
	_paper(team, Vector2(0.18, 0.11), Color(1.0, 0.9, 0.35))
	team_label = _text(team, "TEAM 0", Vector3(0, 0, 0.0016), 30, Color(0.15, 0.12, 0.1))
	_pin(team, Vector3(0, 0.045, 0.004), PINS[2])
	cvs_root = Node3D.new()
	add_child(cvs_root)
	Bus.state_changed.connect(func(keys: Array) -> void:
		if keys.has("employees"):
			refresh(Game.state))
	refresh(Game.state)

func refresh(s: Dictionary) -> void:
	var cands := HQ.candidates(s)
	var staff := HQ.employees(s)
	var key := str(staff.size()) + "|" + ",".join(cands.map(func(c: Dictionary) -> String: return str(c.get("id", ""))))
	if key == _key:
		return
	_key = key
	team_label.text = "TEAM %d" % staff.size()
	for c in cvs_root.get_children():
		c.queue_free()
	var n := mini(cands.size(), 6)
	for i in n:
		var c: Dictionary = cands[i]
		var cv := Node3D.new()
		cv.position = Vector3(-size.x * 0.5 + 0.13 + (i % 4) * 0.23, size.y * 0.5 - 0.27 - (i / 4) * 0.27, 0.003 + i * 0.0004)
		cv.rotation_degrees.z = [-4.0, 3.0, -2.0, 5.0, 2.0, -3.0][i]
		cvs_root.add_child(cv)
		_paper(cv, Vector2(0.17, 0.22), Color(0.95, 0.94, 0.9))
		# photo square + lines
		_rect(cv, Vector2(0.045, 0.05), Vector3(-0.05, 0.065, 0.0014), Color.from_hsv(float(hash(str(c.get("id", ""))) % 100) / 100.0, 0.35, 0.75))
		var nm := str(c.get("name", "?"))
		_text(cv, nm.split(" ")[0] + "\n" + (nm.split(" ")[1] if nm.split(" ").size() > 1 else ""), Vector3(0.028, 0.068, 0.0016), 18, Color(0.1, 0.1, 0.12))
		_text(cv, HQ.role_label(str(c.get("role", ""))), Vector3(0, 0.012, 0.0016), 15, Color(0.25, 0.25, 0.4))
		var sk := clampi(int(round(float(c.get("skill", 0.2)) * 5.0)), 1, 5)
		_text(cv, "★".repeat(sk) + "☆".repeat(5 - sk), Vector3(0, -0.025, 0.0016), 18, Color(0.85, 0.55, 0.05))
		_text(cv, "%s/mo" % HQ.money(float(c.get("salaryMonthly", 0))), Vector3(0, -0.06, 0.0016), 16, Color(0.1, 0.35, 0.15))
		for k in 2:
			_rect(cv, Vector2(0.12, 0.003), Vector3(0, -0.085 - k * 0.012, 0.0014), Color(0.6, 0.6, 0.62))
		_pin(cv, Vector3(0, 0.095, 0.004), PINS[i % PINS.size()])
	if n == 0:
		var e := Node3D.new()
		e.position = Vector3(-0.1, -0.08, 0.003)
		cvs_root.add_child(e)
		_text(e, "no applicants\ncheck back later", Vector3.ZERO, 26, Color(0.25, 0.2, 0.15))

func _paper(parent: Node3D, sz: Vector2, col: Color) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = Meshes.cbox(Vector3(sz.x, sz.y, 0.002), 0.0)
	mi.material_override = Mats.m("paper", Color.WHITE, {"albedo": col})
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)

func _rect(parent: Node3D, sz: Vector2, pos: Vector3, col: Color) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = Meshes.quad(sz)
	mi.material_override = Mats.unlit(col)
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)

func _pin(parent: Node3D, pos: Vector3, col: Color) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = Meshes.sphere(0.011, 8)
	mi.material_override = Mats.m("plastic_white", Color.WHITE, {"albedo": col, "roughness_base": 0.25})
	mi.position = pos
	parent.add_child(mi)

func _text(parent: Node3D, t: String, pos: Vector3, px: int, col: Color) -> Label3D:
	var l := Label3D.new()
	l.text = t
	l.position = pos
	l.font_size = px
	l.pixel_size = 0.0011 if px >= 26 else 0.0009
	l.modulate = col
	l.shaded = true
	l.outline_size = 0
	l.line_spacing = -3.0
	if ResourceLoader.exists("res://ui/fonts/Inter-Bold.ttf"):
		l.font = load("res://ui/fonts/Inter-Bold.ttf")
	parent.add_child(l)
	return l
