extends Node
## Audio service (AUDIO agent owns client/audio/**). Stable API used by world and UI:
##   Sfx.play(name: String, at: Variant = null, volume_db := 0.0)  # at = Vector3 / Node3D for 3D, null for 2D
##   Sfx.ui(name: String)                                           # UI click/hover/confirm/error/toast
##   Sfx.music(name: String)                                        # "" stops; crossfades
##   Sfx.ambient(name: String)                                      # room tone loop ("garage", "loft", "stage", "outdoor", "")
##   Sfx.speak(user_id: int, display_name: String, text: String, at: Variant = null, lang := "")  # chat → character voice
## Extras: Sfx.loop(name, parent) -> Node, Sfx.stop_loop(node), Sfx.apply_settings(), Sfx.has_sound(name).
## Sound names, buses, settings and licences: docs/AUDIO.md. All sounds are synthesized by client/audio/gen/make_audio.py.
## Every call is safe headless / without an audio device; unknown names print one debug line and are ignored.

const Bank := preload("res://audio/bank_data.gd")
const Voice := preload("res://audio/voice.gd")

const SETTINGS := "user://settings.cfg"
## Settings file actually read/written. Tests point it at a private file so parallel runs (other tests, a running
## game) cannot change it under them; the game always uses SETTINGS.
var settings_path := SETTINGS
const DEFAULTS := {"master": 0.8, "music": 0.5, "sfx": 0.8, "ui": 0.7, "voice": 0.9, "voice_mode": "character", "voice_pitch": 1.0,
	"voice_rev": 2}
const BUSES := [["Music", "Master"], ["SFX", "Master"], ["UI", "Master"], ["Voice", "Master"], ["Ambient", "SFX"]]
const KIND_BUS := {"ui": "UI", "sfx": "SFX", "loop": "SFX", "ambient": "Ambient", "music": "Music", "voice": "Voice"}
const POOL_2D := 12
const POOL_3D := 24
const MAX_SAME := 4            # concurrent instances of one sound
const RETRIGGER_MS := 35       # the same sound again within this window is skipped
const MUSIC_DB := -9.0         # trims so default slider values give a calm mix
const AMBIENT_DB := -3.0
const FADE := 2.0
const DUCK_DB := -8.0
## 3D reach per sound (unit_size, max_distance); everything else uses DEFAULT_3D
const DEFAULT_3D := Vector2(3.0, 32.0)
const REACH_3D := {
	"van_start": Vector2(8, 60), "van_door_close": Vector2(6, 45), "rollup_door": Vector2(8, 50),
	"crowd_cheer": Vector2(12, 80), "applause": Vector2(12, 80), "whoosh": Vector2(10, 60), "confetti": Vector2(8, 50),
	"step_concrete": Vector2(2, 22), "step_wood": Vector2(2, 22), "step_metal": Vector2(2, 22),
	"keyboard": Vector2(1.5, 14), "marker": Vector2(1.5, 14), "paper": Vector2(1.5, 14), "pc_beep": Vector2(1.5, 16),
	"machine_hum": Vector2(3, 25), "conveyor": Vector2(3, 25), "fluorescent": Vector2(1.2, 10), "fridge": Vector2(1.2, 10),
	"van_idle": Vector2(5, 40), "crowd_murmur": Vector2(10, 60),
}
const QUIET_UI := ["hover", "type"]   # these don't count as "the UI already made a sound"

var settings := {}
var voice: Node                       # voice.gd
var music_name := ""
var ambient_name := ""
var debug_log: Array = []             # debug messages so far (tests)
var auto_ui := true                   # automatic button/tab/text-field sounds

