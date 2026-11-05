extends Node
## Replicated company state cache (server is authoritative). Net feeds it; UI and world read it.

var state: Dictionary = {}
var me: Dictionary = {}
var members: Array = []
var code: String = ""

func apply_snapshot(s: Dictionary) -> void:
	state = s
	Bus.state_changed.emit(s.keys())

func apply_sections(data: Dictionary) -> void:
	for k in data:
		state[k] = data[k]
	Bus.state_changed.emit(data.keys())

func get_section(key: String, default: Variant = null) -> Variant:
	return state.get(key, default)

func has_company() -> bool:
	return not state.is_empty()
