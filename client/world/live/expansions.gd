extends Node3D
## 0.5.0 garage expansions (WORLD agent): the rooms that grow out of the garage before the move to an office.
## Driven by Game.state.hq.expansions {id: {level}} (docs/ACTIONS.md "Expansions"). Level space = the garage's.
##   annex     side annex lab through the LEFT wall door (world x[-10.2,-4.2] z[-2.5,2.5], 2.8 high)
##   basement  trapdoor + stairs down (x[-4,4] z[-3.5,3.5], floor y -2.8, 2.4 high), alcoves for shelves/racks
##   shed      backyard workshop through the BACK door (x[-1.5,3.5] z[-10,-6], 2.6 high), board-and-batten
##   showroom  glass storefront out front, right of the driveway (x[0.6,4.0] z[3.7,7.7], 2.8 high)
## Not bought: the door is shut with a cardboard "FOR SALE" tag (interactable `expansion_locked`, id = expansion id,
## prompt "Buy: <name>") and the plot outside is staked out with tape + a realtor sign. Bought: the door stands open,
## the room has its own light and mood; levels 2/3 visibly equip it (lights, ducts, racks, signage, awning...).
## Built-in equipment stays out of the furnishing area (alcoves, ceiling, outside walls) so it never fights
## the player's own furniture (server bounds: shared-luau/Data/RoomGeometry.luau).

const Mats := preload("res://world/lib/mats.gd")
const Meshes := preload("res://world/lib/meshes.gd")
const Data := preload("res://world/build/interior_data.gd")
const Anim := preload("res://world/build/item_anim.gd")

const W := 4.0
const D := 3.5
const H := 3.0
const T := 0.2
const DOOR_H := 2.04
const IDS := ["annex", "basement", "shed", "showroom"]
const NAMES := {"annex": "Side annex lab", "basement": "Basement", "shed": "Backyard workshop", "showroom": "Showroom"}
const BASE_Y := -2.8          # basement floor
const TRAP := Rect2(-1.6, -2.7, 1.2, 2.9)

var level: Node3D
var decor_only := false
var levels := {}               # id -> built level (0 = locked look)
var roots := {}                # id -> Node3D
var bodies := {}               # id -> StaticBody3D
var _cur: StaticBody3D         # body the helpers add collision to
var _ia: Array = []            # interactables built for the current id

func _ready() -> void:
	name = "Expansions"
	if not decor_only:
		Bus.state_changed.connect(func(keys: Array) -> void:
			if keys.has("hq"):
				refresh(Game.state))
	refresh(Game.state)

func refresh(s: Dictionary) -> void:
	for id in IDS:
		var lv := 0 if decor_only else Data.expansion_level(s, id)
		if levels.get(id, -1) == lv:
			continue
		var was: int = levels.get(id, -1)
		levels[id] = lv
		if roots.has(id) and is_instance_valid(roots[id]):
			(roots[id] as Node).queue_free()
		var r := Node3D.new()
		r.name = "Exp_" + id
		add_child(r)
		roots[id] = r
		_cur = StaticBody3D.new()
		_cur.name = "Collision"
		r.add_child(_cur)
		bodies[id] = _cur
		match id:
			"annex":
				_annex(r, lv)
			"basement":
				_basement(r, lv)
			"shed":
				_shed(r, lv)
			"showroom":
				_showroom(r, lv)
		if was == 0 and lv > 0 and is_inside_tree():
			Sfx.play("door_open", global_transform * _door_point(id))
			var Puff: Script = load("res://world/build/puff.gd")
			Puff.spawn(self, global_transform * _door_point(id), 1.2, Color(0.8, 0.75, 0.65))

func level_of(id: String) -> int:
	return int(levels.get(id, 0))

func _door_point(id: String) -> Vector3:
	match id:
		"annex":
			return Vector3(-W, 0.1, 0.45)
		"basement":
			return Vector3(-1.0, 0.1, -1.2)
		"shed":
			return Vector3(0.72, 0.1, -D)
		_:
			return Vector3(1.06, 0.1, D)

## Footstep surface for the new spaces (level space), "" = let the level decide.
func surface_at(p: Vector3) -> String:
	if p.x < -W - 0.1 and absf(p.z) < 2.6:
		return "concrete"
	if p.z < -5.9 and p.z > -10.1 and p.x > -1.6 and p.x < 3.6:
		return "wood"
	if p.z > D + 0.15 and p.x > 0.55 and p.x < 4.05 and p.z < 7.75 and level_of("showroom") > 0:
		return "concrete"
	return ""

