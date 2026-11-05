extends Node
## Spoken chat (owned by the AUDIO agent; created by Sfx as its child "Voice").
## Each chat line is spoken by the speaker's character (docs/VOICE.md). Engines, by voice_mode:
##  "character" (default): our own robot-radio character voice — Piper TTS (char_tts.gd, files in <exe>/voice/)
##      played in 3D on the speaker's avatar through a per-speaker bus (pitch shift per user, chorus, light
##      distortion, radio band-pass); falls back to OS TTS, then to the robot blips.
##  "tts": OS text-to-speech (DisplayServer.tts_*) with a voice matching the text language and a per-user pitch/rate.
##  "robot": pitched syllable blips (Animal-Crossing style).   "off": silent (avatars still move their mouths).
## Volume depends on the distance from the listener (camera) to the speaker. Every speaker has its own queue;
## OS TTS can only say one line at a time, so TTS lines of different speakers wait for each other.

const MAX_CHARS := 200
const FULL_RADIUS := 4.0     # metres: full volume inside
const MAX_RADIUS := 30.0     # metres: silent beyond
const QUEUE_LIMIT := 4       # lines waiting per speaker (older ones are dropped)
const SYLLABLE_TIME := 0.085 # robot voice: seconds per syllable at rate 1
const SYNTH_WAIT_MS := 3500  # character voice: give up on a line that is not synthesized by then (→ fallback)
const FX_BUSES := 8          # per-speaker effect buses "VoiceFx0..7" (reused, least recently used first)
const MODES := ["character", "tts", "robot", "off"]
const CharTTS := preload("res://audio/char_tts.gd")

var mode := "character"    # "character" | "tts" | "robot" | "off"
var own_pitch := 1.0       # [audio] voice_pitch: your own character voice pitch (0.5 deep .. 2.0 squeaky)
var user_pitch := {}       # user_id -> pitch sent by the server (peers "voicePitch", optional)
var tts                    # char_tts.gd instance (Piper / fake)
var volume := 0.9          # 0..1 (settings [audio] voice)
var master := 0.8          # 0..1, OS TTS bypasses Godot buses so master is applied by hand
var game_lang := "en"
var preferred := {}        # lang -> OS voice id chosen in settings ([audio] voice_<lang>), "" = automatic

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
var _char := {}            # user_id -> {p2d, p3d, line, slot}
var _slot_of := {}         # user_id -> fx bus slot
var _slot_used := []       # slot -> msec last used

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	tts = CharTTS.new()
	if OS.get_environment("SO_TTS_FAKE") == "1":
		tts.use_fake()
	else:
		tts.setup()

func _exit_tree() -> void:
	if tts:
		tts.shutdown()

## Start the piper processes now (model load ≈ 0.5–1 s) so the first chat line is fast.
func prewarm() -> void:
	if mode == "character" and tts:
		tts.prewarm(["ru", "en"])

func character_available() -> bool:
	return tts != null and tts.available
## Queue a line. Returns the line dictionary (also used by tests).
## lang: "" = detect from the text (see detect_lang), or a language code to force ("de", "ru"...).
func speak(user_id: int, display_name: String, text: String, at: Variant = null, lang := "") -> Dictionary:
	text = clean_text(text)
	if text == "":
		return {}
	var q: Array = _queues.get(user_id, [])
	if q.size() >= QUEUE_LIMIT:
		var dropped: Dictionary = q.pop_front()
		if int(dropped.get("job", 0)) > 0 and tts:
			tts.cancel(int(dropped.job))
	var line := {"user_id": user_id, "name": display_name, "text": text, "at": at, "lang": lang if lang != "" else detect_lang(text, game_lang),
		"t_queued": Time.get_ticks_msec()}
	_request_char(line)
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
	for uid in _char:
		var c: Dictionary = _char[uid]
		for k in ["p2d", "p3d"]:
			if c.get(k):
				(c[k] as Node).call("stop")
		c.line = {}
	if tts:
		tts.cancel_all()
	if _tts_ok:
		DisplayServer.tts_stop()
	_tts_busy_until = 0

