extends CharacterBody3D
## First-person player (WORLD agent).
## WASD move, mouse look, Shift sprint, Space jump, Ctrl/C crouch, E interact, F flashlight.
## LMB hold = grab prop with a springy physics hold, RMB (while holding) = rotate it with the mouse,
## mouse wheel = hold distance, Q or MMB = throw, release LMB = drop (keeps momentum: swing to fling).
## Raycasts (<= 2.5 m) nodes in group "interactable" (meta kind/id/prompt) -> Bus.focus_changed / Bus.interact.
## Every 0.1 s calls Net.send_pos(position, yaw, pitch, anim) if Net has that method.

const WALK_SPEED := 3.2
const SPRINT_SPEED := 5.6
const CROUCH_SPEED := 1.6
const ACCEL := 12.0
const AIR_ACCEL := 2.5
const JUMP_VELOCITY := 4.3
const GRAVITY := 12.5
const RADIUS := 0.3
const STAND_HEIGHT := 1.72
const CROUCH_HEIGHT := 1.05
const EYE_STAND := 1.58
const EYE_CROUCH := 0.92
const REACH := 2.5
const GRAB_REACH := 2.6
const HOLD_MIN := 0.65
const HOLD_MAX := 2.3
const HOLD_FREQ := 11.0       # spring angular frequency (rad/s)
const HOLD_DAMPING := 0.75    # damping ratio
const STRENGTH := 300.0       # max hold force (N): heavy things sag and drag
const THROW_POWER := 55.0     # impulse budget (N*s), split by mass
const BREAK_DIST := 1.6       # hold breaks if the object is stuck this far from the hold point
const NET_INTERVAL := 0.1

@export var mouse_sensitivity := 0.0022
@export var invert_y := false

var head: Node3D
var cam: Camera3D
var flashlight: SpotLight3D
var col_shape: CollisionShape3D
var capsule: CapsuleShape3D

var yaw := 0.0
var pitch := 0.0
var controls_enabled := true
var crouching := false
var anim := "idle"

var held: RigidBody3D = null
var hold_local := Vector3.ZERO
var hold_dist := 1.4
var rotating := false
var _held_saved := {}
var _rot_input := Vector2.ZERO

var focus: Node = null
var _focus_prompt := ""

var _eye := EYE_STAND
var _bob_t := 0.0
var _bob_amt := 0.0
var _land_dip := 0.0
var _fall_speed := 0.0
var _tilt := 0.0
var _net_t := 0.0
var _gravity_vec := Vector3(0, -9.8, 0)

func _enter_tree() -> void:
	add_to_group("local_player")

func _ready() -> void:
	_gravity_vec = Vector3.DOWN * float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	floor_snap_length = 0.25
	floor_max_angle = deg_to_rad(50)
	capsule = CapsuleShape3D.new()
	capsule.radius = RADIUS
	capsule.height = STAND_HEIGHT
	col_shape = CollisionShape3D.new()
	col_shape.name = "Collision"
	col_shape.shape = capsule
	col_shape.position.y = STAND_HEIGHT * 0.5
	add_child(col_shape)
	head = Node3D.new()
	head.name = "Head"
	head.position.y = EYE_STAND
	add_child(head)
	cam = Camera3D.new()
	cam.name = "Camera"
	cam.fov = 74.0
	cam.near = 0.03
	cam.far = 300.0
	head.add_child(cam)
	cam.current = true
	flashlight = SpotLight3D.new()
	flashlight.name = "Flashlight"
	flashlight.light_color = Color(1.0, 0.94, 0.82)
	flashlight.light_energy = 4.0
	flashlight.spot_range = 16.0
	flashlight.spot_angle = 24.0
	flashlight.spot_angle_attenuation = 1.4
	flashlight.shadow_enabled = true
	flashlight.shadow_bias = 0.03
	flashlight.light_volumetric_fog_energy = 0.6
	flashlight.visible = false
	add_child(flashlight)
	flashlight.top_level = true
	Bus.ui_modal_changed.connect(_on_modal_changed)
	_capture_mouse(not Bus.modal_open)

