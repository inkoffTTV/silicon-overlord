extends Node3D
## World root (WORLD agent). Builds the environment + post FX, the current HQ level, other players'
## avatars and the launch stage. Talks to the rest of the game only through Bus / Game.
##
## Public API (for UI):
##   set_board_text(lines: Array)          — text on the company board TV ("board_company")
##   play_launch(product_name, model=null) — run the launch show on the stage (also via Bus.launch_show)
##   apply_quality(q: String)              — "lo-fi" | "clean"
##   rebuild()                             — rebuild the HQ for Game.state.hq.level (also via Bus.world_rebuild)
##   avatar_talk(user_id, seconds, text="") — spoken chat: mouth anim + speech bubble on that player's avatar
##                                            (the local player has no visible avatar: no bubble for yourself)
##   avatar_position(user_id) -> Vector3|null — mouth position of a player's avatar (for 3D voice)
## Iteration 2 (all state-driven, see world/live/*): prototype on the workbench, research on the whiteboard,
## production lines in the loft, crates + van (manual shipping), employees as NPCs, job board.
## Iteration 3 (story start, see docs/STORY.md + world/live/repair_shop.gd):
##   story_stage(chapter, step)  — highlight the current objective (glow outline + floating marker); driven
##                                 automatically by Game.state.story, callable by the UI too
##   play_cutscene(id)           — "intro" | "investor" | "sign_swap" (also via Bus.story_cutscene(id));
##                                 signal cutscene_finished(id); is_cutscene_running()
##   get_shop()                  — the repair shop node of the garage (null in offices)
##   set_company_sign(text, color) — force the outside sign (preview); "" = back to the state
## Iteration 5 (0.5.0, docs/INTERIOR.md): build mode (key B, world/build/build_mode.gd — the UI finds it in group
##   "build_mode"), the interior renderer per level (level.interior, world/build/interior_view.gd), the garage
##   expansions (world/live/expansions.gd), production processes on the loft lines, a day–night cycle through the
##   windows (world/day_night.gd):
##   get_build_mode() -> Node                   set_time_of_day(phase) (0 dusk, .25 night, .5 dawn, .75 noon; -1 clock)

const PostFX := preload("res://fx/post_fx.gd")
const STAGE_SCENE := "res://world/stage.tscn"
const AVATAR_SCENE := preload("res://world/peer_avatar.tscn")
const LEVELS := {
	1: "res://world/levels/level_1_garage.gd",
	2: "res://world/levels/level_2_office.gd",
}
const STAGE_OFFSET := Vector3(0, 0, -400)
const BuildMode := preload("res://world/build/build_mode.gd")
const DayNight := preload("res://world/day_night.gd")

signal level_built(level: int)
## emitted when the launch show on the stage is over (camera is back on the player)
signal launch_finished(product_name: String)
## emitted when a story cutscene is over (camera back on the player)
signal cutscene_finished(id: String)
## 0.5.0 build mode contract with the UI (docs/REQUESTS.md): aim info (≤ 10 Hz), "please send this action"
## (interiorPlace / interiorMove / interiorRemove / interiorPaint / interiorTheme / interiorLight, pseudo "copy"),
## and — when the world sent an action itself (no UI listening) — the result.
signal build_hover(info: Dictionary)
signal build_request(action: String, args: Dictionary)
signal build_done(action: String, args: Dictionary, result: Dictionary)

const Objective := preload("res://world/story/objective.gd")
const Cutscenes := preload("res://world/story/cutscenes.gd")
const Story := preload("res://world/live/story_state.gd")
const STAGE_KINDS := [["polish", "pc_challenge"], ["qc_", "line_qc"], ["supplier", "supplier_phone"], ["phone_call", "supplier_phone"], ["call", "supplier_phone"],
	["part", "supplier_phone"], ["buy", "supplier_phone"], ["purchas", "supplier_phone"], ["material", "supplier_phone"],
	["whiteboard", "whiteboard_research"], ["research", "whiteboard_research"], ["brainstorm", "whiteboard_challenge"],
	["challenge", "whiteboard_challenge"], ["design", "pc_design"], ["blueprint", "pc_design"], ["publish", "pc_design"],
	["pc", "pc_design"], ["develop", "pc_design"], ["production", "workbench_production"], ["produce", "workbench_production"],
	["assembl", "workbench_production"], ["batch", "workbench_production"], ["queue", "workbench_production"],
	["crate", "van"], ["ship", "van"], ["van", "van"], ["launch", "stage_launch"], ["stage", "stage_launch"],
	["keynote", "stage_launch"], ["hire", "job_board"], ["job", "job_board"]]