func set_peer_positions(list: Array) -> void:
	for p in list:
		if p is Dictionary and p.has("userId") and p.get("p") is Array and (p.p as Array).size() >= 3:
			_peer_pos[int(p.userId)] = Vector3(float(p.p[0]), float(p.p[1]) + 1.6, float(p.p[2]))
		if p is Dictionary and p.has("userId") and p.has("voicePitch"):  # optional, sent by newer servers
			user_pitch[int(p.userId)] = clampf(float(p.voicePitch), 0.5, 2.0)

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

const LATIN_LANGS := ["en", "de", "fr", "es", "it", "pt", "pl", "nl", "tr", "id", "vi"]
## Letters that give a Latin-script language away (checked in this order).
const LATIN_HINTS := [["tr", "şğıİŞĞ"], ["pl", "ąęłśżźćńĄĘŁŚŻŹĆŃ"], ["pt", "ãõÃÕ"], ["es", "ñÑ¿¡"],
	["de", "äöüßÄÖÜ"], ["fr", "èêàçœâîûùëïÈÊÀÇ"]]

## Other scripts → the language that writes them (none has a character voice: OS voice, else robot).
const OTHER_SCRIPTS := [["el", 0x0370, 0x03FF], ["el", 0x1F00, 0x1FFF], ["hy", 0x0530, 0x058F], ["he", 0x0590, 0x05FF],
	["ar", 0x0600, 0x06FF], ["ar", 0x0750, 0x077F], ["ar", 0xFB50, 0xFDFF], ["ar", 0xFE70, 0xFEFF],
	["hi", 0x0900, 0x097F], ["bn", 0x0980, 0x09FF], ["ta", 0x0B80, 0x0BFF], ["th", 0x0E00, 0x0E7F],
	["ka", 0x10A0, 0x10FF], ["am", 0x1200, 0x137F], ["km", 0x1780, 0x17FF]]

## "ru" for Cyrillic ("uk" with і ї є ґ), "ja" for kana, "zh" for Han, "ko" for Hangul, "el"/"ar"/"he"/"th"... for
## other scripts (OTHER_SCRIPTS); Latin text → a language guessed from its special letters (ß, ñ, ł, ş...), else the
## game language when it is a Latin-script one, else "en". No letters at all (digits, emoji) → fallback.
static func detect_lang(text: String, fallback: String = "en") -> String:
	var cyr := 0
	var uk := 0
	var lat := 0
	var kana := 0
	var han := 0
	var hangul := 0
	var other := {}
	var other_n := 0
	for i in text.length():
		var c := text.unicode_at(i)
		if c >= 0x0400 and c <= 0x04FF:
			cyr += 1
			if c in [0x0456, 0x0457, 0x0454, 0x0491, 0x0406, 0x0407, 0x0404, 0x0490]:
				uk += 1
		elif (c >= 0x41 and c <= 0x5A) or (c >= 0x61 and c <= 0x7A) or (c >= 0xC0 and c <= 0x24F):
			lat += 1
		elif c >= 0x3040 and c <= 0x30FF:
			kana += 1
		elif c >= 0x4E00 and c <= 0x9FFF:
			han += 1
		elif c >= 0xAC00 and c <= 0xD7AF:
			hangul += 1
		elif c >= 0x0370:
			for sc in OTHER_SCRIPTS:
				if c >= int(sc[1]) and c <= int(sc[2]):
					other[sc[0]] = int(other.get(sc[0], 0)) + 1
					other_n += 1
					break
	if kana > 0:
		return "ja"
	if hangul > 0 and hangul >= han:
		return "ko"
	if han > 0:
		return "zh"
	if other_n > cyr + lat:
		var best := ""
		for l in other:
			if best == "" or int(other[l]) > int(other[best]):
				best = l
		return best
	if cyr > 0 and cyr >= lat:
		return "uk" if uk > 0 else ("uk" if fallback == "uk" else "ru")
	if lat == 0:
		return fallback
	for hint in LATIN_HINTS:
		for ch in str(hint[1]):
			if text.contains(ch):
				return hint[0]
	return fallback if fallback in LATIN_LANGS else "en"

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
		"char_pitch": lerpf(0.62, 1.6, a),           # character voice: deep .. squeaky
		"ring_hz": lerpf(32.0, 90.0, b),            # metallic ring frequency
		"chorus_ms": lerpf(1.6, 4.5, float((h / 7) % 1000) / 999.0),
	}

