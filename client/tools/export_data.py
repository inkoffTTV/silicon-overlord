#!/usr/bin/env python3
"""Export the game data the Godot client needs from the shared Luau modules to JSON.

Same loading approach as /home/user/PhoneTycoon/tests/run_tests.py: a lupa Lua VM, Luau type annotations
stripped by tools/luau_strip.py, Roblox globals shimmed by tools/lua_shim.lua, and a Rojo-like module tree
(game.ReplicatedStorage.Shared -> shared-luau/).

Writes client/ui/data/:
  catalog.json        components (ComponentCatalog.list) + generationYear
  techtree.json       TechTree.list
  devicespecs.json    DeviceSpecs (list, subtypeSegment, categoryNeedsTech, subtypeNeedsTech)
  features.json       Features.list
  finishes.json       Finishes (finishes, accents, lights, logos, wallpapers, colours)
  balance.json        the few Balance tables the UI shows (research cost/days, time, price references)
  locale.json         Locale phrase tables from the Roblox client (en keyed dict + ru phrase table)
  goals.json          Goals.list (id, title, desc, badge, reward) — the 28 sequential goals (checks stay on the server)
  daily.json          DailyRewards (7-day gift cycle, streak bonus)
  (interior.json      0.5.0 catalogue + room geometry: client/tools/export_interior.py, read by the world and the UI)
  sample_interior.json 0.5.0: interior + hq.expansions + line processes of a furnished demo garage (merged into
                      sample_state by ui/lib/gdata.gd; tests and screenshots only)
  sample_state.json   a realistic CompanyState (created by CompanyFactory, a few weeks simulated,
                      one blueprint, one launched product) — used only by UI tests and screenshots.

Usage:  python3 client/tools/export_data.py [--roblox=/home/user/PhoneTycoon] [--only=goals,daily,balance,...]
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))  # SiliconOverlordOnline
sys.path.insert(0, os.path.join(ROOT, "tools"))
from luau_strip import strip  # noqa: E402
from lupa import LuaRuntime  # noqa: E402

ROBLOX = "/home/user/PhoneTycoon"
ONLY = set()
for a in sys.argv[1:]:
    if a.startswith("--roblox="):
        ROBLOX = a.split("=", 1)[1]
    if a.startswith("--only="):
        ONLY = set(a.split("=", 1)[1].split(","))
OUT = os.path.join(ROOT, "client", "ui", "data")


def tree_of(path):
    node = {"$path": path}
    for entry in sorted(os.listdir(path)):
        full = os.path.join(path, entry)
        if os.path.isdir(full):
            node[entry] = tree_of(full)
        elif entry.endswith(".luau"):
            node[entry[:-5]] = {"$path": full}
    return node


def make_runtime():
    shared = tree_of(os.path.join(ROOT, "shared-luau"))
    tree = {"ReplicatedStorage": {"Shared": shared}}
    # the Roblox client's Locale module (phrase tables) lives outside shared-luau
    locale_path = os.path.join(ROBLOX, "src", "client", "UI", "Lib", "Locale.luau")
    if os.path.exists(locale_path):
        tree["ClientLib"] = {"Locale": {"$path": locale_path}}
    L = LuaRuntime(unpack_returned_tuples=True)
    cache = {}

    def read_stripped(path):
        if path not in cache:
            src = open(path, encoding="utf-8").read()
            if path.endswith("Locale.luau"):
                # expose the module-local phrase table for export
                src = src.replace("\nreturn Locale", "\nLocale.__ru = ru\nreturn Locale")
            cache[path] = strip(src)
        return cache[path]

    L.globals()["__read_stripped"] = read_stripped
    L.globals()["__root"] = ROOT
    L.globals()["__tree"] = L.table_from(json.loads(json.dumps(tree)), recursive=True)
    L.execute(open(os.path.join(ROOT, "tools", "lua_shim.lua"), encoding="utf-8").read())
    # services the Locale module touches at load time
    L.execute("""
local svc = game.GetService
function game.GetService(self, name)
  if name == 'Players' then return { LocalPlayer = nil } end
  if name == 'LocalizationService' then return { RobloxLocaleId = 'en-us' } end
  return svc(self, name)
