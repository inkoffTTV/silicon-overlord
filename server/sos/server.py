"""Authoritative game server: asyncio + websockets, one shared Lua VM (see lua_host.py), SQLite saves.

Wire protocol: docs/PROTOCOL.md. Actions: docs/ACTIONS.md.
Everything runs on one asyncio thread. Calls into Lua are synchronous; after every call the Lua outbox is
drained and turned into frames (sections / notify / snapshot / profile / left / members) immediately, so
state is never observed half-way. Each connection has an outgoing queue + writer task (ordering, back-pressure).
"""
import asyncio
import concurrent.futures
import json
import logging
import math
import re
import secrets
import time
import unicodedata

import websockets
from websockets.asyncio.server import serve

from .lua_host import LuaHost, LuaError
from .convert import lua_to_py
from .store import Store
from .locale import Locale
from . import accounts as acc

log = logging.getLogger("server")

PROTOCOL_VERSION = 1
MAX_MESSAGE_BYTES = 64 * 1024
CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"   # room codes (PROTOCOL.md)
INVITE_ALPHABET = CODE_ALPHABET + "L"                  # GovernanceService.makeCode (personal invites) also uses L
SPEEDS = (0, 1, 2, 4, 8)
# act names handled in Python without a company (iteration 3; accounts: docs/ACCOUNTS.md)
ACCOUNT_ACTIONS = ("accountStatus", "accountRegister", "accountLogin", "accountLogout", "accountChangePassword",
                   "accountDelete", "transferCreate", "transferRedeem")
LOBBY_ACTIONS = ("listMyCompanies",) + ACCOUNT_ACTIONS
MEMBER_COLORS = ["#4FC3F7", "#FFB74D", "#81C784", "#E57373", "#BA68C8", "#FFD54F", "#4DB6AC", "#F06292"]

# limits
BUCKET_CAPACITY = 30          # same as Roblox RemoteGuard
BUCKET_REFILL = 10.0          # tokens / s
POS_CAPACITY = 20             # pos/ping frames: separate bucket, excess silently dropped
POS_REFILL = 15.0
MAX_QUEUE = 2000              # outgoing frames buffered for a slow client before it is dropped
CHAT_MAX = 200
NAME_MAX = 20
CREATE_COOLDOWN = 5.0         # seconds between two "create" from one connection


LOCALE = Locale()  # localization keys for English texts (docs/LOCALE_KEYS.md)


def now():
    return time.monotonic()


def format_code(code):
    return code[:3] + "-" + code[3:]


def normalize_code(raw):
    if not isinstance(raw, str):
        return None
    code = re.sub(r"[\s\-]", "", raw).upper()
    if len(code) != 6 or any(ch not in INVITE_ALPHABET for ch in code):
        return None
    return code


def clean_name(raw, max_chars):
    """Unicode-aware display / company name check: letters (any script), digits, spaces, - . _ ' & !"""
    if not isinstance(raw, str):
        return None
    s = " ".join(raw.split())
    if not s or len(s) > max_chars:
        return None
    for ch in s:
        if ch in " -._'&!":
            continue
        cat = unicodedata.category(ch)
        if cat[0] not in ("L", "N"):
            return None
    return s


def notify_kind(note):
    sound = str(note.get("sound") or "")
    kind = str(note.get("kind") or "")
    if sound == "Error" or kind.lower() == "error":
        return "error"
    if sound == "Alert":
        return "warning"
    if sound in ("Success", "Launch", "Cash", "Research"):
        return "success"
    return "info"


class Bucket:
    __slots__ = ("cap", "rate", "tokens", "last")

    def __init__(self, cap, rate):
        self.cap, self.rate, self.tokens, self.last = cap, rate, float(cap), now()

    def take(self):
        t = now()
        self.tokens = min(self.cap, self.tokens + (t - self.last) * self.rate)
        self.last = t
        if self.tokens < 1:
            return False
        self.tokens -= 1
        return True


class Conn:
    _next = 1

    def __init__(self, ws):
        self.ws = ws
        self.cid = Conn._next
        Conn._next += 1
        self.queue = asyncio.Queue()
        self.pid = None
        self.name = None
        self.room = None          # Room or None
        self.bucket = Bucket(BUCKET_CAPACITY, BUCKET_REFILL)
        self.pos_bucket = Bucket(POS_CAPACITY, POS_REFILL)
        self.pos = None
        self.closed = False
        self.last_create = -1e9
        self.addr = getattr(ws, "remote_address", None)
        self.token_hash = None    # sha256 of the device token this connection said hello with
        self.acct_busy = False    # an account action (scrypt) is running

    @property
    def ip(self):
        a = self.addr
        return str(a[0]) if isinstance(a, (tuple, list)) and a else str(a)

    def send(self, obj):
        if obj.get("t") in ("res", "error"):
            LOCALE.outgoing(obj)
        self.send_raw(json.dumps(obj, ensure_ascii=False, separators=(",", ":"), allow_nan=False))

    def send_raw(self, text):
        if self.closed:
            return
        if self.queue.qsize() > MAX_QUEUE:
            log.warning("conn %s (player %s) too slow, dropping", self.cid, self.pid)
            self.closed = True
            asyncio.ensure_future(self.ws.close(1008, "too slow"))
            return
        self.queue.put_nowait(text)


class Room:
    """A loaded company (the Python half of a CompanyService session)."""

    def __init__(self, company_id, code, owner):
        self.id = company_id
        self.code = code
        self.owner = owner
        self.conns = {}            # pid -> Conn
        self.empty_since = now()
        self.last_save = now()
        self.pos_dirty = False