# ------------------------------------------------------------------ public API
func set_look(new_yaw: float, new_pitch: float) -> void:
	yaw = new_yaw
	pitch = clampf(new_pitch, -1.5, 1.5)
	_apply_look()

func set_controls_enabled(on: bool) -> void:
	controls_enabled = on
	if not on:
		release_held()

func make_camera_current() -> void:
	if cam:
		cam.make_current()

func get_camera() -> Camera3D:
	return cam

## Grab whatever grabbable prop is under the crosshair. Returns true on success.
func try_grab() -> bool:
	if held:
		return true
	var hit := _ray(GRAB_REACH)
	if hit.is_empty():
		return false
	var body: Object = hit.collider
	if body is RigidBody3D and not body.freeze and (body.is_in_group("grabbable") or body.mass < 50.0):
		_start_hold(body, hit.position)
		return true
	return false

func release_held(throw: bool = false) -> void:
	if held == null:
		return
	var b := held
	held = null
	rotating = false
	if is_instance_valid(b):
		remove_collision_exception_with(b)
		b.remove_collision_exception_with(self)
		b.angular_damp = _held_saved.get("angular_damp", 0.6)
		b.linear_damp = _held_saved.get("linear_damp", 0.05)
		b.can_sleep = true
		if throw:
			var dir := -cam.global_basis.z
			var speed := clampf(THROW_POWER / maxf(b.mass, 0.1), 1.5, 13.0)
			b.linear_velocity = b.linear_velocity * 0.3 + dir * speed + velocity * 0.5
		elif b.linear_velocity.length() > 9.0:
			b.linear_velocity = b.linear_velocity.normalized() * 9.0

## Press E: interact with the focused interactable. Returns true if Bus.interact was emitted.
func try_interact() -> bool:
	_update_focus()
	if focus == null or not is_instance_valid(focus):
		return false
	Bus.interact.emit(str(focus.get_meta("kind", "")), str(focus.get_meta("id", "")))
	return true

# ------------------------------------------------------------------ input
func _input_allowed() -> bool:
	return controls_enabled and not Bus.modal_open

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and _input_allowed():
			if rotating and held:
				_rot_input += event.relative
			else:
				yaw -= event.relative.x * mouse_sensitivity
				pitch -= event.relative.y * mouse_sensitivity * (-1.0 if invert_y else 1.0)
				pitch = clampf(pitch, -1.5, 1.5)
				_apply_look()
		return
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		if not Bus.modal_open and controls_enabled:
			_capture_mouse(true)
			get_viewport().set_input_as_handled()
		return
	if not _input_allowed():
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and held:
			hold_dist = clampf(hold_dist + 0.12, HOLD_MIN, HOLD_MAX)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and held:
			hold_dist = clampf(hold_dist - 0.12, HOLD_MIN, HOLD_MAX)
		elif event.button_index == MOUSE_BUTTON_MIDDLE and held:
			release_held(true)
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_Q and held:
		release_held(true)
	if event.is_action_pressed("menu"):
		_capture_mouse(false)
	elif event.is_action_pressed("flashlight"):
		flashlight.visible = not flashlight.visible
	elif event.is_action_pressed("interact"):
		try_interact()
	elif event.is_action_pressed("grab"):
		try_grab()
	elif event.is_action_released("grab"):
		release_held()
	elif event.is_action_pressed("rotate_held"):
		rotating = held != null
	elif event.is_action_released("rotate_held"):
		rotating = false

func _on_modal_changed(open: bool) -> void:
	_capture_mouse(not open)
	if open:
		release_held()

