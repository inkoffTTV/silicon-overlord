extends RefCounted
## Parametric device model (port of shared-luau/World/DeviceModelBuilder.luau, phone first).
## build(params) -> Node3D. Sizes in "studs" like the Roblox version (a phone is ~1.5 units tall at scale 1).
## Orientation: screen faces +Z, back faces -Z, Y up. Every designer choice changes the model:
## size, corners, bezel, body colour/finish/material, accent frame, camera layout/bump/lens count/MP/OIS,
## selfie position, side buttons, port type/offset, panel tint, refresh strip, logo style, wallpaper, foldables.

const M := preload("res://phone/phone_mesh.gd")
const HomeScreen := preload("res://phone/home_screen.gd")
const GData := preload("res://ui/lib/gdata.gd")

const COLORWAYS := {
	"graphite": Color8(52, 54, 60), "silver": Color8(200, 203, 210), "midnight": Color8(28, 32, 48), "gold": Color8(214, 180, 120),
	"blue": Color8(60, 110, 200), "red": Color8(190, 55, 60), "green": Color8(70, 140, 95), "white": Color8(235, 236, 240),
	"purple": Color8(120, 80, 170), "black": Color8(20, 20, 24), "titanium": Color8(140, 140, 145), "orange": Color8(230, 130, 50),
}
const PANEL_TINT := {
	"TN": [Color8(90, 120, 170), 0.55], "VA": [Color8(50, 110, 200), 0.8], "IPS": [Color8(40, 130, 255), 0.9],
	"OLED": [Color8(20, 100, 255), 1.0], "LTPO": [Color8(15, 95, 255), 1.05], "FlexOLED": [Color8(30, 90, 250), 1.0],
	"MicroLED": [Color8(60, 160, 255), 1.15], "microOLED": [Color8(30, 100, 255), 1.0],
}
## material look: [metallic, roughness, clearcoat]
const MATERIAL_LOOK := {
	"plastic": [0.0, 0.55, 0.0], "polycarbonate": [0.0, 0.35, 0.3], "aluminum": [0.75, 0.32, 0.0], "glass": [0.1, 0.08, 1.0],
	"titanium": [0.8, 0.42, 0.0], "magnesium": [0.7, 0.45, 0.0], "carbon": [0.15, 0.4, 0.6], "steel": [0.85, 0.3, 0.0],
}
const FINISH_LOOK := {
	"classic": {}, "soft_matte": {"rough": 0.85, "metal": 0.0, "tint": 0.95}, "carbon_fibre": {"rough": 0.4, "tint": 0.6, "tex": "carbon"},
	"brushed_metal": {"metal": 0.85, "rough": 0.3, "tex": "brushed"}, "pearl_ceramic": {"metal": 0.0, "rough": 0.12, "lift": 0.25, "coat": 1.0},
	"iridescent": {"metal": 0.4, "rough": 0.15, "lift": 0.1, "coat": 1.0, "rim": true}, "blush_gold": {"metal": 0.8, "rough": 0.25, "lift": 0.15, "blush": true},
	"white_marble": {"metal": 0.0, "rough": 0.2, "lift": 0.5, "coat": 0.8}, "glacier": {"metal": 0.1, "rough": 0.1, "lift": 0.35, "coat": 1.0},
	"founder": {"metal": 0.9, "rough": 0.2, "lift": 0.05, "founder": true},
}

static var _tex_cache := {}

# ================================================================ params
static func _hex(v: Variant) -> Variant:
	if v is String and (v as String).length() == 7 and (v as String).begins_with("#"):
		return Color(v)
	return null

static func _charger_kind(c: Dictionary) -> String:
	if c.is_empty():
		return "usbc"
	if c.get("wireless", false) and float(c.get("wattage", 0)) >= 120:
		return "none"
	var w := float(c.get("wattage", 10))
	if w <= 10:
		return "mini"
	if w <= 25:
		return "micro"
	return "usbc"

