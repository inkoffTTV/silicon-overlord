extends Node3D
## Where crates get shipped (WORLD agent). style "van": an original boxy delivery van backed up to the garage door,
## rear doors open, ramp, cargo light, hazard blinkers; style "chute": a wall DISPATCH hatch with a belt (offices).
## Local frame: the cargo opening is at z=0 facing -Z (toward the room); the van body extends to +Z.
## The whole body is an interactable kind "van" ("Ship all crates" -> UI). A cargo Area3D reports crates:
## signal crate_entered(crate). shipping.gd decides what happens (Net.act shipCrate) and calls absorb/accept/reject.

signal crate_entered(crate: RigidBody3D)

const Mats := preload("res://world/lib/mats.gd")
const Meshes := preload("res://world/lib/meshes.gd")

var style := "van"
var dock_id := "garage_van"
var brand := "SILICON OVERLORD"
var brand_col := Color(0.31, 0.55, 1.0)
var body: StaticBody3D
var cargo: Area3D
var loaded: Array = []          # crates resting inside
var _blink_mats: Array = []
var _flash_mat: StandardMaterial3D
var _flash_light: OmniLight3D
var _flash := 0.0
var _flash_col := Color.GREEN
var _bounce := 0.0
var _shell: Node3D
var _t := 0.0

func _ready() -> void:
	body = StaticBody3D.new()
	body.name = "IA_van"
	body.add_to_group("interactable")
	body.set_meta("kind", "van")
	body.set_meta("id", dock_id)
	body.set_meta("prompt", "Ship all crates")
	add_child(body)
	_shell = Node3D.new()
	_shell.name = "Shell"
	body.add_child(_shell)
	if style == "van":
		_build_van()
	else:
		_build_chute()
	cargo.body_entered.connect(func(b: Node3D) -> void:
		if b is RigidBody3D and b.is_in_group("ship_crate"):
			crate_entered.emit(b))

# ------------------------------------------------------------------ helpers
func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, bevel: float = 0.02, collide: bool = false, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = Meshes.cbox(size, bevel)
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot
	parent.add_child(mi)
	if collide:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		body.add_child(cs)
		cs.global_transform = mi.global_transform
	return mi

func _label(parent: Node3D, text: String, pos: Vector3, px: int, col: Color, rot: Vector3 = Vector3.ZERO, ps: float = 0.003) -> Label3D:
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

func _cargo_area(size: Vector3, pos: Vector3) -> void:
	cargo = Area3D.new()
	cargo.name = "Cargo"
	cargo.monitoring = true
	cargo.monitorable = false
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cargo.add_child(cs)
	cargo.position = pos
	add_child(cargo)

