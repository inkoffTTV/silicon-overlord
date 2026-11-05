extends SceneTree
## Headless test for core/updater.gd: version compare, download + sha256 verification against a local HTTP server.
var fails := 0
func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok: fails += 1

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var U = load("res://core/updater.gd")
	check(U.compare_versions("0.2.0", "0.1.9") == 1, "0.2.0 > 0.1.9")
	check(U.compare_versions("0.10.0", "0.9.9") == 1, "0.10.0 > 0.9.9 (numeric, not text)")
	check(U.compare_versions("1.0", "1.0.0") == 0, "1.0 == 1.0.0")
	check(U.compare_versions("0.1.2", "0.2.0") == -1, "0.1.2 < 0.2.0")
	# local server with a fake pack
	var dir := OS.get_environment("UPD_DIR")
	var port := int(OS.get_environment("UPD_PORT"))
	var payload := FileAccess.get_file_as_bytes(dir + "/fake.pck")
	var sha := FileAccess.get_sha256(dir + "/fake.pck")
	var up = U.new()
	root.add_child(up)
	DirAccess.make_dir_recursive_absolute("user://updates")
	var target := "user://updates/game_9.9.9.pck"
	if FileAccess.file_exists(target): DirAccess.remove_absolute(target)
	var ok: bool = await up._download_pack("http://127.0.0.1:%d/fake.pck" % port, target, sha, payload.size())
	check(ok and FileAccess.file_exists(target), "download with correct sha256 is accepted")
	check(FileAccess.get_sha256(target) == sha, "downloaded bytes match")
	var bad: bool = await up._download_pack("http://127.0.0.1:%d/fake.pck" % port, "user://updates/game_9.9.8.pck", "00" + sha.substr(2), payload.size())
	check(not bad and not FileAccess.file_exists("user://updates/game_9.9.8.pck"), "wrong sha256 is rejected and nothing is kept")
	var missing: bool = await up._download_pack("http://127.0.0.1:%d/nope.pck" % port, "user://updates/game_9.9.7.pck", sha, 0)
	check(not missing, "404 is rejected")
	check(not up._enabled(), "updater is disabled in headless/editor runs")
	DirAccess.remove_absolute(target)
	print("updater_test: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(0 if fails == 0 else 1)
