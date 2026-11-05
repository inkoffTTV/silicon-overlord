extends Node
## Network client (autoload "Net"). WebSocket + JSON frames, see docs/PROTOCOL.md.
##
##   var r := await Net.create_company("Nebula", "#4F8CFF", "#B15CFF", "solo")   # {ok, error?}
##   var r := await Net.join("ABC-123")  /  await Net.resume()
##   var r := await Net.act("startResearch", {"techId": "arch_arm_2"})          # {ok, data?, error?}
##   Net.set_speed(2); Net.send_pos(pos, yaw, pitch, "walk"); Net.chat("hi"); Net.leave()
##
## Feeds Game.apply_snapshot / apply_sections, Game.members / me / code, Bus.notify, Bus.peers_changed.
## Reconnects with backoff while in a company and resumes it with the saved token.

const Prefs := preload("res://ui/lib/prefs.gd")
const L := preload("res://ui/lib/loc.gd")

signal status_changed(status: String, detail: String)
signal joined_company(code: String)
signal left_company(reason: String)
signal members_changed(list: Array)
signal chat_received(user_id: int, name: String, text: String)
signal latency_changed(ms: int)
signal profile_changed(profile: Dictionary)
signal boards_changed(boards: Dictionary)
signal welcomed()
## a production job stopped for lack of a material (English name), right after its notify toast
signal production_blocked(material: String)

const PROTOCOL_VERSION := 1
const ACT_TIMEOUT := 10.0
const CONNECT_TIMEOUT := 6.0
const JOIN_TIMEOUT := 12.0
const POS_INTERVAL := 0.1
const PING_INTERVAL := 5.0
const DEAD_AFTER := 20.0
const BACKOFF := [1.0, 2.0, 4.0, 8.0, 15.0]

class Waiter extends RefCounted:
	signal done(result: Dictionary)
	var deadline := 0.0
	var fired := false
	func finish(r: Dictionary) -> void:
		if fired:
			return
		fired = true
		done.emit(r)

## "offline" | "connecting" | "online" (hello done, no company) | "in_company" | "reconnecting"
var status := "offline"
var detail := ""
var url := Prefs.DEFAULT_URL
var player_id := 0
var token := ""
var player_name := ""
var latency_ms := -1
var profile: Dictionary = {}
## company id the server would resume (welcome.lastCompany), "" when none
var last_company := ""
var boards: Dictionary = {}
## Tests/screenshots: Callable(action: String, args: Dictionary) -> Dictionary replaces the socket for act().
var mock_handler: Callable

var _ws: WebSocketPeer = null
var _ws_state := WebSocketPeer.STATE_CLOSED
var _next_id := 1
var _pending := {}
var _hello: Waiter = null
var _join: Waiter = null
var _stay_in_company := false
var _attempt := 0
var _retry_at := -1.0
var _connect_deadline := 0.0
var _pos_last := 0.0
var _pos_msg: Dictionary = {}
var _last_rx := 0.0
var _ping_at := 0.0
var _ping_n := 0
var _ping_sent := {}

func _ready() -> void:
	url = Prefs.url()
	player_name = str(Prefs.get_profile("name", ""))
	token = str(Prefs.get_profile("token", ""))
	process_mode = Node.PROCESS_MODE_ALWAYS

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

# ================================================================ public API
func is_online() -> bool:
	return status == "online" or status == "in_company"

func is_in_company() -> bool:
	return status == "in_company"

func set_url(u: String) -> void:
	u = u.strip_edges()
	if u == "":
		u = Prefs.DEFAULT_URL
	if not u.begins_with("ws://") and not u.begins_with("wss://"):
		u = "ws://" + u
	if not u.trim_prefix("ws://").trim_prefix("wss://").contains("/"):
		if not u.trim_prefix("ws://").trim_prefix("wss://").contains(":"):
			u += ":7350"
		u += "/ws"
	url = u
	Prefs.set_setting("net", "url", u)

func set_player_name(n: String) -> void:
	player_name = n.strip_edges().substr(0, 24)
	Prefs.set_profile("name", player_name)

## Opens the socket and says hello. Resolves {ok, error?}.
func ensure_connected() -> Dictionary:
	if is_online():
		return {"ok": true}
	if _hello == null or _hello.fired:
		_hello = Waiter.new()
		_open_socket()
	var w := _hello
	return await w.done

