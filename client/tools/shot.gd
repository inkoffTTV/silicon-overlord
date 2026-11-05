extends SceneTree
## Screenshot tool (WORLD agent). Loads a scene, puts a camera at named viewpoints (Marker3D nodes in
## group "viewpoint", meta vp_name/fov), waits for lighting/fog to settle and saves PNGs.
##
## xvfb-run -a -s "-screen 0 1600x900x24" <godot> --path client -s res://tools/shot.gd -- \
##     --scene=res://main.tscn --out=tools/shots --prefix=garage --views=overview,desk --frames=60
## Options:
##   --views=all|a,b,c     viewpoints to capture (default all)
##   --frames=N            frames to wait per view (default 45)
##   --quality=lo-fi|clean post-processing preset
##   --peers               spawn three fake peers (avatars) in front of the camera
##   --show=12,3,3,25      run world.play_launch("Nebula One"); capture each phase (lights, 3, 1, reveal) after N frames
##   --level=N             build HQ level N (fakes Game.state.hq.level)
##   --hide-ui             hide main.tscn's UI layer (world-only shots of the real game scene)
##   --grab=box_m          (main.tscn) walk the player up to a prop of that kind and hold it
##   --dark                switch off every light except the player's flashlight (debug)
##   --flashlight          turn the local player's flashlight on
##   --player              also capture the player's own camera ("player" view)
## Output dir may also come from env SHOT_DIR.

var args := {}

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var s: String = a.trim_prefix("--")
		var i := s.find("=")
		if i >= 0:
			args[s.substr(0, i)] = s.substr(i + 1)
		else:
			args[s] = "1"
	_run.call_deferred()

func _out_dir() -> String:
	var out: String = args.get("out", OS.get_environment("SHOT_DIR"))
	if out == "":
		out = "tools/shots"
	if not out.is_absolute_path():
		out = ProjectSettings.globalize_path("res://").path_join(out)
	DirAccess.make_dir_recursive_absolute(out)
	return out

func _wait(n: int) -> void:
	for i in n:
		await process_frame

func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(path)
	print("[shot] saved ", path)

func _run() -> void:
	var scene_path: String = args.get("scene", "res://main.tscn")
	var prefix: String = args.get("prefix", scene_path.get_file().get_basename())
	var frames := int(args.get("frames", "45"))
	var out := _out_dir()
	if args.has("level"):
		var game := root.get_node_or_null("/root/Game")
		if game:
			game.state = {"hq": {"level": int(args["level"]), "rooms": {}}, "time": {"year": 2016, "day": 85}}
	var scene: Node = load(scene_path).instantiate()
	root.add_child(scene)
	await _wait(5)
	var world: Node = null
	var worlds := get_nodes_in_group("world")
	if worlds.size() > 0:
		world = worlds[0]
	if args.has("quality") and world:
		world.apply_quality(args["quality"])
	elif args.has("quality") and scene.has_method("apply_quality"):
		scene.apply_quality(args["quality"])
	await _wait(10)

	var cam := Camera3D.new()
	cam.name = "ShotCam"
	cam.near = 0.03
	root.add_child(cam)

	var views: Array = []
	for vp in get_nodes_in_group("viewpoint"):
		views.append(vp)
	var want: String = args.get("views", "all")
	if want != "all":
		var names := want.split(",")
		views = views.filter(func(v: Node) -> bool: return names.has(str(v.get_meta("vp_name", v.name))))

	if args.has("peers"):
		_spawn_peers(views)

	if args.has("hide-ui"):
		var ui := scene.get_node_or_null("UI")
		if ui and "visible" in ui:
			ui.visible = false
		var bus := root.get_node_or_null("/root/Bus")
		if bus:
			bus.ui_modal_changed.emit(false)
	if args.has("flashlight"):
		for p in get_nodes_in_group("local_player"):
			if p.get("flashlight"):
				p.flashlight.visible = true
	if args.has("dark"):
		for l in scene.find_children("*", "Light3D", true, false):
			if l.name != "Flashlight":
				l.visible = false
	for vp in views:
		cam.global_transform = vp.global_transform
		cam.fov = float(vp.get_meta("fov", 70.0))
		cam.make_current()
		await _wait(frames)
		await _save(out.path_join("%s_%s.png" % [prefix, vp.get_meta("vp_name", vp.name)]))

	if args.has("grab"):
		await _grab_demo(str(args["grab"]))
	if args.has("player"):
		for p in get_nodes_in_group("local_player"):
			if p.has_method("make_camera_current"):
				p.make_camera_current()
				await _wait(frames)
				await _save(out.path_join("%s_player.png" % prefix))

	if args.has("show") and world:
		# capture one frame per show phase (software rendering is too slow for wall-clock timing)
		var delays: Array = Array(str(args["show"]).split(",")).map(func(t: String) -> int: return int(t))
		world.play_launch("Nebula One", null)
		var st: Node = world.get_stage()
		var phases := ["lights", "count3", "count1", "reveal"]
		for i in phases.size():
			while str(st.get("phase")) != phases[i]:
				await process_frame
			await _wait(int(delays[i]) if i < delays.size() else 10)
			await _save(out.path_join("%s_show_%d_%s.png" % [prefix, i + 1, phases[i]]))
	quit(0)

func _spawn_peers(views: Array) -> void:
	var bus := root.get_node_or_null("/root/Bus")
	if bus == null or views.is_empty():
		return
	var vp: Node3D = views[0]
	var base := vp.global_position + (-vp.global_basis.z * Vector3(1, 0, 1)).normalized() * 2.4
	base.y = 0.0
	var yaw := vp.global_rotation.y
	var list := []
	var cols := ["#ff6a3d", "#3dc6ff", "#b4ff3d"]
	var names := ["Alex", "Mira", "Sasha"]
	for i in 3:
		var off := Vector3((i - 1) * 0.9, 0, (i % 2) * 0.5).rotated(Vector3.UP, yaw)
		var p := base + off
		list.append({"userId": 100 + i, "name": names[i], "color": cols[i], "p": [p.x, p.y, p.z], "yaw": yaw + PI + (i - 1) * 0.4, "pitch": -0.1 * i, "anim": ["idle", "walk", "crouch"][i]})
	bus.peers_changed.emit(list)

func _grab_demo(kind: String) -> void:
	var player: Node = get_first_node_in_group("local_player")
	if player == null:
		return
	var target: RigidBody3D = null
	for b in get_nodes_in_group("grabbable"):
		if str(b.get_meta("prop", "")) == kind:
			target = b
			break
	if target == null:
		return
	var tp := target.global_position
	var stand: Vector3 = tp + (player.global_position - tp).normalized() * 1.2
	player.global_position = Vector3(stand.x, 0.05, stand.z)
	await _wait(4)
	var d: Vector3 = tp - player.cam.global_position
	player.set_look(atan2(-d.x, -d.z), atan2(d.y, Vector2(d.x, d.z).length()))
	await _wait(3)
	player.try_grab()
	player.set_look(player.yaw + 0.5, -0.05)
	await _wait(20)