# ------------------------------------------------------------------ van
func _build_van() -> void:
	var paint := Mats.m("plastic_white", Color.WHITE, {"albedo": Color(0.82, 0.8, 0.74), "albedo2": Color(0.6, 0.58, 0.52), "metallic_base": 0.3, "roughness_base": 0.4, "grime": 0.55, "edge_wear": 0.4, "edge_color": Color(0.45, 0.42, 0.38), "floor_dirt": 1.0})
	var stripe := Mats.m("plastic_white", Color.WHITE, {"albedo": brand_col, "albedo2": brand_col.darkened(0.3), "metallic_base": 0.3, "roughness_base": 0.4, "grime": 0.4})
	var dark := Mats.m("steel_dark")
	var rubber := Mats.m("rubber", Color(2, 2, 2))
	var glass := Mats.glass(Color(0.05, 0.07, 0.1, 0.85))
	var w := 2.0
	var L := 3.0
	var y0 := 0.5
	var top := 2.45
	var s := _shell
	# cargo box: floor, walls, roof (open at z=0)
	_box(s, Vector3(w, 0.1, L), Vector3(0, y0 + 0.05, L * 0.5), dark, 0.02, true)
	_box(s, Vector3(w - 0.12, 0.012, L - 0.05), Vector3(0, y0 + 0.106, L * 0.5 + 0.02), Mats.m("wood_planks", Color(1.0, 0.95, 0.9), {"cell": Vector2(0.16, 3.0)}), 0.0)
	for sx in [-1.0, 1.0]:
		_box(s, Vector3(0.06, top - y0, L), Vector3(sx * (w * 0.5 - 0.03), (top + y0) * 0.5, L * 0.5), paint, 0.03, true)
		# colour stripe + brand on the outside
		_box(s, Vector3(0.012, 0.32, L - 0.2), Vector3(sx * (w * 0.5 + 0.002), 1.35, L * 0.5 + 0.05), stripe, 0.0)
		var lb := _label(s, brand + "\nDELIVERY", Vector3(sx * (w * 0.5 + 0.012), 1.85, L * 0.5), 64, Color(0.12, 0.14, 0.2), Vector3(0, sx * 90.0, 0), 0.0045)
		lb.line_spacing = -8.0
		# ribs inside
		for i in 4:
			_box(s, Vector3(0.03, top - y0 - 0.1, 0.05), Vector3(sx * (w * 0.5 - 0.075), (top + y0) * 0.5, 0.4 + i * 0.75), Mats.m("metal"), 0.008)
	_box(s, Vector3(w, 0.08, L + 0.02), Vector3(0, top + 0.04, L * 0.5), paint, 0.04, true)
	_box(s, Vector3(w, top - y0, 0.06), Vector3(0, (top + y0) * 0.5, L), paint, 0.02, true)   # bulkhead
	# rear frame + bumper step
	for sx in [-1.0, 1.0]:
		_box(s, Vector3(0.1, top - y0, 0.08), Vector3(sx * (w * 0.5 - 0.05), (top + y0) * 0.5, 0.0), paint, 0.02, true)
		# tail lights
		var tl := _box(s, Vector3(0.1, 0.32, 0.03), Vector3(sx * (w * 0.5 - 0.05), 1.0, -0.045), Mats.glow(Color(1.0, 0.08, 0.05), 2.2), 0.01)
		var am := StandardMaterial3D.new()
		am.albedo_color = Color(1.0, 0.55, 0.05)
		am.emission_enabled = true
		am.emission = Color(1.0, 0.55, 0.05)
		am.emission_energy_multiplier = 0.0
		var blinker := _box(s, Vector3(0.1, 0.1, 0.03), Vector3(sx * (w * 0.5 - 0.05), 0.78, -0.045), am, 0.01)
		_blink_mats.append(am)
		tl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		blinker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_box(s, Vector3(w, 0.1, 0.08), Vector3(0, top - 0.02, 0.0), paint, 0.02)
	_box(s, Vector3(w + 0.06, 0.12, 0.25), Vector3(0, y0 - 0.02, -0.1), dark, 0.02, true)
	_box(s, Vector3(0.9, 0.03, 0.18), Vector3(0, y0 + 0.05, -0.12), Mats.m("metal", Color(1.1, 1.1, 1.1)), 0.006)
	# rear doors swung open
	for sx in [-1.0, 1.0]:
		var hinge := Node3D.new()
		hinge.position = Vector3(sx * w * 0.5, 0, -0.02)
		hinge.rotation_degrees.y = sx * -105.0
		s.add_child(hinge)
		_box(hinge, Vector3(0.97, top - y0 - 0.1, 0.05), Vector3(-sx * 0.485, (top + y0) * 0.5, 0), paint, 0.025)
		_box(hinge, Vector3(0.7, 0.55, 0.012), Vector3(-sx * 0.5, 1.95, -0.03), glass, 0.0)
		_box(hinge, Vector3(0.03, 0.25, 0.04), Vector3(-sx * 0.9, 1.3, -0.04), Mats.m("metal"), 0.006)
	# cab
	var cab_l := 1.5
	var cz := L + cab_l * 0.5
	for sx in [-1.0, 1.0]:
		_box(s, Vector3(0.06, 1.5, cab_l), Vector3(sx * (w * 0.5 - 0.03), y0 + 0.75, cz), paint, 0.03, true)
		_box(s, Vector3(0.012, 0.5, 0.75), Vector3(sx * (w * 0.5 + 0.002), 1.72, cz - 0.15), glass, 0.0)
		_box(s, Vector3(0.012, 0.32, cab_l - 0.1), Vector3(sx * (w * 0.5 + 0.002), 1.35, cz), stripe, 0.0)
		_box(s, Vector3(0.05, 0.12, 0.2), Vector3(sx * (w * 0.5 + 0.1), 1.75, L + 0.5), dark, 0.01)   # mirror
	_box(s, Vector3(w, 0.08, cab_l * 0.7), Vector3(0, 2.1, L + cab_l * 0.35), paint, 0.04, true)
	_box(s, Vector3(w - 0.04, 0.75, 0.06), Vector3(0, 1.75, L + cab_l * 0.72), glass, 0.0, false, Vector3(-28, 0, 0))
	_box(s, Vector3(w, 0.55, 0.9), Vector3(0, y0 + 0.4, L + cab_l + 0.2), paint, 0.12, true)   # hood
	_box(s, Vector3(w + 0.04, 0.16, 0.18), Vector3(0, y0 + 0.08, L + cab_l + 0.62), dark, 0.03)   # bumper
	_box(s, Vector3(0.9, 0.22, 0.03), Vector3(0, y0 + 0.4, L + cab_l + 0.66), Mats.m("steel_dark", Color(0.6, 0.6, 0.6)), 0.01)   # grille
	for sx in [-1.0, 1.0]:
		_box(s, Vector3(0.3, 0.16, 0.03), Vector3(sx * 0.7, y0 + 0.48, L + cab_l + 0.66), Mats.glow(Color(1.0, 0.93, 0.75), 4.0), 0.02)
	# wheels
	for zz in [0.55, L + cab_l - 0.25]:
		for sx in [-1.0, 1.0]:
			var wh := MeshInstance3D.new()
			wh.mesh = Meshes.cyl(0.37, 0.25, 16)
			wh.material_override = rubber
			wh.position = Vector3(sx * (w * 0.5 - 0.08), 0.37, zz)
			wh.rotation_degrees.z = 90
			s.add_child(wh)
			var hub := MeshInstance3D.new()
			hub.mesh = Meshes.cyl(0.18, 0.26, 10)
			hub.material_override = Mats.m("metal", Color(0.8, 0.8, 0.8))
			hub.position = wh.position
			hub.rotation_degrees.z = 90
			s.add_child(hub)
	# ramp into the cargo bay (walkable)
	var ramp_len := 1.35
	var ang := atan2(y0 + 0.1, ramp_len)
	_box(s, Vector3(1.0, 0.04, sqrt(ramp_len * ramp_len + (y0 + 0.1) * (y0 + 0.1))), Vector3(0, (y0 + 0.1) * 0.5, -ramp_len * 0.5 - 0.1), Mats.m("metal", Color(0.9, 0.9, 0.9), {"pattern": 8, "cell": Vector2(0.06, 0.06), "gap": 0.01}), 0.006, true, Vector3(-rad_to_deg(ang), 0, 0))
	# interior cargo light + hazard light pool on the ground
	var bulb := _box(s, Vector3(0.3, 0.03, 0.12), Vector3(0, top - 0.04, L * 0.5), Mats.glow(Color(1.0, 0.85, 0.6), 5.0), 0.01)
	bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var il := OmniLight3D.new()
	il.light_color = Color(1.0, 0.82, 0.55)
	il.light_energy = 1.3
	il.omni_range = 3.2
	il.omni_attenuation = 1.4
	il.position = Vector3(0, top - 0.3, 1.0)
	il.light_volumetric_fog_energy = 0.8
	il.shadow_enabled = false
	s.add_child(il)
	_flash_light = OmniLight3D.new()
	_flash_light.light_energy = 0.0
	_flash_light.omni_range = 4.0
	_flash_light.position = Vector3(0, 1.3, -0.6)
	_flash_light.light_volumetric_fog_energy = 1.5
	s.add_child(_flash_light)
	# roof beacon (flashes on shipments)
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.albedo_color = Color(0.3, 0.3, 0.3)
	_flash_mat.emission_enabled = true
	_flash_mat.emission = Color(0.3, 1.0, 0.4)
	_flash_mat.emission_energy_multiplier = 0.0
	var bc := MeshInstance3D.new()
	bc.mesh = Meshes.cyl(0.1, 0.12, 12)
	bc.material_override = _flash_mat
	bc.position = Vector3(0, top + 0.14, 0.4)
	s.add_child(bc)
	_label(s, "LOAD HERE ↓", Vector3(0, top - 0.25, -0.03), 64, Color(0.95, 0.85, 0.3), Vector3(0, 180, 0), 0.0035)
	_cargo_area(Vector3(1.75, 1.6, 2.9), Vector3(0, y0 + 0.9, 1.25))