var _streams := {}                    # path -> AudioStream
var _warned := {}
var _last_play := {}                  # name -> msec
var _pool2d: Array = []
var _pool3d: Array = []
var _started := {}                    # player instance id -> msec started
var _playing_name := {}               # player instance id -> sound name
var _music: Array = []                # two AudioStreamPlayer for crossfades
var _music_idx := 0
var _amb: Array = []
var _amb_idx := 0
var _duck := 0.0
var _settings_mtime := 0
var _settings_check := 0.0
var _ui_frame := -1                   # process frame of the last (non-quiet) UI sound
var _last_notify_ms := -100000
var _music_before_launch := ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_make_buses()
	for i in POOL_2D:
		var p := AudioStreamPlayer.new()
		p.name = "P2D_%d" % i
		add_child(p)
		_pool2d.append(p)
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.name = "P3D_%d" % i
		add_child(p)
		_pool3d.append(p)
	for side in 2:
		var m := AudioStreamPlayer.new()
		m.name = "Music%d" % side
		m.bus = "Music"
		m.volume_db = -80.0
		add_child(m)
		_music.append(m)
		var a := AudioStreamPlayer.new()
		a.name = "Ambient%d" % side
		a.bus = "Ambient"
		a.volume_db = -80.0
		add_child(a)
		_amb.append(a)
	voice = Voice.new()
	voice.name = "Voice"
	add_child(voice)
	var syl: Array = []
	for path in Bank.SOUNDS.get("voice_blip", []):
		var s := _stream(path)
		if s:
			syl.append(s)
	voice.set_syllables(syl)
	apply_settings()
	_connect_signals.call_deferred()
	music("menu")

# =============================================================================================
# public API
# =============================================================================================

func has_sound(sound: String) -> bool:
	return Bank.SOUNDS.has(sound)

## One-shot sound. at: Vector3 (3D at that point), Node3D (3D, follows the node) or null (2D).
func play(sound: String, at: Variant = null, volume_db := 0.0) -> void:
	if sound == "":
		return
	if not Bank.SOUNDS.has(sound):
		_unknown(sound)
		return
	var kind: String = Bank.KIND[sound]
	match kind:
		"music":
			music(sound)
			return
		"ambient":
			ambient(sound)
			return
		"loop":
			if at is Node3D:
				loop(sound, at, volume_db)
			else:
				_debug_once("loop:" + sound, "[Sfx] '%s' is a loop - use Sfx.loop(name, node)" % sound)
			return
	var now := Time.get_ticks_msec()
	if now - int(_last_play.get(sound, -100000)) < RETRIGGER_MS:
		return
	_last_play[sound] = now
	if kind == "ui" and sound not in QUIET_UI:
		_ui_frame = Engine.get_process_frames()
	var stream := _pick(sound)
	if stream == null:
		return
	var bus: String = KIND_BUS.get(kind, "SFX")
	var pitch := randf_range(0.96, 1.04) if kind == "sfx" else randf_range(0.985, 1.015)
	if at is Node3D and is_instance_valid(at) and (at as Node3D).is_inside_tree():
		var follower := AudioStreamPlayer3D.new()
		_setup_3d(follower, sound, bus, volume_db, pitch)
		follower.stream = stream
		follower.finished.connect(follower.queue_free)
		(at as Node3D).add_child(follower)
		follower.play()
		return
	if at is Vector3:
		var p3: AudioStreamPlayer3D = _take(_pool3d, sound)
		_setup_3d(p3, sound, bus, volume_db, pitch)
		p3.stream = stream
		p3.global_position = at
		_mark(p3, sound)
		p3.play()
		return
	var p2: AudioStreamPlayer = _take(_pool2d, sound)
	p2.bus = bus
	p2.volume_db = volume_db
	p2.pitch_scale = pitch
	p2.stream = stream
	_mark(p2, sound)
	p2.play()

## UI sound (2D, UI bus).
func ui(sound: String) -> void:
	play(sound, null, 0.0)

## Background music with a crossfade: "menu", "game", "launch", "" = stop.
func music(track: String) -> void:
	if track == music_name:
		return
	if track != "" and not (Bank.SOUNDS.has(track) and Bank.KIND[track] == "music"):
		_unknown(track)
		return
	music_name = track
	_music_idx = _crossfade(_music, _music_idx, track, MUSIC_DB)

## Room tone / ambience loop: "garage", "loft", "stage", "outdoor", "" = stop.
func ambient(room: String) -> void:
	if room == ambient_name:
		return
	if room != "" and not (Bank.SOUNDS.has(room) and Bank.KIND[room] == "ambient"):
		_unknown(room)
		return
	ambient_name = room
	_amb_idx = _crossfade(_amb, _amb_idx, room, AMBIENT_DB)

