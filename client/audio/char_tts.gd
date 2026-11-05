extends RefCounted
## Character voice synthesizer (AUDIO agent). Turns a chat line into raw speech with Piper TTS
## (github.com/rhasspy/piper, MIT) running as a separate process next to the game, then adds the "walkie-talkie
## robot" colouring that has to be baked into the samples (ring modulation, squelch + crackle at start/end).
## Pitch shift, chorus, distortion and the radio band-pass live on the speaker's audio bus (voice.gd).
##
## Files (shipped in the full zip next to the exe, NOT in the .pck — see docs/VOICE.md):
##   <exe dir>/voice/manifest.json         {"version":1, "build":"0.3.1", "piper":{"windows":"piper/piper.exe","linux":"piper/piper"},
##                                          "voices":{"ru":"ru_RU-dmitri-medium.onnx","en":"en_US-ljspeech-medium.onnx"}}
##   <exe dir>/voice/piper/...              piper.exe + espeak-ng-data + onnxruntime dlls
##   <exe dir>/voice/*.onnx (+ .onnx.json)  voice models
## Search order for the folder: env SO_VOICE_DIR, <exe dir>/voice, <project>/../build/SiliconOverlord/voice (dev).
##
## One persistent piper process per language ("--json-input --output_dir"): the model is loaded once, every line
## is one JSON line on stdin, piper answers with the path of the WAV it wrote. All of this runs on one worker
## thread; the game polls results (request → poll). Raw WAVs are cached in user://tts/ (identical lines are free).
## Tests: `fake = true` synthesizes beeps in-process; `use_command([...])` runs any program that speaks the piper
## protocol (client/tests/audio_fake_piper.py).

const CACHE_DIR := "user://tts"     # default; env SO_TTS_CACHE overrides it (tests use a private folder)
const CACHE_MAX_FILES := 400
const CACHE_MAX_BYTES := 64 * 1024 * 1024
const CACHE_PRUNE_EVERY := 16       # new WAVs written between two prunes (also pruned once in setup())
## piper.exe, piper_phonemize.dll and onnxruntime.dll import these (Visual C++ 2015-2022 runtime). The full zip ships
## them next to piper.exe; without them Windows shows a "DLL not found" dialog, so piper is not even started.
const VC_RUNTIME_DLLS := ["msvcp140.dll", "vcruntime140.dll", "vcruntime140_1.dll"]
const MEM_CACHE := 48
const JOB_TIMEOUT_MS := 8000        # a piper process that does not answer in time is killed (watchdog)
const MANIFEST := "manifest.json"
const CRACKLE_IN := 0.07            # seconds of radio squelch before the line
const CRACKLE_OUT := 0.09           # seconds of crackle after it

var available := false              # piper (or the fake) can be used
var fake := false
var fake_delay_ms := 120
var voice_dir := ""
var manifest: Dictionary = {}
var command: PackedStringArray = [] # [program, extra args...]
var models := {}                    # lang -> absolute model path
var broken_langs := {}              # lang -> true after repeated failures (skipped for this session)
var last_error := ""
var cache_dir := CACHE_DIR
var cache_max_files := CACHE_MAX_FILES
var cache_max_bytes := CACHE_MAX_BYTES
var prune_every := CACHE_PRUNE_EVERY
var stats := {"jobs": 0, "synth": 0, "cache": 0, "fail": 0, "last_ms": 0, "max_ms": 0}

var _thread: Thread
var _mutex := Mutex.new()
var _sem := Semaphore.new()
var _jobs: Array = []
var _results := {}                  # id -> result dict
var _cancelled := {}
var _quit := false
var _next_id := 1
var _procs := {}                    # lang -> {pid, stdio, stderr}   (worker thread; shutdown kills)
var _busy_since := 0
var _busy_lang := ""
var _fails := {}                    # lang -> consecutive failures (worker)
var _mem := {}                      # cache key -> raw {rate, pcm}
var _mem_order: Array = []
var _written := 0                   # WAVs written since the last prune (worker)