# ------------------------------------------------------------------ chute (offices)
func _build_chute() -> void:
	var s := _shell
	var frame := Mats.m("metal_yellow")
	_box(s, Vector3(1.2, 1.0, 0.12), Vector3(0, 1.1, 0.06), Mats.m("steel_dark"), 0.02, true)
	_box(s, Vector3(0.9, 0.7, 0.02), Vector3(0, 1.1, -0.01), Mats.m("tv_black"), 0.0)
	for sx in [-1.0, 1.0]:
		_box(s, Vector3(0.08, 1.05, 0.15), Vector3(sx * 0.6, 1.1, 0.0), frame, 0.02)
	# belt table leading into the hatch
	_box(s, Vector3(0.8, 0.08, 1.0), Vector3(0, 0.78, -0.5), Mats.m("rubber", Color(3, 3, 3)), 0.01, true)
	for zz in [-0.9, -0.1]:
		for sx in [-1.0, 1.0]:
			_box(s, Vector3(0.05, 0.76, 0.05), Vector3(sx * 0.35, 0.38, zz), frame, 0.008, true)
	_label(s, "DISPATCH", Vector3(0, 1.75, -0.01), 72, Color(0.95, 0.8, 0.2), Vector3(0, 180, 0), 0.003)
	var am := StandardMaterial3D.new()
	am.albedo_color = Color(1.0, 0.55, 0.05)
	am.emission_enabled = true
	am.emission = Color(1.0, 0.55, 0.05)
	_blink_mats.append(am)
	_box(s, Vector3(0.1, 0.1, 0.05), Vector3(0.5, 1.75, -0.02), am, 0.01)
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.emission_enabled = true
	_flash_mat.emission = Color(0.3, 1.0, 0.4)
	_box(s, Vector3(0.1, 0.1, 0.05), Vector3(-0.5, 1.75, -0.02), _flash_mat, 0.01)
	_flash_light = OmniLight3D.new()
	_flash_light.light_energy = 0.0
	_flash_light.omni_range = 3.0
	_flash_light.position = Vector3(0, 1.3, -0.6)
	s.add_child(_flash_light)
	_cargo_area(Vector3(0.9, 0.9, 1.1), Vector3(0, 1.2, -0.5))

