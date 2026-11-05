extends SceneTree
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
func _initialize() -> void:
	var L = load("res://ui/lib/loc.gd")
	var re := RegEx.create_from_string("L\\.(?:t|f)\\(\\s*\"((?:[^\"\\\\]|\\\\.)*)\"")
	var lits := {}
	for dir in ["res://ui", "res://net"]:
		for f in _files(dir):
			if not f.ends_with(".gd") or f.ends_with("loc.gd") or f.ends_with("loc_extra.gd"):
				continue
			for m in re.search_all(FileAccess.get_file_as_string(f)):
				lits[m.get_string(1)] = f
	var out := {}
	for lang in ["ru", "de", "zh"]:
		for k in lits:
			if not L.covered(k, lang) and k != "SILICON" and k != "OVERLORD":
				out[k] = lits[k]
	var keys := out.keys()
	keys.sort()
	for k in keys:
		print("MISSING\t", out[k].get_file(), "\t", k)
	quit(0)