## "ru" voice for Cyrillic (Russian + Ukrainian), "en" for English; other languages: "" when the OS has a voice for
## them (→ OS TTS), else the English voice for Latin-script text; CJK / Korean without an OS voice → "" (robot).
static func char_lang(lang: String, has_ru: bool, has_en: bool, os_voice: bool) -> String:
	if lang in ["ru", "uk"]:
		return "ru" if has_ru else ""
	if lang == "en":
		return "en" if has_en else ""
	if os_voice:
		return ""
	return "en" if has_en and lang in LATIN_LANGS else ""

## 0..1 loudness for a speaker at `at` heard from `listener` (null = right here).
static func distance_volume(listener: Variant, at: Variant) -> float:
	if not (listener is Vector3) or not (at is Vector3):
		return 1.0
	return volume_at((listener as Vector3).distance_to(at))

## distance_volume for a distance in metres: 1 inside FULL_RADIUS, quadratic fade to 0 at MAX_RADIUS.
static func volume_at(d: float) -> float:
	if d <= FULL_RADIUS:
		return 1.0
	if d >= MAX_RADIUS:
		return 0.0
	var v := 1.0 - (d - FULL_RADIUS) / (MAX_RADIUS - FULL_RADIUS)
	return v * v

## volume_db for the 3D character-voice player so that it sounds exactly as loud as distance_volume() (the robot and
## the OS voice): the player uses ATTENUATION_DISABLED, and Godot still multiplies by (1 - d / max_distance) when
## max_distance > 0, so that factor is divided out here. Smooth down to silence at MAX_RADIUS, no step.
static func char_volume_db(d: float) -> float:
	var lin := volume_at(d) / maxf(1.0 - d / MAX_RADIUS, 0.0001)
	return linear_to_db(maxf(lin, 0.00001))

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
	if tts:
		tts.watchdog()
	for uid in _queues.keys():
		var q: Array = _queues[uid]
		if q.is_empty():
			_queues.erase(uid)
			continue
		if now < int(_busy_until.get(uid, 0)):
			continue
		var line: Dictionary = q[0]
		var engine := _engine_for(line)
		if engine == "character":
			if not line.has("result"):
				var r: Variant = tts.poll(int(line.job))
				if r == null:
					if now - int(line.t_queued) < SYNTH_WAIT_MS:
						continue   # still synthesizing: the speaker's next lines wait behind this one
					tts.cancel(int(line.job))
					r = {"ok": false, "error": "timeout"}
				line["result"] = r
			if not bool(line.result.get("ok", false)):
				line["char_error"] = str(line.result.get("error", ""))
				engine = _fallback_engine(line)
		if engine == "tts" and now < _tts_busy_until:
			continue
		q.pop_front()
		_start(line, engine)
	for uid in _robot:
		_robot_tick(uid, now)
	_follow_speakers(now)

func _engine_for(line: Dictionary) -> String:
	if mode == "off":
		return "off"
	if int(line.get("job", 0)) > 0:
		return "character"
	if mode == "character":
		return _fallback_engine(line)
	if mode == "tts" and tts_available() and not _voice_for(str(line.lang), int(line.user_id)).is_empty():
		return "tts"
	return "robot"

## Character voice unavailable for this line: OS voice if there is one, else the robot.
func _fallback_engine(line: Dictionary) -> String:
	if tts_available() and not _voice_for(str(line.lang), int(line.user_id)).is_empty():
		return "tts"
	return "robot"

## Ask the synthesizer for a line as soon as it is queued (so it is ready when the speaker's turn comes).
func _request_char(line: Dictionary) -> void:
	if mode != "character" or tts == null or not tts.available:
		return
	var os_voice := tts_available() and not _voice_for(str(line.lang), int(line.user_id)).is_empty()
	var cl := char_lang(str(line.lang), tts.has_lang("ru"), tts.has_lang("en"), os_voice)
	if cl == "":
		return
	var vt := traits(int(line.user_id))
	line["char_lang"] = cl
	line["job"] = tts.request(str(line.text), cl, {"ring_hz": vt.ring_hz, "ring_mix": 0.28, "crackle": true,
		"seed": hash(str(line.text)) + int(line.user_id)})

