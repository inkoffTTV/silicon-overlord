extends SceneTree
## Iteration-2 screenshots (WORLD agent): loads main.tscn with a rich fake company state (sample_state.json +
## projects, crates, lines, staff), hides the UI and captures the new world features.
##   xvfb-run -a -s "-screen 0 1600x900x24" <godot> --path client -s res://tools/shot_iter2.gd -- --shots=all
## --shots=all|supplies,build,whiteboard,loft,van,van_fp,staff,avatars,avatar_close,crate_fp,locked,seat,jobs,shelf,office
## --frames=N (default 40) --out=tools/shots

const HQ := preload("res://world/live/hq_state.gd")

var args := {}
var game: Node
var bus: Node
var world: Node
var player: Node
var out := ""
var frames := 40

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var s: String = a.trim_prefix("--")
		var i := s.find("=")
		if i >= 0:
			args[s.substr(0, i)] = s.substr(i + 1)
		else:
			args[s] = "1"
	_run.call_deferred()

static func fake_state(locked: bool = false) -> Dictionary:
	var f := FileAccess.open("res://ui/data/sample_state.json", FileAccess.READ)
	var s: Dictionary = JSON.parse_string(f.get_as_text())
	s["name"] = "Nebula Labs"
	# second blueprint/product in development
	var bp2: Dictionary = (s.blueprints["bp_84_5"] as Dictionary).duplicate(true)
	bp2["id"] = "bp_90_9"
	bp2["name"] = "Nebula Pro"
	bp2.options["bodyColorHex"] = "#E3A33A"
	s.blueprints["bp_90_9"] = bp2
	var p2: Dictionary = (s.products["prod_84_6"] as Dictionary).duplicate(true)
	p2["id"] = "prod_90_10"
	p2["name"] = "Nebula Pro"
	p2["blueprintId"] = "bp_90_9"
	s.products["prod_90_10"] = p2
	s.projects["proj_84_7"]["day"] = 25
	s.projects["proj_90_11"] = {"id": "proj_90_11", "name": "Nebula Pro", "productId": "prod_90_10", "blueprintId": "bp_90_9",
		"day": 6, "totalDays": 30, "bugs": 2, "toughBugs": 1}
	# production: bench + two upstairs lines, jobs, crates
	var prod: Dictionary = s.production
	var l1: Dictionary = (prod.lines[0] as Dictionary).duplicate(true)
	l1["location"] = "garage"
	l1["bench"] = true
	var l2 := l1.duplicate(true)
	l2["id"] = "line_2"
	l2["location"] = "upstairs"
	l2.erase("bench")
	var l3 := l2.duplicate(true)
	l3["id"] = "line_3"
	l3["level"] = 2
	prod["lines"] = [l1, l2, l3] if not locked else [l1]
	prod["jobs"] = [
		{"id": "job_a", "lineId": "line_1", "productId": "prod_20_2", "quantity": 200, "produced": 120, "status": "Running"},
		{"id": "job_b", "lineId": "line_2", "productId": "prod_84_6", "quantity": 1000, "produced": 380, "status": "Running"},
		{"id": "job_c", "lineId": "line_3", "productId": "prod_20_2", "quantity": 500, "produced": 40, "status": "Blocked", "blockedReason": "no displays"},
	]
	prod["crates"] = [
		{"id": "crate_88_1", "productId": "prod_20_2", "units": 250, "day": 88},
		{"id": "crate_89_2", "productId": "prod_20_2", "units": 180, "day": 89},
		{"id": "crate_90_3", "productId": "prod_84_6", "units": 1200, "day": 90},
		{"id": "crate_91_4", "productId": "prod_84_6", "units": 940, "day": 91},
		{"id": "crate_92_5", "productId": "prod_20_2", "units": 75, "day": 92},
	]
	if locked:
		(s.hq.rooms as Dictionary).erase("AssemblyLine")
	# more staff (station derived from role like the server does)
	var extra := [["Lena Ortiz", "Researcher"], ["Sam Park", "Marketer"], ["Ivo Brandt", "QCEngineer"], ["Ana Silva", "FinancialAnalyst"], ["Yuki Mori", "HardwareEngineer"]]
	var i := 0
	for e in extra:
		s.employees.list.append({"id": "emp_x_%d" % i, "name": e[0], "role": e[1], "skill": 0.5, "experience": 0.3, "satisfaction": 0.7, "salaryMonthly": 9000, "hiredDay": 50})
		i += 1
	for e in s.employees.list:
		e["station"] = HQ.ROLE_STATION.get(e.role, "office")
	return s

