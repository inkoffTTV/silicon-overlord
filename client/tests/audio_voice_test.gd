extends SceneTree
## Character voice pipeline test (AUDIO agent, docs/VOICE.md). Headless:
##   <godot> --headless --path client -s tests/audio_voice_test.gd
## 1. pure helpers (JSON escaping, WAV parse/build, language → voice, per-user pitch)
## 2. fake in-process synthesizer: queue per speaker, effect bus per speaker, 3D position, cache, latency < 1 s
## 3. fallback chain: missing piper → robot; synthesis too slow → robot
## 4. the real process protocol through client/tests/audio_fake_piper.py (python3), persistent process
## 5. real piper if SO_VOICE_DIR points at a voice folder with a Linux piper (prints latency; skipped otherwise)
## 6. settings: 0.3.0 "tts" default migrates to "character", voice_pitch applied
## 7. regressions: other scripts (Greek, Arabic...) never reach piper, 3D loudness = distance_volume (smooth to 30 m),
##    the disk cache is pruned while the game runs, missing Visual C++ runtime = piper not started.
## Runs on its own TTS cache folder (SO_TTS_CACHE) and settings file (Sfx.settings_path), so the game or parallel
## tests sharing user:// cannot make it fail; the real user://settings.cfg and user://tts are not touched.

const CharTTS := preload("res://audio/char_tts.gd")
const V := preload("res://audio/voice.gd")
var SETTINGS := "user://audio_voice_test_%d.cfg" % OS.get_process_id()
var CACHE := "user://audio_voice_test_tts_%d" % OS.get_process_id()

class FakeWorld extends Node3D:
	var talks: Array = []
	func avatar_talk(user_id: int, seconds: float, text: String) -> void:
		talks.append([user_id, seconds, text])

var checks := 0
var failures: Array = []
var latency: Array = []

func _initialize() -> void:
	_run.call_deferred()
	create_timer(90).timeout.connect(func() -> void:
		print("audio_voice_test: TIMEOUT")
		quit(2))

