extends Node3D
## The garage as a PHONE REPAIR shop (WORLD agent, iteration 3). Driven by Game.state.story / Game.state.repairs
## (docs/STORY.md "Client contract", helpers in story_state.gd). Lives in the garage level (level_1_garage._live()).
##
## Builds (level space, the node sits at the level origin):
##   outside sign  — neon "PHONE REPAIR" on the gable over the roll-up door (one letter buzzes); after the story a
##                   backlit company lightbox (name + logo shape in the company colours). set_sign_override() for the
##                   title screen / cutscenes.
##   shop door     — the roll-up door, closed in chapter 0 until opened: interactable `shop_door` ("Open the shop").
##   light switch  — chunky wall switch by the door with a pilot lamp: `light_switch`; chapter 0 starts dark.
##   counter       — glass display counter with a service bell (grabbable, it dings), drop-off tray, price stand,
##                   hanging lightbox sign; interactable `counter` (id = orderId of the device lying there / the next
##                   order to take or return). After the story: reception (logo plaque, product stand, plant).
##   repair bench  — right wall: ESD mat + phone holder, magnifier lamp, soldering station, tools, parts bins that show
##                   inventory.resources repair_screen / repair_battery / repair_port; interactable `repair_bench`
##                   (seat: the player sits on the stool looking at the device, then Bus.interact fires).
##   gadget shelf  — rack of broken gadgets with tickets.
##   customers     — one NPC per live order (customer_npc.gd): walk in from the street, hand the device over, wait,
##                   react when it is fixed, take it back when paid and leave (angry if the order vanishes unpaid).
##   devices       — one grabbable broken_device.gd per order (tagged with orderId), carried counter -> bench -> counter.
## The world never decides outcomes: door / lights call Net.act("storyEvent"); take / repair / return are the UI's
## (Bus.interact("counter" | "repair_bench", orderId)).

const Mats := preload("res://world/lib/mats.gd")
const Meshes := preload("res://world/lib/meshes.gd")
const HQ := preload("res://world/live/hq_state.gd")
const Story := preload("res://world/live/story_state.gd")
const Device := preload("res://world/live/broken_device.gd")
const Customer := preload("res://world/actors/customer_npc.gd")
const Kit := preload("res://world/lib/kit.gd")

const D := 3.5          # garage half depth (front wall inner face at z = D)
const W := 4.0
const C_POS := Vector3(-0.9, 0, 1.1)        # counter (front faces +Z, the door)
const C_TOP := 1.02
const B_POS := Vector3(3.62, 0, -1.15)      # repair bench, rot -90 (front faces -X)
const B_TOP := 0.92
const S_POS := Vector3(3.78, 0, 0.3)        # broken gadget shelf, rot -90
const SWITCH_POS := Vector3(0.95, 1.32, D - 0.005)
const SIGN_POS := Vector3(-1.5, 3.44, D + 0.27)   # outside, on the gable over the roll-up door
const HOUSE_SPAWN := Vector3(2.85, 0.05, -2.75)
const COUNTER_SPOT := Vector3(-0.85, 0, 1.78)
const QUEUE_SPOT := Vector3(-0.3, 0, 2.6)
const WAIT_SPOTS := [[Vector3(-2.2, 0, 1.95), 140.0], [Vector3(0.3, 0, 2.45), 215.0], [Vector3(-1.6, 0, 2.75), 168.0], [Vector3(1.05, 0, 1.95), 240.0]]
const DOOR_LANE_X := 0.25
const NEON := Color(1.0, 0.28, 0.62)
const NEON_2 := Color(0.25, 0.85, 1.0)

var level: Node3D
var kit: Kit                  # level kit
var decor_only := false       # title screen: no state, no interactables, no Bus
var look := ""                # "repair" | "company"

var counter_ia: StaticBody3D
var bench_ia: StaticBody3D
var door_ia: StaticBody3D
var switch_ia: StaticBody3D
var holder: Node3D
var bell: RigidBody3D
var devices := {}             # orderId -> Device
var customers := {}           # orderId -> Customer
var last_status := {}         # orderId -> status

var _sign_root: Node3D
var _sign_letters: Array = []
var _sign_lights: Array = []
var _sign_mats: Array = []
var _buzz_letter := -1
var _sign_lit := true
var _sign_style := ""
var _sign_key := ""
var _override := {}           # {text, color, color2, style}
var _hang_root: Node3D
var _hang_key := ""
var _repair_dress: Node3D
var _reception: Node3D
var _reception_key := ""
var _curtain: Node3D
var _curtain_shape: CollisionShape3D
var _door_open := true
var _lever: Node3D
var _pilot_mat: StandardMaterial3D
var _pilot_light: OmniLight3D
var _lights_on := true
var _local_lights: Variant = null    # local toggle override (bool) or null
var _local_door := false
var _dark_cache := {}
var _bins := {}               # resource id -> {label, parts:Array}
var _poll := 0.0
var _t := 0.0
var _next_spot := 0
var _first_sync := true
var _spawned_key := ""
var _bell_held := false
var _sent_events := {}

func _ready() -> void:
	name = "RepairShop"
	if kit == null and level:
		kit = level.get("kit")
	_build_sign_mount()
	_build_curtain()
	_build_switch()
	_build_counter()
	_build_hanging_sign()
	_build_bench()
	_build_gadget_shelf()
	if decor_only:
		look = "repair"
		_apply_look(true)
		set_door_open(true, false)
		return
	Bus.state_changed.connect(_on_state)
	Bus.interact.connect(_on_interact)
	refresh.call_deferred()

func _on_state(keys: Array) -> void:
	# a full snapshot (join / resume / reconnect): orders already in the shop appear in place, no walk-in
	if keys.size() > 6 and keys.has("story"):
		_first_sync = true
	for k in ["story", "repairs", "name", "logo", "inventory", "products", "hq"]:
		if keys.has(k):
			refresh()
			return

# ================================================================== state
func refresh() -> void:
	if decor_only or not is_inside_tree():
		return
	var s: Dictionary = Game.state
	_apply_look(Story.repair_look(s))
	set_door_open(Story.door_open(s) or _local_door, not _first_sync)
	var want_lights: bool = Story.lights_on(s)
	if _local_lights != null and (want_lights or Story.chapter(s) > 0 or _local_lights == true):
		want_lights = bool(_local_lights)
	set_lights(want_lights, not _first_sync)
	var dock: Node3D = level.get("dock") if level else null
	if dock:
		var vis := Story.van_visible(s)
		dock.visible = vis
		dock.process_mode = Node.PROCESS_MODE_INHERIT if vis else Node.PROCESS_MODE_DISABLED
	_update_bins(s)
	_sync_orders(s)
	_story_spawn(s)
	_first_sync = false

## Chapter 0 (dark garage, door shut): the friends come in from the house — put the local player by the house door
## once per company.
func _story_spawn(s: Dictionary) -> void:
	if not Story.active(s) or Story.chapter(s) != 0 or Story.door_open(s) or Story.lights_on(s):
		return
	var key := str(Game.code) + "|" + str(s.get("name", ""))
	if key == _spawned_key:
		return
	_spawned_key = key
	var xf := Transform3D(Basis(Vector3.UP, PI), HOUSE_SPAWN)
	if level:
		level.set("spawn_xform", xf)
	for p in get_tree().get_nodes_in_group("local_player"):
		if p is Node3D and p.get("seated") != true:
			p.global_position = level.global_transform * HOUSE_SPAWN if level else HOUSE_SPAWN
			if p.has_method("set_look"):
				p.set_look(PI + (level.global_rotation.y if level else 0.0), -0.08)
			if "velocity" in p:
				p.velocity = Vector3.ZERO

# ================================================================== look (repair shop <-> company)
func _apply_look(repair: bool, force: bool = false) -> void:
	var lk := "repair" if repair else "company"
	var s: Dictionary = Game.state
	var nm := Story.company_name(s)
	var cols := Story.company_colors(s)
	var key := "%s|%s|%s|%s" % [lk, nm, cols[0].to_html(), Story.company_shape(s)]
	if not _override.is_empty():
		key = "ovr|" + str(_override)
	if key == _sign_key and not force:
		return
	_sign_key = key
	look = lk
	if not _override.is_empty():
		_build_sign(str(_override.get("style", "company")), str(_override.get("text", "")), _override.get("color", NEON), _override.get("color2", NEON_2), str(_override.get("shape", "hex")))
		_set_hanging(str(_override.get("style", "company")) == "neon", str(_override.get("text", "")), _override.get("color", NEON))
		_set_dress(str(_override.get("style", "company")) == "neon")
		return
	if repair:
		_build_sign("neon", "PHONE REPAIR", NEON, NEON_2, "")
	else:
		_build_sign("company", nm, cols[0], cols[1], Story.company_shape(s))
	_set_hanging(repair, nm, cols[0])
	_set_dress(repair)

## Title screen / cutscenes: force a sign. style "neon" (repair look) or "company". {} = back to the state.
func set_sign_override(text: String, color: Color, style: String = "company", color2: Color = NEON_2, shape: String = "hex") -> void:
	_override = {"text": text, "color": color, "color2": color2, "style": style, "shape": shape}
	_apply_look(style == "neon", true)

func clear_sign_override() -> void:
	_override = {}
	_apply_look(Story.repair_look(Game.state), true)

func sign_node() -> Node3D:
	return _sign_root

# ================================================================== outside sign
func _build_sign_mount() -> void:
	var g := kit.node(self, Vector3.ZERO, 0.0, "SignMount")
	# conduit + transformer box on the wall next to the sign
	var tz := D + 0.21
	kit.box(g, Vector3(0.22, 0.3, 0.12), Vector3(0.55, 3.35, tz), Mats.m("steel_dark"), Vector3.ZERO, false, 0.02)
	kit.box(g, Vector3(0.04, 0.04, 0.005), Vector3(0.55, 3.42, tz + 0.063), Mats.glow(Color(1.0, 0.5, 0.1), 2.0), Vector3.ZERO, false, 0.0, false)
	kit.cyl(g, 0.018, 0.9, Vector3(0.55, 2.75, D + 0.17), Mats.m("steel_dark"), Vector3.ZERO, 8)
	_sign_root = kit.node(self, SIGN_POS, 0.0, "OutsideSign")