func _out() -> String:
	var o: String = args.get("out", "tools/shots")
	if not o.is_absolute_path():
		o = ProjectSettings.globalize_path("res://").path_join(o)
	DirAccess.make_dir_recursive_absolute(o)
	return o

func _wait(n: int) -> void:
	for i in n:
		await process_frame

func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var p := out.path_join("iter2_%s.png" % name)
	img.save_png(p)
	print("[shot] saved ", p)

func _vp(name: String) -> Node3D:
	for v in get_nodes_in_group("viewpoint"):
		if str(v.get_meta("vp_name", "")) == name and v.is_inside_tree():
			return v
	return null

func _cam_at(cam: Camera3D, xf: Transform3D, fov: float) -> void:
	cam.global_transform = xf
	cam.fov = fov
	cam.make_current()

func _look(cam: Camera3D, from: Vector3, to: Vector3, fov: float) -> void:
	_cam_at(cam, Transform3D(Basis.looking_at(to - from, Vector3.UP), from), fov)

func _run() -> void:
	out = _out()
	frames = int(args.get("frames", "40"))
	game = root.get_node("/root/Game")
	bus = root.get_node("/root/Bus")
	var net := root.get_node("/root/Net")
	var want: String = args.get("shots", "all")
	var shots := ["supplies", "build", "whiteboard", "loft", "van", "van_fp", "staff", "avatars", "avatar_close", "crate_fp", "seat", "jobs", "shelf", "locked", "office"] if want == "all" else Array(want.split(","))
	game.me = {"userId": 1, "name": "You"}
	game.state = fake_state(shots == ["locked"])
	# fake server for shipCrate: remove the crate, report units
	net.mock_handler = func(action: String, a: Dictionary) -> Dictionary:
		if action == "shipCrate":
			var prod: Dictionary = game.state.production
			var keep := []
			var units := 0
			for c in prod.crates:
				if c.id == a.get("crateId"):
					units = int(c.units)
				else:
					keep.append(c)
			prod["crates"] = keep
			game.apply_sections({"production": prod})
			return {"ok": true, "data": {"crateId": a.get("crateId"), "units": int(units * 1.05), "bonusUnits": int(units * 0.05)}}
		return {"ok": true}
	var main: Node = load("res://main.tscn").instantiate()
	root.add_child(main)
	await _wait(6)
	var ui := main.get_node_or_null("UI")
	if ui:
		ui.visible = false
	bus.ui_modal_changed.emit(false)
	world = get_first_node_in_group("world")
	player = get_first_node_in_group("local_player")
	if args.has("quality"):
		world.apply_quality(args["quality"])
	await _wait(10)
	var cam := Camera3D.new()
	cam.near = 0.03
	root.add_child(cam)
	for sh in shots:
		await _shot(str(sh), cam)
	quit(0)

func _peers(list: Array) -> void:
	bus.peers_changed.emit(list)