## Chat line → character voice (OS TTS or robot blah-blah). Sfx already speaks Net.chat_received by itself.
## lang (optional): force a language code instead of detecting it from the text (settings "test voice").
func speak(user_id: int, display_name: String, text: String, at: Variant = null, lang := "") -> void:
	if voice:
		voice.speak(user_id, display_name, text, at, lang)

## Settings "Test voice": your own voice (your pitch) saying a sample line in the given language.
func test_voice(text: String, lang := "") -> void:
	if voice:
		var net := get_node_or_null("/root/Net")
		var uid := int(net.get("player_id")) if net else 0
		voice.speak(uid, "", text, null, lang)

## {"character": bool (voice files found), "dir": String, "error": String} for the settings panel.
func voice_status() -> Dictionary:
	if voice == null or voice.tts == null:
		return {"character": false, "dir": "", "error": ""}
	return {"character": voice.tts.available, "dir": voice.tts.voice_dir, "error": voice.tts.last_error}

## Looping 3D emitter attached to `parent` (machine hum, conveyor, fluorescent tube...). Returns the player node
## (free it or call stop_loop to stop; freeing the parent stops it too). null for unknown names.
func loop(sound: String, parent: Node3D, volume_db := 0.0) -> Node:
	if not Bank.SOUNDS.has(sound):
		_unknown(sound)
		return null
	if parent == null or not is_instance_valid(parent):
		return null
	var p := AudioStreamPlayer3D.new()
	p.name = "Loop_" + sound
	_setup_3d(p, sound, "SFX", volume_db, 1.0)
	p.stream = _pick(sound)
	p.autoplay = true
	parent.add_child(p)
	if p.is_inside_tree() and p.stream:
		# start at a random point so several identical machines don't phase
		p.play(randf() * maxf(p.stream.get_length() - 0.1, 0.0))
	return p

func stop_loop(player: Node) -> void:
	if player and is_instance_valid(player):
		player.queue_free()

## Silence everything at once (one-shots, music, ambience, voices). Also done on exit.
func stop_all() -> void:
	for p in _pool2d + _pool3d + _music + _amb:
		p.stop()
	music_name = ""
	ambient_name = ""
	if voice:
		voice.stop_all()

func _exit_tree() -> void:
	stop_all()

## (Re)read user://settings.cfg [audio], writing defaults for missing keys, and apply bus volumes.
func apply_settings() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(settings_path)
	var dirty := false
	# 0.3.0 wrote voice_mode "tts" as its default: move those players to the new character voice once
	if err == OK and cfg.has_section("audio") and not cfg.has_section_key("audio", "voice_rev"):
		if str(cfg.get_value("audio", "voice_mode", "")) == "tts":
			cfg.set_value("audio", "voice_mode", "character")
		cfg.set_value("audio", "voice_rev", 2)
		dirty = true
	for k in DEFAULTS:
		if not cfg.has_section_key("audio", k):
			cfg.set_value("audio", k, DEFAULTS[k])
			dirty = true
		settings[k] = cfg.get_value("audio", k, DEFAULTS[k])
	if dirty or err != OK:
		cfg.save(settings_path)
	_settings_mtime = FileAccess.get_modified_time(settings_path)
	var lang := str(cfg.get_value("ui", "lang", ""))
	if lang.length() < 2:
		lang = OS.get_locale_language()
	if voice:
		var pref := {}
		if cfg.has_section("audio"):
			for k in cfg.get_section_keys("audio"):
				if k.begins_with("voice_") and k not in ["voice_mode", "voice_pitch", "voice_rev"]:
					pref[k.substr(6)] = str(cfg.get_value("audio", k, ""))
		voice.preferred = pref
		var vm := str(settings.voice_mode)
		voice.mode = vm if vm in voice.MODES else "character"
		voice.own_pitch = clampf(float(settings.voice_pitch), 0.5, 2.0)
		voice.volume = _vol("voice")
		voice.master = _vol("master")
		voice.game_lang = lang
	_apply_bus_volumes()

func bus_volume_db(bus_name: String) -> float:
	var i := AudioServer.get_bus_index(bus_name)
	return AudioServer.get_bus_volume_db(i) if i >= 0 else 0.0

# =============================================================================================
# internals
# =============================================================================================

func _make_buses() -> void:
	for b in BUSES:
		if AudioServer.get_bus_index(b[0]) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, b[0])
	for b in BUSES:
		AudioServer.set_bus_send(AudioServer.get_bus_index(b[0]), b[1])