func _init() -> void:
	var env := OS.get_environment("SO_TTS_CACHE")
	if env != "":
		cache_dir = env

# --------------------------------------------------------------------------------------------- setup
static func default_dirs() -> Array:
	var out: Array = []
	var env := OS.get_environment("SO_VOICE_DIR")
	if env != "":
		out.append(env)
	out.append(OS.get_executable_path().get_base_dir().path_join("voice"))
	out.append(ProjectSettings.globalize_path("res://").path_join("../build/SiliconOverlord/voice").simplify_path())
	return out

static func read_manifest(dir: String) -> Dictionary:
	var path := dir.path_join(MANIFEST)
	if dir == "" or not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

static func platform_key() -> String:
	match OS.get_name():
		"Windows":
			return "windows"
		"macOS":
			return "macos"
		_:
			return "linux"

## Find the voice folder and check that piper + models exist. Returns `available`.
func setup(dir := "") -> bool:
	available = false
	var dirs: Array = [dir] if dir != "" else default_dirs()
	for d in dirs:
		var m := read_manifest(d)
		if m.is_empty():
			continue
		var exe := str((m.get("piper", {}) as Dictionary).get(platform_key(), "")) if m.get("piper") is Dictionary else ""
		if exe == "":
			last_error = "no piper for %s in %s" % [platform_key(), d]
			continue
		if exe.is_relative_path():
			exe = d.path_join(exe)
		if not FileAccess.file_exists(exe):
			last_error = "missing " + exe
			continue
		var found := {}
		var voices: Variant = m.get("voices", {})
		if voices is Dictionary:
			for lang in voices:
				var model := str(voices[lang])
				if model.is_relative_path():
					model = d.path_join(model)
				if FileAccess.file_exists(model):
					found[str(lang)] = model
		if found.is_empty():
			last_error = "no voice models in " + d
			continue
		if platform_key() == "windows":
			var missing := missing_vc_runtime(exe.get_base_dir(), OS.get_environment("SystemRoot").path_join("System32"))
			if not missing.is_empty():
				last_error = "Visual C++ runtime missing: " + ", ".join(missing)
				continue
		voice_dir = d
		manifest = m
		models = found
		command = PackedStringArray([exe])
		var espeak := exe.get_base_dir().path_join("espeak-ng-data")
		if DirAccess.dir_exists_absolute(espeak):
			command.append_array(["--espeak_data", espeak])
		available = true
		break
	prune_cache()
	return available

