extends SceneTree
## Headless audio smoke test (AUDIO agent): every sound name plays in 2D/3D without errors, unknown names are safe,
## buses + settings (user://settings.cfg [audio]) are applied, music/ambient crossfade, loops attach, chat voices
## queue per speaker with distance-based volume, the world's avatar_talk is called, ducking kicks in.
##
##   <godot> --headless --path client -s tests/audio_smoke.gd

class ErrCounter extends Logger:
	var errors: Array = []
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _bt: Array) -> void:
		if error_type == Logger.ERROR_TYPE_WARNING:
			return
		if file.contains("alsa") or file.contains("display_server") or file.contains("pulse"):
			return
		errors.append("%s:%d %s %s %s" % [file, line, function, code, rationale])
	func _log_message(_m: String, _e: bool) -> void:
		pass

class FakeWorld extends Node3D:
	var talks: Array = []
	func avatar_talk(user_id: int, seconds: float, text: String) -> void:
		talks.append([user_id, seconds, text])

const SETTINGS := "user://settings.cfg"

var log_counter := ErrCounter.new()
var checks := 0
var failures: Array = []

func _initialize() -> void:
	OS.add_logger(log_counter)
	_run.call_deferred()
	create_timer(60).timeout.connect(func() -> void:
		print("audio_smoke: TIMEOUT")
		quit(2))