func create_company(company_name: String, color_a: String, color_b: String, mode: String) -> Dictionary:
	return await _enter({"t": "create", "company": {"name": company_name, "colorA": color_a, "colorB": color_b,
		"mode": "cofounder" if mode == "coop" or mode == "cofounder" else "solo"}})

func join(code: String) -> Dictionary:
	return await _enter({"t": "join", "code": normalize_code(code)})

func resume() -> Dictionary:
	return await _enter({"t": "resume"})

func leave() -> void:
	_stay_in_company = false
	if _ws_state == WebSocketPeer.STATE_OPEN:
		_send({"t": "leave"})
	# the server answers "left"; clear locally right away so the menu shows instantly
	_on_left("leave")

func disconnect_from_server() -> void:
	_stay_in_company = false
	_retry_at = -1.0
	if _ws:
		_ws.close(1000, "bye")
	_set_status("offline", "")

## Sends an action and waits for its result: {ok: bool, data?: Variant, error?: String}
func act(action: String, args: Dictionary = {}) -> Dictionary:
	if mock_handler.is_valid():
		var r: Variant = mock_handler.call(action, args)
		if r is Dictionary:
			return r
		return {"ok": true}
	if not is_in_company():
		return {"ok": false, "error": L.t("Not connected to the server")}
	var id := _next_id
	_next_id += 1
	var w := Waiter.new()
	w.deadline = _now() + ACT_TIMEOUT
	_pending[id] = w
	_send({"t": "act", "id": id, "action": action, "args": args})
	var r2: Dictionary = await w.done
	return r2

func set_speed(speed: int) -> void:
	if mock_handler.is_valid():
		mock_handler.call("setSpeed", {"speed": speed})
		return
	_send({"t": "speed", "speed": speed})

func send_pos(pos: Vector3, yaw: float, pitch: float, anim: String = "idle") -> void:
	_pos_msg = {"t": "pos", "p": [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01), snappedf(pos.z, 0.01)],
		"yaw": snappedf(yaw, 0.001), "pitch": snappedf(pitch, 0.001), "anim": anim}

func chat(text: String) -> void:
	text = text.strip_edges().substr(0, 200)
	if text != "":
		_send({"t": "chat", "text": text})

func ping() -> void:
	_ping_n += 1
	_ping_sent[_ping_n] = _now()
	_send({"t": "ping", "n": _ping_n})

static func normalize_code(code: String) -> String:
	var c := code.strip_edges().to_upper().replace(" ", "").replace("-", "")
	if c.length() == 6:
		return c.substr(0, 3) + "-" + c.substr(3)
	return c

static func is_valid_code(code: String) -> bool:
	var c := normalize_code(code).replace("-", "")
	if c.length() != 6:
		return false
	for ch in c:
		if not "ABCDEFGHJKMNPQRSTUVWXYZ23456789".contains(ch):
			return false
	return true

# ================================================================ internals
func _enter(msg: Dictionary) -> Dictionary:
	var c: Dictionary = await ensure_connected()
	if not c.get("ok", false):
		return c
	if _join and not _join.fired:
		_join.finish({"ok": false, "error": L.t("Cancelled")})
	_join = Waiter.new()
	_join.deadline = _now() + JOIN_TIMEOUT
	var w := _join
	_send(msg)
	return await w.done

func _open_socket() -> void:
	if _ws:
		_ws.close()
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = 16 * 1024 * 1024
	_ws.outbound_buffer_size = 1024 * 1024
	_ws.max_queued_packets = 4096
	var err := _ws.connect_to_url(url)
	_ws_state = WebSocketPeer.STATE_CONNECTING
	_connect_deadline = _now() + CONNECT_TIMEOUT
	if err != OK:
		_ws_state = WebSocketPeer.STATE_CLOSED
		_fail_connect(L.f("That server address doesn't look right: {url}", {"url": url}))
		return
	_set_status("reconnecting" if _stay_in_company else "connecting", url)

func _send(msg: Dictionary) -> void:
	if _ws and _ws_state == WebSocketPeer.STATE_OPEN:
		_ws.send_text(JSON.stringify(msg))

