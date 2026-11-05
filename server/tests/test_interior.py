"""0.5.0: interior editor, garage expansions, production processes (docs/ACTIONS.md "Interior", "Expansions",
"Production processes"). Rules tests run in the server's Lua VM; E2E tests use a real server + websocket clients."""
import asyncio
import shutil
import tempfile
import unittest

from client import Client
from sos.lua_host import LuaHost
from sos.server import GameServer

PRELUDE = r"""
local Shared = game:GetService("ReplicatedStorage").Shared
local CompanyFactory = require(Shared.Domain.CompanyFactory)
local CompanySim = require(Shared.Domain.CompanySim)
local CompanyActions = require(Shared.Domain.CompanyActions)
local ProductionRules = require(Shared.Domain.ProductionRules)
local Interior = require(Shared.Domain.Interior)
local Catalog = require(Shared.Data.Interior)
local Geo = require(Shared.Data.RoomGeometry)
local Shipping = require(Shared.Domain.Shipping)
local Office = require(Shared.Domain.Office)
local Balance = require(Shared.Config.Balance)
local function newCompany(cash)
  local c = CompanyFactory.new({ id = "t1", name = "Test", logo = { shape = "hex", colorA = "#fff", colorB = "#000" },
    mode = "solo", founderUserId = 1, founderName = "T", founderShare = 100, seed = 42, now = 0 })
  c.finance.cash = cash or 5000000
  return c
end
local function place(c, room, def, x, z, rot, extra)
  local a = { room = room, def = def, x = x, z = z, rot = rot or 0 }
  for k, v in pairs(extra or {}) do a[k] = v end
  local ok, d = CompanyActions.interiorPlace(c, a)
  return { ok = ok, d = d }
end
"""


