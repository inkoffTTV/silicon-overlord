extends Node3D
## A repair-shop customer (WORLD agent, iteration 3). Original "bean" people with a stable, varied look derived from the
## order's customer id (granny with a bun and handbag, courier with a cap and backpack, chef, punk, student, gardener,
## runner, grandpa with a flat cap, influencer in sunglasses, kid in a huge hoodie, ...).
## Moved by repair_shop.gd: walk(points, then) along level-space waypoints, pose(name), emote(symbol), hold(device).
## Has a capsule AnimatableBody3D so the player bumps into them. Root origin = feet, faces +Z.

const Rig := preload("res://world/actors/worker_rig.gd")
const Bubble := preload("res://world/actors/speech_bubble.gd")
const Mats := preload("res://world/lib/mats.gd")
const Meshes := preload("res://world/lib/meshes.gd")

const SKINS := [Color(0.96, 0.8, 0.66), Color(0.86, 0.66, 0.5), Color(0.72, 0.52, 0.36), Color(0.55, 0.38, 0.25), Color(0.4, 0.27, 0.18), Color(0.93, 0.76, 0.6)]
const HAIRS := [Color(0.1, 0.07, 0.05), Color(0.25, 0.16, 0.09), Color(0.55, 0.38, 0.2), Color(0.85, 0.7, 0.4), Color(0.6, 0.25, 0.12), Color(0.82, 0.82, 0.84)]
## look presets: [shirt, pants, hair_style, extras...]
const LOOKS := ["granny", "courier", "student", "office", "kid", "punk", "chef", "gardener", "runner", "grandpa", "influencer", "musician"]

var order_id := ""
var customer := ""
var look := ""
var rig: Node3D
var bubble: Node3D
var body: AnimatableBody3D
var state := "idle"          # enter | give | wait | collect | leave | gone (set by the shop)
var speed := 1.35
var held: Node3D = null
var waited := 0.0
var _path: Array = []
var _then: Callable
var _yaw_target := 0.0
var _turn_only := false
var _emote_t := 0.0

func setup(order: Dictionary) -> void:
	order_id = str(order.get("id", ""))
	customer = str(order.get("customer", order_id))
	name = "Customer_" + order_id.validate_node_name()
	add_to_group("customer")
	set_meta("order_id", order_id)
	look = pick_look(customer)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(customer)
	rig = Rig.new()
	rig.name = "Rig"
	rig.head_style = "bean"
	rig.skin = SKINS[rng.randi() % SKINS.size()]
	rig.hair = HAIRS[rng.randi() % HAIRS.size()]
	rig.hair_style = rng.randi() % 3
	rig.pants = [Color(0.18, 0.22, 0.32), Color(0.22, 0.2, 0.18), Color(0.15, 0.15, 0.17), Color(0.35, 0.3, 0.22)][rng.randi() % 4]
	rig.shirt = Color.from_hsv(rng.randf(), 0.5, 0.75)
	match look:
		"granny":
			rig.hair = Color(0.85, 0.85, 0.88)
			rig.hair_style = 1
			rig.shirt = Color(0.55, 0.35, 0.6)
			rig.pants = Color(0.3, 0.25, 0.3)
		"courier":
			rig.hair_style = 2
			rig.hat_color = Color(0.85, 0.2, 0.15)
			rig.shirt = Color(0.55, 0.38, 0.2)
		"student":
			rig.shirt = Color(0.15, 0.55, 0.55)
			rig.hair_style = 3
		"office":
			rig.shirt = Color(0.82, 0.84, 0.9)
			rig.accessory = "tie"
			rig.hair_style = 0
		"kid":
			rig.shirt = Color(0.95, 0.5, 0.1)
			rig.hair_style = 2
			rig.hat_color = Color(0.2, 0.4, 0.9)
		"punk":
			rig.shirt = Color(0.1, 0.1, 0.12)
			rig.hair_style = 3
			rig.pants = Color(0.12, 0.12, 0.14)
		"chef":
			rig.shirt = Color(0.92, 0.92, 0.9)
			rig.hair_style = 3
			rig.accessory = "coat"
		"gardener":
			rig.shirt = Color(0.35, 0.5, 0.25)
			rig.hair_style = 3
		"runner":
			rig.shirt = Color(0.65, 0.9, 0.2)
			rig.pants = Color(0.1, 0.1, 0.12)
			rig.hair_style = 1
		"grandpa":
			rig.hair = Color(0.75, 0.75, 0.78)
			rig.hair_style = 3
			rig.shirt = Color(0.45, 0.4, 0.32)
		"influencer":
			rig.shirt = Color(0.95, 0.45, 0.65)
			rig.hair = Color(0.95, 0.85, 0.55)
			rig.hair_style = 1
		"musician":
			rig.shirt = Color(0.2, 0.25, 0.35)
			rig.hair_style = 0
	rig.build()
	_dress(rng)
	if look == "kid":
		rig.scale = Vector3.ONE * 0.8
	add_child(rig)
	bubble = Bubble.new()
	bubble.position = Vector3(0, 2.15 * rig.scale.y, 0)
	add_child(bubble)
	body = AnimatableBody3D.new()
	body.name = "Body"
	body.sync_to_physics = false
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.24
	cap.height = 1.6 * rig.scale.y
	cs.shape = cap
	cs.position.y = cap.height * 0.5
	body.add_child(cs)
	add_child(body)