func _capture_mouse(on: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE

func _apply_look() -> void:
	rotation.y = yaw
	if head:
		head.rotation.x = pitch

# ------------------------------------------------------------------ simulation
func _physics_process(dt: float) -> void:
	var ok := _input_allowed()
	var iv := Vector2.ZERO
	if ok:
		iv = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var on_floor := is_on_floor()
	if not on_floor:
		velocity.y -= GRAVITY * dt
		_fall_speed = maxf(_fall_speed, -velocity.y)
	# crouch (stay crouched if something is overhead)
	var want_crouch := ok and Input.is_action_pressed("crouch")
	if crouching and not want_crouch and _blocked_above():
		want_crouch = true
	_set_crouch(want_crouch)
	# walk
	var sprint := ok and Input.is_action_pressed("sprint") and not crouching and iv.y < -0.1
	var speed := CROUCH_SPEED if crouching else (SPRINT_SPEED if sprint else WALK_SPEED)
	if held and held.mass > 12.0:
		speed *= clampf(1.0 - (held.mass - 12.0) / 40.0, 0.45, 1.0)
	var dir := (Basis(Vector3.UP, yaw) * Vector3(iv.x, 0, iv.y))
	var target := dir * speed
	var k := 1.0 - exp(-(ACCEL if on_floor else AIR_ACCEL) * dt)
	velocity.x = lerpf(velocity.x, target.x, k)
	velocity.z = lerpf(velocity.z, target.z, k)
	if ok and on_floor and Input.is_action_just_pressed("jump") and not crouching:
		velocity.y = JUMP_VELOCITY
	var was_on_floor := on_floor
	move_and_slide()
	# landing dip
	if is_on_floor() and not was_on_floor:
		_land_dip = clampf(_fall_speed * 0.018, 0.0, 0.14)
		_fall_speed = 0.0
	# shove props we walk into
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var other := c.get_collider()
		if other is RigidBody3D and other != held:
			var push := -c.get_normal()
			push.y = 0.0
			var hv := Vector2(velocity.x, velocity.z).length()
			other.apply_impulse(push * clampf(hv, 0.0, 6.0) * 0.6 * minf(other.mass, 4.0) * dt * 10.0, c.get_position() - other.global_position)
	# anim tag for peers
	var hspeed := Vector2(velocity.x, velocity.z).length()
	if not is_on_floor():
		anim = "air"
	elif crouching:
		anim = "crouch"
	elif held:
		anim = "carry"
	elif hspeed > 4.2:
		anim = "run"
	elif hspeed > 0.4:
		anim = "walk"
	else:
		anim = "idle"
	_update_hold(dt)
	_update_focus()
	_net_tick(dt)

func _process(dt: float) -> void:
	_update_head(dt)

func _set_crouch(on: bool) -> void:
	if on == crouching:
		return
	crouching = on
	capsule.height = CROUCH_HEIGHT if on else STAND_HEIGHT
	col_shape.position.y = capsule.height * 0.5

func _blocked_above() -> bool:
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var s := CapsuleShape3D.new()
	s.radius = RADIUS * 0.95
	s.height = STAND_HEIGHT
	q.shape = s
	q.transform = Transform3D(Basis(), global_position + Vector3(0, STAND_HEIGHT * 0.5 + 0.02, 0))
	q.exclude = [get_rid()] + ([held.get_rid()] if held else [])
	return not space.intersect_shape(q, 1).is_empty()

func _update_head(dt: float) -> void:
	if head == null:
		return
	_eye = lerpf(_eye, EYE_CROUCH if crouching else EYE_STAND, 1.0 - exp(-12.0 * dt))
	head.position.y = _eye
	var hspeed := Vector2(velocity.x, velocity.z).length()
	var moving := is_on_floor() and hspeed > 0.3
	_bob_amt = lerpf(_bob_amt, clampf(hspeed / WALK_SPEED, 0.0, 1.6) if moving else 0.0, 1.0 - exp(-8.0 * dt))
	_bob_t += dt * (4.2 + hspeed * 1.5) * (1.0 if moving else 0.4)
	_land_dip = lerpf(_land_dip, 0.0, 1.0 - exp(-7.0 * dt))
	cam.position = Vector3(cos(_bob_t) * 0.022 * _bob_amt, -absf(sin(_bob_t)) * 0.04 * _bob_amt - _land_dip, 0)
	var strafe := 0.0
	if _input_allowed():
		strafe = Input.get_axis("move_left", "move_right")
	_tilt = lerpf(_tilt, -strafe * 0.025 + sin(_bob_t * 0.5) * 0.004 * _bob_amt, 1.0 - exp(-6.0 * dt))
	cam.rotation.z = _tilt
	var sprinting := hspeed > WALK_SPEED + 0.6
	cam.fov = lerpf(cam.fov, 80.0 if sprinting else 74.0, 1.0 - exp(-5.0 * dt))
	# flashlight follows the view with a little lag (hand-held feel)
	if flashlight:
		var anchor := cam.global_transform
		var want := anchor.origin + anchor.basis.x * 0.18 - anchor.basis.y * 0.14
		flashlight.global_position = want
		var b := flashlight.global_basis.orthonormalized().slerp(anchor.basis.orthonormalized(), 1.0 - exp(-14.0 * dt))
		flashlight.global_basis = b

func _ray(dist: float) -> Dictionary:
	if cam == null or not is_inside_tree():
		return {}
	var from := cam.global_position
	var to := from - cam.global_basis.z * dist
	var q := PhysicsRayQueryParameters3D.create(from, to)
	var ex: Array[RID] = [get_rid()]
	if held:
		ex.append(held.get_rid())
	q.exclude = ex
	q.collide_with_areas = true
	return get_world_3d().direct_space_state.intersect_ray(q)

static func find_interactable(n: Node) -> Node:
	var depth := 0
	while n != null and depth < 6:
		if n.is_in_group("interactable"):
			return n
		n = n.get_parent()
		depth += 1
	return null

func _update_focus() -> void:
	var f: Node = null
	if _input_allowed() and held == null:
		var hit := _ray(REACH)
		if not hit.is_empty():
			f = find_interactable(hit.collider)
	var prompt := str(f.get_meta("prompt", "")) if f else ""
	focus = f
	if prompt != _focus_prompt:
		_focus_prompt = prompt
		Bus.focus_changed.emit(prompt)

# ------------------------------------------------------------------ physics hold
func _start_hold(body: RigidBody3D, point: Vector3) -> void:
	held = body
	hold_local = body.to_local(point)
	# small things are held by their centre (feels nicer), big ones by the grabbed point
	if body.mass < 1.0:
		hold_local = hold_local * 0.3
	hold_dist = clampf(cam.global_position.distance_to(point), HOLD_MIN + 0.2, HOLD_MAX)
	_held_saved = {"angular_damp": body.angular_damp, "linear_damp": body.linear_damp}
	body.angular_damp = 4.0
	body.linear_damp = 0.8
	body.can_sleep = false
	body.sleeping = false
	add_collision_exception_with(body)
	body.add_collision_exception_with(self)
	_focus_prompt = ""
	Bus.focus_changed.emit("")

func _update_hold(dt: float) -> void:
	if held == null:
		return
	if not is_instance_valid(held) or not held.is_inside_tree():
		held = null
		return
	var target := cam.global_position - cam.global_basis.z * hold_dist
	var grab_world := held.to_global(hold_local)
	var to := target - grab_world
	if to.length() > BREAK_DIST:
		release_held()
		return
	var r := grab_world - held.global_position
	var point_vel := held.linear_velocity + held.angular_velocity.cross(r)
	var rel_vel := point_vel - velocity
	var m := held.mass
	var w := HOLD_FREQ
	var f := m * (w * w * to - 2.0 * HOLD_DAMPING * w * rel_vel) - m * _gravity_vec
	if f.length() > STRENGTH:
		f = f.normalized() * STRENGTH
	held.apply_force(f, r)
	if rotating:
		var b := cam.global_basis
		var spin := (b.y * _rot_input.x + b.x * _rot_input.y) * 0.35
		held.angular_velocity = held.angular_velocity.lerp(spin, 0.6)
	_rot_input = Vector2.ZERO

# ------------------------------------------------------------------ network
func _net_tick(dt: float) -> void:
	_net_t += dt
	if _net_t < NET_INTERVAL:
		return
	_net_t = fmod(_net_t, NET_INTERVAL)
	var net := get_node_or_null("/root/Net")
	if net and net.has_method("send_pos"):
		net.send_pos(global_position, yaw, pitch, anim)
