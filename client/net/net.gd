extends Node
## Network client (autoload "Net"). WebSocket + JSON frames, see docs/PROTOCOL.md.
##
##   var r := await Net.create_company("Nebula", "#4F8CFF", "#B15CFF", "solo", true)   # {ok, error?}; true = story start
##   var r := await Net.list_my_companies()     # lobby: {ok, data: [{companyId, code, name, date, cash, role, lastPlayed}]}
##   var r := await Net.join("ABC-123")  /  await Net.resume()
##   var r := await Net.act("startResearch", {"techId": "arch_arm_2"})          # {ok, data?, error?}
##   Net.set_speed(2); Net.send_pos(pos, yaw, pitch, "walk"); Net.chat("hi"); Net.leave()
##   Accounts (docs/ACCOUNTS.md), lobby only for login / logout / transfer redeem:
##   await Net.account_register("Vasya", "password") / account_login(...) / account_logout() /
##   account_change_password(old, new) / account_delete(password) / transfer_create() / transfer_redeem("ABCD-EFGH")
##   Net.account_name ("" = guest), signal account_changed. The password is turned into a key here (net/kdf.gd).
##
## Feeds Game.apply_snapshot / apply_sections, Game.members / me / code, Bus.notify, Bus.peers_changed.
## Reconnects with backoff while in a company and resumes it with the saved token.

const Prefs := preload("res://ui/lib/prefs.gd")
const L := preload("res://ui/lib/loc.gd")
const Kdf := preload("res://net/kdf.gd")

signal status_changed(status: String, detail: String)
signal joined_company(code: String)
signal left_company(reason: String)
signal members_changed(list: Array)
signal chat_received(user_id: int, name: String, text: String)
signal latency_changed(ms: int)
signal profile_changed(profile: Dictionary)
signal boards_changed(boards: Dictionary)
signal welcomed()
## logged in / out / registered (account_name changed)
signal account_changed()
## a production job stopped for lack of a material (English name), right after its notify toast
signal production_blocked(material: String)
## a server notify with a "story.*" key (story.step.done, story.chapter, ...), emitted before Bus.notify
signal story_notified(key: String, params: Dictionary)

const PROTOCOL_VERSION := 1
const ACT_TIMEOUT := 10.0
const CONNECT_TIMEOUT := 6.0
const JOIN_TIMEOUT := 12.0
const POS_INTERVAL := 0.1
const PING_INTERVAL := 5.0
const DEAD_AFTER := 20.0
const BACKOFF := [1.0, 2.0, 4.0, 8.0, 15.0]
## actions the server accepts in the lobby (after hello, outside a company)
const LOBBY_ACTIONS := ["listMyCompanies", "accountStatus", "accountRegister", "accountLogin", "accountLogout",
	"accountChangePassword", "accountDelete", "transferCreate", "transferRedeem"]
## account rules (server/sos/accounts.py)
const USERNAME_MIN := 3
const USERNAME_MAX := 20
const PASSWORD_MIN := 8

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
## account username ("" = guest: progress tied to this PC's token)
var account_name := ""
var latency_ms := -1
var profile: Dictionary = {}
## company id the server would resume (welcome.lastCompany), "" when none
var last_company := ""
var boards: Dictionary = {}
## the notify frame being delivered right now (Bus.notify handlers may read its key / params)
var last_notify: Dictionary = {}
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
	account_name = str(Prefs.get_profile("account", ""))
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

## story = true: "Story start" (repair-shop tutorial, docs/STORY.md); false = quick start (the old behaviour).
func create_company(company_name: String, color_a: String, color_b: String, mode: String, story: bool = false) -> Dictionary:
	return await _enter({"t": "create", "company": {"name": company_name, "colorA": color_a, "colorB": color_b,
		"mode": "cofounder" if mode == "coop" or mode == "cofounder" else "solo", "storyMode": story}})

