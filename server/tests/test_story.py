"""Rules-level tests for iteration 3 (story start, repair orders, research points), run in the server's Lua VM."""
import unittest

from sos.lua_host import LuaHost

PRELUDE = r"""
local Shared = game:GetService("ReplicatedStorage").Shared
local CompanyFactory = require(Shared.Domain.CompanyFactory)
local CompanySim = require(Shared.Domain.CompanySim)
local CompanyActions = require(Shared.Domain.CompanyActions)
local ResearchRules = require(Shared.Domain.ResearchRules)
local Story = require(Shared.Domain.Story)
local Balance = require(Shared.Config.Balance)
local function newCompany(story)
  local c = CompanyFactory.new({ id = "s1", name = "Garage", logo = { shape = "hex", colorA = "#fff", colorB = "#000" },
    mode = "solo", founderUserId = 1, founderName = "T", founderShare = 100, seed = 42, now = 0, storyMode = story })
  Story.take(c)
  return c
end
-- runs an action like the server does: the domain function, then the story hook on success
local function act(c, name, fn)
  local ok, data = fn()
  if ok then Story.afterAction(c, name, nil, data) else Story.take(c) end
  return ok, data
end
local function ev(c, id)
  local ok, data = Story.event(c, id)
  Story.afterAction(c, "storyEvent", { id = id }, data)
  return data
end
local function order(c, i) return c.repairs.orders[i] end
local function stepsDone(c) local t = {} for k in pairs(c.story.stepsDone) do t[#t + 1] = k end table.sort(t) return t end
"""


