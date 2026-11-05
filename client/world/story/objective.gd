extends Node3D
## Story objective highlight (WORLD agent, iteration 3): a soft pulsing glow outline on the target object(s)
## (GeometryInstance3D.material_overlay: rim glow + inverted-hull outline, shaders/rim + outline) and a floating
## chevron marker above the first target, visible through walls and in the dark, kept readable at any distance.
## world.story_stage() decides the targets; this node only draws.

const Mats := preload("res://world/lib/mats.gd")
const Meshes := preload("res://world/lib/meshes.gd")
const RIM := preload("res://world/shaders/rim.gdshader")
const OUTLINE := preload("res://world/shaders/outline.gdshader")
const COLOR := Color(1.0, 0.76, 0.29)
const MAX_MESHES := 160

var targets: Array = []
var overlay: ShaderMaterial
var marker: Node3D
var _marker_mat: StandardMaterial3D
var _meshes: Array = []          # MeshInstance3D with our overlay
var _t := 0.0
var _anchor := Vector3.ZERO
var _anchor_t := 0.0
var _strength := 0.0
var label := ""

func _ready() -> void:
	name = "Objective"
	overlay = ShaderMaterial.new()
	overlay.shader = RIM
	overlay.set_shader_parameter("color", COLOR)
	var hull := ShaderMaterial.new()
	hull.shader = OUTLINE
	hull.set_shader_parameter("color", COLOR)
	overlay.next_pass = hull
	marker = Node3D.new()
	marker.name = "Marker"
	marker.visible = false
	add_child(marker)
	_marker_mat = StandardMaterial3D.new()
	_marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker_mat.albedo_color = COLOR
	_marker_mat.emission_enabled = true
	_marker_mat.emission = COLOR
	_marker_mat.emission_energy_multiplier = 2.5
	_marker_mat.no_depth_test = true
	_marker_mat.render_priority = 10
	_marker_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var dark := StandardMaterial3D.new()
	dark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dark.albedo_color = Color(0.12, 0.07, 0.02, 0.9)
	dark.no_depth_test = true
	dark.render_priority = 9
	dark.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# chunky down-pointing chevron with a dark outline behind it, plus a small dot above (an "!"-ish read)
	var pivot := Node3D.new()
	pivot.name = "Spin"
	marker.add_child(pivot)
	for s in [-1.0, 1.0]:
		var b := MeshInstance3D.new()
		b.mesh = Meshes.cbox(Vector3(0.05, 0.17, 0.03), 0.012)
		b.material_override = _marker_mat
		b.position = Vector3(s * 0.05, 0.06, 0.0)
		b.rotation_degrees.z = s * 40.0
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pivot.add_child(b)
		var o := MeshInstance3D.new()
		o.mesh = Meshes.cbox(Vector3(0.08, 0.2, 0.02), 0.012)
		o.material_override = dark
		o.position = Vector3(s * 0.05, 0.06, -0.012)
		o.rotation_degrees.z = s * 40.0
		o.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pivot.add_child(o)
	var dot := MeshInstance3D.new()
	dot.mesh = Meshes.sphere(0.035, 8)
	dot.material_override = _marker_mat
	dot.position = Vector3(0, 0.24, 0)
	dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(dot)

## Highlight these nodes ([] = nothing). Same targets again = no-op.
func set_targets(nodes: Array, text: String = "") -> void:
	label = text
	var valid := nodes.filter(func(n: Variant) -> bool: return n is Node3D and is_instance_valid(n) and (n as Node3D).is_inside_tree())
	if valid.size() == targets.size():
		var same := true
		for i in valid.size():
			if valid[i] != targets[i]:
				same = false
		if same:
			return
	_clear_overlays()
	targets = valid
	_strength = 0.0
	for t in targets:
		for mi in (t as Node).find_children("*", "MeshInstance3D", true, false):
			if _meshes.size() >= MAX_MESHES:
				break
			var m := mi as MeshInstance3D
			if not m.visible or m.material_overlay != null:
				continue
			m.material_overlay = overlay
			_meshes.append(m)
		if t is MeshInstance3D and (t as MeshInstance3D).material_overlay == null:
			(t as MeshInstance3D).material_overlay = overlay
			_meshes.append(t)
	_anchor_t = 0.0
	marker.visible = not targets.is_empty()

func clear() -> void:
	set_targets([])

func has_target(n: Node) -> bool:
	return targets.has(n)

func _clear_overlays() -> void:
	for m in _meshes:
		if is_instance_valid(m) and m.material_overlay == overlay:
			m.material_overlay = null
	_meshes.clear()

func _exit_tree() -> void:
	_clear_overlays()

static func node_aabb(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var list: Array = n.find_children("*", "VisualInstance3D", true, false)
	if n is VisualInstance3D:
		list.append(n)
	for vi in list:
		if not (vi as Node3D).is_visible_in_tree() or vi is Light3D or vi is Label3D:
			continue
		var bb: AABB = (vi as VisualInstance3D).global_transform * (vi as VisualInstance3D).get_aabb()
		if bb.size.length() > 30.0:
			continue
		out = bb if first else out.merge(bb)
		first = false
	if first:
		return AABB(n.global_position, Vector3.ZERO)
	return out

func _process(dt: float) -> void:
	_t += dt
	targets = targets.filter(func(n: Variant) -> bool: return is_instance_valid(n) and (n as Node3D).is_inside_tree())
	if targets.is_empty():
		marker.visible = false
		return
	_strength = move_toward(_strength, 1.0, dt * 2.5)
	overlay.set_shader_parameter("strength", _strength)
	(overlay.next_pass as ShaderMaterial).set_shader_parameter("strength", _strength)
	_anchor_t -= dt
	var first: Node3D = targets[0]
	if _anchor_t <= 0.0 or first is RigidBody3D:
		_anchor_t = 0.5
		var bb := node_aabb(first)
		_anchor = Vector3(bb.get_center().x, bb.end.y + 0.22, bb.get_center().z)
	var cam := get_viewport().get_camera_3d()
	marker.visible = cam != null
	if cam == null:
		return
	var dist := cam.global_position.distance_to(_anchor)
	var sc := clampf(dist * 0.16, 0.35, 2.2)
	marker.global_position = _anchor + Vector3(0, (0.05 + 0.04 * sin(_t * 3.0)) * sc, 0)
	marker.scale = Vector3.ONE * sc
	# face the camera (yaw only) with a slow wobble
	var to := cam.global_position - marker.global_position
	marker.global_rotation = Vector3(0, atan2(to.x, to.z) + sin(_t * 1.7) * 0.25, 0)
	_marker_mat.albedo_color.a = 0.75 + 0.25 * sin(_t * 4.0)