static func pick_look(cust: String) -> String:
	var c := cust.to_lower()
	for k in LOOKS:
		if c.contains(k):
			return k
	for pair in [["grand", "granny"], ["babushka", "granny"], ["nan", "granny"], ["cook", "chef"], ["pizza", "courier"],
			["deliver", "courier"], ["boy", "kid"], ["girl", "kid"], ["teen", "student"], ["boss", "office"], ["blog", "influencer"],
			["star", "influencer"], ["garden", "gardener"], ["jog", "runner"], ["rock", "punk"], ["dj", "musician"], ["grandad", "grandpa"]]:
		if c.contains(pair[0]):
			return pair[1]
	return LOOKS[absi(hash(cust)) % LOOKS.size()]

## Extra accessories attached to the rig's bones.
func _dress(rng: RandomNumberGenerator) -> void:
	var h: Node3D = rig.head
	var sp: Node3D = rig.spine
	match look:
		"granny":
			_glasses(h, false)
			var bag := _box(rig.farm_l, Vector3(0.2, 0.16, 0.08), Vector3(0, -0.36, 0.02), Mats.m("fabric", Color.WHITE, {"albedo": Color(0.6, 0.15, 0.2)}), 0.03)
			bag.rotation_degrees.z = 5
			_box(rig.farm_l, Vector3(0.012, 0.12, 0.012), Vector3(0, -0.25, 0.02), Mats.m("plastic_black"), 0.0)
			# cardigan buttons
			for i in 3:
				_box(sp, Vector3(0.025, 0.025, 0.01), Vector3(0, 0.12 + i * 0.12, 0.168), Mats.m("ceramic", Color(1.1, 1.0, 0.8)), 0.005)
		"courier", "student":
			_box(sp, Vector3(0.36, 0.42, 0.18), Vector3(0, 0.27, -0.25), Mats.m("fabric", Color.WHITE, {"albedo": Color(0.25, 0.3, 0.45) if look == "student" else Color(0.85, 0.55, 0.1)}), 0.06)
			for s in [-1.0, 1.0]:
				_box(sp, Vector3(0.05, 0.42, 0.04), Vector3(s * 0.15, 0.3, 0.17), Mats.m("plastic_black", Color(3, 3, 3)), 0.01)
			if look == "student":
				_beanie(h, Color(0.85, 0.3, 0.2))
				_headphones_neck(sp)
		"office":
			_glasses(h, false)
			var case := _box(rig.farm_r, Vector3(0.08, 0.28, 0.36), Vector3(0, -0.4, 0.02), Mats.m("wood_dark", Color(0.6, 0.45, 0.4)), 0.02)
			case.name = "Briefcase"
		"kid":
			pass
		"punk":
			var hair_m := Mats.m("fabric", Color.WHITE, {"albedo": Color(1.0, 0.25, 0.65)})
			for i in 6:
				var sp2 := _box(h, Vector3(0.05, 0.12, 0.05), Vector3(0, 0.42 - absf(i - 2.5) * 0.015, 0.14 - i * 0.06), hair_m, 0.015)
				sp2.rotation_degrees.x = -10 + i * 6
			_glasses(h, true)
			for s in [-1.0, 1.0]:
				_box(sp, Vector3(0.03, 0.03, 0.01), Vector3(s * 0.15, 0.4, 0.168), Mats.m("metal"), 0.005)
		"chef":
			var w := Mats.m("plastic_white", Color(1.25, 1.25, 1.25), {"roughness_base": 0.9})
			_mesh(h, Meshes.cyl(0.17, 0.2, 14), Vector3(0, 0.48, -0.01), w)
			_mesh(h, Meshes.sphere(0.21, 12), Vector3(0, 0.6, -0.01), w, Vector3(1.0, 0.55, 1.0))
		"gardener":
			_straw_hat(h)
			_box(sp, Vector3(0.4, 0.5, 0.02), Vector3(0, 0.15, 0.175), Mats.m("fabric", Color.WHITE, {"albedo": Color(0.2, 0.35, 0.15)}), 0.01)
		"runner":
			_box(h, Vector3(0.43, 0.05, 0.43), Vector3(0, 0.33, 0.0), Mats.m("fabric", Color.WHITE, {"albedo": Color(0.95, 0.2, 0.3)}), 0.02)
		"grandpa":
			var cap_m := Mats.m("fabric", Color.WHITE, {"albedo": Color(0.35, 0.3, 0.25)})
			_mesh(h, Meshes.sphere(0.215, 14), Vector3(0, 0.33, 0.0), cap_m, Vector3(1.0, 0.42, 1.05))
			_box(h, Vector3(0.24, 0.025, 0.12), Vector3(0, 0.33, 0.2), cap_m, 0.01)
			_box(h, Vector3(0.13, 0.03, 0.03), Vector3(0, 0.16, 0.2), Mats.m("fabric", Color.WHITE, {"albedo": Color(0.8, 0.8, 0.82)}), 0.012)  # moustache
			_glasses(h, false)
		"influencer":
			_glasses(h, true)
			var ph := _box(rig.farm_l, Vector3(0.08, 0.15, 0.012), Vector3(0, -0.3, 0.08), Mats.m("plastic_black"), 0.006)
			ph.rotation_degrees.x = 70
		"musician":
			var beret := Mats.m("fabric", Color.WHITE, {"albedo": Color(0.45, 0.08, 0.12)})
			_mesh(h, Meshes.sphere(0.21, 12), Vector3(0.03, 0.38, -0.02), beret, Vector3(1.05, 0.35, 1.0)).rotation_degrees.z = -12
			var scarf := Mats.m("fabric", Color.WHITE, {"albedo": Color(0.95, 0.75, 0.2)})
			_box(sp, Vector3(0.36, 0.08, 0.3), Vector3(0, 0.52, 0.0), scarf, 0.04)
			_box(sp, Vector3(0.08, 0.3, 0.03), Vector3(0.08, 0.35, 0.17), scarf, 0.02)
	if rng.randf() < 0.25 and look in ["office", "musician", "runner"]:
		_glasses(h, false)