## Pitch of a speaker's character voice: yours from settings, others from the server (if sent) or their user id.
func pitch_for(user_id: int) -> float:
	var net := get_node_or_null("/root/Net")
	if user_id <= 0 or (net and int(net.get("player_id")) == user_id):
		return clampf(own_pitch, 0.5, 2.0)
	if user_pitch.has(user_id):
		return float(user_pitch[user_id])
	return float(traits(user_id).char_pitch)

## OS voice for a line: the one chosen in settings for that language, else one picked per user.
## Ukrainian falls back to Russian voices, Latin-script languages to English ones; "" = none (robot voice).
func _voice_for(lang: String, user_id: int) -> String:
	for l in [lang, "ru" if lang == "uk" else ("en" if lang in LATIN_LANGS else "")]:
		if l == "":
			continue
		var ids := DisplayServer.tts_get_voices_for_language(l)
		if ids.is_empty():
			continue
		var want := str(preferred.get(l, ""))
		if want != "" and want in ids:
			return want
		return ids[int(traits(user_id).pick) % ids.size()]
	return ""

func _start(line: Dictionary, engine: String) -> void:
	var uid := int(line.user_id)
	var vt := traits(uid)
	var pos: Variant = resolve_position(uid, line.at)
	var vol := distance_volume(listener_position(), pos)
	var text := str(line.text)
	var seconds := estimate_seconds(text, float(vt.rate))
	var stream: AudioStreamWAV = null
	var speed := 1.0
	if engine == "character":
		stream = line.result.get("stream")
		speed = 1.0 + (pitch_for(uid) - 1.0) * 0.18   # higher voices talk a little faster (playful)
		seconds = stream.get_length() / speed if stream else seconds
		line["latency_ms"] = Time.get_ticks_msec() - int(line.t_queued)
		line["source"] = str(line.result.get("source", ""))
		line.erase("result")
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
	if engine == "character":
		_char_play(uid, line, stream, pos, speed)
	elif engine == "tts":
		_utt_id += 1
		_tts_current = _utt_id
		_tts_busy_until = Time.get_ticks_msec() + int(seconds * 1500.0) + 1500  # safety if no callback arrives
		var v := _voice_for(str(line.lang), uid)
		DisplayServer.tts_speak(text, v, clampi(int(round(loud * master * 100.0)), 1, 100), float(vt.pitch), float(vt.rate), _utt_id, false)
	else:
		_robot_say(uid, text, float(vt.robot_pitch), float(vt.rate), vol, seconds)  # the Voice bus applies the volume setting

# ---- character voice playback ---------------------------------------------------------------
func _char_play(uid: int, line: Dictionary, stream: AudioStreamWAV, pos: Variant, speed: float) -> void:
	if stream == null:
		return
	var c: Dictionary = _char.get(uid, {})
	if c.is_empty():
		c = {"p2d": null, "p3d": null, "line": {}}
		_char[uid] = c
	var bus := _fx_bus(uid)
	var listener: Variant = listener_position()
	var use_3d := pos is Vector3 and listener is Vector3 and (listener as Vector3).distance_to(pos) > 0.5
	var key := "p3d" if use_3d else "p2d"
	if c[key] == null:
		var p: Node
		if use_3d:
			var p3 := AudioStreamPlayer3D.new()
			p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED   # loudness: char_volume_db()
			p3.unit_size = FULL_RADIUS
			p3.max_distance = MAX_RADIUS
			p3.max_db = 3.0
			p3.panning_strength = 0.8
			p = p3
		else:
			p = AudioStreamPlayer.new()
		p.name = ("Char3D%d" if use_3d else "Char2D%d") % uid
		add_child(p)
		c[key] = p
	var player: Node = c[key]
	player.set("bus", bus)
	player.set("stream", stream)
	player.set("pitch_scale", clampf(speed, 0.7, 1.3))
	if use_3d:
		(player as AudioStreamPlayer3D).global_position = pos
		(player as AudioStreamPlayer3D).volume_db = char_volume_db((listener as Vector3).distance_to(pos))
	player.call("play")
	c.line = line
	c.mode3d = use_3d
	line["bus"] = bus

