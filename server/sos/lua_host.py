"""The Lua VM that runs the game rules.

Runtime strategy: ONE shared LuaRuntime for all companies (not one VM per session).
  * It mirrors Roblox, where one server VM hosts several companies: the ported services (CompanyService,
    GovernanceService, ActionRouter, MissionService, LegacyService) keep their module-level registries and
    already isolate companies by session (separate state tables, per-session pcall in the clock).
  * The rules are ~16k lines of Luau; one VM loads them once (~0.15 s, a few MB). A VM per session would
    multiply load time and memory by the number of companies for no gain: the asyncio server is
    single-threaded, so separate VMs would not run in parallel anyway.
  * A simulated day costs ~0.2 ms, so 50 companies at speed 8 (4 days/s each) need ~40 ms of CPU per second.
  * Risk: a Lua error in the middle of an action can leave that company's state half-updated (same as on
    Roblox); it cannot corrupt other companies. Every call into Lua is wrapped (see LuaHost.call).

Modules are loaded exactly like PhoneTycoon/tests/run_tests.py: Luau type annotations are stripped by
tools/luau_strip.py and tools/lua_shim.lua provides the Roblox globals and a `game` tree in which
ReplicatedStorage.Shared = shared-luau/ and ServerScriptService.Server = server/lua/.
"""
import json
import logging
import os
import secrets
import sys

from lupa import LuaRuntime, LuaError  # noqa: F401  (LuaError re-exported)

from .convert import lua_to_py, py_to_lua

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.dirname(HERE)
ROOT = os.path.dirname(SERVER)
sys.path.insert(0, os.path.join(ROOT, "tools"))
from luau_strip import strip  # noqa: E402

log = logging.getLogger("lua")


def _tree_of(path):
    node = {"$path": path}
    for entry in sorted(os.listdir(path)):
        full = os.path.join(path, entry)
        if os.path.isdir(full):
            node[entry] = _tree_of(full)
        elif entry.endswith(".luau"):
            node[entry[:-5]] = {"$path": full}
    return node


PRELUDE = r"""
-- Roblox services the ported server modules touch at load time
local baseGetService = game.GetService
local http = {
  GenerateGUID = function(_, _wrap) return __py_guid() end,
  JSONEncode = function(_, v) return tostring(v) end,
}
local playersStub = { GetPlayers = function() return {} end, GetPlayerByUserId = function() return nil end }
function game.GetService(self, name)
  if name == "HttpService" then return http end
  if name == "Players" then return playersStub end
  return baseGetService(self, name)
end
warn = function(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
  __py_log("warning", table.concat(parts, " "))
end
print = function(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
  __py_log("info", table.concat(parts, " "))
end
"""


class LuaHost:
    """Owns the Lua VM and exposes the Host.luau entry points with Python values."""

    def __init__(self, load_profile=None):
        self.L = LuaRuntime(unpack_returned_tuples=True)
        self._cache = {}
        self._load_profile = load_profile or (lambda uid: None)
        g = self.L.globals()
        g["__read_stripped"] = self._read_stripped
        g["__root"] = ROOT
        tree = {
            "ReplicatedStorage": {"Shared": _tree_of(os.path.join(ROOT, "shared-luau"))},
            "ServerScriptService": {"Server": _tree_of(os.path.join(SERVER, "lua"))},
        }
        g["__tree"] = self.L.table_from(json.loads(json.dumps(tree)), recursive=True)
        with open(os.path.join(ROOT, "tools", "lua_shim.lua"), encoding="utf-8") as f:
            self.L.execute(f.read())
        g["__py_guid"] = lambda: secrets.token_hex(16).upper()
        g["__py_log"] = self._lua_log
        g["__py_load_profile"] = self._py_load_profile
        self.L.execute(PRELUDE)
        self.host = self.L.execute('return require(game:GetService("ServerScriptService").Server.Host)')
        self.host.start()
        self.action_names = set(lua_to_py(self.host.actionNames()))

    # ---- loader / callbacks ------------------------------------------------------------------
    def _read_stripped(self, path):
        src = self._cache.get(path)
        if src is None:
            with open(path, encoding="utf-8") as f:
                src = strip(f.read())
            self._cache[path] = src
        return src

    @staticmethod
    def _lua_log(level, msg):
        getattr(log, level if level in ("info", "warning", "error") else "info")(msg)

    def _py_load_profile(self, user_id):
        data = self._load_profile(int(user_id))
        if data is None:
            return None
        return py_to_lua(self.L, data)

    # ---- helpers -------------------------------------------------------------------------------
    def to_lua(self, obj):
        return py_to_lua(self.L, obj)

    @staticmethod
    def to_py(v):
        return lua_to_py(v)

    def call(self, name, *args):
        """Calls Host.<name>(...). Raises LuaError on a Lua error (callers decide how to report it)."""
        return getattr(self.host, name)(*args)

    def drain(self):
        """Returns the outbox events as Python dicts (conversion happens now, while state is consistent)."""
        events = self.host.drain()
        out = []
        for i in range(1, len(events) + 1):
            ev = events[i]
            t = ev["t"]
            if t == "sections":
                data = {}
                for k, v in ev["data"].items():
                    data[str(k)] = lua_to_py(v)
                cleared = ev["cleared"]
                if cleared is not None:
                    for j in range(1, len(cleared) + 1):
                        data[str(cleared[j])] = None
                out.append({"t": t, "sid": ev["sid"], "data": data})
            elif t == "notify":
                out.append({"t": t, "sid": ev["sid"], "note": lua_to_py(ev["note"]), "userId": ev["userId"]})
            elif t == "profile":
                out.append({"t": t, "userId": int(ev["userId"]), "profile": lua_to_py(ev["profile"]),
                            "save": bool(ev["save"]), "send": bool(ev["send"])})
            elif t == "snapshot":
                out.append({"t": t, "sid": ev["sid"], "userId": int(ev["userId"])})
            elif t == "left":
                out.append({"t": t, "sid": ev["sid"], "userId": int(ev["userId"]), "reason": ev["reason"],
                            "points": ev["points"]})
            elif t == "members":
                out.append({"t": t, "sid": ev["sid"]})
        return out

    def state_py(self, company_id):
        st = self.host.state(company_id)
        return None if st is None else lua_to_py(st)
