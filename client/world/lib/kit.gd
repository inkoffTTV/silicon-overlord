extends RefCounted
## Level-building kit: boxes with shared static collision, lights, labels, cables, interactables.
## One Kit per level root. All positions are local to the given parent node.

const Mats := preload("res://world/lib/mats.gd")
const Meshes := preload("res://world/lib/meshes.gd")

var root: Node3D
var body: StaticBody3D
var font: Font

func _init(level_root: Node3D) -> void:
	root = level_root
	body = StaticBody3D.new()
	body.name = "StaticCollision"
	root.add_child(body)
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	body.physics_material_override = pm
	if ResourceLoader.exists("res://ui/fonts/Inter-Bold.ttf"):
		font = load("res://ui/fonts/Inter-Bold.ttf")

func node(parent: Node3D, pos: Vector3 = Vector3.ZERO, rot_y_deg: float = 0.0, name: String = "") -> Node3D:
	var n := Node3D.new()
	if name != "":
		n.name = name
	n.position = pos
	n.rotation_degrees.y = rot_y_deg
	parent.add_child(n)
	return n

## Chamfered box. collide=true adds a box shape to the shared static body.
func box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO,
		collide: bool = true, bevel: float = 0.015, shadow: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = Meshes.cbox(size, bevel)
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	if collide:
		shape(size, mi.global_transform)
	return mi

## Box shape on the shared static body at a global transform.
func shape(size: Vector3, gxf: Transform3D, target: CollisionObject3D = null) -> CollisionShape3D:
	var t: CollisionObject3D = target if target != null else body
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	t.add_child(cs)
	cs.global_transform = gxf
	return cs

func mesh(parent: Node3D, m: Mesh, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO, shadow: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

func cyl(parent: Node3D, r: float, h: float, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO, sides: int = 16, collide: bool = false) -> MeshInstance3D:
	var mi := mesh(parent, Meshes.cyl(r, h, sides), pos, mat, rot)
	if collide:
		var cs := CollisionShape3D.new()
		var c := CylinderShape3D.new()
		c.radius = r
		c.height = h
		cs.shape = c
		body.add_child(cs)
		cs.global_transform = mi.global_transform
	return mi

func label(parent: Node3D, text: String, pos: Vector3, px: int = 64, color: Color = Color.WHITE,
		rot: Vector3 = Vector3.ZERO, pixel_size: float = 0.002, shaded: bool = false) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.rotation_degrees = rot
	l.font_size = px
	l.pixel_size = pixel_size
	l.modulate = color
	l.outline_size = 0
	l.shaded = shaded
	l.double_sided = false
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if font:
		l.font = font
	parent.add_child(l)
	return l

func omni(parent: Node3D, pos: Vector3, color: Color, energy: float, rng: float, shadow: bool = false, fog: float = 1.0) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng
	l.omni_attenuation = 1.6
	l.shadow_enabled = shadow
	l.omni_shadow_mode = OmniLight3D.SHADOW_DUAL_PARABOLOID
	l.shadow_blur = 1.5
	l.shadow_bias = 0.04
	l.light_volumetric_fog_energy = fog
	l.light_specular = 0.6
	parent.add_child(l)
	return l

func spot(parent: Node3D, pos: Vector3, target: Vector3, color: Color, energy: float, rng: float, angle: float,
		shadow: bool = false, fog: float = 1.0) -> SpotLight3D:
	var l := SpotLight3D.new()
	parent.add_child(l)
	l.position = pos
	if not pos.is_equal_approx(target):
		var up := Vector3.UP if absf((target - pos).normalized().y) < 0.98 else Vector3.FORWARD
		l.transform = Transform3D(Basis.looking_at(target - pos, up), pos)
	l.light_color = color
	l.light_energy = energy
	l.spot_range = rng
	l.spot_angle = angle
	l.spot_angle_attenuation = 0.8
	l.spot_attenuation = 1.0
	l.shadow_enabled = shadow
	l.shadow_blur = 1.2
	l.shadow_bias = 0.03
	l.light_volumetric_fog_energy = fog
	return l

## Interactable furniture: StaticBody3D in group "interactable" with metadata kind/id/prompt.
## Add visuals as children (collide=false) and a hit box with ia_shape().
func interactable(parent: Node3D, kind: String, id: String, prompt: String, pos: Vector3, rot_y_deg: float = 0.0) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.name = "IA_" + kind
	sb.position = pos
	sb.rotation_degrees.y = rot_y_deg
	sb.add_to_group("interactable")
	sb.set_meta("kind", kind)
	sb.set_meta("id", id)
	sb.set_meta("prompt", prompt)
	parent.add_child(sb)
	return sb

func ia_shape(ia: StaticBody3D, size: Vector3, local_pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = local_pos
	ia.add_child(cs)

## Thin sagging cable from a to b (local to parent). Returns the sample points.
func cable(parent: Node3D, a: Vector3, b: Vector3, sag: float, segs: int = 10, thick: float = 0.012,
		mat: Material = null) -> Array:
	if mat == null:
		mat = Mats.m("rubber")
	var pts := []
	for i in segs + 1:
		var t := float(i) / segs
		var p := a.lerp(b, t)
		p.y -= sag * 4.0 * t * (1.0 - t)
		pts.append(p)
	for i in segs:
		var p0: Vector3 = pts[i]
		var p1: Vector3 = pts[i + 1]
		var mi := MeshInstance3D.new()
		mi.mesh = Meshes.cbox(Vector3(thick, thick, 1.0), 0.0)
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
		var mid := (p0 + p1) * 0.5
		var dir := p1 - p0
		var up := Vector3.UP if absf(dir.normalized().y) < 0.95 else Vector3.RIGHT
		mi.transform = Transform3D(Basis.looking_at(dir, up).scaled_local(Vector3(1, 1, dir.length() + thick)), mid)
	return pts

## Cable lying on the floor along a polyline (y is forced to `y`).
func floor_cable(parent: Node3D, pts: Array, y: float = 0.008, thick: float = 0.016, mat: Material = null) -> void:
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		a.y = y
		b.y = y
		cable(parent, a, b, 0.0, 1, thick, mat)

## String of glowing bulbs hanging between two points.
func string_lights(parent: Node3D, a: Vector3, b: Vector3, sag: float, count: int, colors: Array) -> Array:
	var pts := cable(parent, a, b, sag, count * 2, 0.008, Mats.m("plastic_black"))
	var bulbs := []
	for i in count:
		var t := (i + 0.5) / count
		var idx := int(round(t * (pts.size() - 1)))
		var p: Vector3 = pts[idx]
		var c: Color = colors[i % colors.size()]
		var bulb := mesh(parent, Meshes.sphere(0.022, 8), p + Vector3(0, -0.035, 0), Mats.glow(c, 6.0), Vector3.ZERO, false)
		mesh(parent, Meshes.cyl(0.01, 0.02, 6), p + Vector3(0, -0.012, 0), Mats.m("plastic_black"), Vector3.ZERO, false)
		bulbs.append(bulb)
	return bulbs

func viewpoint(parent: Node3D, vname: String, pos: Vector3, target: Vector3, fov: float = 70.0) -> Marker3D:
	var mk := Marker3D.new()
	mk.name = "VP_" + vname
	mk.add_to_group("viewpoint")
	mk.set_meta("vp_name", vname)
	mk.set_meta("fov", fov)
	parent.add_child(mk)
	mk.transform = Transform3D(Basis.looking_at(target - pos, Vector3.UP), pos)
	return mk