func check(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		failures.append(what)
		print("  FAIL ", what)
	else:
		print("  ok   ", what)

func frames(n: int = 2) -> void:
	for i in n:
		await process_frame

## Wait until speaker uid has started a line (history grows) or the timeout passes.
func wait_line(voice: Node, uid: int, after: int, timeout_ms: int) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < timeout_ms:
		await process_frame
		for i in range(voice.history.size() - 1, -1, -1):
			var l: Dictionary = voice.history[i]
			if int(l.user_id) == uid and int(l.get("t_queued", 0)) >= after:
				return l
	return {}

func _run() -> void:
	OS.set_environment("SO_TTS_CACHE", CACHE)
	var Sfx: Node = root.get_node("Sfx")
	Sfx.settings_path = SETTINGS
	var voice: Node = Sfx.voice
	await frames(3)

	print("audio_voice_test: helpers")
	var j := CharTTS.json_line("Привет \"bot\" \\ 😀")
	var ascii := true
	for i in j.length():
		ascii = ascii and j.unicode_at(i) < 127
	check(ascii, "json line is plain ASCII")
	var parsed: Variant = JSON.parse_string(j)
	check(parsed is Dictionary and str(parsed.text) == "Привет \"bot\" \\ 😀", "json line round-trips Cyrillic, quotes, emoji")
	var pcm := PackedByteArray()
	pcm.resize(2205 * 2)
	for i in 2205:
		pcm.encode_s16(i * 2, int(sin(i * 0.1) * 10000))
	var raw := CharTTS.parse_wav(CharTTS.wav_bytes(pcm, 22050))
	check(int(raw.get("rate", 0)) == 22050 and (raw.get("pcm", PackedByteArray()) as PackedByteArray).size() == pcm.size(), "WAV write/parse round trip")
	check(CharTTS.parse_wav(PackedByteArray([1, 2, 3])).is_empty(), "garbage is not a WAV")
	var st: AudioStreamWAV = CharTTS.build_stream(raw, {"ring_hz": 50.0, "crackle": true, "seed": 3})
	var expect := 0.1 + CharTTS.CRACKLE_IN + CharTTS.CRACKLE_OUT
	check(absf(st.get_length() - expect) < 0.01, "stream = line + squelch + crackle (%.3f s)" % st.get_length())
	var dry: AudioStreamWAV = CharTTS.build_stream(raw, {"crackle": false})
	check(absf(dry.get_length() - 0.1) < 0.005, "no crackle when disabled")
	check(V.char_lang("ru", true, true, false) == "ru" and V.char_lang("uk", true, true, false) == "ru", "Cyrillic (ru/uk) -> Russian voice")
	check(V.char_lang("en", true, true, false) == "en", "en -> English voice")
	check(V.char_lang("de", true, true, false) == "en" and V.char_lang("de", true, true, true) == "", "de -> English voice, or the OS voice when there is one")
	check(V.char_lang("ja", true, true, false) == "", "ja without OS voice -> robot")
	var lo := 9.0
	var hi := 0.0
	for uid in range(1, 200):
		var p: float = V.traits(uid).char_pitch
		lo = minf(lo, p)
		hi = maxf(hi, p)
	check(lo < 0.75 and hi > 1.45, "per-user pitch spans deep..squeaky (%.2f..%.2f)" % [lo, hi])
	var big := ""
	for i in 60:
		big += "слово "
	check(V.clean_text(big).length() <= 200, "200 char cap")

	print("audio_voice_test: fake synthesizer")
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.make_current()
	cam.global_position = Vector3.ZERO
	var world := FakeWorld.new()
	world.add_to_group("world")
	root.add_child(world)
	voice.tts.shutdown()
	voice.tts = CharTTS.new()
	voice.tts.use_fake()
	voice.tts.fake_delay_ms = 150
	voice.mode = "character"
	var t := Time.get_ticks_msec()
	var text_ru := "Привет, это тест голоса %d" % t
	voice.speak(21, "Mira", text_ru, Vector3(0, 0, 10))
	voice.speak(21, "Mira", "second line %d" % t, Vector3(0, 0, 10))
	voice.speak(22, "Oleg", "Hello there %d" % t, Vector3(3, 0, 0))
	check(voice.queue_size(21) == 2, "two lines queued for speaker 21")
	var l21 := await wait_line(voice, 21, t, 3000)
	var l22 := await wait_line(voice, 22, t, 3000)
	check(str(l21.get("engine", "")) == "character" and str(l21.get("char_lang", "")) == "ru", "Cyrillic line spoken by the Russian character voice")
	check(str(l22.get("engine", "")) == "character" and str(l22.get("char_lang", "")) == "en", "Latin line spoken by the English character voice")
	check(int(l21.get("latency_ms", 99999)) < 1000, "latency < 1 s (%d ms, fake synth 150 ms)" % int(l21.get("latency_ms", -1)))
	latency.append(["fake (in-process, 150 ms synth)", int(l21.get("latency_ms", -1))])
	check(voice.is_speaking(21) and voice.queue_size(21) == 1, "speaker 21 talks, its second line waits")
	var bus := str(l21.get("bus", ""))
	var bi := AudioServer.get_bus_index(bus)
	check(bus.begins_with("VoiceFx") and bi >= 0 and AudioServer.get_bus_send(bi) == "Voice", "own effect bus per speaker -> Voice (%s)" % bus)
	check(bi >= 0 and AudioServer.get_bus_effect_count(bi) == 7, "effect chain: pitch, chorus, distortion, HP, LP, EQ, limiter")
	var ps := AudioServer.get_bus_effect(bi, 0) as AudioEffectPitchShift if bi >= 0 else null
	check(ps != null and absf(ps.pitch_scale - voice.pitch_for(21)) < 0.001, "pitch shift = speaker's pitch (%.2f)" % voice.pitch_for(21))
	check(str(l22.get("bus", "")) != bus, "different speakers use different buses")
	var c21: Dictionary = voice._char.get(21, {})
	var p3: AudioStreamPlayer3D = c21.get("p3d")
	check(p3 != null and p3.global_position.distance_to(Vector3(0, 0, 10)) < 0.01 and p3.max_distance == 30.0, "3D voice at the speaker, fades out by 30 m")
	check(world.talks.size() >= 2 and float(world.talks[0][1]) > 0.5, "avatar_talk gets the real line length")
	# cache: the same text again comes from the cache
	await wait_line(voice, 21, t + 1, 6000)
	var t2 := Time.get_ticks_msec()
	voice.speak(23, "Echo", text_ru, Vector3(0, 0, 2))
	var l23 := await wait_line(voice, 23, t2, 3000)
	check(str(l23.get("source", "")) in ["memory", "disk"], "identical line comes from the cache (%s, %d ms)" % [l23.get("source", "?"), int(l23.get("latency_ms", -1))])
	latency.append(["cached line", int(l23.get("latency_ms", -1))])
	var key := CharTTS.cache_key(text_ru, "ru", "fake")
	check(voice.tts.cache_dir == CACHE and FileAccess.file_exists(CACHE.path_join("%s.wav" % key)), "WAV cached in the TTS cache folder")
	# own pitch from settings
	voice.own_pitch = 0.55
	check(absf(voice.pitch_for(0) - 0.55) < 0.001, "your own pitch comes from settings")
	voice.user_pitch[30] = 1.9
	check(absf(voice.pitch_for(30) - 1.9) < 0.001, "pitch sent by the server wins over the hash")
	voice.set_peer_positions([{"userId": 31, "p": [0, 0, 0], "voicePitch": 0.7}])
	check(absf(voice.pitch_for(31) - 0.7) < 0.001, "peers voicePitch is read")
	voice.stop_all()

	print("audio_voice_test: fallbacks")
	voice.tts.shutdown()
	voice.tts = CharTTS.new()
	# a "piper" that reads the line and exits without audio (broken install)
	voice.tts.use_command(PackedStringArray(["python3", "-c", "import sys; sys.stdin.readline()"]), ["ru", "en"])
	var t3 := Time.get_ticks_msec()
	voice.speak(24, "Nope", "no piper here", Vector3(0, 0, 2))
	var l24 := await wait_line(voice, 24, t3, 4500)
	check(str(l24.get("engine", "")) == "robot", "broken piper -> robot voice (OS TTS is off in headless)")
	voice.stop_all()
	voice.tts.shutdown()
	voice.tts = CharTTS.new()
	voice.tts.use_fake()
	voice.tts.fake_delay_ms = 4200
	var t4 := Time.get_ticks_msec()
	voice.speak(25, "Slow", "too slow line %d" % t4, Vector3(0, 0, 2))
	var l25 := await wait_line(voice, 25, t4, 6000)
	check(str(l25.get("engine", "")) == "robot" and str(l25.get("char_error", "")) == "timeout", "synthesis slower than %d ms -> robot" % V.SYNTH_WAIT_MS)
	voice.stop_all()
	voice.tts.shutdown()
	voice.mode = "off"
	var t5 := Time.get_ticks_msec()
	voice.speak(26, "Mute", "shh")
	var l26 := await wait_line(voice, 26, t5, 1000)
	check(str(l26.get("engine", "")) == "off", "voice off: silent")
	voice.mode = "character"

	print("audio_voice_test: piper protocol (fake process)")
	var script := ProjectSettings.globalize_path("res://tests/audio_fake_piper.py")
	var out := []
	if OS.execute("python3", ["--version"], out) == 0:
		voice.tts = CharTTS.new()
		voice.tts.use_command(PackedStringArray(["python3", script]), ["ru", "en"])
		voice.tts.prewarm(["ru", "en"])
		await create_timer(0.5).timeout
		var t6 := Time.get_ticks_msec()
		voice.speak(27, "Proc", "Процесс номер %d" % t6, Vector3(0, 0, 3))
		voice.speak(28, "Proc", "process line %d" % t6, Vector3(0, 0, 3))
		var l27 := await wait_line(voice, 27, t6, 4000)
		var l28 := await wait_line(voice, 28, t6, 4000)
		check(str(l27.get("engine", "")) == "character" and str(l27.get("source", "")) == "piper", "line synthesized through the piper pipe")
		check(str(l28.get("engine", "")) == "character", "second language through its own process")
		check(int(l27.get("latency_ms", 99999)) < 1000, "pipe latency < 1 s (%d ms)" % int(l27.get("latency_ms", -1)))
		latency.append(["piper protocol, fake process", int(l27.get("latency_ms", -1))])
		var pid_before := int((voice.tts._procs.get("ru", {}) as Dictionary).get("pid", -1))
		var t7 := Time.get_ticks_msec()
		voice.speak(29, "Proc", "ещё одна строка %d" % t7, Vector3(0, 0, 3))
		var l29 := await wait_line(voice, 29, t7, 4000)
		check(str(l29.get("engine", "")) == "character" and int((voice.tts._procs.get("ru", {}) as Dictionary).get("pid", -2)) == pid_before, "the process stays alive between lines")
		var leftovers := DirAccess.get_files_at(CACHE.path_join("out"))
		check(leftovers.is_empty(), "piper output files are moved into the cache")
		voice.stop_all()
		voice.tts.shutdown()
		check(voice.tts._procs.is_empty() and OS.execute("sh", ["-c", "kill -0 %d 2>/dev/null" % pid_before]) != 0, "shutdown kills the piper processes")
	else:
		print("  skip  python3 not found")

	print("audio_voice_test: voice folder discovery")
	var vf := ProjectSettings.globalize_path("user://voice_fake_%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(vf + "/piper/espeak-ng-data")
	for fn in ["piper/piper", "piper/piper.exe", "ru_RU-x.onnx", "en_US-y.onnx"]:
		var ff := FileAccess.open(vf + "/" + fn, FileAccess.WRITE)
		ff.store_string("x")
		ff.close()
	var mfile := FileAccess.open(vf + "/manifest.json", FileAccess.WRITE)
	mfile.store_string(JSON.stringify({"version": 1, "build": "0.3.1", "piper": {"windows": "piper/piper.exe", "linux": "piper/piper", "macos": "piper/piper"},
		"voices": {"ru": "ru_RU-x.onnx", "en": "en_US-y.onnx", "de": "missing.onnx"}}))
	mfile.close()
	var disc := CharTTS.new()
	check(disc.setup(vf) and disc.has_lang("ru") and disc.has_lang("en") and not disc.has_lang("de"), "voice folder found: piper + ru/en models, missing model ignored")
	check(disc.command.size() == 3 and disc.command[1] == "--espeak_data", "espeak-ng-data passed to piper")
	var nodir := CharTTS.new()
	check(not nodir.setup(vf + "_nope") and not nodir.available, "no voice folder -> not available")
	for fn in ["piper/espeak-ng-data", "piper/piper", "piper/piper.exe", "ru_RU-x.onnx", "en_US-y.onnx", "manifest.json"]:
		DirAccess.remove_absolute(vf + "/" + fn)
	DirAccess.remove_absolute(vf + "/piper")
	DirAccess.remove_absolute(vf)

	print("audio_voice_test: real piper")
	var real := CharTTS.new()
	if OS.get_environment("SO_VOICE_DIR") != "" and real.setup(OS.get_environment("SO_VOICE_DIR")):
		real.prewarm(["ru", "en"])
		for lt in [["ru", "Привет! Соберём телефон?"], ["en", "Hello! Shall we build a phone?"], ["ru", "Это второй русский тест %d" % Time.get_ticks_msec()]]:
			var id: int = real.request(lt[1], lt[0], {})
			var tr := Time.get_ticks_msec()
			var r: Variant = null
			while r == null and Time.get_ticks_msec() - tr < 15000:
				await process_frame
				r = real.poll(id)
			check(r is Dictionary and bool(r.ok), "real piper %s: %s" % [lt[0], lt[1]])
			if r is Dictionary:
				latency.append(["real piper " + str(lt[0]) + " (" + str(r.get("source", "")) + ")", int(r.get("wait_ms", -1))])
		real.shutdown()
	else:
		print("  skip  no Linux piper (set SO_VOICE_DIR to a voice folder, see docs/VOICE.md)")

	print("audio_voice_test: settings")
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "voice_mode", "tts")   # what 0.3.0 wrote by default
	cfg.set_value("audio", "voice", 0.9)
	cfg.save(SETTINGS)
	Sfx.apply_settings()
	cfg = ConfigFile.new()
	cfg.load(SETTINGS)
	check(str(cfg.get_value("audio", "voice_mode", "")) == "character" and voice.mode == "character", "0.3.0 default 'tts' -> character voice")
	cfg.set_value("audio", "voice_mode", "tts")
	cfg.set_value("audio", "voice_pitch", 1.7)
	cfg.save(SETTINGS)
	Sfx.apply_settings()
	check(voice.mode == "tts" and absf(voice.own_pitch - 1.7) < 0.001, "a chosen 'tts' stays; voice_pitch applied")
	check(not voice.preferred.has("pitch") and not voice.preferred.has("rev"), "voice_pitch/voice_rev are not OS voice ids")

	await _regressions(voice, world, cam)

	cam.queue_free()
	world.queue_free()
	var own := ConfigFile.new()
	check(own.load(SETTINGS) == OK and float(own.get_value("audio", "voice_pitch", 0.0)) == 1.7, "settings checks ran on the test's own settings file")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	Sfx.settings_path = Sfx.SETTINGS
	Sfx.apply_settings()
	_rm_tree(CACHE)
	print("audio_voice_test: latency")
	for l in latency:
		print("  %-40s %5d ms" % [l[0], l[1]])
	print("audio_voice_test: %d checks, %d failures" % [checks, failures.size()])
	for f in failures:
		print("  FAILED: ", f)
	quit(0 if failures.is_empty() else 1)

func _rm_tree(dir: String) -> void:
	var abs := ProjectSettings.globalize_path(dir)
	if not DirAccess.dir_exists_absolute(abs):
		return
	for sub in DirAccess.get_directories_at(abs):
		_rm_tree(abs.path_join(sub))
	for f in DirAccess.get_files_at(abs):
		DirAccess.remove_absolute(abs.path_join(f))
	DirAccess.remove_absolute(abs)

func _regressions(voice: Node, world: Node, cam: Camera3D) -> void:
	print("audio_voice_test: other scripts")
	check(V.detect_lang("Ελληνικά", "ru") == "el", "Greek -> el (not the game language)")
	check(V.detect_lang("مرحبا بالعالم", "ru") == "ar", "Arabic -> ar")
	check(V.detect_lang("שלום עולם", "en") == "he", "Hebrew -> he")
	check(V.detect_lang("สวัสดีครับ", "ru") == "th", "Thai -> th")
	check(V.detect_lang("ok Γεια σου φίλε", "en") == "el", "mostly Greek with a Latin word -> el")
	check(V.detect_lang("Привет ok", "en") == "ru" and V.detect_lang("hello", "ru") == "en" and V.detect_lang("123 !!", "ru") == "ru", "Cyrillic/Latin/no letters unchanged")
	for l in ["el", "ar", "he", "th"]:
		check(V.char_lang(l, true, true, false) == "" and V.char_lang(l, true, true, true) == "", "%s never goes to a piper voice" % l)
	voice.tts.shutdown()
	voice.tts = CharTTS.new()
	voice.tts.use_fake()
	voice.tts.fake_delay_ms = 10
	voice.mode = "character"
	var t := Time.get_ticks_msec()
	voice.speak(41, "Nikos", "Γεια σου, τι κάνεις;", Vector3(0, 0, 2))
	var lg := await wait_line(voice, 41, t, 2000)
	check(not lg.has("job") and not lg.has("char_lang") and str(lg.get("engine", "")) == "robot", "a Greek chat line is not sent to piper (robot here: no OS voice headless)")
	voice.stop_all()

	print("audio_voice_test: 3D loudness")
	var prev := 2.0
	var max_step := 0.0
	var monotonic := true
	var d := V.FULL_RADIUS
	while d < V.MAX_RADIUS:
		var eff := db_to_linear(V.char_volume_db(d)) * maxf(0.0, 1.0 - d / V.MAX_RADIUS)   # what Godot plays
		if absf(eff - V.volume_at(d)) > 0.002:
			monotonic = false
		max_step = maxf(max_step, absf(prev - eff) if prev <= 1.5 else 0.0)
		if eff > prev + 0.0001:
			monotonic = false
		prev = eff
		d += 0.05
	check(monotonic, "3D voice loudness = distance_volume() from 4 m to 30 m (same curve as robot / OS voice)")
	check(max_step < 0.02 and prev < 0.001, "3D voice fades smoothly to silence at 30 m (max step %.4f, last %.5f)" % [max_step, prev])
	var e25 := db_to_linear(V.char_volume_db(25.0)) * (1.0 - 25.0 / V.MAX_RADIUS)
	check(absf(e25 - V.distance_volume(Vector3.ZERO, Vector3(0, 0, 25))) < 0.001, "at 25 m: %.3f (robot/OS voice %.3f)" % [e25, V.distance_volume(Vector3.ZERO, Vector3(0, 0, 25))])
	voice.tts.fake_delay_ms = 10
	var t2 := Time.get_ticks_msec()
	voice.speak(42, "Far", "far away line %d" % t2, Vector3(0, 0, 20))
	var lf := await wait_line(voice, 42, t2, 2000)
	var pf: AudioStreamPlayer3D = (voice._char.get(42, {}) as Dictionary).get("p3d")
	check(str(lf.get("engine", "")) == "character" and pf != null and pf.attenuation_model == AudioStreamPlayer3D.ATTENUATION_DISABLED \
		and absf(pf.volume_db - V.char_volume_db(20.0)) < 0.01 and pf.max_distance == V.MAX_RADIUS, "3D player: no built-in curve, volume_db from distance")
	world.set("talks", [])
	voice.stop_all()

	print("audio_voice_test: cache pruning")
	var pc := CharTTS.new()
	pc.cache_dir = CACHE.path_join("prune")
	pc.use_fake()
	pc.fake_delay_ms = 0
	pc.cache_max_files = 5
	pc.prune_every = 1
	var ids: Array = []
	for i in 14:
		ids.append(pc.request("prune line %d %d" % [i, t2], "en", {}))
	var done := 0
	var tw := Time.get_ticks_msec()
	while done < ids.size() and Time.get_ticks_msec() - tw < 8000:
		await process_frame
		for id in ids:
			if pc.poll(id) != null:
				done += 1
	var n_files := 0
	for f in DirAccess.get_files_at(pc.cache_dir):
		if f.ends_with(".wav"):
			n_files += 1
	check(done == ids.size() and n_files > 0 and n_files <= 5, "disk cache pruned during the session (%d lines -> %d WAVs, limit 5)" % [done, n_files])
	pc.cache_max_files = 100
	pc.cache_max_bytes = 1
	pc.prune_cache()
	check(DirAccess.get_files_at(pc.cache_dir).size() == 0, "disk cache size limit (bytes) is enforced")
	pc.shutdown()

	print("audio_voice_test: Visual C++ runtime")
	var vd := ProjectSettings.globalize_path(CACHE.path_join("vcrt"))
	DirAccess.make_dir_recursive_absolute(vd + "/piper")
	DirAccess.make_dir_recursive_absolute(vd + "/sys")
	for dll in CharTTS.VC_RUNTIME_DLLS:
		var fd := FileAccess.open(vd + "/piper/" + dll, FileAccess.WRITE)
		fd.store_string("MZ")
		fd.close()
	check(CharTTS.missing_vc_runtime(vd + "/piper", "").is_empty(), "runtime DLLs next to piper.exe: piper can start")
	DirAccess.remove_absolute(vd + "/piper/vcruntime140_1.dll")
	var miss := CharTTS.missing_vc_runtime(vd + "/piper", vd + "/sys")
	check(miss.size() == 1 and miss[0] == "vcruntime140_1.dll", "missing vcruntime140_1.dll detected (no Windows DLL dialog)")
	var fs := FileAccess.open(vd + "/sys/vcruntime140_1.dll", FileAccess.WRITE)
	fs.store_string("MZ")
	fs.close()
	check(CharTTS.missing_vc_runtime(vd + "/piper", vd + "/sys").is_empty(), "runtime installed in System32 is accepted")