# ------------------------------------------------------------------ feedback
## Next free spot inside the cargo bay (local).
func slot_for(i: int) -> Transform3D:
	if style != "van":
		return Transform3D(Basis(), Vector3(0, 1.0, 0.4))
	var col := i % 2
	var row := (i / 2) % 4
	var layer := (i / 8) % 3
	return Transform3D(Basis(Vector3.UP, deg_to_rad(90.0 + (i % 3) * 4.0 - 4.0)), Vector3(-0.42 + col * 0.84, 0.5 + 0.11 + 0.18 + layer * 0.37, 2.55 - row * 0.45))

func flash(ok: bool, text: String = "") -> void:
	_flash = 1.0
	_flash_col = Color(0.3, 1.0, 0.45) if ok else Color(1.0, 0.2, 0.12)
	_bounce = 1.0
	if text != "":
		var l := _label(self, text, Vector3(0, 2.0, -0.5), 72, _flash_col * 1.6, Vector3.ZERO, 0.004)
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.shaded = false
		l.outline_size = 16
		l.outline_modulate = Color(0, 0, 0, 0.8)
		l.no_depth_test = true
		var tw := l.create_tween()
		tw.set_parallel(true)
		tw.tween_property(l, "position:y", 2.9, 1.8)
		tw.tween_property(l, "modulate:a", 0.0, 1.8).set_delay(0.6)
		tw.chain().tween_callback(l.queue_free)

func _process(delta: float) -> void:
	_t += delta
	var on := fmod(_t, 1.1) < 0.5
	for m in _blink_mats:
		(m as StandardMaterial3D).emission_energy_multiplier = 4.0 if on else 0.0
	_flash = maxf(0.0, _flash - delta * 0.9)
	if _flash_mat:
		_flash_mat.emission = _flash_col
		_flash_mat.emission_energy_multiplier = 8.0 * _flash * (0.6 + 0.4 * sin(_t * 30.0))
	if _flash_light:
		_flash_light.light_color = _flash_col
		_flash_light.light_energy = 3.0 * _flash
	if _shell and style == "van":
		_bounce = maxf(0.0, _bounce - delta * 2.2)
		_shell.position.y = -sin(_bounce * PI * 3.0) * 0.035 * _bounce