func check(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		failures.append(what)
		print("  FAIL ", what)

func frames(n: int = 2) -> void:
	for i in n:
		await process_frame

func _run() -> void:
	var Sfx: Node = root.get_node("Sfx")
	var Bus: Node = root.get_node("Bus")
	var Bank = load("res://audio/bank_data.gd")
	var V = load("res://audio/voice.gd")
	# keep the user's settings file intact
	var backup := FileAccess.get_file_as_string(SETTINGS) if FileAccess.file_exists(SETTINGS) else ""
	await frames(3)

	print("audio_smoke: buses")
	for b in ["Music", "SFX", "UI", "Voice", "Ambient"]:
		check(AudioServer.get_bus_index(b) >= 0, "bus " + b)
	check(AudioServer.get_bus_send(AudioServer.get_bus_index("Ambient")) == "SFX", "Ambient sends to SFX")
	check(AudioServer.get_bus_send(AudioServer.get_bus_index("Music")) == "Master", "Music sends to Master")

	print("audio_smoke: settings")
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	if cfg.has_section("audio"):
		cfg.erase_section("audio")
	cfg.save(SETTINGS)
	Sfx.apply_settings()
	cfg = ConfigFile.new()
	cfg.load(SETTINGS)
	for k in ["master", "music", "sfx", "ui", "voice", "voice_mode"]:
		check(cfg.has_section_key("audio", k), "default written: " + k)
	cfg.set_value("audio", "music", 0.25)
	cfg.set_value("audio", "sfx", 0.0)
	cfg.set_value("audio", "voice_mode", "robot")
	cfg.save(SETTINGS)
	Sfx.apply_settings()
	check(absf(Sfx.bus_volume_db("Music") - linear_to_db(0.25)) < 0.6, "music volume applied (%.1f dB)" % Sfx.bus_volume_db("Music"))
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")), "sfx 0 mutes the SFX bus")
	check(Sfx.voice.mode == "robot", "voice_mode robot applied")
	cfg.set_value("audio", "sfx", 0.8)
	cfg.save(SETTINGS)
	Bus.settings_changed.emit()
	check(not AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")), "settings_changed re-reads the file")

	print("audio_smoke: every sound")
	var holder := Node3D.new()
	root.add_child(holder)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.make_current()
	var n_sounds := 0
	for sname in Bank.SOUNDS:
		var kind: String = Bank.KIND[sname]
		if kind in ["music", "ambient", "voice"] or sname in Bank.LOOPS:
			continue
		Sfx.play(sname)
		Sfx.play(sname, Vector3(randf() * 10, 1, randf() * 10))
		Sfx.play(sname, holder)
		n_sounds += 1
		if n_sounds % 10 == 0:
			await frames(1)
	check(n_sounds >= 50, "at least 50 one-shot names (%d)" % n_sounds)
	for u in ["click", "hover", "confirm", "back", "error", "notify", "success", "coin", "cash_register", "research_done"]:
		check(Sfx.has_sound(u), "ui sound exists: " + u)
		Sfx.ui(u)
	for w in ["step_concrete", "step_wood", "impact_cardboard", "crate_grab", "van_door_close", "ship_ok", "solder"]:
		check(Sfx.has_sound(w), "world sound exists: " + w)
	var kids := Sfx.get_child_count()
	for i in 60:
		Sfx.play("impact_wood" if i % 2 else "step_concrete", Vector3(i, 0, 0))
		if i % 20 == 0:
			await frames(1)
	check(Sfx.get_child_count() == kids, "pooled: no new players created (%d -> %d)" % [kids, Sfx.get_child_count()])

	print("audio_smoke: unknown names")
	var before: int = Sfx.debug_log.size()
	Sfx.play("definitely_not_a_sound", Vector3.ZERO)
	Sfx.play("definitely_not_a_sound")
	Sfx.ui("definitely_not_a_sound")
	Sfx.music("no_such_track")
	Sfx.ambient("no_such_room")
	check(Sfx.loop("no_such_loop", holder) == null, "unknown loop returns null")
	Sfx.play("")
	check(Sfx.debug_log.size() - before == 4, "one debug line per unknown name (%d)" % (Sfx.debug_log.size() - before))

	print("audio_smoke: music / ambient / loops")
	Sfx.music("game")
	check(Sfx.music_name == "game", "music game")
	Sfx.music("no_such_track")
	check(Sfx.music_name == "game", "unknown track keeps current music")
	Sfx.ambient("garage")
	check(Sfx.ambient_name == "garage", "ambient garage")
	Sfx.ambient("outdoor")
	Sfx.ambient("")
	check(Sfx.ambient_name == "", "ambient stop")
	var lp: Node = Sfx.loop("machine_hum", holder)
	check(lp is AudioStreamPlayer3D and lp.get_parent() == holder, "loop attached to the node")
	check(lp.stream != null and lp.stream.get("loop") == true, "loop stream loops")
	Sfx.stop_loop(lp)
	Sfx.play("conveyor")  # loop name via play(): safe, just a debug line
	Bus.launch_show.emit("p1")
	check(Sfx.music_name == "launch", "launch_show -> launch music")
	Bus.launch_finished.emit("p1")
	check(Sfx.music_name == "game", "launch_finished -> back to game music")
	Bus.notify.emit("success", "Research done: ARM", "x")
	await frames(2)

	print("audio_smoke: voices")
	check(V.detect_lang("Привет, как дела?", "en") == "ru", "cyrillic -> ru")
	check(V.detect_lang("こんにちは", "en") == "ja", "kana -> ja")
	check(V.detect_lang("你好世界", "en") == "zh", "han -> zh")
	check(V.detect_lang("안녕하세요", "en") == "ko", "hangul -> ko")
	check(V.detect_lang("hello there", "en") == "en", "latin -> en")
	check(V.detect_lang("hello there", "ru") == "en", "latin text in a ru game -> en voice")
	check(V.detect_lang("123 !!", "ru") == "ru", "no letters -> game language")
	check(V.detect_lang("Привіт! Зберемо телефон?", "en") == "uk", "ukrainian letters -> uk")
	check(V.detect_lang("Die Größe passt", "en") == "de", "umlaut -> de")
	check(V.detect_lang("¡Hola amigo!", "en") == "es", "¡ -> es")
	check(V.detect_lang("Cześć wszystkim", "en") == "pl", "ś/ć -> pl")
	check(V.detect_lang("Merhaba, nasılsın?", "en") == "tr", "ı -> tr")
	check(V.detect_lang("hello", "de") == "de", "plain latin in a German game -> de")
	check(str(Sfx.voice.speak(3, "T", "Hallo", null, "de").get("lang", "")) == "de", "forced language")
	Sfx.voice.stop_all()
	check(V.distance_volume(Vector3.ZERO, Vector3(0, 0, 2)) == 1.0, "close = full volume")
	check(V.distance_volume(Vector3.ZERO, Vector3(0, 0, 50)) == 0.0, "far = silent")
	var mid: float = V.distance_volume(Vector3.ZERO, Vector3(0, 0, 15))
	check(mid > 0.05 and mid < 0.9, "mid distance in between (%.2f)" % mid)
	check(V.distance_volume(null, Vector3(0, 0, 50)) == 1.0, "no listener = full volume")
	var t1: Dictionary = V.traits(1)
	var t2: Dictionary = V.traits(2)
	check(t1.pitch != t2.pitch and V.traits(1).pitch == t1.pitch, "per-user voice traits are distinct and stable")
	check(V.clean_text("x".repeat(500)).length() == 200, "200 char cap")
	check(V.clean_text("  a\n\tb  ") == "a b", "control chars cleaned")

	var world := FakeWorld.new()
	world.add_to_group("world")
	root.add_child(world)
	cam.global_position = Vector3.ZERO
	var voice: Node = Sfx.voice
	voice.speak(7, "Mira", "hello there", Vector3(0, 0, 12))
	voice.speak(7, "Mira", "second line", Vector3(0, 0, 12))
	Sfx.speak(8, "Oleg", "Привет!", Vector3(0, 0, 1))
	check(voice.queue_size(7) == 2, "two lines queued for speaker 7")
	await frames(3)
	check(voice.is_speaking(7) and voice.is_speaking(8), "speakers 7 and 8 talk at the same time")
	check(voice.queue_size(7) == 1, "second line of 7 waits")
	var l7: Dictionary = {}
	var l8: Dictionary = {}
	for l in voice.history:
		if l.user_id == 7 and l7.is_empty():
			l7 = l
		if l.user_id == 8:
			l8 = l
	check(not l7.is_empty() and absf(float(l7.volume) - V.distance_volume(Vector3.ZERO, Vector3(0, 0, 12))) < 0.001, "volume by distance for 7")
	check(not l8.is_empty() and float(l8.volume) == 1.0 and str(l8.lang) == "ru", "close speaker 8: full volume, ru")
	check(str(l7.get("engine", "")) == "robot", "headless/robot mode uses the robot voice")
	check(world.talks.size() >= 2 and float(world.talks[0][1]) > 0.3, "world.avatar_talk called with seconds")
	await frames(20)
	check(Sfx.bus_volume_db("Music") < linear_to_db(0.25) - 1.0, "music ducks while someone speaks (%.1f dB)" % Sfx.bus_volume_db("Music"))
	# peers position fallback
	Bus.peers_changed.emit([{"userId": 9, "p": [100.0, 0.0, 0.0]}])
	Sfx.speak(9, "Far", "can you hear me?")
	await frames(3)
	var l9: Dictionary = voice.last_line
	check(l9.get("user_id", -1) == 9 and float(l9.volume) == 0.0, "far peer (from peers list) is silent")
	cfg.set_value("audio", "voice_mode", "off")
	cfg.save(SETTINGS)
	Sfx.apply_settings()
	var talks_before: int = world.talks.size()
	Sfx.speak(10, "Mute", "shh")
	await frames(3)
	check(str(voice.last_line.get("engine", "")) == "off" and world.talks.size() == talks_before + 1, "voice off: silent but the avatar still talks")
	voice.stop_all()
	check(voice.queue_size(7) == 0, "stop_all clears queues")

	print("audio_smoke: automatic button sounds")
	var btn := Button.new()
	root.add_child(btn)
	await frames(1)
	Sfx._last_play.erase("click")
	btn.pressed.emit()
	await frames(2)
	check(Sfx._last_play.has("click"), "buttons click by themselves")
	var quiet := Button.new()
	quiet.set_meta("sfx", "")
	root.add_child(quiet)
	await frames(1)
	Sfx._last_play.erase("click")
	quiet.pressed.emit()
	await frames(2)
	check(not Sfx._last_play.has("click"), "meta sfx='' silences a button")
	var own := Button.new()
	root.add_child(own)
	own.pressed.connect(func() -> void: Sfx.ui("confirm"))
	await frames(1)
	Sfx._last_play.erase("click")
	await frames(3)
	own.pressed.emit()
	await frames(2)
	check(not Sfx._last_play.has("click"), "no default click when the handler plays its own UI sound")

	for n in [holder, cam, world, btn, quiet, own]:
		n.queue_free()
	Sfx.stop_all()
	check(Sfx.music_name == "" and Sfx.voice.speaking_count() == 0, "stop_all silences everything")
	# restore the settings file
	if backup != "":
		var f := FileAccess.open(SETTINGS, FileAccess.WRITE)
		f.store_string(backup)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	await frames(2)
	for e in log_counter.errors:
		failures.append("engine error: " + str(e))
		print("  ERR ", e)
	print("audio_smoke: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
