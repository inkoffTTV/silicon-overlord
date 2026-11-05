extends RefCounted
## Procedural mesh primitives for device models: bevelled rounded slabs, cylinders, rings.
## Winding is fixed automatically from the intended normal (Godot: clockwise = front face).

## Rounded-rectangle outline (CCW seen from +Z). Returns [points: PackedVector2Array, normals: PackedVector2Array].
static func outline(w: float, h: float, r: float, segs: int) -> Array:
	r = clampf(r, 0.0005, minf(w, h) * 0.5 - 0.0001)
	var pts := PackedVector2Array()
	var nrm := PackedVector2Array()
	var centers := [Vector2(w / 2 - r, h / 2 - r), Vector2(-w / 2 + r, h / 2 - r), Vector2(-w / 2 + r, -h / 2 + r), Vector2(w / 2 - r, -h / 2 + r)]
	for i in 4:
		for j in segs + 1:
			var a := (i * 90.0 + j * 90.0 / segs) * PI / 180.0
			var n := Vector2(cos(a), sin(a))
			pts.append(centers[i] + n * r)
			nrm.append(n)
	return [pts, nrm]

class Builder:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var size := Vector2.ONE

	func _uv(p: Vector3) -> Vector2:
		return Vector2(p.x / size.x + 0.5, 0.5 - p.y / size.y)

	func tri(a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3) -> void:
		var face := (b - a).cross(c - a)
		if face.dot(na + nb + nc) > 0.0:
			var t := b
			b = c
			c = t
			var tn := nb
			nb = nc
			nc = tn
		v.append_array([a, b, c])
		n.append_array([na, nb, nc])
		uv.append_array([_uv(a), _uv(b), _uv(c)])

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, na: Vector3, nb: Vector3, nc: Vector3, nd: Vector3) -> void:
		tri(a, b, c, na, nb, nc)
		tri(a, c, d, na, nc, nd)

	func commit(mesh: ArrayMesh = null) -> ArrayMesh:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = n
		arr[Mesh.ARRAY_TEX_UV] = uv
		var m := mesh if mesh else ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return m

## Bevelled rounded slab centred at the origin, depth along Z. bevel = edge chamfer size (rounded with 2 steps).
static func slab(w: float, h: float, d: float, r: float, bevel: float = -1.0, segs: int = 8, front: bool = true, back: bool = true) -> ArrayMesh:
	if bevel < 0:
		bevel = d * 0.22
	bevel = clampf(bevel, 0.0, minf(d * 0.45, minf(w, h) * 0.2))
	var b := Builder.new()
	b.size = Vector2(w, h)
	# rings from back (z=-d/2) to front (z=+d/2): inset cap edge, mid-bevel, full, full, mid-bevel, inset cap edge
	var steps := [[bevel, -d / 2, -1.0], [bevel * 0.29, -d / 2 + bevel * 0.29, -0.7], [0.0, -d / 2 + bevel, 0.0],
		[0.0, d / 2 - bevel, 0.0], [bevel * 0.29, d / 2 - bevel * 0.29, 0.7], [bevel, d / 2, 1.0]]
	var rings := []
	for st in steps:
		var inset: float = st[0]
		var o := outline(w - 2 * inset, h - 2 * inset, maxf(r - inset, 0.0005), segs)
		var pts: PackedVector2Array = o[0]
		var nr: PackedVector2Array = o[1]
		var ring := []
		var zf: float = st[2]
		for i in pts.size():
			var p := Vector3(pts[i].x, pts[i].y, st[1])
			var nn := Vector3(nr[i].x, nr[i].y, 0.0)
			if absf(zf) > 0.01:
				nn = (nn * (1.0 - absf(zf) * 0.75) + Vector3(0, 0, signf(zf) * absf(zf))).normalized()
			ring.append([p, nn])
		rings.append(ring)
	var count: int = rings[0].size()
	for k in rings.size() - 1:
		var ra: Array = rings[k]
		var rb: Array = rings[k + 1]
		if (ra[0][0] as Vector3).is_equal_approx(rb[0][0]):
			continue
		for i in count:
			var j := (i + 1) % count
			b.quad(ra[i][0], ra[j][0], rb[j][0], rb[i][0], ra[i][1], ra[j][1], rb[j][1], rb[i][1])
	# caps (flat)
	if back:
		_cap(b, rings[0], Vector3(0, 0, -1), -d / 2)
	if front:
		_cap(b, rings[rings.size() - 1], Vector3(0, 0, 1), d / 2)
	return b.commit()

static func _cap(b: Builder, ring: Array, normal: Vector3, z: float) -> void:
	var c := Vector3(0, 0, z)
	for i in ring.size():
		var j := (i + 1) % ring.size()
		b.tri(c, ring[i][0], ring[j][0], normal, normal, normal)

## Flat rounded plate (single face, normal +Z) — screens, bezels.
static func plate(w: float, h: float, r: float, segs: int = 8) -> ArrayMesh:
	var b := Builder.new()
	b.size = Vector2(w, h)
	var o := outline(w, h, r, segs)
	var pts: PackedVector2Array = o[0]
	var nz := Vector3(0, 0, 1)
	for i in pts.size():
		var j := (i + 1) % pts.size()
		b.tri(Vector3.ZERO, Vector3(pts[i].x, pts[i].y, 0), Vector3(pts[j].x, pts[j].y, 0), nz, nz, nz)
	return b.commit()

## Cylinder along Z (lenses, rings, punch holes) with a small bevel on the front edge.
static func disc(radius: float, depth: float, segs: int = 32, bevel: float = -1.0) -> ArrayMesh:
	return slab(radius * 2, radius * 2, depth, radius, bevel if bevel >= 0 else depth * 0.3, maxi(4, segs / 4))

## Torus-like ring in the XY plane (logo rings, lens trims).
static func ring(radius: float, thickness: float, segs: int = 40, tube_segs: int = 8) -> ArrayMesh:
	var b := Builder.new()
	b.size = Vector2(radius * 2, radius * 2)
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		for j in tube_segs:
			var t0 := TAU * j / tube_segs
			var t1 := TAU * (j + 1) / tube_segs
			var pts := []
			for pair in [[a0, t0], [a1, t0], [a1, t1], [a0, t1]]:
				var dir := Vector3(cos(pair[0]), sin(pair[0]), 0)
				var nn := dir * cos(pair[1]) + Vector3(0, 0, sin(pair[1]))
				pts.append([dir * radius + nn * thickness, nn])
			b.quad(pts[0][0], pts[1][0], pts[2][0], pts[3][0], pts[0][1], pts[1][1], pts[2][1], pts[3][1])
	return b.commit()
