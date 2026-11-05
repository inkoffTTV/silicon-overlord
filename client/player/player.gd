extends CharacterBody3D
## First-person player (WORLD agent).
## WASD move, mouse look, Shift sprint, Space jump, Ctrl/C crouch, E interact, F flashlight.
## LMB hold = grab prop with a springy physics hold, RMB (while holding) = rotate it with the mouse,
## mouse wheel = hold distance, Q or MMB = throw, release LMB = drop (keeps momentum: swing to fling).
## Draws a small reticle (dot / interact ring / grab ring) and a faint grab beam while holding.
## Raycasts (<= 2.5 m) nodes in group "interactable" (meta kind/id/prompt) -> Bus.focus_changed / Bus.interact.
## Every 0.1 s calls Net.send_pos(position, yaw, pitch, anim) if Net has that method.
## Ladders: nodes in group "ladder" (meta bottom_local/top_local, level space): walk into the foot of the ladder
## facing it and press W to climb (W/S move along it, looking away flips them, Space lets go).
## Seats: interactables with meta "seat" {pos, yaw (deg, 0 = face the node's -Z), eye, pitch, pose "sit"|"stand"}
## (pc_challenge, whiteboard_challenge, line_qc): E moves the camera there and emits Bus.interact(kind, id);
## the player stands up when the UI closes its modal (Bus.ui_modal_changed(false)) or on E / Space / Esc / move.
## Crates (meta e_grabs): E picks them up like LMB.

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
const CLIMB_SPEED := 2.1
const Reticle := preload("res://player/reticle.gd")

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
var _aim_grabbable := false
var reticle: Control
var hud: CanvasLayer
var beam: MeshInstance3D

var _eye := EYE_STAND
var _bob_t := 0.0
var _bob_amt := 0.0
var _land_dip := 0.0
var _fall_speed := 0.0
var _tilt := 0.0
var _net_t := 0.0
var _gravity_vec := Vector3(0, -9.8, 0)
var climbing := false
var _ladder := {}
var _climb_cd := 0.0
var seated := false
var seat_kind := ""
var _seat_pose := "sit"
var _seat_eye := EYE_STAND
var _seat_back := Transform3D()
var _seat_saw_modal := false
var _seat_t := 0.0
var _step_side := 0.0
var _world: Node = null

func _enter_tree() -> void:
	add_to_group("local_player")

func _ready() -> void:
	_gravity_vec = Vector3.DOWN * float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	floor_snap_length = 0.25
	safe_margin = 0.01
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
	# reticle (between the post-FX layer -1 and the UI layer 1)
	hud = CanvasLayer.new()
	hud.name = "PlayerHUD"
	hud.layer = 0
	add_child(hud)
	reticle = Reticle.new()
	hud.add_child(reticle)
	# faint "grab beam" from the hand to the grabbed point
	beam = MeshInstance3D.new()
	beam.name = "GrabBeam"
	var bm := BoxMesh.new()
	bm.size = Vector3(0.006, 0.006, 1.0)
	beam.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(0.45, 0.85, 1.0, 0.5)
	beam.material_override = mat
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.visible = false
	add_child(beam)
	beam.top_level = true
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
			Sfx.play("throw", b.global_position, -4.0)
		elif b.linear_velocity.length() > 9.0:
			b.linear_velocity = b.linear_velocity.normalized() * 9.0
		if not throw:
			Sfx.play("crate_drop" if b.is_in_group("ship_crate") else "drop", b.global_position, -8.0)

## Press E: interact with the focused interactable. Returns true if Bus.interact was emitted.
func try_interact() -> bool:
	_update_focus()
	if focus == null or not is_instance_valid(focus):
		return false
	if focus is RigidBody3D and focus.get_meta("e_grabs", false):
		return try_grab()
	if focus.has_meta("seat"):
		sit_at(focus)
		return true
	Bus.interact.emit(str(focus.get_meta("kind", "")), str(focus.get_meta("id", "")))
	return true

## Sit down (or take a standing work spot) at an interactable with meta "seat", then emit Bus.interact.
func sit_at(node: Node3D) -> void:
	if seated:
		return
	release_held()
	var seat: Dictionary = node.get_meta("seat")
	var gp: Vector3 = node.global_transform * (seat.get("pos", Vector3.ZERO) as Vector3)
	var gyaw: float = node.global_rotation.y + deg_to_rad(float(seat.get("yaw", 0.0)))
	_seat_back = global_transform
	seated = true
	seat_kind = str(node.get_meta("kind", ""))
	_seat_pose = str(seat.get("pose", "sit"))
	_seat_eye = float(seat.get("eye", EYE_STAND))
	_seat_saw_modal = Bus.modal_open
	_seat_t = 0.0
	velocity = Vector3.ZERO
	col_shape.disabled = _seat_pose == "sit"
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "global_position", Vector3(gp.x, gp.y + (0.02 if _seat_pose != "sit" else 0.0), gp.z), 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_method(func(k: float) -> void: set_look(lerp_angle(yaw, gyaw, k), lerpf(pitch, deg_to_rad(float(seat.get("pitch", 0.0))), k)), 0.0, 1.0, 0.35)
	if _seat_pose == "sit":
		Sfx.play("sit", gp)
	if seat_kind == "pc_challenge":
		Sfx.play("pc_beep", gp + Vector3(0, 0.9, 0), -6.0)
	Bus.focus_changed.emit("")
	_focus_prompt = ""
	Bus.interact.emit(seat_kind, str(node.get_meta("id", "")))

