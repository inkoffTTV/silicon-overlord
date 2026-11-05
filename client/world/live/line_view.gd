extends Node3D
## One upstairs production line (WORLD agent), built from a `production.lines[]` entry. Original machine design:
## parts bins -> conveyor through 1..3 boxy machines (count/size by line level) -> QC table -> open crate.
## Running job (production.jobs status "Running" on this line): belt rollers spin, phones in the product colour ride
## the belt through the machines and drop into the crate, sparks + steam, stack lights green, machine hum.
## Idle: amber, "IDLE". Blocked: amber blink + reason. Down (downUntilDay): red beacon.
## Local frame: the line runs along +Z from z=0 to z=length; belt top at y=BELT_Y; operator side = -X.
## Interactables: production_line (id = line id), line_qc (id = line id) with a "seat" (stand) spot.

const Mats := preload("res://world/lib/mats.gd")
const Meshes := preload("res://world/lib/meshes.gd")
const HQ := preload("res://world/live/hq_state.gd")
const BELT_Y := 0.82
const KIND_COL := {"Assembly": Color(0.2, 0.42, 0.45), "CPUFab": Color(0.18, 0.28, 0.55), "GPUFab": Color(0.42, 0.2, 0.5),
	"DisplayFab": Color(0.5, 0.36, 0.14), "BatteryFab": Color(0.25, 0.45, 0.2)}

var line: Dictionary = {}
var length := 4.6
var line_id := ""
var running := false
var status := "idle"
var product_col := Color(0.5, 0.5, 0.5)
var ia: StaticBody3D
var qc: StaticBody3D
var screen_label: Label3D
var lamps := {}          # "r"/"y"/"g" -> StandardMaterial3D
var rollers: Array[Node3D] = []
var phones: Array[MeshInstance3D] = []
var phone_mat: StandardMaterial3D
var machines: Array[Node3D] = []
var sparks: Array[CPUParticles3D] = []
var steam: Array[CPUParticles3D] = []
var arm: Node3D
var crate_fill: MeshInstance3D
var beacon: OmniLight3D
var _loops: Array = []
var _t := 0.0
var _phone_t := 0.0
var _beep_t := 0.0
var _fill := 0.0
var _progress := 0.0

func setup(l: Dictionary) -> void:
	line = l
	line_id = str(l.get("id", "line"))
	name = "Line_" + line_id.validate_node_name()

func _ready() -> void:
	_build()
	Bus.state_changed.connect(func(keys: Array) -> void:
		if keys.has("production") or keys.has("time") or keys.has("products"):
			refresh(Game.state))
	refresh(Game.state)

# ------------------------------------------------------------------ build
func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, bevel: float = 0.01, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = Meshes.cbox(size, bevel)
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot
	parent.add_child(mi)
	return mi