func _build_sign(style: String, text: String, col: Color, col2: Color, shape: String) -> void:
	for c in _sign_root.get_children():
		c.queue_free()
	_sign_letters.clear()
	_sign_lights.clear()
	_sign_mats.clear()
	_buzz_letter = -1
	_sign_style = style
	var g := _sign_root
	if style == "neon":
		var bw := 3.4
		var bh := 0.66
		_sbox(g, Vector3(bw, bh, 0.07), Vector3(0, 0, -0.04), Mats.m("plastic_black", Color(3.2, 3.2, 3.6), {"roughness_base": 0.55, "grime": 0.6, "edge_wear": 0.5, "edge_color": Color(0.4, 0.4, 0.42)}), 0.015)
		for sx in [-1.0, 1.0]:
			_sbox(g, Vector3(0.05, 0.2, 0.22), Vector3(sx * 1.2, bh * 0.5 + 0.05, -0.12), Mats.m("steel_dark"), 0.01)
		# border tube (second colour)
		var bm := _neon_mat(col2, 3.0)
		_sbox(g, Vector3(bw - 0.1, 0.024, 0.024), Vector3(0, bh * 0.5 - 0.06, 0.01), bm, 0.0)
		_sbox(g, Vector3(bw - 0.1, 0.024, 0.024), Vector3(0, -bh * 0.5 + 0.06, 0.01), bm, 0.0)
		for sx in [-1.0, 1.0]:
			_sbox(g, Vector3(0.024, bh - 0.12, 0.024), Vector3(sx * (bw * 0.5 - 0.05), 0, 0.01), bm, 0.0)
		# icon: phone outline + wrench, left end
		var ic := Node3D.new()
		ic.position = Vector3(-bw * 0.5 + 0.3, 0, 0.02)
		g.add_child(ic)
		var pm := _neon_mat(col2, 3.4)
		for sx in [-1.0, 1.0]:
			_sbox(ic, Vector3(0.022, 0.38, 0.022), Vector3(sx * 0.1, 0, 0), pm, 0.0)
		for sy in [-1.0, 1.0]:
			_sbox(ic, Vector3(0.2, 0.022, 0.022), Vector3(0, sy * 0.19, 0), pm, 0.0)
		_sbox(ic, Vector3(0.05, 0.016, 0.02), Vector3(0, 0.155, 0.002), pm, 0.0)
		var wm := _neon_mat(col, 3.2)
		var wr := Node3D.new()
		wr.rotation_degrees.z = -40
		wr.position = Vector3(0.05, -0.02, 0.03)
		ic.add_child(wr)
		_sbox(wr, Vector3(0.03, 0.34, 0.02), Vector3(0, -0.04, 0), wm, 0.0)
		for sx in [-1.0, 1.0]:
			_sbox(wr, Vector3(0.022, 0.07, 0.02), Vector3(sx * 0.035, 0.15, 0), wm, 0.0)
		# letters (one Label3D each: one of them buzzes)
		var px := 104
		var ps := 0.0034
		var start := -bw * 0.5 + 0.62
		var avail := bw - 0.75
		var widths := []
		var total := 0.0
		for ch in text:
			var w := _char_w(ch, px)
			widths.append(w)
			total += w
		if total * ps > avail:
			ps = avail / total
		var x := start + (avail - total * ps) * 0.5
		for i in text.length():
			var ch := text[i]
			var w: float = widths[i] * ps
			if ch != " ":
				var l := Label3D.new()
				l.text = ch
				l.font_size = px
				l.pixel_size = ps
				l.position = Vector3(x + w * 0.5, -0.01, 0.03)
				l.outline_size = 14
				l.shaded = false
				l.double_sided = false
				l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
				if kit.font:
					l.font = kit.font
				g.add_child(l)
				_sign_letters.append({"l": l, "col": col})
			x += w
		# the "I" (or the 3rd-from-last letter) is the one with the bad transformer
		for i in _sign_letters.size():
			if (_sign_letters[i].l as Label3D).text == "I":
				_buzz_letter = i
		if _buzz_letter < 0 and _sign_letters.size() > 3:
			_buzz_letter = _sign_letters.size() - 3
		_sign_lights.append(kit.omni(g, Vector3(0.2, -0.25, 0.75), col, 1.5, 6.5, false, 0.9))
		_sign_lights.append(kit.omni(g, Vector3(-bw * 0.5 + 0.3, -0.2, 0.5), col2, 0.6, 3.5, false, 0.6))
	else:
		# backlit company lightbox + two gooseneck lamps
		var bw := 3.2
		var bh := 0.7
		var face := StandardMaterial3D.new()
		face.albedo_color = Color(0.96, 0.95, 0.92)
		face.emission_enabled = true
		face.emission = Color(1.0, 0.97, 0.92)
		face.emission_energy_multiplier = 0.75
		face.roughness = 0.35
		_sign_mats.append(face)
		face.set_meta("base", 0.75)
		_sbox(g, Vector3(bw + 0.08, bh + 0.08, 0.16), Vector3(0, 0, -0.06), Mats.m("plastic_white", Color.WHITE, {"albedo": col.darkened(0.55), "roughness_base": 0.4}), 0.02)
		_sbox(g, Vector3(bw, bh, 0.02), Vector3(0, 0, 0.03), face, 0.0)
		# colour bar under the name
		_sbox(g, Vector3(bw, 0.07, 0.025), Vector3(0, -bh * 0.5 + 0.035, 0.035), _neon_mat(col, 1.2), 0.0)
		# logo badge
		var lg := Node3D.new()
		lg.position = Vector3(-bw * 0.5 + 0.38, 0.03, 0.05)
		g.add_child(lg)
		logo_mesh(lg, shape, col, col2, 0.25, text.substr(0, 1).to_upper())
		var l := Label3D.new()
		l.text = text if text != "" else "COMPANY"
		l.font_size = 120
		l.shaded = false
		l.outline_size = 0
		l.modulate = col.darkened(0.4)
		l.text = l.text.to_upper()
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if kit.font:
			l.font = kit.font
		var tw := 1.0
		for ch in l.text:
			tw += _char_w(ch, 120)
		var avail := bw - 0.8
		l.pixel_size = minf(0.0048, avail / tw)
		l.position = Vector3(0.28, 0.02, 0.045)
		g.add_child(l)
		for sx in [-0.8, 0.8]:
			var gn := Node3D.new()
			gn.position = Vector3(sx, bh * 0.5 + 0.05, 0.0)
			g.add_child(gn)
			_sbox(gn, Vector3(0.025, 0.025, 0.32), Vector3(0, 0.05, 0.14), Mats.m("steel_dark"), 0.004)
			_sbox(gn, Vector3(0.12, 0.06, 0.08), Vector3(0, 0.03, 0.32), Mats.m("steel_dark"), 0.015)
			_sbox(gn, Vector3(0.09, 0.006, 0.05), Vector3(0, 0.0, 0.33), _neon_mat(Color(1.0, 0.9, 0.75), 4.0), 0.0)
			var sp: SpotLight3D = kit.spot(gn, Vector3(0, -0.01, 0.33), Vector3(0, -0.6, 0.05), Color(1.0, 0.9, 0.75), 2.2, 1.6, 50.0, false, 0.6)
			_sign_lights.append(sp)
		_sign_lights.append(kit.omni(g, Vector3(0, -0.3, 0.9), col.lerp(Color.WHITE, 0.5), 0.9, 5.0, false, 0.7))
	set_sign_lit(_sign_lit)

func _char_w(ch: String, px: int) -> float:
	if kit.font:
		return (kit.font as Font).get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	return px * 0.62