end
""")
    return L


def to_py(v, depth=0):
    """Lua value -> JSON-able python. Tables with 1..n keys become lists."""
    if depth > 40:
        return None
    t = type(v).__name__
    if t == "_LuaTable":
        keys = list(v.keys())
        if not keys:
            return {}
        if all(isinstance(k, int) for k in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
            return [to_py(v[k], depth + 1) for k in range(1, len(keys) + 1)]
        out = {}
        for k in keys:
            val = v[k]
            if type(val).__name__ == "_LuaFunction":
                continue
            out[str(k)] = to_py(val, depth + 1)
        return out
    if t == "_LuaFunction":
        return None
    if isinstance(v, bytes):
        return v.decode("utf-8", "replace")
    if isinstance(v, float) and v.is_integer() and abs(v) < 2**53:
        return int(v)
    return v


def to_py_list(t):
    out = []
    i = 1
    while t[i] is not None:
        item = {}
        for k in list(t[i].keys()):
            v = t[i][k]
            if type(v).__name__ == "_LuaTable":
                item[str(k)] = to_py(v)
            elif not callable(v):
                item[str(k)] = v
        out.append(item)
        i += 1
    return out


def dump(name, data):
    if ONLY and name.split(".")[0] not in ONLY:
        return
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
    print("wrote %s (%d KB)" % (os.path.relpath(path, ROOT), os.path.getsize(path) // 1024))


def main():
    L = make_runtime()
    req = L.eval("function(path) local n = game.ReplicatedStorage.Shared for part in string.gmatch(path, '[^.]+') do n = n[part] end return require(n) end")

    catalog = req("Data.ComponentCatalog")
    gy = to_py(catalog.generationYear)
    dump("catalog.json", {"list": to_py(catalog.list), "generationYear": gy if isinstance(gy, list) else [gy[str(i)] for i in range(1, 8)]})

    tech = req("Data.TechTree")
    dump("techtree.json", {"list": to_py(tech.list)})

    specs = req("Data.DeviceSpecs")
    dump("devicespecs.json", {
        "list": to_py(specs.list),
        "subtypeSegment": to_py(specs.subtypeSegment),
        "categoryNeedsTech": to_py(specs.categoryNeedsTech),
        "subtypeNeedsTech": to_py(specs.subtypeNeedsTech),
    })

    features = req("Data.Features")
    dump("features.json", {"list": to_py(features.list)})

    finishes = req("Data.Finishes")
    fin = {}
    for k in list(finishes.keys()):
        v = finishes[k]
        if type(v).__name__ == "_LuaTable" and not str(k).endswith("ById"):
            fin[str(k)] = to_py(v)
    dump("finishes.json", fin)

    balance = req("Config.Balance")
    bal = {}
    for key in ("Research", "Time", "Market", "Production", "Development", "Start", "Employees", "Story", "Challenges"):
        try:
            bal[key] = to_py(balance[key])
        except Exception:
            pass
    dump("balance.json", bal)

    goals = req("Data.Goals")
    glist = []
    for g in to_py_list(goals.list):
        glist.append({k: g.get(k) for k in ("id", "title", "desc", "badge", "reward")})
    dump("goals.json", {"list": glist})

    daily = req("Data.DailyRewards")
    dump("daily.json", {"days": to_py(daily.days), "streakBonus": to_py(daily.streakBonus), "secondsPerDay": to_py(daily.secondsPerDay)})

    # ---- 0.5.0 interior: client/ui/data/interior.json is written by client/tools/export_interior.py (shared with the
    # world); here only the furnished demo state for UI tests / screenshots
    if not ONLY or "sample_interior" in ONLY:
        dump("sample_interior.json", to_py(L.execute(SAMPLE_INTERIOR_LUA)))

    # ---- locale -------------------------------------------------------------------------
    try:
        Locale = L.eval("require(game.ClientLib.Locale)")
        dump("locale.json", {"dict": to_py(Locale.dict), "ru": to_py(Locale.__ru), "opNames": to_py(Locale.opNames)})
    except Exception as e:  # Roblox project missing: keep the old file
        print("locale export skipped:", e)

    # ---- sample state (tests & screenshots only) ----------------------------------------------
    if not ONLY or "sample_state" in ONLY:
        sample = L.execute(SAMPLE_LUA)
        dump("sample_state.json", to_py(sample))


SAMPLE_LUA = r"""
local S = game.ReplicatedStorage.Shared
local Factory = require(S.Domain.CompanyFactory)
local Sim = require(S.Domain.CompanySim)
local Actions = require(S.Domain.CompanyActions)
local DesignWizard = require(S.Domain.DesignWizard)
local Balance = require(S.Config.Balance)
local c = Factory.new({ id = "c_demo", name = "Nebula Labs", logo = { shape = "circle", colorA = "#4F8CFF", colorB = "#B15CFF" },
  mode = "cofounder", founderUserId = 1, founderName = "Alex", founderShare = 1, seed = 42, now = 0 })
-- a lab and some research
Actions.buildRoom(c, "ResearchLab")
local TechTree = require(S.Data.TechTree)
local function startSome(n)
  local started = 0
  for _, t in ipairs(TechTree.list) do
    if started < n and Actions.startResearch(c, 1, t.id) then started = started + 1 end
  end