func _glasses(h: Node3D, dark: bool) -> void:
	var m := Mats.m("plastic_black") if not dark else Mats.m("tv_black", Color.WHITE, {"roughness_base": 0.05})
	for s in [-1.0, 1.0]:
		_box(h, Vector3(0.085, 0.06 if dark else 0.07, 0.012), Vector3(s * 0.075, 0.25, 0.2), m if dark else Mats.glass(Color(0.7, 0.8, 0.9, 0.25)), 0.01)
		if not dark:
			_box(h, Vector3(0.09, 0.012, 0.014), Vector3(s * 0.075, 0.29, 0.2), m, 0.004)
	_box(h, Vector3(0.05, 0.012, 0.012), Vector3(0, 0.27, 0.205), m, 0.003)

func _beanie(h: Node3D, c: Color) -> void:
	var m := Mats.m("fabric", Color.WHITE, {"albedo": c})
	_mesh(h, Meshes.sphere(0.215, 14), Vector3(0, 0.32, -0.01), m, Vector3(1.0, 0.75, 1.0))
	_mesh(h, Meshes.sphere(0.05, 8), Vector3(0, 0.49, -0.01), m)

func _straw_hat(h: Node3D) -> void:
	var m := Mats.m("plywood", Color(1.3, 1.2, 0.8))
	_mesh(h, Meshes.cyl(0.36, 0.02, 18), Vector3(0, 0.36, 0), m)
	_mesh(h, Meshes.cyl(0.18, 0.14, 14, 0.15), Vector3(0, 0.43, 0), m)
	_mesh(h, Meshes.cyl(0.185, 0.03, 14), Vector3(0, 0.39, 0), Mats.m("fabric", Color.WHITE, {"albedo": Color(0.7, 0.15, 0.12)}))

