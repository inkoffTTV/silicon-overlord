"""End-to-end tests for iteration 3: story start (co-op, chapters, clock), repair orders, skip, company slots,
old-save migration, quick start unchanged, research points and the daily gift. Real server, websocket clients."""
import asyncio
import json
import shutil
import tempfile
import time
import unittest

from client import Client, PHONE_SLOTS
from sos.server import GameServer
from test_e2e import diff_keys

STEPS = {
    0: ["intro_seen", "door_open", "lights_on"],
    1: ["take_device", "repair_device", "get_paid", "second_customer"],
    2: ["diagnose_part", "call_supplier", "buy_parts", "fit_part", "paid_with_part"],
    3: ["pattern_repair", "notice_pattern", "start_research", "research_challenge"],
    4: ["investor_seen", "design_phone", "publish_phone", "develop_phone", "polish_challenge"],
    5: ["queue_batch", "first_crate", "ship_crate", "qc_challenge"],
    6: ["launch_phone", "reviews_seen", "sign_swapped"],
}


class StoryE2E(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        asyncio.get_running_loop().slow_callback_duration = 2.0
        self.dir = tempfile.mkdtemp(prefix="sos_story_")
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

    async def ok(self, cl, action, args=None):
        r = await cl.act(action, args or {})
        self.assertTrue(r["ok"], (action, args, r))
        return r.get("data")

    async def chapter(self, cl, n, timeout=10):
        await cl.wait_for(lambda: cl.state["story"]["chapter"] == n, timeout, "chapter %d" % n)

    def orders(self, cl, **match):
        out = []
        for o in cl.state["repairs"]["orders"] or []:
            if all(o.get(k) == v for k, v in match.items()):
                out.append(o)
        return out

    # ------------------------------------------------------------------------------------------
    async def test_story_full_coop_run(self):
        t0 = time.time()
        a = await self.client("Аня")
        await a.hello()
        j = await a.create("Гараж", mode="cofounder", story=True)
        st = a.state
        self.assertEqual((st["story"]["done"], st["story"]["mode"], st["story"]["chapter"]), (False, "story", 0))
        self.assertEqual((st["finance"]["cash"], st["time"]["speed"], len(st["employees"]["list"])), (6000, 0, 2))
        self.assertEqual(st["story"]["step"], "intro_seen")
        await a.wait_for(lambda: any(n.get("key") == "story.chapter" for n in a.notes), 5, "chapter 0 card")
        b = await self.client("Боря")
        await b.hello()
        jb = await b.join(j["code"])
        self.assertEqual(jb["t"], "joined", jb)
        self.assertEqual(b.state["story"]["chapter"], 0)

        # ---- the clock is paused until chapter 4; speed changes are refused with a friendly reason
        n = len(a.frames)
        await a.send({"t": "speed", "speed": 8})
        await a.wait_for(lambda: any(f["t"] == "error" and f.get("key") == "err.story_clock_paused" for f in a.frames[n:]),
                         5, "speed refused")
        r = await b.act("setSpeed", {"speed": 4})
        self.assertEqual((r["ok"], r["errorKey"]), (False, "err.story_clock_paused"))
        await asyncio.sleep(0.5)
        self.assertEqual(a.state["time"]["elapsedDays"], 0)

        # ---- chapter 0: both players complete steps; events of later chapters do not count
        self.assertTrue((await self.ok(a, "storyEvent", {"id": "intro_seen"}))["counted"])
        self.assertTrue((await self.ok(b, "storyEvent", {"id": "door_open"}))["counted"])
        self.assertFalse((await self.ok(b, "storyEvent", {"id": "sign_swapped"}))["counted"])
        self.assertFalse((await self.ok(a, "storyEvent", {"id": "door_open"}))["counted"])
        r = await a.act("storyEvent", {"id": "cheat_finish"})
        self.assertEqual((r["ok"], r["errorKey"]), (False, "err.story_unknown_event"))
        await self.ok(a, "storyEvent", {"id": "lights_on"})
        await self.chapter(b, 1)
        self.assertNotIn("sign_swapped", b.state["story"]["stepsDone"])

        # ---- chapter 1: B takes orders, A repairs; rewards are capped by the agreed price
        await b.wait_for(lambda: self.orders(b, status="waiting"), 5, "first customer")
        o1 = self.orders(b, status="waiting")[0]
        self.assertEqual((o1["customer"], o1["device"], o1["fault"], o1["reward"]), ("grandma", "phone", "software_glitch", 60))
        d = await self.ok(b, "repairTake", {"orderId": o1["id"]})
        self.assertEqual(d["order"]["status"], "inRepair")
        await a.wait_for(lambda: len(a.state["repairs"]["orders"]) == 2, 5, "next customer while A repairs")
        d = await self.ok(a, "repairFinish", {"orderId": o1["id"], "score": 7})
        self.assertEqual((d["payout"], d["quality"]), (60, 1))
        cash0 = b.state["finance"]["cash"]
        d = await self.ok(b, "repairReturn", {"orderId": o1["id"]})
        self.assertEqual(d["paid"], 60)
        await b.wait_for(lambda: b.state["finance"]["cash"] == cash0 + 60, 5, "paid")
        o2 = self.orders(a, status="waiting")[0]
        await self.ok(a, "repairTake", {"orderId": o2["id"]})
        d = await self.ok(a, "repairFinish", {"orderId": o2["id"], "score": 0.5})
        self.assertEqual(d["payout"], 35)  # 50 x (0.4 + 0.6 x 0.5)
        r = await a.act("repairFinish", {"orderId": o2["id"], "score": 1})
        self.assertEqual(r["errorKey"], "err.repair_not_in_repair")
        await self.ok(b, "repairReturn", {"orderId": o2["id"]})
        await self.chapter(a, 2)

        # ---- chapter 2: spare parts through Purchasing
        await a.wait_for(lambda: self.orders(a, status="waiting", partId="screen"), 5, "screen order")
        o3 = self.orders(a, status="waiting", partId="screen")[0]
        await self.ok(a, "repairTake", {"orderId": o3["id"]})
        r = await a.act("repairFinish", {"orderId": o3["id"], "score": 1})
        self.assertEqual((r["ok"], r["errorKey"], r["errorParams"]), (False, "err.repair_no_part", {"part": "Replacement Screen"}))
        self.assertTrue((await self.ok(b, "storyEvent", {"id": "supplier_called"}))["counted"])
        q = await self.ok(b, "getMaterialQuotes")
        mats = {m["id"]: m for m in q["materials"]}
        self.assertIn("repair_screen", mats)
        self.assertTrue(any(o["supplierId"] == "parts_depot" for o in mats["repair_screen"]["offers"]))
        await self.ok(b, "buyResources", {"resourceId": "repair_screen", "units": 2})
        d = await self.ok(a, "repairFinish", {"orderId": o3["id"], "score": 1})
        self.assertEqual(d["partUsed"], "repair_screen")
        await a.wait_for(lambda: a.state["inventory"]["resources"]["repair_screen"] == 1, 5, "part used")
        await self.ok(b, "repairReturn", {"orderId": o3["id"]})
        await self.chapter(a, 3)

        # ---- chapter 3: the same fault; the first research is free
        d = await self.ok(b, "startResearch", {"techId": "bat_2"})
        self.assertEqual((d["cost"], d["free"]), (0, True))
        await self.ok(a, "storyEvent", {"id": "pattern_noticed"})
        await a.wait_for(lambda: len(self.orders(a, chapter=3)) == 2, 5, "two port orders")
        o4 = self.orders(a, chapter=3)[0]
        self.assertEqual((o4["fault"], o4["partId"]), ("broken_port", "port"))
        await self.ok(a, "buyResources", {"resourceId": "repair_port", "units": 2})
        await self.ok(a, "repairTake", {"orderId": o4["id"]})
        await self.ok(b, "repairFinish", {"orderId": o4["id"], "score": 0.9})
        self.assertEqual(a.state["story"]["chapter"], 3)
        self.assertEqual(a.state["time"]["elapsedDays"], 0, "clock still paused in chapter 3")
        await self.ok(a, "repairReturn", {"orderId": o4["id"]})

        # ---- chapter 4: investor money, team, the clock starts
        await self.chapter(a, 4)
        await a.wait_for(lambda: any(n.get("key") == "story.investor" for n in a.notes), 5, "investor note")
        self.assertGreaterEqual(a.state["finance"]["cash"], 2500000)
        self.assertEqual(len(a.state["employees"]["list"]), 5)
        self.assertEqual(a.state["time"]["speed"], 1)
        await a.wait_for(lambda: a.state["time"]["elapsedDays"] >= 1, 6, "clock running")
        await self.ok(a, "storyEvent", {"id": "investor_seen"})
        bp = (await self.ok(b, "createBlueprint", {"name": "Fixer", "subtype": "MidrangePhone"}))["id"]
        await self.ok(b, "updateBlueprint", {"id": bp, "slots": PHONE_SLOTS, "priceUSD": 399})
        pid = (await self.ok(a, "publishBlueprint", {"id": bp}))["productId"]
        await a.speed(8)
        await self.chapter(a, 5, timeout=40)
        self.assertNotIn("polish_challenge", a.state["story"]["stepsDone"])

        # ---- chapter 5: first batch on the bench, ship a crate
        await self.ok(a, "queueProduction", {"productId": pid, "lineId": "line_1", "quantity": 100})
        await a.wait_for(lambda: a.state["production"]["crates"], 20, "first crate")
        crate = a.state["production"]["crates"][0]
        await self.ok(b, "shipCrate", {"crateId": crate["id"]})
        await self.chapter(a, 6)
        await a.speed(0)

        # ---- chapter 6: launch, critics, the new sign
        await self.ok(a, "launchProduct", {"productId": pid})
        await self.ok(b, "storyEvent", {"id": "reviews_seen"})
        await self.ok(a, "storyEvent", {"id": "sign_swapped"})
        await a.wait_for(lambda: a.state["story"]["done"], 5, "story done")
        await b.wait_for(lambda: any(n.get("key") == "story.complete" for n in b.notes), 5, "complete note on B")
        self.assertEqual((a.state["story"]["chapter"], a.state["story"]["step"]), (7, ""))

        # chapter cards arrived in order; every required step was announced once
        chapters = [n["params"]["chapter"] for n in a.notes if n.get("key") == "story.chapter"]
        self.assertEqual(chapters, list(range(7)))
        self.assertEqual([n["params"]["chapter"] for n in b.notes if n.get("key") == "story.chapter"], list(range(1, 7)))
        done_notes = [n["params"]["step"] for n in a.notes if n.get("key") == "story.step.done"]
        self.assertEqual(len(done_notes), len(set(done_notes)))
        for ch, ids in STEPS.items():
            for sid in ids:
                if sid.endswith("_challenge"):
                    continue
                self.assertIn(sid, a.state["story"]["stepsDone"], sid)
        step_note = [n for n in a.notes if n.get("key") == "story.step.done"][0]
        self.assertTrue(step_note["bodyKey"].startswith("data.story."), step_note)
        # repair income + research points from repairs
        self.assertGreaterEqual(a.state["repairs"]["done"], 4)
        self.assertGreater(a.state["research"]["points"], 0)

        # both replicas match a fresh snapshot (story / repairs replicate through sections)
        await asyncio.sleep(0.3)
        before = json.loads(json.dumps(b.state))
        n = len(b.frames)
        await self.ok(b, "getSnapshot")
        await b.wait_frame("snapshot", after=n)
        self.assertEqual(diff_keys(before, b.state), [])
        self.assertEqual(diff_keys(a.state, b.state), [])
        print("\n    story run took %.1f s (game days: %d)" % (time.time() - t0, a.state["time"]["elapsedDays"]))

    # ------------------------------------------------------------------------------------------
    async def test_skip_slots_quick_start_migration_daily(self):
        a = await self.client("Quick")
        wa = await a.hello()
        self.assertEqual(await self.ok(a, "listMyCompanies"), [])
        jq = await a.create("Quick Co")
        st = a.state
        # quick start unchanged
        self.assertEqual((st["story"]["done"], st["story"]["mode"], st["story"]["chapter"]), (True, "quick", 7))
        self.assertEqual((st["finance"]["cash"], st["time"]["speed"], len(st["employees"]["list"])), (2500000, 1, 5))
        r = await a.act("storyEvent", {"id": "door_open"})
        self.assertEqual((r["ok"], r["data"]["counted"]), (True, False))
        # daily gift through the server
        d = await self.ok(a, "claimDaily")
        self.assertEqual((d["dayIndex"], d["streak"]), (1, 1))
        self.assertEqual(d["reward"]["kind"], "cash")
        r = await a.act("claimDaily")
        self.assertEqual((r["ok"], r["errorKey"]), (False, "err.already_claimed_today"))
        # passive research points while the clock runs; no repair customers in a quick start
        rp0 = a.state["research"]["points"]
        await a.speed(8)
        await a.wait_for(lambda: a.state["time"]["elapsedDays"] >= 12, 10, "12 days")
        await a.speed(0)
        self.assertGreaterEqual(a.state["research"]["points"], rp0 + 12)
        self.assertEqual(a.state["repairs"]["orders"] or [], [])

        # ---- skip: founder only
        c = await self.client("Founder")
        await c.hello()
        js = await c.create("Story Co", mode="cofounder", story=True)
        b = await self.client("Partner")
        await b.hello()
        self.assertEqual((await b.join(js["code"]))["t"], "joined")
        r = await b.act("storySkip")
        self.assertEqual((r["ok"], r["errorKey"]), (False, "err.story_founder_only"))
        d = await self.ok(c, "storySkip")
        self.assertTrue(d["skipped"])
        self.assertGreater(d["investor"], 0)
        await b.wait_for(lambda: b.state["story"]["done"], 5, "skipped on B")
        self.assertTrue(b.state["story"]["flags"]["skipped"])
        self.assertGreaterEqual(b.state["finance"]["cash"], 2500000)
        self.assertEqual((len(b.state["employees"]["list"]), b.state["time"]["speed"]), (5, 1))
        await b.wait_for(lambda: any(n.get("key") == "story.skipped" for n in b.notes), 5, "skip note")
        r = await c.act("storySkip")
        self.assertEqual(r["errorKey"], "err.story_already_done")
        await b.speed(2)
        await b.wait_for(lambda: b.state["time"]["elapsedDays"] >= 2, 6, "clock runs after skip")
        await b.speed(0)

        # ---- company slots (lobby action, also right after hello)
        slots = await self.ok(b, "listMyCompanies")
        self.assertEqual([s["name"] for s in slots], ["Story Co"])
        s = slots[0]
        self.assertEqual((s["code"], s["role"], s["companyId"], s["story"]["done"], s["mode"]), (js["code"], "CoFounder", js["companyId"], True, "cofounder"))
        self.assertGreater(s["cash"], 0)
        self.assertIn("year", s["date"])
        self.assertGreater(s["online"], 0)
        x = await self.client("Fresh")
        await x.hello()
        self.assertEqual(await self.ok(x, "listMyCompanies"), [])

        # ---- old save without story / repairs: loads as a finished story ("legacy")
        cid = jq["companyId"]
        for cl in self.clients:
            await cl.close()
        self.clients = []
        await self.server.stop()
        store = __import__("sos.store", fromlist=["Store"]).Store(self.dir)
        state = store.load_company_state(cid)
        state.pop("story", None)
        state.pop("repairs", None)
        store.save_company(cid, [wa["playerId"]], state["name"], state["mode"], state, state["stateVersion"])
        store.close()
        self.server = await GameServer(self.dir).start("127.0.0.1", 0)
        self.url = "ws://127.0.0.1:%d/ws" % self.server.port
        a2 = await self.client("Quick")
        await a2.hello(wa["token"])
        slots = await self.ok(a2, "listMyCompanies")
        self.assertEqual([(s["name"], s["role"]) for s in slots], [("Quick Co", "Founder")])
        j2 = await a2.resume()
        self.assertEqual(j2["t"], "joined", j2)
        sto = a2.state["story"]
        self.assertEqual((sto["done"], sto["mode"], sto["chapter"]), (True, "legacy", 7))
        self.assertEqual(a2.state["repairs"]["orders"] or [], [])
        self.assertEqual(a2.state["time"]["speed"], 1)


if __name__ == "__main__":
    unittest.main()