# ================================================================== helpers
func _box(p: Node3D, size: Vector3, pos: Vector3, mat: Material, collide: bool = false, bevel: float = 0.01, rot: Vector3 = Vector3.ZERO, shadow: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = Meshes.cbox(size, minf(bevel, minf(size.x, minf(size.y, size.z)) * 0.45))
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.add_child(mi)
	if collide:
		_shape(size, mi.global_transform if mi.is_inside_tree() else _xf(p) * mi.transform)
	return mi

func _xf(n: Node3D) -> Transform3D:
	var t := Transform3D()
	var cur: Node = n
	while cur and cur != self:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t

## Box collision at a transform relative to this node (= level space).
func _shape(size: Vector3, xf_level: Transform3D) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.transform = xf_level
	_cur.add_child(cs)

func _cyl(p: Node3D, r: float, h: float, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO, sides: int = 12) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = Meshes.cyl(r, h, sides)
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot
	p.add_child(mi)
	return mi

func _node(p: Node3D, pos: Vector3, rot_y: float = 0.0, nm: String = "") -> Node3D:
	var n := Node3D.new()
	if nm != "":
		n.name = nm
	n.position = pos
	n.rotation_degrees.y = rot_y
	p.add_child(n)
	return n

func _label(p: Node3D, text: String, pos: Vector3, px: int, col: Color, rot: Vector3 = Vector3.ZERO, ps: float = 0.0016, shaded: bool = true) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.rotation_degrees = rot
	l.font_size = px
	l.pixel_size = ps
	l.modulate = col
	l.shaded = shaded
	l.outline_size = 0
	l.double_sided = false
	if ResourceLoader.exists("res://ui/fonts/Inter-Bold.ttf"):
		l.font = load("res://ui/fonts/Inter-Bold.ttf")
	p.add_child(l)
	return l

func _omni(p: Node3D, pos: Vector3, col: Color, energy: float, rng: float, shadow: bool = false, fog: float = 0.8) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng
	l.omni_attenuation = 1.6
	l.shadow_enabled = shadow
	l.omni_shadow_mode = OmniLight3D.SHADOW_DUAL_PARABOLOID
	l.shadow_blur = 1.5
	l.shadow_bias = 0.04
	l.light_volumetric_fog_energy = fog
	l.light_specular = 0.5
	p.add_child(l)
	return l

func _spot(p: Node3D, pos: Vector3, target: Vector3, col: Color, energy: float, rng: float, angle: float, shadow: bool = false, fog: float = 0.8) -> SpotLight3D:
	var l := SpotLight3D.new()
	p.add_child(l)
	var dir := target - pos
	var up := Vector3.UP if absf(dir.normalized().y) < 0.98 else Vector3.FORWARD
	l.transform = Transform3D(Basis.looking_at(dir, up), pos)
	l.light_color = col
	l.light_energy = energy
	l.spot_range = rng
	l.spot_angle = angle
	l.spot_angle_attenuation = 0.8
	l.shadow_enabled = shadow
	l.shadow_blur = 1.2
	l.light_volumetric_fog_energy = fog
	return l

func _tube(p: Node3D, pos: Vector3, rot_y: float, shadow: bool, col: Color = Color(0.82, 0.95, 1.0), energy: float = 2.4) -> void:
	var g := _node(p, pos, rot_y)
	_box(g, Vector3(1.3, 0.05, 0.14), Vector3.ZERO, Mats.m("metal", Color(1.1, 1.1, 1.1), {"metallic_base": 0.3}))
	var t := _cyl(g, 0.016, 1.2, Vector3(0, -0.04, 0), Mats.glow(col, 5.0), Vector3(0, 0, 90), 8)
	t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var l := _spot(g, Vector3(0, -0.08, 0), Vector3(0, -2, 0.001), col, energy, 4.5, 75.0, shadow, 0.9)
	l.position = Vector3(0, -0.08, 0)

func _bulb(p: Node3D, pos: Vector3, drop: float, col: Color, energy: float, rng: float, shadow: bool) -> void:
	_box(p, Vector3(0.01, drop, 0.01), pos - Vector3(0, drop * 0.5, 0), Mats.m("rubber"), false, 0.0)
	_cyl(p, 0.025, 0.06, pos - Vector3(0, drop + 0.02, 0), Mats.m("plastic_black"), Vector3.ZERO, 10)
	var b := MeshInstance3D.new()
	b.mesh = Meshes.sphere(0.05, 12)
	b.material_override = Mats.glow(col, 12.0)
	b.position = pos - Vector3(0, drop + 0.09, 0)
	b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.add_child(b)
	_omni(p, pos - Vector3(0, drop + 0.16, 0), col, energy, rng, shadow, 1.0)

func _window(p: Node3D, center: Vector3, size: Vector2, rot_y: float, outside_glow: Color) -> void:
	var g := _node(p, center, rot_y)
	var frame := Mats.m("plaster", Color(1.15, 1.15, 1.1), {"edge_wear": 0.3})
	for s in [-1.0, 1.0]:
		_box(g, Vector3(0.05, size.y + 0.05, 0.24), Vector3(s * size.x * 0.5, 0, 0), frame)
		_box(g, Vector3(size.x + 0.05, 0.05, 0.24), Vector3(0, s * size.y * 0.5, 0), frame)
	_box(g, Vector3(0.04, size.y, 0.06), Vector3.ZERO, frame)
	var gl := _box(g, Vector3(size.x, size.y, 0.006), Vector3(0, 0, 0), Mats.glass(Color(0.55, 0.62, 0.7, 0.12)), false, 0.0)
	gl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# (the outside behind these windows is the real lot / yard / street: no fake glow panel)
	_shape(Vector3(size.x, size.y, 0.2), _xf(g))

## A door leaf hinged at `hinge` (level space), closed along +X of `yaw`, opened by `open_deg`.
## Closed doors block the opening and carry the "for sale" interactable.
func _door(p: Node3D, hinge: Vector3, yaw: float, w: float, open_deg: float, id: String, mat: Material, sale: bool, inside_sign: float = 1.0) -> Node3D:
	var hn := _node(p, hinge, yaw + open_deg, "Door")
	var leaf := _node(hn, Vector3.ZERO)
	_box(leaf, Vector3(w - 0.02, DOOR_H - 0.02, 0.045), Vector3(w * 0.5, DOOR_H * 0.5, 0), mat)
	for r in 2:
		_box(leaf, Vector3(w * 0.36, 0.7 if r == 0 else 0.5, 0.012), Vector3(w * 0.28 + (w * 0.44) * (r % 2), 0.55 + r * 0.95, 0.026), mat)
	var knob := MeshInstance3D.new()
	knob.mesh = Meshes.sphere(0.03, 10)
	knob.material_override = Mats.m("metal", Color(1.2, 1.0, 0.6))
	knob.position = Vector3(w - 0.09, 1.0, 0.05 * inside_sign)
	leaf.add_child(knob)
	if open_deg == 0.0:
		_shape(Vector3(w, DOOR_H, 0.1), _xf(leaf) * Transform3D(Basis(), Vector3(w * 0.5, DOOR_H * 0.5, 0)))
	if sale:
		_sale_tag(leaf, Vector3(w * 0.5, 1.4, 0.04 * inside_sign), 0.0 if inside_sign > 0 else 180.0, id)
		var tape := Mats.m("metal_yellow", Color.WHITE, {"metallic_base": 0.0, "roughness_base": 0.4, "pattern": 1, "cell": Vector2(0.12, 0.05), "albedo2": Color(0.05, 0.05, 0.05), "gap": 0.0})
		for sg in [-1.0, 1.0]:
			_box(leaf, Vector3(0.07, sqrt(w * w + 1.6 * 1.6) + 0.1, 0.004), Vector3(w * 0.5, 0.95, 0.03 * inside_sign), tape, false, 0.0, Vector3(0, 0, sg * rad_to_deg(atan2(w, 1.6))), false)
		var ia := StaticBody3D.new()
		ia.name = "IA_expansion_locked"
		ia.add_to_group("interactable")
		ia.set_meta("kind", "expansion_locked")
		ia.set_meta("id", id)
		ia.set_meta("prompt", "Buy: %s" % NAMES.get(id, id))
		ia.collision_layer = 1
		leaf.add_child(ia)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(w, DOOR_H, 0.12)
		cs.shape = bs
		cs.position = Vector3(w * 0.5, DOOR_H * 0.5, 0)
		ia.add_child(cs)
		_ia.append(ia)
	return hn

## Cardboard tag on a string: "FOR SALE" + what it is.
func _sale_tag(p: Node3D, pos: Vector3, rot_y: float, id: String) -> void:
	var g := _node(p, pos, rot_y, "ForSale")
	_box(g, Vector3(0.006, 0.22, 0.006), Vector3(-0.14, 0.2, 0), Mats.m("plastic_white"), false, 0.0, Vector3(0, 0, -25))
	_box(g, Vector3(0.006, 0.22, 0.006), Vector3(0.14, 0.2, 0), Mats.m("plastic_white"), false, 0.0, Vector3(0, 0, 25))
	_box(g, Vector3(0.62, 0.42, 0.012), Vector3(0, 0, 0.012), Mats.m("cardboard", Color(1.1, 1.05, 1.0)), false, 0.004, Vector3(0, 0, -3))
	_label(g, "FOR SALE", Vector3(0, 0.08, 0.02), 90, Color(0.8, 0.1, 0.06), Vector3(0, 0, -3), 0.0014)
	_label(g, str(NAMES.get(id, id)).to_upper(), Vector3(0, -0.06, 0.02), 44, Color(0.15, 0.12, 0.1), Vector3(0, 0, -3), 0.0013)
	_label(g, "ask the realtor →", Vector3(0, -0.15, 0.02), 28, Color(0.3, 0.25, 0.2), Vector3(0, 0, -3), 0.0013)

## Staked plot outside: four stakes, caution tape between them, a realtor sign facing `sign_dir`.
func _plot(p: Node3D, x0: float, x1: float, z0: float, z1: float, sign_pos: Vector3, sign_yaw: float, id: String) -> void:
	var g := _node(p, Vector3.ZERO, 0.0, "Plot")
	var tape := Mats.m("metal_yellow", Color.WHITE, {"metallic_base": 0.0, "roughness_base": 0.4, "pattern": 1, "cell": Vector2(0.12, 0.05), "albedo2": Color(0.05, 0.05, 0.05), "gap": 0.0})
	var corners := [Vector3(x0, 0, z0), Vector3(x1, 0, z0), Vector3(x1, 0, z1), Vector3(x0, 0, z1)]
	for c in corners:
		_box(g, Vector3(0.05, 0.7, 0.05), c + Vector3(0, 0.35, 0), Mats.m("wood"), false, 0.006)
		_box(g, Vector3(0.06, 0.06, 0.06), c + Vector3(0, 0.68, 0), Mats.m("plastic_orange"), false, 0.01)
	for i in 4:
		var a: Vector3 = corners[i] + Vector3(0, 0.6, 0)
		var b: Vector3 = corners[(i + 1) % 4] + Vector3(0, 0.6, 0)
		var seg := _box(g, Vector3(0.05, 0.003, a.distance_to(b)), (a + b) * 0.5 - Vector3(0, 0.04, 0), tape, false, 0.0, Vector3.ZERO, false)
		seg.transform = Transform3D(Basis.looking_at(b - a, Vector3.UP), (a + b) * 0.5 - Vector3(0, 0.04, 0))
	var sg := _node(g, sign_pos, sign_yaw, "RealtorSign")
	_box(sg, Vector3(0.05, 1.3, 0.05), Vector3(-0.42, 0.65, 0), Mats.m("wood_dark"), false, 0.006)
	_box(sg, Vector3(0.05, 1.3, 0.05), Vector3(0.42, 0.65, 0), Mats.m("wood_dark"), false, 0.006)
	_box(sg, Vector3(1.0, 0.6, 0.03), Vector3(0, 1.0, 0), Mats.m("plastic_white", Color(1.15, 1.12, 1.05)), false, 0.008)
	_box(sg, Vector3(1.0, 0.14, 0.032), Vector3(0, 1.23, 0), Mats.m("metal_red", Color(1.3, 1.3, 1.3), {"metallic_base": 0.0}), false, 0.004)
	_label(sg, "FOR SALE", Vector3(0, 1.23, 0.018), 72, Color(0.98, 0.95, 0.9), Vector3.ZERO, 0.0016)
	_label(sg, str(NAMES.get(id, id)).to_upper(), Vector3(0, 1.06, 0.018), 54, Color(0.12, 0.12, 0.15), Vector3.ZERO, 0.0016)
	_label(sg, "build here · ask inside", Vector3(0, 0.88, 0.018), 34, Color(0.35, 0.3, 0.3), Vector3.ZERO, 0.0016)
	_shape(Vector3(1.0, 1.3, 0.1), _xf(sg) * Transform3D(Basis(), Vector3(0, 0.65, 0)))

# ================================================================== side annex lab
func _annex(r: Node3D, lv: int) -> void:
	var dz0 := 0.0
	var dz1 := 0.9
	var hinge := Vector3(-W - 0.1, 0, dz1)
	if lv <= 0:
		_door(r, hinge, 90.0, dz1 - dz0, 0.0, "annex", Mats.m("plaster", Color(0.95, 0.95, 1.0)), not decor_only, 1.0)
		if not decor_only:
			_plot(r, -10.2, -4.4, -2.5, 2.5, Vector3(-7.2, 0, 2.9), 0.0, "annex")
		return
	var x0 := -10.2
	var x1 := -4.2
	var z0 := -2.5
	var z1 := 2.5
	var hh := 2.8
	var g := _node(r, Vector3.ZERO, 0.0, "Annex")
	var wall := Mats.m("plaster_cool", Color(1.05, 1.05, 1.08))
	var ext := Mats.m("siding_warm", Color(0.85, 0.85, 0.85))
	var floor_m := Mats.m("floor_tiles", Color(1.1, 1.12, 1.15)) if lv < 2 else Mats.m("floor_tiles", Color(0.75, 0.85, 1.05), {"cell": Vector2(0.6, 0.6)})
	_box(g, Vector3(x1 - x0 + 0.2, 0.2, z1 - z0 + 0.4), Vector3((x0 + x1) * 0.5 - 0.1, -0.1, 0), floor_m, true, 0.0)
	_box(g, Vector3(x1 - x0 + 0.4, 0.12, z1 - z0 + 0.4), Vector3((x0 + x1) * 0.5 - 0.1, hh + 0.06, 0), Mats.m("ceiling_tiles"), true, 0.0)
	# lean-to roof (seen from the driveway): slopes down to the left
	_box(g, Vector3(x1 - x0 + 0.7, 0.12, z1 - z0 + 0.8), Vector3((x0 + x1) * 0.5 - 0.15, hh + 0.38, 0), Mats.m("roof"), false, 0.0, Vector3(0, 0, 6))
	# walls: far (x0) with a high window, back (z0) solid, front (z1, the street side) with a window
	_wall_x(g, x0 - 0.1, z0 - 0.2, z1 + 0.2, hh, [[-0.8, 0.8, 1.2, 2.0]], wall)
	_panel(g, "x", x0 - 0.21, z0 - 0.2, z1 + 0.2, hh, [[-0.8, 0.8, 1.2, 2.0]], ext)
	_box(g, Vector3(x1 - x0, hh + 0.12, 0.2), Vector3((x0 + x1) * 0.5, (hh + 0.12) * 0.5, z0 - 0.1), wall, true, 0.0)
	_wall_z(g, z1 + 0.1, x0, x1, hh, [[-9.2, -7.6, 0.95, 2.0]], wall)
	_panel(g, "z", z1 + 0.21, x0 - 0.2, x1 + 0.2, hh, [[-9.2, -7.6, 0.95, 2.0]], ext)
	_window(g, Vector3(x0 - 0.1, 1.6, 0.0), Vector2(1.6, 0.8), 90.0, Color(0.2, 0.28, 0.5))
	_window(g, Vector3(-8.4, 1.475, z1 + 0.1), Vector2(1.6, 1.05), 0.0, Color(0.25, 0.3, 0.55))
	# baseboard + the door, open into the lab
	for z in [z0 + 0.01, z1 - 0.01]:
		_box(g, Vector3(x1 - x0, 0.08, 0.02), Vector3((x0 + x1) * 0.5, 0.04, z), Mats.m("plastic_grey"), false, 0.0)
	_door(r, hinge, 90.0, dz1 - dz0, 90.0, "annex", Mats.m("plaster", Color(0.95, 0.95, 1.0)), false)
	_label(g, "LAB", Vector3(x1 - 0.02, 2.4, 0.45), 110, Color(0.25, 0.3, 0.4), Vector3(0, -90, 0), 0.002)
	# lights: one shadowed cold tube + an LED panel, a warm sconce by the door (one warm key, one cold counter)
	_tube(g, Vector3(-8.2, hh - 0.08, -0.6), 0.0, true)
	_box(g, Vector3(1.2, 0.02, 0.6), Vector3(-6.0, hh - 0.012, 0.8), Mats.glow(Color(0.85, 0.93, 1.0), 2.0), false, 0.0, Vector3.ZERO, false)
	_spot(g, Vector3(-6.0, hh - 0.05, 0.8), Vector3(-6.0, 0, 0.801), Color(0.85, 0.93, 1.0), 1.6, 4.0, 75.0, false, 0.5)
	var sc := _node(g, Vector3(x1 - 0.03, 1.95, 1.35), -90.0, "Sconce")
	_box(sc, Vector3(0.12, 0.2, 0.06), Vector3(0, 0, 0.03), Mats.m("metal", Color(1.2, 1.0, 0.7)))
	_box(sc, Vector3(0.09, 0.14, 0.02), Vector3(0, 0, 0.065), Mats.glow(Color(1.0, 0.72, 0.4), 4.0), false, 0.0)
	_omni(sc, Vector3(0, 0.0, 0.25), Color(1.0, 0.66, 0.36), 0.8, 3.5)
	# hazard tape threshold, a fire extinguisher and a safety sign above head height by the door
	_box(g, Vector3(0.12, 0.004, 0.9), Vector3(x1 - 0.06, 0.003, 0.45), Mats.m("metal_yellow", Color.WHITE, {"metallic_base": 0.0, "pattern": 1, "cell": Vector2(0.1, 0.05), "albedo2": Color(0.05, 0.05, 0.05)}), false, 0.0)
	_box(g, Vector3(0.36, 0.26, 0.01), Vector3(x1 - 0.01, 2.35, -0.6), Mats.m("plastic_white", Color(0.2, 0.55, 0.3)), false, 0.0, Vector3(0, -90, 0))
	_label(g, "EYE WASH\n→", Vector3(x1 - 0.02, 2.35, -0.6), 34, Color(0.95, 0.95, 0.95), Vector3(0, -90, 0), 0.0016)
	# cable tray along the ceiling from the garage door
	_box(g, Vector3(5.6, 0.04, 0.22), Vector3(-7.2, hh - 0.25, z0 + 0.25), Mats.m("steel_dark"), false, 0.004)
	for i in 3:
		_box(g, Vector3(5.5, 0.025, 0.025), Vector3(-7.2, hh - 0.215, z0 + 0.18 + i * 0.05), Mats.m("plastic_white", [Color(0.9, 0.2, 0.1), Color(0.2, 0.4, 0.9), Color(0.2, 0.2, 0.2)][i]), false, 0.0)
	if lv >= 2:
		# level 2: ESD floor (above), a second LED panel, an extractor fan in the back wall, grounding strip
		_box(g, Vector3(1.2, 0.02, 0.6), Vector3(-9.0, hh - 0.012, 1.0), Mats.glow(Color(0.85, 0.93, 1.0), 2.0), false, 0.0, Vector3.ZERO, false)
		_spot(g, Vector3(-9.0, hh - 0.05, 1.0), Vector3(-9.0, 0, 1.001), Color(0.85, 0.93, 1.0), 1.2, 4.0, 75.0, false, 0.4)
		var fan := _node(g, Vector3(-5.2, 2.3, z0 + 0.02), 0.0, "Extractor")
		_box(fan, Vector3(0.5, 0.5, 0.06), Vector3(0, 0, 0.03), Mats.m("metal", Color(1.1, 1.1, 1.1)))
		var blades := _node(fan, Vector3(0, 0, 0.07))
		for k in 4:
			_box(blades, Vector3(0.06, 0.2, 0.01), Vector3(0, 0.1, 0), Mats.m("steel_dark"), false, 0.0, Vector3(0, 0, k * 90.0)).position = Vector3(sin(k * PI * 0.5) * 0.1, cos(k * PI * 0.5) * 0.1, 0)
		var a := Anim.new()
		a.target = blades
		a.mode = "spin"
		a.speed = 9.0
		a.axis = Vector3.BACK
		fan.add_child(a)
		_box(g, Vector3(x1 - x0, 0.03, 0.01), Vector3((x0 + x1) * 0.5, 0.3, z0 + 0.012), Mats.m("metal", Color(1.2, 1.0, 0.5)), false, 0.0)
		_label(g, "ESD AREA", Vector3(-8.0, 2.5, z0 + 0.012), 64, Color(0.95, 0.75, 0.15), Vector3.ZERO, 0.0016)
	if lv >= 3:
		# level 3: a skylight (dusk sky), a clean-air unit on the ceiling and a cool accent strip
		_box(g, Vector3(1.0, 0.02, 1.4), Vector3(-7.2, hh + 0.005, -0.6), Mats.glow(Color(0.22, 0.3, 0.6), 0.9), false, 0.0, Vector3.ZERO, false)
		for s in [-1.0, 1.0]:
			_box(g, Vector3(1.08, 0.08, 0.04), Vector3(-7.2, hh - 0.02, -0.6 + s * 0.72), Mats.m("steel_dark"))
		_omni(g, Vector3(-7.2, hh - 0.4, -0.6), Color(0.45, 0.55, 0.95), 0.6, 3.5)
		var hepa := _node(g, Vector3(-9.3, hh - 0.18, -1.6), 0.0, "HEPA")
		_box(hepa, Vector3(0.9, 0.3, 0.6), Vector3.ZERO, Mats.m("plastic_white", Color(1.15, 1.15, 1.15)))
		_box(hepa, Vector3(0.8, 0.01, 0.5), Vector3(0, -0.155, 0), Mats.m("metal", Color.WHITE, {"pattern": 8, "cell": Vector2(0.03, 0.03)}), false, 0.0)
		_box(hepa, Vector3(0.05, 0.02, 0.005), Vector3(0.35, 0.0, 0.302), Mats.glow(Color(0.3, 1.0, 0.5), 3.0), false, 0.0)
		_box(g, Vector3(x1 - x0 - 0.1, 0.012, 0.012), Vector3((x0 + x1) * 0.5, hh - 0.03, z1 - 0.03), Mats.glow(Color(0.3, 0.75, 1.0), 3.0), false, 0.0, Vector3.ZERO, false)
		_label(g, "CLEAN LAB · LV3", Vector3(-6.2, 2.5, z0 + 0.012), 54, Color(0.4, 0.75, 1.0), Vector3.ZERO, 0.0016)

## A wall along Z at x (thickness 0.2) from z0 to z1, height hh, with openings [[z0,z1,y0,y1]] + collision.
func _wall_x(g: Node3D, x: float, z0: float, z1: float, hh: float, holes: Array, mat: Material, yb: float = 0.0) -> void:
	var V: Script = load("res://world/build/interior_view.gd")
	for rc in V.split_rect(z0, z1, 0.0, hh + 0.12, holes):
		_box(g, Vector3(0.2, rc[3] - rc[2], rc[1] - rc[0]), Vector3(x, yb + (rc[2] + rc[3]) * 0.5, (rc[0] + rc[1]) * 0.5), mat, true, 0.0)

## Thin cladding / lining (2 cm, no collision) along a wall line with holes (doors / windows).
func _panel(g: Node3D, axis: String, at: float, a0: float, a1: float, hh: float, holes: Array, mat: Material) -> void:
	var V: Script = load("res://world/build/interior_view.gd")
	for rc in V.split_rect(a0, a1, 0.0, hh, holes):
		if axis == "x":
			_box(g, Vector3(0.02, rc[3] - rc[2], rc[1] - rc[0]), Vector3(at, (rc[2] + rc[3]) * 0.5, (rc[0] + rc[1]) * 0.5), mat, false, 0.0)
		else:
			_box(g, Vector3(rc[1] - rc[0], rc[3] - rc[2], 0.02), Vector3((rc[0] + rc[1]) * 0.5, (rc[2] + rc[3]) * 0.5, at), mat, false, 0.0)

func _wall_z(g: Node3D, z: float, x0: float, x1: float, hh: float, holes: Array, mat: Material, yb: float = 0.0) -> void:
	var V: Script = load("res://world/build/interior_view.gd")
	for rc in V.split_rect(x0, x1, 0.0, hh + 0.12, holes):
		_box(g, Vector3(rc[1] - rc[0], rc[3] - rc[2], 0.2), Vector3((rc[0] + rc[1]) * 0.5, yb + (rc[2] + rc[3]) * 0.5, z), mat, true, 0.0)

# ================================================================== basement
func _basement(r: Node3D, lv: int) -> void:
	var hx0 := TRAP.position.x
	var hx1 := TRAP.position.x + TRAP.size.x
	var hz0 := TRAP.position.y
	var hz1 := TRAP.position.y + TRAP.size.y
	var plank := Mats.m("wood_planks", Color(0.95, 0.88, 0.8), {"cell": Vector2(1.3, 0.16)})
	if lv <= 0:
		# trapdoor shut: two plank leaves flush with the floor, chain + padlock, stencil
		var td := _node(r, Vector3(hx0, 0, hz0), 0.0, "Trapdoor")
		for i in 2:
			_box(td, Vector3(TRAP.size.x - 0.02, 0.04, TRAP.size.y * 0.5 - 0.02), Vector3(TRAP.size.x * 0.5, -0.02, TRAP.size.y * (0.25 + 0.5 * i)), plank, false, 0.006)
			for k in 2:
				_box(td, Vector3(0.04, 0.012, TRAP.size.y * 0.5 - 0.1), Vector3(0.15 + k * (TRAP.size.x - 0.3), 0.004, TRAP.size.y * (0.25 + 0.5 * i)), Mats.m("steel_dark"), false, 0.003)
		_shape(Vector3(TRAP.size.x, 0.1, TRAP.size.y), Transform3D(Basis(), Vector3(hx0 + TRAP.size.x * 0.5, -0.05, hz0 + TRAP.size.y * 0.5)))
		var hasp := _node(td, Vector3(TRAP.size.x * 0.5, 0.01, TRAP.size.y * 0.5), 0.0)
		for k in 6:
			var lk := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = 0.018
			tm.outer_radius = 0.026
			tm.rings = 10
			tm.ring_segments = 4
			lk.mesh = tm
			lk.material_override = Mats.m("metal")
			lk.position = Vector3(-0.15 + k * 0.06, 0.008, 0.0)
			lk.rotation_degrees = Vector3(0, 0, 90 if k % 2 else 0)
			hasp.add_child(lk)
		_box(hasp, Vector3(0.07, 0.03, 0.08), Vector3(0.22, 0.015, 0.0), Mats.m("metal", Color(1.2, 1.0, 0.5), {"metallic_base": 0.9}), false, 0.01)
		_label(td, "BASEMENT", Vector3(TRAP.size.x * 0.5, 0.003, TRAP.size.y * 0.3), 90, Color(0.95, 0.85, 0.2, 0.75), Vector3(-90, 180, 0), 0.0018)
		if decor_only:
			return
		var tag := _node(td, Vector3(TRAP.size.x * 0.5, 0.03, TRAP.size.y * 0.72), 0.0)
		_box(tag, Vector3(0.46, 0.012, 0.3), Vector3.ZERO, Mats.m("cardboard", Color(1.05, 1.0, 0.95)), false, 0.004, Vector3(0, 8, 0))
		_label(tag, "FOR SALE", Vector3(0, 0.008, -0.04), 64, Color(0.75, 0.1, 0.06), Vector3(-90, 188, 0), 0.0014)
		_label(tag, "BASEMENT · storage", Vector3(0, 0.008, 0.06), 30, Color(0.15, 0.12, 0.1), Vector3(-90, 188, 0), 0.0014)
		var ia := StaticBody3D.new()
		ia.name = "IA_expansion_locked"
		ia.add_to_group("interactable")
		ia.set_meta("kind", "expansion_locked")
		ia.set_meta("id", "basement")
		ia.set_meta("prompt", "Buy: %s" % NAMES.basement)
		td.add_child(ia)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(TRAP.size.x, 0.1, TRAP.size.y)
		cs.shape = bs
		cs.position = Vector3(TRAP.size.x * 0.5, -0.05, TRAP.size.y * 0.5)
		ia.add_child(cs)
		_ia.append(ia)
		return
	var y0 := BASE_Y
	var hh := 2.4
	var g := _node(r, Vector3.ZERO, 0.0, "Basement")
	var wall := Mats.m("block_wall", Color(0.78, 0.8, 0.78), {"floor_dirt": 1.0, "grime": 0.6})
	var conc := Mats.m("concrete_floor", Color(0.85, 0.85, 0.85))
	_box(g, Vector3(2 * W + 2 * T, 0.2, 2 * D + 2 * T), Vector3(0, y0 - 0.1, 0), conc, true, 0.0)
	var top := -y0 - 0.12 - 0.05   # walls up to the garage slab
	# walls with alcoves: left (x0) z[1,3], right (x1) z[-1.5,1.5], back (z0) x[1,3.6]
	_wall_x(g, -W - 0.1, -D - 0.2, D + 0.2, top, [[1.0, 3.0, 0.0, 2.0]], wall, y0)
	_wall_x(g, W + 0.1, -D - 0.2, D + 0.2, top, [[-1.5, 1.5, 0.0, 2.0]], wall, y0)
	_wall_z(g, -D - 0.1, -W, W, top, [[1.0, 3.6, 0.0, 2.0]], wall, y0)
	_wall_z(g, D + 0.1, -W, W, top, [], wall, y0)
	_alcove(g, "x0", Vector3(-W - 0.6, y0, 2.0), Vector3(0.6, 2.0, 2.0), wall)
	_alcove(g, "x1", Vector3(W + 0.6, y0, 0.0), Vector3(0.6, 2.0, 3.0), wall)
	_alcove(g, "z0", Vector3(2.3, y0, -D - 0.6), Vector3(2.6, 2.0, 0.6), wall)
	# underside of the garage slab: joists, pipes, a duct
	for i in 6:
		var x := -W + 0.6 + i * 1.36
		if x > hx0 - 0.05 and x < hx1 + 0.05:
			continue
		_box(g, Vector3(0.08, 0.18, 2 * D), Vector3(x, -0.49, 0), Mats.m("wood", Color(0.8, 0.75, 0.7)), false, 0.006)
	_cyl(g, 0.05, 2 * W - 0.4, Vector3(0, -0.66, -D + 0.3), Mats.m("metal", Color(0.8, 0.6, 0.45)), Vector3(0, 0, 90), 10)
	_cyl(g, 0.035, 2 * W - 0.4, Vector3(0, -0.76, -D + 0.45), Mats.m("steel_dark"), Vector3(0, 0, 90), 8)
	_box(g, Vector3(0.4, 0.25, 2 * D - 0.6), Vector3(W - 0.5, -0.6, 0.0), Mats.m("metal", Color(1.0, 1.0, 1.0), {"metallic_base": 0.6, "pattern": 9, "cell": Vector2(1.0, 0.3)}), false, 0.01)
	# damp stain + floor drain
	_cyl(g, 0.12, 0.004, Vector3(1.6, y0 + 0.003, 1.2), Mats.m("steel_dark", Color.WHITE, {"pattern": 8, "cell": Vector2(0.03, 0.03)}), Vector3.ZERO, 14)
	_cyl(g, 0.8, 0.002, Vector3(1.6, y0 + 0.002, 1.2), Mats.m("concrete_floor", Color(0.55, 0.55, 0.58), {"roughness_base": 0.15, "pattern": 0}), Vector3.ZERO, 18).scale = Vector3(1.3, 1, 0.8)
	# stairs: the ramp the player walks on + visible steps and stringers (top at the back, z -2.7; bottom at z 0.6)
	var zt := hz0
	var zb := 0.6
	var run := zb - zt
	var ang := atan2(-y0, run)
	var len_r := sqrt(run * run + y0 * y0)
	var ramp_xf := Transform3D(Basis(Vector3.RIGHT, ang), Vector3((hx0 + hx1) * 0.5, y0 * 0.5 - 0.06, (zt + zb) * 0.5))
	_shape(Vector3(hx1 - hx0, 0.1, len_r), ramp_xf)
	var steps := 13
	var tread := Mats.m("wood_planks", Color(1.05, 0.95, 0.85), {"cell": Vector2(1.3, 0.14)})
	for i in steps:
		var t := (i + 0.5) / steps
		_box(g, Vector3(hx1 - hx0 - 0.1, 0.04, run / steps + 0.03), Vector3((hx0 + hx1) * 0.5, -t * (-y0) - 0.01, zt + t * run), tread, false, 0.006)
	for sx in [hx0 + 0.03, hx1 - 0.03]:
		var st := _box(g, Vector3(0.05, 0.25, len_r), Vector3(sx, y0 * 0.5 - 0.05, (zt + zb) * 0.5), Mats.m("wood", Color(0.9, 0.85, 0.8)), false, 0.006)
		st.rotation = Vector3(ang, 0, 0)
	# the trapdoor leaves stand open along the -x side (= a guard), a railing on the deep +x end
	for i in 2:
		var leaf := _node(r, Vector3(hx0 - 0.02, 0.0, hz0 + TRAP.size.y * (0.25 + 0.5 * i)), 0.0)
		leaf.rotation_degrees.z = -84.0
		_box(leaf, Vector3(TRAP.size.x - 0.02, 0.04, TRAP.size.y * 0.5 - 0.02), Vector3(-TRAP.size.x * 0.5, 0.0, 0), plank, false, 0.006).rotation_degrees.z = 0
	_shape(Vector3(0.08, 1.2, TRAP.size.y), Transform3D(Basis(), Vector3(hx0 - 0.06, 0.6, hz0 + TRAP.size.y * 0.5)))
	var rail := Mats.m("metal_yellow")
	for p in [Vector3(hx1 + 0.03, 0, -1.2), Vector3(hx1 + 0.03, 0, hz1 + 0.03), Vector3(hx0, 0, hz1 + 0.03)]:
		_box(g, Vector3(0.05, 1.0, 0.05), p + Vector3(0, 0.5, 0), rail, false, 0.006)
	_box(g, Vector3(0.05, 0.05, hz1 + 1.2 + 0.03), Vector3(hx1 + 0.03, 1.0, (-1.2 + hz1 + 0.03) * 0.5), rail, false, 0.006)
	_box(g, Vector3(TRAP.size.x + 0.05, 0.05, 0.05), Vector3((hx0 + hx1) * 0.5, 1.0, hz1 + 0.03), rail, false, 0.006)
	_shape(Vector3(0.08, 1.1, hz1 + 1.2), Transform3D(Basis(), Vector3(hx1 + 0.03, 0.55, (-1.2 + hz1) * 0.5)))
	_shape(Vector3(TRAP.size.x, 1.1, 0.08), Transform3D(Basis(), Vector3((hx0 + hx1) * 0.5, 0.55, hz1 + 0.03)))
	# handrail down the stairs
	var hr := _box(g, Vector3(0.04, 0.04, len_r), Vector3(hx0 + 0.08, y0 * 0.5 + 0.85, (zt + zb) * 0.5), Mats.m("wood_dark"), false, 0.006)
	hr.rotation = Vector3(ang, 0, 0)
	# light: two bare bulbs (one shadowed key) + cold glow from the right alcove; a light leaking up the stairs
	_bulb(g, Vector3(1.4, -0.4, 1.4), 0.3, Color(1.0, 0.64, 0.34), 1.8, 6.5, true)
	_bulb(g, Vector3(-2.6, -0.4, -1.6), 0.25, Color(1.0, 0.6, 0.3), 0.9, 4.5, false)
	_omni(g, Vector3(-1.0, -0.6, -1.4), Color(1.0, 0.7, 0.45), 0.35, 3.0, false, 1.2)
	# fuse box + stencil
	_box(g, Vector3(0.35, 0.5, 0.1), Vector3(-W + 0.06, y0 + 1.5, -1.6), Mats.m("metal", Color(0.75, 0.75, 0.72)), false, 0.01)
	_label(g, "B1", Vector3(-W + 0.01, y0 + 1.9, -2.6), 140, Color(0.85, 0.8, 0.6, 0.6), Vector3(0, 90, 0), 0.002)
	# alcove contents by level: storage shelves (always), server racks (2+), cold aisle (3)
	_wire_shelves(g, Vector3(2.3, y0, -D - 0.55), 2.4)
	_label(g, "CRATES x3", Vector3(2.3, y0 + 2.12, -D - 0.08), 50, Color(0.95, 0.85, 0.3), Vector3.ZERO, 0.0016)
	if lv >= 2:
		for i in 2:
			_rack(g, Vector3(W + 0.55, y0, -0.7 + i * 0.75), -90.0)
		_label(g, "SERVERS", Vector3(W - 0.01, y0 + 2.12, 0.0), 50, Color(0.4, 0.75, 1.0), Vector3(0, -90, 0), 0.0016)
		_omni(g, Vector3(W - 0.2, y0 + 1.2, 0.0), Color(0.35, 0.6, 1.0), 0.7, 3.0, false, 1.0)
	else:
		_label(g, "SERVER ROOM\n(soon)", Vector3(W + 0.39, y0 + 1.2, 0.0), 44, Color(0.6, 0.6, 0.55), Vector3(0, -90, 0), 0.0016)
		_box(g, Vector3(0.004, 0.004, 2.6), Vector3(W + 0.15, y0 + 0.003, 0.0), Mats.m("metal_yellow", Color.WHITE, {"metallic_base": 0.0}), false, 0.0)
	if lv >= 3:
		_rack(g, Vector3(W + 0.55, y0, 1.15), -90.0)
		for i in 2:
			_rack(g, Vector3(-W - 0.55, y0, 1.5 + i * 0.75), 90.0)
		_box(g, Vector3(0.012, 0.012, 2.0), Vector3(-W + 0.02, y0 + 2.05, 2.0), Mats.glow(Color(0.3, 0.7, 1.0), 4.0), false, 0.0, Vector3.ZERO, false)
		_omni(g, Vector3(-W + 0.3, y0 + 1.2, 2.0), Color(0.3, 0.55, 1.0), 0.7, 3.0, false, 1.0)
		_label(g, "COLD AISLE", Vector3(-W + 0.01, y0 + 2.12, 2.0), 50, Color(0.4, 0.75, 1.0), Vector3(0, 90, 0), 0.0016)
	else:
		# boiler + water tank in the left alcove
		_cyl(g, 0.3, 1.6, Vector3(-W - 0.45, y0 + 0.8, 1.6), Mats.m("plastic_white", Color(0.9, 0.9, 0.85), {"grime": 0.7}), Vector3.ZERO, 16)
		_box(g, Vector3(0.5, 0.8, 0.45), Vector3(-W - 0.45, y0 + 0.9, 2.5), Mats.m("metal_red", Color(1.1, 1.1, 1.1)), false, 0.02)
		_omni(g, Vector3(-W - 0.2, y0 + 0.4, 2.5), Color(1.0, 0.45, 0.15), 0.4, 1.6, false, 0.6)

func _alcove(g: Node3D, side: String, c: Vector3, size: Vector3, mat: Material) -> void:
	# back wall + two cheeks + ceiling of a niche (c = floor centre of the niche, size = depth/height/width)
	match side:
		"x0", "x1":
			var s := -1.0 if side == "x0" else 1.0
			_box(g, Vector3(0.2, size.y + 0.2, size.z + 0.4), c + Vector3(s * (size.x * 0.5 + 0.1), size.y * 0.5, 0), mat, true, 0.0)
			for k in [-1.0, 1.0]:
				_box(g, Vector3(size.x + 0.2, size.y, 0.2), c + Vector3(0, size.y * 0.5, k * (size.z * 0.5 + 0.1)), mat, true, 0.0)
			_box(g, Vector3(size.x + 0.2, 0.2, size.z + 0.4), c + Vector3(0, size.y + 0.1, 0), mat, true, 0.0)
			_box(g, Vector3(size.x + 0.2, 0.2, size.z + 0.4), c + Vector3(0, -0.1, 0), Mats.m("concrete_floor"), true, 0.0)
		_:
			_box(g, Vector3(size.x + 0.4, size.y + 0.2, 0.2), c + Vector3(0, size.y * 0.5, -size.z * 0.5 - 0.1), mat, true, 0.0)
			for k in [-1.0, 1.0]:
				_box(g, Vector3(0.2, size.y, size.z + 0.2), c + Vector3(k * (size.x * 0.5 + 0.1), size.y * 0.5, 0), mat, true, 0.0)
			_box(g, Vector3(size.x + 0.4, 0.2, size.z + 0.2), c + Vector3(0, size.y + 0.1, 0), mat, true, 0.0)
			_box(g, Vector3(size.x + 0.4, 0.2, size.z + 0.2), c + Vector3(0, -0.1, 0), Mats.m("concrete_floor"), true, 0.0)

func _wire_shelves(g: Node3D, c: Vector3, w: float) -> void:
	var post := Mats.m("metal", Color(1.2, 1.2, 1.25))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box(g, Vector3(0.03, 1.9, 0.03), c + Vector3(sx * (w * 0.5 - 0.02), 0.95, sz * 0.2), post, false, 0.004)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	for i in 4:
		var y := 0.12 + i * 0.55
		_box(g, Vector3(w, 0.02, 0.45), c + Vector3(0, y, 0), Mats.m("metal", Color.WHITE, {"pattern": 8, "cell": Vector2(0.03, 0.03), "albedo2": Color(0.05, 0.05, 0.05)}), false, 0.004)
		if i < 3:
			var x := -w * 0.5 + 0.05
			while x < w * 0.5 - 0.3:
				var s := Vector3(rng.randf_range(0.25, 0.45), rng.randf_range(0.2, 0.4), 0.38)
				_box(g, s, c + Vector3(x + s.x * 0.5, y + 0.01 + s.y * 0.5, 0), Mats.m("cardboard", Color(1, 1, 1).lerp(Color(0.8, 0.78, 0.7), rng.randf())), false, 0.015, Vector3(0, rng.randf_range(-4, 4), 0))
				x += s.x + 0.04

func _rack(g: Node3D, pos: Vector3, yaw: float) -> void:
	var rk := _node(g, pos, yaw, "Rack")
	_box(rk, Vector3(0.6, 1.95, 0.9), Vector3(0, 0.975, 0), Mats.m("plastic_black"), false, 0.015)
	var mats: Array = []
	for i in 12:
		var y := 0.15 + i * 0.14
		_box(rk, Vector3(0.52, 0.1, 0.01), Vector3(0, y, 0.452), Mats.m("steel_dark"), false, 0.003)
		for k in 3:
			var lm := StandardMaterial3D.new()
			var c: Color = [Color(0.2, 1.0, 0.35), Color(0.3, 0.6, 1.0), Color(1.0, 0.65, 0.1)][(i + k) % 3]
			lm.albedo_color = c * 0.3
			lm.emission_enabled = true
			lm.emission = c
			lm.emission_energy_multiplier = 2.0
			_box(rk, Vector3(0.012, 0.012, 0.004), Vector3(-0.2 + k * 0.035, y, 0.46), lm, false, 0.0)
			mats.append(lm)
	var a := Anim.new()
	a.target = rk
	a.mode = "blink"
	a.speed = 1.1
	a.mats = mats
	rk.add_child(a)

# ================================================================== backyard shed (QC workshop)
func _shed(r: Node3D, lv: int) -> void:
	var dx0 := 0.3
	var dx1 := 1.15
	if lv <= 0:
		var d := _door(r, Vector3(dx0, 0, -D - 0.1), 0.0, dx1 - dx0, 0.0, "shed", Mats.m("wood", Color(1.15, 1.1, 1.05)), not decor_only, 1.0)
		d.name = "YardDoor"
		if not decor_only:
			_plot(r, -1.5, 3.5, -10.0, -6.0, Vector3(1.0, 0, -5.4), 0.0, "shed")
		return
	_door(r, Vector3(dx0, 0, -D - 0.1), 0.0, dx1 - dx0, 90.0, "shed", Mats.m("wood", Color(1.15, 1.1, 1.05)), false)
	var o := Vector3(1.0, 0, -8.0)
	var x0 := o.x - 2.5
	var x1 := o.x + 2.5
	var z0 := o.z - 2.0
	var z1 := o.z + 2.0
	var hh := 2.6
	var g := _node(r, Vector3.ZERO, 0.0, "Shed")
	var boards := Mats.m("wood_planks", Color(1.05, 1.15, 1.1), {"cell": Vector2(2.4, 0.18), "grime": 0.5})
	var outside := Mats.m("wood_planks", Color(0.75, 0.95, 0.88), {"cell": Vector2(2.4, 0.18), "grime": 0.6})
	_box(g, Vector3(x1 - x0 + 0.24, 0.16, z1 - z0 + 0.24), Vector3(o.x, -0.05, o.z), Mats.m("wood_planks", Color(1.0, 0.95, 0.9), {"cell": Vector2(1.2, 0.14)}), true, 0.0)
	_box(g, Vector3(x1 - x0 + 0.24, 0.08, z1 - z0 + 0.24), Vector3(o.x, hh + 0.04, o.z), Mats.m("plywood"), true, 0.0)
	# walls: door in the front (+Z, facing the garage), windows left and right
	_wall_x(g, x0 - 0.06, z0 - 0.12, z1 + 0.12, hh, [[o.z - 0.8, o.z + 0.8, 1.0, 1.8]], boards)
	_wall_x(g, x1 + 0.06, z0 - 0.12, z1 + 0.12, hh, [[o.z - 0.8, o.z + 0.8, 1.0, 1.8]], boards)
	_wall_z(g, z0 - 0.06, x0, x1, hh, [], boards)
	_wall_z(g, z1 + 0.06, x0, x1, hh, [[o.x - 0.45, o.x + 0.45, 0.0, DOOR_H]], boards)
	_panel(g, "x", x0 - 0.13, z0 - 0.14, z1 + 0.14, hh, [[o.z - 0.8, o.z + 0.8, 1.0, 1.8]], outside)
	_panel(g, "x", x1 + 0.13, z0 - 0.14, z1 + 0.14, hh, [[o.z - 0.8, o.z + 0.8, 1.0, 1.8]], outside)
	_panel(g, "z", z0 - 0.13, x0 - 0.14, x1 + 0.14, hh, [], outside)
	_panel(g, "z", z1 + 0.13, x0 - 0.14, x1 + 0.14, hh, [[o.x - 0.45, o.x + 0.45, 0.0, DOOR_H]], outside)
	if lv >= 3:
		# insulated white lining inside
		var lining := Mats.m("plaster", Color(1.25, 1.25, 1.22), {"grime": 0.2})
		_panel(g, "x", x0 + 0.055, z0, z1, hh, [[o.z - 0.8, o.z + 0.8, 1.0, 1.8]], lining)
		_panel(g, "x", x1 - 0.055, z0, z1, hh, [[o.z - 0.8, o.z + 0.8, 1.0, 1.8]], lining)
		_panel(g, "z", z0 + 0.055, x0, x1, hh, [], lining)
		_panel(g, "z", z1 - 0.055, x0, x1, hh, [[o.x - 0.45, o.x + 0.45, 0.0, DOOR_H]], lining)
	_window(g, Vector3(x0 - 0.06, 1.4, o.z), Vector2(1.6, 0.8), 90.0, Color(0.15, 0.22, 0.4))
	_window(g, Vector3(x1 + 0.06, 1.4, o.z), Vector2(1.6, 0.8), -90.0, Color(0.15, 0.22, 0.4))
	# pitched corrugated roof, ridge along X, overhang over the door
	for s in [-1.0, 1.0]:
		var rs := _box(g, Vector3(x1 - x0 + 0.6, 0.05, 2.45), Vector3(o.x, hh + 0.42, o.z + s * 1.1), Mats.m("rollup", Color(0.8, 0.85, 0.8), {"cell": Vector2(1.0, 0.15)}), false, 0.0)
		rs.rotation_degrees.x = s * 20.0
	for s in [-1.0, 1.0]:
		var gab := _box(g, Vector3(0.04, 0.6, 3.6), Vector3(o.x + s * (2.5 + 0.12), hh + 0.25, o.z), outside, false, 0.0)
		gab.scale = Vector3(1, 1, 1)
	# shed door: board-and-batten leaf open outward
	_door(r, Vector3(o.x - 0.45, 0, z1 + 0.06), 0.0, 0.9, -90.0, "shed", Mats.m("wood_planks", Color(0.7, 0.85, 0.8), {"cell": Vector2(0.15, 3.0)}), false)
	_label(g, "WORKSHOP", Vector3(o.x, 2.35, z1 + 0.19), 70, Color(0.95, 0.92, 0.85), Vector3.ZERO, 0.0018)
	# light: shadowed cold tube inside, warm lamp over the door outside
	_tube(g, Vector3(o.x - 0.6, hh - 0.08, o.z - 0.4), 0.0, true, Color(0.82, 0.95, 1.0), 3.4)
	var lamp := _node(g, Vector3(o.x + 0.75, 2.2, z1 + 0.2), 0.0, "PorchLamp")
	_box(lamp, Vector3(0.14, 0.18, 0.1), Vector3.ZERO, Mats.m("steel_dark"))
	_box(lamp, Vector3(0.1, 0.12, 0.02), Vector3(0, 0, 0.055), Mats.glow(Color(1.0, 0.72, 0.4), 6.0), false, 0.0)
	_omni(lamp, Vector3(0, -0.1, 0.35), Color(1.0, 0.7, 0.4), 1.0, 4.5, false, 1.1)
	_omni(g, Vector3(o.x + 1.2, 1.4, o.z + 0.6), Color(1.0, 0.75, 0.5), 0.35, 3.0)
	# a shelf of jigs high on the back wall (above the furnishing height)
	_box(g, Vector3(3.0, 0.03, 0.25), Vector3(o.x, 2.25, z0 + 0.14), Mats.m("plywood"), false, 0.004)
	for i in 8:
		_box(g, Vector3(0.22, 0.12, 0.18), Vector3(o.x - 1.35 + i * 0.38, 2.33, z0 + 0.14), Mats.m("plastic_white", [Color(0.95, 0.55, 0.1), Color(0.2, 0.45, 0.85)][i % 2]), false, 0.012)
	_label(g, "QC", Vector3(o.x + 1.6, 2.0, z0 + 0.01), 160, Color(0.95, 0.8, 0.2, 0.85), Vector3.ZERO, 0.002)
	if lv >= 2:
		# level 2: a second tube, a lean-to canopy on the right with pallets of returns
		_tube(g, Vector3(o.x + 0.9, hh - 0.08, o.z + 0.5), 0.0, false)
		var cn := _node(g, Vector3(x1 + 0.9, 0, o.z), 0.0, "Canopy")
		for z in [-1.4, 1.4]:
			_box(cn, Vector3(0.08, 2.0, 0.08), Vector3(0.8, 1.0, z), Mats.m("wood"), true, 0.008)
		_box(cn, Vector3(1.9, 0.04, 3.2), Vector3(0.0, 2.15, 0), Mats.m("rollup", Color(0.7, 0.75, 0.8)), false, 0.0, Vector3(0, 0, -8))
		for i in 2:
			_box(cn, Vector3(0.8, 0.12, 1.0), Vector3(0.1, 0.06, -0.6 + i * 1.2), Mats.m("plywood"), false, 0.008)
			_box(cn, Vector3(0.7, 0.5, 0.8), Vector3(0.1, 0.37, -0.6 + i * 1.2), Mats.m("cardboard"), false, 0.02)
		_label(cn, "RETURNS", Vector3(0.1, 0.4, -0.6 + 0.41), 50, Color(0.15, 0.1, 0.1), Vector3.ZERO, 0.0016)
	if lv >= 3:
		# level 3: insulated white interior (above), LED panels, AC box outside, lit sign
		for z in [o.z - 0.8, o.z + 0.8]:
			_box(g, Vector3(1.2, 0.02, 0.6), Vector3(o.x, hh - 0.012, z), Mats.glow(Color(0.9, 0.96, 1.0), 2.2), false, 0.0, Vector3.ZERO, false)
		_spot(g, Vector3(o.x, hh - 0.05, o.z), Vector3(o.x, 0, o.z + 0.001), Color(0.9, 0.96, 1.0), 1.4, 3.5, 80.0, false, 0.4)
		var ac := _node(g, Vector3(x0 - 0.45, 0.0, o.z + 1.0), 0.0, "AC")
		_box(ac, Vector3(0.5, 0.6, 0.8), Vector3(0, 0.3, 0), Mats.m("plastic_white", Color(1.1, 1.1, 1.1)), true, 0.02)
		_cyl(ac, 0.22, 0.02, Vector3(-0.26, 0.32, 0), Mats.m("steel_dark", Color.WHITE, {"pattern": 8, "cell": Vector2(0.03, 0.03)}), Vector3(0, 0, 90), 16)
		var sg := _node(g, Vector3(o.x, hh + 0.35, z1 + 0.32), 0.0, "Sign")
		_box(sg, Vector3(2.4, 0.36, 0.08), Vector3.ZERO, Mats.m("plastic_black"))
		_label(sg, "QUALITY CONTROL", Vector3(0, 0, 0.045), 90, Color(1.0, 0.85, 0.4) * 2.5, Vector3.ZERO, 0.0018, false)
		_omni(sg, Vector3(0, -0.3, 0.4), Color(1.0, 0.8, 0.4), 0.8, 3.0)

# ================================================================== showroom
func _showroom(r: Node3D, lv: int) -> void:
	var dx0 := 0.66
	var dx1 := 1.46
	if lv <= 0:
		_door(r, Vector3(dx1, 0, D + 0.1), 180.0, dx1 - dx0, 0.0, "showroom", Mats.m("plaster", Color(0.95, 0.95, 1.0)), not decor_only, 1.0)
		if not decor_only:
			_plot(r, 0.7, 3.9, 3.9, 7.6, Vector3(0.95, 0, 5.8), -90.0, "showroom")
		return
	_door(r, Vector3(dx1, 0, D + 0.1), 180.0, dx1 - dx0, 90.0, "showroom", Mats.m("plaster", Color(0.95, 0.95, 1.0)), false)
	var x0 := 0.6
	var x1 := 4.0
	var z0 := D + T
	var z1 := 7.7
	var hh := 2.8
	var g := _node(r, Vector3.ZERO, 0.0, "Showroom")
	var white := Mats.m("plaster", Color(1.3, 1.3, 1.28), {"grime": 0.15})
	_box(g, Vector3(x1 - x0 + 0.4, 0.2, z1 - z0 + 0.2), Vector3((x0 + x1) * 0.5 + 0.1, -0.1, (z0 + z1) * 0.5 + 0.1), Mats.m("floor_tiles", Color(1.35, 1.35, 1.35), {"roughness_base": 0.15, "cell": Vector2(0.6, 0.6)}), true, 0.0)
	_box(g, Vector3(x1 - x0 + 0.4, 0.12, z1 - z0 + 0.3), Vector3((x0 + x1) * 0.5 + 0.1, hh + 0.06, (z0 + z1) * 0.5 + 0.1), white, true, 0.0)
	_box(g, Vector3(x1 - x0 + 0.7, 0.2, z1 - z0 + 0.6), Vector3((x0 + x1) * 0.5 + 0.1, hh + 0.22, (z0 + z1) * 0.5 + 0.15), Mats.m("steel_dark"), false, 0.01)
	# right wall (x1) solid; street wall (z1) with a glass door and a display window; storefront glass on x0
	_wall_x(g, x1 + 0.1, z0, z1 + 0.2, hh, [], white)
	_wall_z(g, z1 + 0.1, x0, x1, hh, [[1.85, 2.75, 0.0, 2.1], [2.9, 3.9, 0.5, 2.3]], white)
	_box(g, Vector3(0.02, hh, z1 - z0 + 0.4), Vector3(x1 + 0.21, hh * 0.5, (z0 + z1) * 0.5 + 0.1), Mats.m("siding", Color(0.95, 0.95, 0.95)))
	_window(g, Vector3(3.4, 1.4, z1 + 0.1), Vector2(1.0, 1.8), 180.0, Color(0.25, 0.3, 0.5))
	# storefront: sill, mullions, glass, header; thick invisible pane
	var fx := x0 - 0.1
	_box(g, Vector3(0.2, 0.3, z1 - z0 + 0.2), Vector3(fx, 0.15, (z0 + z1) * 0.5 + 0.1), Mats.m("steel_dark"), true, 0.006)
	_box(g, Vector3(0.2, 0.3, z1 - z0 + 0.2), Vector3(fx, hh - 0.15, (z0 + z1) * 0.5 + 0.1), Mats.m("steel_dark"), true, 0.006)
	for i in 5:
		_box(g, Vector3(0.08, hh, 0.08), Vector3(fx, hh * 0.5, z0 + 0.04 + i * (z1 - z0 + 0.1) / 4.0), Mats.m("steel_dark"), false, 0.006)
	var gl := _box(g, Vector3(0.01, hh - 0.6, z1 - z0 + 0.2), Vector3(fx, hh * 0.5, (z0 + z1) * 0.5 + 0.1), Mats.glass(Color(0.6, 0.7, 0.75, 0.1)), false, 0.0)
	gl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shape(Vector3(0.25, hh, z1 - z0 + 0.3), Transform3D(Basis(), Vector3(fx, hh * 0.5, (z0 + z1) * 0.5 + 0.1)))
	# glass street door (closed; the shop is open: a neon OPEN sign)
	var sd := _node(g, Vector3(2.3, 0, z1 + 0.1), 0.0, "StreetDoor")
	_box(sd, Vector3(0.9, 2.1, 0.06), Vector3(0, 1.05, 0), Mats.glass(Color(0.6, 0.7, 0.75, 0.18)), true, 0.0)
	for s in [-1.0, 1.0]:
		_box(sd, Vector3(0.05, 2.1, 0.07), Vector3(s * 0.43, 1.05, 0), Mats.m("steel_dark"), false, 0.004)
	_box(sd, Vector3(0.6, 0.04, 0.05), Vector3(0, 1.05, -0.05), Mats.m("metal"), false, 0.006)
	_label(sd, "OPEN", Vector3(0, 1.6, -0.04), 90, Color(1.0, 0.3, 0.5) * 3.0, Vector3(0, 180, 0), 0.0018, false)
	# signage: name band over the street front + over the storefront
	var nm := str(Game.state.get("name", "")).to_upper()
	if nm == "":
		nm = "SHOWROOM"
	var logo: Dictionary = Game.state.get("logo", {}) if Game.state.get("logo") is Dictionary else {}
	var bc := Color.html(str(logo.colorA)) if str(logo.get("colorA", "")).is_valid_html_color() else Color(0.31, 0.55, 1.0)
	var band := _node(g, Vector3(2.3, hh + 0.22, z1 + 0.42), 0.0, "Band")
	_box(band, Vector3(x1 - x0, 0.4 if lv < 2 else 0.55, 0.06), Vector3.ZERO, Mats.m("plastic_black"))
	_label(band, nm + " STORE", Vector3(0, 0, 0.035), 80 if lv < 2 else 110, bc.lightened(0.3) * 2.6, Vector3.ZERO, 0.0018, false)
	var band2 := _node(g, Vector3(fx - 0.14, hh + 0.22, (z0 + z1) * 0.5), -90.0, "Band2")
	_box(band2, Vector3(z1 - z0, 0.36, 0.06), Vector3.ZERO, Mats.m("plastic_black"))
	_label(band2, nm, Vector3(0, 0, 0.035), 80, bc.lightened(0.3) * 2.2, Vector3.ZERO, 0.0018, false)
	_omni(g, Vector3(2.3, hh, z1 + 1.0), bc, 0.8, 3.5, false, 1.0)
	# light: track with warm-white spots (shadowed key on the middle), a cold wash from the street lamp side
	_box(g, Vector3(0.05, 0.04, z1 - z0 - 0.6), Vector3(2.3, hh - 0.03, (z0 + z1) * 0.5), Mats.m("plastic_black"), false, 0.004)
	for i in 3:
		var z := z0 + 0.8 + i * (z1 - z0 - 1.6) / 2.0
		var hd := _node(g, Vector3(2.3, hh - 0.12, z), 0.0)
		_cyl(hd, 0.05, 0.14, Vector3.ZERO, Mats.m("plastic_black"), Vector3(30, 0, 0), 12)
		_spot(hd, Vector3(0, -0.05, 0), Vector3(0.6 * (i - 1), -2.5, 0.4), Color(1.0, 0.88, 0.72), 2.4, 4.5, 40.0, i == 1, 0.6)
	_omni(g, Vector3(1.2, 1.6, (z0 + z1) * 0.5), Color(0.75, 0.82, 1.0), 0.4, 3.5)
	if lv >= 2:
		# level 2: awning over the street door + uplights along the storefront
		var aw := _node(g, Vector3(2.3, 2.45, z1 + 0.5), 0.0, "Awning")
		for i in 7:
			_box(aw, Vector3(0.24, 0.02, 0.9), Vector3(-0.72 + i * 0.24, 0, 0), Mats.m("fabric", Color.WHITE, {"albedo": bc if i % 2 == 0 else Color(0.9, 0.9, 0.88)}), false, 0.0, Vector3(25, 0, 0))
		for i in 3:
			var up := _node(g, Vector3(x0 + 0.2, 0.02, z0 + 0.7 + i * 1.3), 0.0)
			_cyl(up, 0.05, 0.03, Vector3.ZERO, Mats.glow(Color(1.0, 0.9, 0.75), 3.0), Vector3.ZERO, 10)
			_spot(up, Vector3(0, 0.05, 0), Vector3(-0.1, 2.0, 0), Color(1.0, 0.85, 0.7), 1.2, 3.0, 30.0, false, 0.8)
	if lv >= 3:
		# level 3: rooftop totem with the logo colour, red carpet to the street, crossing searchlights
		var tot := _node(g, Vector3(3.5, hh + 0.3, 6.6), 0.0, "Totem")
		_box(tot, Vector3(0.12, 1.4, 0.12), Vector3(0, 0.7, 0), Mats.m("steel_dark"))
		_box(tot, Vector3(1.1, 0.9, 0.18), Vector3(0, 1.7, 0), Mats.m("plastic_black"))
		_box(tot, Vector3(1.0, 0.8, 0.02), Vector3(0, 1.7, 0.1), Mats.glow(bc, 2.2), false, 0.0)
		_label(tot, nm.substr(0, 1), Vector3(0, 1.7, 0.115), 300, Color(1, 1, 1) * 2.0, Vector3.ZERO, 0.002, false)
		_omni(tot, Vector3(0, 1.7, 0.8), bc, 1.0, 5.0)
		_box(g, Vector3(0.9, 0.006, 1.6), Vector3(2.3, -0.015, z1 + 0.95), Mats.m("carpet", Color(2.6, 0.5, 0.45)), false, 0.0)
		for s in [-1.0, 1.0]:
			var sl := _node(g, Vector3(2.3 + s * 1.3, 0.0, z1 + 1.0), 0.0)
			_cyl(sl, 0.12, 0.25, Vector3(0, 0.12, 0), Mats.m("steel_dark"), Vector3.ZERO, 12)
			_spot(sl, Vector3(0, 0.3, 0), Vector3(-s * 4.0, 18.0, -3.0), Color(0.85, 0.9, 1.0), 4.0, 20.0, 6.0, false, 3.0)