func stand_up() -> void:
	if not seated:
		return
	seated = false
	col_shape.disabled = false
	if _seat_pose == "sit":
		global_position = _seat_back.origin
		Sfx.play("sit", global_position, -6.0)
	velocity = Vector3.ZERO
	seat_kind = ""

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
	if seated:
		if _seat_t > 0.3 and (event.is_action_pressed("interact") or event.is_action_pressed("jump") or event.is_action_pressed("menu")):
			stand_up()
			get_viewport().set_input_as_handled()
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
		if seated:
			_seat_saw_modal = true
	elif seated and _seat_saw_modal:
		stand_up()

func _capture_mouse(on: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE

func _apply_look() -> void:
	rotation.y = yaw
	if head:
		head.rotation.x = pitch

# ------------------------------------------------------------------ simulation
## Safety net: below this height (or far outside the level) the player is put back on the spawn point.
const FALL_LIMIT := -8.0
const FAR_LIMIT := 120.0
var rescues := 0

func out_of_bounds() -> bool:
	if global_position.y < FALL_LIMIT or not is_finite(global_position.y):
		return true
	return Vector2(global_position.x, global_position.z).length() > FAR_LIMIT and global_position.y < 50.0 and _world_level_far()

func _world_level_far() -> bool:
	var w := get_tree().get_first_node_in_group("world") if is_inside_tree() else null
	if w and w.has_method("get_level") and w.get_level():
		return global_position.distance_to((w.get_level() as Node3D).global_position) > FAR_LIMIT
	return true

## Back to the level's spawn point: drop what we hold, zero velocity, short fade from black.
func rescue() -> void:
	rescues += 1
	release_held()
	if seated:
		stand_up()
	climbing = false
	velocity = Vector3.ZERO
	_fall_speed = 0.0
	var w := get_tree().get_first_node_in_group("world")
	if w and w.has_method("place_local_player"):
		w.place_local_player()
	else:
		global_position = Vector3(0, 0.1, 0)
	velocity = Vector3.ZERO
	if hud:
		var fade := ColorRect.new()
		fade.color = Color(0, 0, 0, 1)
		fade.set_anchors_preset(Control.PRESET_FULL_RECT)
		fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud.add_child(fade)
		var tw := fade.create_tween()
		tw.tween_property(fade, "color:a", 0.0, 0.6)
		tw.tween_callback(fade.queue_free)

func _physics_process(dt: float) -> void:
	if out_of_bounds():
		rescue()
		return
	var ok := _input_allowed()
	var iv := Vector2.ZERO
	if ok:
		iv = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if seated:
		_seat_t += dt
		anim = "sit" if _seat_pose == "sit" else "idle"
		if ok and _seat_t > 0.5 and iv.length() > 0.5:
			stand_up()
		_update_focus()
		_net_tick(dt)
		return
	_climb_cd = maxf(0.0, _climb_cd - dt)
	if _ladder_step(dt, iv, ok):
		_net_tick(dt)
		return
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
		Sfx.play("jump", global_position, -8.0)
	var was_on_floor := on_floor
	move_and_slide()
	# landing dip
	if is_on_floor() and not was_on_floor:
		_land_dip = clampf(_fall_speed * 0.018, 0.0, 0.14)
		if _fall_speed > 2.5:
			Sfx.play("land", global_position, clampf(_fall_speed * 2.0 - 14.0, -14.0, 0.0))
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
	_update_feedback()
	_footsteps()

func _update_feedback() -> void:
	if hud:
		hud.visible = _input_allowed()
	if reticle:
		if held:
			reticle.mode = Reticle.Mode.HOLD
		elif focus:
			reticle.mode = Reticle.Mode.INTERACT
		elif _aim_grabbable:
			reticle.mode = Reticle.Mode.GRAB
		else:
			reticle.mode = Reticle.Mode.IDLE
	if beam:
		beam.visible = held != null and is_instance_valid(held)
		if beam.visible:
			var b := cam.global_basis
			var a := cam.global_position + b.x * 0.22 - b.y * 0.2 - b.z * 0.35
			var t := held.to_global(hold_local)
			var d := t - a
			if d.length() > 0.02:
				var up := Vector3.UP if absf(d.normalized().y) < 0.98 else Vector3.RIGHT
				beam.global_transform = Transform3D(Basis.looking_at(d, up).scaled_local(Vector3(1, 1, d.length())), (a + t) * 0.5)

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
	var eye_want := EYE_CROUCH if crouching else EYE_STAND
	if seated:
		eye_want = _seat_eye
	_eye = lerpf(_eye, eye_want, 1.0 - exp(-(6.0 if seated else 12.0) * dt))
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

# ------------------------------------------------------------------ ladders
## {b, t, fwd} for a ladder the player is at (global), or {}.
func _ladder_near(catch_radius: float) -> Dictionary:
	if not is_inside_tree():
		return {}
	for lad in get_tree().get_nodes_in_group("ladder"):
		if not (lad is Node3D) or not lad.is_inside_tree():
			continue
		var b: Vector3 = lad.global_transform * (lad.get_meta("bottom_local", Vector3.ZERO) as Vector3)
		var t: Vector3 = lad.global_transform * (lad.get_meta("top_local", Vector3.UP) as Vector3)
		var p := global_position
		if p.y < b.y - 0.2 or p.y > t.y + 0.35:
			continue
		var k := clampf((p.y - b.y) / maxf(0.01, t.y - b.y), 0.0, 1.0)
		var on := b.lerp(t, k)
		if Vector2(p.x - on.x, p.z - on.z).length() <= catch_radius:
			var fwd := Vector3(t.x - b.x, 0, t.z - b.z).normalized()
			return {"b": b, "t": t, "fwd": fwd}
	return {}

## Returns true while climbing (this frame handled).
func _ladder_step(dt: float, iv: Vector2, ok: bool) -> bool:
	var look := -global_basis.z
	look.y = 0
	look = look.normalized()
	if not climbing:
		if _climb_cd > 0.0 or held and held.mass > 12.0:
			return false
		var lad := _ladder_near(0.55 if is_on_floor() else 0.75)
		if lad.is_empty():
			return false
		var facing := look.dot(lad.fwd) > 0.25
		var at_bottom: bool = global_position.y < (lad.b as Vector3).y + 0.3
		# start: at the foot, facing the ladder, pushing forward — or falling into the hatch from above
		if (at_bottom and facing and iv.y < -0.3 and ok) or (not is_on_floor() and not at_bottom):
			climbing = true
			_ladder = lad
			velocity = Vector3.ZERO
			_crouch_off()
		else:
			return false
	var lb: Vector3 = _ladder.b
	var lt: Vector3 = _ladder.t
	var lf: Vector3 = _ladder.fwd
	var dir := -iv.y if ok else 0.0
	if look.dot(lf) < -0.2:
		dir = -dir  # looking away from the ladder: W goes down
	var p := global_position
	var k := clampf((p.y - lb.y) / maxf(0.01, lt.y - lb.y), 0.0, 1.0)
	var want := lb.lerp(lt, k)
	velocity = Vector3((want.x - p.x) * 12.0, dir * CLIMB_SPEED, (want.z - p.z) * 12.0)
	anim = "climb"
	_bob_t += dt * absf(dir) * 5.0
	# top: step off onto the floor upstairs
	if p.y >= lt.y - 0.03 and dir > 0.1:
		climbing = false
		_climb_cd = 0.5
		global_position = Vector3(lt.x, lt.y + 0.06, lt.z) + lf * 1.05
		velocity = Vector3.ZERO
		return true
	# bottom: feet on the floor and going down
	if p.y <= lb.y + 0.08 and dir < -0.1:
		climbing = false
		_climb_cd = 0.6
		velocity = -lf * 1.5
		return false
	if ok and Input.is_action_just_pressed("jump"):
		climbing = false
		_climb_cd = 0.8
		velocity = -lf * 2.2
		return false
	move_and_slide()
	if absf(dir) > 0.1 and int(_bob_t / PI) != int((_bob_t - dt * 5.0) / PI):
		Sfx.play("step_wood", global_position, -10.0)
	_update_hold(dt)
	_update_focus()
	return true

func _crouch_off() -> void:
	if crouching:
		_set_crouch(false)

# ------------------------------------------------------------------ footsteps
func _surface() -> String:
	if _world == null or not is_instance_valid(_world):
		_world = get_tree().get_first_node_in_group("world")
	if _world and _world.has_method("get_level"):
		var lv: Node = _world.get_level()
		if lv and lv.has_method("surface_at"):
			return str(lv.surface_at(lv.to_local(global_position)))
	return "concrete"

func _footsteps() -> void:
	var s := sin(_bob_t)
	if _bob_amt > 0.25 and is_on_floor() and signf(s) != signf(_step_side) and not climbing:
		Sfx.play("step_" + _surface(), global_position, -4.0 if _bob_amt > 1.1 else (-10.0 if crouching else -7.0))
	_step_side = s

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
	_aim_grabbable = false
	if _input_allowed() and held == null and not seated:
		var hit := _ray(GRAB_REACH)
		if not hit.is_empty():
			var c: Object = hit.collider
			_aim_grabbable = c is RigidBody3D and c.is_in_group("grabbable")
			if cam.global_position.distance_to(hit.position) <= REACH:
				f = find_interactable(c)
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
	Sfx.play("crate_grab" if body.is_in_group("ship_crate") else "grab", point, -4.0)

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
