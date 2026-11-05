extends Node
## Global signal bus — the only coupling between world (3D) and UI. See docs/ARCHITECTURE.md.

signal interact(kind: String, id: String)
signal focus_changed(prompt: String)
signal ui_modal_changed(open: bool)
signal state_changed(keys: Array)
signal notify(kind: String, title: String, body: String)
signal launch_show(product_id: String)
signal world_rebuild()
signal peers_changed(list: Array)
signal ship_feedback(crate_id: String, ok: bool)
signal settings_changed()
signal launch_finished(product_id: String)

var modal_open := false

func _ready() -> void:
	ui_modal_changed.connect(func(open: bool) -> void: modal_open = open)