class StoryRules(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.lua = LuaHost()

    def run_lua(self, body):
        return self.lua.to_py(self.lua.L.execute(PRELUDE + body))

    def test_new_story_vs_quick_start(self):
        r = self.run_lua(r"""
          local s, q = newCompany(true), newCompany(false)
          return { s = { cash = s.finance.cash, speed = s.time.speed, staff = #s.employees.list, story = s.story,
                         paused = Story.clockPaused(s), free = Story.freeResearchAvailable(s), news = s.news[1].title },
                   q = { cash = q.finance.cash, speed = q.time.speed, staff = #q.employees.list, story = q.story,
                         paused = Story.clockPaused(q), orders = #q.repairs.orders } }
        """)
        s, q = r["s"], r["q"]
        self.assertEqual((s["cash"], s["speed"], s["staff"], s["paused"], s["free"]), (6000, 0, 2, True, True))
        self.assertEqual((s["story"]["done"], s["story"]["mode"], s["story"]["chapter"], s["story"]["chapterId"]),
                         (False, "story", 0, "workshop"))
        self.assertEqual([o["id"] for o in s["story"]["objectives"]], ["intro_seen", "door_open", "lights_on"])
        self.assertEqual(s["story"]["step"], "intro_seen")
        self.assertEqual(s["news"], "Garage opens its doors")
        self.assertEqual((q["cash"], q["speed"], q["staff"], q["paused"], q["orders"]), (2500000, 1, 5, False, 0))
        self.assertEqual((q["story"]["done"], q["story"]["mode"], q["story"]["chapter"]), (True, "quick", 7))

    def test_chapter_order_events_and_scripted_orders(self):
        r = self.run_lua(r"""
          local c = newCompany(true)
          local out = {}
          out.early = ev(c, "sign_swapped").counted             -- a chapter-6 event in chapter 0: ignored
          out.ok1 = ev(c, "door_open").counted
          out.again = ev(c, "door_open").counted                -- counts once
          ev(c, "intro_seen"); ev(c, "lights_on")
          out.ch = c.story.chapter
          out.done0 = stepsDone(c)
          out.orders1 = #c.repairs.orders
          out.bad = select(2, Story.event(c, "hack"))
          -- chapter 1: taking order 1 brings the next customer
          act(c, "repairTake", function() return Story.repairTake(c, 1, order(c, 1).id) end)
          out.orders2 = #c.repairs.orders
          out.busy = select(2, Story.repairTake(c, 2, order(c, 1).id))
          out.notReady = select(2, Story.repairReturn(c, 2, order(c, 1).id))
          local _, f = act(c, "repairFinish", function() return Story.repairFinish(c, 1, order(c, 1).id, 7) end)
          out.payoutCap = f.payout
          out.again2 = select(2, Story.repairFinish(c, 1, order(c, 1).id, 1))
          local cash0 = c.finance.cash
          local _, p = act(c, "repairReturn", function() return Story.repairReturn(c, 2, order(c, 1).id) end)
          out.paid, out.cashDelta = p.paid, c.finance.cash - cash0
          out.paidAgain = select(2, Story.repairReturn(c, 2, order(c, 1).id))
          out.ch1 = c.story.chapter
          -- order 2 finished straight from the counter with a low score
          local _, f2 = act(c, "repairFinish", function() return Story.repairFinish(c, 2, order(c, 2).id, -3) end)
          out.payoutLow = f2.payout
          act(c, "repairReturn", function() return Story.repairReturn(c, 1, order(c, 2).id) end)
          out.ch2 = c.story.chapter
          out.ch2order = order(c, 3)
          local notes = Story.take(c)
          out.keys = {}
          for _, n in ipairs(notes) do out.keys[#out.keys + 1] = n.key end
          return out
        """)
        self.assertFalse(r["early"])
        self.assertTrue(r["ok1"])
        self.assertFalse(r["again"])
        self.assertEqual(r["ch"], 1)
        self.assertEqual(r["done0"], ["door_open", "intro_seen", "lights_on"])
        self.assertEqual(r["orders1"], 1)
        self.assertEqual(r["bad"], "Unknown story event")
        self.assertEqual(r["orders2"], 2)
        self.assertEqual(r["busy"], "That device is already at the bench")
        self.assertEqual(r["notReady"], "That device is not repaired yet")
        self.assertEqual(r["payoutCap"], 60)           # score 7 is clamped: never above the agreed reward
        self.assertEqual(r["again2"], "That device is already repaired")
        self.assertEqual((r["paid"], r["cashDelta"]), (60, 60))
        self.assertEqual(r["paidAgain"], "That repair is already paid")
        self.assertEqual(r["ch1"], 1)
        self.assertEqual(r["payoutLow"], 20)           # 50 x 0.4 (minimum quality)
        self.assertEqual(r["ch2"], 2)
        self.assertEqual((r["ch2order"]["fault"], r["ch2order"]["partId"], r["ch2order"]["chapter"]),
                         ("cracked_screen", "screen", 2))
        self.assertIn("story.step.done", r["keys"])
        self.assertIn("story.chapter", r["keys"])
        self.assertIn("story.repair.paid", r["keys"])

    def test_payout_formula_capped(self):
        r = self.run_lua(r"""
          return { Story.payout(100, 1), Story.payout(100, 2), Story.payout(100, 0), Story.payout(100, -1),
                   Story.payout(100, 0 / 0), Story.payout(100, "x"), Story.payout(100, 0.5), Story.payout(140, 0.99) }
        """)
        self.assertEqual(r, [100, 100, 40, 40, 40, 40, 70, 139])

    def test_parts_free_research_and_investor(self):
        r = self.run_lua(r"""
          local c = newCompany(true)
          c.story.chapter = 2; c.story.chapterId = "spare_parts"
          c.repairs.orders = {}
          local o = Story.repairTake  -- keep the linter quiet
          local out = {}
          -- a part order without parts in stock
          c.story.flags.spawned = {}
          Story.afterAction(c, "noop", nil, nil)
          local spec = { customer = "courier", device = "phone", fault = "cracked_screen" }
          c.repairs.orders[1] = { id = "rep_x", customer = "courier", device = "phone", fault = "cracked_screen", partId = "screen", reward = 140, status = "waiting", createdDay = 0, chapter = 2 }
          out.noPart = select(2, Story.repairFinish(c, 1, "rep_x", 1))
          c.inventory.resources.repair_screen = 2
          local ok, d = Story.repairFinish(c, 1, "rep_x", 1)
          out.used, out.left, out.rp = d.partUsed, c.inventory.resources.repair_screen, d.rp
          -- free first research in chapters 0..3, no refund when cancelled
          local cash0 = c.finance.cash
          local ok1, r1 = CompanyActions.startResearch(c, 1, "arch_arm_2")
          out.free = { ok1, r1.cost, r1.free, c.finance.cash - cash0, Story.freeResearchAvailable(c) }
          local _, rf = CompanyActions.cancelResearch(c, "arch_arm_2")
          out.refund = rf.refund
          local ok2, r2 = CompanyActions.startResearch(c, 1, "arch_arm_2")
          out.second = { ok2, r2 }
          -- entering chapter 4: investor money, the team, the clock
          c.finance.cash = 6500
          c.story.chapter = 3; c.story.chapterId = "same_fault"
          for _, id in ipairs({ "pattern_repair", "start_research" }) do c.story.stepsDone[id] = true end
          Story.take(c)
          ev(c, "pattern_noticed")
          out.ch4 = { c.story.chapter, c.finance.cash, #c.employees.list, c.time.speed, Story.clockPaused(c), c.story.flags.investor }
          return out
        """)
        self.assertEqual(r["noPart"], "No spare part: buy a Replacement Screen in Purchasing")
        self.assertEqual((r["used"], r["left"], r["rp"]), ("repair_screen", 1, 3))
        self.assertEqual(r["free"], [True, 0, True, 0, False])
        self.assertEqual(r["refund"], 0)
        self.assertFalse(r["second"][0])
        self.assertIn("Not enough cash", r["second"][1])
        ch, cash, staff, speed, paused, inv = r["ch4"]
        self.assertEqual((ch, staff, speed, paused, inv), (4, 5, 1, False, True))
        self.assertEqual(cash, 6500 + 2500000 - 6000)  # earnings are kept on top of the quick-start budget

    def test_migration_old_save_is_done(self):
        r = self.run_lua(r"""
          local c = newCompany(false)
          c.story = nil; c.repairs = nil
          local m = CompanyFactory.migrate(c)
          local s = newCompany(true)
          s.story.chapter = 2
          local m2 = CompanyFactory.migrate(s)
          return { m.story, #m.repairs.orders, Story.clockPaused(m), m2.story.mode, m2.story.chapter, m2.story.done }
        """)
        self.assertEqual((r[0]["done"], r[0]["mode"], r[0]["chapter"], r[0]["chapterId"]), (True, "legacy", 7, "done"))
        self.assertEqual((r[1], r[2]), (0, False))
        self.assertEqual(r[3:], ["story", 2, False])

    def test_side_orders_cadence_cap_and_hq_stop(self):
        r = self.run_lua(r"""
          local c = newCompany(true)
          Story.skip(c, 1)
          local q = newCompany(false)
          local maxOpen, spawned = 0, 0
          for d = 1, 120 do
            c.time.elapsedDays = d; q.time.elapsedDays = d
            local before = #c.repairs.orders
            Story.onDay(c); Story.onDay(q)
            local open = 0
            for _, o in ipairs(c.repairs.orders) do if o.status ~= "paid" then open = open + 1 end end
            maxOpen = math.max(maxOpen, open)
          end
          local ids = {}
          for _, o in ipairs(c.repairs.orders) do ids[#ids + 1] = o.id end
          -- HQ level 2: no new orders
          c.repairs.orders = {}
          c.hq.level = 2
          for d = 121, 200 do c.time.elapsedDays = d; Story.onDay(c) end
          return { maxOpen = maxOpen, seq = c.repairs.seq, after = #c.repairs.orders, quick = #q.repairs.orders, ids = ids,
                   skipNotDone = select(2, Story.skip(c, 1)), sample = c.repairs }
        """)
        self.assertGreaterEqual(r["seq"], 2, "random customers arrive while the clock runs")
        self.assertLessEqual(r["maxOpen"], 2)
        self.assertEqual(r["after"], 0, "no new orders once HQ level >= 2")
        self.assertEqual(r["quick"], 0, "quick start never gets repair orders")
        self.assertEqual(r["skipNotDone"], "The story is already finished")

    def test_research_points_accrual_and_tech_bonus(self):
        r = self.run_lua(r"""
          local c = newCompany(false)
          c.research.points = 0
          local researchers = 0
          for _, e in ipairs(c.employees.list) do if e.station == "research" then researchers = researchers + 1 end end
          local perDay = ResearchRules.dailyPoints(c.employees.list, 1)
          local pts = {}
          for d = 1, 10 do CompanySim.tickDay(c); pts[#pts + 1] = c.research.points end
          -- fractional accumulation is exact over time (1.15 / day with one researcher at lab level 1)
          local acc = { ResearchRules.addPoints({ points = 0 }, 0.4) }
          local r2 = { points = 0 }
          for i = 1, 10 do ResearchRules.addPoints(r2, 0.35) end
          -- tech bonus: a tier-2 research completes today
          local c2 = newCompany(false)
          c2.research.points = 0
          c2.employees.list = {}
          c2.research.active = { { techId = "arch_arm_2", progress = 0.9999, startedDay = 0, collaborators = {} } }
          CompanySim.tickDay(c2)
          return { researchers = researchers, perDay = perDay, pts = pts, frac = c.research.rpFraction, acc = acc,
                   r2 = { r2.points, r2.rpFraction }, bonus = c2.research.points, unlocked = c2.research.unlocked.arch_arm_2 ~= nil,
                   lab2 = ResearchRules.dailyPoints({ { station = "research" }, { station = "research" }, { station = "design" } }, 2) }
        """)
        self.assertEqual(r["researchers"], 1)
        self.assertAlmostEqual(r["perDay"], 1.15)
        self.assertEqual(r["pts"][-1], 11)  # 10 days x 1.15 = 11.5 -> 11 whole points, 0.5 carried
        self.assertAlmostEqual(r["frac"], 0.5, places=3)
        self.assertEqual(r["pts"], sorted(r["pts"]))
        self.assertEqual(r["acc"], [0])
        self.assertEqual(r["r2"][0], 3)
        self.assertAlmostEqual(r["r2"][1], 0.5, places=3)
        self.assertTrue(r["unlocked"])
        self.assertEqual(r["bonus"], 10)  # 5 x tier 2 (no research staff in this company)
        self.assertAlmostEqual(r["lab2"], 2 * 1.0 * 1.3)


if __name__ == "__main__":
    unittest.main()
