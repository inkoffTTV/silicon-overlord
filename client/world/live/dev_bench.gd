extends Node3D
## Prototype being built on the workbench (WORLD agent). One slot per project in `state.projects` (max 2).
## Local frame: origin on the bench top, x along the bench, +z toward the room, y up.
## Stages by progress: parts laid out (<30%) -> open shell with board + battery and the screen panel waiting
## (30..70%) -> the real phone (res://phone/phone_builder.gd, blueprint colours) on a holder with its screen on.
## Each slot has a little build monitor (name, %, day, bugs) and a soldering light that crackles while work goes on.

const Mats := preload("res://world/lib/mats.gd")
const Meshes := preload("res://world/lib/meshes.gd")
const HQ := preload("res://world/live/hq_state.gd")

var slot_x: Array = [-0.55, 0.45]
var slots: Array = []   # [{root, key, label, bar, light, sparks, pid}]
var _solder_t := 0.0

func _ready() -> void:
	for x in slot_x:
		var r := Node3D.new()
		r.position = Vector3(x, 0, 0)
		add_child(r)
		# cutting mat + build monitor (always there)
		_box(r, Vector3(0.5, 0.004, 0.34), Vector3(0, 0.002, 0.05), Mats.m("rubber", Color.WHITE, {"albedo": Color(0.1, 0.28, 0.2), "roughness_base": 0.8}))
		for i in 6:
			_box(r, Vector3(0.48, 0.001, 0.003), Vector3(0, 0.0045, -0.1 + i * 0.05), Mats.unlit(Color(0.35, 0.55, 0.45)))
		var mon := Node3D.new()
		mon.position = Vector3(0.0, 0, -0.24)
		r.add_child(mon)
		_box(mon, Vector3(0.12, 0.012, 0.08), Vector3(0, 0.006, 0), Mats.m("plastic_grey"))
		_box(mon, Vector3(0.02, 0.1, 0.02), Vector3(0, 0.06, -0.01), Mats.m("plastic_grey"))
		_box(mon, Vector3(0.3, 0.17, 0.025), Vector3(0, 0.19, 0), Mats.m("plastic_black"), 0.008)
		var scr := MeshInstance3D.new()
		scr.mesh = Meshes.quad(Vector2(0.28, 0.15))
		scr.material_override = Mats.screen(3, Color(0.2, 0.45, 0.35), 0.6, x)
		scr.position = Vector3(0, 0.19, 0.0128)
		mon.add_child(scr)
		var lbl := Label3D.new()
		lbl.font_size = 28
		lbl.pixel_size = 0.00072
		lbl.position = Vector3(-0.13, 0.255, 0.014)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		lbl.modulate = Color(0.6, 1.0, 0.75) * 1.8
		lbl.font = _mono()
		lbl.line_spacing = 2.0
		mon.add_child(lbl)
		var bar := _box(mon, Vector3(0.24, 0.012, 0.002), Vector3(-0.0, 0.135, 0.0135), Mats.glow(Color(0.4, 1.0, 0.55), 3.0), 0.0)
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.55, 0.2)
		light.light_energy = 0.0
		light.omni_range = 0.9
		light.position = Vector3(0.05, 0.06, 0.08)
		light.light_volumetric_fog_energy = 0.4
		r.add_child(light)
		var sp := _sparks()
		sp.position = Vector3(0.05, 0.02, 0.06)
		r.add_child(sp)
		var content := Node3D.new()
		content.name = "Content"
		r.add_child(content)
		slots.append({"root": r, "content": content, "key": "", "label": lbl, "bar": bar, "light": light, "sparks": sp, "progress": -1.0})
	Bus.state_changed.connect(_on_state)
	refresh(Game.state)

func _on_state(keys: Array) -> void:
	if keys.has("projects") or keys.has("products") or keys.has("blueprints") or keys.has("time"):
		refresh(Game.state)