func _set_status(s: String, d: String = "") -> void:
	if s == status and d == detail:
		return
	status = s
	detail = d
	status_changed.emit(s, d)

func _process(_dt: float) -> void:
	var now := _now()
	if _ws:
		_ws.poll()
		var st := _ws.get_ready_state()
		if st != _ws_state:
			var prev := _ws_state
			_ws_state = st
			if st == WebSocketPeer.STATE_OPEN:
				_on_open()
			elif st == WebSocketPeer.STATE_CLOSED:
				_on_closed(prev)
		if _ws_state == WebSocketPeer.STATE_OPEN:
			while _ws.get_available_packet_count() > 0:
				var pkt := _ws.get_packet()
				_last_rx = now
				_on_text(pkt.get_string_from_utf8())
			if now >= _ping_at:
				_ping_at = now + PING_INTERVAL
				ping()
			if now - _last_rx > DEAD_AFTER:
				_ws.close(4000, "timeout")
			if not _pos_msg.is_empty() and now - _pos_last >= POS_INTERVAL and is_in_company():
				_send(_pos_msg)
				_pos_msg = {}
				_pos_last = now
		elif _ws_state == WebSocketPeer.STATE_CONNECTING and now > _connect_deadline:
			_ws.close()
			_ws_state = WebSocketPeer.STATE_CLOSED
			_on_closed(WebSocketPeer.STATE_CONNECTING)
	# timeouts
	for id in _pending.keys():
		var w: Waiter = _pending[id]
		if now > w.deadline:
			_pending.erase(id)
			w.finish({"ok": false, "error": L.t("The server did not answer in time")})
	if _join and not _join.fired and _join.deadline > 0 and now > _join.deadline:
		_join.finish({"ok": false, "error": L.t("The server did not answer in time")})
	# reconnect
	if _retry_at > 0 and now >= _retry_at:
		_retry_at = -1.0
		_hello = Waiter.new()
		_open_socket()

func _on_open() -> void:
	_last_rx = _now()
	_ping_at = _now() + 1.0
	var hello := {"t": "hello", "v": PROTOCOL_VERSION, "name": player_name if player_name != "" else "Player"}
	if token != "":
		hello["token"] = token
	_send(hello)

func _on_closed(prev_state: int) -> void:
	var code := _ws.get_close_code() if _ws else -1
	var was_open := prev_state == WebSocketPeer.STATE_OPEN
	for id in _pending.keys():
		(_pending[id] as Waiter).finish({"ok": false, "error": L.t("Connection lost")})
	_pending.clear()
	if _join and not _join.fired:
		_join.finish({"ok": false, "error": L.t("Connection lost")})
	if _stay_in_company:
		var delay: float = BACKOFF[mini(_attempt, BACKOFF.size() - 1)]
		_attempt += 1
		_retry_at = _now() + delay
		_set_status("reconnecting", L.f("Connection lost. Reconnecting in {s} s…", {"s": int(delay)}))
		if _hello and not _hello.fired and not was_open:
			pass
		return
	var msg := ""
	if was_open:
		msg = L.t("The server closed the connection.") if code != 1000 else ""
	else:
		msg = L.f("Can't reach the server at {url}. Is it running? Check the address in Settings.", {"url": url})
	_fail_connect(msg)

func _fail_connect(msg: String) -> void:
	if _hello and not _hello.fired:
		_hello.finish({"ok": false, "error": msg})
	_set_status("offline", msg)