## resolve: Callable(id: String) -> Dictionary (catalog / custom components)
static func params_from_blueprint(bp: Dictionary, resolve: Callable, brand: Dictionary = {}) -> Dictionary:
	var slots: Dictionary = bp.get("slots", {}) if bp.get("slots") is Dictionary else {}
	var opt: Dictionary = bp.get("options", {}) if bp.get("options") is Dictionary else {}
	var get_c := func(slot: String) -> Dictionary:
		if slots.has(slot):
			var c: Variant = resolve.call(str(slots[slot]))
			return c if c is Dictionary else {}
		return {}
	var chassis: Dictionary = get_c.call("Chassis")
	var display: Dictionary = get_c.call("Display")
	var camera: Dictionary = get_c.call("Camera")
	var charger: Dictionary = get_c.call("Charger")
	var battery: Dictionary = get_c.call("Battery")
	var p := {
		"category": bp.get("category", "Smartphone"), "subtype": bp.get("subtype", "MidrangePhone"), "colorway": opt.get("colorway", "graphite"),
		"material": chassis.get("material", "aluminum"), "screenInch": float(display.get("sizeInch", 6.1)) if not display.is_empty() else 6.1,
		"lenses": int(camera.get("lenses", 2)) if not camera.is_empty() else 1, "foldable": display.get("foldable", false) == true,
		"glassBack": chassis.get("material", "") == "glass", "name": bp.get("name", ""),
		"cameraLayout": opt.get("cameraLayout", "topLeft"), "bumpShape": opt.get("bumpShape", "circle"), "selfiePosition": opt.get("selfiePosition", "centre"),
		"cornerRadius": float(opt.get("cornerRadius", 0.5)), "bezelInch": float(opt.get("bezelInch", 0.3)), "buttonSide": opt.get("buttonSide", "right"),
		"buttonHeight": float(opt.get("buttonHeight", 0.6)), "portOffset": float(opt.get("portOffset", 0.0)), "bodyColor": _hex(opt.get("bodyColorHex")),
		"finish": opt.get("finish", "classic"), "logoStyle": opt.get("logoStyle", "ring"),
		"displayPanel": display.get("panel", "IPS"), "refreshHz": float(display.get("refreshHz", 60)) if not display.is_empty() else 60.0,
		"cameraMP": float(camera.get("mainMP", 12)) if not camera.is_empty() else 8.0, "ois": camera.get("ois", false) == true,
		"cameraSensorInch": float(camera.get("sensorSizeInch", 0.43)) if not camera.is_empty() else 0.43, "cameraGen": int(camera.get("generation", 1)) if not camera.is_empty() else 1,
		"chargerKind": _charger_kind(charger), "wireless": charger.get("wireless", false) == true,
		"batteryWh": float(battery.get("capacityWh", 12)) if not battery.is_empty() else 12.0, "thicknessMm": float(chassis.get("thicknessMm", 8.5)) if not chassis.is_empty() else 8.5,
		"companyInitial": brand.get("initial", ""), "companyName": brand.get("name", ""),
		"brandA": _hex(brand.get("colorA", "")), "brandB": _hex(brand.get("colorB", "")),
	}
	var acc := GData.finish_item("accentColors", str(opt.get("accentColor", "auto")))
	if acc.has("hex"):
		p["accentColor"] = Color(acc.hex)
	var light := GData.finish_item("lightColors", str(opt.get("lightColor", "auto")))
	if light.has("hex"):
		p["lightColor"] = Color(light.hex)
	var wp := GData.finish_item("wallpapers", str(opt.get("wallpaper", "auto")))
	if wp.has("a") and wp.has("b"):
		p["wallpaper"] = [Color(wp.a), Color(wp.b)]
	return p

