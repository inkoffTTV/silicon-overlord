extends Node3D
## Manual shipping (WORLD agent). Spawns `production.crates` as grabbable crates on a pallet zone near the door and
## ships a crate when it enters the dock's cargo area: Net.act("shipCrate", {crateId}) exactly once, crate slides in,
## van flashes + Sfx; on failure the crate is pushed back out. The world never decides the outcome itself.
## Crates that leave the state while idle (auto-ship / "Ship all" from the UI) hop into the van (or fade away).
## Setup (by the level): zone (Transform3D, local to this node: origin = first spot, +X columns, +Z rows), dock.

const CrateBody := preload("res://world/live/crate_body.gd")
const HQ := preload("res://world/live/hq_state.gd")

var zone := Transform3D.IDENTITY
var cols := 3
var rows := 2
var layers := 3
var spacing := Vector3(0.56, 0.37, 0.43)
var dock: Node3D            # ship_dock.gd
var crates := {}            # crate_id -> CrateBody
var homes := {}             # crate_id -> spot index
## Replace for tests: Callable(action, args) -> Dictionary (may be a coroutine). Defaults to Net.act.
var act_fn: Callable
const MAX_LOADED := 12

var _poll := 0.0

func _ready() -> void:
	if dock:
		dock.crate_entered.connect(_on_crate_entered)
	Bus.state_changed.connect(func(keys: Array) -> void:
		if keys.has("production") or keys.has("products"):
			refresh(Game.state))
	refresh(Game.state)

func refresh(s: Dictionary) -> void:
	var want := {}
	for c in HQ.crates(s):
		want[str(c.id)] = c
	for id in want:
		var c: Dictionary = want[id]
		if crates.has(id) and is_instance_valid(crates[id]):
			var cb: Node = crates[id]
			if int(c.get("units", 0)) != cb.units:
				cb.set_units(int(c.get("units", 0)))
		else:
			_spawn(s, c)
	var gone := []
	for id in crates:
		if not want.has(id):
			gone.append(id)
	var hop := 0
	for id in gone:
		var cb: Node = crates[id]
		crates.erase(id)
		homes.erase(id)
		if not is_instance_valid(cb):
			continue
		match str(cb.ship_state):
			"idle":
				if dock and hop < 8:
					_hop_into_dock(cb, hop * 0.18)
					hop += 1
				else:
					cb.vanish()
			"shipping":
				cb.gone_from_state = true
			_:
				pass
	if hop > 0 and dock:
		dock.flash(true, "")
		Sfx.play("ship_ok", dock.global_position + Vector3(0, 1, 0))

func spot_position(i: int) -> Vector3:
	var per := cols * rows
	var layer := (i / per) % layers
	var k := i % per
	var p := Vector3((k % cols) * spacing.x, layer * spacing.y + 0.2, (k / cols) * spacing.z)
	return global_transform * (zone * p)

func _free_spot() -> int:
	var used := {}
	for id in homes:
		used[homes[id]] = true
	for i in cols * rows * layers:
		if not used.has(i):
			return i
	return homes.size()

func _spawn(s: Dictionary, c: Dictionary) -> void:
	var cb: RigidBody3D = CrateBody.new()
	var pid := str(c.get("productId", ""))
	cb.setup(c, HQ.product_name(s, pid), HQ.product_color(s, pid))
	var spot := _free_spot()
	homes[cb.crate_id] = spot
	crates[cb.crate_id] = cb
	add_child(cb)
	var yaw := (global_transform.basis * zone.basis).get_euler().y
	cb.global_transform = Transform3D(Basis(Vector3.UP, yaw + deg_to_rad(randf_range(-4.0, 4.0))), spot_position(spot) + Vector3(0, 0.03, 0))

func crate_nodes() -> Array:
	return crates.values().filter(func(c: Variant) -> bool: return is_instance_valid(c))

func _process(delta: float) -> void:
	_poll -= delta
	if _poll > 0.0 or dock == null:
		return
	_poll = 0.4
	# catch crates that sit in the cargo area without a fresh body_entered (pushed back, dropped inside, ...)
	for b in dock.cargo.get_overlapping_bodies():
		if b is RigidBody3D and b.is_in_group("ship_crate"):
			_on_crate_entered(b)

func _on_crate_entered(cb: RigidBody3D) -> void:
	if not is_instance_valid(cb) or str(cb.get("ship_state")) != "idle":
		return
	if float(cb.get_meta("ship_cooldown", 0.0)) > Time.get_ticks_msec() * 0.001:
		return
	_ship(cb)