func _vol(key: String) -> float:
	return clampf(float(settings.get(key, DEFAULTS.get(key, 1.0))), 0.0, 1.0)

static func _lin_db(v: float) -> float:
	return -80.0 if v <= 0.001 else linear_to_db(v)

func _apply_bus_volumes() -> void:
	var pairs := {"Master": "master", "Music": "music", "SFX": "sfx", "UI": "ui", "Voice": "voice"}
	for bus_name in pairs:
		var i := AudioServer.get_bus_index(bus_name)
		if i < 0:
			continue
		var v := _lin_db(_vol(pairs[bus_name]))
		if bus_name == "Music" and v > -80.0:
			v += _duck
		AudioServer.set_bus_volume_db(i, v)
		AudioServer.set_bus_mute(i, v <= -79.0)
	var ai := AudioServer.get_bus_index("Ambient")
	if ai >= 0:
		AudioServer.set_bus_volume_db(ai, _duck * 0.4)

func _connect_signals() -> void:
	var bus := get_node_or_null("/root/Bus")
	if bus:
		_try_connect(bus, "notify", _on_notify)
		_try_connect(bus, "launch_show", _on_launch_show)
		_try_connect(bus, "launch_finished", _on_launch_finished)
		_try_connect(bus, "settings_changed", apply_settings)
		_try_connect(bus, "peers_changed", _on_peers)
	var net := get_node_or_null("/root/Net")
	if net:
		_try_connect(net, "chat_received", _on_chat)
		_try_connect(net, "joined_company", _on_joined)
		_try_connect(net, "left_company", _on_left)
	if not get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.connect(_on_node_added)

func _try_connect(obj: Object, sig: String, cb: Callable) -> void:
	if obj.has_signal(sig) and not obj.is_connected(sig, cb):
		obj.connect(sig, cb)

func _process(dt: float) -> void:
	# ducking under voices (music fully, ambience a bit)
	var target := DUCK_DB if voice and voice.speaking_count() > 0 else 0.0
	var nd := move_toward(_duck, target, dt * (30.0 if target < _duck else 6.0))
	if not is_equal_approx(nd, _duck):
		_duck = nd
		_apply_bus_volumes()
	# settings written by the UI (or by hand) are picked up within a second
	_settings_check -= dt
	if _settings_check <= 0.0:
		_settings_check = 1.0
		if FileAccess.file_exists(settings_path) and FileAccess.get_modified_time(settings_path) != _settings_mtime:
			apply_settings()

func _stream(path: String) -> AudioStream:
	if _streams.has(path):
		return _streams[path]
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		s = load(path) as AudioStream
	if s == null:
		_debug_once("missing:" + path, "[Sfx] missing audio file " + path)
	_streams[path] = s
	return s

func _pick(sound: String) -> AudioStream:
	var paths: Array = Bank.SOUNDS.get(sound, [])
	if paths.is_empty():
		return null
	var s := _stream(paths[randi() % paths.size()])
	if s and sound in Bank.LOOPS and "loop" in s:
		s.set("loop", true)
	return s

func _take(pool: Array, sound: String) -> Node:
	# too many of the same sound → reuse its oldest instance; else a free player; else the oldest player overall
	var same: Array = []
	var free_p: Node = null
	var oldest: Node = pool[0]
	for p in pool:
		var id: int = p.get_instance_id()
		if not p.playing:
			if free_p == null:
				free_p = p
		elif _playing_name.get(id, "") == sound:
			same.append(p)
		if int(_started.get(id, 0)) < int(_started.get(oldest.get_instance_id(), 0)):
			oldest = p
	if same.size() >= MAX_SAME:
		var o: Node = same[0]
		for p in same:
			if int(_started.get(p.get_instance_id(), 0)) < int(_started.get(o.get_instance_id(), 0)):
				o = p
		o.stop()
		return o
	if free_p:
		return free_p
	oldest.stop()
	return oldest

func _mark(p: Node, sound: String) -> void:
	_started[p.get_instance_id()] = Time.get_ticks_msec()
	_playing_name[p.get_instance_id()] = sound

