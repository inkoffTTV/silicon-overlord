extends SubViewportContainer
## Live 3D device preview: own World3D, studio lights, glowing pedestal, orbit camera.
## Drag to spin, wheel to zoom, view presets (front/back/side/bottom), optional auto-spin.
##   preview.show_params(PhoneBuilder.params_from_blueprint(bp, resolve, brand))
##   preview.set_view("back")

const Builder := preload("res://phone/phone_builder.gd")

signal view_changed(view: String)

var yaw := 0.5
var pitch := 0.08
var distance := 3.2
var auto_spin := false
var spin_speed := 0.35
var stage_style := "studio" # "studio" (designer) | "hero" (menu, neon rim lights) | "plain"
var pedestal := true
var accent := Color("#4F8CFF")
## camera distance multiplier (smaller = the device fills more of the view)
var fit := 1.0

var _vp: SubViewport
var _cam: Camera3D
var _pivot: Node3D
var _device: Node3D
var _params: Dictionary = {}
var _dragging := false
var _drag_moved := 0.0
var _tween: Tween
var _target_dist := 3.2
var _view := "auto"
var _ped_ring: MeshInstance3D
var _ready_done := false

func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	_vp.positional_shadow_atlas_size = 1024
	_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(_vp)
	var world := Node3D.new()
	_vp.add_child(world)
	_build_env(world)
	_pivot = Node3D.new()
	world.add_child(_pivot)
	_cam = Camera3D.new()
	_cam.fov = 30
	_cam.near = 0.05
	_cam.far = 60
	world.add_child(_cam)
	_cam.current = true
	_ready_done = true
	if not _params.is_empty():
		show_params(_params)
	_update_cam()

func _build_env(world: Node3D) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.09, 0.12, 0.22)
	sm.sky_horizon_color = Color(0.45, 0.5, 0.62)
	sm.ground_bottom_color = Color(0.02, 0.02, 0.04)
	sm.ground_horizon_color = Color(0.25, 0.27, 0.35)
	sm.sun_angle_max = 30
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.glow_enabled = false
	env.glow_intensity = 0.55
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 0.9
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.ssao_enabled = false
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	# key + fill + rims
	var key := DirectionalLight3D.new()
	key.light_energy = 1.25
	key.rotation_degrees = Vector3(-38, 35, 0)
	key.shadow_enabled = true
	key.shadow_blur = 1.5
	world.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.45
	fill.light_color = Color(0.75, 0.82, 1.0)
	fill.rotation_degrees = Vector3(-15, -140, 0)
	world.add_child(fill)
	var rim_a := OmniLight3D.new()
	rim_a.light_color = Color("#38C6D9") if stage_style == "hero" else Color(0.65, 0.75, 1.0)
	rim_a.light_energy = 2.2 if stage_style == "hero" else 1.0
	rim_a.omni_range = 6
	rim_a.position = Vector3(-2.2, 1.2, -1.2)
	world.add_child(rim_a)
	var rim_b := OmniLight3D.new()
	rim_b.light_color = Color("#E85CC4") if stage_style == "hero" else Color(1.0, 0.85, 0.75)
	rim_b.light_energy = 2.2 if stage_style == "hero" else 0.7
	rim_b.omni_range = 6
	rim_b.position = Vector3(2.2, 0.8, -1.0)
	world.add_child(rim_b)
	if pedestal:
		var disc := CylinderMesh.new()
		disc.top_radius = 0.78
		disc.bottom_radius = 0.82
		disc.height = 0.06
		disc.radial_segments = 64
		var dm := StandardMaterial3D.new()
		dm.albedo_color = Color(0.035, 0.045, 0.08)
		dm.metallic = 0.3
		dm.roughness = 0.55
		var d := MeshInstance3D.new()
		d.mesh = disc
		d.material_override = dm
		d.position = Vector3(0, -0.95, 0)
		world.add_child(d)
		var ring := TorusMesh.new()
		ring.inner_radius = 0.78
		ring.outer_radius = 0.805
		ring.rings = 64
		_ped_ring = MeshInstance3D.new()
		_ped_ring.mesh = ring
		var rm := StandardMaterial3D.new()
		rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rm.albedo_color = accent * 1.8
		_ped_ring.material_override = rm
		_ped_ring.position = Vector3(0, -0.92, 0)
		world.add_child(_ped_ring)

func set_accent(c: Color) -> void:
	accent = c
	if _ped_ring:
		(_ped_ring.material_override as StandardMaterial3D).albedo_color = c * 1.8

func show_params(p: Dictionary) -> void:
	_params = p
	if not _ready_done:
		return
	if _device:
		_pivot.remove_child(_device)
		_device.queue_free()
	_device = Builder.build(p)
	_pivot.add_child(_device)
	var ext := Builder.extents(p)
	var e := maxf(ext.x, ext.y)
	_target_dist = clampf(e * 2.45 + 0.7, 2.2, 8.5) if stage_style == "hero" else clampf(e * 2.9 + 0.8, 2.4, 9.0) * fit
	if not _dragging:
		distance = _target_dist
	_update_cam()

func set_view(view: String) -> void:
	_view = view
	var target := Vector2(yaw, pitch)
	match view:
		"front":
			target = Vector2(0.0, 0.0)
		"back":
			target = Vector2(PI, 0.0)
		"side":
			target = Vector2(PI / 2.0, 0.0)
		"bottom":
			target = Vector2(0.0, -1.2)
		"auto", "three_quarter":
			target = Vector2(0.55, 0.1)
		"back_three_quarter":
			target = Vector2(PI - 0.6, 0.12)
	# shortest way round
	var dy := wrapf(target.x - yaw, -PI, PI)
	if _tween:
		_tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT).set_parallel(true)
	_tween.tween_property(self, "yaw", yaw + dy, 0.6)
	_tween.tween_property(self, "pitch", target.y, 0.6)
	view_changed.emit(view)

func current_view() -> String:
	return _view

func _process(dt: float) -> void:
	if auto_spin and not _dragging:
		yaw += spin_speed * dt
	distance = lerpf(distance, _target_dist, minf(1.0, dt * 8.0))
	_update_cam()

func _update_cam() -> void:
	if not _cam:
		return
	var center := Vector3(0, 0.0, 0)
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	_cam.position = center + dir * distance
	_cam.look_at(center, Vector3.UP if absf(pitch) < 1.45 else Vector3.FORWARD)

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
			_drag_moved = 0.0
			if mb.pressed and _tween:
				_tween.kill()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_target_dist = clampf(_target_dist * 0.9, 1.2, 9.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_target_dist = clampf(_target_dist * 1.1, 1.2, 9.0)
		accept_event()
	elif e is InputEventMouseMotion and _dragging:
		var mm := e as InputEventMouseMotion
		yaw -= mm.relative.x * 0.01
		pitch = clampf(pitch + mm.relative.y * 0.008, -1.3, 1.3)
		_drag_moved += mm.relative.length()
		if _view != "free":
			_view = "free"
			view_changed.emit("free")
		accept_event()

func zoom(step: float) -> void:
	_target_dist = clampf(_target_dist * step, 1.2, 9.0)