## Your companies (lobby action, works right after hello). {ok, data: Array, error?}
func list_my_companies() -> Dictionary:
	if mock_handler.is_valid():
		return await act("listMyCompanies", {})
	var c: Dictionary = await ensure_connected()
	if not c.get("ok", false):
		return c
	var r: Dictionary = await act("listMyCompanies", {})
	if r.get("ok", false):
		var d: Variant = r.get("data")
		if d is Dictionary:
			d = (d as Dictionary).get("companies", (d as Dictionary).values())
		r["data"] = d if d is Array else []
	return r

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
	if not is_in_company() and not (action in LOBBY_ACTIONS and is_online()):
		return {"ok": false, "error": L.t("Not connected to the server")}
	var id := _next_id
	_next_id += 1
	var w := Waiter.new()
	w.deadline = _now() + ACT_TIMEOUT
	_pending[id] = w
	_send({"t": "act", "id": id, "action": action, "args": args})
	var r2: Dictionary = await w.done
	return r2

## The story keeps the clock paused until chapter 4 (docs/ACTIONS.md): speed changes are not sent then; the first
## attempt explains why (toast), later ones only click.
var _clock_note_shown := false

func story_clock_paused() -> bool:
	var st: Variant = Game.state.get("story")
	if not (st is Dictionary) or (st as Dictionary).get("done", true):
		return false
	return int((st as Dictionary).get("chapter", 0)) < 4

func set_speed(speed: int) -> void:
	if story_clock_paused():
		if not _clock_note_shown:
			_clock_note_shown = true
			Bus.notify.emit("info", L.t("Time is paused for the story"), L.t("Story: time starts at chapter 4"))
		return
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

# ================================================================ accounts (docs/ACCOUNTS.md)
func is_logged_in() -> bool:
	return account_name != ""

## "" when fine, else a translated reason (same rules as the server).
static func username_problem(u: String) -> String:
	if u.length() < USERNAME_MIN or u.length() > USERNAME_MAX:
		return L.t("Username: 3-20 letters, digits or _")
	var latin := false
	var cyr := false
	for ch in u:
		var c := ch.unicode_at(0)
		if (c >= 65 and c <= 90) or (c >= 97 and c <= 122):
			latin = true
		elif (c >= 0x410 and c <= 0x44F) or c in [0x401, 0x451, 0x406, 0x456, 0x407, 0x457, 0x404, 0x454, 0x490, 0x491, 0x40E, 0x45E]:
			# Russian alphabet + Ё ё І і Ї ї Є є Ґ ґ Ў ў only (server: accounts.CYRILLIC_LETTERS): no rare
			# look-alikes (Ј Ѕ Һ), no combining marks
			cyr = true
		elif not (ch == "_" or (c >= 48 and c <= 57)):
			return L.t("Username: 3-20 letters, digits or _")
	if latin and cyr:
		return L.t("Username: use Latin or Cyrillic letters, not both")
	return ""

static func password_problem(p: String) -> String:
	if p.length() < PASSWORD_MIN:
		return L.t("Password: at least 8 characters")
	return ""

## PBKDF2 on a worker thread (~0.2-0.4 s), the UI keeps animating.
func derive_key(username: String, password: String) -> String:
	if not is_inside_tree():
		return Kdf.derive(username, password)
	var th := Thread.new()
	th.start(Kdf.derive.bind(username, password))
	while th.is_alive():
		await get_tree().process_frame
	return str(th.wait_to_finish())

func _set_account(n: String) -> void:
	if n == account_name:
		return
	account_name = n
	Prefs.set_profile("account", n)
	account_changed.emit()

func _account_ready(lobby: bool) -> Dictionary:
	if mock_handler.is_valid():
		return {"ok": true}
	var c: Dictionary = await ensure_connected()
	if not c.get("ok", false):
		return c
	if lobby and is_in_company():
		return {"ok": false, "error": L.t("Leave the company first")}
	return {"ok": true}

func account_status() -> Dictionary:
	var c: Dictionary = await _account_ready(false)
	if not c.get("ok", false):
		return c
	return await act("accountStatus", {})

func account_register(username: String, password: String) -> Dictionary:
	username = username.strip_edges()
	var bad := username_problem(username)
	if bad == "":
		bad = password_problem(password)
	if bad != "":
		return {"ok": false, "error": bad}
	var c: Dictionary = await _account_ready(false)
	if not c.get("ok", false):
		return c
	var key: String = await derive_key(username, password)
	var r: Dictionary = await act("accountRegister", {"username": username, "key": key, "kdf": Kdf.KDF_ID})
	if r.get("ok", false):
		var d: Dictionary = r.get("data", {}) if r.get("data") is Dictionary else {}
		if str(d.get("token", "")) != "":
			token = str(d.token)
			Prefs.set_profile("token", token)
		_set_account(str(d.get("username", username)))
	return r