func _shot(name: String, cam: Camera3D) -> void:
	var lv: Node3D = world.get_level()
	match name:
		"supplies":
			var vp := _vp("supplies")
			_cam_at(cam, vp.global_transform, float(vp.get_meta("fov", 64.0)))
			await _wait(frames)
			await _save("supplier_phone")
		"build", "whiteboard", "staff", "jobs":
			var vp := _vp(name)
			_cam_at(cam, vp.global_transform, float(vp.get_meta("fov", 70.0)))
			await _wait(frames)
			await _save(name)
		"shelf":
			_look(cam, lv.to_global(Vector3(-0.45, 1.25, -1.9)), lv.to_global(Vector3(-0.45, 1.0, -3.4)), 62.0)
			await _wait(frames)
			await _save(name)
		"loft":
			var vp := _vp("loft")
			_cam_at(cam, vp.global_transform, 76.0)
			await _wait(frames + 30)
			await _save("loft_running")
			_look(cam, lv.to_global(Vector3(-1.9, 4.75, 2.6)), lv.to_global(Vector3(-0.3, 3.9, -0.6)), 70.0)
			await _wait(frames)
			await _save("loft_lines")
		"locked":
			var vp := _vp("hatch")
			_cam_at(cam, vp.global_transform, 72.0)
			await _wait(frames)
			await _save("stairs_locked")
		"van":
			var vp := _vp("van")
			_cam_at(cam, vp.global_transform, 72.0)
			await _wait(frames)
			await _save("van")
			# ship one crate: drop it into the cargo area
			var sh: Node = lv.get("shipping")
			var c: RigidBody3D = sh.crate_nodes()[0]
			c.global_position = lv.dock.global_transform * Vector3(0, 1.0, 0.5)
			await _wait(14)
			await _save("van_shipping")
			await _wait(frames)
		"van_fp", "crate_fp":
			var sh: Node = lv.get("shipping")
			var nodes: Array = sh.crate_nodes()
			if nodes.is_empty():
				return
			var c: RigidBody3D = nodes[nodes.size() - 1]
			cam.current = false
			player.make_camera_current()
			player.global_position = c.global_position + Vector3(1.0, -c.global_position.y + 0.02, -0.9)
			await _wait(4)
			var d: Vector3 = c.global_position - player.cam.global_position
			player.set_look(atan2(-d.x, -d.z), atan2(d.y, Vector2(d.x, d.z).length()))
			await _wait(3)
			player.try_grab()
			# walk toward the van
			var tgt: Vector3 = lv.dock.global_transform * Vector3(0, 0, -1.6)
			player.global_position = Vector3(tgt.x + 0.2, 0.03, tgt.z - 1.4)
			var dd: Vector3 = lv.dock.global_transform * Vector3(0, 1.0, 1.5) - player.global_position
			player.set_look(atan2(-dd.x, -dd.z), -0.12)
			await _wait(frames)
			await _save(name)
			player.release_held()
			cam.make_current()
		"avatars":
			var base: Vector3 = lv.to_global(Vector3(0.2, 0, 0.4))
			_peers([
				{"userId": 101, "name": "Alex", "color": "#ff6a3d", "p": [base.x - 0.9, 0, base.z], "yaw": 2.6, "pitch": 0.0, "anim": "idle"},
				{"userId": 102, "name": "Mira", "color": "#3dc6ff", "p": [base.x, 0, base.z + 0.4], "yaw": 3.3, "pitch": 0.1, "anim": "walk"},
				{"userId": 103, "name": "Sasha", "color": "#b4ff3d", "p": [base.x + 0.9, 0, base.z - 0.1], "yaw": 3.7, "pitch": -0.2, "anim": "crouch"},
			])
			await _wait(5)
			world.avatar_talk(102, 6.0, "Did anyone ship the Nebula crates yet?")
			_look(cam, lv.to_global(Vector3(0.6, 1.55, 3.0)), lv.to_global(Vector3(0.1, 1.0, 0.3)), 70.0)
			await _wait(frames)
			await _save("avatars_showcase")
			# also copy to the name the brief asks for
			var img := root.get_texture().get_image()
			img.save_png(out.path_join("avatars_showcase.png"))
		"avatar_close":
			var av: Node3D = world.peers.get("102")
			if av:
				world.avatar_talk(102, 6.0, "Привет! Ship it!")
				var p := av.global_position
				var fwd: Vector3 = av.global_basis.z
				_look(cam, p + fwd * 1.25 + Vector3(0.35, 1.45, 0), p + Vector3(0, 1.3, 0), 55.0)
				await _wait(frames)
				await _save("avatar_closeup")
			_peers([])
		"seat":
			var chair: Node3D = null
			for n in get_nodes_in_group("interactable"):
				if str(n.get_meta("kind", "")) == "pc_challenge" and n.is_inside_tree():
					chair = n
			if chair:
				cam.current = false
				player.make_camera_current()
				player.sit_at(chair)
				await _wait(frames)
				await _save("seat_pc")
				bus.ui_modal_changed.emit(true)
				await _wait(2)
				bus.ui_modal_changed.emit(false)
				await _wait(4)
				cam.make_current()
		"office":
			game.apply_sections({"hq": {"level": 2, "rooms": {"AssemblyLine": {"level": 1}}}})
			await _wait(10)
			var vp := _vp("dispatch")
			if vp:
				_cam_at(cam, vp.global_transform, 72.0)
				await _wait(frames)
				await _save("office_dispatch")
			var vo := _vp("overview")
			if vo:
				_cam_at(cam, vo.global_transform, 76.0)
				await _wait(frames)
				await _save("office_staff")