## Visual C++ runtime DLLs that are neither next to piper.exe nor in the system folder ([] = piper can start).
static func missing_vc_runtime(piper_dir: String, system_dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for dll in VC_RUNTIME_DLLS:
		if not FileAccess.file_exists(piper_dir.path_join(dll)) and (system_dir == "" or not FileAccess.file_exists(system_dir.path_join(dll))):
			out.append(dll)
	return out

## Tests: use any program that speaks the piper protocol, e.g. ["python3", "/abs/audio_fake_piper.py"].
func use_command(cmd: PackedStringArray, langs: Array) -> void:
	command = cmd
	models = {}
	for l in langs:
		models[str(l)] = "fake-" + str(l) + ".onnx"
	available = true
	fake = false

func use_fake(langs := ["ru", "en"]) -> void:
	fake = true
	models = {}
	for l in langs:
		models[str(l)] = "fake"
	available = true

func has_lang(lang: String) -> bool:
	return available and models.has(lang) and not broken_langs.has(lang)

# --------------------------------------------------------------------------------------------- jobs (main thread)
## Queue a line. fx: {ring_hz, ring_mix, crackle(bool), seed}. Returns a job id for poll().
func request(text: String, lang: String, fx: Dictionary = {}) -> int:
	_ensure_thread()
	_mutex.lock()
	var id := _next_id
	_next_id += 1
	_jobs.append({"id": id, "type": "say", "text": text, "lang": lang, "fx": fx, "t": Time.get_ticks_msec()})
	_mutex.unlock()
	_sem.post()
	return id

## Load the models now so the first line is fast (starts the piper processes).
func prewarm(langs: Array) -> void:
	if fake or not available:
		return
	_ensure_thread()
	_mutex.lock()
	for l in langs:
		if models.has(l):
			_jobs.append({"id": 0, "type": "warm", "lang": str(l), "t": Time.get_ticks_msec()})
			_sem.post()
	_mutex.unlock()

## null while pending; then {ok, stream:AudioStreamWAV, ms, source} once (the result is removed).
func poll(id: int) -> Variant:
	_mutex.lock()
	var r: Variant = _results.get(id, null)
	if r != null:
		_results.erase(id)
	_mutex.unlock()
	return r

func cancel(id: int) -> void:
	_mutex.lock()
	_cancelled[id] = true
	_results.erase(id)
	_mutex.unlock()

func cancel_all() -> void:
	_mutex.lock()
	for j in _jobs:
		_cancelled[int(j.id)] = true
	_jobs = _jobs.filter(func(j: Dictionary) -> bool: return j.type == "warm")
	_results.clear()
	_mutex.unlock()

func pending() -> int:
	_mutex.lock()
	var n := _jobs.size() + (1 if _busy_since > 0 else 0)
	_mutex.unlock()
	return n

## Call every frame: kills a piper process that hangs (its pipe read then returns and the worker moves on).
func watchdog() -> void:
	_mutex.lock()
	var stuck := _busy_since > 0 and Time.get_ticks_msec() - _busy_since > JOB_TIMEOUT_MS
	var lang := _busy_lang
	var p: Dictionary = _procs.get(lang, {})
	_mutex.unlock()
	if stuck and not p.is_empty() and not p.has("killed"):
		p["killed"] = true
		OS.kill(int(p.pid))

func shutdown() -> void:
	_mutex.lock()
	_quit = true
	_jobs.clear()
	var procs := _procs.duplicate()
	_procs.clear()
	_mutex.unlock()
	for l in procs:
		if not procs[l].has("killed"):
			procs[l]["killed"] = true
			OS.kill(int(procs[l].pid))
	if _thread and _thread.is_started():
		_sem.post()
		_thread.wait_to_finish()
	_thread = null
	_procs.clear()

func _ensure_thread() -> void:
	if _thread == null:
		_quit = false
		_thread = Thread.new()
		_thread.start(_worker)

# --------------------------------------------------------------------------------------------- worker thread
func _worker() -> void:
	while true:
		_sem.wait()
		_mutex.lock()
		if _quit:
			_mutex.unlock()
			break
		var job: Variant = null if _jobs.is_empty() else _jobs.pop_front()
		if job != null and _cancelled.has(int(job.id)):
			_cancelled.erase(int(job.id))
			job = null
		if job != null:
			_busy_since = Time.get_ticks_msec()
			_busy_lang = str(job.lang)
		_mutex.unlock()
		if job == null:
			continue
		var res: Dictionary = _warm(str(job.lang)) if job.type == "warm" else _say(job)
		_mutex.lock()
		_busy_since = 0
		if job.type == "say":
			stats.jobs += 1
			if _cancelled.has(int(job.id)):
				_cancelled.erase(int(job.id))
			else:
				_results[int(job.id)] = res
			res["wait_ms"] = Time.get_ticks_msec() - int(job.t)
			stats.last_ms = res.wait_ms
			stats.max_ms = maxi(int(stats.max_ms), int(res.wait_ms))
		_mutex.unlock()

func _warm(lang: String) -> Dictionary:
	if not _procs.has(lang):
		_start_proc(lang)
	return {}

func _say(job: Dictionary) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var text := str(job.text)
	var lang := str(job.lang)
	var key := cache_key(text, lang, str(models.get(lang, "")).get_file())
	var source := "memory"
	var raw: Dictionary = _mem.get(key, {})
	if raw.is_empty():
		var path := cache_dir.path_join(key + ".wav")
		var bytes := PackedByteArray()
		if FileAccess.file_exists(path):
			bytes = FileAccess.get_file_as_bytes(path)
			source = "disk"
		if bytes.is_empty():
			source = "fake" if fake else "piper"
			bytes = _fake_wav(text) if fake else _piper(text, lang)
			if not bytes.is_empty():
				DirAccess.make_dir_recursive_absolute(cache_dir)
				var f := FileAccess.open(path, FileAccess.WRITE)
				if f:
					f.store_buffer(bytes)
					f.close()
					_written += 1
					if _written >= prune_every:
						prune_cache()
		raw = parse_wav(bytes)
		if raw.is_empty():
			_mutex.lock()
			stats.fail += 1
			_mutex.unlock()
			return {"ok": false, "ms": Time.get_ticks_msec() - t0, "source": source, "error": last_error}
		_mem[key] = raw
		_mem_order.append(key)
		if _mem_order.size() > MEM_CACHE:
			_mem.erase(_mem_order.pop_front())
	_mutex.lock()
	if source in ["memory", "disk"]:
		stats.cache += 1
	else:
		stats.synth += 1
	_mutex.unlock()
	var stream := build_stream(raw, job.get("fx", {}))
	return {"ok": true, "stream": stream, "ms": Time.get_ticks_msec() - t0, "source": source,
		"seconds": stream.get_length()}

func _start_proc(lang: String) -> Dictionary:
	var model := str(models.get(lang, ""))
	if command.is_empty() or model == "":
		return {}
	var tmp := ProjectSettings.globalize_path(cache_dir.path_join("out"))
	DirAccess.make_dir_recursive_absolute(tmp)
	var args := PackedStringArray()
	for i in range(1, command.size()):
		args.append(command[i])
	args.append_array(["--model", model, "--json-input", "--output_dir", tmp, "--quiet"])
	var d: Dictionary = OS.execute_with_pipe(command[0], args, true)
	if d.is_empty() or not (d.get("stdio") is FileAccess):
		last_error = "cannot start " + command[0]
		return {}
	# a program that cannot start (missing library, bad binary) dies within milliseconds; writing to its stdin
	# afterwards would raise SIGPIPE on Linux/macOS (Windows just returns an error), so give it a moment first
	OS.delay_msec(60)
	if not OS.is_process_running(int(d.pid)):
		last_error = "piper exited at start (%s)" % command[0]
		return {}
	_mutex.lock()
	_procs[lang] = d
	_mutex.unlock()
	return d

func _stop_proc(lang: String) -> void:
	_mutex.lock()
	var p: Dictionary = _procs.get(lang, {})
	_procs.erase(lang)
	_mutex.unlock()
	if not p.is_empty() and not p.has("killed"):
		p["killed"] = true
		OS.kill(int(p.pid))

## One line through the persistent process (restarted once if it died). Empty = failed.
func _piper(text: String, lang: String) -> PackedByteArray:
	for attempt in 2:
		var p: Dictionary = _procs.get(lang, {})
		if p.is_empty() or p.has("killed") or not OS.is_process_running(int(p.pid)):
			_stop_proc(lang)
			p = _start_proc(lang)
			if p.is_empty():
				break
		var io: FileAccess = p.stdio
		io.store_string(json_line(text) + "\n")
		io.flush()
		var out := io.get_line().strip_edges()
		if out != "" and FileAccess.file_exists(out):
			var bytes := FileAccess.get_file_as_bytes(out)
			DirAccess.remove_absolute(out)
			_fails[lang] = 0
			return bytes
		last_error = "piper gave no audio (%s)" % lang
		_stop_proc(lang)
	_fails[lang] = int(_fails.get(lang, 0)) + 1
	if int(_fails[lang]) >= 3:
		_mutex.lock()
		broken_langs[lang] = true
		_mutex.unlock()
	return PackedByteArray()

## Fake synthesizer for tests / CI: one beep per syllable, 22050 Hz mono 16-bit WAV.
func _fake_wav(text: String) -> PackedByteArray:
	if fake_delay_ms > 0:
		OS.delay_msec(fake_delay_ms)
	var rate := 22050
	var n := int(rate * clampf(0.25 + text.length() * 0.055, 0.3, 12.0))
	var pcm := PackedByteArray()
	pcm.resize(n * 2)
	var syl := int(rate * 0.11)
	for i in n:
		var k := i / syl
		var ph := float(i % syl) / float(syl)
		var f := 140.0 + float((k * 37 + text.length()) % 9) * 18.0
		var env := sin(PI * ph)
		var s := (sin(TAU * f * i / rate) + 0.4 * sin(TAU * 2.0 * f * i / rate)) * env * 0.45
		pcm.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32000.0))
	return wav_bytes(pcm, rate)

