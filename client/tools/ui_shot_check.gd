extends SceneTree
## Compile check for every UI/net/phone script (headless): godot --headless --path client -s tools/ui_shot_check.gd
func _initialize() -> void:
	var bad := 0
	for dir in ["res://ui", "res://net", "res://phone", "res://tests"]:
		for f in _files(dir):
			if f.ends_with(".gd"):
				var s: Variant = load(f)
				if s == null or not (s as GDScript).can_instantiate():
					print("FAIL ", f)
					bad += 1
	print("checked, failures: ", bad)
	quit(1 if bad > 0 else 0)

func _files(dir: String) -> Array:
	var out := []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		out.append(dir + "/" + f)
	for sub in d.get_directories():
		out.append_array(_files(dir + "/" + sub))
	return out