func _act(action: String, args: Dictionary) -> Dictionary:
	if act_fn.is_valid():
		var r: Variant = await act_fn.call(action, args)
		return r if r is Dictionary else {"ok": true}
	return await Net.act(action, args)

func _ship(cb: RigidBody3D) -> void:
	cb.ship_state = "shipping"
	var id: String = cb.crate_id
	for p in get_tree().get_nodes_in_group("local_player"):
		if p.get("held") == cb and p.has_method("release_held"):
			p.release_held()
	var slot: Transform3D = dock.global_transform * dock.slot_for(dock.loaded.size())
	_slide(cb, slot, 0.45)
	Sfx.play("crate_drop", cb.global_position)
	var r: Dictionary = await _act("shipCrate", {"crateId": id})
	if not is_instance_valid(self) or not is_instance_valid(cb):
		return
	if r.get("ok", false):
		cb.ship_state = "shipped"
		crates.erase(id)
		homes.erase(id)
		var data: Dictionary = r.get("data", {}) if r.get("data") is Dictionary else {}
		var n := int(data.get("units", cb.units))
		_load(cb)
		dock.flash(true, "+%s units" % CrateBody._fmt(n))
		Sfx.play("ship_ok", dock.global_position + Vector3(0, 1, 0))
		Bus.ship_feedback.emit(id, true)
	else:
		cb.ship_state = "idle"
		cb.set_meta("ship_cooldown", Time.get_ticks_msec() * 0.001 + 2.0)
		var out: Vector3 = dock.global_transform * Vector3(0, 0.75, -1.9)
		_kill_tween(cb)
		var tw := cb.create_tween()
		tw.tween_property(cb, "global_position", out, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_callback(func() -> void:
			cb.collision_layer = 1
			cb.collision_mask = 1
			cb.freeze = false
			cb.linear_velocity = dock.global_basis * Vector3(0, 1.0, -1.5))
		var err := str(r.get("error", "Can't ship"))
		dock.flash(false, err.substr(0, 28))
		Sfx.play("ship_fail", dock.global_position + Vector3(0, 1, 0))
		Bus.ship_feedback.emit(id, false)
		if cb.gone_from_state:
			cb.vanish()

func _slide(cb: RigidBody3D, to: Transform3D, t: float) -> void:
	cb.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	cb.freeze = true
	cb.collision_layer = 0
	cb.collision_mask = 0
	cb.linear_velocity = Vector3.ZERO
	cb.angular_velocity = Vector3.ZERO
	_kill_tween(cb)
	var tw := cb.create_tween()
	cb.set_meta("slide_tween", tw)
	tw.set_parallel(true)
	tw.tween_property(cb, "global_position", to.origin, t).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(cb, "global_basis", to.basis, t)

func _kill_tween(cb: Node) -> void:
	var old: Variant = cb.get_meta("slide_tween", null)
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()

## Crate stays inside the van as cargo (no longer interactable).
func _load(cb: RigidBody3D) -> void:
	cb.remove_from_group("interactable")
	cb.remove_from_group("grabbable")
	cb.remove_from_group("ship_crate")
	dock.loaded.append(cb)
	while dock.loaded.size() > MAX_LOADED:
		var old: Variant = dock.loaded.pop_front()
		if is_instance_valid(old):
			old.vanish()

func _hop_into_dock(cb: RigidBody3D, delay: float) -> void:
	cb.ship_state = "shipped"
	if cb.get_parent() == null:
		return
	for p in get_tree().get_nodes_in_group("local_player"):
		if p.get("held") == cb and p.has_method("release_held"):
			p.release_held()
	var slot: Transform3D = dock.global_transform * dock.slot_for(dock.loaded.size())
	cb.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	cb.freeze = true
	cb.collision_layer = 0
	cb.collision_mask = 0
	_load(cb)
	var from := cb.global_position
	var mid := (from + slot.origin) * 0.5 + Vector3(0, 1.4, 0)
	var tw := cb.create_tween()
	tw.tween_interval(delay)
	tw.tween_method(func(k: float) -> void:
		if is_instance_valid(cb):
			cb.global_position = from.lerp(mid, k).lerp(mid.lerp(slot.origin, k), k), 0.0, 1.0, 0.7)
	tw.tween_callback(func() -> void:
		if is_instance_valid(cb):
			cb.global_basis = slot.basis
			Sfx.play("crate_drop", cb.global_position))
