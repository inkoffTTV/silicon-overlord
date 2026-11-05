extends Node3D
## Hand-assembly bench = the garage line (`production.lines[]` with location "garage" / bench:true, usually line_1).
## Child of the assembly table interactable (local: top at y=TOP, +Z = front). While a batch runs: a phone in the
## product colour turns under the magnifier, finished phones pile up in the tray, the soldering iron sparks, and the
## little status screen shows product + produced/quantity. Adds the `line_qc` QC table at the right end.
## The bench line has a production process too (hand / semi / robotic / smart, `line.process`): a small benchtop kit
## shows it (`kit`, rebuilt when the process changes) — a pneumatic press for semi, a desktop robot arm for robotic,
## arm + blue vision camera for smart — and the status screen names the process (RETOOLING while it is switched).

const Mats := preload("res://world/lib/mats.gd")
const Meshes := preload("res://world/lib/meshes.gd")
const HQ := preload("res://world/live/hq_state.gd")
const LineView := preload("res://world/live/line_view.gd")
const TOP := 0.9

var table_w := 1.8
var line_id := "line_1"
var running := false
var lcd: Label3D
var tray_phones: Array[MeshInstance3D] = []
var wip: Node3D
var phone_mat: StandardMaterial3D
var sparks: CPUParticles3D
var qc: StaticBody3D
var _t := 0.0
var _snd := 3.0
var process := ""            # "" until the first refresh; "hand" | "semi" | "robotic" | "smart"
var retooling := false
var kit: Node3D              # process kit on the bench top (back middle, between the iron and the parts tray)
var _press_head: Node3D
var _arm: Node3D             # Base > Shoulder > Elbow
var _cam_glow: OmniLight3D

const PROCESS_TAG := {"hand": "HAND", "semi": "SEMI-AUTO", "robotic": "ROBOTIC", "smart": "SMART CELL"}

func _ready() -> void:
	phone_mat = StandardMaterial3D.new()
	phone_mat.albedo_color = Color(0.3, 0.3, 0.32)
	phone_mat.roughness = 0.35
	# status screen hanging under the top shelf
	var scr_root := Node3D.new()
	scr_root.position = Vector3(-0.15, TOP + 0.47, -0.1)
	scr_root.rotation_degrees.x = -12
	add_child(scr_root)
	_box(scr_root, Vector3(0.36, 0.17, 0.03), Vector3.ZERO, Mats.m("plastic_black"), 0.008)
	var scr := MeshInstance3D.new()
	scr.mesh = Meshes.quad(Vector2(0.33, 0.14))
	scr.material_override = Mats.screen(3, Color(0.3, 0.6, 0.45), 0.5, 3.0)
	scr.position = Vector3(0, 0, 0.0155)
	scr_root.add_child(scr)
	lcd = Label3D.new()
	lcd.font_size = 30
	lcd.pixel_size = 0.00078
	lcd.position = Vector3(-0.155, 0.06, 0.017)
	lcd.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lcd.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	lcd.modulate = Color(0.7, 1.0, 0.8) * 2.0
	lcd.font = LineView._mono()
	scr_root.add_child(lcd)
	# finished tray (right) — phones appear as the batch progresses
	var tray := Node3D.new()
	tray.position = Vector3(0.3, TOP, 0.2)
	add_child(tray)
	_box(tray, Vector3(0.46, 0.025, 0.3), Vector3(0, 0.0125, 0), Mats.m("plastic_grey", Color(1.4, 1.4, 1.5)), 0.006)
	var scr_m := Mats.m("tv_black")
	for i in 12:
		var ph := _box(tray, Vector3(0.075, 0.011, 0.15), Vector3(-0.17 + (i % 6) * 0.068, 0.031 + (i / 6) * 0.012, -0.0 + (i / 6) * 0.02), phone_mat, 0.004)
		_box(ph, Vector3(0.066, 0.002, 0.135), Vector3(0, 0.0065, 0), scr_m, 0.0)
		ph.rotation_degrees.y = sin(i * 2.3) * 4.0
		ph.visible = false
		tray_phones.append(ph)
	# work in progress under the magnifier (assembly_table has the magnifier at x=0.65, z=-0.2)
	wip = Node3D.new()
	wip.position = Vector3(0.57, TOP + 0.012, -0.12)
	add_child(wip)
	var wp := _box(wip, Vector3(0.075, 0.011, 0.15), Vector3.ZERO, phone_mat, 0.004)
	_box(wp, Vector3(0.06, 0.003, 0.07), Vector3(0, 0.006, -0.03), Mats.m("metal_green", Color(0.6, 1.6, 0.8)), 0.001)
	sparks = preload("res://world/live/dev_bench.gd")._sparks()
	sparks.position = Vector3(-0.45, TOP + 0.05, -0.2)
	add_child(sparks)
	_build_qc()
	Bus.state_changed.connect(func(keys: Array) -> void:
		if keys.has("production") or keys.has("products") or keys.has("time"):
			refresh(Game.state))
	refresh(Game.state)