func _headphones_neck(sp: Node3D) -> void:
	var m := Mats.m("plastic_black")
	for s in [-1.0, 1.0]:
		_box(sp, Vector3(0.07, 0.09, 0.09), Vector3(s * 0.13, 0.56, 0.06), m, 0.02)
	_box(sp, Vector3(0.3, 0.03, 0.04), Vector3(0, 0.57, -0.08), m, 0.01)

func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, bevel: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = Meshes.cbox(size, bevel)
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi

func _mesh(parent: Node3D, m: Mesh, pos: Vector3, mat: Material, sc: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	mi.scale = sc
	parent.add_child(mi)
	return mi

# ------------------------------------------------------------------ behaviour (driven by repair_shop.gd)
## Walk along global waypoints, then call `then` (optional).
func walk(points: Array, then: Callable = Callable(), walk_speed: float = 1.35) -> void:
	_path = points.duplicate()
	_then = then
	speed = walk_speed
	_turn_only = false

## Turn in place to face a global yaw (radians), keeping the current pose.
func face(yaw: float) -> void:
	_yaw_target = yaw
	_turn_only = true

func set_pose(p: String) -> void:
	if rig:
		rig.pose = p

func is_walking() -> bool:
	return not _path.is_empty()

## Short symbol bubble ("!", "?", "♥", "...", "$") + a little mouth flap.
func emote(text: String, seconds: float = 2.2) -> void:
	if bubble:
		bubble.say(text, seconds)
	if rig:
		rig.talk(minf(seconds, 1.2))

func talk(seconds: float) -> void:
	if rig:
		rig.talk(seconds)

## Put a device in the right hand (or null to let go).
func hold(dev: Node3D) -> void:
	held = dev
	if dev == null or rig == null:
		return
	var hand: Node3D = rig.farm_r
	if dev.get_parent():
		dev.get_parent().remove_child(dev)
	hand.add_child(dev)
	dev.position = Vector3(0, -0.27, 0.08)
	dev.rotation_degrees = Vector3(80, 0, 0)

func _physics_process(dt: float) -> void:
	if rig == null:
		return
	if not _path.is_empty():
		var tgt: Vector3 = _path[0]
		var p := global_position
		var d := Vector3(tgt.x - p.x, 0, tgt.z - p.z)
		var dist := d.length()
		var step := speed * dt
		if dist <= step + 0.01:
			global_position = Vector3(tgt.x, tgt.y, tgt.z)
			_path.pop_front()
			if _path.is_empty():
				rig.move_speed = 0.0
				if rig.pose in ["walk", "carry"]:
					rig.pose = "idle"
				if _then.is_valid():
					var cb := _then
					_then = Callable()
					cb.call()
		else:
			global_position = p + d / dist * step
			global_position.y = lerpf(p.y, tgt.y, clampf(step / maxf(dist, 0.01), 0.0, 1.0))
			_yaw_target = atan2(d.x, d.z)
			rig.pose = "carry" if held and rig.pose in ["carry", "walk", "idle"] and held.get_parent() == rig.farm_r else "walk"
			rig.move_speed = speed
		rotation.y = lerp_angle(rotation.y, _yaw_target, 1.0 - exp(-10.0 * dt))
	elif _turn_only:
		rotation.y = lerp_angle(rotation.y, _yaw_target, 1.0 - exp(-6.0 * dt))
		if absf(angle_difference(rotation.y, _yaw_target)) < 0.02:
			_turn_only = false

## Fade out and free.
func vanish() -> void:
	state = "gone"
	if body:
		body.process_mode = Node.PROCESS_MODE_DISABLED
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3(0.05, 0.05, 0.05), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)