func refresh(s: Dictionary) -> void:
	var projs := HQ.projects(s)
	for i in slots.size():
		var sl: Dictionary = slots[i]
		var p: Dictionary = projs[i] if i < projs.size() else {}
		var stage := -1
		if not p.is_empty():
			stage = 0 if p.progress < 0.3 else (1 if p.progress < 0.7 else 2)
		var key := "%s|%d" % [p.get("id", ""), stage]
		if key != sl.key:
			sl.key = key
			for c in sl.content.get_children():
				c.queue_free()
			if stage >= 0:
				_build_stage(sl.content, s, p, stage)
			else:
				_build_idle(sl.content)
		sl.progress = float(p.get("progress", -1.0))
		var lbl: Label3D = sl.label
		var bar: MeshInstance3D = sl.bar
		if p.is_empty():
			lbl.text = "BENCH %d\n\n-- free --\nnew design?" % (i + 1)
			bar.scale.x = 0.001
			bar.position.x = -0.12
		else:
			var pct := int(round(p.progress * 100.0))
			lbl.text = "%s\nDEV %d%%\nDAY %d/%d\nBUGS %d" % [str(p.name).to_upper().substr(0, 14), pct, p.day, p.totalDays, p.bugs]
			bar.scale.x = maxf(0.001, p.progress)
			bar.position.x = -0.12 + 0.12 * p.progress

func _process(delta: float) -> void:
	_solder_t -= delta
	var t := Time.get_ticks_msec() * 0.001
	for sl in slots:
		var active: bool = float(sl.progress) >= 0.0
		var light: OmniLight3D = sl.light
		var crackle := 0.0
		if active:
			crackle = 0.25 + 0.75 * maxf(0.0, sin(t * 13.0 + float(sl.root.position.x) * 7.0)) * (0.6 + 0.4 * sin(t * 47.0))
		light.light_energy = crackle * 0.6
		(sl.sparks as CPUParticles3D).emitting = active and fmod(t + float(sl.root.position.x) * 3.0, 4.0) < 1.2
	if _solder_t <= 0.0:
		_solder_t = randf_range(5.0, 11.0)
		for sl in slots:
			if float(sl.progress) >= 0.0:
				Sfx.play("solder", (sl.root as Node3D).global_position)
				break

# ------------------------------------------------------------------ visuals
func _build_idle(c: Node3D) -> void:
	# a sketch on paper + pencil: "next prototype?"
	_box(c, Vector3(0.21, 0.002, 0.297), Vector3(0, 0.006, 0.05), Mats.m("paper"), 0.0).rotation_degrees.y = 8
	var sk := Node3D.new()
	sk.position = Vector3(0, 0.0075, 0.05)
	sk.rotation_degrees.y = 8
	c.add_child(sk)
	for sx in [-1.0, 1.0]:
		_box(sk, Vector3(0.004, 0.001, 0.16), Vector3(sx * 0.04, 0, 0), Mats.unlit(Color(0.25, 0.25, 0.3)), 0.0)
		_box(sk, Vector3(0.08, 0.001, 0.004), Vector3(0, 0, sx * 0.08), Mats.unlit(Color(0.25, 0.25, 0.3)), 0.0)
	_box(c, Vector3(0.008, 0.008, 0.17), Vector3(0.14, 0.006, 0.08), Mats.m("metal_yellow"), 0.002).rotation_degrees.y = -30