func _shape(body: CollisionObject3D, size: Vector3, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = pos
	body.add_child(cs)

func _lamp_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c * 0.3
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 0.2
	return m

func _build() -> void:
	var level := clampi(int(line.get("level", 1)), 1, 5)
	var kind := str(line.get("kind", "Assembly"))
	var mcol: Color = KIND_COL.get(kind, KIND_COL.Assembly)
	var mm := Mats.m("metal_green", Color.WHITE, {"albedo": mcol, "albedo2": mcol.darkened(0.3), "metallic_base": 0.35, "roughness_base": 0.45, "grime": 0.45, "edge_wear": 0.6})
	var frame := Mats.m("steel_dark")
	var yellow := Mats.m("metal_yellow")
	ia = StaticBody3D.new()
	ia.name = "IA_production_line"
	ia.add_to_group("interactable")
	ia.set_meta("kind", "production_line")
	ia.set_meta("id", line_id)
	ia.set_meta("prompt", "Production line %s" % line_id.replace("line_", "#"))
	add_child(ia)
	# conveyor
	_box(ia, Vector3(0.62, 0.06, length), Vector3(0, BELT_Y - 0.03, length * 0.5), Mats.m("rubber", Color(2.2, 2.2, 2.2)), 0.008)
	for sx in [-1.0, 1.0]:
		_box(ia, Vector3(0.05, 0.12, length + 0.1), Vector3(sx * 0.34, BELT_Y + 0.0, length * 0.5), yellow, 0.01)
	var nl := int(length / 1.1) + 1
	for i in nl:
		var z := 0.1 + i * (length - 0.2) / maxf(1.0, nl - 1)
		for sx in [-1.0, 1.0]:
			_box(ia, Vector3(0.05, BELT_Y - 0.05, 0.05), Vector3(sx * 0.3, (BELT_Y - 0.05) * 0.5, z), frame, 0.008)
		_box(ia, Vector3(0.6, 0.04, 0.04), Vector3(0, 0.15, z), frame, 0.006)
	for z in [0.03, length - 0.03]:
		var r := Node3D.new()
		r.position = Vector3(0, BELT_Y - 0.04, z)
		ia.add_child(r)
		var cy := MeshInstance3D.new()
		cy.mesh = Meshes.cyl(0.045, 0.64, 10)
		cy.material_override = Mats.m("metal")
		cy.rotation_degrees.z = 90
		r.add_child(cy)
		_box(r, Vector3(0.66, 0.012, 0.012), Vector3(0, 0.04, 0), Mats.m("plastic_black"), 0.0)
		rollers.append(r)
	_shape(ia, Vector3(0.75, BELT_Y + 0.06, length + 0.1), Vector3(0, (BELT_Y + 0.06) * 0.5, length * 0.5))
	# infeed parts bins
	var bin_cols := [Color(0.85, 0.25, 0.15), Color(0.15, 0.4, 0.8), Color(0.95, 0.75, 0.1)]
	for i in 3:
		_box(ia, Vector3(0.2, 0.14, 0.24), Vector3(-0.2 + i * 0.2, BELT_Y + 0.13, -0.18), Mats.m("plastic_white", bin_cols[i]), 0.015)
	_box(ia, Vector3(0.66, 0.06, 0.3), Vector3(0, BELT_Y + 0.03, -0.18), frame, 0.008)
	# machines
	var n := clampi(level, 1, 3)
	var msize := Vector3(1.0 + level * 0.06, 0.95 + level * 0.1, 0.62 + level * 0.05)
	for k in n:
		var z := length * (k + 1) / (n + 1)
		var m := Node3D.new()
		m.position = Vector3(0, 0, z)
		ia.add_child(m)
		machines.append(m)
		var hy := BELT_Y + 0.14
		var top_h := msize.y - (hy - 0.6)
		var H := msize.y + 0.6
		for sx in [-1.0, 1.0]:
			_box(m, Vector3((msize.x - 0.7) * 0.5, H, msize.z), Vector3(sx * (0.35 + (msize.x - 0.7) * 0.25), H * 0.5, 0), mm, 0.03)
		_box(m, Vector3(msize.x, top_h, msize.z), Vector3(0, hy + top_h * 0.5, 0), mm, 0.03)
		_box(m, Vector3(0.74, 0.04, msize.z + 0.02), Vector3(0, hy, 0), frame, 0.01)
		# hazard stripes at the tunnel mouth
		for sz in [-1.0, 1.0]:
			for i in 4:
				_box(m, Vector3(0.09, 0.03, 0.006), Vector3(-0.27 + i * 0.18, hy + 0.035, sz * (msize.z * 0.5 + 0.004)), Mats.m("metal_yellow") if i % 2 == 0 else Mats.m("plastic_black"), 0.0, Vector3(0, 0, 35))
		# vent + steam
		_box(m, Vector3(0.22, 0.12, 0.22), Vector3(0.2, hy + top_h + 0.06, -0.05), frame, 0.02)
		var st := _steam()
		st.position = Vector3(0.2, hy + top_h + 0.14, -0.05)
		m.add_child(st)
		steam.append(st)
		# side panel facing the operator (-X): screen + buttons
		var px := -msize.x * 0.5 - 0.004
		_box(m, Vector3(0.012, 0.3, 0.38), Vector3(px, hy + top_h * 0.45, 0), Mats.m("plastic_black"), 0.004)
		var scr := MeshInstance3D.new()
		scr.mesh = Meshes.quad(Vector2(0.34, 0.24))
		scr.material_override = Mats.screen(2, Color(0.4, 1.0, 0.6), 0.55, float(k) + float(hash(line_id) % 7))
		scr.position = Vector3(px - 0.007, hy + top_h * 0.45, 0)
		scr.rotation_degrees.y = -90
		m.add_child(scr)
		for i in 3:
			_box(m, Vector3(0.02, 0.035, 0.035), Vector3(px - 0.006, hy + top_h * 0.45 - 0.2, -0.08 + i * 0.08), Mats.glow([Color(0.2, 1.0, 0.3), Color(1.0, 0.8, 0.1), Color(1.0, 0.15, 0.1)][i], 1.5), 0.005)
		if k == 0:
			screen_label = Label3D.new()
			screen_label.font_size = 30
			screen_label.pixel_size = 0.00075
			screen_label.position = Vector3(px - 0.009, hy + top_h * 0.45 + 0.08, -0.15)
			screen_label.rotation_degrees.y = -90
			screen_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			screen_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
			screen_label.modulate = Color(0.7, 1.0, 0.8) * 2.0
			screen_label.font = _mono()
			m.add_child(screen_label)
			# stack light
			var pole := Vector3(msize.x * 0.5 - 0.1, hy + top_h, msize.z * 0.5 - 0.1)
			_box(m, Vector3(0.03, 0.18, 0.03), pole + Vector3(0, 0.09, 0), frame, 0.004)
			var cols := {"r": Color(1.0, 0.1, 0.05), "y": Color(1.0, 0.7, 0.05), "g": Color(0.2, 1.0, 0.3)}
			var y := 0.2
			for key in ["r", "y", "g"]:
				var lm := _lamp_mat(cols[key])
				var mi := MeshInstance3D.new()
				mi.mesh = Meshes.cyl(0.04, 0.06, 10)
				mi.material_override = lm
				mi.position = pole + Vector3(0, y + 0.03, 0)
				m.add_child(mi)
				lamps[key] = lm
				y += 0.065
			beacon = OmniLight3D.new()
			beacon.position = pole + Vector3(0, 0.4, 0)
			beacon.omni_range = 3.0
			beacon.light_energy = 0.0
			beacon.light_volumetric_fog_energy = 1.2
			m.add_child(beacon)
		# welding head with sparks under the tunnel exit
		var sp := _sparks()
		sp.position = Vector3(0.0, BELT_Y + 0.05, msize.z * 0.5 + 0.05)
		m.add_child(sp)
		sparks.append(sp)
		_shape(ia, Vector3(msize.x, H, msize.z), Vector3(0, H * 0.5, z))
	# pick & place arm at the infeed
	arm = Node3D.new()
	arm.position = Vector3(0.42, BELT_Y + 0.05, 0.25)
	ia.add_child(arm)
	var amat := Mats.m("metal_yellow", Color(1.05, 1.05, 1.05))
	_box(arm, Vector3(0.14, 0.1, 0.14), Vector3(0, 0.05, 0), frame, 0.02)
	var a1 := Node3D.new()
	a1.name = "A1"
	a1.position = Vector3(0, 0.1, 0)
	arm.add_child(a1)
	_box(a1, Vector3(0.06, 0.38, 0.06), Vector3(0, 0.19, 0), amat, 0.02)
	var a2 := Node3D.new()
	a2.name = "A2"
	a2.position = Vector3(0, 0.38, 0)
	a1.add_child(a2)
	_box(a2, Vector3(0.05, 0.05, 0.32), Vector3(0, 0, 0.0), amat, 0.015, Vector3(0, 90, 0))
	_box(a2, Vector3(0.04, 0.12, 0.04), Vector3(-0.16, -0.06, 0), frame, 0.01)
	# outfeed crate (open top) that fills up
	var crate := Node3D.new()
	crate.position = Vector3(0, 0, length + 0.38)
	ia.add_child(crate)
	var card := Mats.m("cardboard")
	_box(crate, Vector3(0.5, 0.02, 0.4), Vector3(0, 0.12, 0), card, 0.005)
	for sx in [-1.0, 1.0]:
		_box(crate, Vector3(0.02, 0.38, 0.4), Vector3(sx * 0.24, 0.3, 0), card, 0.005)
		_box(crate, Vector3(0.5, 0.38, 0.02), Vector3(0, 0.3, sx * 0.19), card, 0.005)
		_box(crate, Vector3(0.5, 0.012, 0.2), Vector3(0, 0.49, sx * 0.29), card, 0.004, Vector3(sx * 30.0, 0, 0))
	_box(crate, Vector3(0.6, 0.1, 0.5), Vector3(0, 0.05, 0), Mats.m("plywood"), 0.01)
	phone_mat = StandardMaterial3D.new()
	phone_mat.albedo_color = product_col
	phone_mat.roughness = 0.35
	crate_fill = _box(crate, Vector3(0.44, 0.02, 0.34), Vector3(0, 0.14, 0), phone_mat, 0.004)
	_shape(ia, Vector3(0.6, 0.5, 0.5), Vector3(0, 0.25, length + 0.38))
	# phones on the belt
	var scr_m := Mats.m("tv_black")
	for i in 10:
		var ph := MeshInstance3D.new()
		ph.mesh = Meshes.cbox(Vector3(0.078, 0.012, 0.158), 0.005)
		ph.material_override = phone_mat
		ph.visible = false
		ia.add_child(ph)
		var s := MeshInstance3D.new()
		s.mesh = Meshes.cbox(Vector3(0.068, 0.002, 0.14), 0.0)
		s.material_override = scr_m
		s.position = Vector3(0, 0.007, 0)
		ph.add_child(s)
		phones.append(ph)
	# QC station on the operator side by the outfeed
	qc = StaticBody3D.new()
	qc.name = "IA_line_qc"
	qc.add_to_group("interactable")
	qc.set_meta("kind", "line_qc")
	qc.set_meta("id", line_id)
	qc.set_meta("prompt", "QC inspection (challenge)")
	qc.position = Vector3(-0.85, 0, length - 0.3)
	add_child(qc)
	_box(qc, Vector3(0.7, 0.04, 0.55), Vector3(0, 0.88, 0), Mats.m("plywood"), 0.01)
	_box(qc, Vector3(0.62, 0.006, 0.45), Vector3(0, 0.903, 0), Mats.m("rubber", Color.WHITE, {"albedo": Color(0.08, 0.22, 0.24)}), 0.0)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box(qc, Vector3(0.04, 0.86, 0.04), Vector3(sx * 0.3, 0.43, sz * 0.23), frame, 0.006)
	_box(qc, Vector3(0.025, 0.5, 0.025), Vector3(0.28, 1.15, -0.2), frame, 0.005)
	var lampg := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.07
	tm.outer_radius = 0.095
	tm.rings = 16
	tm.ring_segments = 6
	lampg.mesh = tm
	lampg.material_override = Mats.glow(Color(0.9, 0.95, 1.0), 3.0)
	lampg.position = Vector3(0.15, 1.35, -0.1)
	lampg.rotation_degrees = Vector3(0, 0, 30)
	qc.add_child(lampg)
	var ql := SpotLight3D.new()
	ql.position = Vector3(0.12, 1.3, -0.08)
	ql.light_color = Color(0.9, 0.95, 1.0)
	ql.light_energy = 2.0
	ql.spot_range = 1.2
	ql.spot_angle = 40
	ql.rotation_degrees = Vector3(-90, 0, 0)
	qc.add_child(ql)
	for i in 3:
		var ph := _box(qc, Vector3(0.078, 0.012, 0.158), Vector3(-0.18 + i * 0.12, 0.912, 0.05), phone_mat, 0.005, Vector3(0, -10 + i * 12, 0))
		_box(ph, Vector3(0.068, 0.002, 0.14), Vector3(0, 0.007, 0), Mats.m("tv_black"), 0.0)
	var tag := Label3D.new()
	tag.text = "QC"
	tag.font_size = 72
	tag.pixel_size = 0.0018
	tag.modulate = Color(0.95, 0.85, 0.2)
	tag.shaded = true
	tag.position = Vector3(-0.351, 0.75, 0)
	tag.rotation_degrees.y = -90
	qc.add_child(tag)
	_shape(qc, Vector3(0.7, 0.92, 0.55), Vector3(0, 0.46, 0))
	# the player stands at the QC table looking down at the phones
	qc.set_meta("seat", {"pos": Vector3(-0.62, 0.0, 0.0), "yaw": -90.0, "eye": 1.5, "pitch": -45.0, "pose": "stand"})
	# sign above
	var sign := Label3D.new()
	sign.text = "%s · %s · LV%d" % [line_id.replace("line_", "LINE ").to_upper(), kind.to_upper(), level]
	sign.font_size = 64
	sign.pixel_size = 0.0022
	sign.modulate = Color(0.95, 0.85, 0.3)
	sign.position = Vector3(-0.38, 1.85, length * 0.5)
	sign.rotation_degrees.y = -90
	sign.shaded = true
	sign.double_sided = false
	if ResourceLoader.exists("res://ui/fonts/Inter-Bold.ttf"):
		sign.font = load("res://ui/fonts/Inter-Bold.ttf")
	ia.add_child(sign)
	var back := sign.duplicate() as Label3D
	back.rotation_degrees.y = 90
	back.position.x = 0.38
	ia.add_child(back)

## Operator spot for staff placement (global): {pos, yaw, pose}
func operator_slot() -> Dictionary:
	var p := global_transform * Vector3(-0.9, 0, length * 0.3)
	return {"pos": p, "yaw": global_rotation.y + PI * 0.5, "pose": "stand_assemble"}

# ------------------------------------------------------------------ state
func refresh(s: Dictionary) -> void:
	for l in HQ.lines(s):
		if str(l.get("id", "")) == line_id:
			line = l
	var job := HQ.line_job(s, line_id)
	var down := HQ.line_down(s, line)
	var st := "idle"
	if down:
		st = "down"
	elif not job.is_empty():
		st = "running" if str(job.get("status", "")) == "Running" else ("blocked" if str(job.get("status", "")) == "Blocked" else "queued")
	status = st
	var was := running
	running = st == "running"
	var pid := str(job.get("productId", ""))
	if pid != "":
		product_col = HQ.product_color(s, pid)
		phone_mat.albedo_color = product_col
	var q := maxf(1.0, float(job.get("quantity", 1)))
	_progress = clampf(float(job.get("produced", 0)) / q, 0.0, 1.0) if not job.is_empty() else 0.0
	var pname := HQ.product_name(s, pid) if pid != "" else ""
	if screen_label:
		var health := int(round(float(line.get("health", 1.0)) * 100.0))
		match st:
			"running":
				screen_label.text = "%s\nRUN  %d/%d\nHEALTH %d%%" % [pname.to_upper().substr(0, 14), int(job.get("produced", 0)), int(q), health]
			"blocked":
				screen_label.text = "BLOCKED\n%s\nHEALTH %d%%" % [str(job.get("blockedReason", "no parts")).substr(0, 16), health]
			"queued":
				screen_label.text = "QUEUED\n%s\nHEALTH %d%%" % [pname.to_upper().substr(0, 14), health]
			"down":
				screen_label.text = "!! DOWN !!\nREPAIR UNTIL\nDAY %d" % int(line.get("downUntilDay", 0))
			_:
				screen_label.text = "IDLE\nqueue a batch\nHEALTH %d%%" % health
	if running != was:
		_set_loops(running)
	for sp in sparks:
		sp.emitting = running
	for st2 in steam:
		st2.emitting = running or st == "down"

func _set_loops(on: bool) -> void:
	for l in _loops:
		if is_instance_valid(l):
			Sfx.stop_loop(l)
	_loops.clear()
	if on and machines.size() > 0:
		for nm in ["machine_hum", "conveyor"]:
			var h: Variant = Sfx.loop(nm, machines[0], -6.0) if Sfx.has_method("loop") else null
			if h is Node:
				_loops.append(h)

func _process(delta: float) -> void:
	_t += delta
	var blink := fmod(_t, 0.8) < 0.4
	if lamps.size() == 3:
		var r := 0.0
		var y := 0.0
		var g := 0.0
		match status:
			"running":
				g = 5.0
			"down":
				r = 6.0 if blink else 0.3
			"blocked":
				y = 5.0 if blink else 0.3
			_:
				y = 3.0
		(lamps.r as StandardMaterial3D).emission_energy_multiplier = r
		(lamps.y as StandardMaterial3D).emission_energy_multiplier = y
		(lamps.g as StandardMaterial3D).emission_energy_multiplier = g
	if beacon:
		beacon.light_color = Color(1.0, 0.15, 0.08) if status == "down" else Color(1.0, 0.7, 0.1)
		beacon.light_energy = (2.0 if blink else 0.0) if status in ["down", "blocked"] else 0.0
	_fill = lerpf(_fill, _progress, 1.0 - exp(-2.0 * delta))
	if crate_fill:
		crate_fill.position.y = 0.14 + _fill * 0.3
		crate_fill.visible = _fill > 0.02
	if not running:
		return
	for r in rollers:
		r.rotation.x += delta * 6.0
	for m in machines:
		m.position.y = sin(_t * 41.0 + m.position.z) * 0.002
	if arm:
		var a1: Node3D = arm.get_node("A1")
		a1.rotation.y = sin(_t * 1.6) * 1.2
		(a1.get_node("A2") as Node3D).rotation.z = 0.2 + sin(_t * 3.2) * 0.25
	# phones ride the belt
	var speed := 0.32
	var gap := length / phones.size()
	for i in phones.size():
		var z := fmod(_t * speed + i * gap, length + 0.45)
		var ph := phones[i]
		ph.visible = true
		if z < length:
			ph.position = Vector3(0.0, BELT_Y + 0.008, z)
			ph.rotation = Vector3.ZERO
		else:
			var k := (z - length) / 0.45
			ph.position = Vector3(0.0, BELT_Y + 0.008 - k * k * 0.5, length + k * 0.3)
			ph.rotation.x = k * 1.2
			ph.visible = k < 0.9
	_beep_t -= delta
	if _beep_t <= 0.0:
		_beep_t = gap / speed
		if machines.size() > 0:
			Sfx.play("machine_beep", machines[machines.size() - 1].global_position, -10.0)

static func _sparks() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 24
	p.lifetime = 0.5
	p.explosiveness = 0.3
	p.emitting = false
	p.direction = Vector3(0, 1, 0.4)
	p.spread = 60.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.6
	p.gravity = Vector3(0, -5.0, 0)
	var q := QuadMesh.new()
	q.size = Vector2(0.01, 0.01)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.8, 0.35)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	q.material = m
	p.mesh = q
	return p

