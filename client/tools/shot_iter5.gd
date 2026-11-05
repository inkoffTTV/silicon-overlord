extends SceneTree
## Iteration-5 screenshots (WORLD agent, 0.5.0): build mode, decorated garage, themes, expansions, production
## processes, living decor. Loads main.tscn with the iteration-2 fake company + an interior, hides the UI.
##   xvfb-run -a -s "-screen 0 1600x900x24" <godot> --path client -s res://tools/shot_iter5.gd -- --shots=all
## --shots=all|ghost,cozy,themes,annex,basement,shed,showroom,locked,processes,posters,day,office
## --frames=N (default 40) --out=tools/shots/iter5
## Also the home of the local interior mock used by the world tests (mock_act: a tiny copy of the server rules).

const Shots := preload("res://tools/shot_iter2.gd")
const Data := preload("res://world/build/interior_data.gd")

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

# ------------------------------------------------------------------ fake data
static func item(id: String, def: String, x: float, z: float, rot: float = 0.0, y: Variant = null, color: String = "", day: int = 0) -> Dictionary:
	var it := {"id": id, "def": def, "x": x, "z": z, "rot": rot, "day": day, "paid": float(Data.def(def).get("price", 0))}
	if y != null:
		it["y"] = y
	if color != "":
		it["color"] = color
	return it

## The cozy garage (Cozy Wood): every spot passes the local mirror of the server rules (checked in world_smoke).
static func cozy_items() -> Array:
	return [
		item("i1", "decor_rug_braided", 1.0, 1.0, 90.0),
		item("i2", "seat_beanbag", 0.75, 0.5, 0.0, null, "#C8643A"),
		item("i3", "decor_arcade", 1.25, -0.5, 0.0),
		item("i4", "plant_monstera", 0.75, 2.0, 0.0, null, "", -90),
		item("i5", "decor_vinyl_player", -2.75, -2.25, 0.0),
		item("i6", "decor_aquarium", 2.25, -0.25, 90.0),
		item("i7", "decor_coffee_machine", 2.25, -2.25, 180.0),
		item("i8", "plant_palm", 2.25, -1.5, 0.0, null, "", -200),
		item("i9", "seat_armchair", -2.5, 0.25, 90.0),
		item("i10", "light_floor_arc", -2.5, -1.0, 180.0),
		item("i11", "plant_fig", -2.0, -2.25, 0.0, null, "", -30),
		item("i12", "light_bulb_string", 1.0, 1.0, 90.0),
		item("i13", "light_paper_lantern", 2.5, -0.25),
		item("i14", "decor_neon_name", -2.5, -3.46, 0.0, 2.65),
		item("i15", "decor_poster_launch", -3.985, -3.0, 90.0, 1.6),
		item("i16", "decor_trophy_shelf", 3.85, 2.75, 90.0, 2.25),
	]

static func with_interior(s: Dictionary, rooms: Dictionary, expansions: Dictionary = {}) -> Dictionary:
	s["interior"] = {"version": 1, "nextId": 100, "rooms": rooms, "summary": {}}
	var hq: Dictionary = s.get("hq", {})
	hq["expansions"] = expansions
	s["hq"] = hq
	return s

## A trophy-worthy company: awards, review scores, history.
static func decorate_company(s: Dictionary) -> void:
	s["awards"] = {"deviceOfYear": [{"year": 2016, "productName": "Nebula One", "prize": 500000, "winnerIsPlayer": true}],
		"bestOfKind": [{"year": 2016, "productName": "Nebula One", "category": "Midrange", "prize": 150000, "winnerIsPlayer": true}],
		"prizeTotal": 650000, "lastYearJudged": 2016}
	var p1: Dictionary = s.products["prod_20_2"]
	p1["reviewScore"] = 8.4
	var p2: Dictionary = s.products["prod_84_6"]
	p2["launchedDay"] = 80
	p2["reviewScore"] = 7.1
	if s.products.has("prod_90_10"):
		s.products["prod_90_10"]["launchedDay"] = 0