var objective: Node3D
var builder: Node
var day_night: Node
var sky_mat: ProceduralSkyMaterial
var cutscenes: Node3D
var _stage: Array = []        # [chapter, step] set by story_stage() (UI) — else from Game.state.story
var _stage_t := 0.0

var env: Environment
var world_env: WorldEnvironment
var post: CanvasLayer
var level_node: Node3D
var level_num := 0
var peers_root: Node3D
var peers := {}
var stage: Node3D
var _board_override: Array = []
var _show_running := false
var _amb := ""
var _amb_t := 0.0

func _ready() -> void:
	add_to_group("world")
	_make_environment()
	post = PostFX.new()
	post.name = "PostFX"
	add_child(post)
	peers_root = Node3D.new()
	peers_root.name = "Peers"
	add_child(peers_root)
	Bus.state_changed.connect(_on_state_changed)
	Bus.world_rebuild.connect(rebuild)
	Bus.peers_changed.connect(_on_peers_changed)
	Bus.launch_show.connect(_on_launch_show)
	objective = Objective.new()
	add_child(objective)
	cutscenes = Cutscenes.new()
	cutscenes.world = self
	add_child(cutscenes)
	cutscenes.finished.connect(_on_cutscene_done)
	Bus.story_cutscene.connect(play_cutscene)
	day_night = DayNight.new()
	day_night.name = "DayNight"
	day_night.world = self
	day_night.sky = sky_mat
	day_night.env = env
	add_child(day_night)
	builder = BuildMode.new()
	builder.world = self
	add_child(builder)
	rebuild()

# ------------------------------------------------------------------ environment
func _make_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.06, 0.09, 0.25)
	psm.sky_horizon_color = Color(0.85, 0.42, 0.28)
	psm.sky_curve = 0.09
	psm.ground_bottom_color = Color(0.02, 0.02, 0.03)
	psm.ground_horizon_color = Color(0.2, 0.14, 0.16)
	psm.sky_energy_multiplier = 1.0
	psm.sun_angle_max = 0.0
	sky.sky_material = psm
	sky_mat = psm
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.36, 0.5)
	env.ambient_light_energy = 0.07
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.ssao_enabled = true
	env.ssao_radius = 0.9
	env.ssao_intensity = 1.8
	env.ssao_power = 1.6
	env.glow_enabled = true
	env.glow_intensity = 0.75
	env.glow_strength = 1.0
	env.glow_bloom = 0.03
	env.glow_hdr_threshold = 0.9
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.set_glow_level(0, 0.0)
	env.set_glow_level(1, 1.0)
	env.set_glow_level(2, 0.8)
	env.set_glow_level(3, 0.6)
	env.set_glow_level(4, 0.4)
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.035
	env.volumetric_fog_albedo = Color(0.85, 0.86, 0.92)
	env.volumetric_fog_anisotropy = 0.35
	env.volumetric_fog_length = 28.0
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_ambient_inject = 0.15
	env.volumetric_fog_sky_affect = 0.0
	env.volumetric_fog_temporal_reprojection_enabled = true
	world_env = WorldEnvironment.new()
	world_env.name = "Env"
	world_env.environment = env
	add_child(world_env)

func get_build_mode() -> Node:
	return builder

## UI -> world (docs/REQUESTS.md "build mode contract")
func build_mode(on: bool) -> void:
	if builder:
		builder.ui_attached = on
		builder.set_active(on)
		builder.ui_attached = on and builder.is_active()

func build_select(sel: Dictionary) -> void:
	if builder:
		builder.apply_ui_selection(sel)

func build_result(action: String, ok: bool, data: Dictionary, error: String) -> void:
	if builder:
		builder.on_result(action, ok, data, error)

func set_time_of_day(phase: float) -> void:
	if day_night:
		day_night.force(phase)

func apply_quality(q: String) -> void:
	if post:
		post.apply_quality(q)

# ------------------------------------------------------------------ HQ levels
func current_hq_level() -> int:
	var hq: Variant = Game.state.get("hq", {})
	if hq is Dictionary:
		return clampi(int(hq.get("level", 1)), 1, 7)
	return 1

func rebuild() -> void:
	build_level(current_hq_level())

func build_level(n: int) -> void:
	if builder and builder.is_active():
		builder.set_active(false)
	if level_node:
		level_node.queue_free()
		level_node.name = "OldLevel"
		level_node = null
	var path := ""
	for k in range(n, 0, -1):
		if LEVELS.has(k) and ResourceLoader.exists(LEVELS[k]):
			path = LEVELS[k]
			break
	var script: Script = load(path)
	level_node = Node3D.new()
	level_node.set_script(script)
	level_node.name = "HQ_L%d" % n
	level_node.set("level", n)
	add_child(level_node)
	level_node.build_level()
	level_num = n
	_refresh_calendar()
	_refresh_board()
	place_local_player()
	_amb = ""
	level_built.emit(n)