func _on_text(text: String) -> void:
	var m: Variant = JSON.parse_string(text)
	if not (m is Dictionary):
		return
	var msg: Dictionary = m
	match str(msg.get("t", "")):
		"welcome":
			player_id = int(msg.get("playerId", 0))
			token = str(msg.get("token", token))
			if msg.has("name"):
				player_name = str(msg.name)
			Prefs.set_profile("token", token)
			last_company = str(msg.get("lastCompany", "")) if msg.get("lastCompany") != null else ""
			_set_status("online", "")
			welcomed.emit()
			if _hello:
				_hello.finish({"ok": true})
			if _stay_in_company:
				_send({"t": "resume"})
		"joined":
			Game.code = str(msg.get("code", ""))
			var you: Dictionary = msg.get("you", {}) if msg.get("you") is Dictionary else {}
			you["name"] = player_name
			Game.me = you
			Game.members = msg.get("members", []) if msg.get("members") is Array else []
			Prefs.set_profile("last_code", Game.code)
			var was_reconnect := _stay_in_company and _attempt > 0
			_stay_in_company = true
			_attempt = 0
			_set_status("in_company", Game.code)
			members_changed.emit(Game.members)
			joined_company.emit(Game.code)
			if _join and not _join.fired:
				_join.finish({"ok": true, "code": Game.code})
			if was_reconnect:
				Bus.notify.emit("success", L.t("Reconnected"), L.t("You're back in the company."))
		"snapshot":
			var st: Variant = msg.get("state", {})
			Game.apply_snapshot(st if st is Dictionary else {})
		"sections":
			var data: Variant = msg.get("data", {})
			if data is Dictionary:
				# a null value means the key was cleared on the server (e.g. loan after repayment)
				var removed := []
				var keep := {}
				for k in data:
					if data[k] == null:
						removed.append(k)
						Game.state.erase(k)
					else:
						keep[k] = data[k]
				if not keep.is_empty():
					Game.apply_sections(keep)
				if not removed.is_empty():
					Bus.state_changed.emit(removed)
		"res":
			var id := int(msg.get("id", -1))
			if _pending.has(id):
				var w: Waiter = _pending[id]
				_pending.erase(id)
				var r := {"ok": msg.get("ok", false) == true}
				if msg.has("data") and msg.data != null:
					r["data"] = msg.data
				if msg.has("error") and msg.error != null:
					r["error"] = L.server(msg.get("errorKey"), msg.get("errorParams"), str(msg.error))
					r["errorEn"] = str(msg.error)
					if msg.get("errorKey") != null:
						r["errorKey"] = str(msg.errorKey)
				w.finish(r)
		"notify":
			var nt := L.server(msg.get("key"), msg.get("params"), str(msg.get("title", "")))
			var nb := L.server(msg.get("bodyKey"), msg.get("bodyParams"), str(msg.get("body", "")) if msg.get("body") != null else "")
			Bus.notify.emit(str(msg.get("kind", "info")), nt, nb)
			var body_en := str(msg.get("body", "")) if msg.get("body") != null else ""
			if (str(msg.get("key", "")) == "note.production_blocked" or str(msg.get("title", "")) == "Production blocked") and body_en.contains("Out of "):
				production_blocked.emit(body_en.substr(body_en.find("Out of ") + 7).strip_edges())
		"members":
			Game.members = msg.get("list", []) if msg.get("list") is Array else []
			members_changed.emit(Game.members)
		"peers":
			Bus.peers_changed.emit(msg.get("list", []) if msg.get("list") is Array else [])
		"chat":
			chat_received.emit(int(msg.get("userId", 0)), str(msg.get("name", "?")), str(msg.get("text", "")))
		"left":
			_stay_in_company = false
			var reason := str(msg.get("reason", ""))
			if reason == "replaced":
				Bus.notify.emit("warning", L.t("Opened in another window"), L.t("This account just joined from another window, so this one left the company."))
			elif reason == "sold":
				Bus.notify.emit("info", L.t("Company sold"), "")
			_on_left(reason)
		"error":
			var em := L.server(msg.get("key"), msg.get("params"), str(msg.get("message", "Error")))
			if _join and not _join.fired:
				_join.finish({"ok": false, "error": em})
			else:
				Bus.notify.emit("error", L.t("Server"), em)
		"pong":
			var n := int(msg.get("n", 0))
			if _ping_sent.has(n):
				latency_ms = int((_now() - float(_ping_sent[n])) * 1000.0)
				_ping_sent.erase(n)
				latency_changed.emit(latency_ms)
		"boards":
			boards = msg
			boards_changed.emit(msg)
		"profile":
			var p: Variant = msg.get("profile", msg.get("data", {}))
			if p is Dictionary:
				profile = p
				profile_changed.emit(profile)

func _on_left(reason: String) -> void:
	var had := Game.has_company() or Game.code != ""
	Game.code = ""
	Game.members = []
	if Game.has_company():
		Game.apply_snapshot({})
	if is_online():
		_set_status("online", "")
	if had:
		left_company.emit(reason)