## Keep 3D voices on their avatars while they walk.
func _follow_speakers(now: int) -> void:
	for uid in _char:
		var c: Dictionary = _char[uid]
		if c.line.is_empty() or not bool(c.get("mode3d", false)) or now >= int(_busy_until.get(uid, 0)):
			continue
		var p: Variant = resolve_position(uid, c.line.get("at"))
		if p is Vector3 and c.p3d:
			(c.p3d as AudioStreamPlayer3D).global_position = p
			var lp: Variant = listener_position()
			if lp is Vector3:
				(c.p3d as AudioStreamPlayer3D).volume_db = char_volume_db((lp as Vector3).distance_to(p))

## Per-speaker effect bus (created on first use, LRU-reused): pitch shift → chorus → distortion → radio band-pass.
func _fx_bus(uid: int) -> String:
	if _slot_used.is_empty():
		_slot_used.resize(FX_BUSES)
		_slot_used.fill(-1)
	var slot := int(_slot_of.get(uid, -1))
	if slot < 0:
		slot = 0
		for i in FX_BUSES:
			if int(_slot_used[i]) < int(_slot_used[slot]):
				slot = i
		for other in _slot_of.keys():
			if int(_slot_of[other]) == slot:
				_slot_of.erase(other)
		_slot_of[uid] = slot
	_slot_used[slot] = Time.get_ticks_msec()
	var bus_name := "VoiceFx%d" % slot
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Voice")
		for fx in make_effects():
			AudioServer.add_bus_effect(idx, fx)
	configure_bus(idx, pitch_for(uid), float(traits(uid).chorus_ms))
	return bus_name

## The effect chain of a voice bus (order matters).
static func make_effects() -> Array:
	var ps := AudioEffectPitchShift.new()
	ps.fft_size = AudioEffectPitchShift.FFT_SIZE_1024
	ps.oversampling = 4
	var ch := AudioEffectChorus.new()     # two very short voices = comb filter = tinny metal ring
	ch.voice_count = 2
	ch.dry = 0.85
	ch.wet = 0.45
	var dist := AudioEffectDistortion.new()
	dist.mode = AudioEffectDistortion.MODE_OVERDRIVE
	dist.drive = 0.22
	dist.pre_gain = 0.0
	dist.post_gain = -3.0
	dist.keep_hf_hz = 4000.0
	var hp := AudioEffectHighPassFilter.new()
	hp.cutoff_hz = 330.0
	hp.resonance = 0.6
	var lp := AudioEffectLowPassFilter.new()
	lp.cutoff_hz = 3600.0
	lp.resonance = 0.7
	var eq := AudioEffectEQ6.new()  # walkie-talkie "honk": mids up, lows/highs down
	for b in [[0, -12.0], [1, -8.0], [2, -2.0], [3, 4.0], [4, 2.0], [5, -10.0]]:
		eq.set_band_gain_db(b[0], b[1])
	var lim := AudioEffectHardLimiter.new()
	lim.ceiling_db = -1.0
	return [ps, ch, dist, hp, lp, eq, lim]

static func configure_bus(idx: int, pitch: float, chorus_ms: float) -> void:
	var ps := AudioServer.get_bus_effect(idx, 0) as AudioEffectPitchShift
	if ps:
		ps.pitch_scale = clampf(pitch, 0.5, 2.0)
	var ch := AudioServer.get_bus_effect(idx, 1) as AudioEffectChorus
	if ch:
		for v in 2:
			ch.set_voice_delay_ms(v, chorus_ms * (1.0 + v * 0.6))
			ch.set_voice_rate_hz(v, 0.6 + v * 0.9)
			ch.set_voice_depth_ms(v, 0.25)
			ch.set_voice_level_db(v, -2.0)
			ch.set_voice_cutoff_hz(v, 9000.0)
			ch.set_voice_pan(v, -0.3 if v == 0 else 0.3)

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
		# CJK has no spaces: one syllable per character there
		var n := clampi(w.length(), 1, 40) if w.unicode_at(0) >= 0x3000 else clampi(int(ceil(w.length() / 2.5)), 1, 5)
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
