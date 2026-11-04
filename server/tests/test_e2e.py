"""End-to-end: a real GameServer on a random port, websocket clients speaking docs/PROTOCOL.md."""
import asyncio
import json
import re
import shutil
import tempfile
import time
import unittest

from client import Client, PHONE_SLOTS
from sos.server import GameServer, CODE_ALPHABET

CODE_RE = re.compile(r"^[%s]{3}-[%s]{3}$" % (CODE_ALPHABET, CODE_ALPHABET))

# top-level keys the server replicates (CompanyService.ALL_KEYS + stateVersion)
REPLICATED = ["time", "finance", "hq", "employees", "research", "blueprints", "products", "production", "inventory",
              "reputation", "ecosystem", "stock", "world", "milestones", "audit", "news", "owners", "approvals", "invites",
              "tutorialStep", "specialization", "liquidated", "customComponents", "name", "logo", "mode", "projects",
              "unlockedFinishes", "loan", "regionsUnlocked", "office", "goals", "achievements", "awards", "daily",
              "empire", "legacyMods", "stateVersion"]


def norm(v):
    """JSON-normalise and treat {} and [] as the same empty collection (the documented client rule)."""
    if isinstance(v, dict):
        if not v:
            return []
        return {k: norm(x) for k, x in v.items()}
    if isinstance(v, list):
        return [norm(x) for x in v]
    return v


def diff_keys(a, b):
    return [k for k in REPLICATED if norm(a.get(k)) != norm(b.get(k))]


