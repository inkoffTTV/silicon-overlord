"""Rules-level tests for the iteration-2 Luau additions (crates, challenges, migration) and the locale catalog,
run directly in the server's Lua VM (no sockets)."""
import os
import subprocess
import sys
import unittest

from sos.lua_host import LuaHost
from sos.locale import Locale

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.dirname(HERE)

PRELUDE = r"""
local Shared = game:GetService("ReplicatedStorage").Shared
local CompanyFactory = require(Shared.Domain.CompanyFactory)
local CompanySim = require(Shared.Domain.CompanySim)
local CompanyActions = require(Shared.Domain.CompanyActions)
local Shipping = require(Shared.Domain.Shipping)
local Challenges = require(Shared.Domain.Challenges)
local Balance = require(Shared.Config.Balance)
local function newCompany()
  return CompanyFactory.new({ id = "t1", name = "Test", logo = { shape = "hex", colorA = "#fff", colorB = "#000" },
    mode = "solo", founderUserId = 1, founderName = "T", founderShare = 100, seed = 42, now = 0 })
end
local function withProduct(c)
  c.products.p1 = { id = "p1", name = "Phone", inventory = 0, priceUSD = 400, lifecycle = "Launch", unitsSold = 0 }
  return c.products.p1
end
"""


class Rules(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.lua = LuaHost()

    def run_lua(self, body):
        return self.lua.to_py(self.lua.L.execute(PRELUDE + body))

    def test_crates_one_per_day_and_cap(self):
        r = self.run_lua(r"""
          local c = newCompany(); withProduct(c)
          Shipping.addOutput(c, "p1", 100)
          Shipping.addOutput(c, "p1", 50)          -- same day: same crate
          local one = #c.production.crates
          for d = 1, 30 do
            c.time.elapsedDays = d
            Shipping.addOutput(c, "p1", 10)
          end
          return { one = one, first = c.production.crates[1].units, count = #c.production.crates,
                   total = (function() local s = 0 for _, cr in ipairs(c.production.crates) do s = s + cr.units end return s end)(),
                   inv = c.products.p1.inventory }
        """)
        self.assertEqual(r["one"], 1)
        self.assertEqual(r["first"], 150)
        self.assertEqual(r["count"], 20)          # Balance.Production.maxOpenCrates
        self.assertEqual(r["total"], 150 + 300)   # merged, nothing lost
        self.assertEqual(r["inv"], 0)

    def test_autoship_age_and_logistics(self):
        r = self.run_lua(r"""
          local c = newCompany(); withProduct(c)
          Shipping.addOutput(c, "p1", 100)        -- day 0
          c.time.elapsedDays = 6; Shipping.autoShip(c)
          local before = #c.production.crates
          c.time.elapsedDays = 7; Shipping.autoShip(c)
          local after = #c.production.crates
          local inv7 = c.products.p1.inventory
          c.hq.rooms.LogisticsCenter = { level = 1, builtDay = 7 }
          Shipping.addOutput(c, "p1", 40); Shipping.autoShip(c)
          return { before = before, after = after, inv7 = inv7, inv = c.products.p1.inventory,
                   last = c.production.lastAutoShip, shipped = c.production.shippedTotal }
        """)
        self.assertEqual((r["before"], r["after"]), (1, 0))
        self.assertEqual(r["inv7"], 100)  # no manual bonus
        self.assertEqual(r["inv"], 140)   # LogisticsCenter: same day
        self.assertEqual(r["last"]["units"], 40)
        self.assertEqual(r["shipped"], 140)

    def test_assembly_bonus_and_retailer_premium(self):
        r = self.run_lua(r"""
          local c = newCompany(); withProduct(c)
          local ok1, d1 = Challenges.reward(c, "assembly", "p1", 1)      -- no crate yet: pending for the next one
          Shipping.addOutput(c, "p1", 200)
          local crate = c.production.crates[1]
          local ok2, d2 = Challenges.reward(c, "negotiation", "van", 1)
          local cash0 = c.finance.cash
          local ok3, d3 = CompanyActions.shipCrate(c, crate.id)
          return { ok1 = ok1, pct = crate.bonusPct, ok2 = ok2, ship = d3, cash = c.finance.cash - cash0,
                   prem = c.challenges.retailerPremium, inv = c.products.p1.inventory }
        """)
        self.assertTrue(r["ok1"] and r["ok2"])
        self.assertAlmostEqual(r["pct"], 0.10)
        self.assertEqual(r["ship"]["units"], 200 + 10 + 20)   # +5% manual, +10% assembly
        self.assertEqual(r["ship"]["premium"], int(230 * 400 * 0.03))
        self.assertEqual(r["cash"], r["ship"]["premium"])
        self.assertEqual(r["prem"], 0)                         # used once
        self.assertEqual(r["inv"], 230)

    def test_design_fixes_bug_free(self):
        r = self.run_lua(r"""
          local c = newCompany()
          c.projects = { pr1 = { id = "pr1", productId = "x", name = "X", day = 1, totalDays = 30, quality = 5, bugs = 2,
                                 toughBugs = 1, bugFixProgress = 0, helpers = {}, spent = 0 } }
          c.research.points = 0
          local ok, d = Challenges.reward(c, "design", "pr1", 0.6)
          return { ok = ok, d = d, bugs = c.projects.pr1.bugs, rp = c.research.points }
        """)
        self.assertTrue(r["ok"], r)
        self.assertEqual(r["d"]["applied"]["fixed"], "bug")
        self.assertEqual((r["bugs"], r["rp"]), (1, 0))

    def test_migration_of_old_save(self):
        r = self.run_lua(r"""
          local c = newCompany()
          c.hq.rooms.AssemblyLine = { level = 1, builtDay = 0 }   -- old saves had the room from the start
          c.production.crates = nil; c.production.shippedTotal = nil; c.challenges = nil
          c.production.lines[1].bench = nil; c.production.lines[1].location = nil
          for _, e in ipairs(c.employees.list) do e.station = nil; e.marketSalary = nil end
          local m = CompanyFactory.migrate(c)
          local st = {}
          for _, e in ipairs(m.employees.list) do st[#st + 1] = e.station end
          return { crates = #m.production.crates, ch = m.challenges ~= nil, floor = m.hq.rooms.AssemblyLine ~= nil,
                   loc = m.production.lines[1].location, st = st }
        """)
        self.assertEqual(r["crates"], 0)
        self.assertTrue(r["ch"] and r["floor"])
        self.assertEqual(r["loc"], "garage")
        self.assertEqual(r["st"], ["design", "design", "research", "assembly", "assembly"])


class LocaleCatalog(unittest.TestCase):
    def test_catalog_and_doc_up_to_date(self):
        res = subprocess.run([sys.executable, os.path.join(SERVER, "tools", "gen_locale.py"), "--check"],
                             capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)

    def test_tagging(self):
        loc = Locale()
        self.assertEqual(loc.tag("Not enough cash ($350000)")[:2], ("err.not_enough_cash_cost", {"cost": 350000}))
        self.assertEqual(loc.tag("Research complete: ARM v2")[0], "note.research_complete_name")
        self.assertEqual(loc.tag("Unknown product")[:2], ("err.unknown_product", {}))
        self.assertEqual(loc.tag("totally new text"), (None, None, None))
        frame = loc.outgoing({"t": "res", "ok": False, "error": "Already done: try again in 3 days"})
        self.assertEqual((frame["errorKey"], frame["errorParams"]), ("err.challenge_cooldown", {"days": 3}))


if __name__ == "__main__":
    unittest.main()
