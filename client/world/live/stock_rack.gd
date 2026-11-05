extends Node3D
## Raw-material rack (WORLD agent): shows `inventory.resources` as physical stock on three shelves —
## glass sheets (1 per 100), copper spools (1 per 50), aluminium bars (1 per 40) — with the amount on the shelf lip.
## Origin on the floor, rack front faces +Z, width along X.

const Mats := preload("res://world/lib/mats.gd")
const Meshes := preload("res://world/lib/meshes.gd")
const HQ := preload("res://world/live/hq_state.gd")

## [resource id, label, per item, max items, shelf y]
const ROWS := [["glass", "GLASS", 100.0, 10, 0.12], ["copper", "COPPER", 50.0, 6, 0.52], ["aluminum", "ALUMINIUM", 40.0, 8, 0.92]]
const W := 0.8
const DEP := 0.4

var items := {}     # resource id -> Node3D (rebuilt)
var labels := {}    # resource id -> Label3D
var _key := ""

func _ready() -> void:
	var post := Mats.m("steel_dark")
	for x in [-1.0, 1.0]:
		for z in [-1.0, 1.0]:
			_box(self, Vector3(0.03, 1.25, 0.03), Vector3(x * (W * 0.5 - 0.015), 0.625, z * (DEP * 0.5 - 0.015)), post, 0.004)
	for r in ROWS:
		var y: float = r[4]
		_box(self, Vector3(W, 0.02, DEP), Vector3(0, y, 0), Mats.m("plywood", Color(0.9, 0.9, 0.9)), 0.004)
		_box(self, Vector3(W, 0.05, 0.015), Vector3(0, y - 0.015, DEP * 0.5), Mats.m("metal_yellow"), 0.003)
		var tag := Label3D.new()
		tag.font_size = 28
		tag.pixel_size = 0.0011
		tag.modulate = Color(0.1, 0.1, 0.1)
		tag.shaded = true
		tag.position = Vector3(0, y - 0.015, DEP * 0.5 + 0.009)
		if ResourceLoader.exists("res://ui/fonts/Inter-Bold.ttf"):
			tag.font = load("res://ui/fonts/Inter-Bold.ttf")
		add_child(tag)
		labels[r[0]] = tag
		var g := Node3D.new()
		g.position = Vector3(0, y + 0.01, 0)
		add_child(g)
		items[r[0]] = g
	_box(self, Vector3(W, 0.02, DEP), Vector3(0, 1.24, 0), Mats.m("plywood", Color(0.9, 0.9, 0.9)), 0.004)
	var sign := Label3D.new()
	sign.text = "MATERIALS"
	sign.font_size = 40
	sign.pixel_size = 0.0015
	sign.modulate = Color(0.95, 0.8, 0.2)
	sign.shaded = true
	sign.position = Vector3(0, 1.31, DEP * 0.5 - 0.02)
	if ResourceLoader.exists("res://ui/fonts/Inter-Bold.ttf"):
		sign.font = load("res://ui/fonts/Inter-Bold.ttf")
	add_child(sign)
	Bus.state_changed.connect(func(keys: Array) -> void:
		if keys.has("inventory"):
			refresh(Game.state))
	refresh(Game.state)

func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, bevel: float = 0.004, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = Meshes.cbox(size, bevel)
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot
	parent.add_child(mi)
	return mi

static func amount(s: Dictionary, id: String) -> float:
	return float(HQ.dict(HQ.section(s, "inventory").get("resources")).get(id, 0))

## items shown for a resource (tests)
func shown(id: String) -> int:
	return (items[id] as Node3D).get_child_count() if items.has(id) else 0

func refresh(s: Dictionary) -> void:
	var key := ""
	for r in ROWS:
		key += "%s=%d;" % [r[0], int(amount(s, r[0]))]
	if key == _key:
		return
	_key = key
	for r in ROWS:
		var id: String = r[0]
		var amt := amount(s, id)
		var n := clampi(int(ceil(amt / float(r[2]))), 0, int(r[3]))
		var g: Node3D = items[id]
		for c in g.get_children():
			g.remove_child(c)
			c.queue_free()
		labels[id].text = "%s  %d" % [r[1], int(amt)]
		for i in n:
			match id:
				"glass":
					# panes leaning in a stack
					var p := _box(g, Vector3(0.34, 0.008, 0.26), Vector3(-0.15, 0.006 + i * 0.011, 0.0), Mats.glass(Color(0.6, 0.8, 0.85, 0.45)), 0.002, Vector3(0, (i % 3 - 1) * 2.0, 0))
					p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					if i == n - 1:
						_box(p, Vector3(0.1, 0.002, 0.06), Vector3(0, 0.006, 0.06), Mats.m("paper"), 0.0)
				"copper":
					var sp := Node3D.new()
					sp.position = Vector3(-0.3 + (i % 3) * 0.2, 0.09 + (i / 3) * 0.0, -0.08 + (i / 3) * 0.17)
					sp.rotation_degrees.z = 90
					g.add_child(sp)
					var coil := MeshInstance3D.new()
					coil.mesh = Meshes.cyl(0.08, 0.1, 14)
					coil.material_override = Mats.m("metal", Color.WHITE, {"albedo": Color(0.85, 0.45, 0.25), "metallic_base": 0.9, "roughness_base": 0.3})
					sp.add_child(coil)
					for sx in [-1.0, 1.0]:
						var fl := MeshInstance3D.new()
						fl.mesh = Meshes.cyl(0.095, 0.01, 14)
						fl.material_override = Mats.m("plywood")
						fl.position = Vector3(0, sx * 0.055, 0)
						sp.add_child(fl)
				"aluminum":
					var layer := i / 4
					var k := i % 4
					_box(g, Vector3(0.7, 0.035, 0.05), Vector3(0, 0.02 + layer * 0.037, -0.11 + k * 0.07 + layer * 0.03), Mats.m("metal", Color(1.15, 1.15, 1.2), {"metallic_base": 0.8, "roughness_base": 0.35}), 0.006)
