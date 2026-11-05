extends Node
## Spoken chat (owned by the AUDIO agent; created by Sfx as its child "Voice").
## Each chat line is spoken by the speaker's character, like R.E.P.O:
##  - OS text-to-speech (DisplayServer.tts_*) with a voice matching the text language and a per-user pitch/rate,
##  - or the "robot" voice: pitched syllable blips (Animal-Crossing style) when TTS is missing or chosen in settings.
## Volume depends on the distance from the listener (camera) to the speaker. Every speaker has its own queue;
## OS TTS can only say one line at a time, so TTS lines of different speakers wait for each other.

const MAX_CHARS := 200
const FULL_RADIUS := 4.0     # metres: full volume inside
const MAX_RADIUS := 30.0     # metres: silent beyond
const QUEUE_LIMIT := 4       # lines waiting per speaker (older ones are dropped)
const SYLLABLE_TIME := 0.085 # robot voice: seconds per syllable at rate 1

var mode := "tts"          # "tts" | "robot" | "off"
var volume := 0.9          # 0..1 (settings [audio] voice)
var master := 0.8          # 0..1, OS TTS bypasses Godot buses so master is applied by hand
var game_lang := "en"

var _queues := {}          # user_id -> Array of line dicts
var _busy_until := {}      # user_id -> msec when the current line ends
var _robot := {}           # user_id -> {player, events:Array, t0}
var _peer_pos := {}        # user_id -> Vector3 (from Bus.peers_changed)
var _tts_checked := false
var _tts_ok := false
var _tts_busy_until := 0   # msec; one OS utterance at a time
var _tts_current := -1
var _utt_id := 1
var _syllables: Array = [] # AudioStream
var last_line: Dictionary = {}   # for tests / debugging: the last line that started
var history: Array = []          # last few started lines (tests)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

## Queue a line. Returns the line dictionary (also used by tests).
func speak(user_id: int, display_name: String, text: String, at: Variant = null) -> Dictionary:
	text = clean_text(text)
	if text == "":
		return {}
	var q: Array = _queues.get(user_id, [])
	if q.size() >= QUEUE_LIMIT:
		q.pop_front()
	var line := {"user_id": user_id, "name": display_name, "text": text, "at": at, "lang": detect_lang(text, game_lang)}
	q.append(line)
	_queues[user_id] = q
	return line

func queue_size(user_id: int) -> int:
	return (_queues.get(user_id, []) as Array).size()

func is_speaking(user_id: int) -> bool:
	return Time.get_ticks_msec() < int(_busy_until.get(user_id, 0))

func speaking_count() -> int:
	var now := Time.get_ticks_msec()
	var n := 0
	for uid in _busy_until:
		if now < int(_busy_until[uid]):
			n += 1
	return n

func stop_all() -> void:
	_queues.clear()
	_busy_until.clear()
	for uid in _robot:
		var r: Dictionary = _robot[uid]
		r.events = []
		(r.player as AudioStreamPlayer).stop()
	if _tts_ok:
		DisplayServer.tts_stop()
	_tts_busy_until = 0

func set_peer_positions(list: Array) -> void:
	for p in list:
		if p is Dictionary and p.has("userId") and p.get("p") is Array and (p.p as Array).size() >= 3:
			_peer_pos[int(p.userId)] = Vector3(float(p.p[0]), float(p.p[1]) + 1.6, float(p.p[2]))

# ---------------------------------------------------------------------------------------------
# pure helpers (static so tests can call them directly)
# ---------------------------------------------------------------------------------------------
static func clean_text(text: String) -> String:
	var t := ""
	for i in text.length():
		var c := text.unicode_at(i)
		t += " " if c < 32 or c == 127 else text[i]
	t = t.strip_edges()
	while t.contains("  "):
		t = t.replace("  ", " ")
	if t.length() > MAX_CHARS:
		t = t.substr(0, MAX_CHARS)
	return t

