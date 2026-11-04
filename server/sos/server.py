"""Authoritative game server: asyncio + websockets, one shared Lua VM (see lua_host.py), SQLite saves.

Wire protocol: docs/PROTOCOL.md. Actions: docs/ACTIONS.md.
Everything runs on one asyncio thread. Calls into Lua are synchronous; after every call the Lua outbox is
drained and turned into frames (sections / notify / snapshot / profile / left / members) immediately, so
state is never observed half-way. Each connection has an outgoing queue + writer task (ordering, back-pressure).
"""
import asyncio
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

log = logging.getLogger("server")

PROTOCOL_VERSION = 1
MAX_MESSAGE_BYTES = 64 * 1024
CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"   # room codes (PROTOCOL.md)
INVITE_ALPHABET = CODE_ALPHABET + "L"                  # GovernanceService.makeCode (personal invites) also uses L
SPEEDS = (0, 1, 2, 4, 8)
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

    def send(self, obj):
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
                    c.send({"t": "snapshot", "state": self.lua.state_py(ev["sid"])})
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
        pid = player["id"]
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
        self.players[pid] = conn
        conn.send({"t": "welcome", "playerId": pid, "token": player["token"], "name": name,
                   "lastCompany": player.get("last_company")})
        self.lcall("connectPlayer", pid, name, self.lua.to_lua(self.store.load_profile(pid)))
        log.info("player %s (%s) connected from %s", pid, name, conn.addr)

    def _leave_current(self, conn):
        if conn.room is not None:
            self.detach(conn, notify=False)

    def on_create(self, conn, msg):
        company = msg.get("company")
        if not isinstance(company, dict):
            conn.send({"t": "error", "message": "create needs company:{name, colorA, colorB, mode}"})
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
        log.info("player %s created company %s %s (%s)", conn.pid, cid, format_code(code), mode)

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
        log.info("server stopped, all companies saved")


def _finite(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v)