func _setup_3d(p: AudioStreamPlayer3D, sound: String, bus: String, volume_db: float, pitch: float) -> void:
	var reach: Vector2 = REACH_3D.get(sound, DEFAULT_3D)
	p.bus = bus
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.unit_size = reach.x
	p.max_distance = reach.y
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.attenuation_filter_cutoff_hz = 9000.0
	p.attenuation_filter_db = -6.0

func _crossfade(pair: Array, idx: int, sound: String, base_db: float) -> int:
	var old: AudioStreamPlayer = pair[idx]
	if old.playing:
		var tw := create_tween()
		tw.tween_property(old, "volume_db", -80.0, FADE)
		tw.tween_callback(old.stop)
	if sound == "":
		return idx
	var nxt: AudioStreamPlayer = pair[1 - idx]
	var s := _pick(sound)
	if s == null:
		return idx
	nxt.stop()
	nxt.stream = s
	nxt.volume_db = -40.0
	nxt.play()
	var tw2 := create_tween()
	tw2.tween_property(nxt, "volume_db", base_db, FADE).set_ease(Tween.EASE_OUT)
	return 1 - idx

func _unknown(sound: String) -> void:
	_debug_once("unknown:" + sound, "[Sfx] unknown sound '%s' (see docs/AUDIO.md)" % sound)

func _debug_once(key: String, msg: String) -> void:
	if _warned.has(key):
		return
	_warned[key] = true
	debug_log.append(msg)
	print(msg)

# ---- automatic reactions --------------------------------------------------------------------
func _on_chat(uid: int, who: String, text: String) -> void:
	speak(uid, who, text)

func _on_peers(list: Array) -> void:
	if voice:
		voice.set_peer_positions(list)

func _on_joined(_code: String) -> void:
	if voice:
		voice.prewarm()
	music("game")
	if ambient_name == "":
		ambient("garage")

func _on_left(_reason: String) -> void:
	if voice:
		voice.stop_all()
	ambient("")
	music("menu")

func _on_notify(kind: String, title: String, _body: String) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_notify_ms < 250:
		return
	_last_notify_ms = now
	var t := title.to_lower()
	var snd := "notify"
	if t.contains("research") or t.contains("исследован"):
		snd = "research_done"
	elif t.contains("sale") or t.contains("sold") or t.contains("revenue") or t.contains("продаж") or t.contains("выручк"):
		snd = "cash_register"
	elif kind in ["success", "warning", "error"]:
		snd = kind
	ui(snd)

func _on_launch_show(_product_id: String) -> void:
	if music_name != "launch":
		_music_before_launch = music_name
	music("launch")
	# safety: come back even if nobody reports the end of the show
	get_tree().create_timer(45.0).timeout.connect(func() -> void:
		if music_name == "launch":
			_on_launch_finished(""))

func _on_launch_finished(_product_id: String) -> void:
	if music_name == "launch":
		music(_music_before_launch if _music_before_launch not in ["", "launch", "menu"] else "game")

func _on_node_added(n: Node) -> void:
	if not auto_ui:
		return
	if n is BaseButton:
		var b := n as BaseButton
		if b is CheckBox or b is CheckButton:
			b.toggled.connect(func(_on: bool) -> void: _auto_ui(b, "toggle"))
		elif b is OptionButton:
			(b as OptionButton).item_selected.connect(func(_i: int) -> void: _auto_ui(b, "tab"))
		else:
			b.pressed.connect(func() -> void: _auto_ui(b, "click"))
		b.mouse_entered.connect(func() -> void:
			if is_instance_valid(b) and not b.disabled and bool(b.get_meta("sfx_hover", true)):
				ui("hover"))
	elif n is TabBar:
		(n as TabBar).tab_changed.connect(func(_i: int) -> void: ui("tab"))
	elif n is LineEdit:
		(n as LineEdit).text_changed.connect(func(_t: String) -> void: ui("type"))

## Default control sound, unless the control has meta "sfx" ("" = silent) or the UI code already played
## its own UI sound in this frame (e.g. Sfx.ui("confirm") in the button's handler).
func _auto_ui(b: Node, def: String) -> void:
	var snd: String = str(b.get_meta("sfx", def)) if is_instance_valid(b) else def
	if snd == "":
		return
	var frame := Engine.get_process_frames()
	(func() -> void:
		if _ui_frame == frame:
			return
		ui(snd)).call_deferred()