func place_local_player() -> void:
	if level_node == null:
		return
	var xf: Transform3D = global_transform * level_node.get("spawn_xform")
	for p in get_tree().get_nodes_in_group("local_player"):
		if p is Node3D:
			p.global_position = xf.origin
			if p.has_method("set_look"):
				p.set_look(xf.basis.get_euler().y, 0.0)
			if "velocity" in p:
				p.velocity = Vector3.ZERO

func get_level() -> Node3D:
	return level_node

# ------------------------------------------------------------------ data hooks
func set_board_text(lines: Array) -> void:
	_board_override = lines.duplicate()
	if level_node and level_node.has_method("set_board_lines"):
		level_node.set_board_lines(lines)

func _refresh_board() -> void:
	if level_node == null:
		return
	if not _board_override.is_empty():
		level_node.set_board_lines(_board_override)
		return
	level_node.set_board_lines(default_board_lines())

func default_board_lines() -> Array:
	var s := Game.state
	if s.is_empty():
		return ["SILICON OVERLORD", "--------------------", "NO COMPANY LOADED", "", "> waiting for server_"]
	var fin: Dictionary = s.get("finance", {}) if s.get("finance") is Dictionary else {}
	var t: Dictionary = s.get("time", {}) if s.get("time") is Dictionary else {}
	var launched := 0
	var products: Variant = s.get("products", {})
	if products is Dictionary:
		for p in products.values():
			if p is Dictionary and p.get("launchedDay") != null:
				launched += 1
	return [
		str(s.get("name", "COMPANY")).to_upper(),
		"--------------------",
		"CASH     %s" % _money(float(fin.get("cash", 0))),
		"DEBT     %s" % _money(float(fin.get("debt", 0))),
		"Q REV    %s" % _money(float(fin.get("qRevenue", 0))),
		"Q UNITS  %d" % int(fin.get("qUnits", 0)),
		"PHONES   %d launched" % launched,
		"Y%d  D%d" % [int(t.get("year", 2016)), int(t.get("day", 1))],
	]

static func _money(v: float) -> String:
	var a := absf(v)
	var sgn := "-" if v < 0 else ""
	if a >= 1e9:
		return "%s$%.2fB" % [sgn, a / 1e9]
	if a >= 1e6:
		return "%s$%.2fM" % [sgn, a / 1e6]
	if a >= 1e3:
		return "%s$%.1fK" % [sgn, a / 1e3]
	return "%s$%d" % [sgn, int(a)]

func _refresh_calendar() -> void:
	if level_node == null:
		return
	var t: Variant = Game.state.get("time", null)
	if t is Dictionary:
		level_node.set_date(int(t.get("year", 2016)), int(t.get("day", 1)))

func _on_state_changed(keys: Array) -> void:
	if keys.has("hq") and current_hq_level() != level_num:
		rebuild()
		return
	if keys.has("time"):
		_refresh_calendar()
	if _board_override.is_empty() and (keys.has("finance") or keys.has("time") or keys.has("name") or keys.has("products")):
		_refresh_board()

# ------------------------------------------------------------------ ambience
## Safety net for physics props / crates / devices: anything that fell out of the world goes back home.
const PROP_FALL_LIMIT := -8.0
var _rescue_t := 0.0

func _rescue_props() -> void:
	if level_node == null:
		return
	var floor_y := level_node.global_position.y + PROP_FALL_LIMIT
	for b in get_tree().get_nodes_in_group("grabbable"):
		if not (b is RigidBody3D) or not b.is_inside_tree() or b.freeze:
			continue
		var rb := b as RigidBody3D
		if not rb.has_meta("home_xf"):
			rb.set_meta("home_xf", rb.global_transform)
		if rb.global_position.y > floor_y and is_finite(rb.global_position.y):
			continue
		var home: Transform3D = rb.get_meta("home_xf")
		if home.origin.y < floor_y + 1.0:
			home = global_transform * level_node.get("spawn_xform")
			home.origin += Vector3(0, 1.0, 0)
		rb.linear_velocity = Vector3.ZERO
		rb.angular_velocity = Vector3.ZERO
		rb.global_transform = home.translated(Vector3(0, 0.05, 0))

