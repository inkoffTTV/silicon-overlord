extends RefCounted
## Procedural meshes: chamfered ("toy-like") boxes, cached by size+bevel.
## The bevel faces have non axis-aligned normals; surface.gdshader uses that for worn edges.

static var _cache := {}

static func cbox(size: Vector3, bevel: float = 0.015) -> Mesh:
	var key := "%.3f|%.3f|%.3f|%.3f" % [size.x, size.y, size.z, bevel]
	if _cache.has(key):
		return _cache[key]
	var mesh: Mesh
	var h := size * 0.5
	var b: float = min(bevel, min(h.x, min(h.y, h.z)) * 0.8)
	if b < 0.001:
		var bm := BoxMesh.new()
		bm.size = size
		mesh = bm
	else:
		mesh = _chamfer(h, b)
	_cache[key] = mesh
	return mesh

static func _pt(h: Vector3, b: float, s: Vector3, axis: int) -> Vector3:
	var p := Vector3(s.x * (h.x - b), s.y * (h.y - b), s.z * (h.z - b))
	p[axis] = s[axis] * h[axis]
	return p

static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3, h: Vector3) -> void:
	# Godot front faces are clockwise when seen from outside.
	if (b - a).cross(c - a).dot(n) > 0.0:
		var t := b
		b = c
		c = t
	for p in [a, b, c]:
		st.set_normal(n)
		var an := n.abs()
		var uv: Vector2
		if an.y >= an.x and an.y >= an.z:
			uv = Vector2(p.x, p.z)
		elif an.x >= an.z:
			uv = Vector2(p.z, -p.y)
		else:
			uv = Vector2(p.x, -p.y)
		st.set_uv(uv)
		st.add_vertex(p)

static func _quad(st: SurfaceTool, p: Array, n: Vector3, h: Vector3) -> void:
	_tri(st, p[0], p[1], p[2], n, h)
	_tri(st, p[0], p[2], p[3], n, h)

static func _chamfer(h: Vector3, b: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ring := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	for a in 3:
		var o1 := (a + 1) % 3
		var o2 := (a + 2) % 3
		for s in [-1.0, 1.0]:
			# main face
			var pts := []
			for r in ring:
				var sv := Vector3.ZERO
				sv[a] = s
				sv[o1] = r.x
				sv[o2] = r.y
				pts.append(_pt(h, b, sv, a))
			var n := Vector3.ZERO
			n[a] = s
			_quad(st, pts, n, h)
		# edges running along axis a
		for r in ring:
			var s_lo := Vector3.ZERO
			var s_hi := Vector3.ZERO
			s_lo[a] = -1.0
			s_hi[a] = 1.0
			s_lo[o1] = r.x
			s_hi[o1] = r.x
			s_lo[o2] = r.y
			s_hi[o2] = r.y
			var en := Vector3.ZERO
			en[o1] = r.x
			en[o2] = r.y
			_quad(st, [_pt(h, b, s_lo, o1), _pt(h, b, s_hi, o1), _pt(h, b, s_hi, o2), _pt(h, b, s_lo, o2)], en.normalized(), h)
	# corners
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var sv := Vector3(sx, sy, sz)
				_tri(st, _pt(h, b, sv, 0), _pt(h, b, sv, 1), _pt(h, b, sv, 2), sv.normalized(), h)
	return st.commit()

## Cylinder helper (cached).
static func cyl(radius: float, height: float, sides: int = 16, top_radius: float = -1.0) -> Mesh:
	var key := "cyl|%.3f|%.3f|%d|%.3f" % [radius, height, sides, top_radius]
	if _cache.has(key):
		return _cache[key]
	var c := CylinderMesh.new()
	c.bottom_radius = radius
	c.top_radius = radius if top_radius < 0.0 else top_radius
	c.height = height
	c.radial_segments = sides
	c.rings = 1
	_cache[key] = c
	return c

static func sphere(radius: float, segs: int = 12) -> Mesh:
	var key := "sph|%.3f|%d" % [radius, segs]
	if _cache.has(key):
		return _cache[key]
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = segs
	s.rings = max(4, segs / 2)
	_cache[key] = s
	return s

static func capsule(radius: float, height: float) -> Mesh:
	var key := "cap|%.3f|%.3f" % [radius, height]
	if _cache.has(key):
		return _cache[key]
	var c := CapsuleMesh.new()
	c.radius = radius
	c.height = height
	c.radial_segments = 16
	c.rings = 4
	_cache[key] = c
	return c

static func quad(size: Vector2) -> Mesh:
	var key := "quad|%.3f|%.3f" % [size.x, size.y]
	if _cache.has(key):
		return _cache[key]
	var q := QuadMesh.new()
	q.size = size
	_cache[key] = q
	return q
