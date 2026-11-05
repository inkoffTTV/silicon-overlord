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
	# full zip needed when the exe-side files (voice/) are missing or too old
	var none: Dictionary = U.installed_full_info("")
	check(none.build == "0.0.0" and int(none.version) == 0, "no voice folder = pre-voice install")
	var vdir := "user://updates/voice_test"
	DirAccess.make_dir_recursive_absolute(vdir)
	var mf := FileAccess.open(vdir + "/manifest.json", FileAccess.WRITE)
	mf.store_string(JSON.stringify({"version": 1, "build": "0.3.1", "voices": {}}))
	mf.close()
	var inst: Dictionary = U.installed_full_info(ProjectSettings.globalize_path(vdir))
	check(inst.build == "0.3.1" and int(inst.version) == 1, "voice manifest read")
	check(not U.full_download_needed({"version": "0.3.2"}, none), "old manifest without full_required_min: pck update only (backward compatible)")
	check(U.full_download_needed({"version": "0.3.2", "full_required_min": "0.3.1", "voice_version": 1}, none), "0.3.0 install without voice/ -> full zip")
	check(not U.full_download_needed({"version": "0.3.2", "full_required_min": "0.3.1", "voice_version": 1}, inst), "install with voice v1 -> pck is enough")
	check(U.full_download_needed({"version": "0.4.0", "full_required_min": "0.3.1", "voice_version": 2}, inst), "newer voice_version -> full zip")
	check(U.full_download_needed({"version": "0.5.0", "full_required_min": "0.5.0"}, inst), "full_required_min above the installed build -> full zip")
	DirAccess.remove_absolute(vdir + "/manifest.json")
	DirAccess.remove_absolute(vdir)
	DirAccess.remove_absolute(target)
	print("updater_test: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(0 if fails == 0 else 1)