# --------------------------------------------------------------------------------------------- pure helpers
static func cache_key(text: String, lang: String, model: String) -> String:
	return (lang + "|" + model + "|" + text).md5_text()

## {"text": "..."} with every non-ASCII character escaped (\uXXXX, surrogate pairs above U+FFFF), so the pipe
## carries plain ASCII whatever the Windows code page is.
static func json_line(text: String) -> String:
	var s := "{\"text\": \""
	for i in text.length():
		var c := text.unicode_at(i)
		if c == 34:
			s += "\\\""
		elif c == 92:
			s += "\\\\"
		elif c < 32:
			s += " "
		elif c > 126:
			if c > 0xFFFF:
				var v := c - 0x10000
				s += "\\u%04x\\u%04x" % [0xD800 + (v >> 10), 0xDC00 + (v & 0x3FF)]
			else:
				s += "\\u%04x" % c
		else:
			s += char(c)
	return s + "\"}"

static func wav_bytes(pcm: PackedByteArray, rate: int) -> PackedByteArray:
	var h := PackedByteArray()
	h.resize(44)
	h.encode_u32(0, 0x46464952)  # RIFF
	h.encode_u32(4, 36 + pcm.size())
	h.encode_u32(8, 0x45564157)  # WAVE
	h.encode_u32(12, 0x20746d66) # fmt
	h.encode_u32(16, 16)
	h.encode_u16(20, 1)
	h.encode_u16(22, 1)
	h.encode_u32(24, rate)
	h.encode_u32(28, rate * 2)
	h.encode_u16(32, 2)
	h.encode_u16(34, 16)
	h.encode_u32(36, 0x61746164) # data
	h.encode_u32(40, pcm.size())
	return h + pcm