## Login on this PC. The server answers with a new welcome (new player id + token) before the result.
## A guest with companies keeps its old token: it is saved as guest_token so Log out brings it back.
func account_login(username: String, password: String) -> Dictionary:
	username = username.strip_edges()
	if username == "" or password == "":
		return {"ok": false, "error": L.t("Wrong username or password")}
	var c: Dictionary = await _account_ready(true)
	if not c.get("ok", false):
		return c
	var prev := token
	var key: String = await derive_key(username, password)
	var r: Dictionary = await act("accountLogin", {"username": username, "key": key, "kdf": Kdf.KDF_ID})
	_after_switch(r, prev)
	return r

func transfer_redeem(code: String) -> Dictionary:
	var c: Dictionary = await _account_ready(true)
	if not c.get("ok", false):
		return c
	var prev := token
	var r: Dictionary = await act("transferRedeem", {"code": code.strip_edges()})
	_after_switch(r, prev)
	return r

func _after_switch(r: Dictionary, prev_token: String) -> void:
	if not r.get("ok", false):
		return
	var d: Dictionary = r.get("data", {}) if r.get("data") is Dictionary else {}
	if d.get("guestKept", false) and prev_token != "":
		Prefs.set_profile("guest_token", prev_token)
	var u: Variant = d.get("username")
	_set_account(str(u) if u != null else "")
	Prefs.set_profile("name", player_name)

func account_logout() -> Dictionary:
	var c: Dictionary = await _account_ready(true)
	if not c.get("ok", false):
		return c
	var args := {}
	var gt := str(Prefs.get_profile("guest_token", ""))
	if gt != "":
		args["guestToken"] = gt
	var r: Dictionary = await act("accountLogout", args)
	if r.get("ok", false):
		var d: Dictionary = r.get("data", {}) if r.get("data") is Dictionary else {}
		if d.get("restored", false):
			Prefs.set_profile("guest_token", "")
		_set_account("")
		Prefs.set_profile("name", player_name)
	return r

func account_change_password(old_password: String, new_password: String) -> Dictionary:
	var bad := password_problem(new_password)
	if bad != "":
		return {"ok": false, "error": bad}
	var c: Dictionary = await _account_ready(false)
	if not c.get("ok", false):
		return c
	var old_key: String = await derive_key(account_name, old_password)
	var new_key: String = await derive_key(account_name, new_password)
	return await act("accountChangePassword", {"oldKey": old_key, "newKey": new_key, "kdf": Kdf.KDF_ID})

func account_delete(password: String) -> Dictionary:
	var c: Dictionary = await _account_ready(false)
	if not c.get("ok", false):
		return c
	var key: String = await derive_key(account_name, password)
	var r: Dictionary = await act("accountDelete", {"key": key})
	if r.get("ok", false):
		_set_account("")
	return r

## {ok, data: {code: "ABCD-EFGH", expiresIn: 600}}
func transfer_create() -> Dictionary:
	var c: Dictionary = await _account_ready(false)
	if not c.get("ok", false):
		return c
	return await act("transferCreate", {})

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
			# servers before accounts send no "account" field: keep what we knew
			if msg.has("account"):
				var acc: Variant = msg.get("account")
				_set_account(str((acc as Dictionary).get("username", "")) if acc is Dictionary else "")
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
			if not (_stay_in_company and _attempt > 0):
				_clock_note_shown = false
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
			last_notify = msg
			var nkey := str(msg.get("key", "")) if msg.get("key") != null else ""
			if nkey.begins_with("story."):
				story_notified.emit(nkey, msg.get("params") if msg.get("params") is Dictionary else {})
			var nt := L.server(msg.get("key"), msg.get("params"), str(msg.get("title", "")))
			var nb := L.server(msg.get("bodyKey"), msg.get("bodyParams"), str(msg.get("body", "")) if msg.get("body") != null else "")
			Bus.notify.emit(str(msg.get("kind", "info")), nt, nb)
			var body_en := str(msg.get("body", "")) if msg.get("body") != null else ""
			last_notify = {}
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
			if str(msg.get("key", "")) == "err.story_clock_paused":
				if _clock_note_shown:
					return
				_clock_note_shown = true
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