class E2E(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        asyncio.get_running_loop().slow_callback_duration = 2.0  # Lua VM boot takes ~0.2 s
        self.dir = tempfile.mkdtemp(prefix="sos_e2e_")
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

    async def restart(self):
        await self.server.stop()
        self.server = await GameServer(self.dir).start("127.0.0.1", 0)
        self.url = "ws://127.0.0.1:%d/ws" % self.server.port

    # ------------------------------------------------------------------------------------------
    async def test_full_game_flow(self):
        t0 = time.time()
        a = await self.client("Анна")
        w = await a.hello()
        self.assertIsInstance(w["playerId"], int)
        token_a = w["token"]
        joined = await a.create("Нова Лабс", mode="cofounder")
        self.assertRegex(joined["code"], CODE_RE)
        self.assertEqual(joined["you"]["role"], "Founder")
        self.assertEqual(a.state["name"], "Нова Лабс")
        code = joined["code"]
        cid = joined["companyId"]
        self.assertIsNotNone(a.profile, "profile frame")

        # ---- research
        r = await a.act("startResearch", {"techId": "arch_arm_2"})
        self.assertTrue(r["ok"], r)
        self.assertIn("cost", r["data"])
        await a.wait_for(lambda: any(j["techId"] == "arch_arm_2" for j in (a.state["research"]["active"] or [])),
                         what="research in sections")
        bad = await a.act("startResearch", {"techId": "nope"})
        self.assertFalse(bad["ok"])
        self.assertIsInstance(bad["error"], str)

        # ---- design -> publish
        r = await a.act("createBlueprint", {"name": "Nova", "subtype": "MidrangePhone"})
        self.assertTrue(r["ok"], r)
        bp = r["data"]["id"]
        r = await a.act("updateBlueprint", {"id": bp, "slots": PHONE_SLOTS, "priceUSD": 399})
        self.assertTrue(r["ok"], r)
        r = await a.act("evaluateBlueprint", {"id": bp, "priceUSD": 450})
        self.assertTrue(r["ok"], r)
        r = await a.act("publishBlueprint", {"id": bp})
        self.assertTrue(r["ok"], r)
        pid = r["data"]["productId"]
        proj = r["data"].get("projectId")
        await a.wait_for(lambda: pid in (a.state["products"] or {}), what="product replicated")

        # ---- clock: speed 8 advances days and money
        day0, cash0 = a.state["time"]["elapsedDays"], a.state["finance"]["cash"]
        await a.speed(8)
        await a.wait_for(lambda: a.state["time"]["elapsedDays"] >= day0 + 4, 5, "4 days at speed 8")
        self.assertNotEqual(a.state["finance"]["cash"], cash0)

        # development project finishes, then produce, launch and sell
        if proj:
            await a.wait_for(lambda: proj not in (a.state.get("projects") or {}), 30, "development project done")
        r = await a.act("queueProduction", {"productId": pid, "lineId": "line_1", "quantity": 2000})
        self.assertTrue(r["ok"], r)
        await a.wait_for(lambda: a.state["products"][pid]["inventory"] > 0, 20, "first units produced")
        r = await a.act("launchProduct", {"productId": pid, "positioning": "Value"})
        self.assertTrue(r["ok"], r)
        self.assertEqual(len(r["data"]["reviews"]), 3)
        await a.wait_for(lambda: a.state["products"][pid]["unitsSold"] > 0, 25, "first sales")
        self.assertGreater(a.state["finance"]["cash"], 0)
        await a.speed(0)
        await asyncio.sleep(0.3)

        # ---- second player joins by room code (co-founder) and sees the same state
        b = await self.client("Борис")
        wb = await b.hello()
        token_b = wb["token"]
        jb = await b.join(code.replace("-", "").lower())
        self.assertEqual(jb["t"], "joined", jb)
        self.assertEqual(jb["companyId"], cid)
        self.assertEqual(jb["you"]["role"], "CoFounder")
        await a.wait_for(lambda: a.members and len(a.members) == 2, 5, "members frame on A")
        await a.wait_for(lambda: str(wb["playerId"]) in a.state["owners"], 5, "owners section on A")
        await asyncio.sleep(0.3)
        mismatch = diff_keys(a.state, b.state)
        self.assertEqual(mismatch, [], "replica (snapshot+sections) differs from a fresh snapshot in %s" % mismatch)
        self.assertTrue(any("joined" in n["title"] for n in a.notes))

        # ---- large spend needs the co-founder's approval
        r = await a.act("upgradeHQ")
        self.assertTrue(r["ok"], r)
        self.assertTrue(r["data"]["pending"], r)
        approval = r["data"]["approvalId"]
        await b.wait_for(lambda: any(x["id"] == approval for x in (b.state["approvals"] or [])), 5, "approval on B")
        r = await b.act("respondApproval", {"id": approval, "approve": True})
        self.assertTrue(r["ok"], r)
        await a.wait_for(lambda: a.state["hq"]["level"] == 2, 5, "HQ upgraded after approval")
        # co-founders lack CorporateGovernance by default
        r = await b.act("renameCompany", {"name": "Hijack"})
        self.assertFalse(r["ok"])
        self.assertIn("permission", r["error"])

        # ---- chat + positions
        await a.send({"t": "chat", "text": "привет " + "x" * 300})
        await b.wait_for(lambda: b.chat, 5, "chat")
        self.assertEqual(b.chat[-1]["userId"], w["playerId"])
        self.assertLessEqual(len(b.chat[-1]["text"]), 200)
        await b.send({"t": "pos", "p": [1.5, 0, -3], "yaw": 1.2, "pitch": 0.1, "anim": "walk"})
        await a.wait_for(lambda: a.peers and any(p["userId"] == wb["playerId"] for p in a.peers), 5, "peers")
        peer = [p for p in a.peers if p["userId"] == wb["playerId"]][0]
        self.assertEqual(peer["p"], [1.5, 0, -3])
        self.assertEqual(peer["anim"], "walk")

        # ---- ping
        await a.send({"t": "ping", "n": 42})
        await a.wait_for(lambda: any(f["t"] == "pong" and f["n"] == 42 for f in a.frames), 5, "pong")

        # ---- solo company: only the owner may enter
        c = await self.client("Сол")
        await c.hello()
        jc = await c.create("Solo Co", mode="solo")
        d = await self.client("Дэн")
        await d.hello()
        res = await d.join(jc["code"])
        self.assertEqual(res["t"], "error")
        self.assertIn("solo", res["message"])
        res = await d.join("ZZZ-ZZZ")
        self.assertEqual(res["t"], "error")

        # ---- disconnect / resume with the saved token
        day_before = a.state["time"]["elapsedDays"]
        await a.close()
        await b.wait_for(lambda: any(not m["online"] for m in b.members if m["userId"] == w["playerId"]), 5,
                         "A shown offline")
        a2 = await self.client("Анна")
        w2 = await a2.hello(token_a)
        self.assertEqual(w2["playerId"], w["playerId"])
        self.assertEqual(w2["lastCompany"], cid)
        j2 = await a2.resume()
        self.assertEqual(j2["t"], "joined", j2)
        self.assertEqual(j2["companyId"], cid)
        self.assertEqual(a2.state["time"]["elapsedDays"], day_before)
        self.assertIn(pid, a2.state["products"])

        # ---- server restart restores everything from SQLite
        await asyncio.sleep(0.2)
        before = json.loads(json.dumps(a2.state))
        for cl in self.clients:
            await cl.close()
        self.clients = []
        await self.restart()
        a3 = await self.client("Анна")
        w3 = await a3.hello(token_a)
        self.assertEqual(w3["playerId"], w["playerId"])
        j3 = await a3.resume()
        self.assertEqual(j3["t"], "joined", j3)
        self.assertEqual(j3["code"], code)
        after = a3.state
        self.assertEqual(after["time"]["elapsedDays"], before["time"]["elapsedDays"])
        self.assertEqual(after["finance"]["cash"], before["finance"]["cash"])
        self.assertEqual(after["hq"]["level"], 2)
        self.assertEqual(sorted(after["products"]), sorted(before["products"]))
        after["time"]["speed"] = before["time"]["speed"]  # a loaded company starts at speed 1 (Roblox rule)
        self.assertEqual(diff_keys(before, after), [])
        b2 = await self.client("Борис")
        await b2.hello(token_b)
        jb2 = await b2.resume()
        self.assertEqual(jb2["you"]["role"], "CoFounder")
        await a3.wait_for(lambda: len([m for m in a3.members if m["online"]]) == 2, 5, "both online after restart")
        print("\n    full flow took %.1f s (game days simulated: %d)" % (time.time() - t0, after["time"]["elapsedDays"]))

    # ------------------------------------------------------------------------------------------
    async def test_safety(self):
        x = await self.client("Иван")
        await x.send({"t": "act", "id": 1, "action": "hire", "args": {}})
        await x.wait_for(lambda: "Send hello first" in x.errors, 5, "hello first")
        await x.ws.send("{not json")
        await x.wait_for(lambda: "Invalid JSON" in x.errors, 5, "invalid json")
        await x.hello()
        r = await x.act("startResearch", {"techId": "arch_arm_2"})
        self.assertFalse(r["ok"])  # not in a company
        await x.create("Safe Corp")
        r = await x.act("doEvil", {})
        self.assertEqual(r["error"], "Unknown action")
        r = await x.act("createCompany", {})
        self.assertEqual(r["error"], "Unknown action")   # lobby actions are protocol messages
        # a Lua runtime error inside an action is caught: res ok=false, server keeps running
        r = await x.act("setFactoryLayout", {"cells": [1, 2]})
        self.assertFalse(r["ok"])
        r = await x.act("updateBlueprint", {"id": "nope", "slots": "garbage"})
        self.assertFalse(r["ok"])
        await x.send({"t": "act", "id": 999, "action": "setSpeed", "args": [1, 2]})
        await x.wait_for(lambda: any(f["t"] == "res" and f["id"] == 999 and not f["ok"] for f in x.frames), 5, "args type")
        await x.send({"t": "speed", "speed": 3})
        await x.wait_for(lambda: any("Speed" in e for e in x.errors), 5, "bad speed")
        # rate limit
        for i in range(60):
            await x.send({"t": "act", "id": 1000 + i, "action": "getAudit", "args": {}})
        await x.wait_for(lambda: any(f["t"] == "res" and f.get("error") == "Too many requests" for f in x.frames), 5,
                         "rate limit")
        # oversized frame closes only that connection
        y = await self.client("Big")
        await y.hello()
        await y.ws.send(json.dumps({"t": "chat", "text": "x" * 70000}))
        await y.wait_for(lambda: y.closed, 5, "oversized frame closes the socket")
        z = await self.client("Zed")
        wz = await z.hello()
        self.assertIn("token", wz)
        res = await z.join("ABC-12I")
        self.assertEqual(res["t"], "error")
        # health endpoint for monitoring
        reader, writer = await asyncio.open_connection("127.0.0.1", self.server.port)
        writer.write(b"GET /health HTTP/1.1\r\nHost: x\r\n\r\n")
        data = await reader.read(200)
        writer.close()
        self.assertIn(b"200", data)

    async def test_invite_code_and_leave(self):
        a = await self.client("Founder")
        await a.hello()
        await a.create("Solo Start", mode="solo")
        boards = await a.wait_frame("boards")
        self.assertTrue(any(x["name"] == "Solo Start" for x in boards["money"]), boards)
        r = await a.act("createInvite", {"sharePercent": 30, "title": "CTO"})
        self.assertTrue(r["ok"], r)
        invite = r["data"]["code"]
        b = await self.client("Partner")
        wb = await b.hello()
        jb = await b.join(invite)
        self.assertEqual(jb["t"], "joined", jb)
        self.assertEqual(b.state["mode"], "cofounder")
        self.assertEqual(b.state["owners"][str(wb["playerId"])]["sharePercent"], 30)
        # protocol leave keeps ownership; leaveCompany action gives it up
        await b.send({"t": "leave"})
        await b.wait_for(lambda: b.left is not None, 5, "left")
        jr = await b.resume()
        self.assertEqual(jr["t"], "joined")
        r = await b.act("leaveCompany")
        self.assertTrue(r["ok"], r)
        await b.wait_for(lambda: b.left is not None and b.left["reason"] == "leftCompany", 5, "left company")
        await a.wait_for(lambda: a.state["owners"][str(wb["playerId"])].get("left") is True, 5, "dormant stake")
        res = await b.resume()
        self.assertEqual(res["t"], "error")


if __name__ == "__main__":
    unittest.main()
