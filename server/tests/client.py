"""Tiny protocol client used by the tests and the soak: keeps a replica of the company state
(snapshot + sections, exactly what a Godot client must do) and matches act ids to res frames."""
import asyncio
import json

from websockets.asyncio.client import connect

PHONE_SLOTS = {"SoC": "soc_arm_g1_plus", "RAM": "ram_lp4x_g1", "Storage": "ufs_g1", "Display": "disp_phone_lcd_g1",
               "Camera": "cam_dual_g1", "Battery": "bat_phone_l_g1", "Charger": "charger_25",
               "Cooling": "cool_phone_graphite_g1", "Chassis": "chassis_phone_aluminum", "OS": "os_mobile_g1"}


class Client:
    def __init__(self, url, name="Tester", local_ip=None):
        self.url = url
        self.local_ip = local_ip  # e.g. "127.0.0.9": connect from another loopback address (per-IP limit tests)
        self.name = name
        self.ws = None
        self.state = None
        self.frames = []          # every frame received (for assertions)
        self.welcome = None
        self.joined = None
        self.members = None
        self.profile = None
        self.peers = None
        self.chat = []
        self.notes = []
        self.left = None
        self.errors = []
        self.sections_count = 0
        self._next_id = 1
        self._pending = {}
        self._reader = None
        self._event = asyncio.Event()
        self.closed = False

    async def connect(self):
        kw = {"local_addr": (self.local_ip, 0)} if self.local_ip else {}
        self.ws = await connect(self.url, max_size=None, **kw)
        self._reader = asyncio.ensure_future(self._read())
        return self

    async def _read(self):
        try:
            async for raw in self.ws:
                f = json.loads(raw)
                self.frames.append(f)
                self._handle(f)
                self._event.set()
        except Exception:
            pass
        finally:
            self.closed = True
            self._event.set()

    def _handle(self, f):
        t = f["t"]
        if t == "welcome":
            self.welcome = f
        elif t == "joined":
            self.joined = f
            self.members = f["members"]
            self.left = None
        elif t == "snapshot":
            self.state = f["state"]
        elif t == "sections":
            self.sections_count += 1
            if self.state is not None:
                for k, v in f["data"].items():
                    if v is None:
                        self.state.pop(k, None)
                    else:
                        self.state[k] = v
        elif t == "res":
            fut = self._pending.pop(f["id"], None)
            if fut and not fut.done():
                fut.set_result(f)
        elif t == "members":
            self.members = f["list"]
        elif t == "profile":
            self.profile = f["profile"]
        elif t == "peers":
            self.peers = f["list"]
        elif t == "chat":
            self.chat.append(f)
        elif t == "notify":
            self.notes.append(f)
        elif t == "left":
            self.left = f
        elif t == "error":
            self.errors.append(f["message"])

    async def send(self, obj):
        await self.ws.send(json.dumps(obj))

    async def wait_for(self, pred, timeout=10.0, what="condition"):
        loop = asyncio.get_running_loop()
        end = loop.time() + timeout
        while True:
            if pred():
                return True
            left = end - loop.time()
            if left <= 0 or self.closed:
                raise AssertionError("timeout waiting for " + what)
            self._event.clear()
            try:
                await asyncio.wait_for(self._event.wait(), min(left, 0.5))
            except asyncio.TimeoutError:
                pass

    async def wait_frame(self, t, timeout=5.0, after=0):
        await self.wait_for(lambda: any(f["t"] == t for f in self.frames[after:]), timeout, "frame " + t)
        return [f for f in self.frames[after:] if f["t"] == t][-1]

    async def hello(self, token=None):
        n = len(self.frames)
        msg = {"t": "hello", "v": 1, "name": self.name}
        if token:
            msg["token"] = token
        await self.send(msg)
        return await self.wait_frame("welcome", after=n)

    async def create(self, name, mode="solo", story=None):
        n = len(self.frames)
        company = {"name": name, "colorA": "#2F80ED", "colorB": "#56CCF2", "mode": mode}
        if story is not None:
            company["storyMode"] = story
        await self.send({"t": "create", "company": company})
        await self.wait_for(lambda: any(f["t"] in ("joined", "error") for f in self.frames[n:]), 5, "joined")
        await self.wait_frame("snapshot", after=n)
        return self.joined

    async def join(self, code, expect_ok=True):
        n = len(self.frames)
        await self.send({"t": "join", "code": code})
        await self.wait_for(lambda: any(f["t"] in ("joined", "error") for f in self.frames[n:]), 5, "join reply")
        got = [f for f in self.frames[n:] if f["t"] in ("joined", "error")][0]
        if got["t"] == "joined":
            await self.wait_frame("snapshot", after=n)
        return got

    async def resume(self):
        n = len(self.frames)
        await self.send({"t": "resume"})
        await self.wait_for(lambda: any(f["t"] in ("joined", "error") for f in self.frames[n:]), 5, "resume reply")
        got = [f for f in self.frames[n:] if f["t"] in ("joined", "error")][0]
        if got["t"] == "joined":
            await self.wait_frame("snapshot", after=n)
        return got

    async def act(self, action, args=None, timeout=5.0):
        aid = self._next_id
        self._next_id += 1
        fut = asyncio.get_running_loop().create_future()
        self._pending[aid] = fut
        await self.send({"t": "act", "id": aid, "action": action, "args": args or {}})
        return await asyncio.wait_for(fut, timeout)

    async def speed(self, s):
        await self.send({"t": "speed", "speed": s})
        await self.wait_for(lambda: self.state and self.state["time"]["speed"] == s, 5, "speed %s" % s)

    async def close(self):
        if self.ws:
            await self.ws.close()
        if self._reader:
            try:
                await asyncio.wait_for(self._reader, 2)
            except Exception:
                pass