func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, bevel: float = 0.005) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = Meshes.cbox(size, bevel)
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi

func _build_qc() -> void:
	qc = StaticBody3D.new()
	qc.name = "IA_line_qc"
	qc.add_to_group("interactable")
	qc.set_meta("kind", "line_qc")
	qc.set_meta("id", line_id)
	qc.set_meta("prompt", "QC inspection (challenge)")
	qc.position = Vector3(table_w * 0.5 + 0.3, 0, 0.0)
	add_child(qc)
	var frame := Mats.m("steel_dark")
	_box(qc, Vector3(0.5, 0.04, 0.6), Vector3(0, 0.86, 0), Mats.m("plywood"), 0.01)
	_box(qc, Vector3(0.44, 0.006, 0.5), Vector3(0, 0.883, 0), Mats.m("rubber", Color.WHITE, {"albedo": Color(0.85, 0.85, 0.82), "roughness_base": 0.6}), 0.0)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box(qc, Vector3(0.04, 0.84, 0.04), Vector3(sx * 0.21, 0.42, sz * 0.26), frame, 0.006)
	# ring lamp + "QC" placard + magnifying loupe
	_box(qc, Vector3(0.025, 0.55, 0.025), Vector3(-0.18, 1.15, -0.24), frame, 0.005)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.08
	tm.outer_radius = 0.105
	tm.rings = 16
	tm.ring_segments = 6
	ring.mesh = tm
	ring.material_override = Mats.glow(Color(0.92, 0.96, 1.0), 3.5)
	ring.position = Vector3(-0.08, 1.38, -0.12)
	ring.rotation_degrees = Vector3(20, 0, 0)
	qc.add_child(ring)
	var l := SpotLight3D.new()
	l.position = Vector3(-0.08, 1.34, -0.1)
	l.rotation_degrees = Vector3(-90, 0, 0)
	l.light_color = Color(0.92, 0.96, 1.0)
	l.light_energy = 1.6
	l.spot_range = 1.0
	l.spot_angle = 45.0
	l.light_volumetric_fog_energy = 0.4
	qc.add_child(l)
	var tag := Label3D.new()
	tag.text = "QC"
	tag.font_size = 72
	tag.pixel_size = 0.0016
	tag.modulate = Color(0.95, 0.85, 0.2)
	tag.shaded = true
	tag.position = Vector3(0, 0.75, 0.301)
	if ResourceLoader.exists("res://ui/fonts/Inter-Bold.ttf"):
		tag.font = load("res://ui/fonts/Inter-Bold.ttf")
	qc.add_child(tag)
	for i in 3:
		var ph := _box(qc, Vector3(0.075, 0.011, 0.15), Vector3(-0.1 + i * 0.1, 0.892, 0.05), phone_mat, 0.004)
		ph.rotation_degrees.y = -12 + i * 11
		_box(ph, Vector3(0.066, 0.002, 0.135), Vector3(0, 0.0065, 0), Mats.m("tv_black"), 0.0)
	_box(qc, Vector3(0.04, 0.04, 0.06), Vector3(0.15, 0.9, -0.15), Mats.m("plastic_black"), 0.01)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.5, 0.9, 0.6)
	cs.shape = bs
	cs.position = Vector3(0, 0.45, 0)
	qc.add_child(cs)
	# stand at the right end of the table, looking down at the phones
	qc.set_meta("seat", {"pos": Vector3(0.62, 0.0, 0.05), "yaw": 90.0, "eye": 1.5, "pitch": -48.0, "pose": "stand"})