# ================================================================ materials
static func _mat(col: Color, metal: float = 0.0, rough: float = 0.5, coat: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = metal
	m.roughness = rough
	m.metallic_specular = 0.55
	if coat > 0:
		m.clearcoat_enabled = true
		m.clearcoat = coat
		m.clearcoat_roughness = 0.08
	return m

static func _emissive(col: Color, energy: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.BLACK
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	m.roughness = 0.2
	return m

static func _texture(kind: String) -> Texture2D:
	if _tex_cache.has(kind):
		return _tex_cache[kind]
	var img := Image.create(128, 128, true, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for y in 128:
		var row := rng.randf_range(0.82, 1.0)
		for x in 128:
			var v := 1.0
			if kind == "carbon":
				var cx := int(x / 8)
				var cy := int(y / 8)
				var along := (x % 8) if (cx + cy) % 2 == 0 else (y % 8)
				v = 0.55 + 0.45 * sin(float(along) / 8.0 * PI)
			else:
				v = row * rng.randf_range(0.94, 1.0)
			img.set_pixel(x, y, Color(v, v, v))
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_tex_cache[kind] = t
	return t

static func darken(c: Color, k: float) -> Color:
	return Color(c.r * k, c.g * k, c.b * k, c.a)

static func body_look(p: Dictionary) -> Dictionary:
	var col: Color = p.bodyColor if p.get("bodyColor") is Color else COLORWAYS.get(p.get("colorway", "graphite"), COLORWAYS.graphite)
	var look: Array = MATERIAL_LOOK.get(p.get("material", "aluminum"), MATERIAL_LOOK.aluminum)
	var metal: float = look[0]
	var rough: float = look[1]
	var coat: float = look[2]
	var tex := ""
	if p.get("material", "") == "titanium":
		col = darken(col, 0.85)
	if p.get("material", "") == "carbon":
		tex = "carbon"
	if p.get("material", "") in ["aluminum", "titanium"]:
		tex = "brushed"
	var fl: Dictionary = FINISH_LOOK.get(p.get("finish", "classic"), {})
	metal = fl.get("metal", metal)
	rough = fl.get("rough", rough)
	coat = fl.get("coat", coat)
	tex = fl.get("tex", tex)
	if fl.has("tint"):
		col = darken(col, fl.tint)
	if fl.has("lift"):
		col = col.lerp(Color.WHITE, fl.lift)
	if fl.get("blush", false):
		col = col.lerp(Color8(220, 170, 150), 0.5)
	if fl.get("founder", false):
		col = col.lerp(Color8(240, 200, 90), 0.4)
	var m := _mat(col, metal, rough, coat)
	if tex != "":
		m.roughness_texture = _texture(tex)
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		if tex == "carbon":
			m.albedo_texture = _texture(tex)
			m.uv1_scale = Vector3(3, 3, 1)
	if fl.get("rim", false):
		m.rim_enabled = true
		m.rim = 0.8
		m.rim_tint = 0.9
	return {"color": col, "material": m}

static func screen_colors(p: Dictionary) -> Array:
	if p.get("wallpaper") is Array:
		return p.wallpaper
	var t: Array = PANEL_TINT.get(p.get("displayPanel", "IPS"), PANEL_TINT.IPS)
	var c: Color = t[0]
	var a: Color = p.brandA if p.get("brandA") is Color else c.darkened(0.35)
	var b: Color = p.brandB if p.get("brandB") is Color else c.lightened(0.15)
	if p.get("brandA") is Color:
		a = a.lerp(c, 0.25).darkened(0.25)
		b = b.lerp(c, 0.2)
	return [a, b]

# ================================================================ build
static func build(p: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Device"
	var cat: String = p.get("category", "Smartphone")
	if cat == "Smartphone" or cat == "Wearable" and p.get("subtype", "") == "Smartwatch":
		if p.get("foldable", false):
			_foldable(root, p)
		else:
			_phone(root, p)
	elif cat == "Laptop":
		_laptop(root, p)
	else:
		_box_device(root, p)
	return root

static func extents(p: Dictionary) -> Vector3:
	var k: float = float(p.get("screenInch", 6.4)) / 6.4
	match str(p.get("category", "Smartphone")):
		"Smartphone":
			if p.get("foldable", false):
				return Vector3(1.45 * k, 1.5 * k, 0.16)
			return Vector3(0.76 * k, 1.52 * k, 0.2)
		"Laptop":
			return Vector3(2.2, 1.5, 1.6)
	return Vector3(1.4, 1.2, 1.2)

static func _mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, nm: String = "", rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	if nm != "":
		mi.name = nm
	parent.add_child(mi)
	return mi

static func _dims(p: Dictionary) -> Vector3:
	var inch: float = float(p.get("screenInch", 6.4))
	var k := inch / 6.4
	var d := clampf(float(p.get("thicknessMm", 8.5)) / 8.5 * 0.08, 0.055, 0.12)
	return Vector3(0.72 * k, 1.5 * k, d)

static func _phone(root: Node3D, p: Dictionary) -> void:
	var dims := _dims(p)
	_phone_body(root, p, dims.x, dims.y, dims.z, Vector3.ZERO, true)

static func _phone_body(root: Node3D, p: Dictionary, w: float, h: float, d: float, origin: Vector3, with_back: bool) -> void:
	var look := body_look(p)
	var body_col: Color = look.color
	var radius := (0.04 + 0.16 * float(p.get("cornerRadius", 0.5)))
	radius = minf(radius, w * 0.45)
	var frame_col: Color = p.accentColor if p.get("accentColor") is Color else darken(body_col, 0.78).lerp(Color(0.5, 0.52, 0.56), 0.15)
	var frame_mat := _mat(frame_col, 0.9, 0.28)
	# frame (the whole bevelled body)
	_mesh(root, M.slab(w, h, d, radius, d * 0.32, 10), frame_mat, origin, "Frame")
	# back panel
	var inset := 0.012
	if with_back:
		var back := _mesh(root, M.slab(w - inset * 2, h - inset * 2, 0.012, radius - inset, 0.005, 10, false, true), look.material, origin + Vector3(0, 0, -d / 2 + 0.003), "Back")
		back.rotation = Vector3.ZERO
	# front glass + screen
	var glass := _mat(Color(0.012, 0.013, 0.018), 0.0, 0.06, 1.0)
	_mesh(root, M.slab(w - 0.008, h - 0.008, 0.01, radius - 0.004, 0.004, 10, true, false), glass, origin + Vector3(0, 0, d / 2 - 0.002), "FrontGlass")
	var inch: float = float(p.get("screenInch", 6.4))
	var bezel_frac := clampf(float(p.get("bezelInch", 0.3)) / inch * 0.7, 0.015, 0.12)
	var sw := w * (0.965 - 2 * bezel_frac)
	var sh := h * (0.978 - 2 * bezel_frac)
	var sr := maxf(radius - w * bezel_frac * 1.2, 0.012)
	var screen := _mesh(root, M.plate(sw, sh, sr, 10), _screen_material(root, p, sw, sh), origin + Vector3(0, 0, d / 2 + 0.0045), "Screen")
	screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_front_details(root, p, w, h, d, origin, frame_col)
	if with_back:
		_camera_island(root, p, w, h, d, origin, body_col)
		_brand_mark(root, p, w, h, d, origin, body_col)
		_port(root, p, w, h, d, origin)

static func _screen_material(root: Node3D, p: Dictionary, sw: float, sh: float) -> StandardMaterial3D:
	var hs := HomeScreen.new()
	hs.name = "HomeScreen"
	var cols := screen_colors(p)
	hs.wall_a = cols[0]
	hs.wall_b = cols[1]
	hs.accent = p.brandA if p.get("brandA") is Color else Color("#4F8CFF")
	hs.brand_initial = str(p.get("companyInitial", ""))
	hs.high_refresh = float(p.get("refreshHz", 60)) >= 90
	hs.on = p.get("screenOn", true)
	root.add_child(hs)
	var px_w := 360
	hs.setup(Vector2i(px_w, int(px_w * sh / sw)))
	var t: Array = PANEL_TINT.get(p.get("displayPanel", "IPS"), PANEL_TINT.IPS)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.02, 0.02, 0.025)
	m.emission_enabled = true
	m.emission_texture = hs.get_texture()
	m.emission = Color.WHITE
	m.emission_energy_multiplier = 0.95 * float(t[1])
	m.roughness = 0.05
	m.metallic_specular = 0.8
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m

static func _front_details(root: Node3D, p: Dictionary, w: float, h: float, d: float, o: Vector3, frame_col: Color) -> void:
	var black := _mat(Color(0.01, 0.01, 0.015), 0.2, 0.25)
	var sx := 0.0
	match str(p.get("selfiePosition", "centre")):
		"left":
			sx = -w * 0.3
		"right":
			sx = w * 0.3
	_mesh(root, M.disc(0.024, 0.006, 24), black, o + Vector3(sx, h * 0.44, d / 2 + 0.006), "Selfie")
	var lens_dot := _mat(Color(0.1, 0.12, 0.25), 0.4, 0.05)
	_mesh(root, M.disc(0.009, 0.004, 16), lens_dot, o + Vector3(sx + 0.004, h * 0.44 + 0.004, d / 2 + 0.0085), "SelfieLens")
	_mesh(root, M.slab(0.16, 0.012, 0.004, 0.006, 0.001, 4), _mat(Color(0.06, 0.06, 0.07), 0.5, 0.5), o + Vector3(0, h / 2 - 0.022, d / 2 + 0.003), "Earpiece")
	# side buttons
	var side := -1.0 if p.get("buttonSide", "right") == "left" else 1.0
	var by := (-0.25 + 0.6 * float(p.get("buttonHeight", 0.6))) * h
	var btn_col: Color = (p.accentColor if p.get("accentColor") is Color else frame_col).lightened(0.12)
	var btn_mat := _mat(btn_col, 0.9, 0.3)
	_mesh(root, M.slab(0.03, 0.16, d * 0.42, 0.012, 0.006, 4), btn_mat, o + Vector3(side * (w / 2 + 0.004), by, 0), "PowerButton", Vector3(0, PI / 2, 0))
	_mesh(root, M.slab(0.03, 0.26, d * 0.42, 0.012, 0.006, 4), btn_mat, o + Vector3(side * (w / 2 + 0.004), by + 0.27, 0), "VolumeButton", Vector3(0, PI / 2, 0))

static func _port(root: Node3D, p: Dictionary, w: float, h: float, d: float, o: Vector3) -> void:
	var kind: String = p.get("chargerKind", "usbc")
	var dark := _mat(Color(0.015, 0.015, 0.02), 0.3, 0.5)
	var x := float(p.get("portOffset", 0.0)) * w * 0.3
	var size := Vector2(0.09, 0.028)
	var rr := 0.014
	match kind:
		"mini":
			size = Vector2(0.11, 0.04)
			rr = 0.004
		"micro":
			size = Vector2(0.07, 0.022)
			rr = 0.005
		"none":
			size = Vector2.ZERO
	if size.x > 0:
		_mesh(root, M.slab(size.x, size.y, 0.012, rr, 0.002, 4), dark, o + Vector3(x, -h / 2 + 0.002, 0), "Port", Vector3(PI / 2, 0, 0))
	for i in 3:
		var hx := x + size.x / 2 + 0.04 + i * 0.03
		var hole := _mesh(root, M.disc(0.007, 0.01, 12), dark, o + Vector3(hx, -h / 2 + 0.002, 0), "SpeakerHole", Vector3(PI / 2, 0, 0))
		hole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

static func _island_origin(layout: String, w: float, h: float) -> Vector2:
	# seen from the back the viewer's left is +X
	var x := w * 0.27
	var y := h * 0.34
	match layout:
		"topMiddle":
			x = 0.0
		"topRight":
			x = -w * 0.27
		"centre":
			x = 0.0
			y = h * 0.12
	return Vector2(x, y)

static func _camera_island(root: Node3D, p: Dictionary, w: float, h: float, d: float, o: Vector3, body_col: Color) -> void:
	var n := clampi(int(p.get("lenses", 2)), 1, 4)
	var mp := float(p.get("cameraMP", 12))
	var main_d := (0.09 + 0.07 * clampf((mp - 8) / 192.0, 0, 1)) * (0.85 + 0.4 * clampf((float(p.get("cameraSensorInch", 0.43)) - 0.3) / 0.7, 0, 1))
	var shape: String = p.get("bumpShape", "circle")
	var iw := 0.26 if n <= 2 else 0.44
	var ih := 0.26 if n == 1 else 0.44
	if shape == "pill":
		iw = 0.22 if n <= 2 else 0.24
		ih = 0.2 + 0.18 * n
	elif shape == "bar":
		iw = w * 0.86
		ih = 0.22
	var org2 := _island_origin(p.get("cameraLayout", "topLeft"), w, h)
	if shape == "bar":
		org2.x = 0
	var back_z := o.z - d / 2
	var island_col := darken(body_col, 0.72).lerp(Color(0.12, 0.12, 0.14), 0.35)
	var island_mat := _mat(island_col, 0.7, 0.25, 0.5)
	var lens_z := back_z - 0.012
	if shape != "none":
		var mesh: Mesh
		var depth := 0.05
		match shape:
			"circle":
				var r := maxf(iw, ih) / 2
				mesh = M.slab(r * 2, r * 2, depth, r, depth * 0.35, 10)
			"square":
				mesh = M.slab(iw, ih, depth, 0.07, depth * 0.35, 8)
			"pill":
				mesh = M.slab(iw, ih, depth, iw / 2 - 0.001, depth * 0.35, 10)
			_:
				mesh = M.slab(iw, ih, depth, ih / 2 - 0.001, depth * 0.35, 10)
		_mesh(root, mesh, island_mat, Vector3(o.x + org2.x, o.y + org2.y, back_z - depth / 2 + 0.012), "CameraIsland")
		lens_z = back_z - depth + 0.012
	var positions := []
	var sp := 0.1
	if shape == "bar":
		for i in n:
			positions.append(Vector2((i - (n - 1) / 2.0) * 0.15, 0))
	elif shape == "pill":
		for i in n:
			positions.append(Vector2(0, ((n - 1) / 2.0 - i) * 0.17))
	elif n == 1:
		positions = [Vector2.ZERO]
	elif n == 2:
		positions = [Vector2(0, sp), Vector2(0, -sp)]
	elif n == 3:
		positions = [Vector2(sp, sp), Vector2(-sp, sp), Vector2(sp, -sp)]
	else:
		positions = [Vector2(sp, sp), Vector2(-sp, sp), Vector2(sp, -sp), Vector2(-sp, -sp)]
	var ring_mat := _mat(Color(0.16, 0.17, 0.2), 0.9, 0.22)
	var glass_mat := _mat(Color(0.015, 0.02, 0.05), 0.5, 0.04, 1.0)
	var gen := clampi(int(p.get("cameraGen", 1)), 1, 7)
	var hl := _emissive(Color8(215 - gen * 15, 225 - gen * 8, 255), 1.2)
	for i in positions.size():
		var dd: float = main_d if i == 0 else main_d * 0.75
		var c := Vector3(o.x + org2.x + positions[i].x, o.y + org2.y + positions[i].y, lens_z)
		var flip := Vector3(0, PI, 0)
		_mesh(root, M.disc(dd * 0.65, 0.03, 32), ring_mat, c - Vector3(0, 0, 0.008), "LensRing", flip)
		if i == 0 and p.get("ois", false):
			_mesh(root, M.ring(dd * 0.53, 0.006, 32, 6), _mat(Color(0.55, 0.57, 0.65), 0.9, 0.2), c - Vector3(0, 0, 0.024), "OisRing", flip)
		_mesh(root, M.disc(dd * 0.45, 0.02, 32), glass_mat, c - Vector3(0, 0, 0.012), "Lens", flip)
		var dot := _mesh(root, M.disc(dd * 0.07, 0.004, 12), hl, c + Vector3(-dd * 0.16, dd * 0.16, -0.0235), "LensHighlight", flip)
		dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# flash
	var flash_off := Vector2(-0.1, 0) if n < 3 else Vector2(-sp, -sp)
	if shape == "bar":
		flash_off = Vector2(-iw / 2 + 0.06, 0)
	elif shape == "pill":
		flash_off = Vector2(0, -ih / 2 - 0.06)
	if n == 4 and shape != "bar" and shape != "pill":
		flash_off = Vector2(0, -0.2)
	var light_col: Color = p.lightColor if p.get("lightColor") is Color else Color8(255, 236, 200)
	var fl := _mesh(root, M.disc(0.022, 0.008, 16), _emissive(light_col, 0.9),
		Vector3(o.x + org2.x + flash_off.x, o.y + org2.y + flash_off.y, lens_z - 0.004), "Flash", Vector3(0, PI, 0))
	fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

static func _brand_mark(root: Node3D, p: Dictionary, w: float, h: float, d: float, o: Vector3, body_col: Color) -> void:
	var style: String = p.get("logoStyle", "ring")
	if style == "none":
		return
	var lum := body_col.get_luminance()
	var mark_col: Color = p.accentColor if p.get("accentColor") is Color else (Color(0.12, 0.12, 0.14) if lum > 0.55 else Color(0.82, 0.84, 0.9))
	var light_col: Color = p.lightColor if p.get("lightColor") is Color else (p.brandA if p.get("brandA") is Color else mark_col)
	var z := o.z - d / 2 - 0.007
	var center := Vector3(o.x, o.y - h * 0.05, z)
	var initial := str(p.get("companyInitial", ""))
	var mark_mat := _mat(mark_col, 0.9, 0.2)
	match style:
		"ring":
			_mesh(root, M.ring(0.085, 0.007, 40, 6), mark_mat, center, "LogoRing")
		"badge":
			_mesh(root, M.slab(0.15, 0.15, 0.006, 0.04, 0.002, 6), mark_mat, center, "LogoBadge")
		"stripe":
			_mesh(root, M.slab(0.03, h * 0.7, 0.004, 0.012, 0.001, 4), _emissive(light_col, 0.6), Vector3(o.x, o.y, z), "LogoStripe")
			return
	var text := initial if style != "wordmark" else str(p.get("companyName", initial)).to_upper()
	if text == "":
		return
	var l := Label3D.new()
	l.name = "LogoText"
	l.text = text
	l.font = load("res://ui/fonts/InterDisplay-Bold.ttf")
	l.font_size = 64 if style != "wordmark" else 40
	l.pixel_size = 0.0016 if style != "wordmark" else 0.0011
	l.modulate = mark_col if style != "badge" else (Color.WHITE if lum < 0.5 else Color(0.1, 0.1, 0.12))
	l.outline_size = 0
	l.position = center + Vector3(0, 0, -0.004)
	l.rotation = Vector3(0, PI, 0)
	l.double_sided = false
	l.shaded = true
	l.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	root.add_child(l)

static func _foldable(root: Node3D, p: Dictionary) -> void:
	var dims := _dims(p)
	var half := dims.x * 0.95
	var tilt := deg_to_rad(9.0)
	var left := Node3D.new()
	left.position = Vector3(-half / 2 - 0.015, 0, 0)
	left.rotation.y = tilt
	root.add_child(left)
	var right := Node3D.new()
	right.position = Vector3(half / 2 + 0.015, 0, 0)
	right.rotation.y = -tilt
	root.add_child(right)
	var p2 := p.duplicate()
	_phone_body(right, p2, half, dims.y, dims.z, Vector3.ZERO, true)
	p2["companyInitial"] = ""
	p2["bumpShape"] = "none"
	_phone_body(left, p2, half, dims.y, dims.z, Vector3.ZERO, false)
	for c in left.get_children():
		if c.name in ["Selfie", "SelfieLens", "Earpiece", "PowerButton", "VolumeButton"]:
			c.queue_free()
	var hinge_col: Color = p.accentColor if p.get("accentColor") is Color else Color(0.4, 0.41, 0.45)
	var cyl := CylinderMesh.new()
	cyl.top_radius = dims.z * 0.62
	cyl.bottom_radius = dims.z * 0.62
	cyl.height = dims.y * 0.96
	_mesh(root, cyl, _mat(hinge_col, 0.9, 0.25), Vector3(0, 0, -0.01), "Hinge")

static func _laptop(root: Node3D, p: Dictionary) -> void:
	var look := body_look(p)
	var base_mat: Material = look.material
	var k := float(p.get("screenInch", 14)) / 14.0
	var w := 2.0 * k
	var dpt := 1.35 * k
	var base := _mesh(root, M.slab(w, dpt, 0.07, 0.06, 0.02, 8), base_mat, Vector3(0, -0.5, 0), "Base", Vector3(-PI / 2, 0, 0))
	base.position = Vector3(0, -0.55, 0.2)
	var deck := _mat(darken(look.color, 0.6), 0.3, 0.6)
	_mesh(root, M.plate(w * 0.8, dpt * 0.42, 0.02, 4), deck, Vector3(0, -0.514, 0.05), "Keyboard", Vector3(-PI / 2, 0, 0))
	var lid := Node3D.new()
	lid.position = Vector3(0, -0.52, -0.47 * k)
	lid.rotation.x = deg_to_rad(-12)
	root.add_child(lid)
	_mesh(lid, M.slab(w, dpt * 0.95, 0.05, 0.06, 0.015, 8), base_mat, Vector3(0, dpt * 0.47, 0), "Lid")
	var sw := w * 0.9
	var sh := dpt * 0.82
	_mesh(lid, M.plate(sw, sh, 0.02, 6), _screen_material(lid, p, sw, sh), Vector3(0, dpt * 0.48, 0.027), "Screen")

static func _box_device(root: Node3D, p: Dictionary) -> void:
	var look := body_look(p)
	var sub: String = p.get("subtype", "")
	var size := Vector3(0.9, 1.6, 1.6)
	if p.get("category", "") == "Console":
		size = Vector3(1.6, 0.36, 1.4) if sub != "HandheldConsole" else Vector3(1.9, 0.8, 0.3)
	elif p.get("category", "") == "Wearable":
		size = Vector3(0.8, 0.8, 0.8)
	var mesh := M.slab(size.x, size.y, size.z, minf(size.x, size.y) * 0.12, 0.03, 8)
	_mesh(root, mesh, look.material, Vector3.ZERO, "Body")
	var accent: Color = p.lightColor if p.get("lightColor") is Color else (p.brandA if p.get("brandA") is Color else Color("#4F8CFF"))
	_mesh(root, M.slab(size.x * 0.7, 0.02, 0.01, 0.01, 0.002, 4), _emissive(accent, 2.0), Vector3(0, -size.y * 0.3, size.z / 2 + 0.004), "LightStrip")