## "ru" for Cyrillic, "ja" for kana, "zh" for Han ideographs, "ko" for Hangul, else the game language
## (or "en" when the game language does not use the Latin script, so Latin text gets a Latin voice).
static func detect_lang(text: String, fallback: String = "en") -> String:
	var cyr := 0
	var lat := 0
	var kana := 0
	var han := 0
	var hangul := 0
	for i in text.length():
		var c := text.unicode_at(i)
		if c >= 0x0400 and c <= 0x04FF:
			cyr += 1
		elif (c >= 0x41 and c <= 0x5A) or (c >= 0x61 and c <= 0x7A) or (c >= 0xC0 and c <= 0x24F):
			lat += 1
		elif c >= 0x3040 and c <= 0x30FF:
			kana += 1
		elif c >= 0x4E00 and c <= 0x9FFF:
			han += 1
		elif c >= 0xAC00 and c <= 0xD7AF:
			hangul += 1
	if kana > 0:
		return "ja"
	if hangul > 0 and hangul >= han:
		return "ko"
	if han > 0:
		return "zh"
	if cyr > 0 and cyr >= lat:
		return "ru"
	if lat == 0:
		return fallback
	return fallback if fallback in ["en", "de", "fr", "es", "it", "pt", "pl", "nl", "tr"] else "en"

## Deterministic per-user voice traits: {pitch, rate, robot_pitch, pick} (pick chooses among OS voices).
static func traits(user_id: int) -> Dictionary:
	var h := absi((absi(user_id) * 2654435761 + 40503) % 4294967296)
	var a := float(h % 1000) / 999.0
	var b := float((h / 1000) % 1000) / 999.0
	return {
		"pitch": lerpf(0.7, 1.45, a),
		"rate": lerpf(0.9, 1.3, b),
		"robot_pitch": lerpf(0.72, 1.6, a),
		"pick": int(h / 1000000),
	}

## 0..1 loudness for a speaker at `at` heard from `listener` (null = right here).
static func distance_volume(listener: Variant, at: Variant) -> float:
	if not (listener is Vector3) or not (at is Vector3):
		return 1.0
	var d: float = (listener as Vector3).distance_to(at)
	if d <= FULL_RADIUS:
		return 1.0
	if d >= MAX_RADIUS:
		return 0.0
	var v := 1.0 - (d - FULL_RADIUS) / (MAX_RADIUS - FULL_RADIUS)
	return v * v

static func estimate_seconds(text: String, rate: float) -> float:
	return clampf(0.35 + text.length() * 0.062 / maxf(rate, 0.3), 0.6, 16.0)

# ---------------------------------------------------------------------------------------------
# runtime
# ---------------------------------------------------------------------------------------------
func tts_available() -> bool:
	if not _tts_checked:
		_tts_checked = true
		_tts_ok = false
		if DisplayServer.get_name() != "headless" and bool(ProjectSettings.get_setting("audio/general/text_to_speech", false)):
			_tts_ok = DisplayServer.tts_get_voices().size() > 0
			if _tts_ok:
				DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_ENDED, _on_utt_end)
				DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_CANCELED, _on_utt_end)
	return _tts_ok

func _on_utt_end(id: int) -> void:
	if id == _tts_current:
		_tts_busy_until = 0

func listener_position() -> Variant:
	var vp := get_viewport()
	var cam := vp.get_camera_3d() if vp else null
	if cam and cam.is_inside_tree():
		return cam.global_position
	return null

func resolve_position(user_id: int, at: Variant) -> Variant:
	if at is Vector3:
		return at
	if at is Node3D and is_instance_valid(at) and (at as Node3D).is_inside_tree():
		return (at as Node3D).global_position
	var world := get_tree().get_first_node_in_group("world") if is_inside_tree() else null
	if world and world.has_method("avatar_position"):
		var p: Variant = world.call("avatar_position", user_id)
		if p is Vector3:
			return p
	var net := get_node_or_null("/root/Net")
	if net and int(net.get("player_id")) == user_id:
		return listener_position()
	return _peer_pos.get(user_id, null)

func _process(_dt: float) -> void:
	var now := Time.get_ticks_msec()
	for uid in _queues.keys():
		var q: Array = _queues[uid]
		if q.is_empty():
			_queues.erase(uid)
			continue
		if now < int(_busy_until.get(uid, 0)):
			continue
		var line: Dictionary = q[0]
		var engine := _engine_for(line)
		if engine == "tts" and now < _tts_busy_until:
			continue
		q.pop_front()
		_start(line, engine)
	for uid in _robot:
		_robot_tick(uid, now)