func _process(delta: float) -> void:
	_rescue_t -= delta
	if _rescue_t <= 0.0:
		_rescue_t = 0.5
		_rescue_props()
	_stage_t -= delta
	if _stage_t <= 0.0:
		_stage_t = 0.25
		_update_stage()
		_auto_cutscene(0.25)
	_amb_t -= delta
	if _amb_t > 0.0 or level_node == null or _show_running:
		return
	_amb_t = 0.5
	var p := get_tree().get_first_node_in_group("local_player") as Node3D
	if p == null:
		return
	var a := "garage"
	if level_node.has_method("ambient_at"):
		a = str(level_node.ambient_at(level_node.to_local(p.global_position)))
	if a != _amb:
		_amb = a
		Sfx.ambient(a)

# ------------------------------------------------------------------ voice / speech bubbles
func avatar_talk(user_id: Variant, seconds: float, text: String = "") -> void:
	var uid := str(user_id)
	if uid == str(Game.me.get("userId", "__none__")):
		return
	var av: Node = peers.get(uid)
	if av and is_instance_valid(av) and av.has_method("talk"):
		av.talk(seconds, text)

func avatar_position(user_id: Variant) -> Variant:
	var uid := str(user_id)
	if uid == str(Game.me.get("userId", "__none__")):
		var p := get_tree().get_first_node_in_group("local_player") as Node3D
		return p.global_position + Vector3(0, 1.5, 0) if p else null
	var av: Node3D = peers.get(uid)
	if av and is_instance_valid(av):
		return av.global_position + Vector3(0, 1.35, 0)
	return null

# ------------------------------------------------------------------ peers
func _on_peers_changed(list: Array) -> void:
	var me := str(Game.me.get("userId", "__none__"))
	var seen := {}
	for e in list:
		if not (e is Dictionary):
			continue
		var uid := str(e.get("userId", ""))
		if uid == "" or uid == me:
			continue
		seen[uid] = true
		var av: Node3D = peers.get(uid)
		if av == null or not is_instance_valid(av):
			av = AVATAR_SCENE.instantiate()
			av.name = "Peer_" + uid.validate_node_name()
			peers_root.add_child(av)
			peers[uid] = av
		av.apply_state(e)
	for uid in peers.keys():
		if not seen.has(uid):
			if is_instance_valid(peers[uid]):
				peers[uid].queue_free()
			peers.erase(uid)

# ------------------------------------------------------------------ launch stage
func get_stage() -> Node3D:
	if stage == null or not is_instance_valid(stage):
		stage = load(STAGE_SCENE).instantiate()
		stage.position = STAGE_OFFSET
		add_child(stage)
	return stage

func _on_launch_show(product_id: String) -> void:
	var pname := product_id
	var products: Variant = Game.state.get("products", {})
	var product: Dictionary = {}
	if products is Dictionary and products.get(product_id) is Dictionary:
		product = products[product_id]
		pname = str(product.get("name", product_id))
	play_launch(pname, _product_model(product))

## Asks the phone module for a 3D model if it offers one, else returns null (stage uses its own).
func _product_model(product: Dictionary) -> Node3D:
	# Uses the UI agent's parametric builder (res://phone/phone_builder.gd) when present.
	const BUILDER := "res://phone/phone_builder.gd"
	const WIZARD := "res://ui/lib/wizard.gd"
	if product.is_empty() or not ResourceLoader.exists(BUILDER):
		return null
	var st: Dictionary = Game.state
	var bps: Variant = st.get("blueprints", {})
	var bp: Variant = bps.get(str(product.get("blueprintId", ""))) if bps is Dictionary else null
	if not (bp is Dictionary):
		bp = {"name": product.get("name", ""), "category": product.get("category", "Smartphone")}
	var pb_script: Script = load(BUILDER)
	var wizard: Script = load(WIZARD) if ResourceLoader.exists(WIZARD) else null
	var resolve := func(id: String) -> Dictionary:
		if wizard:
			var r: Variant = wizard.call("resolve", st, id)
			return r if r is Dictionary else {}
		return {}
	var logo: Dictionary = st.get("logo", {}) if st.get("logo") is Dictionary else {}
	var brand := {"initial": str(st.get("name", "?")).substr(0, 1), "name": st.get("name", ""),
		"colorA": logo.get("colorA", "#4F8CFF"), "colorB": logo.get("colorB", "#B15CFF")}
	var params: Variant = pb_script.call("params_from_blueprint", bp, resolve, brand)
	if not (params is Dictionary):
		return null
	var res: Variant = pb_script.call("build", params)
	return res if res is Node3D else null