## 16-bit PCM WAV → {rate, pcm (mono s16le)}; {} if it is not one.
static func parse_wav(b: PackedByteArray) -> Dictionary:
	if b.size() < 44 or b.slice(0, 4).get_string_from_ascii() != "RIFF" or b.slice(8, 12).get_string_from_ascii() != "WAVE":
		return {}
	var pos := 12
	var rate := 0
	var ch := 1
	var bits := 0
	while pos + 8 <= b.size():
		var id := b.slice(pos, pos + 4).get_string_from_ascii()
		var size := b.decode_u32(pos + 4)
		var body := pos + 8
		if id == "fmt ":
			ch = b.decode_u16(body + 2)
			rate = b.decode_u32(body + 4)
			bits = b.decode_u16(body + 14)
		elif id == "data":
			if bits != 16 or rate <= 0 or ch < 1:
				return {}
			var end := mini(body + size, b.size())
			var pcm := b.slice(body, end)
			if ch > 1:  # keep the first channel
				var mono := PackedByteArray()
				var frames := pcm.size() / (2 * ch)
				mono.resize(frames * 2)
				for i in frames:
					mono.encode_s16(i * 2, pcm.decode_s16(i * 2 * ch))
				pcm = mono
			return {"rate": rate, "pcm": pcm} if pcm.size() >= 2 else {}
		pos = body + size + (size & 1)
	return {}

