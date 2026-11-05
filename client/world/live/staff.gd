extends Node3D
## Employees in the world (WORLD agent). Places one NPC per `employees.list` entry on a slot of its `station`
## (design -> desks, research -> whiteboard, assembly -> upstairs lines first then the bench, office -> sofa /
## spare desk). When a station is full the person sits on a cardboard box (overflow slots). Max MAX_SHOWN NPCs.
## Slots come from the level: level.staff_slots() -> {station: [{pos: Vector3 (global), yaw, pose, seat_h}]}
## plus "overflow". Rebuilds only the NPCs whose slot changed.

const Npc := preload("res://world/actors/npc_worker.gd")
const HQ := preload("res://world/live/hq_state.gd")
const Mats := preload("res://world/lib/mats.gd")
const Meshes := preload("res://world/lib/meshes.gd")
const MAX_SHOWN := 14

var level: Node3D
var npcs := {}        # employee id -> {node, key}

func _ready() -> void:
	Bus.state_changed.connect(func(keys: Array) -> void:
		if keys.has("employees") or keys.has("hq") or keys.has("production"):
			refresh.call_deferred(Game.state))
	refresh.call_deferred(Game.state)

## {employee id: slot dict} for the current state.
func assign(s: Dictionary) -> Dictionary:
	var slots: Dictionary = level.staff_slots() if level and level.has_method("staff_slots") else {}
	var used := {}
	var out := {}
	var overflow: Array = slots.get("overflow", [])
	var oi := 0
	var n := 0
	for e in HQ.employees(s):
		if n >= MAX_SHOWN:
			break
		var st := HQ.station_of(e)
		var list: Array = slots.get(st, [])
		var got := {}
		for i in list.size():
			var k := "%s:%d" % [st, i]
			if not used.has(k):
				used[k] = true
				got = list[i].duplicate()
				got["key"] = k
				break
		if got.is_empty() and oi < overflow.size():
			got = overflow[oi].duplicate()
			got["key"] = "overflow:%d" % oi
			got["box"] = true
			oi += 1
		if got.is_empty():
			continue
		out[str(e.get("id", ""))] = {"slot": got, "e": e}
		n += 1
	return out

func refresh(s: Dictionary) -> void:
	if not is_inside_tree():
		return
	var want := assign(s)
	for id in npcs.keys():
		if not want.has(id) or str(want[id].slot.key) != str(npcs[id].key):
			if is_instance_valid(npcs[id].node):
				npcs[id].node.queue_free()
			npcs.erase(id)
	for id in want:
		if npcs.has(id):
			continue
		var w: Dictionary = want[id]
		var slot: Dictionary = w.slot
		var npc: Node3D = Npc.new()
		add_child(npc)
		npc.setup(w.e, slot)
		npc.global_position = slot.pos
		npc.global_rotation = Vector3(0, float(slot.yaw), 0)
		if slot.get("box", false):
			_box_seat(npc)
		npcs[id] = {"node": npc, "key": slot.key}

## cardboard box to sit on (overflow)
func _box_seat(npc: Node3D) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = Meshes.cbox(Vector3(0.5, 0.42, 0.42), 0.02)
	mi.material_override = Mats.m("cardboard", Color(1.0, 0.95, 0.9))
	mi.position = Vector3(0, 0.21, -0.12)
	npc.add_child(mi)

## For tests: {station: count}
func counts() -> Dictionary:
	var out := {}
	for id in npcs:
		var n: Node = npcs[id].node
		if is_instance_valid(n):
			var k := str(npcs[id].key).split(":")[0]
			out[k] = int(out.get(k, 0)) + 1
	return out