func _neon_mat(c: Color, e: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = e
	m.set_meta("base", e)
	_sign_mats.append(m)
	return m

func set_sign_lit(on: bool) -> void:
	_sign_lit = on
	for d in _sign_letters:
		var l: Label3D = d.l
		var c: Color = d.col
		if on:
			l.modulate = c.lerp(Color.WHITE, 0.55) * 2.6
			l.outline_modulate = Color(c.r, c.g, c.b, 1.0) * 1.6
		else:
			l.modulate = Color(0.22, 0.14, 0.17)
			l.outline_modulate = c.darkened(0.82)
	for m in _sign_mats:
		(m as StandardMaterial3D).emission_energy_multiplier = float(m.get_meta("base", 2.0)) if on else 0.02
	for li in _sign_lights:
		if is_instance_valid(li):
			li.visible = on

## Static logo badge: shape in colour A with the initial in colour B. shape: hex/circle/diamond/triangle/ring/square.
func logo_mesh(parent: Node3D, shape: String, ca: Color, cb: Color, r: float, initial: String) -> void:
	var m := _neon_mat(ca, 0.6)
	m.roughness = 0.4
	var mi := MeshInstance3D.new()
	match shape:
		"circle", "ring":
			mi.mesh = Meshes.cyl(r, 0.03, 28)
		"square":
			mi.mesh = Meshes.cbox(Vector3(r * 1.7, 0.03, r * 1.7), 0.02)
		"diamond":
			mi.mesh = Meshes.cyl(r, 0.03, 4)
		"triangle":
			mi.mesh = Meshes.cyl(r * 1.15, 0.03, 3)
		_:
			mi.mesh = Meshes.cyl(r, 0.03, 6)
	mi.material_override = m
	mi.rotation_degrees = Vector3(90, 0, 0 if shape != "triangle" else 90)
	if shape == "diamond":
		mi.rotation_degrees = Vector3(90, 45, 0)
	parent.add_child(mi)
	if shape == "ring":
		var hole := MeshInstance3D.new()
		hole.mesh = Meshes.cyl(r * 0.62, 0.035, 24)
		hole.material_override = Mats.m("plastic_white", Color(1.25, 1.25, 1.25))
		hole.rotation_degrees.x = 90
		hole.position.z = 0.002
		parent.add_child(hole)
	var l := Label3D.new()
	l.text = initial
	l.font_size = 120
	l.pixel_size = r * 0.011
	l.modulate = cb.lerp(Color.WHITE, 0.25) * 1.4
	l.outline_size = 10
	l.outline_modulate = ca.darkened(0.5)
	l.position = Vector3(0, -r * 0.05, 0.022)
	l.shaded = false
	if kit and kit.font:
		l.font = kit.font
	parent.add_child(l)

func _sbox(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, bevel: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = Meshes.cbox(size, bevel)
	mi.material_override = mat
	mi.position = pos
	if size.y < 0.03 or size.x < 0.03:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

# ================================================================== roll-up shop door
func _build_curtain() -> void:
	door_ia = StaticBody3D.new()
	door_ia.name = "IA_shop_door"
	door_ia.position = Vector3(-1.5, 0, D + 0.03)
	door_ia.set_meta("kind", "shop_door")
	door_ia.set_meta("id", "garage_rollup")
	door_ia.set_meta("prompt", "Open the shop")
	add_child(door_ia)
	_curtain = Node3D.new()
	_curtain.name = "Curtain"
	_curtain.position = Vector3(0, 2.4, 0)
	door_ia.add_child(_curtain)
	var slats := Mats.m("rollup", Color(0.95, 0.95, 1.0))
	kit.box(_curtain, Vector3(4.2, 2.4, 0.035), Vector3(0, -1.2, 0), slats, Vector3.ZERO, false, 0.0)
	kit.box(_curtain, Vector3(4.22, 0.07, 0.07), Vector3(0, -2.36, 0), Mats.m("steel_dark"), Vector3.ZERO, false, 0.012)
	for sz in [-1.0, 1.0]:
		var h := kit.node(_curtain, Vector3(0, -1.55, sz * 0.03), 0.0)
		kit.box(h, Vector3(0.22, 0.04, 0.03), Vector3(0, 0, sz * 0.02), Mats.m("metal"), Vector3.ZERO, false, 0.008)
	# a paper sign taped inside: "CLOSED - back at 9 (probably)"
	kit.box(_curtain, Vector3(0.42, 0.3, 0.003), Vector3(0.9, -1.1, -0.022), Mats.m("paper", Color(1.1, 1.05, 0.9)), Vector3(0, 0, 2), false, 0.0, false)
	var t := kit.label(_curtain, "CLOSED\nback at 9\n(probably)", Vector3(0.9, -1.1, -0.025), 44, Color(0.6, 0.1, 0.08), Vector3(0, 180, 2), 0.0014, true)
	t.line_spacing = -6.0
	_curtain_shape = CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(4.2, 2.4, 0.14)
	_curtain_shape.shape = bs
	_curtain_shape.position = Vector3(0, 1.2, 0)
	door_ia.add_child(_curtain_shape)
	_door_open = false

func door_is_open() -> bool:
	return _door_open

func set_door_open(open: bool, animate: bool) -> void:
	if open == _door_open:
		return
	_door_open = open
	_set_ia(door_ia, not open)
	if open:
		_curtain_shape.set_deferred("disabled", true)
		if animate:
			Sfx.play("rollup_door", door_ia.global_position + Vector3(0, 1.5, 0))
			var tw := create_tween()
			tw.tween_property(_curtain, "scale:y", 0.04, 1.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			tw.tween_callback(func() -> void: _curtain.visible = false)
		else:
			_curtain.scale.y = 0.04
			_curtain.visible = false
	else:
		_curtain_shape.set_deferred("disabled", false)
		_curtain.visible = true
		_curtain.scale.y = 1.0

# ================================================================== light switch + lights
func _build_switch() -> void:
	switch_ia = kit.interactable(self, "light_switch", "garage_lights", "Lights on", SWITCH_POS, 180.0)
	switch_ia.set_meta("keep_lit", true)
	kit.box(switch_ia, Vector3(0.15, 0.22, 0.07), Vector3(0, 0, 0.035), Mats.m("metal", Color(0.8, 0.8, 0.78), {"metallic_base": 0.5, "grime": 0.5}), Vector3.ZERO, false, 0.015)
	kit.box(switch_ia, Vector3(0.11, 0.16, 0.01), Vector3(0, 0, 0.072), Mats.m("steel_dark"), Vector3.ZERO, false, 0.004)
	_lever = kit.node(switch_ia, Vector3(0, 0, 0.08), 0.0, "Lever")
	kit.box(_lever, Vector3(0.03, 0.11, 0.03), Vector3(0, 0.05, 0.02), Mats.m("metal"), Vector3.ZERO, false, 0.006)
	kit.box(_lever, Vector3(0.06, 0.04, 0.05), Vector3(0, 0.11, 0.035), Mats.m("metal_red", Color(1.3, 1.3, 1.3)), Vector3.ZERO, false, 0.012)
	kit.cyl(switch_ia, 0.016, 1.58, Vector3(0, 0.9, 0.03), Mats.m("steel_dark"), Vector3.ZERO, 8)
	var lbl := kit.label(switch_ia, "LIGHTS", Vector3(0, 0.15, 0.0005), 40, Color(0.92, 0.88, 0.75), Vector3.ZERO, 0.0012, true)
	kit.box(switch_ia, Vector3(0.11, 0.035, 0.003), Vector3(0, 0.15, -0.001), Mats.m("plastic_black"), Vector3.ZERO, false, 0.0, false)
	lbl.position.z = 0.0015
	_pilot_mat = StandardMaterial3D.new()
	_pilot_mat.albedo_color = Color(1.0, 0.55, 0.1)
	_pilot_mat.emission_enabled = true
	_pilot_mat.emission = Color(1.0, 0.55, 0.1)
	_pilot_mat.emission_energy_multiplier = 5.0
	var pilot := kit.mesh(switch_ia, Meshes.sphere(0.014, 8), Vector3(0.045, -0.085, 0.078), _pilot_mat, Vector3.ZERO, false)
	pilot.set_meta("keep_lit", true)
	_pilot_light = kit.omni(switch_ia, Vector3(0.045, -0.085, 0.16), Color(1.0, 0.55, 0.1), 0.25, 0.9, false, 0.2)
	kit.ia_shape(switch_ia, Vector3(0.3, 0.36, 0.16), Vector3(0, 0, 0.06))
	_lever.rotation_degrees.x = 0.0

func lights_are_on() -> bool:
	return _lights_on

## All garage lights inside the room (+ the outside sign). Remembers emissive materials and swaps dark copies in.
func set_lights(on: bool, animate: bool) -> void:
	var changed := on != _lights_on
	_lights_on = on
	if _lever:
		var tw := create_tween()
		tw.tween_property(_lever, "rotation_degrees:x", -150.0 if on else 0.0, 0.15 if animate else 0.0)
	if _pilot_mat:
		var pc := Color(0.3, 1.0, 0.35) if on else Color(1.0, 0.55, 0.1)
		_pilot_mat.albedo_color = pc
		_pilot_mat.emission = pc
		_pilot_light.light_color = pc
		_pilot_light.light_energy = 0.08 if on else 0.3
	if switch_ia:
		switch_ia.set_meta("prompt", "Lights off" if on else "Lights on")
	set_sign_lit(on)
	if level == null:
		return
	var inv := level.global_transform.affine_inverse()
	var lights: Array = []
	var lit_meshes: Array = []
	for n in level.find_children("*", "", true, false):
		if not (n is Node3D) or _keep_lit(n):
			continue
		var p: Vector3 = inv * (n as Node3D).global_position
		if p.x < -W - 0.05 or p.x > W + 0.05 or p.z < -D - 0.1 or p.z > D + 0.05 or p.y < -0.1 or p.y > 3.02:
			continue
		if n is Light3D:
			lights.append(n)
		elif n is MeshInstance3D:
			var mi := n as MeshInstance3D
			var cur: Material = mi.material_override
			var orig: Material = mi.get_meta("lit_mat") if mi.has_meta("lit_mat") else cur
			if orig is StandardMaterial3D and (orig as StandardMaterial3D).emission_enabled:
				if mi.get_aabb().size.length() < 0.05:
					continue  # standby LEDs stay on: they help in the dark
				lit_meshes.append([mi, orig])
			elif orig is ShaderMaterial and (orig as ShaderMaterial).shader == Mats.SCREEN:
				lit_meshes.append([mi, orig])
		elif n is Label3D:
			var lb := n as Label3D
			if not lb.has_meta("lit_mod"):
				if lb.modulate.get_luminance() < 1.05:
					continue
				lb.set_meta("lit_mod", lb.modulate)
			lb.modulate = (lb.get_meta("lit_mod") as Color) if on else (lb.get_meta("lit_mod") as Color) * 0.12
	for e in lit_meshes:
		var mi: MeshInstance3D = e[0]
		var orig: Material = e[1]
		if not mi.has_meta("lit_mat"):
			mi.set_meta("lit_mat", orig)
		if on:
			if animate and changed:
				_delayed(mi, func() -> void: mi.material_override = orig, randf_range(0.0, 0.35))
			else:
				mi.material_override = orig
		else:
			mi.material_override = _dark_of(orig)
	for li in lights:
		var l := li as Light3D
		if on and animate and changed:
			var tube := l.get_parent() != null and str(l.get_parent().name).begins_with("Tube")
			l.visible = false
			if tube:
				_flicker_on(l)
			else:
				_delayed(l, func() -> void: l.visible = true, randf_range(0.0, 0.3))
		else:
			l.visible = on
	if changed and animate:
		Sfx.play("switch", switch_ia.global_position if switch_ia else global_position)

func _keep_lit(n: Node) -> bool:
	var k := 0
	while n != null and n != level and k < 8:
		if n.has_meta("keep_lit") or n.is_in_group("local_player") or n.is_in_group("customer") or n.is_in_group("repair_device"):
			return true
		n = n.get_parent()
		k += 1
	return false

func _dark_of(m: Material) -> Material:
	if _dark_cache.has(m):
		return _dark_cache[m]
	var d: Material
	if m is ShaderMaterial:
		d = (m as ShaderMaterial).duplicate()
		(d as ShaderMaterial).set_shader_parameter("energy", 0.03)
	else:
		var sm := (m as StandardMaterial3D).duplicate() as StandardMaterial3D
		sm.emission_energy_multiplier = 0.0
		sm.albedo_color = sm.albedo_color.darkened(0.5)
		d = sm
	_dark_cache[m] = d
	return d

func _delayed(n: Node, cb: Callable, t: float) -> void:
	if t <= 0.0:
		cb.call()
		return
	get_tree().create_timer(t).timeout.connect(func() -> void:
		if is_instance_valid(n) and _lights_on:
			cb.call())

func _flicker_on(l: Light3D) -> void:
	var seq := [0.08, 0.06, 0.12, 0.05, 0.25, 0.04]
	var t := 0.05
	var vis := true
	for d in seq:
		var v := vis
		_delayed(l, func() -> void: l.visible = v, t)
		t += d
		vis = not vis
	_delayed(l, func() -> void: l.visible = true, t)

# ================================================================== counter
func _build_counter() -> void:
	counter_ia = kit.interactable(self, "counter", "", "Counter", C_POS, 0.0)
	counter_ia.remove_from_group("interactable")
	var ia := counter_ia
	var w := 1.7
	var dp := 0.56
	var top := C_TOP
	var wood_dark := Mats.m("wood_dark")
	var teal := Mats.m("plaster", Color.WHITE, {"albedo": Color(0.16, 0.38, 0.4), "albedo2": Color(0.1, 0.25, 0.27), "grime": 0.45, "edge_wear": 0.5, "edge_color": Color(0.55, 0.6, 0.55)})
	# butcher-block top with a front overhang
	kit.box(ia, Vector3(w + 0.1, 0.05, dp + 0.1), Vector3(0, top - 0.025, 0.03), Mats.m("wood", Color(1.2, 1.08, 0.95)), Vector3.ZERO, false, 0.012)
	for sx in [-1.0, 1.0]:
		kit.box(ia, Vector3(0.05, top - 0.05, dp), Vector3(sx * (w * 0.5 - 0.025), (top - 0.05) * 0.5, 0), wood_dark, Vector3.ZERO, false, 0.01)
	# customer side: teal kick panel + glass display case
	kit.box(ia, Vector3(w - 0.1, 0.44, 0.03), Vector3(0, 0.22, dp * 0.5 - 0.015), teal, Vector3.ZERO, false, 0.008)
	var kick := kit.label(ia, "REPAIRS  •  PARTS  •  CASES", Vector3(0, 0.25, dp * 0.5 + 0.002), 64, Color(0.95, 0.88, 0.7), Vector3.ZERO, 0.0019, true)
	kick.name = "KickText"
	kit.box(ia, Vector3(w - 0.1, 0.03, dp - 0.06), Vector3(0, 0.45, 0), Mats.m("plywood"), Vector3.ZERO, false, 0.006)
	var glass := kit.box(ia, Vector3(w - 0.12, 0.5, 0.006), Vector3(0, 0.71, dp * 0.5 - 0.01), Mats.glass(Color(0.7, 0.8, 0.85, 0.12)), Vector3.ZERO, false, 0.0, false)
	glass.name = "DisplayGlass"
	for x in [-w * 0.5 + 0.06, 0.0, w * 0.5 - 0.06]:
		kit.box(ia, Vector3(0.025, 0.52, 0.025), Vector3(x, 0.71, dp * 0.5 - 0.012), Mats.m("metal"), Vector3.ZERO, false, 0.004)
	kit.box(ia, Vector3(w - 0.1, 0.012, dp - 0.1), Vector3(0, 0.68, 0.02), Mats.glass(Color(0.75, 0.85, 0.9, 0.25)), Vector3.ZERO, false, 0.0, false)
	# goods in the display: cases, coiled cables, earbuds, chargers
	var rng := RandomNumberGenerator.new()
	rng.seed = 33
	for row in 2:
		var y := 0.47 + row * 0.225
		var x := -w * 0.5 + 0.16
		while x < w * 0.5 - 0.14:
			var r := rng.randf()
			var p := Vector3(x, y, 0.05 + rng.randf_range(-0.04, 0.06))
			if r < 0.4:
				var c := Color.from_hsv(rng.randf(), 0.6, 0.85)
				var case := kit.box(ia, Vector3(0.075, 0.15, 0.012), p + Vector3(0, 0.075, 0), Mats.m("plastic_white", Color.WHITE, {"albedo": c, "roughness_base": 0.35}), Vector3(-10, rng.randf_range(-12, 12), 0), false, 0.008)
				kit.cyl(case, 0.01, 0.004, Vector3(-0.02, 0.05, 0.007), Mats.m("plastic_black"), Vector3(90, 0, 0), 8)
				x += 0.11
			elif r < 0.6:
				var tor := MeshInstance3D.new()
				var tm := TorusMesh.new()
				tm.inner_radius = 0.035
				tm.outer_radius = 0.05
				tm.rings = 12
				tm.ring_segments = 6
				tor.mesh = tm
				tor.material_override = Mats.m("plastic_white", Color(1.25, 1.25, 1.25)) if rng.randf() < 0.6 else Mats.m("plastic_black")
				tor.position = p + Vector3(0, 0.01, 0)
				ia.add_child(tor)
				x += 0.13
			elif r < 0.8:
				for k in 2:
					kit.mesh(ia, Meshes.sphere(0.014, 8), p + Vector3(k * 0.035, 0.015, 0), Mats.m("plastic_white", Color(1.3, 1.3, 1.3)), Vector3.ZERO, false)
				kit.box(ia, Vector3(0.07, 0.03, 0.05), p + Vector3(0.018, 0.005, 0.02), Mats.m("plastic_white", Color(1.3, 1.3, 1.3)), Vector3.ZERO, false, 0.01)
				x += 0.1
			else:
				kit.box(ia, Vector3(0.05, 0.05, 0.05), p + Vector3(0, 0.025, 0), Mats.m("plastic_white", Color(1.25, 1.25, 1.25)), Vector3.ZERO, false, 0.008)
				x += 0.09
	kit.box(ia, Vector3(w - 0.2, 0.01, 0.02), Vector3(0, top - 0.065, dp * 0.5 - 0.06), Mats.glow(Color(1.0, 0.95, 0.85), 2.5), Vector3.ZERO, false, 0.0, false)
	kit.omni(ia, Vector3(0, 0.82, 0.12), Color(1.0, 0.92, 0.8), 0.22, 1.1, false, 0.2)
	# staff side: shelf with receipt rolls, cash box, a sleeping toolbox
	kit.box(ia, Vector3(0.28, 0.12, 0.2), Vector3(0.45, 0.53, -0.12), Mats.m("metal_green"), Vector3.ZERO, false, 0.015)
	for i in 3:
		kit.cyl(ia, 0.035, 0.06, Vector3(-0.5 + i * 0.09, 0.5, -0.15), Mats.m("paper", Color(1.15, 1.15, 1.1)), Vector3(0, 0, 90), 12)
	kit.box(ia, Vector3(0.36, 0.14, 0.18), Vector3(-0.1, 0.1, -0.12), Mats.m("metal_red"), Vector3.ZERO, false, 0.015)
	# --- top: drop-off tray, bell, receipt printer + card terminal, pen cup
	var tray := Mats.m("rubber", Color.WHITE, {"albedo": Color(0.08, 0.14, 0.26), "roughness_base": 0.8})
	kit.box(ia, Vector3(0.72, 0.008, 0.36), Vector3(-0.42, top + 0.004, 0.04), tray, Vector3.ZERO, false, 0.003)
	kit.label(ia, "DROP-OFF", Vector3(-0.42, top + 0.0095, 0.19), 40, Color(0.7, 0.8, 0.95, 0.85), Vector3(-90, 0, 0), 0.0012, true)
	kit.box(ia, Vector3(0.14, 0.08, 0.16), Vector3(0.62, top + 0.04, -0.14), Mats.m("plastic_grey", Color(1.3, 1.3, 1.35)), Vector3.ZERO, false, 0.015)
	kit.box(ia, Vector3(0.06, 0.002, 0.12), Vector3(0.62, top + 0.09, -0.03), Mats.m("paper", Color(1.15, 1.15, 1.1)), Vector3(-25, 0, 0), false, 0.0, false)
	kit.box(ia, Vector3(0.08, 0.035, 0.13), Vector3(0.42, top + 0.018, -0.16), Mats.m("plastic_black"), Vector3(0, 12, 0), false, 0.01)
	kit.box(ia, Vector3(0.05, 0.002, 0.035), Vector3(0.42, top + 0.037, -0.13), Mats.glow(Color(0.4, 0.95, 0.6), 1.2), Vector3(0, 12, 0), false, 0.0, false)
	kit.cyl(ia, 0.035, 0.1, Vector3(0.78, top + 0.05, 0.12), Mats.m("ceramic", Color(0.3, 0.45, 0.8)), Vector3.ZERO, 12)
	for i in 3:
		kit.cyl(ia, 0.005, 0.14, Vector3(0.775 + i * 0.008, top + 0.12, 0.12), Mats.m("plastic_white", [Color(0.2, 0.3, 1.4), Color(1.4, 0.2, 0.2), Color(0.1, 0.1, 0.1)][i]), Vector3(0, 0, -8 + i * 8), 6)
	# repair look: price stand + candy bowl ; company look: reception (built on demand)
	_repair_dress = kit.node(ia, Vector3.ZERO, 0.0, "RepairDress")
	var st := kit.node(_repair_dress, Vector3(0.3, top, 0.17), 0.0, "PriceStand")
	kit.box(st, Vector3(0.24, 0.32, 0.006), Vector3(0, 0.16, 0), Mats.glass(Color(0.8, 0.9, 1.0, 0.25)), Vector3(-12, 0, 0), false, 0.0, false)
	kit.box(st, Vector3(0.22, 0.3, 0.002), Vector3(0, 0.16, -0.004), Mats.m("paper", Color(1.1, 1.08, 1.0)), Vector3(-12, 0, 0), false, 0.0, false)
	kit.box(st, Vector3(0.24, 0.012, 0.08), Vector3(0, 0.006, -0.03), Mats.glass(Color(0.8, 0.9, 1.0, 0.25)), Vector3.ZERO, false, 0.0, false)
	var pl := kit.label(st, "PRICES\nscreen ...... $49\nbattery ..... $29\nport ........ $19\nwet phone .. ask!", Vector3(0, 0.17, 0.0), 30, Color(0.1, 0.12, 0.2), Vector3(-12, 0, 0), 0.00078, true)
	pl.line_spacing = 2.0
	var bowl := kit.cyl(_repair_dress, 0.07, 0.05, Vector3(0.62, top + 0.025, 0.14), Mats.glass(Color(0.8, 0.9, 1.0, 0.3)), Vector3.ZERO, 14)
	bowl.name = "CandyBowl"
	for i in 9:
		var a := i * 2.1
		kit.mesh(_repair_dress, Meshes.sphere(0.014, 6), Vector3(0.62 + cos(a) * 0.035 * (i % 3) * 0.6, top + 0.03 + (i / 4) * 0.012, 0.14 + sin(a) * 0.03), Mats.m("plastic_white", Color.from_hsv(i * 0.13, 0.7, 1.1)), Vector3.ZERO, false)
	kit.box(_repair_dress, Vector3(0.12, 0.05, 0.002), Vector3(0.0, top + 0.03, 0.27), Mats.m("paper", Color(1.1, 1.05, 0.85)), Vector3(-60, 0, 0), false, 0.0, false)
	kit.label(_repair_dress, "RING FOR\nSERVICE", Vector3(0.0, top + 0.031, 0.2712), 22, Color(0.5, 0.08, 0.05), Vector3(-60, 0, 0), 0.0011, true)
	_reception = kit.node(ia, Vector3.ZERO, 0.0, "Reception")
	_reception.visible = false
	kit.ia_shape(ia, Vector3(w, top, dp), Vector3(0, top * 0.5, 0))
	# service bell: a real (grabbable) prop that dings
	if not decor_only:
		bell = _make_bell()
		bell.position = C_POS + Vector3(0.05, top + 0.035, 0.14)
		add_child(bell)
	else:
		_bell_mesh(kit.node(ia, Vector3(0.05, top, 0.14)))

func _bell_mesh(parent: Node3D) -> void:
	var brass := Mats.m("metal", Color(1.35, 1.05, 0.55), {"roughness_base": 0.25})
	var base := MeshInstance3D.new()
	base.mesh = Meshes.cyl(0.055, 0.018, 18)
	base.material_override = Mats.m("plastic_black", Color(2.2, 1.6, 1.2))
	base.position.y = 0.009
	parent.add_child(base)
	var dome := MeshInstance3D.new()
	dome.mesh = Meshes.sphere(0.045, 14)
	dome.scale = Vector3(1.0, 0.75, 1.0)
	dome.position.y = 0.022
	dome.material_override = brass
	parent.add_child(dome)
	var knob := MeshInstance3D.new()
	knob.mesh = Meshes.cyl(0.006, 0.03, 8)
	knob.position.y = 0.065
	knob.material_override = brass
	parent.add_child(knob)
	var cap := MeshInstance3D.new()
	cap.mesh = Meshes.sphere(0.011, 8)
	cap.position.y = 0.082
	cap.material_override = brass
	parent.add_child(cap)

func _make_bell() -> RigidBody3D:
	var rb := RigidBody3D.new()
	rb.name = "ServiceBell"
	rb.add_to_group("grabbable")
	rb.set_meta("prop", "service_bell")
	rb.mass = 0.4
	rb.angular_damp = 1.0
	rb.contact_monitor = true
	rb.max_contacts_reported = 2
	var v := Node3D.new()
	v.position.y = -0.035
	rb.add_child(v)
	_bell_mesh(v)
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.055
	cyl.height = 0.07
	cs.shape = cyl
	rb.add_child(cs)
	var last := [0.0]
	rb.body_entered.connect(func(_o: Node) -> void:
		var now := Time.get_ticks_msec() * 0.001
		if now - last[0] > 0.3 and rb.linear_velocity.length() > 0.8:
			last[0] = now
			ring_bell())
	return rb

func ring_bell() -> void:
	var at: Vector3 = bell.global_position if bell and is_instance_valid(bell) else to_global(C_POS + Vector3(0, C_TOP, 0))
	Sfx.play("counter_bell" if Sfx.has_sound("counter_bell") else "notify", at, -2.0)

## Counter dressing: repair look (price stand, candy) or reception (logo plaque, product stand, plant).
func _set_dress(repair: bool) -> void:
	if _repair_dress == null:
		return
	_repair_dress.visible = repair
	_reception.visible = not repair
	var kick := counter_ia.get_node_or_null("KickText") as Label3D
	var s: Dictionary = Game.state
	var nm := Story.company_name(s)
	if not _override.is_empty():
		nm = str(_override.get("text", nm))
	if kick:
		kick.text = "REPAIRS  •  PARTS  •  CASES" if repair else (nm.to_upper() + "  •  RECEPTION")
	if repair:
		return
	var cols := Story.company_colors(s)
	if not _override.is_empty():
		cols = [_override.get("color", cols[0]), _override.get("color2", cols[1])]
	var key := "%s|%s|%s" % [nm, (cols[0] as Color).to_html(), str(HQ.finished_products(s).size())]
	if key == _reception_key:
		return
	_reception_key = key
	for c in _reception.get_children():
		c.queue_free()
	var top := C_TOP
	# logo plaque on the glass front
	var plq := kit.node(_reception, Vector3(0, 0.72, 0.287), 0.0, "Plaque")
	kit.box(plq, Vector3(0.62, 0.2, 0.012), Vector3.ZERO, Mats.m("plastic_white", Color.WHITE, {"albedo": (cols[0] as Color).darkened(0.35), "roughness_base": 0.3}), Vector3.ZERO, false, 0.01)
	var lg := kit.node(plq, Vector3(-0.22, 0, 0.008), 0.0)
	logo_mesh(lg, Story.company_shape(s), cols[0], cols[1], 0.07, nm.substr(0, 1).to_upper())
	var pn := kit.label(plq, nm if nm != "" else "COMPANY", Vector3(0.06, 0, 0.008), 64, Color(1, 1, 1), Vector3.ZERO, 0.0016, false)
	pn.pixel_size = minf(0.0016, 0.4 / maxf(1.0, _char_w(pn.text, 64) * 1.0 + 1.0) * 1.0)
	# product on a little turntable stand
	var stand := kit.node(_reception, Vector3(0.38, top, 0.08), 0.0, "ProductStand")
	kit.cyl(stand, 0.09, 0.02, Vector3(0, 0.01, 0), Mats.m("plastic_white", Color(1.3, 1.3, 1.3)), Vector3.ZERO, 20)
	kit.mesh(stand, Meshes.cyl(0.094, 0.006, 20), Vector3(0, 0.022, 0), Mats.glow(cols[0], 1.5), Vector3.ZERO, false)
	var prods := HQ.finished_products(s)
	var model: Node3D = HQ.phone_model(s, prods[0], 0.09) if not prods.is_empty() else null
	if model:
		model.position = Vector3(0, 0.1, 0)
		model.rotation_degrees = Vector3(-8, 20, 0)
		stand.add_child(model)
	else:
		var ph := kit.node(stand, Vector3(0, 0.11, 0), 20.0)
		kit.box(ph, Vector3(0.075, 0.155, 0.01), Vector3.ZERO, Mats.m("plastic_black", Color.WHITE, {"albedo": (cols[0] as Color).darkened(0.3), "roughness_base": 0.25}), Vector3(-8, 0, 0), false, 0.006)
		kit.mesh(ph, Meshes.quad(Vector2(0.066, 0.14)), Vector3(0, 0, 0.0055), Mats.screen(3, cols[1], 1.2, 2.0), Vector3(-8, 0, 0), false)
	# plant + "WELCOME" card
	var pot := kit.node(_reception, Vector3(0.74, top, 0.1), 0.0, "Plant")
	kit.cyl(pot, 0.05, 0.09, Vector3(0, 0.045, 0), Mats.m("ceramic", Color(0.95, 0.95, 0.92)), Vector3.ZERO, 12)
	for i in 5:
		var lf := kit.box(pot, Vector3(0.025, 0.14, 0.006), Vector3(sin(i * 1.3) * 0.02, 0.15, cos(i * 1.3) * 0.02), Mats.m("grass", Color(1.4, 1.8, 1.2), {"pattern": 0}), Vector3(sin(i * 1.3) * 25, i * 70, cos(i * 1.3) * 25), false, 0.003)
		lf.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	kit.box(_reception, Vector3(0.16, 0.06, 0.002), Vector3(0.05, top + 0.035, 0.25), Mats.m("paper", Color(1.15, 1.15, 1.1)), Vector3(-60, 0, 0), false, 0.0, false)
	kit.label(_reception, "WELCOME!", Vector3(0.05, top + 0.036, 0.2512), 26, (cols[0] as Color).darkened(0.3), Vector3(-60, 0, 0), 0.0011, true)

# ================================================================== hanging lightbox sign over the counter
func _build_hanging_sign() -> void:
	_hang_root = kit.node(self, C_POS + Vector3(0, 2.36, 0), 0.0, "HangingSign")
	for sx in [-0.5, 0.5]:
		kit.cable(_hang_root, Vector3(sx, 0.62, 0), Vector3(sx, 0.16, 0), 0.0, 4, 0.008, Mats.m("metal"))

func _set_hanging(repair: bool, nm: String, col: Color) -> void:
	var key := "%s|%s|%s" % [repair, nm, col.to_html()]
	if key == _hang_key:
		return
	_hang_key = key
	for c in _hang_root.get_children():
		if c.name.begins_with("Box"):
			c.queue_free()
	var b := kit.node(_hang_root, Vector3.ZERO, 0.0, "Box")
	var face := StandardMaterial3D.new()
	face.albedo_color = Color(0.95, 0.93, 0.86) if repair else col.lerp(Color.WHITE, 0.2)
	face.emission_enabled = true
	face.emission = face.albedo_color
	face.emission_energy_multiplier = 0.9 if repair else 0.7
	kit.box(b, Vector3(1.32, 0.34, 0.09), Vector3.ZERO, Mats.m("steel_dark", Color(1.2, 1.2, 1.2)), Vector3.ZERO, false, 0.015)
	for sz in [-1.0, 1.0]:
		kit.box(b, Vector3(1.24, 0.27, 0.004), Vector3(0, 0, sz * 0.047), face, Vector3.ZERO, false, 0.0, false)
		var txt := "PHONE REPAIR" if repair else (nm.to_upper() if nm != "" else "WELCOME")
		var l := kit.label(b, txt, Vector3(0, 0.0, sz * 0.0505), 96, Color(0.12, 0.14, 0.22) if repair else Color(1, 1, 1), Vector3(0, 0 if sz > 0 else 180, 0), 0.0024, true)
		var tw := _char_w(txt, 96) if txt.length() < 2 else (kit.font as Font).get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 96).x if kit.font else 600.0
		l.pixel_size = minf(0.0024, 1.1 / maxf(tw, 1.0))
		if repair:
			var sub := kit.label(b, "while u wait  •  since last tuesday", Vector3(0, -0.1, sz * 0.0505), 40, Color(0.75, 0.2, 0.15), Vector3(0, 0 if sz > 0 else 180, 0), 0.0016, true)
			sub.name = "Sub"
			l.position.y = 0.025
	kit.omni(b, Vector3(0, -0.3, 0.0), Color(1.0, 0.95, 0.85) if repair else col.lerp(Color.WHITE, 0.4), 0.35, 1.8, false, 0.3)

# ================================================================== repair bench
func _build_bench() -> void:
	bench_ia = kit.interactable(self, "repair_bench", "", "Repair bench", B_POS, -90.0)
	bench_ia.remove_from_group("interactable")
	bench_ia.set_meta("seat", {"pos": Vector3(0, 0, 0.66), "yaw": 0.0, "eye": 1.24, "pitch": -27.0, "pose": "sit"})
	var ia := bench_ia
	var w := 1.6
	var dp := 0.7
	var top := B_TOP
	var frame := Mats.m("steel_dark")
	kit.box(ia, Vector3(w, 0.06, dp), Vector3(0, top - 0.03, 0), Mats.m("wood_planks", Color(1.15, 1.0, 0.85), {"cell": Vector2(2.0, 0.12)}), Vector3.ZERO, false, 0.012)
	for x in [-1.0, 1.0]:
		for z in [-1.0, 1.0]:
			kit.box(ia, Vector3(0.05, top - 0.06, 0.05), Vector3(x * (w * 0.5 - 0.05), (top - 0.06) * 0.5, z * (dp * 0.5 - 0.05)), frame, Vector3.ZERO, false, 0.008)
	kit.box(ia, Vector3(w - 0.1, 0.025, dp - 0.1), Vector3(0, 0.22, 0), Mats.m("plywood", Color(0.85, 0.85, 0.85)), Vector3.ZERO, false, 0.006)
	# junk under the bench: a donor-phone box + a shop vac
	kit.box(ia, Vector3(0.42, 0.26, 0.32), Vector3(-0.45, 0.365, -0.05), Mats.m("cardboard"), Vector3(0, 6, 0), false, 0.02)
	kit.label(ia, "DONOR\nPHONES", Vector3(-0.45, 0.38, 0.115), 44, Color(0.12, 0.1, 0.1), Vector3(0, 6, 0), 0.0014, true)
	kit.box(ia, Vector3(0.3, 0.2, 0.25), Vector3(0.4, 0.335, 0.0), Mats.m("plastic_black", Color(3, 3, 3)), Vector3.ZERO, false, 0.02)
	# ESD mat + holder (where a device snaps)
	var mat := Mats.m("rubber", Color.WHITE, {"albedo": Color(0.12, 0.42, 0.33), "roughness_base": 0.8, "grime": 0.35})
	kit.box(ia, Vector3(0.9, 0.005, 0.46), Vector3(-0.05, top + 0.0025, 0.08), mat, Vector3.ZERO, false, 0.002)
	for i in 6:
		kit.box(ia, Vector3(0.002, 0.0015, 0.44), Vector3(-0.45 + i * 0.16, top + 0.0055, 0.08), Mats.m("rubber", Color.WHITE, {"albedo": Color(0.2, 0.55, 0.45)}), Vector3.ZERO, false, 0.0, false)
	kit.label(ia, "ESD SAFE AREA", Vector3(-0.42, top + 0.006, 0.29), 30, Color(0.85, 0.95, 0.85, 0.8), Vector3(-90, 0, 0), 0.0011, true)
	holder = kit.node(ia, Vector3(-0.05, top + 0.005, 0.1), 0.0, "Holder")
	for sx in [-1.0, 1.0]:
		kit.box(holder, Vector3(0.025, 0.03, 0.08), Vector3(sx * 0.085, 0.015, 0), Mats.m("plastic_grey", Color(1.5, 1.5, 1.6)), Vector3.ZERO, false, 0.006)
	kit.box(holder, Vector3(0.2, 0.012, 0.03), Vector3(0, 0.006, -0.06), Mats.m("plastic_grey", Color(1.5, 1.5, 1.6)), Vector3.ZERO, false, 0.004)
	# magnifier lamp on an arm, light pointed at the holder
	var arm := kit.node(ia, Vector3(-0.6, top, -0.25), 0.0, "Magnifier")
	kit.box(arm, Vector3(0.08, 0.05, 0.08), Vector3(0, 0.025, 0), frame, Vector3.ZERO, false, 0.01)
	var am := Mats.m("plastic_white", Color(1.3, 1.3, 1.3))
	var elbow := Vector3(-0.5, top + 0.62, -0.12)
	_stick(ia, Vector3(-0.6, top + 0.04, -0.25), elbow, 0.026, am)
	_stick(ia, elbow, Vector3(-0.17, top + 0.4, 0.06), 0.024, am)
	kit.mesh(ia, Meshes.sphere(0.025, 8), elbow, Mats.m("steel_dark"), Vector3.ZERO, false)
	var head := kit.node(ia, Vector3(-0.05, top + 0.36, 0.1), 0.0, "LampHead")
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.085
	tm.outer_radius = 0.115
	tm.rings = 20
	tm.ring_segments = 8
	ring.mesh = tm
	ring.material_override = Mats.m("plastic_white", Color(1.3, 1.3, 1.35))
	head.add_child(ring)
	var ledring := MeshInstance3D.new()
	var tm2 := TorusMesh.new()
	tm2.inner_radius = 0.09
	tm2.outer_radius = 0.1
	tm2.rings = 20
	tm2.ring_segments = 4
	ledring.mesh = tm2
	ledring.position.y = -0.012
	ledring.material_override = Mats.glow(Color(0.92, 0.97, 1.0), 4.0)
	ledring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	head.add_child(ledring)
	kit.mesh(head, Meshes.cyl(0.088, 0.008, 20), Vector3(0, 0.002, 0), Mats.glass(Color(0.8, 0.92, 1.0, 0.22)), Vector3.ZERO, false)
	var ml := kit.spot(head, Vector3(0, -0.03, 0), Vector3(0, -0.4, 0.001), Color(0.9, 0.95, 1.0), 3.2, 1.3, 58.0, true, 0.3)
	ml.position = Vector3(0, -0.03, 0)
	ml.rotation_degrees = Vector3(-90, 0, 0)
	# soldering station + iron in its spring holder
	var ss := kit.node(ia, Vector3(0.5, top, -0.16), -10.0, "Solder")
	kit.box(ss, Vector3(0.17, 0.1, 0.15), Vector3(0, 0.05, 0), Mats.m("metal_blue"), Vector3.ZERO, false, 0.012)
	kit.box(ss, Vector3(0.07, 0.03, 0.003), Vector3(-0.02, 0.07, 0.076), Mats.glow(Color(1.0, 0.25, 0.1), 3.5), Vector3.ZERO, false, 0.0, false)
	kit.label(ss, "350°", Vector3(-0.02, 0.07, 0.079), 26, Color(1.0, 0.85, 0.7), Vector3.ZERO, 0.0009, false)
	kit.cyl(ss, 0.006, 0.012, Vector3(0.05, 0.075, 0.077), Mats.m("plastic_black"), Vector3(90, 0, 0), 8)
	for i in 6:
		kit.cyl(ss, 0.018, 0.006, Vector3(0.14, 0.03 + i * 0.012, 0.0), Mats.m("metal"), Vector3(0, 0, 30), 10)
	kit.cyl(ss, 0.006, 0.12, Vector3(0.13, 0.06, 0.0), Mats.m("metal"), Vector3(0, 0, 60), 6)
	kit.cyl(ss, 0.012, 0.08, Vector3(0.2, 0.1, 0.0), Mats.m("plastic_black"), Vector3(0, 0, 60), 8)
	kit.cable(ss, Vector3(0.08, 0.05, 0.0), Vector3(0.24, 0.12, 0.0), 0.06, 5, 0.007, Mats.m("plastic_black"))
	# parts drawers organizer at the back
	var org := kit.node(ia, Vector3(0.12, top, -0.27), 0.0, "Drawers")
	kit.box(org, Vector3(0.42, 0.3, 0.14), Vector3(0, 0.15, 0), Mats.m("plastic_grey", Color(1.6, 1.6, 1.7)), Vector3.ZERO, false, 0.008)
	var dcols := [Color(1.4, 0.5, 0.4), Color(0.5, 0.8, 1.4), Color(1.4, 1.3, 0.5), Color(0.6, 1.3, 0.6)]
	for r in 4:
		for c in 4:
			kit.box(org, Vector3(0.09, 0.06, 0.01), Vector3(-0.15 + c * 0.1, 0.04 + r * 0.07, 0.072), Mats.m("plastic_white", dcols[(r + c) % 4], {"roughness_base": 0.25}), Vector3.ZERO, false, 0.004)
	# screwdriver stand (a fan of handles)
	var sd := kit.node(ia, Vector3(-0.62, top, 0.12), 0.0, "Drivers")
	kit.cyl(sd, 0.05, 0.06, Vector3(0, 0.03, 0), Mats.m("wood_dark"), Vector3.ZERO, 12)
	for i in 7:
		var a := TAU * i / 7.0
		var hc := Color.from_hsv(i / 7.0, 0.75, 0.9)
		kit.cyl(sd, 0.008, 0.08, Vector3(cos(a) * 0.025, 0.1, sin(a) * 0.025), Mats.m("plastic_white", Color.WHITE, {"albedo": hc}), Vector3(sin(a) * 10, 0, -cos(a) * 10), 8)
	# multimeter, suction cup, spudgers, tweezers, screw mat, heat gun
	kit.box(ia, Vector3(0.09, 0.03, 0.16), Vector3(0.52, top + 0.015, 0.16), Mats.m("metal_yellow", Color.WHITE, {"metallic_base": 0.0}), Vector3(0, 20, 0), false, 0.012)
	kit.box(ia, Vector3(0.06, 0.003, 0.04), Vector3(0.52, top + 0.031, 0.13), Mats.m("tv_black"), Vector3(0, 20, 0), false, 0.0, false)
	kit.cable(ia, Vector3(0.5, top + 0.02, 0.24), Vector3(0.3, top + 0.005, 0.3), 0.0, 3, 0.005, Mats.m("plastic_white", Color(1.4, 0.3, 0.2)))
	kit.cyl(ia, 0.028, 0.012, Vector3(0.3, top + 0.006, -0.05), Mats.m("plastic_white", Color(0.5, 0.6, 1.4), {"roughness_base": 0.2}), Vector3.ZERO, 12)
	for i in 3:
		kit.box(ia, Vector3(0.008, 0.004, 0.11), Vector3(0.22 + i * 0.03, top + 0.003, 0.25), Mats.m("plastic_white", [Color(0.3, 0.3, 1.5), Color(1.5, 1.5, 1.5), Color(0.3, 0.3, 0.32)][i]), Vector3(0, 10 - i * 12, 0), false, 0.002)
	var mag := Mats.m("plastic_white", Color(1.4, 1.4, 1.45))
	kit.box(ia, Vector3(0.14, 0.004, 0.1), Vector3(0.28, top + 0.002, 0.08), mag, Vector3.ZERO, false, 0.002)
	for r in 3:
		for c in 4:
			kit.mesh(ia, Meshes.sphere(0.003, 4), Vector3(0.235 + c * 0.03, top + 0.006, 0.05 + r * 0.03), Mats.m("metal"), Vector3.ZERO, false)
	var hg := kit.node(ia, Vector3(-0.3, top, -0.2), 70.0, "HeatGun")
	kit.box(hg, Vector3(0.2, 0.07, 0.06), Vector3(0, 0.035, 0), Mats.m("plastic_orange"), Vector3.ZERO, false, 0.015)
	kit.cyl(hg, 0.02, 0.08, Vector3(0.13, 0.035, 0), Mats.m("metal"), Vector3(0, 0, 90), 10)
	kit.box(hg, Vector3(0.04, 0.1, 0.04), Vector3(-0.05, -0.0, 0), Mats.m("plastic_black"), Vector3(0, 0, 15), false, 0.01)
	# pegboard + hanging tools
	kit.box(ia, Vector3(w - 0.1, 0.78, 0.02), Vector3(0, 1.55, -dp * 0.5 + 0.02), Mats.m("pegboard", Color(0.9, 1.0, 1.05)), Vector3.ZERO, false, 0.004)
	var tools := kit.node(ia, Vector3(0, 1.55, -dp * 0.5 + 0.04), 0.0)
	for i in 6:
		kit.box(tools, Vector3(0.022, 0.16 + (i % 3) * 0.03, 0.01), Vector3(-0.62 + i * 0.07, 0.12, 0.0), Mats.m("metal"), Vector3(0, 0, -6 + i * 2), false, 0.004)
		kit.box(tools, Vector3(0.03, 0.08, 0.025), Vector3(-0.62 + i * 0.07, 0.24, 0.0), Mats.m("plastic_white", Color.from_hsv(i * 0.16, 0.7, 0.9)), Vector3.ZERO, false, 0.008)
	for i in 3:
		var pli := kit.node(tools, Vector3(-0.1 + i * 0.13, 0.05, 0.005), 0.0)
		for s in [-1.0, 1.0]:
			kit.box(pli, Vector3(0.018, 0.17, 0.01), Vector3(s * 0.018, -0.02, 0), Mats.m("metal_red" if i != 1 else "metal_blue"), Vector3(0, 0, s * 8.0), false, 0.004)
	var hint := kit.label(tools, "IF IN DOUBT:\nTURN IT OFF\nAND ON AGAIN", Vector3(0.48, 0.12, 0.004), 40, Color(0.1, 0.1, 0.12), Vector3.ZERO, 0.0011, true)
	kit.box(tools, Vector3(0.26, 0.18, 0.002), Vector3(0.48, 0.12, 0.001), Mats.m("paper", Color(1.1, 1.0, 0.6)), Vector3(0, 0, 2), false, 0.0, false)
	hint.rotation_degrees.z = 2
	# parts shelf: SCREENS / BATTERIES / PORTS bins that show inventory.resources
	kit.box(ia, Vector3(w - 0.05, 0.03, 0.3), Vector3(0, 2.02, -dp * 0.5 + 0.17), Mats.m("plywood"), Vector3.ZERO, false, 0.006)
	for x in [-0.7, 0.7]:
		kit.box(ia, Vector3(0.03, 0.15, 0.26), Vector3(x, 1.94, -dp * 0.5 + 0.15), frame, Vector3.ZERO, false, 0.004)
	var bins := [["repair_screen", "SCREENS", Color(0.3, 0.55, 1.0)], ["repair_battery", "BATTERIES", Color(1.0, 0.75, 0.15)], ["repair_port", "PORTS", Color(0.95, 0.3, 0.25)]]
	for i in bins.size():
		var bx := kit.node(ia, Vector3(-0.48 + i * 0.48, 2.035, -dp * 0.5 + 0.17), 0.0, "Bin_" + str(bins[i][0]))
		var bm := Mats.m("plastic_white", Color.WHITE, {"albedo": bins[i][2], "roughness_base": 0.4})
		kit.box(bx, Vector3(0.36, 0.012, 0.24), Vector3(0, 0.006, 0), bm, Vector3.ZERO, false, 0.004)
		kit.box(bx, Vector3(0.36, 0.12, 0.012), Vector3(0, 0.06, -0.115), bm, Vector3.ZERO, false, 0.004)
		for sx in [-1.0, 1.0]:
			kit.box(bx, Vector3(0.012, 0.12, 0.24), Vector3(sx * 0.174, 0.06, 0), bm, Vector3.ZERO, false, 0.004)
		kit.box(bx, Vector3(0.36, 0.07, 0.012), Vector3(0, 0.035, 0.115), bm, Vector3.ZERO, false, 0.004)
		kit.box(bx, Vector3(0.24, 0.045, 0.002), Vector3(0, 0.04, 0.122), Mats.m("paper", Color(1.15, 1.15, 1.1)), Vector3.ZERO, false, 0.0, false)
		var bl := kit.label(bx, str(bins[i][1]), Vector3(0, 0.04, 0.1235), 34, Color(0.08, 0.08, 0.12), Vector3.ZERO, 0.0011, true)
		var parts := []
		for k in 6:
			var pm: Material
			var ps: Vector3
			match i:
				0:
					pm = Mats.m("tv_black", Color.WHITE, {"roughness_base": 0.1})
					ps = Vector3(0.09, 0.006, 0.17)
				1:
					pm = Mats.m("metal", Color(1.1, 1.1, 1.15))
					ps = Vector3(0.06, 0.012, 0.1)
				_:
					pm = Mats.m("plastic_black")
					ps = Vector3(0.03, 0.01, 0.05)
			var pp := kit.box(bx, ps, Vector3(-0.1 + (k % 3) * 0.1, 0.018 + (k / 3) * (ps.y + 0.003), 0.0), pm, Vector3(0, (k * 37) % 11 - 5, 0), false, 0.003)
			parts.append(pp)
		_bins[bins[i][0]] = {"label": bl, "parts": parts, "name": bins[i][1]}
	kit.box(ia, Vector3(w - 0.2, 0.01, 0.02), Vector3(0, 1.995, -dp * 0.5 + 0.28), Mats.glow(Color(0.85, 0.95, 1.0), 2.5), Vector3.ZERO, false, 0.0, false)
	var sl := kit.spot(ia, Vector3(0, 1.98, -dp * 0.5 + 0.3), Vector3(0, top, 0.1), Color(0.85, 0.92, 1.0), 1.2, 1.8, 70.0, false, 0.25)
	sl.position = Vector3(0, 1.98, -dp * 0.5 + 0.3)
	# little "REPAIR" neon on the pegboard
	kit.label(ia, "REPAIRS", Vector3(-0.42, 1.86, -dp * 0.5 + 0.035), 64, Color(0.4, 1.0, 0.9) * 2.0, Vector3.ZERO, 0.0016, false).outline_size = 10
	# stool
	var stool := kit.node(ia, Vector3(0, 0, 0.62), 0.0, "Stool")
	kit.cyl(stool, 0.17, 0.05, Vector3(0, 0.62, 0), Mats.m("fabric", Color(0.5, 0.2, 0.15)), Vector3.ZERO, 16)
	kit.cyl(stool, 0.025, 0.6, Vector3(0, 0.31, 0), frame, Vector3.ZERO, 8)
	for i in 4:
		var a := TAU * i / 4.0 + 0.4
		kit.box(stool, Vector3(0.03, 0.025, 0.24), Vector3(sin(a) * 0.1, 0.02, cos(a) * 0.1), frame, Vector3(0, rad_to_deg(a), 0), false, 0.006)
	kit.ia_shape(ia, Vector3(w, top, dp), Vector3(0, top * 0.5, 0))
	kit.ia_shape(ia, Vector3(w, 0.8, 0.06), Vector3(0, 1.55, -dp * 0.5 + 0.03))
	kit.ia_shape(ia, Vector3(0.36, 0.64, 0.36), Vector3(0, 0.32, 0.62))

func _stick(parent: Node3D, a: Vector3, b: Vector3, thick: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = Meshes.cbox(Vector3(thick, thick, 1.0), 0.0)
	mi.material_override = mat
	parent.add_child(mi)
	var d := b - a
	mi.transform = Transform3D(Basis.looking_at(d, Vector3.UP if absf(d.normalized().y) < 0.95 else Vector3.RIGHT).scaled_local(Vector3(1, 1, d.length())), (a + b) * 0.5)

func _update_bins(s: Dictionary) -> void:
	var res := HQ.dict(HQ.section(s, "inventory").get("resources"))
	for id in _bins:
		var b: Dictionary = _bins[id]
		var n := int(float(str(res.get(id, 0))) if str(res.get(id, 0)).is_valid_float() else 0.0)
		var parts: Array = b.parts
		for i in parts.size():
			(parts[i] as Node3D).visible = i < n
		(b.label as Label3D).text = "%s %d" % [b.name, n] if n > 0 else "%s — OUT!" % b.name
		(b.label as Label3D).modulate = Color(0.08, 0.08, 0.12) if n > 0 else Color(0.75, 0.08, 0.05)

## For tests: units shown in a parts bin.
func bin_shown(resource_id: String) -> int:
	if not _bins.has(resource_id):
		return -1
	var n := 0
	for p in _bins[resource_id].parts:
		if (p as Node3D).visible:
			n += 1
	return n

# ================================================================== broken gadget shelf (decor)
func _build_gadget_shelf() -> void:
	var g := kit.node(self, S_POS, -90.0, "GadgetShelf")
	var w := 1.0
	var dp := 0.38
	var post := Mats.m("metal_green", Color(1.2, 1.2, 1.2))
	for x in [-1.0, 1.0]:
		for z in [-1.0, 1.0]:
			kit.box(g, Vector3(0.035, 1.85, 0.035), Vector3(x * (w * 0.5 - 0.02), 0.925, z * (dp * 0.5 - 0.02)), post, Vector3.ZERO, false, 0.006)
	var ys := [0.1, 0.58, 1.06, 1.5, 1.84]
	var tags := ["SPARE CABLES", "DONOR PARTS — DO NOT SELL", "MYSTERY FAULTS", "WAITING FOR PARTS", ""]
	for i in ys.size():
		var y: float = ys[i]
		kit.box(g, Vector3(w, 0.022, dp), Vector3(0, y, 0), Mats.m("metal", Color(0.85, 0.85, 0.85)), Vector3.ZERO, false, 0.004)
		if tags[i] != "":
			kit.box(g, Vector3(0.5, 0.035, 0.002), Vector3(0, y - 0.03, dp * 0.5 + 0.001), Mats.m("paper", Color(1.1, 1.05, 0.8)), Vector3.ZERO, false, 0.0, false)
			kit.label(g, tags[i], Vector3(0, y - 0.03, dp * 0.5 + 0.0025), 30, Color(0.1, 0.1, 0.15), Vector3.ZERO, 0.0012, true)
	kit.shape(Vector3(w, 1.85, dp), g.global_transform.translated_local(Vector3(0, 0.925, 0)))
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	# shelf 1.5: phones waiting for parts, with tickets
	for k in 5:
		_decor_phone(g, Vector3(-0.38 + k * 0.18, 1.52, 0.02), Vector3(-75, rng.randf_range(-10, 10), 0), rng, true)
	# shelf 1.06: mystery gadgets: old radio, flip phones, handheld, smart watch
	var radio := kit.node(g, Vector3(-0.28, 1.08, 0.0), 8.0, "Radio")
	kit.box(radio, Vector3(0.3, 0.17, 0.1), Vector3(0, 0.085, 0), Mats.m("plastic_beige", Color(0.9, 0.7, 0.55)), Vector3.ZERO, false, 0.02)
	kit.box(radio, Vector3(0.14, 0.12, 0.004), Vector3(-0.06, 0.085, 0.051), Mats.m("pegboard", Color(0.4, 0.4, 0.4)), Vector3.ZERO, false, 0.0)
	kit.cyl(radio, 0.025, 0.02, Vector3(0.08, 0.11, 0.055), Mats.m("plastic_black"), Vector3(90, 0, 0), 12)
	kit.box(radio, Vector3(0.006, 0.3, 0.006), Vector3(0.12, 0.3, -0.02), Mats.m("metal"), Vector3(0, 0, -25), false, 0.0)
	var hh := kit.node(g, Vector3(0.08, 1.09, 0.03), -12.0, "Handheld")
	kit.box(hh, Vector3(0.2, 0.03, 0.09), Vector3(0, 0.015, 0), Mats.m("plastic_white", Color(0.6, 0.6, 1.2)), Vector3.ZERO, false, 0.012)
	kit.mesh(hh, Meshes.quad(Vector2(0.08, 0.06)), Vector3(0, 0.031, 0), Mats.m("tv_black"), Vector3(-90, 0, 0), false)
	for k in 2:
		var fp := kit.node(g, Vector3(0.28 + k * 0.1, 1.08, 0.04), 20.0 - k * 40.0, "Flip")
		kit.box(fp, Vector3(0.055, 0.025, 0.11), Vector3(0, 0.0125, 0), Mats.m("metal", Color(0.5 + k * 0.4, 0.5, 0.6)), Vector3.ZERO, false, 0.008)
	kit.box(g, Vector3(0.035, 0.012, 0.035), Vector3(0.42, 1.08, -0.08), Mats.m("plastic_black"), Vector3(0, 30, 0), false, 0.008)
	# shelf 0.58: donor parts: a cracked tablet leaning, a laptop with a sticky note, boards in a tray
	var tab := kit.node(g, Vector3(-0.3, 0.6, -0.1), 0.0, "Tablet")
	kit.box(tab, Vector3(0.3, 0.21, 0.012), Vector3(0, 0.11, 0), Mats.m("plastic_black"), Vector3(-12, 0, 0), false, 0.008)
	var tq := kit.mesh(tab, Meshes.quad(Vector2(0.27, 0.18)), Vector3(0, 0.112, 0.0075), Mats.m("tv_black", Color.WHITE, {"roughness_base": 0.08}), Vector3(-12, 0, 0), false)
	for i in 6:
		var a := i * 1.05 + 0.3
		kit.box(tq, Vector3(0.0025, 0.08, 0.001), Vector3(cos(a) * 0.04, sin(a) * 0.04, 0.001), Mats.unlit(Color(0.75, 0.82, 0.9)), Vector3(0, 0, rad_to_deg(a) - 90.0), false, 0.0, false)
	var lap := kit.node(g, Vector3(0.18, 0.6, 0.0), -8.0, "Laptop")
	kit.box(lap, Vector3(0.34, 0.025, 0.24), Vector3(0, 0.0125, 0), Mats.m("plastic_grey", Color(1.5, 1.5, 1.6)), Vector3.ZERO, false, 0.008)
	kit.box(lap, Vector3(0.34, 0.24, 0.015), Vector3(0, 0.13, -0.13), Mats.m("plastic_grey", Color(1.5, 1.5, 1.6)), Vector3(-20, 0, 0), false, 0.008)
	kit.box(lap, Vector3(0.07, 0.07, 0.002), Vector3(0.1, 0.16, -0.115), Mats.m("paper", Color(1.2, 1.1, 0.4)), Vector3(-20, 0, 5), false, 0.0, false)
	kit.label(lap, "FIX\nME", Vector3(0.1, 0.16, -0.1135), 30, Color(0.1, 0.1, 0.2), Vector3(-20, 0, 5), 0.0012, true)
	for k in 3:
		kit.box(g, Vector3(0.09, 0.012, 0.15), Vector3(0.38, 0.6 + k * 0.014, 0.05), Mats.m("metal_green", Color(0.6, 1.5, 0.7)), Vector3(0, k * 9, 0), false, 0.003)
	# shelf 0.1: cable spaghetti in a crate, boxes
	kit.box(g, Vector3(0.4, 0.22, 0.3), Vector3(-0.25, 0.22, 0), Mats.m("cardboard"), Vector3(0, -4, 0), false, 0.02)
	for k in 4:
		var tor := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.05 + k * 0.01
		tm.outer_radius = 0.065 + k * 0.01
		tm.rings = 14
		tm.ring_segments = 5
		tor.mesh = tm
		tor.material_override = Mats.m("plastic_white", Color.from_hsv(k * 0.23, 0.3, 1.0)) if k % 2 == 0 else Mats.m("plastic_black")
		tor.position = Vector3(-0.25 + (k % 2) * 0.05, 0.34 + k * 0.012, -0.02 + k * 0.02)
		tor.rotation_degrees = Vector3(k * 10, 0, k * 7)
		g.add_child(tor)
	kit.box(g, Vector3(0.36, 0.3, 0.3), Vector3(0.26, 0.26, -0.02), Mats.m("cardboard", Color(0.9, 0.85, 0.8)), Vector3(0, 6, 0), false, 0.02)
	kit.label(g, "CASES", Vector3(0.26, 0.28, 0.135), 48, Color(0.1, 0.1, 0.12), Vector3(0, 6, 0), 0.0016, true)
	# top: a stack of phones with rubber bands
	for k in 4:
		_decor_phone(g, Vector3(0.1, 1.86 + k * 0.016, 0.0), Vector3(0, k * 13, 0), rng, false, true)

func _decor_phone(g: Node3D, pos: Vector3, rot: Vector3, rng: RandomNumberGenerator, ticket: bool, flat: bool = false) -> void:
	var n := kit.node(g, pos, 0.0)
	n.rotation_degrees = rot
	var col: Color = Device.BODY_COLS[rng.randi() % Device.BODY_COLS.size()]
	kit.box(n, Vector3(0.08, 0.012, 0.16) if flat else Vector3(0.08, 0.16, 0.012), Vector3(0, 0.0 if flat else 0.08, 0), Mats.m("plastic_black", Color.WHITE, {"albedo": col, "roughness_base": 0.35}), Vector3.ZERO, false, 0.006)
	if not flat:
		var sc := kit.mesh(n, Meshes.quad(Vector2(0.07, 0.14)), Vector3(0, 0.08, 0.0065), Mats.m("tv_black", Color.WHITE, {"roughness_base": 0.08}), Vector3.ZERO, false)
		if rng.randf() < 0.7:
			for i in 5:
				var a := rng.randf() * TAU
				kit.box(sc, Vector3(0.002, rng.randf_range(0.03, 0.07), 0.001), Vector3(cos(a) * 0.015, sin(a) * 0.02, 0.001), Mats.unlit(Color(0.75, 0.82, 0.9)), Vector3(0, 0, rad_to_deg(a)), false, 0.0, false)
	if ticket:
		kit.box(n, Vector3(0.045, 0.03, 0.002), Vector3(0.03, 0.03, 0.012), Mats.m("paper", Color(1.1, 1.05, 0.85)), Vector3(0, 0, -15), false, 0.0, false)
		kit.label(n, "#%d" % rng.randi_range(3, 99), Vector3(0.03, 0.03, 0.0135), 30, Color(0.6, 0.1, 0.08), Vector3(0, 0, -15), 0.0009, true)
	else:
		kit.box(n, Vector3(0.084, 0.016, 0.01), Vector3(0, 0, 0.02), Mats.m("plastic_orange", Color(1.2, 0.6, 0.4)), Vector3.ZERO, false, 0.002)

# ================================================================== interactables
func _set_ia(n: Node, on: bool) -> void:
	if n == null:
		return
	if on and not n.is_in_group("interactable"):
		n.add_to_group("interactable")
	elif not on and n.is_in_group("interactable"):
		n.remove_from_group("interactable")

func _on_interact(kind: String, _id: String) -> void:
	var s: Dictionary = Game.state
	match kind:
		"shop_door":
			if _door_open:
				return
			_local_door = true
			set_door_open(true, true)
			_story_event(Story.EV_DOOR, s)
		"light_switch":
			_local_lights = not _lights_on
			set_lights(bool(_local_lights), true)
			if _lights_on:
				_story_event(Story.EV_LIGHTS, s)
		"supplier_phone":
			if Story.active(s) and Story.chapter(s) == 2 and not Story.any_done(s, ["call_supplier"]) and not _sent_events.has(Story.EV_SUPPLIER):
				_sent_events[Story.EV_SUPPLIER] = true
				Net.act("storyEvent", {"id": Story.EV_SUPPLIER})

func _story_event(id: String, s: Dictionary) -> void:
	if not Story.active(s) or Story.chapter(s) > 0 or _sent_events.has(id) or str(Story.story(s).get("mode", "story")) != "story" and Story.story(s).has("mode"):
		return
	if id == Story.EV_DOOR and Story.any_done(s, Story.DOOR_STEPS):
		return
	if id == Story.EV_LIGHTS and Story.any_done(s, Story.LIGHT_STEPS):
		return
	_sent_events[id] = true
	var r: Dictionary = await Net.act("storyEvent", {"id": id})
	if not r.get("ok", false):
		_sent_events.erase(id)

# ================================================================== orders: customers + devices
func _counter_xf() -> Transform3D:
	return global_transform * Transform3D(Basis(), C_POS)

func _bench_xf() -> Transform3D:
	return bench_ia.global_transform

func tray_slot(i: int) -> Vector3:
	return to_global(C_POS + Vector3(-0.66 + (i % 3) * 0.24, C_TOP + 0.03, 0.04))

func _g(p: Vector3) -> Vector3:
	return to_global(p)

func on_counter(dev: Node3D) -> bool:
	var p: Vector3 = _counter_xf().affine_inverse() * dev.global_position
	return absf(p.x) < 0.88 and absf(p.z) < 0.36 and p.y > C_TOP - 0.06 and p.y < C_TOP + 0.45

func on_bench(dev: Node3D) -> bool:
	var p: Vector3 = _bench_xf().affine_inverse() * dev.global_position
	return absf(p.x + 0.05) < 0.55 and p.z > -0.22 and p.z < 0.36 and p.y > B_TOP - 0.06 and p.y < B_TOP + 0.45

func _player_holds(dev: Node) -> bool:
	for p in get_tree().get_nodes_in_group("local_player"):
		if p.get("held") == dev:
			return true
	return false

func _sync_orders(s: Dictionary) -> void:
	var live := {}
	for o in Story.orders(s):
		live[str(o.id)] = o
	var every := Story.all_orders(s)
	# gone: paid (happy) or vanished (angry)
	for id in customers.keys() + devices.keys():
		if live.has(id):
			continue
		var paid := str(HQ.dict(every.get(id)).get("status", "")) == "paid" or str(last_status.get(id, "")) == "ready"
		_finish_order(id, paid)
	for id in live:
		var o: Dictionary = live[id]
		var st := str(o.get("status", "waiting"))
		var prev := str(last_status.get(id, ""))
		last_status[id] = st
		if not customers.has(id):
			_spawn_customer(o, _first_sync or st != "waiting")
		var dev: RigidBody3D = devices.get(id)
		if dev == null and (st != "waiting" or _first_sync):
			dev = _spawn_device(o)
			_place_canonical(dev, st)
		if dev and is_instance_valid(dev):
			dev.set_fixed(st in ["ready", "paid"])
			if prev == "inRepair" and st == "ready":
				_unsnap(dev)
				var c: Node = customers.get(id)
				if c and is_instance_valid(c):
					c.emote("!", 2.0)
					_dialogue(c, "notice")
	_update_interactables()

## Customer appears. instant = already inside (rebuild / join / order not new).
func _spawn_customer(o: Dictionary, instant: bool) -> void:
	var id := str(o.id)
	var c: Node3D = Customer.new()
	add_child(c)
	c.setup(o)
	customers[id] = c
	if instant:
		var spot: Array = WAIT_SPOTS[_next_spot % WAIT_SPOTS.size()]
		_next_spot += 1
		c.global_position = _g(spot[0])
		c.rotation.y = deg_to_rad(float(spot[1])) + global_rotation.y
		c.state = "wait"
		c.set_pose(_idle_pose(c))
		return
	var side := -1.0 if absi(hash(id)) % 2 == 0 else 1.0
	var start := Vector3(7.0 if side > 0 else -7.5, 0, 7.3)
	c.global_position = _g(start)
	c.state = "enter"
	var target := COUNTER_SPOT if not _counter_busy(c) else QUEUE_SPOT
	var path := [_g(Vector3(DOOR_LANE_X, 0, 7.3)), _g(Vector3(DOOR_LANE_X, 0, 4.3)), _g(Vector3(DOOR_LANE_X, 0, 2.7)), _g(target)]
	c.walk(path, func() -> void: _arrived(c))

func _counter_busy(except: Node) -> bool:
	for c in customers.values():
		if c != except and is_instance_valid(c) and c.state in ["give", "collect"]:
			return true
		if c != except and is_instance_valid(c) and c.state == "enter" and not c.is_walking():
			return true
	return false

func _arrived(c: Node3D) -> void:
	if not is_instance_valid(c) or c.state != "enter":
		return
	if c.global_position.distance_to(_g(COUNTER_SPOT)) > 0.2:
		# queued: wait until the counter is free
		c.face(PI + global_rotation.y)
		c.set_pose("tap_foot")
		_retry_arrive(c)
		return
	c.state = "give"
	c.face(PI + global_rotation.y)
	c.set_pose("give")
	ring_bell()
	c.emote("!", 1.6)
	_dialogue(c, "arrive")
	get_tree().create_timer(0.9).timeout.connect(func() -> void:
		if not is_instance_valid(c):
			return
		var id := str(c.order_id)
		var o: Dictionary = HQ.dict(Story.all_orders(Game.state).get(id))
		if devices.get(id) == null and not o.is_empty():
			var dev := _spawn_device(o)
			dev.global_position = c.global_position + Vector3(0, 1.1, 0) + (-c.global_basis.z) * -0.4
			_slide_to(dev, Transform3D(Basis(Vector3.UP, global_rotation.y), tray_slot(_free_tray())), 0.4, true)
			_update_interactables()
		get_tree().create_timer(0.7).timeout.connect(func() -> void:
			if is_instance_valid(c) and c.state == "give":
				_go_wait(c)))

func _retry_arrive(c: Node3D) -> void:
	get_tree().create_timer(1.5).timeout.connect(func() -> void:
		if not is_instance_valid(c) or c.state != "enter":
			return
		if _counter_busy(c):
			_retry_arrive(c)
		else:
			c.walk([_g(COUNTER_SPOT)], func() -> void: _arrived(c)))

func _go_wait(c: Node3D) -> void:
	var spot: Array = WAIT_SPOTS[_next_spot % WAIT_SPOTS.size()]
	_next_spot += 1
	c.state = "wait"
	c.set_pose("walk")
	c.walk([_g(spot[0])], func() -> void:
		if is_instance_valid(c) and c.state == "wait":
			c.face(deg_to_rad(float(spot[1])) + global_rotation.y)
			c.set_pose(_idle_pose(c)))

func _idle_pose(c: Node) -> String:
	match str(c.look):
		"granny", "grandpa", "office":
			return "cross_arms"
		"influencer", "student", "kid", "punk":
			return "phone"
		_:
			return ["phone", "tap_foot", "cross_arms"][absi(hash(c.order_id)) % 3]

## Order left the list: paid -> take the device, cheer, leave; vanished -> angry exit.
func _finish_order(id: String, paid: bool) -> void:
	last_status.erase(id)
	var c: Node3D = customers.get(id)
	var dev: RigidBody3D = devices.get(id)
	customers.erase(id)
	devices.erase(id)
	if c == null or not is_instance_valid(c):
		if dev and is_instance_valid(dev):
			_vanish(dev)
		return
	c.state = "collect" if paid else "leave"
	if dev and is_instance_valid(dev):
		for p in get_tree().get_nodes_in_group("local_player"):
			if p.get("held") == dev and p.has_method("release_held"):
				p.release_held()
		dev.remove_from_group("interactable")
		dev.remove_from_group("grabbable")
		dev.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		dev.freeze = true
		dev.collision_layer = 0
		dev.collision_mask = 0
	if paid:
		c.walk([_g(COUNTER_SPOT)], func() -> void:
			if not is_instance_valid(c):
				return
			c.face(PI + global_rotation.y)
			c.set_pose("give")
			get_tree().create_timer(0.5).timeout.connect(func() -> void:
				if not is_instance_valid(c):
					return
				if dev and is_instance_valid(dev):
					c.hold(dev)
				c.set_pose("cheer")
				c.emote("♥", 2.5)
				_dialogue(c, "happy")
				Sfx.play("coin", c.global_position + Vector3(0, 1.2, 0), -6.0)
				get_tree().create_timer(1.6).timeout.connect(func() -> void: _leave(c, 1.35))))
	else:
		if dev and is_instance_valid(dev):
			c.hold(dev)
		c.set_pose("angry")
		c.emote("!!", 2.0)
		_dialogue(c, "angry")
		get_tree().create_timer(1.4).timeout.connect(func() -> void: _leave(c, 1.8))

func _leave(c: Node3D, spd: float) -> void:
	if not is_instance_valid(c):
		return
	c.state = "leave"
	var side := 1.0 if c.global_position.x > global_position.x - 1.0 else -1.0
	var path := [_g(Vector3(DOOR_LANE_X, 0, 2.7)), _g(Vector3(DOOR_LANE_X, 0, 4.3)), _g(Vector3(DOOR_LANE_X, 0, 7.3)), _g(Vector3(7.0 * side if side > 0 else -7.5, 0, 7.3))]
	c.walk(path, func() -> void:
		if is_instance_valid(c):
			c.vanish(), spd)

## Customer lines: the UI shows/speaks them (docs/REQUESTS.md): Bus.story_dialogue("customer:<customer>:<moment>").
func _dialogue(c: Node, moment: String) -> void:
	if c == null or not is_instance_valid(c):
		return
	c.talk(1.6)
	Bus.story_dialogue.emit("customer:%s:%s" % [str(c.customer), moment])

# ------------------------------------------------------------------ devices
func _spawn_device(o: Dictionary) -> RigidBody3D:
	var dev: RigidBody3D = Device.new()
	dev.setup(o)
	add_child(dev)
	devices[str(o.id)] = dev
	if not _lights_on:
		pass
	return dev

func _free_tray() -> int:
	var used := {}
	for d in devices.values():
		if is_instance_valid(d) and on_counter(d):
			var p: Vector3 = _counter_xf().affine_inverse() * d.global_position
			used[clampi(int(round((p.x + 0.66) / 0.24)), 0, 2)] = true
	for i in 3:
		if not used.has(i):
			return i
	return devices.size() % 3

## Where a device belongs for its status when nobody carries it (rebuild / join).
func _place_canonical(dev: RigidBody3D, st: String) -> void:
	if st == "inRepair":
		_snap(dev, false)
	else:
		dev.global_transform = Transform3D(Basis(Vector3.UP, global_rotation.y + randf_range(-0.2, 0.2)), tray_slot(_free_tray()))

func _slide_to(dev: RigidBody3D, xf: Transform3D, t: float, release: bool) -> void:
	dev.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	dev.freeze = true
	var tw := dev.create_tween()
	tw.set_parallel(true)
	tw.tween_property(dev, "global_position", xf.origin, t).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(dev, "global_basis", xf.basis, t)
	if release:
		tw.chain().tween_callback(func() -> void:
			if is_instance_valid(dev) and dev.place != "bench":
				dev.freeze = false
				Sfx.play("drop", dev.global_position, -10.0))

## Device into the bench holder (frozen, under the bench interactable so E there opens the repair).
func _snap(dev: RigidBody3D, animate: bool = true) -> void:
	if dev.place == "bench":
		return
	dev.place = "bench"
	for p in get_tree().get_nodes_in_group("local_player"):
		if p.get("held") == dev and p.has_method("release_held"):
			p.release_held()
	dev.set_interact("", "", false)
	var xf := holder.global_transform.translated_local(Vector3(0, dev.size.y * 0.5 + 0.004, 0))
	if dev.kind == "laptop":
		xf = holder.global_transform.translated_local(Vector3(0, 0.02, 0.05))
	dev.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	dev.freeze = true
	if dev.get_parent() != holder:
		var g := dev.global_transform
		dev.get_parent().remove_child(dev)
		holder.add_child(dev)
		dev.global_transform = g
	if animate:
		_slide_to(dev, xf, 0.3, false)
		Sfx.play("grab", dev.global_position, -8.0)
	else:
		dev.global_transform = xf

func _unsnap(dev: RigidBody3D) -> void:
	if dev.place != "bench":
		return
	dev.place = "free"
	var g := dev.global_transform
	if dev.get_parent() != self:
		dev.get_parent().remove_child(dev)
		add_child(dev)
	dev.global_transform = g.translated(Vector3(0, 0.05, 0))
	dev.freeze = false
	dev.apply_central_impulse(Vector3(0, 0.6, 0) * dev.mass)

func _vanish(dev: Node3D) -> void:
	var tw := dev.create_tween()
	tw.tween_property(dev, "scale", Vector3.ONE * 0.05, 0.3)
	tw.tween_callback(dev.queue_free)

## Interactable metadata on the counter, the bench and every device (by status + where the device lies).
func _update_interactables() -> void:
	var orders := Story.all_orders(Game.state)
	var counter_pick := ""
	var counter_prompt := ""
	var bench_pick := ""
	var bench_prompt := ""
	for id in devices:
		var dev: RigidBody3D = devices[id]
		if not is_instance_valid(dev):
			continue
		var o: Dictionary = HQ.dict(orders.get(id))
		var st := str(o.get("status", ""))
		var what := _what(o)
		if dev.place == "bench":
			dev.set_interact("", "", false)
			if st == "inRepair" and bench_pick == "":
				bench_pick = id
				bench_prompt = "Repair: %s" % what
			continue
		var here := on_counter(dev)
		match st:
			"waiting":
				dev.set_interact("counter", "Take the order: %s" % what, false)
				if here and counter_pick == "":
					counter_pick = id
					counter_prompt = "Take the order: %s" % what
			"inRepair":
				dev.set_interact("device", "Carry to the repair bench", true)
			"ready":
				if here:
					dev.set_interact("counter", "Hand it back & get paid", false)
					if counter_pick == "" or str(HQ.dict(orders.get(counter_pick)).get("status", "")) != "ready":
						counter_pick = id
						counter_prompt = "Hand it back & get paid"
				else:
					dev.set_interact("device", "Carry back to the counter", true)
			_:
				dev.set_interact("", "", false)
	if bench_pick == "":
		for o in Story.orders(Game.state):
			if str(o.get("status", "")) == "inRepair":
				bench_pick = str(o.id)
				bench_prompt = "Repair: %s" % _what(o)
				break
	counter_ia.set_meta("id", counter_pick)
	counter_ia.set_meta("prompt", counter_prompt if counter_pick != "" else "Counter")
	_set_ia(counter_ia, counter_pick != "")
	bench_ia.set_meta("id", bench_pick)
	bench_ia.set_meta("prompt", bench_prompt if bench_pick != "" else "Repair bench")
	_set_ia(bench_ia, bench_pick != "")

static func _what(o: Dictionary) -> String:
	var f := str(o.get("fault", ""))
	var d := str(o.get("device", ""))
	if f != "" and d != "":
		return "%s (%s)" % [f, d]
	return f if f != "" else (d if d != "" else "device")

# ================================================================== per frame
func _process(dt: float) -> void:
	_t += dt
	# buzzing neon letter
	if _sign_lit and _buzz_letter >= 0 and _buzz_letter < _sign_letters.size():
		var d: Dictionary = _sign_letters[_buzz_letter]
		var l: Label3D = d.l
		var on := not (fmod(_t * 7.3, 11.0) < 0.6 and sin(_t * 61.0) > 0.0) and not (fmod(_t, 9.0) > 8.6)
		var c: Color = d.col
		l.modulate = c.lerp(Color.WHITE, 0.55) * (2.6 if on else 0.35)
		l.outline_modulate = Color(c.r, c.g, c.b, 1.0) * (1.6 if on else 0.2)
		if not _sign_lights.is_empty() and is_instance_valid(_sign_lights[0]):
			(_sign_lights[0] as Light3D).light_energy = 1.5 if on else 1.25
	if decor_only:
		return
	_poll -= dt
	if _poll > 0.0:
		return
	_poll = 0.2
	# devices dropped on the bench mat while in repair snap into the holder; zones decide prompts
	var orders := Story.all_orders(Game.state)
	var dirty := false
	for id in devices:
		var dev: RigidBody3D = devices[id]
		if not is_instance_valid(dev) or dev.freeze or _player_holds(dev):
			continue
		var st := str(HQ.dict(orders.get(id)).get("status", ""))
		if st == "inRepair" and dev.place != "bench" and on_bench(dev) and dev.linear_velocity.length() < 0.6:
			_snap(dev)
			dirty = true
		var z := "counter" if on_counter(dev) else "free"
		if z != str(dev.get_meta("zone", "")):
			dev.set_meta("zone", z)
			dirty = true
		# fell out of the world
		if dev.global_position.y < global_position.y - 2.0:
			_place_canonical(dev, st)
	if dirty:
		_update_interactables()
	# bell: ding when picked up
	if bell and is_instance_valid(bell):
		var h := _player_holds(bell)
		if h and not _bell_held:
			ring_bell()
		_bell_held = h
	# patience: long waits make customers fidget
	for c in customers.values():
		if not is_instance_valid(c) or c.state != "wait" or c.is_walking():
			continue
		c.waited += 0.2
		if fmod(c.waited, 40.0) < 0.2 and c.waited > 30.0:
			c.emote("...", 2.0)
			c.set_pose("tap_foot")
			_dialogue(c, "wait")

# ================================================================== objective targets (world.story_stage)
## Nodes to highlight for a story step. Repair steps follow the live orders (what to do next).
func objective_targets(chapter: int, step: String) -> Array:
	var s := step.to_lower()
	if s.contains("supplier") or s.contains("buy") or s.contains("call") or s.contains("research") or s.contains("pattern") \
			or s.contains("intro") or s.contains("investor") or s.contains("seen") or s.contains("sign") or chapter >= 3 and not s.contains("repair"):
		if not (chapter == 0 and s.contains("intro") and not _door_open):
			return []
	if not _door_open and (s.contains("door") or s.contains("open") or chapter == 0 and not s.contains("light")):
		return [door_ia]
	if s.contains("light") or s.contains("switch") or (chapter == 0 and _door_open and not _lights_on):
		return [switch_ia]
	if chapter in [1, 2] or s.contains("repair") or s.contains("counter") or s.contains("customer") or s.contains("bench") \
			or s.contains("take") or s.contains("return") or s.contains("pay") or s.contains("fix") or s.contains("device"):
		return repair_targets()
	return []

## What to do next with the repair orders: take (counter) -> carry (device) -> repair (bench) -> carry back -> hand over.
func repair_targets() -> Array:
	var orders := Story.all_orders(Game.state)
	for want in ["ready", "inRepair", "waiting"]:
		for id in devices:
			var dev: RigidBody3D = devices[id]
			if not is_instance_valid(dev):
				continue
			var st := str(HQ.dict(orders.get(id)).get("status", ""))
			if st != want:
				continue
			match st:
				"ready":
					return [counter_ia] if on_counter(dev) else [dev]
				"inRepair":
					return [bench_ia] if dev.place == "bench" or _player_holds(dev) else [dev]
				"waiting":
					return [dev]
	for o in Story.orders(Game.state):
		if str(o.get("status", "")) == "inRepair":
			return [bench_ia]
	return [counter_ia] if not Story.orders(Game.state).is_empty() else []

## For tests / tools
func customer_count() -> int:
	var n := 0
	for c in customers.values():
		if is_instance_valid(c):
			n += 1
	return n