## Bake the robot/radio colouring into the samples: ring modulation (metallic ring), squelch + crackle at the
## start and end, peak normalised to about -1 dBFS.
static func build_stream(raw: Dictionary, fx: Dictionary) -> AudioStreamWAV:
	var rate := int(raw.rate)
	var src: PackedByteArray = raw.pcm
	var n := src.size() / 2
	var crackle := bool(fx.get("crackle", true))
	var pre := int(rate * CRACKLE_IN) if crackle else 0
	var post := int(rate * CRACKLE_OUT) if crackle else 0
	var ring_hz := float(fx.get("ring_hz", 55.0))
	var mix := clampf(float(fx.get("ring_mix", 0.3)), 0.0, 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(fx.get("seed", 1))
	var peak := 1
	for i in range(0, n, 3):
		peak = maxi(peak, absi(src.decode_s16(i * 2)))
	var gain := clampf(29000.0 / float(peak), 0.5, 3.0)
	var out := PackedByteArray()
	out.resize((pre + n + post) * 2)
	# ring modulator: rotate a unit phasor instead of calling sin() per sample
	var c := cos(TAU * ring_hz / rate)
	var s := sin(TAU * ring_hz / rate)
	var x := 1.0
	var y := 0.0
	for i in n:
		var v := float(src.decode_s16(i * 2)) * gain
		v *= (1.0 - mix) + mix * x
		var nx := x * c - y * s
		y = x * s + y * c
		x = nx
		if (i & 1023) == 0:  # keep the phasor on the unit circle
			var m := sqrt(x * x + y * y)
			x /= m
			y /= m
		out.encode_s16((pre + i) * 2, int(clampf(v, -32767.0, 32767.0)))
	if crackle:
		_crackle(out, 0, pre, rate, rng, 0.10, true)
		_crackle(out, pre + n, post, rate, rng, 0.07, false)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = out
	return w

## Radio squelch: a short burst of hissy noise that fades (in = rising into the line, out = fading tail) with a
## few random clicks on top.
static func _crackle(out: PackedByteArray, start: int, count: int, rate: int, rng: RandomNumberGenerator, level: float, rising: bool) -> void:
	var prev := 0.0
	for i in count:
		var t := float(i) / float(maxi(count, 1))
		var env := (0.35 + 0.65 * t) if rising else (1.0 - t) * (1.0 - t)
		var w := rng.randf_range(-1.0, 1.0)
		var hiss := w - prev * 0.6
		prev = w
		var v := hiss * level * env
		if rng.randf() < 0.004:
			v += rng.randf_range(-0.5, 0.5) * env
		out.encode_s16((start + i) * 2, int(clampf(v, -1.0, 1.0) * 32767.0))

## Keep the disk cache under cache_max_files WAVs and cache_max_bytes (oldest first). Runs in setup() and on the
## worker after every prune_every new WAVs, so a long chat session cannot fill the disk.
func prune_cache() -> void:
	_written = 0
	var d := DirAccess.open(cache_dir)
	if d == null:
		return
	var files: Array = []
	var total := 0
	for f in d.get_files():
		if f.ends_with(".wav"):
			var p := cache_dir.path_join(f)
			var size := 0
			var fa := FileAccess.open(p, FileAccess.READ)
			if fa:
				size = fa.get_length()
				fa.close()
			total += size
			files.append([FileAccess.get_modified_time(p), f, size])
	if files.size() <= cache_max_files and total <= cache_max_bytes:
		return
	files.sort()
	var count := files.size()
	for e in files:
		if count <= cache_max_files and total <= cache_max_bytes:
			break
		d.remove(e[1])
		count -= 1
		total -= int(e[2])