class InteriorRules(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.lua = LuaHost()

    def run_lua(self, body):
        return self.lua.to_py(self.lua.L.execute(PRELUDE + body))

    def test_catalog_and_geometry_data(self):
        r = self.run_lua(r"""
          local bad = {}
          local cats = {}
          for _, c in ipairs(Catalog.categories) do cats[c.id] = true end
          for _, d in ipairs(Catalog.list) do
            if not cats[d.cat] or d.w <= 0 or d.d <= 0 or d.h <= 0 or d.price < 0 then bad[#bad + 1] = d.id end
            for _, t in ipairs(d.themes) do if not Catalog.themeById[t] then bad[#bad + 1] = d.id .. ":" .. t end end
          end
          for old, new in pairs(Catalog.legacyMap) do
            if not Catalog.byId[new] then bad[#bad + 1] = "map:" .. old end
          end
          local living = {}
          for _, d in ipairs(Catalog.list) do if d.living then living[d.living] = true end end
          return { n = #Catalog.list, bad = bad, themes = #Catalog.themes, rooms = #Geo.list, living = living,
                   office7 = Geo.room("office", 7).bounds.x1 }
        """)
        self.assertGreaterEqual(r["n"], 60)
        self.assertEqual(r["bad"] or [], [])
        self.assertEqual(r["themes"], 5)
        self.assertEqual(r["rooms"], 7)
        for k in ("poster", "trophies", "history", "neon_name", "aquarium", "plant"):
            self.assertIn(k, r["living"])
        self.assertEqual(r["office7"], 15.0)

    def test_place_move_remove_paint_theme_light(self):
        r = self.run_lua(r"""
          local c = newCompany(100000)
          local cash0 = c.finance.cash
          local p = place(c, "garage", "plant_monstera", -2.5, -1.5, 0)
          local id = p.d.item.id
          local afterBuy = c.finance.cash
          local okm, m = CompanyActions.interiorMove(c, { room = "garage", id = id, x = -2.2, z = -0.45, rot = 47 })
          local okr, rr = CompanyActions.interiorRemove(c, { room = "garage", id = id })
          local okp, pp = CompanyActions.interiorPaint(c, { room = "garage", surface = "wall", mat = "brick", color = "#aa3300" })
          local badMat = { CompanyActions.interiorPaint(c, { room = "garage", surface = "wall", mat = "carpet", color = "#aa3300" }) }
          local badColor = { CompanyActions.interiorPaint(c, { room = "garage", surface = "floor", mat = "tile", color = "red" }) }
          local okt, tt = CompanyActions.interiorTheme(c, { room = "garage", theme = "wood" })
          local okl, ll = CompanyActions.interiorLight(c, { room = "garage", preset = "neon" })
          local badTheme = { CompanyActions.interiorTheme(c, { room = "garage", theme = "vaporwave" }) }
          return { p = p, cash0 = cash0, afterBuy = afterBuy, okm = okm, m = m, okr = okr, rr = rr, cash = c.finance.cash,
                   okp = okp, pp = pp, badMat = badMat, badColor = badColor, okt = okt, tt = tt, okl = okl, badTheme = badTheme,
                   room = c.interior.rooms.garage }
        """)
        self.assertTrue(r["p"]["ok"], r["p"])
        self.assertEqual(r["cash0"] - r["afterBuy"], 260)
        self.assertTrue(r["okm"], r["m"])
        self.assertEqual((r["m"]["item"]["x"], r["m"]["item"]["z"], r["m"]["item"]["rot"]), (-2.25, -0.5, 45))  # snapped
        self.assertTrue(r["okr"])
        self.assertEqual(r["rr"]["refund"], 130)                                   # 50 %
        self.assertTrue(r["okp"])
        self.assertEqual(r["pp"]["surface"], {"mat": "brick", "color": "#AA3300"})
        self.assertEqual(r["badMat"], [False, "That material does not go on this surface"])
        self.assertEqual(r["badColor"], [False, "Pick a colour"])
        self.assertTrue(r["okt"])
        self.assertEqual(r["tt"]["cost"], 1800)                                    # plank wall + plank floor
        self.assertEqual(r["room"]["theme"], "wood")
        self.assertEqual(r["room"]["light"], "neon")                               # light set after the theme
        self.assertEqual(r["room"]["surfaces"]["floor"]["mat"], "plank")
        self.assertEqual(r["badTheme"], [False, "Unknown theme"])
        self.assertEqual(r["room"].get("items") or [], [])

    def test_validation_rejects(self):
        r = self.run_lua(r"""
          local c = newCompany()
          local out = {}
          out.first = place(c, "garage", "store_wire_shelf", -2.5, -2.0, 0)
          out.overlap = place(c, "garage", "store_wire_shelf", -2.75, -1.75, 0)
          out.outside = place(c, "garage", "store_wire_shelf", 3.9, 0.5, 0)
          out.door = place(c, "garage", "plant_cactus", 2.85, -3.2, 0)
          out.ramp = place(c, "garage", "plant_cactus", -1.5, 3.0, 0)
          out.fixture = place(c, "garage", "plant_cactus", -3.5, -0.8, 0)
          out.rugOverFixture = place(c, "garage", "decor_rug_braided", 2.0, 1.75, 0)
          out.wallFloating = place(c, "garage", "decor_wall_clock", -2.0, 0.0, 0)
          out.wallOk = place(c, "garage", "decor_wall_clock", -2.0, -3.25, 0, { y = 2.0 })
          out.wallTooHigh = place(c, "garage", "decor_framed_print", 0.0, -3.4, 0, { y = 2.9 })
          out.loft = place(c, "loft", "plant_cactus", 3.0, 2.5, 0)
          out.annex = place(c, "annex", "plant_cactus", 0, 0, 0)
          out.office = place(c, "office", "plant_cactus", 0, 0, 0)
          out.room = place(c, "attic", "plant_cactus", 0, 0, 0)
          out.def = place(c, "garage", "desk_gold_toilet", 0, 0, 0)
          out.minHQ = place(c, "garage", "decor_pinball", -2.5, -1.5, 0)
          out.role = place(c, "garage", "lab_fume_hood", -2.5, -1.75, 0)
          out.nan = { CompanyActions.interiorPlace(c, { room = "garage", def = "plant_cactus", x = 0 / 0, z = 0 }) }
          out.str = { CompanyActions.interiorPlace(c, { room = "garage", def = "plant_cactus", x = "a", z = 0 }) }
          out.max1 = place(c, "garage", "decor_coffee_machine", -2.5, -0.5, 0)
          out.max2 = place(c, "garage", "decor_coffee_machine", -2.0, 1.75, 0)
          c.finance.cash = 10; c.finance.creditLine = 0; c.finance.debt = 0
          out.cash = place(c, "garage", "decor_aquarium", -3.0, 1.75, 0)
          out.unknownId = { CompanyActions.interiorRemove(c, { room = "garage", id = "i999" }) }
          return out
        """)
        self.assertTrue(r["first"]["ok"], r["first"])
        expect = {
            "overlap": "Overlaps another item", "outside": "Outside the room", "door": "Blocked: doorway",
            "ramp": "Blocked: van ramp", "fixture": "Blocked: something built in", "wallFloating": "Wall items must touch a wall",
            "wallTooHigh": "Too tall for this room", "loft": "That room is not built yet", "annex": "That room is not built yet",
            "office": "That room is not part of this HQ", "room": "Unknown room", "def": "Unknown item",
            "minHQ": "Needs HQ level 2", "role": "That does not belong in this room", "max2": "Only 1 of these per room",
            "cash": "Not enough cash ($5200)",
        }
        for k, msg in expect.items():
            self.assertEqual((r[k]["ok"], r[k]["d"]), (False, msg), k)
        self.assertTrue(r["rugOverFixture"]["ok"], r["rugOverFixture"])
        self.assertTrue(r["wallOk"]["ok"], r["wallOk"])
        self.assertTrue(r["max1"]["ok"], r["max1"])
        self.assertEqual(r["nan"], [False, "Bad position"])
        self.assertEqual(r["str"], [False, "Bad position"])
        self.assertEqual(r["unknownId"], [False, "Unknown item id"])

    def test_room_item_cap(self):
        r = self.run_lua(r"""
          local c = newCompany()
          local geo = Geo.room("garage", 1)
          local placed, last = 0, nil
          for i = 1, 60 do
            local x, z = Interior.autoSpot(c, geo, Catalog.byId.plant_cactus)
            if not x then break end
            last = place(c, "garage", "plant_cactus", x, z, 0)
            if last.ok then placed = placed + 1 else break end
          end
          return { placed = placed, last = last, max = geo.maxItems }
        """)
        self.assertEqual(r["placed"], r["max"])
        self.assertEqual(r["last"]["d"], "The room is full (40 items)")

    def test_comfort_effects_capped_and_staff_from_seats(self):
        r = self.run_lua(r"""
          local c = newCompany(1e9)
          c.hq.level = 3
          local cap0 = CompanySim.staffCap(c)
          local geo = Geo.room("office", 3)
          local function fill(def, n)
            for i = 1, n do
              local x, z, rot = Interior.autoSpot(c, geo, Catalog.byId[def])
              if x then place(c, "office", def, x, z, rot) end
            end
          end
          fill("desk_pod6", 6)
          fill("lab_esd_bench", 3)
          fill("prod_xray_inspector", 1)
          fill("prod_qc_light_table", 4)
          fill("decor_robot_mascot", 1)
          fill("decor_aquarium", 1)
          fill("decor_coffee_machine", 1)
          fill("decor_arcade", 2)
          fill("plant_indoor_tree", 6)
          fill("light_floor_arc", 8)
          fill("decor_demo_table", 4)
          CompanyActions.interiorTheme(c, { room = "office", theme = "scandi" })
          c.time.elapsedDays = 400 -- plants fully grown
          Interior.refresh(c)
          local s = c.interior.summary
          return { s = s, caps = Balance.Interior.caps, cap0 = cap0, cap1 = CompanySim.staffCap(c), room = c.interior.rooms.office,
                   bonusMax = Balance.Interior.staffBonusMax[3], slots = Interior.extraResearchSlots(c) }
        """)
        s, caps = r["s"], r["caps"]
        e = s["effects"]
        self.assertGreater(r["room"]["comfort"], 40)
        self.assertLessEqual(r["room"]["comfort"], 100)
        for k in ("morale", "research", "defects", "design", "brand"):
            self.assertGreater(e[k], 0, k)
            self.assertLessEqual(e[k], caps[k] + 1e-9, k)
        self.assertGreaterEqual(s["seats"], 30)
        self.assertEqual(r["cap1"] - r["cap0"], min(r["bonusMax"], s["seats"] // 2))
        self.assertEqual(r["slots"], 1)  # lab benches: capped at +1

    def test_effects_reach_the_sim(self):
        r = self.run_lua(r"""
          local c = newCompany()
          local base = { def = 0.1 }
          c.interior.summary.effects.defects = 0.15
          local line = c.production.lines[1]
          local cap1 = ProductionRules.effectiveCapacity(line, 0, 1, 1e9, 1)
          line.process = "robotic"
          local cap2 = ProductionRules.effectiveCapacity(line, 0, 1, 1e9, 1)
          local e1 = ProductionRules.energyCost(100, line, 1)
          line.process = "hand"
          local e0 = ProductionRules.energyCost(100, line, 1)
          -- workers: robotic lines need fewer hands
          line.process = "hand"
          local w1 = ProductionRules.effectiveCapacity(line, 0, 1, 500, 1)
          line.process = "robotic"
          local w2 = ProductionRules.effectiveCapacity(line, 0, 1, 500, 1)
          return { cap1 = cap1, cap2 = cap2, e1 = e1, e0 = e0, w1 = w1, w2 = w2,
                   defectMult = ProductionRules.processDefectMult(line), eff = Interior.effect(c, "defects") }
        """)
        self.assertAlmostEqual(r["cap2"] / r["cap1"], 1.75, delta=0.01)
        self.assertAlmostEqual(r["e1"] / r["e0"], 1.5, delta=0.001)
        self.assertGreater(r["w2"], r["w1"])
        self.assertEqual(r["defectMult"], 0.7)
        self.assertEqual(r["eff"], 0.15)

    def test_expansions_at_hq1(self):
        r = self.run_lua(r"""
          local c = newCompany(2000000)
          local out = {}
          out.qc0 = CompanySim.roomLevel(c, "QualityControl")
          out.slots0 = Interior.extraResearchSlots(c)
          out.annex = { CompanyActions.buildExpansion(c, "annex") }
          out.annexRoom = place(c, "annex", "lab_bench", 0, 0, 0)
          out.annex2 = { CompanyActions.buildExpansion(c, "annex") }
          out.annex3 = { CompanyActions.buildExpansion(c, "annex") }
          out.annex4 = { CompanyActions.buildExpansion(c, "annex") }
          out.slots = Interior.extraResearchSlots(c)
          out.shedViaRoom = { CompanyActions.buildRoom(c, "QualityControl") }
          out.qc = CompanySim.roomLevel(c, "QualityControl")
          out.showroom = { CompanyActions.buildExpansion(c, "showroom") }
          out.brand = CompanySim.roomLevel(c, "Showroom")
          out.crates0 = Shipping.maxOpen(c)
          out.basement = { CompanyActions.buildExpansion(c, "basement") }
          out.crates = Shipping.maxOpen(c)
          out.server = CompanySim.roomLevel(c, "ServerRoom")
          out.loft = { CompanyActions.buildExpansion(c, "loft") }
          out.loftRoom = place(c, "loft", "plant_cactus", 3.0, 2.5, 0)
          out.bad = { CompanyActions.buildExpansion(c, "moon_base") }
          local _, cat = CompanyActions.expansionCatalog(c)
          out.cat = cat
          c.hq.level = 2
          out.hq2 = { CompanyActions.buildExpansion(c, "shed") }
          out.qcKept = CompanySim.roomLevel(c, "QualityControl")
          out.garageGone = place(c, "garage", "plant_cactus", -2.5, 0.5, 0)
          return out
        """)
        self.assertEqual(r["qc0"], 0)
        self.assertEqual(r["slots0"], 0)
        self.assertEqual(r["annex"], [True, {"id": "annex", "level": 1, "cost": 90000}])
        self.assertTrue(r["annexRoom"]["ok"], r["annexRoom"])
        self.assertEqual(r["annex2"][1]["cost"], 162000)
        self.assertEqual(r["annex3"][1]["level"], 3)
        self.assertEqual(r["annex4"], [False, "Expansion at max level"])
        self.assertEqual(r["slots"], 3)  # annex level 3 (+2) + lab bench (+1)
        self.assertTrue(r["shedViaRoom"][0], r["shedViaRoom"])
        self.assertEqual((r["shedViaRoom"][1]["expansion"], r["shedViaRoom"][1]["cost"]), ("shed", 70000))
        self.assertEqual(r["qc"], 1)
        self.assertEqual(r["brand"], 1)
        self.assertEqual((r["crates0"], r["crates"]), (20, 60))
        self.assertEqual(r["server"], 1)
        self.assertTrue(r["loft"][0], r["loft"])
        self.assertEqual(r["loft"][1]["id"], "loft")
        self.assertTrue(r["loftRoom"]["ok"], r["loftRoom"])
        self.assertEqual(r["bad"], [False, "Unknown expansion"])
        self.assertEqual(r["cat"]["expansions"]["annex"]["level"], 3)
        self.assertFalse(r["cat"]["expansions"]["annex"]["canBuild"])
        self.assertEqual(r["cat"]["expansions"]["shed"]["nextCost"], 126000)
        self.assertEqual(r["hq2"], [False, "Expansions are for the garage. Build rooms in the office."])
        self.assertEqual(r["qcKept"], 1)
        self.assertEqual(r["garageGone"]["d"], "That room is not part of this HQ")

    def test_line_process_switch(self):
        r = self.run_lua(r"""
          local c = newCompany(5000000)
          c.time.elapsedDays = 10
          local out = {}
          out.p0 = c.production.lines[1].process
          out.gate = { CompanyActions.setLineProcess(c, "line_1", "robotic") }
          out.same = { CompanyActions.setLineProcess(c, "line_1", "hand") }
          out.unknown = { CompanyActions.setLineProcess(c, "line_1", "magic") }
          out.noLine = { CompanyActions.setLineProcess(c, "line_9", "semi") }
          c.research.unlocked.mfg_auto_1 = 1
          local cash = c.finance.cash
          out.semi = { CompanyActions.setLineProcess(c, "line_1", "semi") }
          out.paid = cash - c.finance.cash
          out.down = c.production.lines[1].downUntilDay
          out.capDown = ProductionRules.effectiveCapacity(c.production.lines[1], 0, 1, 1e9, 11)
          out.capUp = ProductionRules.effectiveCapacity(c.production.lines[1], 0, 1, 1e9, 13)
          cash = c.finance.cash
          out.back = { CompanyActions.setLineProcess(c, "line_1", "hand") }
          out.backPaid = cash - c.finance.cash
          c.research.unlocked.mfg_auto_4 = 1
          out.smartGate = { CompanyActions.setLineProcess(c, "line_1", "smart") }
          table.insert(c.production.lines, ProductionRules.newLine("fab_1", "CPUFab", 1))
          out.fab = { CompanyActions.setLineProcess(c, "fab_1", "semi") }
          out.fabProcess = c.production.lines[2].process
          return out
        """)
        self.assertEqual(r["p0"], "hand")
        self.assertEqual(r["gate"], [False, "Research Factory Automation 3 first"])
        self.assertEqual(r["same"], [False, "Already using that process"])
        self.assertEqual(r["unknown"], [False, "Unknown process"])
        self.assertEqual(r["noLine"], [False, "Unknown line"])
        self.assertTrue(r["semi"][0], r["semi"])
        self.assertEqual(r["semi"][1], {"lineId": "line_1", "process": "semi", "cost": 40000, "downtimeDays": 3, "untilDay": 13})
        self.assertEqual(r["paid"], 40000)
        self.assertEqual(r["down"], 13)
        self.assertEqual(r["capDown"], 0)
        self.assertGreater(r["capUp"], 0)
        self.assertEqual(r["back"][1]["cost"], 0)
        self.assertEqual(r["backPaid"], 0)
        self.assertEqual(r["smartGate"], [False, "Research Quality Systems 3 first"])
        self.assertEqual(r["fab"], [False, "Only assembly lines have a process"])
        self.assertIsNone(r.get("fabProcess"))

    def test_old_save_migration_and_legacy_mirror(self):
        r = self.run_lua(r"""
          local c = newCompany(1000000)
          -- a 0.4.0 save: grid office with paid furniture, no interior, no expansions, lines without a process
          c.interior = nil
          c.hq.expansions = nil
          c.production.lines[1].process = nil
          c.office = { comfort = 0, productivity = 0, furniture = { desk_wooden = 2, lounge_sofa = 1, plant_tall = 2, desk_folding = 1, chair_office = 2 }, desksPlaced = 3 }
          local m = CompanyFactory.migrate(c)
          local items = m.interior.rooms.garage.items
          local n0 = #items
          local defs = {}
          for _, it in ipairs(items) do defs[#defs + 1] = it.def end
          table.sort(defs)
          local again = #CompanyFactory.migrate(m).interior.rooms.garage.items -- idempotent
          -- a 0.4.0 client keeps buying through the old grid: mirrored
          local okb = CompanyActions.buyFurniture(m, "plant_palm")
          local n2 = #m.interior.rooms.garage.items
          -- selling a mirrored piece in the editor removes it from the old office too
          local palm
          for _, it in ipairs(m.interior.rooms.garage.items) do if it.def == "plant_palm" then palm = it end end
          local cash = m.finance.cash
          local okr, rr = CompanyActions.interiorRemove(m, { room = "garage", id = palm.id })
          local gained = m.finance.cash - cash
          local stillInOffice = 0
          for _, p in ipairs(m.office.placed) do if p.itemId == "plant_palm" then stillInOffice = stillInOffice + 1 end end
          -- the old client sells a piece: its mirror disappears
          CompanyActions.sellFurniture(m, "lounge_sofa")
          local sofa = 0
          for _, it in ipairs(m.interior.rooms.garage.items) do if it.def == "seat_sofa_felt" then sofa = sofa + 1 end end
          return { defs = defs, again = again, n = n0, okb = okb, n2 = n2, okr = okr, refund = rr.refund, gained = gained,
                   stillInOffice = stillInOffice, storage = m.office.storage.plant_palm, sofa = sofa,
                   process = m.production.lines[1].process, exp = m.hq.expansions, legacy = items[1].legacy }
        """)
        self.assertEqual(r["defs"], ["desk_pine", "plant_monstera", "plant_monstera", "seat_sofa_felt"])  # the 2nd desk sat in the old storage
        self.assertEqual(r["again"], r["n"])
        self.assertTrue(r["legacy"])
        self.assertTrue(r["okb"])
        self.assertEqual(r["n2"], r["n"] + 1)
        self.assertTrue(r["okr"])
        self.assertEqual(r["refund"], 7500)            # half of the old Palm Tree price
        self.assertEqual(r["gained"], 7500)
        self.assertEqual(r["stillInOffice"], 0)
        self.assertIsNone(r.get("storage"))
        self.assertEqual(r["sofa"], 0)
        self.assertEqual(r["process"], "hand")
        self.assertEqual(r["exp"] or {}, {})

    def test_new_company_and_hq_move(self):
        r = self.run_lua(r"""
          local c = newCompany(1e8)
          local fresh = #(c.interior.rooms.garage and c.interior.rooms.garage.items or {})
          CompanyActions.buyFurniture(c, "lounge_bookshelf")
          local atGarage = #c.interior.rooms.garage.items
          c.milestones = c.milestones or {}
          -- move to the office (requirements bypassed): legacy pieces move along, own garage pieces stay behind
          place(c, "garage", "plant_cactus", -2.5, 0.5, 0)
          c.hq.level = 2
          Interior.syncLegacy(c)
          Interior.refresh(c)
          local office = c.interior.rooms.office and #c.interior.rooms.office.items or 0
          return { fresh = fresh, atGarage = atGarage, office = office, garageLeft = #c.interior.rooms.garage.items }
        """)
        self.assertEqual(r["fresh"], 0)       # starter pieces are the garage's built-in furniture
        self.assertEqual(r["atGarage"], 1)
        self.assertEqual(r["office"], 2)      # the legacy piece AND the player's own garage piece move along
        self.assertEqual(r["garageLeft"], 0)


class InteriorRegressions(unittest.TestCase):
    """Fixes from the 0.5.0 adversarial review (one test per finding)."""

    @classmethod
    def setUpClass(cls):
        cls.lua = LuaHost()

    def run_lua(self, body):
        return self.lua.to_py(self.lua.L.execute(PRELUDE + body))

    def test_switch_downtime_survives_incidents(self):
        r = self.run_lua(r"""
          local c = newCompany(1e8)
          for _, t in ipairs({"mfg_auto_1","mfg_auto_3","mfg_auto_4","mfg_qc_3"}) do c.research.unlocked[t] = 1 end
          local line = c.production.lines[1]
          local day = c.time.elapsedDays
          CompanyActions.setLineProcess(c, line.id, "smart")
          local out = {}
          for _, opt in ipairs({ "ReduceOutput", "Repair", "Replace" }) do
            local id = "inc_" .. opt
            c.production.incidents[#c.production.incidents + 1] = { id = id, kind = "MaterialShortage", lineId = line.id, day = day, resolved = false, options = {"Repair","Replace","ReduceOutput"} }
            CompanyActions.resolveIncident(c, id, opt)
            out[opt] = { down = line.downUntilDay, cap = ProductionRules.effectiveCapacity(line, 1, 1, 1e9, day + 5) }
          end
          -- even a hand-edited downUntilDay cannot end the switch early
          line.downUntilDay = 0
          out.isDown = ProductionRules.isDown(line, day + 9)
          out.capAfter = ProductionRules.effectiveCapacity(line, 1, 1, 1e9, day + 10)
          return out
        """)
        for opt in ("ReduceOutput", "Repair", "Replace"):
            self.assertGreaterEqual(r[opt]["down"], 10, opt)
            self.assertEqual(r[opt]["cap"], 0, opt)
        self.assertTrue(r["isDown"])
        self.assertGreater(r["capAfter"], 0)

    def test_upgrade_line_keeps_process(self):
        r = self.run_lua(r"""
          local c = newCompany(1e8)
          for _, t in ipairs({"mfg_auto_1","mfg_auto_3","mfg_auto_4","mfg_qc_3"}) do c.research.unlocked[t] = 1 end
          local line = c.production.lines[1]
          CompanyActions.setLineProcess(c, line.id, "smart")
          local cash = c.finance.cash
          local ok, d = CompanyActions.upgradeLine(c, line.id)
          return { ok = ok, d = d, paid = cash - c.finance.cash, process = line.process, from = line.processFrom,
                   untilDay = line.processUntil, down = line.downUntilDay, level = line.level,
                   build = ProductionRules.buildCost("Assembly", 2) }
        """)
        self.assertTrue(r["ok"], r)
        self.assertEqual((r["process"], r["from"], r["untilDay"], r["down"], r["level"]), ("smart", "hand", 10, 10, 2))
        self.assertEqual(r["d"]["processCost"], 450000)   # setup 900k x1.5 at level 2 minus the 900k paid
        self.assertEqual(r["paid"], r["build"] + 450000)

    def test_expansions_capped_after_the_move(self):
        r = self.run_lua(r"""
          local c = newCompany(1e8)
          for _, id in ipairs({"basement","shed","showroom","annex"}) do for i = 1, 3 do CompanyActions.buildExpansion(c, id) end end
          local hq1 = { qc = CompanySim.roomLevel(c, "QualityControl"), server = CompanySim.roomLevel(c, "ServerRoom"),
                        slots = Interior.extraResearchSlots(c), crates = Shipping.maxOpen(c) }
          c.hq.level = 2
          return { hq1 = hq1, hq2 = { qc = CompanySim.roomLevel(c, "QualityControl"), server = CompanySim.roomLevel(c, "ServerRoom"),
                   show = CompanySim.roomLevel(c, "Showroom"), slots = Interior.extraResearchSlots(c), mult = Interior.researchMult(c),
                   crates = Shipping.maxOpen(c) } }
        """)
        self.assertEqual((r["hq1"]["qc"], r["hq1"]["server"], r["hq1"]["slots"], r["hq1"]["crates"]), (3, 3, 2, 60))
        self.assertEqual((r["hq2"]["qc"], r["hq2"]["server"], r["hq2"]["show"]), (1, 1, 1))
        self.assertEqual((r["hq2"]["slots"], r["hq2"]["mult"], r["hq2"]["crates"]), (0, 1, 20))

    def test_big_old_office_migrates_fast_and_respects_caps(self):
        r = self.run_lua(r"""
          local c = newCompany(1e9)
          c.hq.level = 7
          c.interior = nil
          -- a 0.4.0 save: 250 grid pieces (no interior yet)
          local ids = {"desk_wooden","plant_palm","lounge_sofa","plant_tall","lab_test_bench","lounge_bookshelf","lounge_coffee"}
          local o = { placed = {}, storage = {}, floors = {}, unlocked = {}, furniture = {}, nextUid = 0 }
          local w, h = Office.gridSize(7)
          for i = 1, 250 do
            o.nextUid = i
            o.placed[i] = { uid = i, itemId = ids[(i % #ids) + 1], x = ((i - 1) % w) + 1, y = (math.floor((i - 1) / w) % h) + 1 }
          end
          c.office = o
          local t0 = os.clock()
          CompanyFactory.migrate(c)
          local dt = os.clock() - t0
          local active, stored, coffee = 0, 0, 0
          for _, it in ipairs(c.interior.rooms.office.items) do
            if it.stored then stored = stored + 1 else active = active + 1 end
            if it.def == "decor_coffee_machine" and not it.stored then coffee = coffee + 1 end
          end
          return { dt = dt, active = active, stored = stored, max = Geo.room("office", 7).maxItems, coffee = coffee }
        """)
        self.assertLess(r["dt"], 1.0)
        self.assertLessEqual(r["active"], r["max"])
        self.assertGreater(r["active"], 60)
        self.assertEqual(r["active"] + r["stored"], 250)
        self.assertEqual(r["coffee"], 1)  # def.max holds for mirrored pieces too

    def test_no_free_seats_and_no_comfort_from_an_empty_room(self):
        r = self.run_lua(r"""
          local free = {}
          for _, d in ipairs(Catalog.list) do
            if d.price <= 0 and (d.fx.seats or 0) > 0 then free[#free + 1] = d.id end
          end
          local c = newCompany(0); c.finance.creditLine = 0; c.finance.debt = 0
          local desk = place(c, "garage", "desk_door_trestle", -2.5, -1.5, 0)
          local c2 = newCompany()
          CompanyActions.buildExpansion(c2, "annex")
          CompanyActions.interiorLight(c2, { room = "annex", preset = "warm" })
          CompanyActions.interiorLight(c2, { room = "garage", preset = "warm" })
          CompanyActions.interiorTheme(c2, { room = "garage", theme = "wood" })
          return { free = free, desk = desk, annex = c2.interior.rooms.annex.comfort, garage = c2.interior.rooms.garage.comfort,
                   effects = c2.interior.summary.effects }
        """)
        self.assertEqual(r["free"] or [], [])
        self.assertFalse(r["desk"]["ok"])
        self.assertEqual((r["annex"], r["garage"]), (0, 0))
        self.assertEqual(r["effects"]["research"], 0)
        self.assertEqual(r["effects"]["design"], 0)

    def test_legacy_pieces_respect_def_max(self):
        r = self.run_lua(r"""
          local c = newCompany(1e7)
          CompanyActions.buyFurniture(c, "lounge_coffee")
          CompanyActions.buyFurniture(c, "lounge_water_cooler")
          local standing, storedId = 0, nil
          for _, it in ipairs(c.interior.rooms.garage.items) do
            if it.def == "decor_coffee_machine" then
              if it.stored then storedId = it.id else standing = standing + 1 end
            end
          end
          local x, z, rot = Interior.autoSpot(c, Geo.room("garage", 1), Catalog.byId.decor_coffee_machine)
          local placeNew = place(c, "garage", "decor_coffee_machine", x, z, rot)
          local unstore = { CompanyActions.interiorMove(c, { room = "garage", id = storedId, x = x, z = z, rot = rot }) }
          return { standing = standing, stored = storedId ~= nil, placeNew = placeNew, unstore = unstore }
        """)
        self.assertEqual(r["standing"], 1)
        self.assertTrue(r["stored"])
        self.assertEqual(r["placeNew"]["d"], "Only 1 of these per room")
        self.assertEqual(r["unstore"], [False, "Only 1 of these per room"])

    def test_mirrored_pieces_do_not_double_dip(self):
        r = self.run_lua(r"""
          local c = newCompany(1e8)
          for i = 1, 6 do CompanyActions.buyFurniture(c, "plant_palm") end
          for i = 1, 3 do CompanyActions.buyFurniture(c, "lounge_sofa") end
          local mirrored, all, notMirrored = 0, 0, 0
          local set = Office.mirrored(c)
          for _ in pairs(set) do mirrored = mirrored + 1 end
          local Furniture = require(Shared.Data.Furniture)
          for _, p in ipairs(c.office.placed) do
            local f = Furniture.byId[p.itemId]
            all = all + (f.comfort or 0)
            if not set[p.uid] then notMirrored = notMirrored + (f.comfort or 0) end
          end
          return { p1 = Office.comfortPoints(c), all = all, notMirrored = notMirrored, mirrored = mirrored,
                   interior = Interior.effect(c, "morale"), cap = Balance.Interior.caps.morale }
        """)
        # the old rating skips pieces standing in the interior (stored ones still count there: no effect anywhere else)
        self.assertEqual(r["p1"], r["notMirrored"])
        self.assertLess(r["p1"], r["all"])
        self.assertGreaterEqual(r["mirrored"], 6)
        self.assertGreater(r["interior"], 0)
        self.assertLessEqual(r["interior"], r["cap"])

    def test_garage_items_follow_the_move(self):
        r = self.run_lua(r"""
          local c = newCompany(1e8)
          local spent = 0
          for i = 1, 11 do
            local x, z, rot = Interior.autoSpot(c, Geo.room("garage", 1), Catalog.byId.plant_palm)
            local p = place(c, "garage", "plant_palm", x, z, rot)
            if p.ok then spent = spent + p.d.cost end
          end
          CompanyActions.buildExpansion(c, "annex")
          place(c, "annex", "lab_bench", 0, 0, 0)
          c.hq.level = 2
          Interior.syncLegacy(c); Interior.refresh(c)
          local office = c.interior.rooms.office.items
          local first = office[1]
          local cash = c.finance.cash
          local sell = { CompanyActions.interiorRemove(c, { room = "office", id = first.id }) }
          local left = 0
          for _, id in ipairs({ "garage", "annex" }) do left = left + #c.interior.rooms[id].items end
          return { n = #office, spent = spent, sell = sell, gained = c.finance.cash - cash, left = left, paid = first.paid }
        """)
        self.assertEqual(r["n"], 11)  # 11 palms + the lab bench, one sold
        self.assertTrue(r["sell"][0], r["sell"])
        self.assertEqual(r["gained"], r["paid"] // 2)
        self.assertEqual(r["spent"], 11 * 600)
        self.assertEqual(r["left"], 0)

    def test_malformed_saves_load_and_tick(self):
        r = self.run_lua(r"""
          local out = {}
          local function try(name, mut)
            local c = newCompany(1e6)
            c.interior = nil; c.hq.expansions = nil
            mut(c)
            local ok, err = pcall(function() local m = CompanyFactory.migrate(c); CompanySim.tickDay(m); Interior.syncLegacy(m); Interior.refresh(m) end)
            out[name] = ok and "ok" or tostring(err)
          end
          try("office_string", function(c) c.office = "x" end)
          try("placed_bad", function(c) c.office = { placed = { { uid = "7", itemId = "desk_wooden", x = 1, y = 1 }, { itemId = "nope" }, "z" }, storage = {} } end)
          try("room_string", function(c) c.interior = { rooms = { garage = "x" } } end)
          try("items_nil", function(c) c.interior = { migrated = true, rooms = { garage = { surfaces = {} } } } end)
          try("item_no_xyz", function(c) c.interior = { migrated = true, rooms = { garage = { items = { { id = "i1", def = "plant_palm" }, 5 } } } } end)
          try("exp_bad", function(c) c.hq.expansions = { annex = { level = "99" }, moon = { level = 1 }, shed = "x" } end)
          try("process_bad", function(c) c.production.lines[1].process = "warp" end)
          local c = newCompany(1e6)
          c.interior = { migrated = true, rooms = { garage = { items = { { id = "i1", def = "plant_palm" } } } } }
          c.hq.expansions = { annex = { level = "99" } }
          c.audit = { { note = string.rep("A", 5000) } }
          local m = CompanyFactory.migrate(c)
          out.item = m.interior.rooms.garage.items[1]
          out.annex = m.hq.expansions.annex.level
          out.note = #m.audit[1].note
          return out
        """)
        for k in ("office_string", "placed_bad", "room_string", "items_nil", "item_no_xyz", "exp_bad", "process_bad"):
            self.assertEqual(r[k], "ok", k)
        self.assertTrue(r["item"]["stored"])
        self.assertEqual(r["annex"], 3)
        self.assertEqual(r["note"], 120)

    def test_positions_must_be_numbers(self):
        r = self.run_lua(r"""
          local c = newCompany()
          return { hex = { CompanyActions.interiorPlace(c, { room = "garage", def = "plant_cactus", x = "-0x2", z = -1.5 }) },
                   str = { CompanyActions.interiorPlace(c, { room = "garage", def = "plant_cactus", x = "-2.5", z = "-1.5" }) },
                   num = place(c, "garage", "plant_cactus", -2.5, -1.5, 0) }
        """)
        self.assertEqual(r["hex"], [False, "Bad position"])
        self.assertEqual(r["str"], [False, "Bad position"])
        self.assertTrue(r["num"]["ok"], r["num"])


class InteriorE2E(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        asyncio.get_running_loop().slow_callback_duration = 2.0
        self.dir = tempfile.mkdtemp(prefix="sos_int_")
        self.server = await GameServer(self.dir).start("127.0.0.1", 0)
        self.url = "ws://127.0.0.1:%d/ws" % self.server.port
        self.clients = []

    async def asyncTearDown(self):
        for c in self.clients:
            await c.close()
        if self.server:
            await self.server.stop()
        shutil.rmtree(self.dir, ignore_errors=True)

    async def client(self, name):
        c = await Client(self.url, name).connect()
        self.clients.append(c)
        return c

    def items(self, cl, room="garage"):
        rooms = (cl.state.get("interior") or {}).get("rooms") or {}
        return (rooms.get(room) or {}).get("items") or []

    async def test_coop_build_mode(self):
        a = await self.client("Ann")
        wa = await a.hello()
        ja = await a.create("Build Co", mode="cofounder")
        b = await self.client("Bob")
        await b.hello()
        await b.join(ja["code"])
        self.assertIn("interior", a.state)
        self.assertEqual(a.state["interior"]["rooms"] or {}, {})

        # A places, B sees it live
        r = await a.act("interiorPlace", {"room": "garage", "def": "decor_aquarium", "x": -2.5, "z": -1.5, "rot": 90})
        self.assertTrue(r["ok"], r)
        iid = r["data"]["item"]["id"]
        await b.wait_for(lambda: any(i["id"] == iid for i in self.items(b)), 5, "B sees the aquarium")
        it = [i for i in self.items(b) if i["id"] == iid][0]
        self.assertEqual((it["def"], it["x"], it["z"], it["rot"]), ("decor_aquarium", -2.5, -1.5, 90))
        self.assertGreater(b.state["interior"]["rooms"]["garage"]["comfort"], 0)

        # overlap / bounds / doorway rejected over the wire, with error keys
        r = await b.act("interiorPlace", {"room": "garage", "def": "plant_palm", "x": -2.5, "z": -1.5, "rot": 0})
        self.assertEqual((r["ok"], r["error"], r.get("errorKey")), (False, "Overlaps another item", "err.overlaps_another_item"))
        r = await b.act("interiorPlace", {"room": "garage", "def": "plant_palm", "x": 9, "z": 0})
        self.assertEqual(r["error"], "Outside the room")
        r = await b.act("interiorPlace", {"room": "garage", "def": "plant_palm", "x": 2.85, "z": -3.0})
        self.assertEqual(r["error"], "Blocked: doorway")
        r = await b.act("interiorPlace", {"room": "garage", "def": {"x": 1}, "x": 0, "z": 0})
        self.assertEqual(r["error"], "Unknown item")

        # B moves it, A sees the move; paint + theme replicate
        r = await b.act("interiorMove", {"room": "garage", "id": iid, "x": -2.5, "z": 0.5, "rot": 0})
        self.assertTrue(r["ok"], r)
        await a.wait_for(lambda: any(i["id"] == iid and i["z"] == 0.5 for i in self.items(a)), 5, "A sees the move")
        r = await a.act("interiorTheme", {"room": "garage", "theme": "neon"})
        self.assertTrue(r["ok"], r)
        await b.wait_for(lambda: b.state["interior"]["rooms"]["garage"].get("theme") == "neon", 5, "theme on B")
        cash = a.state["finance"]["cash"]
        r = await a.act("interiorRemove", {"room": "garage", "id": iid})
        self.assertEqual(r["data"]["refund"], 2600)
        await b.wait_for(lambda: not any(i["id"] == iid for i in self.items(b)), 5, "B sees the removal")
        await a.wait_for(lambda: a.state["finance"]["cash"] == cash + 2600, 5, "refund in finance")

        # expansions at HQ 1: the annex room opens for both
        r = await b.act("interiorPlace", {"room": "annex", "def": "lab_bench", "x": 0, "z": 0})
        self.assertEqual(r["error"], "That room is not built yet")
        cat = await a.act("getExpansionCatalog")
        self.assertTrue(cat["data"]["expansions"]["annex"]["canBuild"], cat)
        r = await a.act("buildExpansion", {"id": "annex"})
        self.assertEqual(r["data"], {"id": "annex", "level": 1, "cost": 90000})
        await b.wait_for(lambda: (b.state["hq"].get("expansions") or {}).get("annex", {}).get("level") == 1, 5, "annex on B")
        r = await b.act("interiorPlace", {"room": "annex", "def": "lab_bench", "x": 0, "z": 0})
        self.assertTrue(r["ok"], r)
        await a.wait_for(lambda: a.state["interior"]["summary"]["labSlots"] == 1, 5, "lab slot summary")

        # production process: tech gate, then switch with downtime
        r = await a.act("setLineProcess", {"lineId": "line_1", "process": "semi"})
        self.assertEqual((r["ok"], r["error"]), (False, "Research Factory Automation 1 first"))

        # build actions have their own rate limit
        res = await asyncio.gather(*[a.act("interiorLight", {"room": "garage", "preset": "warm"}) for _ in range(20)])
        self.assertTrue(any(not x["ok"] and x["error"] == "Too many build actions, slow down" for x in res))
        self.assertTrue(any(x["ok"] for x in res))
        self.assertTrue(wa["playerId"])

    async def test_audit_note_is_clipped(self):
        a = await self.client("Eve")
        await a.hello()
        await a.create("Note Co")
        big = "A" * 60000
        r = await a.act("interiorLight", {"room": "garage", "preset": "warm", "def": big})
        self.assertTrue(r["ok"], r)
        r = await a.act("interiorTheme", {"room": "garage", "theme": "", "def": big})
        self.assertTrue(r["ok"], r)
        await a.wait_for(lambda: any(e.get("operationType") == "interiorTheme" for e in a.state.get("audit") or []), 5, "audit")
        notes = [e.get("note") or "" for e in a.state["audit"]]
        self.assertLessEqual(max(len(n) for n in notes), 120)
        self.assertIn("garage", [n for n in notes if n.startswith("garage")][-1])

    async def test_process_switch_and_old_save(self):
        a = await self.client("Pat")
        wa = await a.hello()
        ja = await a.create("Proc Co")
        cid = ja["companyId"]
        await self.server.stop()
        # make it a 0.4.0 save: no interior, no line process, grid furniture, Factory Automation 1 researched
        store = __import__("sos.store", fromlist=["Store"]).Store(self.dir)
        state = store.load_company_state(cid)
        state.pop("interior", None)
        state["hq"].pop("expansions", None)
        for ln in state["production"]["lines"]:
            ln.pop("process", None)
        state["office"] = {"comfort": 0, "productivity": 0, "furniture": {"desk_office": 1, "plant_palm": 1}, "desksPlaced": 1}
        state["research"]["unlocked"]["mfg_auto_1"] = 0
        state["finance"]["cash"] = 3000000
        store.save_company(cid, [wa["playerId"]], state["name"], state["mode"], state, state["stateVersion"])
        store.close()
        await a.close()
        self.clients = []
        self.server = await GameServer(self.dir).start("127.0.0.1", 0)
        self.url = "ws://127.0.0.1:%d/ws" % self.server.port
        a2 = await self.client("Pat")
        await a2.hello(wa["token"])
        j = await a2.resume()
        self.assertEqual(j["t"], "joined", j)
        defs = sorted(i["def"] for i in self.items(a2))
        self.assertEqual(defs, ["desk_white", "plant_palm"])
        self.assertTrue(all(i.get("legacy") for i in self.items(a2)))
        self.assertEqual(a2.state["production"]["lines"][0]["process"], "hand")
        day = a2.state["time"]["elapsedDays"]
        r = await a2.act("setLineProcess", {"lineId": "line_1", "process": "semi"})
        self.assertTrue(r["ok"], r)
        self.assertEqual((r["data"]["cost"], r["data"]["downtimeDays"]), (40000, 3))
        await a2.wait_for(lambda: a2.state["production"]["lines"][0].get("process") == "semi", 5, "process replicated")
        ln = a2.state["production"]["lines"][0]
        self.assertEqual((ln["processFrom"], ln["processUntil"], ln["downUntilDay"]), ("hand", day + 3, day + 3))
        # old 0.4.0 actions keep working and stay in sync
        r = await a2.act("buyFurniture", {"itemId": "lounge_bookshelf"})
        self.assertTrue(r["ok"], r)
        await a2.wait_for(lambda: any(i["def"] == "store_bookcase" for i in self.items(a2)), 5, "legacy buy mirrored")


if __name__ == "__main__":
    unittest.main()
