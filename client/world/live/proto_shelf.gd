extends Node
## Finished prototypes on the shelf (WORLD agent). The level's phone_shelf() registers stands
## ({anchor: Node3D, placeholder: Node3D, tag: Label3D}); every product that left Development gets its real
## 3D model (phone_builder, blueprint colours) on a stand, newest first, with its name on the shelf lip.

const HQ := preload("res://world/live/hq_state.gd")

var stands: Array = []
var _key := ""

func _ready() -> void:
	Bus.state_changed.connect(func(keys: Array) -> void:
		if keys.has("products") or keys.has("blueprints"):
			refresh(Game.state))
	refresh.call_deferred(Game.state)

func refresh(s: Dictionary) -> void:
	var prods := HQ.finished_products(s)
	var key := ",".join(prods.map(func(p: Dictionary) -> String: return "%s:%s:%s" % [p.get("id", ""), p.get("name", ""), p.get("blueprintVersion", "")]))
	if key == _key:
		return
	_key = key
	for i in stands.size():
		var st: Dictionary = stands[i]
		var anchor: Node3D = st.anchor
		if not is_instance_valid(anchor):
			continue
		for c in anchor.get_children():
			c.queue_free()
		var p: Dictionary = prods[i] if i < prods.size() else {}
		var m: Node3D = HQ.phone_model(s, p, 0.1) if not p.is_empty() else null
		if is_instance_valid(st.placeholder):
			st.placeholder.visible = m == null
		if m:
			anchor.add_child(m)
		if is_instance_valid(st.tag):
			st.tag.text = str(p.get("name", "")).to_upper().substr(0, 12) if m else str(st.get("default_tag", ""))