func play_launch(product_name: String, model: Node3D = null) -> void:
	if _show_running:
		return
	_show_running = true
	var st := get_stage()
	for p in get_tree().get_nodes_in_group("local_player"):
		if p.has_method("set_controls_enabled"):
			p.set_controls_enabled(false)
	await st.play_launch(product_name, model)
	for p in get_tree().get_nodes_in_group("local_player"):
		if p.has_method("set_controls_enabled"):
			p.set_controls_enabled(true)
		if p.has_method("make_camera_current"):
			p.make_camera_current()
	_show_running = false
	launch_finished.emit(product_name)

# ------------------------------------------------------------------ story (iteration 3)
func get_shop() -> Node3D:
	return level_node.get("shop") if level_node else null

func set_company_sign(text: String, color: Color = Color(0.31, 0.55, 1.0)) -> void:
	var shop := get_shop()
	if shop == null:
		return
	if text == "":
		shop.clear_sign_override()
	else:
		shop.set_sign_override(text, color, "company")

## Highlight the objective of a story step (chapter, step id). Called automatically from Game.state.story.
## story_stage(-1, "") clears a manual stage (back to the state).
func story_stage(chapter: int, step: String) -> void:
	_stage = [] if chapter < 0 else [chapter, step]
	_update_stage()

func stage_targets(chapter: int, step: String) -> Array:
	var shop := get_shop()
	if shop:
		var t: Array = shop.objective_targets(chapter, step)
		if not t.is_empty():
			return t
	var s := step.to_lower()
	for pair in STAGE_KINDS:
		if s.contains(pair[0]):
			var n := _find_kind(pair[1])
			if n:
				return [n]
	return []

func _find_kind(kind: String) -> Node3D:
	for n in get_tree().get_nodes_in_group("interactable"):
		if n is Node3D and n.is_inside_tree() and str(n.get_meta("kind", "")) == kind and level_node and level_node.is_ancestor_of(n):
			return n
	# the van is not "interactable" for the lookup when hidden; fall back to any node with that meta
	return null

func _update_stage() -> void:
	if objective == null:
		return
	if _show_running or (cutscenes and cutscenes.is_running()):
		objective.set_targets([])
		return
	var ch := -1
	var step := ""
	if not _stage.is_empty():
		ch = int(_stage[0])
		step = str(_stage[1])
	elif Story.active(Game.state):
		ch = Story.chapter(Game.state)
		step = Story.step(Game.state)
	if ch < 0:
		objective.set_targets([])
		return
	objective.set_targets(stage_targets(ch, step))

func is_cutscene_running() -> bool:
	return cutscenes != null and cutscenes.is_running()

func play_cutscene(id: String) -> void:
	if cutscenes == null or cutscenes.is_running() or _show_running:
		return
	# just played (e.g. auto-played, and the UI asks for it too): don't run it twice in a row
	if _played.has(id) and Time.get_ticks_msec() - int(_played[id]) < 20000:
		return
	_show_running = true
	objective.set_targets([])
	cutscenes.play(id)

## Cutscenes the story needs, played once per session when their step is due (the UI may also emit
## Bus.story_cutscene(id): duplicates are ignored). Waits until no UI modal (menu / loading) is open.
var auto_cutscenes := true
var _played := {}
var _due_t := 0.0

func _auto_cutscene(dt: float) -> void:
	if not auto_cutscenes or not Story.active(Game.state) or Bus.modal_open or _show_running or get_shop() == null:
		_due_t = 0.0
		return
	var st := Game.state
	var ch := Story.chapter(st)
	var want := ""
	if ch == 0 and not Story.any_done(st, ["intro_seen"]):
		want = "intro"
	elif ch == 4 and not Story.any_done(st, ["investor_seen"]):
		want = "investor"
	elif ch == 6 and Story.any_done(st, ["reviews_seen"]) and not Story.any_done(st, ["sign_swapped"]):
		want = "sign_swap"
	if want == "" or _played.has(want):
		_due_t = 0.0
		return
	# the UI's story director normally asks first (Bus.story_cutscene); this is only the fallback
	_due_t += dt
	if _due_t >= 8.0:
		_due_t = 0.0
		play_cutscene(want)

func _on_cutscene_done(id: String) -> void:
	_show_running = false
	_amb = ""
	_played[id] = Time.get_ticks_msec()
	var ev: String = Story.CUTSCENE_EVENT.get(id, "")
	if ev != "" and Story.active(Game.state) and not Story.any_done(Game.state, [ev]):
		Net.act("storyEvent", {"id": ev})
	cutscene_finished.emit(id)

## Esc during a cutscene (the UI calls this): rush to the end.
func skip_cutscene() -> void:
	if cutscenes:
		cutscenes.skip()