# ------------------------------------------------------------------ local interior mock (tests + shots)
## A small copy of the server's interior actions (validation = world/build/interior_data.gd, the same mirror the
## ghost uses), so build mode can be driven without a server.
static func mock_act(game_node: Node, action: String, a: Dictionary) -> Dictionary:
	var s: Dictionary = game_node.state
	if not (s.get("interior") is Dictionary):
		s["interior"] = {"version": 1, "nextId": 0, "rooms": {}, "summary": {}}
	var inter: Dictionary = s.interior
	var rooms: Dictionary = inter.rooms
	var rid := str(a.get("room", ""))
	var why := Data.available(s, rid)
	if action.begins_with("interior") and why != "":
		return {"ok": false, "error": why}
	if not rooms.has(rid) and action.begins_with("interior"):
		rooms[rid] = {"items": [], "surfaces": {}, "comfort": 0}
	match action:
		"interiorPlace":
			var d := Data.def(str(a.get("def", "")))
			var spot := Data.snap_spot(Data.room(rid, Data.hq_level(s)), d, float(a.x), float(a.z), float(a.get("rot", 0)), a.get("y"))
			var err := Data.validate(s, rid, d, spot)
			if err != "":
				return {"ok": false, "error": err}
			inter.nextId = int(inter.nextId) + 1
			var it := {"id": "i%d" % inter.nextId, "def": d.id, "x": spot.x, "z": spot.z, "rot": spot.rot, "day": 0, "paid": d.get("price", 0)}
			if spot.y != null:
				it["y"] = spot.y
			if str(a.get("color", "")) != "":
				it["color"] = a.color
			rooms[rid].items.append(it)
			s.finance.cash = float(s.finance.cash) - float(d.get("price", 0))
			game_node.apply_sections({"interior": inter, "finance": s.finance})
			return {"ok": true, "data": {"item": it, "cost": d.get("price", 0)}}
		"interiorMove":
			for it in rooms[rid].items:
				if it.id == a.get("id"):
					var d2 := Data.def(str(it.def))
					var to := str(a.get("toRoom", rid))
					var spot2 := Data.snap_spot(Data.room(to, Data.hq_level(s)), d2, float(a.x), float(a.z), float(a.get("rot", 0)), a.get("y", it.get("y")))
					var err2 := Data.validate(s, to, d2, spot2, str(it.id), true)
					if err2 != "":
						return {"ok": false, "error": err2}
					it.x = spot2.x
					it.z = spot2.z
					it.rot = spot2.rot
					if spot2.y != null:
						it["y"] = spot2.y
					if to != rid:
						rooms[rid].items.erase(it)
						if not rooms.has(to):
							rooms[to] = {"items": [], "surfaces": {}}
						rooms[to].items.append(it)
					game_node.apply_sections({"interior": inter})
					return {"ok": true, "data": {"item": it, "room": to}}
			return {"ok": false, "error": "Unknown item id"}
		"interiorRemove":
			for it in rooms[rid].items:
				if it.id == a.get("id"):
					rooms[rid].items.erase(it)
					var refund := int(float(it.get("paid", 0)) * 0.5)
					s.finance.cash = float(s.finance.cash) + refund
					game_node.apply_sections({"interior": inter, "finance": s.finance})
					return {"ok": true, "data": {"refund": refund}}
			return {"ok": false, "error": "Unknown item id"}
		"interiorPaint":
			rooms[rid].surfaces[str(a.surface)] = {"mat": a.mat, "color": a.color}
			game_node.apply_sections({"interior": inter})
			return {"ok": true, "data": {"cost": 0}}
		"interiorTheme":
			var t := Data.theme(str(a.get("theme", "")))
			if t.is_empty():
				return {"ok": false, "error": "Unknown theme"}
			rooms[rid]["theme"] = t.id
			rooms[rid]["surfaces"] = {"wall": t.wall.duplicate(), "floor": t.floor.duplicate()}
			rooms[rid]["light"] = t.light
			game_node.apply_sections({"interior": inter})
			return {"ok": true, "data": {"theme": t.id}}
		"interiorLight":
			rooms[rid]["light"] = str(a.get("preset", ""))
			game_node.apply_sections({"interior": inter})
			return {"ok": true}
	return {"ok": true}

# ------------------------------------------------------------------ plumbing
func _out() -> String:
	var o: String = args.get("out", "tools/shots/iter5")
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
	var p := out.path_join("%s.png" % name)
	img.save_png(p)
	print("[shot] saved ", p)