func refresh(s: Dictionary) -> void:
	var bl := HQ.bench_line(s)
	if not bl.is_empty():
		line_id = str(bl.get("id", line_id))
		qc.set_meta("id", line_id)
	var pr := str(bl.get("process", "hand"))
	if not pr in PROCESS_TAG:
		pr = "hand"
	if pr != process:
		process = pr
		_build_kit()
	retooling = float(bl.get("processUntil", 0)) > float(HQ.elapsed_days(s)) and not bl.is_empty()
	var job := HQ.line_job(s, line_id)
	running = str(job.get("status", "")) == "Running"
	var pid := str(job.get("productId", ""))
	if pid != "":
		phone_mat.albedo_color = HQ.product_color(s, pid)
	var q := maxf(1.0, float(job.get("quantity", 1)))
	var prog := clampf(float(job.get("produced", 0)) / q, 0.0, 1.0) if not job.is_empty() else 0.0
	var shown := int(ceil(prog * tray_phones.size())) if running else 0
	for i in tray_phones.size():
		tray_phones[i].visible = i < shown
	wip.visible = not job.is_empty()
	sparks.emitting = running
	var head := "BENCH · %s" % PROCESS_TAG[process]
	if retooling:
		running = false
		sparks.emitting = false
		lcd.text = "RETOOLING\n→ %s\nUNTIL DAY %d" % [PROCESS_TAG[process], int(bl.get("processUntil", 0))]
	elif job.is_empty():
		lcd.text = "%s\nIDLE\nqueue a batch" % head
	else:
		lcd.text = "%s\n%s %s\n%d / %d" % [head, str(job.get("status", "")).to_upper(),
			HQ.product_name(s, pid).to_upper().substr(0, 12), int(job.get("produced", 0)), int(q)]