func _build_stage(c: Node3D, s: Dictionary, p: Dictionary, stage: int) -> void:
	var col := HQ.product_color(s, str(p.productId))
	var shell_m := Mats.m("plastic_white", Color.WHITE, {"albedo": col, "albedo2": col.darkened(0.2), "roughness_base": 0.35, "grime": 0.1})
	var pcb_m := Mats.m("metal_green", Color(0.6, 1.6, 0.8), {"metallic_base": 0.1})
	match stage:
		0:
			# parts laid out on the mat: board with chips, battery, empty back shell, screws
			var pcb := _box(c, Vector3(0.065, 0.004, 0.13), Vector3(-0.09, 0.008, 0.06), pcb_m, 0.002)
			pcb.rotation_degrees.y = 12
			for i in 4:
				_box(pcb, Vector3(0.016 + (i % 2) * 0.01, 0.004, 0.016), Vector3(-0.015 + (i % 2) * 0.028, 0.004, -0.04 + i * 0.025), Mats.m("plastic_black"), 0.001)
			_box(c, Vector3(0.055, 0.006, 0.08), Vector3(0.0, 0.009, 0.12), Mats.m("plastic_black", Color(6, 6, 7)), 0.002)
			_box(c, Vector3(0.05, 0.002, 0.07), Vector3(0.0, 0.0125, 0.12), Mats.m("paper", Color(0.9, 0.85, 0.3)), 0.0)
			_shell(c, shell_m, Vector3(0.1, 0.008, 0.05), -6.0)
			for i in 5:
				_box(c, Vector3(0.004, 0.004, 0.004), Vector3(-0.02 + i * 0.012, 0.008, -0.03 + (i % 2) * 0.01), Mats.m("metal"), 0.0)
		1:
			var sh := _shell(c, shell_m, Vector3(-0.03, 0.008, 0.05), 4.0)
			_box(sh, Vector3(0.06, 0.004, 0.07), Vector3(0, 0.004, -0.03), pcb_m, 0.002)
			_box(sh, Vector3(0.058, 0.005, 0.07), Vector3(0, 0.004, 0.04), Mats.m("plastic_black", Color(6, 6, 7)), 0.002)
			# screen panel leaning on a little stand
			var st := Node3D.new()
			st.position = Vector3(0.12, 0.0, 0.02)
			st.rotation_degrees = Vector3(-70, -10, 0)
			c.add_child(st)
			_box(st, Vector3(0.07, 0.15, 0.004), Vector3(0, 0.075, 0), Mats.m("tv_black"), 0.002)
			_box(c, Vector3(0.09, 0.012, 0.03), Vector3(0.12, 0.006, 0.0), Mats.m("plastic_grey"), 0.003)
			# ribbon cable
			_box(c, Vector3(0.012, 0.001, 0.06), Vector3(0.06, 0.0095, 0.04), Mats.m("plastic_orange", Color(1.2, 0.9, 0.3)), 0.0).rotation_degrees.y = 60
		2:
			var m := HQ.phone_model(s, HQ.product(s, str(p.productId)), 0.1)
			var holder := Node3D.new()
			holder.position = Vector3(0, 0.0, 0.05)
			c.add_child(holder)
			_box(holder, Vector3(0.12, 0.02, 0.06), Vector3(0, 0.01, -0.02), Mats.m("plastic_black"), 0.006)
			if m:
				var tilt := Node3D.new()
				tilt.position = Vector3(0, 0.085, -0.01)
				tilt.rotation_degrees.x = -18
				holder.add_child(tilt)
				tilt.add_child(m)
			else:
				var sh := _shell(holder, shell_m, Vector3(0, 0.03, 0), 0.0)
				sh.rotation_degrees.x = -70
			# test probe clip + cable
			_box(c, Vector3(0.012, 0.012, 0.05), Vector3(0.1, 0.01, 0.1), Mats.m("plastic_white", Color(1.4, 0.3, 0.3)), 0.004).rotation_degrees.y = 40

func _shell(c: Node3D, mat: Material, pos: Vector3, rot_y: float) -> Node3D:
	var sh := Node3D.new()
	sh.position = pos
	sh.rotation_degrees.y = rot_y
	c.add_child(sh)
	var w := 0.075
	var l := 0.155
	_box(sh, Vector3(w, 0.003, l), Vector3(0, 0.0015, 0), mat, 0.001)
	for sx in [-1.0, 1.0]:
		_box(sh, Vector3(0.004, 0.009, l), Vector3(sx * (w * 0.5 - 0.002), 0.005, 0), mat, 0.001)
		_box(sh, Vector3(w, 0.009, 0.004), Vector3(0, 0.005, sx * (l * 0.5 - 0.002)), mat, 0.001)
	return sh

func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, bevel: float = 0.004) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = Meshes.cbox(size, bevel)
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if size.y < 0.02 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi

static func _sparks() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 14
	p.lifetime = 0.45
	p.explosiveness = 0.6
	p.emitting = false
	p.direction = Vector3(0, 1, 0)
	p.spread = 70.0
	p.initial_velocity_min = 0.4
	p.initial_velocity_max = 1.1
	p.gravity = Vector3(0, -4.0, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var q := QuadMesh.new()
	q.size = Vector2(0.006, 0.006)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.75, 0.3)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.emission_enabled = true
	q.material = m
	p.mesh = q
	p.color = Color(1.0, 0.8, 0.4)
	return p

static var _mono_font: Font
static func _mono() -> Font:
	if _mono_font == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["DejaVu Sans Mono", "Liberation Mono", "Courier New", "monospace"])
		_mono_font = f
	return _mono_font