static func _steam() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 10
	p.lifetime = 2.2
	p.emitting = false
	p.direction = Vector3(0, 1, 0)
	p.spread = 12.0
	p.initial_velocity_min = 0.25
	p.initial_velocity_max = 0.45
	p.gravity = Vector3(0, 0.05, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var c := Curve.new()
	c.add_point(Vector2(0, 0.4))
	c.add_point(Vector2(1, 1.6))
	p.scale_amount_curve = c
	var grad := Gradient.new()
	grad.set_color(0, Color(0.9, 0.92, 0.95, 0.35))
	grad.set_color(1, Color(0.9, 0.92, 0.95, 0.0))
	p.color_ramp = grad
	var q := QuadMesh.new()
	q.size = Vector2(0.18, 0.18)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	var puff := GradientTexture2D.new()
	puff.fill = GradientTexture2D.FILL_RADIAL
	puff.fill_from = Vector2(0.5, 0.5)
	puff.fill_to = Vector2(1.0, 0.5)
	puff.width = 32
	puff.height = 32
	var pg := Gradient.new()
	pg.set_color(0, Color(1, 1, 1, 1))
	pg.set_color(1, Color(1, 1, 1, 0))
	puff.gradient = pg
	m.albedo_texture = puff
	q.material = m
	p.mesh = q
	return p

static var _mono_font: Font
static func _mono() -> Font:
	if _mono_font == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["DejaVu Sans Mono", "Liberation Mono", "Courier New", "monospace"])
		_mono_font = f
	return _mono_font