## Benchtop kit for the bench line's process (hand = nothing extra: the iron + magnifier already are the tools).
func _build_kit() -> void:
	if kit:
		kit.queue_free()
	kit = Node3D.new()
	kit.name = "ProcessKit_" + process
	kit.position = Vector3(-0.16, TOP, -0.22)
	add_child(kit)
	_press_head = null
	_arm = null
	_cam_glow = null
	var dark := Mats.m("steel_dark")
	var orange := Mats.m("plastic_orange", Color(1.15, 1.0, 0.9), {"roughness_base": 0.35})
	match process:
		"semi":
			# pneumatic benchtop press: base plate, back column, yellow head that stamps an orange jig
			_box(kit, Vector3(0.22, 0.02, 0.17), Vector3(0, 0.01, 0), dark, 0.004)
			var jig := _box(kit, Vector3(0.12, 0.016, 0.1), Vector3(0, 0.028, 0.02), Mats.m("plastic_white", Color(0.95, 0.55, 0.12)), 0.004)
			_box(jig, Vector3(0.045, 0.005, 0.08), Vector3(0, 0.01, 0), Mats.m("plastic_black"), 0.0)
			_box(kit, Vector3(0.035, 0.3, 0.035), Vector3(0, 0.16, -0.06), dark, 0.005)
			_box(kit, Vector3(0.05, 0.04, 0.11), Vector3(0, 0.29, -0.025), Mats.m("metal_yellow"), 0.006)
			_press_head = Node3D.new()
			_press_head.position = Vector3(0, 0.2, 0.02)
			kit.add_child(_press_head)
			_box(_press_head, Vector3(0.05, 0.1, 0.05), Vector3(0, 0.02, 0), Mats.m("metal"), 0.006)
			_box(_press_head, Vector3(0.08, 0.016, 0.07), Vector3(0, -0.035, 0), Mats.m("metal_yellow"), 0.004)
			for sx in [-1.0, 1.0]:
				var b := MeshInstance3D.new()
				b.mesh = Meshes.cyl(0.013, 0.02, 8)
				b.material_override = Mats.m("plastic_white", Color(0.9, 0.15, 0.1) if sx < 0 else Color(0.15, 0.7, 0.2))
				b.position = Vector3(sx * 0.08, 0.03, 0.065)
				kit.add_child(b)
		"robotic", "smart":
			# desktop robot arm on a dark plinth
			_box(kit, Vector3(0.14, 0.04, 0.14), Vector3(0, 0.02, -0.01), dark, 0.008)
			_arm = Node3D.new()
			_arm.name = "Base"
			_arm.position = Vector3(0, 0.04, -0.01)
			kit.add_child(_arm)
			var bc := MeshInstance3D.new()
			bc.mesh = Meshes.cyl(0.045, 0.04, 14)
			bc.material_override = orange
			bc.position = Vector3(0, 0.02, 0)
			_arm.add_child(bc)
			var sh := Node3D.new()
			sh.name = "Shoulder"
			sh.position = Vector3(0, 0.045, 0)
			_arm.add_child(sh)
			_box(sh, Vector3(0.035, 0.16, 0.04), Vector3(0, 0.08, 0), orange, 0.01)
			var el := Node3D.new()
			el.name = "Elbow"
			el.position = Vector3(0, 0.16, 0)
			sh.add_child(el)
			var ec := MeshInstance3D.new()
			ec.mesh = Meshes.cyl(0.025, 0.05, 10)
			ec.material_override = dark
			ec.rotation_degrees.z = 90
			el.add_child(ec)
			_box(el, Vector3(0.03, 0.03, 0.14), Vector3(0, 0, 0.07), orange, 0.008)
			var wr := _box(el, Vector3(0.026, 0.045, 0.026), Vector3(0, -0.02, 0.145), dark, 0.005)
			var led := MeshInstance3D.new()
			led.mesh = Meshes.sphere(0.006, 6)
			led.material_override = Mats.glow(Color(0.3, 1.0, 0.4), 4.0)
			led.position = Vector3(0, 0.026, 0)
			wr.add_child(led)
			sh.rotation.x = 0.35
			el.rotation.x = 0.7
			if process == "smart":
				# vision camera on a gooseneck looking down at the work + blue glow
				_box(kit, Vector3(0.015, 0.3, 0.015), Vector3(0.12, 0.15, -0.06), dark, 0.004)
				_box(kit, Vector3(0.06, 0.015, 0.015), Vector3(0.095, 0.3, -0.06), dark, 0.004)
				var cam := MeshInstance3D.new()
				cam.mesh = Meshes.cyl(0.02, 0.05, 12)
				cam.material_override = Mats.m("plastic_black")
				cam.position = Vector3(0.065, 0.28, -0.06)
				kit.add_child(cam)
				var ring := MeshInstance3D.new()
				ring.mesh = Meshes.cyl(0.024, 0.004, 14)
				ring.material_override = Mats.glow(Color(0.25, 0.55, 1.0), 8.0)
				ring.position = Vector3(0.065, 0.253, -0.06)
				kit.add_child(ring)
				_cam_glow = OmniLight3D.new()
				_cam_glow.position = Vector3(0.065, 0.2, -0.02)
				_cam_glow.light_color = Color(0.3, 0.55, 1.0)
				_cam_glow.light_energy = 0.6
				_cam_glow.omni_range = 0.7
				_cam_glow.light_volumetric_fog_energy = 0.6
				kit.add_child(_cam_glow)

func _process(delta: float) -> void:
	_t += delta
	if _cam_glow:
		_cam_glow.light_energy = 0.6 + (0.25 * sin(_t * 3.0) if running else 0.0)
	if running and _press_head:
		_press_head.position.y = 0.2 - maxf(0.0, sin(_t * 3.0)) * 0.1
	if running and _arm:
		var c := _t * 1.6
		_arm.rotation.y = sin(c) * 0.8
		var shd := _arm.get_node("Shoulder") as Node3D
		shd.rotation.x = 0.35 + sin(c * 2.0) * 0.2
		(shd.get_node("Elbow") as Node3D).rotation.x = 0.7 + cos(c * 2.0) * 0.25
	if running and wip:
		wip.rotation.y = sin(_t * 0.7) * 0.6
		_snd -= delta
		if _snd <= 0.0:
			_snd = randf_range(6.0, 12.0)
			Sfx.play("solder", global_position + Vector3(-0.45, TOP, -0.2), -6.0)