func _cam_at(cam: Camera3D, xf: Transform3D, fov: float) -> void:
	cam.global_transform = xf
	cam.fov = fov
	cam.make_current()

func _look(cam: Camera3D, from: Vector3, to: Vector3, fov: float = 70.0) -> void:
	var lv: Node3D = world.get_level()
	var f := lv.to_global(from)
	_cam_at(cam, Transform3D(Basis.looking_at(lv.to_global(to) - f, Vector3.UP), f), fov)

func _state(rooms: Dictionary, exps: Dictionary = {}) -> Dictionary:
	var s := Shots.fake_state()
	decorate_company(s)
	return with_interior(s, rooms, exps)

func _apply(s: Dictionary) -> void:
	game.apply_snapshot(s)
	await _wait(8)

func _run() -> void:
	out = _out()
	frames = int(args.get("frames", "40"))
	game = root.get_node("/root/Game")
	bus = root.get_node("/root/Bus")
	var net := root.get_node("/root/Net")
	var want: String = args.get("shots", "all")
	var shots := ["ghost", "cozy", "themes", "posters", "annex", "basement", "shed", "showroom", "locked", "processes", "day", "office"] if want == "all" else Array(want.split(","))
	game.me = {"userId": 1, "name": "You"}
	game.state = _state({"garage": {"items": cozy_items(), "surfaces": {}, "theme": "wood", "light": "warm"}})
	net.mock_handler = func(action: String, a: Dictionary) -> Dictionary:
		return mock_act(game, action, a)
	var main: Node = load("res://main.tscn").instantiate()
	root.add_child(main)
	await _wait(6)
	var ui := main.get_node_or_null("UI")
	if ui:
		ui.visible = false
	bus.ui_modal_changed.emit(false)
	world = get_first_node_in_group("world")
	player = get_first_node_in_group("local_player")
	var Loc: Script = load("res://ui/lib/loc.gd")
	Loc.call("set_lang", str(args.get("lang", "en")))
	world.set_time_of_day(0.02)
	if args.has("quality"):
		world.apply_quality(args["quality"])
	await _wait(10)
	var cam := Camera3D.new()
	cam.near = 0.03
	root.add_child(cam)
	for sh in shots:
		await _shot(str(sh), cam)
	quit(0)

func _theme_room(theme: String) -> Dictionary:
	var t := Data.theme(theme)
	return {"items": cozy_items(), "surfaces": {"wall": t.wall, "floor": t.floor}, "theme": theme, "light": t.light}