end
startSome(3)
for _ = 1, 20 do Sim.tickDay(c) end
-- a blueprint, filled with the cheapest parts, published and launched
local ok, r = Actions.createBlueprint(c, 1, "Nebula One", "MidrangePhone")
local bp = c.blueprints[r.id]
local spec = require(S.Data.DeviceSpecs).bySubtype[bp.subtype]
local all = {}
for _, s in ipairs(spec.slots) do all[#all + 1] = s.slot end
bp.slots = DesignWizard.quickPick(c, bp, all, "cheap")
bp.options.bodyColorHex = "#2B3A67"
bp.priceUSD = 349
Balance.Development.daysBase = 0
local okP, pr = Actions.publishBlueprint(c, 1, bp.id)
if okP then
  for _ = 1, 3 do Sim.tickDay(c) end
  local line = c.production.lines[1]
  if line then Actions.queueProduction(c, pr.productId, line.id, 200) end
  for _ = 1, 25 do Sim.tickDay(c) end
  local p = c.products[pr.productId]
  if p.inventory <= 0 then p.inventory = 150 end
  Actions.launchProduct(c, pr.productId, nil)
  for _ = 1, 30 do Sim.tickDay(c) end
end
startSome(3)
for _ = 1, 6 do Sim.tickDay(c) end
c.research.points = math.max(c.research.points or 0, 140)
-- a third device in development (production screen: progress, bugs, quality)
Balance.Development.daysBase = 30
local ok3, r3 = Actions.createBlueprint(c, 1, "Nebula Mini", "BudgetPhone")
if ok3 then
  local bp3 = c.blueprints[r3.id]
  local spec3 = require(S.Data.DeviceSpecs).bySubtype[bp3.subtype]
  local all3 = {}
  for _, s in ipairs(spec3.slots) do all3[#all3 + 1] = s.slot end
  bp3.slots = DesignWizard.quickPick(c, bp3, all3, "cheap")
  bp3.options.bodyColorHex = "#C8324B"
  bp3.priceUSD = 199
  c.finance.cash = math.max(c.finance.cash, 2000000)
  Actions.publishBlueprint(c, 1, bp3.id)
  for _ = 1, 9 do Sim.tickDay(c) end
end
-- a second, unpublished draft for the designer
local ok2, r2 = Actions.createBlueprint(c, 1, "Nebula Two", "PremiumFlagship")
-- screenshots look better with a healthy bank account
c.finance.cash = 1846500
c.audit = {}
return c
"""

SAMPLE_INTERIOR_LUA = r"""
local S = game.ReplicatedStorage.Shared
local Factory = require(S.Domain.CompanyFactory)
local Interior = require(S.Domain.Interior)
local c = Factory.new({ id = "c_demo", name = "Nebula Labs", logo = { shape = "circle", colorA = "#4F8CFF", colorB = "#B15CFF" },
  mode = "cofounder", founderUserId = 1, founderName = "Alex", founderShare = 1, seed = 42, now = 0 })
c.finance.cash = 5000000
c.time.elapsedDays = 93
c.hq.rooms.AssemblyLine = { level = 1, builtDay = 0 }
Interior.buildExpansion(c, "annex")
local function put(room, def, x, z, rot, color)
  local ok, r = Interior.place(c, { room = room, def = def, x = x, z = z, rot = rot or 0, color = color })
  if not ok then print("sample_interior: " .. room .. " " .. def .. ": " .. tostring(r)) end
end
c.time.elapsedDays = 30
put("garage", "plant_monstera", 2.25, -0.5)
put("garage", "plant_cactus", -1.5, 2.0)
c.time.elapsedDays = 93
put("garage", "decor_rug_braided", 1.5, 0.25)
put("garage", "seat_beanbag", -2.75, 1.75)
put("garage", "light_bulb_string", 1.0, 1.0, 0)
put("garage", "decor_poster_launch", -2.5, -3.45, 0)
put("garage", "decor_wall_clock", 2.0, -3.45, 0)
put("garage", "store_wire_shelf", -2.5, 0.25, 0)
put("garage", "decor_coffee_machine", 2.0, -2.5)
Interior.paint(c, { room = "garage", surface = "wall", mat = "brick", color = "#6E5A4E" })
Interior.light(c, { room = "garage", preset = "warm" })
Interior.theme(c, { room = "annex", theme = "lab" })
put("annex", "lab_bench", -1.5, -2.0)
put("annex", "desk_white", 1.5, -2.0)
put("annex", "plant_fig", 2.5, 2.0)
put("annex", "light_led_panel", 0.0, 0.0)
Interior.refresh(c)
for _, l in ipairs(c.production.lines) do
  if l.kind == "Assembly" then l.process = l.process or "hand" end
end
return { interior = c.interior, expansions = c.hq.expansions }
"""

if __name__ == "__main__":
    main()