func _engine_for(line: Dictionary) -> String:
	if mode == "off":
		return "off"
	if mode == "tts" and tts_available() and not _voice_for(str(line.lang), int(line.user_id)).is_empty():
		return "tts"
	return "robot"

func _voice_for(lang: String, user_id: int) -> String:
	var ids := DisplayServer.tts_get_voices_for_language(lang)
	if ids.is_empty():
		return ""
	return ids[int(traits(user_id).pick) % ids.size()]

func _start(line: Dictionary, engine: String) -> void:
	var uid := int(line.user_id)
	var vt := traits(uid)
	var pos: Variant = resolve_position(uid, line.at)
	var vol := distance_volume(listener_position(), pos)
	var text := str(line.text)
	var seconds := estimate_seconds(text, float(vt.rate))
	line["engine"] = engine
	line["volume"] = vol
	line["seconds"] = seconds
	line["pos"] = pos
	last_line = line
	history.append(line)
	if history.size() > 16:
		history.pop_front()
	_busy_until[uid] = Time.get_ticks_msec() + int(seconds * 1000.0) + 250
	var world := get_tree().get_first_node_in_group("world")
	if world and world.has_method("avatar_talk"):
		world.call("avatar_talk", uid, seconds, text)
	var loud := vol * volume
	if engine == "off" or loud <= 0.02:
		return
	if engine == "tts":
		_utt_id += 1
		_tts_current = _utt_id
		_tts_busy_until = Time.get_ticks_msec() + int(seconds * 1500.0) + 1500  # safety if no callback arrives
		var v := _voice_for(str(line.lang), uid)
		DisplayServer.tts_speak(text, v, clampi(int(round(loud * master * 100.0)), 1, 100), float(vt.pitch), float(vt.rate), _utt_id, false)
	else:
		_robot_say(uid, text, float(vt.robot_pitch), float(vt.rate), loud, seconds)

# ---- robot voice ----------------------------------------------------------------------------
func set_syllables(streams: Array) -> void:
	_syllables = streams

func _robot_say(uid: int, text: String, base_pitch: float, rate: float, loud: float, seconds: float) -> void:
	if _syllables.is_empty():
		return
	if not _robot.has(uid):
		var p := AudioStreamPlayer.new()
		p.bus = "Voice"
		p.name = "Robot%d" % uid
		add_child(p)
		_robot[uid] = {"player": p, "events": [], "t0": 0}
	var r: Dictionary = _robot[uid]
	(r.player as AudioStreamPlayer).volume_db = linear_to_db(maxf(loud, 0.001))
	var ev: Array = []
	var t := 0.0
	var step := SYLLABLE_TIME / maxf(rate, 0.3)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(text) + uid
	var question := text.ends_with("?")
	var exclaim := text.ends_with("!")
	var letters := 0
	var words := text.split(" ", false)
	for wi in words.size():
		var w: String = words[wi]
		var n := clampi(int(ceil(w.length() / 2.5)), 1, 5)
		for k in n:
			var p := base_pitch * rng.randf_range(0.9, 1.12)
			var last := wi == words.size() - 1 and k == n - 1
			if last and question:
				p *= 1.25
			elif last and not exclaim:
				p *= 0.92
			ev.append({"t": t, "i": rng.randi() % _syllables.size(), "pitch": p})
			t += step * rng.randf_range(0.85, 1.15)
			letters += 1
			if t > seconds:
				break
		t += step * (2.2 if w.ends_with(",") or w.ends_with(".") else 0.6)
		if t > seconds:
			break
	r.events = ev
	r.t0 = Time.get_ticks_msec()

func _robot_tick(uid: int, now: int) -> void:
	var r: Dictionary = _robot[uid]
	var ev: Array = r.events
	while not ev.is_empty() and now - int(r.t0) >= int(float(ev[0].t) * 1000.0):
		var e: Dictionary = ev.pop_front()
		var p: AudioStreamPlayer = r.player
		p.stream = _syllables[int(e.i)]
		p.pitch_scale = clampf(float(e.pitch), 0.3, 3.0)
		p.play()