class GameServer:
    def __init__(self, data_dir, autosave_seconds=60.0, idle_unload_seconds=60.0, tick_seconds=0.1,
                 peers_hz=10.0, stats_seconds=300.0, housekeeping_seconds=5.0):
        self.store = Store(data_dir)
        self.lua = LuaHost(load_profile=self.store.load_profile)
        self.autosave_seconds = autosave_seconds
        self.idle_unload_seconds = idle_unload_seconds
        self.tick_seconds = tick_seconds
        self.peers_interval = 1.0 / peers_hz
        self.stats_seconds = stats_seconds
        self.boards_seconds = 30.0
        self.housekeeping_seconds = housekeeping_seconds
        self.rooms = {}            # company id -> Room
        self.players = {}          # pid -> Conn (one live connection per player)
        self.profiles_dirty = {}   # pid -> latest profile dict to write
        self.stats = {"ticks": 0, "tick_cpu": 0.0, "tick_max": 0.0, "days": 0}
        self._tasks = []
        self._server = None
        self.port = None
        self.stopping = False
        # account rate limits (docs/ACCOUNTS.md "Rate limits"); tests may replace them.
        # Nothing is locked per username alone: that would let anyone lock any account (password owner included).
        self.login_ip = acc.Limiter(max_fail=5, window=60.0, base_lock=60.0)     # wrong logins per IP, never reset
        self.login_pair = acc.Limiter(max_fail=5, window=60.0, base_lock=60.0)   # per (username, IP)
        self.login_user_fails = acc.Counter(10, 600.0)       # per username, all IPs: only adds a delay (soft)
        self.login_soft_delay = 1.0                          # seconds added to each login of a name under attack
        self.login_ip_attempts = acc.Counter(30, 60.0)       # caps scrypt work per IP, failures or not
        self.verify_pid = acc.Limiter(max_fail=5, window=60.0, base_lock=60.0)   # change password / delete
        self.acct_ops = acc.Counter(5, 600.0)                # change password + delete per player, right or wrong
        self.register_ip = acc.Counter(5, 600.0)             # accounts created per IP
        self.register_probe_ip = acc.Counter(20, 600.0)      # register attempts per IP ("taken" answers count)
        self.transfer_ip = acc.Limiter(max_fail=5, window=60.0, base_lock=60.0)  # wrong codes per IP, never reset
        self.transfer_try_ip = acc.Counter(20, 600.0)        # redeem attempts per IP, right or wrong
        self.transfer_new = acc.Counter(5, 600.0)            # codes created per player
        # scrypt runs in small dedicated pools: logins / registrations, and the rare change-password / delete
        # work, so neither can take all CPUs or starve the other
        self._kdf_pool = concurrent.futures.ThreadPoolExecutor(max_workers=2, thread_name_prefix="kdf")
        self._kdf_pool_slow = concurrent.futures.ThreadPoolExecutor(max_workers=1, thread_name_prefix="kdf-slow")

    # ------------------------------------------------------------------------------------------
    # Lua calls + outbox dispatch
    # ------------------------------------------------------------------------------------------
    def lcall(self, name, *args):
        """Calls Host.<name>; on a Lua error logs it, still drains the outbox and re-raises."""
        try:
            return self.lua.call(name, *args)
        except LuaError:
            log.exception("Lua error in Host.%s", name)
            raise
        finally:
            self.dispatch()

    def dispatch(self):
        events = self.lua.drain()
        if not events:
            return
        profiles = {}
        for ev in events:
            t = ev["t"]
            if t == "sections":
                room = self.rooms.get(ev["sid"])
                if room and room.conns:
                    LOCALE.state(ev["data"])
                    text = json.dumps({"t": "sections", "data": ev["data"]}, ensure_ascii=False,
                                      separators=(",", ":"), allow_nan=False)
                    for c in room.conns.values():
                        c.send_raw(text)
            elif t == "notify":
                room = self.rooms.get(ev["sid"])
                if not room:
                    continue
                note = ev["note"] or {}
                frame = {"t": "notify", "kind": notify_kind(note), "title": str(note.get("title") or ""),
                         "body": str(note.get("body") or ""), "category": note.get("kind"), "sound": note.get("sound")}
                LOCALE.notify(frame, note)
                uid = ev.get("userId")
                if uid is not None:
                    c = room.conns.get(int(uid))
                    if c:
                        c.send(frame)
                else:
                    for c in room.conns.values():
                        c.send(frame)
            elif t == "snapshot":
                room = self.rooms.get(ev["sid"])
                c = room.conns.get(ev["userId"]) if room else None
                if c is None:
                    c = self.players.get(ev["userId"])  # joining: the conn is attached after the Lua call
                if c:
                    c.send({"t": "snapshot", "state": LOCALE.state(self.lua.state_py(ev["sid"]))})
            elif t == "profile":
                p = profiles.setdefault(ev["userId"], {"profile": None, "save": False, "send": False})
                p["profile"] = ev["profile"]
                p["save"] = p["save"] or ev["save"]
                p["send"] = p["send"] or ev["send"]
            elif t == "left":
                self._on_left(ev["sid"], ev["userId"], ev["reason"], ev.get("points"))
            elif t == "members":
                self.send_members(ev["sid"])
        for pid, p in profiles.items():
            if p["save"]:
                self.profiles_dirty[pid] = p["profile"]
            if p["send"]:
                c = self.players.get(pid)
                if c:
                    c.send({"t": "profile", "profile": p["profile"]})

    def _on_left(self, sid, pid, reason, points=None):
        room = self.rooms.get(sid)
        c = self.players.get(pid)
        if room:
            room.conns.pop(pid, None)
            if not room.conns:
                room.empty_since = now()
            room.pos_dirty = True
        if c and c.room is room:
            c.room = None
            frame = {"t": "left", "reason": reason}
            if points is not None:
                frame["points"] = points
            c.send(frame)

    def members_list(self, sid):
        room = self.rooms.get(sid)
        raw = lua_to_py(self.lua.call("members", sid)) or []
        if isinstance(raw, dict):
            raw = list(raw.values())
        out = []
        for i, m in enumerate(raw):
            uid = m.get("userId")
            out.append({"userId": uid, "name": m.get("name"), "color": self.color_of(uid),
                        "role": m.get("role"), "title": m.get("title"), "sharePercent": m.get("sharePercent"),
                        "online": bool(room and uid in room.conns)})
        return out

    @staticmethod
    def color_of(uid):
        return MEMBER_COLORS[(uid or 0) % len(MEMBER_COLORS)]

    def send_members(self, sid):
        room = self.rooms.get(sid)
        if not room or not room.conns:
            return
        frame = {"t": "members", "list": self.members_list(sid)}
        for c in room.conns.values():
            c.send(frame)

    # ------------------------------------------------------------------------------------------
    # persistence
    # ------------------------------------------------------------------------------------------
    def save_room(self, room, force=False):
        meta = lua_to_py(self.lua.call("meta", room.id))
        if not meta:
            return False
        if not force and meta["stateVersion"] == meta["loadedVersion"]:
            room.last_save = now()
            return False
        self.lua.call("markSaved", room.id)
        state = self.lua.state_py(room.id)
        members = [m["userId"] for m in self.members_list(room.id)]
        try:
            self.store.save_company(room.id, members, state.get("name") or "", state.get("mode") or "solo", state,
                                    int(state.get("stateVersion") or 0))
        except Exception:
            log.exception("save failed for company %s", room.id)
            return False
        room.last_save = now()
        return True

    def flush_profiles(self):
        if not self.profiles_dirty:
            return
        dirty, self.profiles_dirty = self.profiles_dirty, {}
        for pid, profile in dirty.items():
            try:
                self.store.save_profile(pid, profile)
            except Exception:
                log.exception("profile save failed for %s", pid)

    def load_room(self, company_id):
        room = self.rooms.get(company_id)
        if room:
            return room
        meta = self.store.company_meta(company_id)
        if not meta:
            return None
        state = self.store.load_company_state(company_id)
        self.lcall("loadCompany", self.lua.to_lua(state))
        room = Room(company_id, meta["code"], meta["owner"])
        self.rooms[company_id] = room
        log.info("loaded company %s (%s)", company_id, meta["name"])
        return room

    def unload_room(self, room):
        self.save_room(room)
        for pid, c in list(room.conns.items()):
            c.room = None
        self.lcall("unload", room.id)
        self.rooms.pop(room.id, None)
        log.info("unloaded company %s", room.id)

    def new_code(self):
        for _ in range(1000):
            code = "".join(secrets.choice(CODE_ALPHABET) for _ in range(6))
            if not self.store.code_exists(code):
                return code
        raise RuntimeError("no free room code")

    # ------------------------------------------------------------------------------------------
    # connection lifecycle
    # ------------------------------------------------------------------------------------------
    async def handler(self, ws):
        conn = Conn(ws)
        writer = asyncio.ensure_future(self._writer(conn))
        try:
            async for raw in ws:
                if conn.closed:
                    break
                try:
                    self.on_message(conn, raw)
                except Exception:
                    log.exception("message handling failed (player %s)", conn.pid)
                    conn.send({"t": "error", "message": "Internal error"})
        except websockets.ConnectionClosed:
            pass
        finally:
            self.on_close(conn)
            conn.closed = True
            writer.cancel()

    async def _writer(self, conn):
        try:
            while True:
                text = await conn.queue.get()
                await conn.ws.send(text)
        except (asyncio.CancelledError, websockets.ConnectionClosed):
            pass

    def on_close(self, conn):
        if self.stopping or conn.pid is None or self.players.get(conn.pid) is not conn:
            return
        self.detach(conn, notify=False)
        try:
            self.lcall("disconnectPlayer", conn.pid)
        except LuaError:
            pass
        self.players.pop(conn.pid, None)
        self.flush_profiles()
        log.info("player %s (%s) disconnected", conn.pid, conn.name)

    def detach(self, conn, notify=True, reason="leave"):
        """Removes the connection from its room (company keeps running for the others)."""
        room = conn.room
        if room is None:
            return
        room.conns.pop(conn.pid, None)
        conn.room = None
        room.pos_dirty = True
        try:
            self.lcall("leave", conn.pid)
        except LuaError:
            pass
        if not room.conns:
            room.empty_since = now()
            self.save_room(room)  # save on last member leave
        if notify:
            conn.send({"t": "left", "reason": reason})

    def attach_conn(self, conn, room):
        room.conns[conn.pid] = conn
        conn.room = room
        conn.pos = None
        room.pos_dirty = True

    def send_joined(self, conn, room):
        role = self.lua.call("roleOf", conn.pid, room.id)
        conn.send({"t": "joined", "code": format_code(room.code), "companyId": room.id,
                   "you": {"userId": conn.pid, "role": role, "name": conn.name, "color": self.color_of(conn.pid)},
                   "members": self.members_list(room.id)})
        try:
            conn.send(dict(t="boards", **self.boards()))
        except Exception:
            log.exception("boards failed")

    # ------------------------------------------------------------------------------------------
    # messages
    # ------------------------------------------------------------------------------------------
    def on_message(self, conn, raw):
        if isinstance(raw, bytes):
            conn.send({"t": "error", "message": "Text frames only"})
            return
        try:
            msg = json.loads(raw)
        except ValueError:
            conn.send({"t": "error", "message": "Invalid JSON"})
            return
        if not isinstance(msg, dict) or not isinstance(msg.get("t"), str):
            conn.send({"t": "error", "message": "Message must be an object with field t"})
            return
        t = msg["t"]
        if t in ("pos", "ping"):
            if not conn.pos_bucket.take():
                return
            if t == "ping":
                conn.send({"t": "pong", "n": msg.get("n")})
            else:
                self.on_pos(conn, msg)
            return
        if not conn.bucket.take():
            if t == "act":
                conn.send({"t": "res", "id": msg.get("id"), "ok": False, "error": "Too many requests"})
            else:
                conn.send({"t": "error", "message": "Too many requests"})
            return
        if t == "hello":
            self.on_hello(conn, msg)
            return
        if conn.pid is None:
            conn.send({"t": "error", "message": "Send hello first"})
            return
        fn = {
            "create": self.on_create, "join": self.on_join, "resume": self.on_resume, "leave": self.on_leave,
            "act": self.on_act, "speed": self.on_speed, "chat": self.on_chat,
        }.get(t)
        if fn is None:
            conn.send({"t": "error", "message": "Unknown message type: " + t[:32]})
            return
        fn(conn, msg)

    def on_hello(self, conn, msg):
        if msg.get("v") != PROTOCOL_VERSION:
            conn.send({"t": "error", "message": "Unsupported protocol version (server speaks v%d)" % PROTOCOL_VERSION})
            return
        if conn.pid is not None:
            conn.send({"t": "error", "message": "Already greeted"})
            return
        name = clean_name(msg.get("name"), NAME_MAX)
        token = msg.get("token")
        player = self.store.player_by_token(token) if isinstance(token, str) and 0 < len(token) <= 128 else None
        if player is None:
            if name is None:
                conn.send({"t": "error", "message": "Name: 1-%d letters, digits or spaces" % NAME_MAX})
                return
            player = self.store.create_player(name)
        else:
            name = name or player["name"]
            self.store.touch_player(player["id"], name)
        self._bind(conn, player["id"], name, player["token"])

    def _bind(self, conn, pid, name, token):
        """Makes conn the live connection of player pid (hello, or an account switch) and sends welcome."""
        old = self.players.get(pid)
        if old is not None and old is not conn:
            # same token connected again (reconnect / second window): the newest connection wins
            self.detach(old, notify=False)
            old.send({"t": "left", "reason": "replaced"})
            try:
                self.lcall("disconnectPlayer", pid)
            except LuaError:
                pass
            self.players.pop(pid, None)
            old.closed = True
            asyncio.ensure_future(old.ws.close(1000, "replaced"))
        self.flush_profiles()
        conn.pid, conn.name = pid, name
        conn.token_hash = acc.token_hash(token)
        self.players[pid] = conn
        account = self.store.account_of(pid)
        # `account` is new (accounts): {username} or null; old clients ignore it
        conn.send({"t": "welcome", "playerId": pid, "token": token, "name": name,
                   "lastCompany": self.store.last_company(pid),
                   "account": {"username": account["username"]} if account else None})
        self.lcall("connectPlayer", pid, name, self.lua.to_lua(self.store.load_profile(pid)))
        log.info("player %s (%s) connected from %s", pid, name, conn.addr)

    def _leave_current(self, conn):
        if conn.room is not None:
            self.detach(conn, notify=False)

    def on_create(self, conn, msg):
        company = msg.get("company")
        if not isinstance(company, dict):
            conn.send({"t": "error", "message": "create needs company: name, colorA, colorB, mode"})
            return
        name = clean_name(company.get("name"), 24)
        if name is None:
            conn.send({"t": "error", "message": "Company name: 1-24 letters, digits or spaces"})
            return
        mode = "cofounder" if company.get("mode") == "cofounder" else "solo"
        if now() - conn.last_create < CREATE_COOLDOWN:
            conn.send({"t": "error", "message": "Wait a few seconds before creating another company"})
            return
        conn.last_create = now()

        def color(v, default):
            return v if isinstance(v, str) and re.fullmatch(r"#[0-9A-Fa-f]{6}", v) else default

        self._leave_current(conn)
        cid = secrets.token_hex(10)
        code = self.new_code()
        args = {"id": cid, "name": name, "mode": mode, "colorA": color(company.get("colorA"), "#2F80ED"),
                "colorB": color(company.get("colorB"), "#56CCF2"),
                "shape": company.get("shape") if isinstance(company.get("shape"), str) else None,
                "founderShare": company.get("founderShare") if isinstance(company.get("founderShare"), (int, float)) else None,
                "storyMode": company.get("storyMode") is True,  # iteration 3: story start (default: quick start)
                "seed": int(time.time()) % 1000000 + conn.pid % 1000}
        room = Room(cid, code, conn.pid)
        self.rooms[cid] = room
        self.attach_conn(conn, room)
        try:
            ok, res = self.lua.call("createCompany", conn.pid, self.lua.to_lua(args), True)
        except LuaError:
            log.exception("createCompany failed")
            ok, res = False, "Internal error"
        if not ok:
            self.rooms.pop(cid, None)
            conn.room = None
            self.lua.drain()
            conn.send({"t": "error", "message": str(res)})
            return
        state = self.lua.state_py(cid)
        self.lua.call("markSaved", cid)
        self.store.insert_company(cid, code, conn.pid, [conn.pid], name, mode, state, int(state.get("stateVersion") or 0))
        self.store.set_last_company(conn.pid, cid)
        self.send_joined(conn, room)
        self.dispatch()  # snapshot, profile, members
        log.info("player %s created company %s %s (%s%s)", conn.pid, cid, format_code(code), mode,
                 ", story" if args["storyMode"] else "")

    def on_join(self, conn, msg):
        code = normalize_code(msg.get("code"))
        if code is None:
            conn.send({"t": "error", "message": "Enter a 6-character code like ABC-123"})
            return
        meta = self.store.company_by_code(code)
        if meta is not None:
            if conn.room is not None and conn.room.id == meta["id"]:
                self.send_joined(conn, conn.room)
                self.lcall("act", conn.pid, "getSnapshot", self.lua.to_lua({}))
                return
            self._leave_current(conn)
            room = self.load_room(meta["id"])
            if room is None:
                conn.send({"t": "error", "message": "Company not found"})
                return
            self._finish_join(conn, room, "joinByRoomCode", conn.pid, room.id)
            return
        # personal invite codes (createInvite action) of companies loaded right now
        sid = self.lua.call("findInvite", code)
        if sid is None or sid not in self.rooms:
            conn.send({"t": "error", "message": "No company with that code"})
            return
        self._leave_current(conn)
        self._finish_join(conn, self.rooms[sid], "redeemInvite", conn.pid, sid, code)

    def _finish_join(self, conn, room, fn, *args):
        self.attach_conn(conn, room)
        try:
            ok, err = self.lua.call(fn, *args)
        except LuaError:
            log.exception("%s failed", fn)
            ok, err = False, "Internal error"
        if not ok:
            room.conns.pop(conn.pid, None)
            conn.room = None
            if not room.conns:
                room.empty_since = now()
            self.dispatch()
            conn.send({"t": "error", "message": str(err)})
            return
        # profile.companyId is the source of "last company" (saved with the profile) -> keep both in sync
        self.lua.call("setProfileCompany", conn.pid, room.id)
        self.store.set_last_company(conn.pid, room.id)
        self.send_joined(conn, room)
        self.dispatch()
        log.info("player %s joined company %s", conn.pid, room.id)

    def on_resume(self, conn, msg):
        last = self.store.last_company(conn.pid)
        if not last:
            conn.send({"t": "error", "message": "No company to resume"})
            return
        if conn.room is not None and conn.room.id == last:
            self.send_joined(conn, conn.room)
            self.lcall("act", conn.pid, "getSnapshot", self.lua.to_lua({}))
            return
        self._leave_current(conn)
        room = self.load_room(last)
        if room is None:
            self.store.set_last_company(conn.pid, None)
            conn.send({"t": "error", "message": "Company not found"})
            return
        self._finish_join(conn, room, "attach", conn.pid, room.id)

    def on_leave(self, conn, msg):
        if conn.room is None:
            conn.send({"t": "left", "reason": "leave"})
            return
        self.detach(conn, notify=True, reason="leave")

    def on_act(self, conn, msg):
        aid = msg.get("id")
        if not isinstance(aid, int) or isinstance(aid, bool):
            conn.send({"t": "error", "message": "act needs an integer id"})
            return
        action = msg.get("action")
        if action in LOBBY_ACTIONS:
            self.on_lobby_act(conn, aid, action, msg.get("args"))
            return
        if not isinstance(action, str) or action not in self.lua.action_names:
            conn.send({"t": "res", "id": aid, "ok": False, "error": "Unknown action"})
            return
        args = msg.get("args")
        if args is None:
            args = {}
        if not isinstance(args, dict):
            conn.send({"t": "res", "id": aid, "ok": False, "error": "args must be an object"})
            return
        if conn.room is None:
            conn.send({"t": "res", "id": aid, "ok": False, "error": "You are not in a company"})
            return
        try:
            ok, data = self.lcall("act", conn.pid, action, self.lua.to_lua(args))
            if ok:
                frame = {"t": "res", "id": aid, "ok": True}
                d = lua_to_py(data)
                if d is not None:
                    frame["data"] = d
            else:
                frame = {"t": "res", "id": aid, "ok": False,
                         "error": str(lua_to_py(data) if data is not None else "Failed")}
            conn.send(frame)
        except LuaError:  # already logged by lcall
            conn.send({"t": "res", "id": aid, "ok": False, "error": "Internal error"})
        except Exception:
            log.exception("act %s failed", action)
            conn.send({"t": "res", "id": aid, "ok": False, "error": "Internal error"})

    # ------------------------------------------------------------------------------------------
    # lobby actions (iteration 3): allowed right after hello, no company needed
    # ------------------------------------------------------------------------------------------
    def on_lobby_act(self, conn, aid, action, args):
        if args is not None and not isinstance(args, dict):
            conn.send({"t": "res", "id": aid, "ok": False, "error": "args must be an object"})
            return
        if action in ACCOUNT_ACTIONS:
            asyncio.ensure_future(self._account_task(conn, aid, action, args or {}))
            return
        try:
            data = self.list_my_companies(conn.pid)
        except Exception:
            log.exception("lobby act %s failed", action)
            conn.send({"t": "res", "id": aid, "ok": False, "error": "Internal error"})
            return
        conn.send({"t": "res", "id": aid, "ok": True, "data": data})

    def list_my_companies(self, pid):
        """Company slots for the title menu: every company where pid is an active owner, newest first.
        Loaded companies report live values (cash, date, online); others the last save."""
        rows = {r["id"]: r for r in self.store.companies_of(pid)}
        for cid in self.rooms:  # joined since the last save: the saved member list is not updated yet
            if cid not in rows and self.lua.call("isOwner", pid, cid):
                meta = self.store.company_meta(cid)
                if meta:
                    rows[cid] = meta
        out = []
        for row in rows.values():
            cid = row["id"]
            room = self.rooms.get(cid)
            state = self.lua.state_py(cid) if room is not None else None
            if state is None:
                state = self.store.load_company_state(cid) or {}
            if state.get("liquidated"):
                continue
            owners = state.get("owners") or {}
            owner = owners.get(str(pid)) if isinstance(owners, dict) else None
            if not isinstance(owner, dict) or owner.get("left"):
                continue
            t = state.get("time") or {}
            story = state.get("story") if isinstance(state.get("story"), dict) else {}
            online = len(room.conns) if room is not None else 0
            out.append({
                "companyId": cid, "code": format_code(row["code"]), "name": state.get("name") or row["name"],
                "date": {"year": t.get("year"), "day": t.get("day"), "elapsedDays": t.get("elapsedDays")},
                "cash": (state.get("finance") or {}).get("cash"), "role": owner.get("role"),
                "lastPlayed": int(time.time()) if online else int(row["updated"] or 0),
                "mode": state.get("mode") or row["mode"], "logo": state.get("logo"),
                "story": {"done": story.get("done", True) is not False, "chapter": story.get("chapter", 7)},
                "online": online,
            })
        out.sort(key=lambda r: (-(r["lastPlayed"] or 0), r["name"] or ""))
        return out

    # ------------------------------------------------------------------------------------------
    # accounts (docs/ACCOUNTS.md). Handlers are coroutines: scrypt runs in a worker thread.
    # Never log args: they carry derived password keys and transfer codes.
    # ------------------------------------------------------------------------------------------
    async def _account_task(self, conn, aid, action, args):
        if conn.acct_busy:
            conn.send({"t": "res", "id": aid, "ok": False, "error": acc.ERR_BUSY})
            return
        conn.acct_busy = True
        try:
            fn = getattr(self, "_acct_" + action)
            ok, data, switch = await fn(conn, args)
        except Exception:
            log.exception("account action %s failed (player %s)", action, conn.pid)
            ok, data, switch = False, "Internal error", None
        finally:
            conn.acct_busy = False
        if conn.closed:
            return
        if ok and switch is not None:
            # identity switch (login, logout, transfer code): welcome with the new token first, then the answer
            pid, token = switch
            self._switch_player(conn, pid, token)
        if ok:
            frame = {"t": "res", "id": aid, "ok": True}
            if data is not None:
                frame["data"] = data
        else:
            frame = {"t": "res", "id": aid, "ok": False, "error": data}
            if isinstance(data, str) and data.startswith("Too many attempts"):
                frame["errorKey"] = "err.account_locked"
                frame["errorParams"] = {"s": int(re.sub(r"\D", "", data) or 0)}
        conn.send(frame)

    def _switch_player(self, conn, pid, token):
        old = conn.pid
        if old is not None and self.players.get(old) is conn:
            self.detach(conn, notify=False)
            try:
                self.lcall("disconnectPlayer", old)
            except LuaError:
                pass
            self.players.pop(old, None)
        player = self.store.player(pid)
        self.store.touch_player(pid, player["name"])
        self._bind(conn, pid, player["name"], token)

    def _alive(self, conn, pid):
        return not conn.closed and conn.pid == pid and self.players.get(pid) is conn

    async def _scrypt(self, fn, *a, slow=False):
        pool = self._kdf_pool_slow if slow else self._kdf_pool
        return await asyncio.get_running_loop().run_in_executor(pool, fn, *a)

    def _locked(self, *waits):
        w = max(waits)
        return acc.ERR_LOCKED.format(s=w) if w > 0 else None

    @staticmethod
    def _reserve(slots):
        """acquire() on every (limiter, key) or on none. 0 when all reserved, else seconds to wait."""
        got = []
        for lim, key in slots:
            w = lim.acquire(key)
            if w:
                for l2, k2 in got:
                    l2.cancel(k2)
                return w
            got.append((lim, key))
        return 0

    def _guest_left_behind(self, conn):
        """Before this PC switches to another player: what happens to the device token it used so far.
        A guest with companies keeps its token (the client keeps it to come back on logout); anything else is
        revoked (rotation: the old token on this PC stops working). Returns True when kept."""
        pid = conn.pid
        if self.store.account_of(pid) is None and self.list_my_companies(pid):
            return True
        if conn.token_hash:
            self.store.revoke_device(conn.token_hash)
        return False

    async def _acct_accountStatus(self, conn, args):
        a = self.store.account_of(conn.pid)
        return True, {"account": {"username": a["username"], "created": int(a["created"])} if a else None,
                      "devices": self.store.device_count(conn.pid),
                      "companies": len(self.list_my_companies(conn.pid))}, None

    async def _acct_accountRegister(self, conn, args):
        pid = conn.pid
        if self.store.account_of(pid):
            return False, "You already have an account", None
        username = args.get("username")
        err = acc.username_error(username)
        if err:
            return False, err, None
        key = args.get("key")
        if not acc.valid_key(key) or args.get("kdf", acc.KDF_ID) != acc.KDF_ID:
            return False, "Bad password key", None
        # every attempt counts before the lookup: "taken" must not be a free username oracle
        if not self.register_probe_ip.hit(conn.ip):
            return False, acc.ERR_LOCKED.format(s=self.register_probe_ip.wait(conn.ip)), None
        lc = acc.canonical(username)
        if self.store.username_taken(lc, acc.skeleton(username)):
            return False, "That username is taken", None
        if not self.register_ip.hit(conn.ip):
            return False, acc.ERR_LOCKED.format(s=self.register_ip.wait(conn.ip)), None
        salt, h = await self._scrypt(acc.hash_key, key)
        if not self._alive(conn, pid):
            return False, "Connection changed", None
        if not self.store.create_account(pid, username, lc, acc.KDF_ID, salt, h):
            return False, "That username is taken", None
        # rotate this device's token: the account is now the only way in, old copies of the guest token die
        token = self.store.add_device(pid)
        if conn.token_hash:
            self.store.revoke_device(conn.token_hash)
        conn.token_hash = acc.token_hash(token)
        log.info("player %s registered account %s", pid, username)
        return True, {"username": username, "token": token}, None

    async def _acct_accountLogin(self, conn, args):
        pid = conn.pid
        if conn.room is not None:
            return False, "Leave the company first", None
        username, key = args.get("username"), args.get("key")
        lc = acc.canonical(username)[:64]
        ip = conn.ip
        # the attempt is reserved (counted as a failure) before the await, so parallel requests cannot all pass
        slots = [(self.login_ip, ip), (self.login_pair, (lc, ip))]
        w = self._reserve(slots)
        if w:
            return False, acc.ERR_LOCKED.format(s=w), None
        if not self.login_ip_attempts.hit(ip):
            for lim, k in slots:
                lim.cancel(k)
            return False, acc.ERR_LOCKED.format(s=self.login_ip_attempts.wait(ip)), None
        ok = False
        try:
            if self.login_user_fails.count(lc) >= self.login_user_fails.max_hits:
                await asyncio.sleep(self.login_soft_delay)   # a name under attack: slower, never locked
            a = self.store.account_by_username(lc) if lc else None
            if a is not None and acc.valid_key(key) and a["kdf"] == args.get("kdf", acc.KDF_ID):
                ok = await self._scrypt(acc.verify_key, key, a["salt"], a["hash"])
            else:
                await self._scrypt(acc.burn_time, key)
        finally:
            # the IP lock is never reset by a success (a login to your own account must not wipe the failures
            # you made guessing other names); it only decays with time
            self.login_ip.release(ip, ok)
            self.login_pair.release((lc, ip), ok, reset=True)
        if not ok:
            self.login_user_fails.add(lc)
            log.info("failed login from %s", ip)
            return False, acc.ERR_LOGIN, None
        if not self._alive(conn, pid) or conn.room is not None:
            return False, "Connection changed", None
        target = a["player_id"]
        kept = False
        if target == pid:
            if conn.token_hash:
                self.store.revoke_device(conn.token_hash)
        else:
            kept = self._guest_left_behind(conn)
        token = self.store.add_device(target)
        log.info("player %s logged in as %s (account player %s)", pid, a["username"], target)
        return True, {"username": a["username"], "guestKept": kept}, (target, token)

    async def _acct_accountLogout(self, conn, args):
        pid = conn.pid
        if conn.room is not None:
            return False, "Leave the company first", None
        if self.store.account_of(pid) is None:
            return False, "You are not logged in", None
        if conn.token_hash:
            self.store.revoke_device(conn.token_hash)
        conn.token_hash = None
        # back to the guest profile this PC had before logging in (if the client kept it), else a fresh guest
        gt = args.get("guestToken")
        guest = self.store.player_by_token(gt) if isinstance(gt, str) and 0 < len(gt) <= 128 else None
        if guest is not None and (guest["id"] == pid or self.store.account_of(guest["id"]) is not None):
            guest = None
        if guest is not None:
            token, gid = gt, guest["id"]
        else:
            g = self.store.create_player(conn.name or "Player")
            token, gid = g["token"], g["id"]
        log.info("player %s logged out (now guest %s)", pid, gid)
        return True, {"guest": True, "restored": guest is not None}, (gid, token)

    async def _verify_current(self, conn, key):
        """(account, None) when key is this account's current key, else (None, error)."""
        a = self.store.account_of(conn.pid)
        if a is None:
            return None, "You are not logged in"
        # Only someone holding a live token of this account gets here, so the limit is per player: failed logins
        # from other IPs (an attack on the username) can never stop the owner from changing the password.
        pid = conn.pid
        if not self.acct_ops.hit(pid):
            return None, acc.ERR_LOCKED.format(s=self.acct_ops.wait(pid))
        w = self._reserve([(self.verify_pid, pid)])
        if w:
            return None, acc.ERR_LOCKED.format(s=w)
        ok = False
        try:
            ok = acc.valid_key(key) and await self._scrypt(acc.verify_key, key, a["salt"], a["hash"], slow=True)
        finally:
            self.verify_pid.release(pid, ok, reset=True)
        if not ok:
            return None, "Wrong password"
        return a, None

    async def _acct_accountChangePassword(self, conn, args):
        pid = conn.pid
        new = args.get("newKey")
        if not acc.valid_key(new):
            return False, "Bad password key", None
        a, err = await self._verify_current(conn, args.get("oldKey"))
        if err:
            return False, err, None
        salt, h = await self._scrypt(acc.hash_key, new, slow=True)
        if not self._alive(conn, pid):
            return False, "Connection changed", None
        self.store.set_password(pid, acc.KDF_ID, salt, h)
        # every other device has to log in again with the new password
        n = self.store.revoke_other_devices(pid, conn.token_hash)
        self.store.drop_transfers(pid)
        log.info("player %s changed the password (%d other devices signed out)", pid, n)
        return True, {"signedOut": n}, None

    async def _acct_accountDelete(self, conn, args):
        pid = conn.pid
        a, err = await self._verify_current(conn, args.get("key"))
        if err:
            return False, err, None
        if not self._alive(conn, pid):
            return False, "Connection changed", None
        self.store.delete_account(pid)
        n = self.store.revoke_other_devices(pid, conn.token_hash)
        self.store.drop_transfers(pid)
        log.info("player %s deleted account %s (%d other devices signed out)", pid, a["username"], n)
        return True, {"signedOut": n}, None

    async def _acct_transferCreate(self, conn, args):
        pid = conn.pid
        if not self.transfer_new.hit(pid):
            return False, acc.ERR_LOCKED.format(s=self.transfer_new.wait(pid)), None
        code = acc.new_transfer_code()
        self.store.put_transfer(acc.token_hash(code), pid, time.time() + acc.TRANSFER_TTL)
        log.info("player %s created a transfer code", pid)
        return True, {"code": acc.format_transfer(code), "expiresIn": int(acc.TRANSFER_TTL)}, None

    async def _acct_transferRedeem(self, conn, args):
        pid = conn.pid
        if conn.room is not None:
            return False, "Leave the company first", None
        ip = conn.ip
        locked = self._locked(self.transfer_ip.check(ip))
        if locked:
            return False, locked, None
        if not self.transfer_try_ip.hit(ip):
            return False, acc.ERR_LOCKED.format(s=self.transfer_try_ip.wait(ip)), None
        code = acc.normalize_transfer(args.get("code"))
        target = self.store.take_transfer(acc.token_hash(code)) if code else None
        if target is None or self.store.player(target) is None:
            self.transfer_ip.fail(ip)
            return False, acc.ERR_CODE, None
        # no reset of transfer_ip on success: redeeming your own code must not wipe the wrong guesses
        a = self.store.account_of(target)
        if target == pid:
            return True, {"username": a["username"] if a else None, "guestKept": False, "same": True}, None
        kept = self._guest_left_behind(conn)
        token = self.store.add_device(target)
        log.info("player %s used a transfer code -> player %s", pid, target)
        return True, {"username": a["username"] if a else None, "guestKept": kept}, (target, token)

    def on_speed(self, conn, msg):
        speed = msg.get("speed")
        if isinstance(speed, bool) or speed not in SPEEDS:
            conn.send({"t": "error", "message": "Speed must be 0, 1, 2, 4 or 8"})
            return
        if conn.room is None:
            conn.send({"t": "error", "message": "You are not in a company"})
            return
        try:
            ok, err = self.lcall("act", conn.pid, "setSpeed", self.lua.to_lua({"speed": int(speed)}))
        except LuaError:
            ok, err = False, "Internal error"
        if not ok:
            conn.send({"t": "error", "message": str(err)})

    def on_pos(self, conn, msg):
        room = conn.room
        if room is None or conn.pid is None:
            return
        p = msg.get("p")
        if not (isinstance(p, list) and len(p) == 3 and all(_finite(v) for v in p)):
            return
        yaw, pitch = msg.get("yaw", 0), msg.get("pitch", 0)
        anim = msg.get("anim", "idle")
        conn.pos = {"p": [round(float(v), 3) for v in p], "yaw": round(float(yaw), 3) if _finite(yaw) else 0,
                    "pitch": round(float(pitch), 3) if _finite(pitch) else 0,
                    "anim": anim[:24] if isinstance(anim, str) else "idle"}
        room.pos_dirty = True

    def on_chat(self, conn, msg):
        room = conn.room
        if room is None:
            conn.send({"t": "error", "message": "You are not in a company"})
            return
        text = msg.get("text")
        if not isinstance(text, str):
            return
        text = "".join(ch for ch in text if ch == " " or unicodedata.category(ch)[0] != "C").strip()[:CHAT_MAX]
        if not text:
            return
        frame = json.dumps({"t": "chat", "userId": conn.pid, "name": conn.name, "text": text}, ensure_ascii=False)
        for c in room.conns.values():
            c.send_raw(frame)

    # ------------------------------------------------------------------------------------------
    # loops
    # ------------------------------------------------------------------------------------------
    async def _tick_loop(self):
        last = now()
        while True:
            await asyncio.sleep(self.tick_seconds)
            t = now()
            dt, last = t - last, t
            if not self.rooms:
                continue
            c0 = time.process_time()
            try:
                days = self.lcall("step", min(dt, 1.0))
                self.stats["days"] += int(days or 0)
            except LuaError:
                pass
            except Exception:
                log.exception("tick failed")
            cpu = time.process_time() - c0
            self.stats["ticks"] += 1
            self.stats["tick_cpu"] += cpu
            self.stats["tick_max"] = max(self.stats["tick_max"], cpu)

    async def _peers_loop(self):
        while True:
            await asyncio.sleep(self.peers_interval)
            for room in list(self.rooms.values()):
                if not room.pos_dirty or not room.conns:
                    continue
                room.pos_dirty = False
                lst = []
                for c in room.conns.values():
                    if c.pos is not None:
                        item = {"userId": c.pid, "name": c.name, "color": self.color_of(c.pid)}
                        item.update(c.pos)
                        lst.append(item)
                text = json.dumps({"t": "peers", "list": lst}, ensure_ascii=False, separators=(",", ":"))
                for c in room.conns.values():
                    c.send_raw(text)

    def boards(self):
        """LeaderboardService: top 10 by cash and by launched devices over all saved companies, with live values
        for the loaded ones."""
        rows = {r["id"]: r for r in self.store.board_rows()}
        for cid in self.rooms:
            m = lua_to_py(self.lua.call("boardEntry", cid))
            if m:
                rows[cid] = {"id": cid, "name": m["name"], "cash": m["cash"], "devices": m["devices"]}
                if m.get("liquidated"):
                    rows.pop(cid)

        def top(key):
            ordered = sorted(rows.values(), key=lambda r: (-(r[key] or 0), r["name"]))
            return [{"name": r["name"], "value": r[key], "companyId": r["id"]} for r in ordered[:10]]

        return {"money": top("cash"), "devices": top("devices")}

    def send_boards(self):
        if not any(r.conns for r in self.rooms.values()):
            return
        text = json.dumps(dict(t="boards", **self.boards()), ensure_ascii=False, separators=(",", ":"), allow_nan=False)
        for room in self.rooms.values():
            for c in room.conns.values():
                c.send_raw(text)

    async def _housekeeping_loop(self):
        last_minute = now()
        last_boards = now()
        last_stats = now()
        last_legacy = now()
        while True:
            await asyncio.sleep(self.housekeeping_seconds)
            t = now()
            try:
                self.flush_profiles()
                for room in list(self.rooms.values()):
                    if room.conns:
                        if t - room.last_save >= self.autosave_seconds:
                            self.save_room(room)
                    elif t - room.empty_since >= self.idle_unload_seconds:
                        self.unload_room(room)
                if t - last_boards >= self.boards_seconds:
                    last_boards = t
                    self.send_boards()
                if t - last_minute >= 60:
                    last_minute = t
                    self.lcall("minuteTick")
                if t - last_legacy >= 3600:
                    last_legacy = t
                    n = self.store.scrub_legacy_tokens()
                    if n:
                        log.info("scrubbed %d legacy plaintext device tokens", n)
                if t - last_stats >= self.stats_seconds:
                    last_stats = t
                    self.log_stats()
            except Exception:
                log.exception("housekeeping failed")

    def log_stats(self):
        s = self.stats
        avg = (s["tick_cpu"] / s["ticks"] * 1000) if s["ticks"] else 0.0
        per_day = (s["tick_cpu"] / s["days"] * 1000) if s["days"] else 0.0
        log.info("stats: %d companies loaded, %d players online, %d ticks avg %.2f ms max %.2f ms, "
                 "%d days simulated (%.3f ms CPU per company-day)",
                 len(self.rooms), len(self.players), s["ticks"], avg, s["tick_max"] * 1000, s["days"], per_day)
        self.stats = {"ticks": 0, "tick_cpu": 0.0, "tick_max": 0.0, "days": 0}

    # ------------------------------------------------------------------------------------------
    # start / stop
    # ------------------------------------------------------------------------------------------
    @staticmethod
    def _process_request(connection, request):
        path = request.path.split("?", 1)[0]
        if path in ("/health", "/healthz"):
            return connection.respond(200, "ok\n")
        if path not in ("/", "/ws"):
            return connection.respond(404, "not found\n")
        return None

    async def start(self, host="0.0.0.0", port=7350):
        self._server = await serve(self.handler, host, port, max_size=MAX_MESSAGE_BYTES, max_queue=64,
                                   process_request=self._process_request, ping_interval=20, ping_timeout=30)
        self.port = self._server.sockets[0].getsockname()[1] if self._server.sockets else port
        self._tasks = [asyncio.ensure_future(self._tick_loop()), asyncio.ensure_future(self._peers_loop()),
                       asyncio.ensure_future(self._housekeeping_loop())]
        p, c = self.store.counts()
        log.info("Silicon Overlord server listening on ws://%s:%d/ws (%d players, %d companies in %s)",
                 host, self.port, p, c, self.store.path)
        return self

    async def stop(self):
        self.stopping = True
        if self.stats["ticks"]:
            self.log_stats()
        for t in self._tasks:
            t.cancel()
        for room in list(self.rooms.values()):
            try:
                self.save_room(room)
            except Exception:
                log.exception("final save failed for %s", room.id)
        for pid in list(self.players):
            try:
                self.lua.call("disconnectPlayer", pid)
                self.dispatch()
            except Exception:
                pass
        self.flush_profiles()
        if self._server is not None:
            self._server.close()
        for conn in list(self.players.values()):
            try:
                await asyncio.wait_for(conn.ws.close(1001, "server shutdown"), 2)
            except Exception:
                pass
        if self._server is not None:
            try:
                await asyncio.wait_for(self._server.wait_closed(), 5)
            except Exception:
                pass
        self.store.close()
        self._kdf_pool.shutdown(wait=False)
        self._kdf_pool_slow.shutdown(wait=False)
        log.info("server stopped, all companies saved")


def _finite(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v)