func _shot(name: String, cam: Camera3D) -> void:
	match name:
		"ghost":
			await _apply(_state({"garage": {"items": cozy_items().slice(0, 6), "surfaces": {}, "light": "warm", "comfort": 38.5}}))
			var bm: Node = world.get_build_mode()
			cam.current = false
			player.make_camera_current()
			player.global_position = world.get_level().to_global(Vector3(-2.5, 0.05, 2.1))
			await _wait(3)
			player.set_look(deg_to_rad(-4.0), -0.62)
			bm.set_active(true)
			bm.ui_attached = false
			bm.select_item("seat_armchair")
			bm.rot = 90.0
			await _wait(frames)
			await _save("build_ghost_valid")
			player.set_look(deg_to_rad(-30.0), -0.5)   # the trapdoor stairs: blocked
			bm.select_item("decor_arcade")
			await _wait(frames)
			await _save("build_ghost_invalid")
			bm.select_paint("plank", "#9A7452")
			player.set_look(deg_to_rad(60.0), -0.05)
			await _wait(frames)
			await _save("build_paint_wall")
			bm.set_active(false)
			cam.make_current()
		"cozy":
			await _apply(_state({"garage": {"items": cozy_items(), "surfaces": {"wall": {"mat": "plank", "color": "#9A7452"}, "floor": {"mat": "plank", "color": "#7A5638"}}, "theme": "wood", "light": "warm", "comfort": 71.2}}))
			_look(cam, Vector3(-1.2, 1.65, 2.9), Vector3(1.6, 0.8, -0.8), 74.0)
			await _wait(frames)
			await _save("cozy_garage")
			_look(cam, Vector3(-0.2, 1.55, 1.9), Vector3(2.6, 0.9, -0.9), 68.0)
			await _wait(frames)
			await _save("cozy_garage_corner")
		"themes":
			for th in ["grunge", "wood", "lab", "neon", "scandi"]:
				await _apply(_state({"garage": _theme_room(th)}))
				_look(cam, Vector3(-1.6, 1.7, 3.0), Vector3(1.4, 0.9, -1.0), 76.0)
				await _wait(frames)
				await _save("theme_%s" % th)
		"posters":
			await _apply(_state({"garage": {"items": cozy_items(), "surfaces": {}, "theme": "wood", "light": "warm"}}))
			_look(cam, Vector3(-3.25, 1.65, -1.25), Vector3(-3.98, 1.65, -3.0), 62.0)
			await _wait(frames + 20)
			await _save("living_poster_neon")
			_look(cam, Vector3(3.05, 2.05, 1.95), Vector3(4.0, 2.3, 2.85), 60.0)
			await _wait(frames)
			await _save("living_trophies")
		"annex":
			for lv in [1, 3]:
				var rooms := {"annex": {"items": [item("a1", "lab_bench", -1.4, -1.9, 0.0), item("a2", "lab_esd_bench", 1.0, -1.9, 0.0), item("a3", "lab_oscilloscope_cart", -2.4, 0.4),
					item("a4", "lab_3d_printer", -2.4, 1.6), item("a5", "decor_history_wall", 0.2, 2.45, 180.0, 1.45), item("a6", "plant_bonsai", 1.9, 1.9), item("a7", "lab_server_rack", -2.6, -0.8, 90.0)],
					"surfaces": {}, "light": "daylight"}}
				await _apply(_state(rooms, {"annex": {"level": lv}}))
				_look(cam, Vector3(-4.6, 1.65, 0.45), Vector3(-8.6, 0.9, -0.6), 78.0)
				await _wait(frames)
				await _save("exp_annex_lv%d" % lv)
			_look(cam, Vector3(-1.0, 1.6, 2.6), Vector3(-4.2, 1.1, 0.45), 70.0)
			await _wait(frames)
			await _save("exp_annex_door")
		"basement":
			for lv in [1, 3]:
				var rooms := {"basement": {"items": [item("b1", "store_pallet_rack", 2.5, 2.9, 0.0), item("b2", "store_crate_stack", -2.8, -2.6), item("b3", "store_wire_shelf", -3.3, 0.0, 90.0)], "surfaces": {}}}
				await _apply(_state(rooms, {"basement": {"level": lv}}))
				_look(cam, Vector3(-2.2, -1.2, 3.0), Vector3(2.0, -2.3, -1.0), 78.0)
				await _wait(frames)
				await _save("exp_basement_lv%d" % lv)
			_look(cam, Vector3(0.6, 1.7, 1.2), Vector3(-1.0, -1.0, -1.4), 70.0)
			await _wait(frames)
			await _save("exp_basement_stairs")
		"shed":
			for lv in [1, 3]:
				var rooms := {"shed": {"items": [item("s1", "prod_qc_light_table", -0.9, -1.2), item("s2", "prod_tool_wall", 1.4, -1.94, 0.0, 1.4), item("s3", "prod_jig_rack", 1.8, 0.9, 90.0)], "surfaces": {}, "light": "warm"}}
				await _apply(_state(rooms, {"shed": {"level": lv}}))
				_look(cam, Vector3(0.75, 1.6, -3.0), Vector3(1.0, 1.0, -7.5), 70.0)
				await _wait(frames)
				await _save("exp_shed_lv%d_yard" % lv)
				_look(cam, Vector3(1.0, 1.6, -6.3), Vector3(0.5, 0.8, -9.6), 78.0)
				await _wait(frames)
				await _save("exp_shed_lv%d" % lv)
		"showroom":
			for lv in [1, 3]:
				var rooms := {"showroom": {"items": [item("w1", "decor_phone_case", 1.2, 1.7, 180.0), item("w2", "decor_demo_table", 0.2, 0.2, 90.0), item("w3", "decor_poster_launch", 1.685, 0.6, 90.0, 1.6), item("w4", "plant_fig", -1.3, 1.6)],
					"surfaces": {}, "light": "daylight"}}
				await _apply(_state(rooms, {"showroom": {"level": lv}}))
				_look(cam, Vector3(3.7, 1.75, 7.45), Vector3(1.4, 0.9, 4.4), 78.0)
				await _wait(frames)
				await _save("exp_showroom_lv%d" % lv)
				_look(cam, Vector3(0.9, 1.7, 9.25), Vector3(2.5, 1.6, 6.0), 72.0)
				await _wait(frames)
				await _save("exp_showroom_lv%d_outside" % lv)
		"locked":
			await _apply(_state({}))
			_look(cam, Vector3(0.6, 1.6, 0.9), Vector3(-4.0, 1.2, 0.45), 74.0)
			await _wait(frames)
			await _save("locked_annex_door")
			_look(cam, Vector3(0.4, 1.7, -0.4), Vector3(-1.0, 0.0, -1.4), 70.0)
			await _wait(frames)
			await _save("locked_trapdoor")
			_look(cam, Vector3(0.9, 1.7, 9.25), Vector3(2.0, 0.6, 5.4), 72.0)
			await _wait(frames)
			await _save("locked_showroom_plot")
		"processes":
			var sets := [["hand", "semi", "robotic"], ["smart", "robotic", "semi"]]
			for k in sets.size():
				var s := _state({})
				var lines: Array = s.production.lines
				for i in lines.size():
					if i >= 1:
						lines[i]["process"] = sets[k][i - 1]
				s.production.jobs[2]["status"] = "Running"
				lines.append((lines[1] as Dictionary).duplicate(true))
				lines[3]["id"] = "line_4"
				lines[3]["process"] = sets[k][2]
				s.production.jobs.append({"id": "job_d", "lineId": "line_4", "productId": "prod_20_2", "quantity": 400, "produced": 200, "status": "Running"})
				await _apply(s)
				_look(cam, Vector3(-3.6, 4.95, 2.9), Vector3(0.0, 3.6, -1.0), 78.0)
				await _wait(frames + 20)
				await _save("process_set%d" % (k + 1))
			# close-ups: hand bench / robot arms / smart cell
			for pz in [["hand", Vector3(-2.2, 4.6, 1.6), Vector3(-0.6, 3.9, -1.0)], ["robotic", Vector3(-1.25, 4.75, 2.6), Vector3(0.05, 3.95, -0.6)], ["smart", Vector3(-0.15, 4.9, 2.95), Vector3(-0.55, 3.8, -1.5)], ["semi", Vector3(-3.7, 4.6, 1.4), Vector3(-2.55, 3.8, -1.2)]]:
				var s2 := _state({})
				var ls: Array = s2.production.lines
				for i in ls.size():
					if i >= 1:
						ls[i]["process"] = pz[0]
				s2.production.jobs[2]["status"] = "Running"
				await _apply(s2)
				_look(cam, pz[1], pz[2], 66.0)
				await _wait(frames + 20)
				await _save("process_%s" % pz[0])
		"day":
			await _apply(_state({"garage": {"items": cozy_items(), "surfaces": {}, "theme": "scandi", "light": "daylight"}}))
			world.set_time_of_day(0.75)
			_look(cam, Vector3(-0.6, 1.5, 0.3), Vector3(-1.2, 2.2, 9.0), 74.0)
			await _wait(frames + 10)
			await _save("daylight_window")
			world.set_time_of_day(0.25)
			await _wait(frames)
			await _save("night_window")
			world.set_time_of_day(0.02)
		"office":
			var s3 := _state({"office": {"items": [item("o1", "decor_ping_pong", 0.0, 2.6, 0.0), item("o2", "plant_indoor_tree", -4.6, 3.5), item("o3", "decor_neon_name", 1.0, -4.46, 0.0, 2.1),
				item("o4", "seat_sofa_felt", -2.6, 3.9, 180.0)], "surfaces": {"wall": {"mat": "paint", "color": "#2A3346"}}, "theme": "neon", "light": "neon"}})
			s3.hq["level"] = 2
			await _apply(s3)
			var vo: Node3D = null
			for v in get_nodes_in_group("viewpoint"):
				if str(v.get_meta("vp_name", "")) == "overview" and v.is_inside_tree():
					vo = v
			if vo:
				_cam_at(cam, vo.global_transform, 76.0)
				await _wait(frames)
				await _save("office_neon")
