"""Accounts (docs/ACCOUNTS.md): unit tests (username rules, hashing, rate limiter, store migration) and end-to-end
tests on a real server: register links companies, login on a 2nd PC, generic errors, rate limits, transfer codes,
old clients with device tokens, nothing secret stored or logged."""
import asyncio
import glob
import hashlib
import logging
import os
import shutil
import sqlite3
import tempfile
import time
import unittest

from client import Client
from sos import accounts as acc
from sos.server import GameServer
from sos.store import Store


def derive(username, password, iterations=acc.KDF_ITERATIONS):
    """What the Godot client sends (client/net/kdf.gd)."""
    salt = ("silicon-overlord:" + username.lower()).encode("utf-8")
    return hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, iterations).hex()


class FakeClock:
    def __init__(self):
        self.t = 1000.0

    def __call__(self):
        return self.t


class Unit(unittest.TestCase):
    def test_usernames(self):
        for ok in ("abc", "Vasya_99", "Вася", "игрок_007", "x" * 20, "ЁжиК"):
            self.assertIsNone(acc.username_error(ok), ok)
        for bad in ("ab", "x" * 21, "has space", "dash-name", "emoji😀", "", None, 5, "Vasяa", "名前名前"):
            self.assertIsNotNone(acc.username_error(bad), bad)
        self.assertEqual(acc.canonical("ВаСя"), "вася")
        self.assertEqual(acc.canonical("Bob_1"), "bob_1")

    def test_hash_and_keys(self):
        key = derive("Bob", "correct horse")
        self.assertTrue(acc.valid_key(key))
        self.assertFalse(acc.valid_key(key.upper()))
        self.assertFalse(acc.valid_key("correct horse"))
        salt, h = acc.hash_key(key)
        self.assertEqual(len(salt), 16)
        self.assertNotIn(bytes.fromhex(key), h)
        self.assertTrue(acc.verify_key(key, salt, h))
        self.assertFalse(acc.verify_key(derive("Bob", "correct horsf"), salt, h))
        salt2, h2 = acc.hash_key(key)
        self.assertNotEqual(h, h2, "per-user random salt")
        # case-insensitive usernames give the same key (salt uses the lowercase name), Cyrillic too
        self.assertEqual(derive("BOB", "pw123456"), derive("bob", "pw123456"))
        self.assertEqual(derive("ВАСЯ", "pw123456"), derive("вася", "pw123456"))

    def test_limiter_exponential_lockout(self):
        clk = FakeClock()
        lim = acc.Limiter(max_fail=5, window=60, base_lock=60, max_lock=3600, clock=clk)
        for _ in range(4):
            lim.fail("ip")
        self.assertEqual(lim.check("ip"), 0)
        lim.fail("ip")
        self.assertGreater(lim.check("ip"), 55)
        clk.t += 61
        self.assertEqual(lim.check("ip"), 0)
        for _ in range(5):
            lim.fail("ip")
        self.assertGreater(lim.check("ip"), 115, "second lockout doubles")
        clk.t += 121
        lim.success("ip")
        for _ in range(4):
            lim.fail("ip")
        self.assertEqual(lim.check("ip"), 0, "success resets")
        # failures spread over more than the window never lock
        clk.t += 1000
        lim.success("ip")
        for _ in range(10):
            lim.fail("slow")
            clk.t += 20
        self.assertEqual(lim.check("slow"), 0)

    def test_limiter_reservations(self):
        """Security #2: attempts still running count as failures, so parallel checks cannot exceed max_fail."""
        clk = FakeClock()
        lim = acc.Limiter(max_fail=5, window=60, base_lock=60, clock=clk)
        got = [lim.acquire("ip") for _ in range(30)]
        self.assertEqual(got.count(0), 5, "only 5 attempts admitted while none has finished")
        for _ in range(5):
            lim.release("ip", False)
        self.assertGreater(lim.check("ip"), 55, "the 5 failures lock the key")
        self.assertGreater(lim.acquire("ip"), 55)
        # a success releases its slot; reset only when asked
        lim2 = acc.Limiter(max_fail=5, clock=clk)
        for _ in range(4):
            lim2.fail("k")
        self.assertEqual(lim2.acquire("k"), 0)
        self.assertNotEqual(lim2.acquire("k"), 0, "4 failures + 1 running = full")
        lim2.release("k", True)
        self.assertEqual(lim2.acquire("k"), 0, "the slot is free again")
        self.assertNotEqual(lim2.acquire("k"), 0, "success without reset keeps the 4 failures")
        lim2.cancel("k")
        self.assertEqual(lim2.pending, {})
        self.assertEqual(lim2.acquire("k"), 0)
        lim2.release("k", True, reset=True)
        self.assertEqual(lim2.items, {})
        # strikes are forgotten after a long quiet period
        lim3 = acc.Limiter(max_fail=1, base_lock=60, max_lock=600, clock=clk)
        lim3.fail("x")
        clk.t += 61
        lim3.fail("x")
        self.assertGreater(lim3.check("x"), 115)
        clk.t += 121 + 601
        lim3.fail("x")
        self.assertLessEqual(lim3.check("x"), 61, "back to the base lock")

    def test_username_lookalikes(self):
        """Security #6: trailing newline, rare Cyrillic look-alikes, combining marks; skeleton folding."""
        for bad in ("Vasya\n", "Vasya\r", "\nVasya", "МАЈЕЅТІС", "Вася\u0483\u0483", "Вася\u0489", "\u0482Вася",
                    "Ѐлка", "Һаха", "Ѕаша"):
            self.assertIsNotNone(acc.username_error(bad), repr(bad))
        for ok in ("Вася", "Їжак_1", "Ґанок", "Ўладзь", "ЁЖИК"):
            self.assertIsNone(acc.username_error(ok), ok)
        self.assertEqual(acc.skeleton("MAKC"), acc.skeleton("МАКС"))
        self.assertEqual(acc.skeleton("BOB"), acc.skeleton("ВОВ"))
        self.assertEqual(acc.skeleton("Ivan"), acc.skeleton("lvan"))
        self.assertEqual(acc.skeleton("Pro100"), acc.skeleton("PrOlOO"))
        self.assertNotEqual(acc.skeleton("Вася"), acc.skeleton("Петя"))
        self.assertFalse(acc.valid_key("a" * 64 + "\n"))

    def test_counter(self):
        clk = FakeClock()
        c = acc.Counter(3, 60, clock=clk)
        self.assertTrue(all(c.hit("k") for _ in range(3)))
        self.assertFalse(c.hit("k"))
        self.assertGreater(c.wait("k"), 0)
        clk.t += 61
        self.assertTrue(c.hit("k"))

    def test_legacy_plaintext_tokens_scrubbed(self):
        """Security #7: plaintext 0.3.0 tokens in players.token are overwritten after the grace period."""
        d = tempfile.mkdtemp(prefix="sos_leg_")
        try:
            db = sqlite3.connect(os.path.join(d, "silicon.db"))
            db.executescript("""
                CREATE TABLE players (id INTEGER PRIMARY KEY AUTOINCREMENT, token TEXT NOT NULL UNIQUE, name TEXT NOT NULL,
                    last_company TEXT, profile TEXT, created REAL NOT NULL, seen REAL NOT NULL);
                CREATE TABLE companies (id TEXT PRIMARY KEY, code TEXT NOT NULL UNIQUE, owner INTEGER NOT NULL,
                    members TEXT NOT NULL DEFAULT '[]', name TEXT NOT NULL DEFAULT '', mode TEXT NOT NULL DEFAULT 'solo',
                    state TEXT NOT NULL, version INTEGER NOT NULL DEFAULT 0, created REAL NOT NULL, updated REAL NOT NULL,
                    cash REAL NOT NULL DEFAULT 0, devices INTEGER NOT NULL DEFAULT 0, liquidated INTEGER NOT NULL DEFAULT 0);
                INSERT INTO players(id, token, name, created, seen) VALUES (1000, 'old-token-a', 'Ann', 1, 1);
                INSERT INTO players(id, token, name, created, seen) VALUES (1001, 'old-token-b', 'Bob', 1, 1);
                PRAGMA user_version=2;
            """)
            db.close()
            s = Store(d)
            # rollback window: the plaintext copy is still there, the token works
            self.assertEqual(s.db.execute("SELECT token FROM players WHERE id=1000").fetchone()[0], "old-token-a")
            new = s.create_player("Cid")
            s.close()
            s = Store(d, legacy_grace_days=0)
            tokens = [r[0] for r in s.db.execute("SELECT token FROM players ORDER BY id")]
            self.assertEqual(tokens[:2], ["migrated:1000", "migrated:1001"])
            self.assertTrue(tokens[2].startswith("dev:"), "placeholders untouched")
            self.assertEqual(s.player_by_token("old-token-a")["id"], 1000, "nobody is signed out")
            self.assertEqual(s.player_by_token(new["token"])["id"], new["id"])
            self.assertEqual(s.scrub_legacy_tokens(force=True), 0, "idempotent")
            s.close()
            with open(os.path.join(d, "silicon.db"), "rb") as fh:
                blob = fh.read()
            for f in glob.glob(os.path.join(d, "silicon.db-wal")):
                with open(f, "rb") as fh:
                    blob += fh.read()
            # the WAL may still hold old pages until checkpoint; the main table must not
            s = Store(d)
            s.db.execute("PRAGMA wal_checkpoint(TRUNCATE)")
            s.db.execute("VACUUM")
            s.close()
            with open(os.path.join(d, "silicon.db"), "rb") as fh:
                self.assertNotIn(b"old-token-a", fh.read())
        finally:
            shutil.rmtree(d, ignore_errors=True)

    def test_migration_4_keeps_existing_lookalikes(self):
        """Security #6: accounts that already collide (made before skeletons) both keep working after migration 4."""
        from sos import store as st
        d = tempfile.mkdtemp(prefix="sos_m4_")
        try:
            db = sqlite3.connect(os.path.join(d, "silicon.db"), isolation_level=None)
            for v in (1, 2, 3):
                for sql in st._MIGRATIONS[v]:
                    sql(db) if callable(sql) else db.execute(sql)
            for pid, name in ((1000, "MAKC"), (1001, "макс")):
                db.execute("INSERT INTO players(id, token, name, created, seen) VALUES (?,?,?,1,1)", (pid, "dev:%d" % pid, name))
                db.execute("INSERT INTO accounts(player_id, username, username_lc, kdf, salt, hash, created, changed) "
                           "VALUES (?,?,?,?,?,?,?,?)", (pid, name, name.lower(), acc.KDF_ID, b"s", b"h", pid, pid))
            db.execute("PRAGMA user_version=3")
            db.close()
            s = Store(d)
            self.assertEqual(s.account_by_username("makc")["player_id"], 1000)
            self.assertEqual(s.account_by_username("макс")["player_id"], 1001)
            self.assertTrue(s.username_taken("mакс".lower(), acc.skeleton("Макс")))
            self.assertFalse(s.create_account(1002, "MaKc", "makc2", acc.KDF_ID, b"s", b"h"), "look-alike refused")
            self.assertTrue(s.create_account(1002, "Other", "other", acc.KDF_ID, b"s", b"h"))
            s.close()
        finally:
            shutil.rmtree(d, ignore_errors=True)

    def test_transfer_codes(self):
        for _ in range(50):
            code = acc.new_transfer_code()
            self.assertEqual(len(code), 8)
            self.assertEqual(acc.normalize_transfer(acc.format_transfer(code).lower()), code)
        self.assertIsNone(acc.normalize_transfer("ABCD-EFG"))
        self.assertIsNone(acc.normalize_transfer("ABCD-EFG0"))   # 0 is not in the alphabet

    def test_store_migration_keeps_old_tokens(self):
        d = tempfile.mkdtemp(prefix="sos_mig_")
        try:
            # a schema-2 database as the live server has it today
            db = sqlite3.connect(os.path.join(d, "silicon.db"))
            db.executescript("""
                CREATE TABLE players (id INTEGER PRIMARY KEY AUTOINCREMENT, token TEXT NOT NULL UNIQUE, name TEXT NOT NULL,
                    last_company TEXT, profile TEXT, created REAL NOT NULL, seen REAL NOT NULL);
                CREATE TABLE companies (id TEXT PRIMARY KEY, code TEXT NOT NULL UNIQUE, owner INTEGER NOT NULL,
                    members TEXT NOT NULL DEFAULT '[]', name TEXT NOT NULL DEFAULT '', mode TEXT NOT NULL DEFAULT 'solo',
                    state TEXT NOT NULL, version INTEGER NOT NULL DEFAULT 0, created REAL NOT NULL, updated REAL NOT NULL,
                    cash REAL NOT NULL DEFAULT 0, devices INTEGER NOT NULL DEFAULT 0, liquidated INTEGER NOT NULL DEFAULT 0);
                INSERT INTO players(id, token, name, created, seen) VALUES (1000, 'old-token-a', 'Ann', 1, 1);
                INSERT INTO players(id, token, name, created, seen) VALUES (1001, 'old-token-b', 'Bob', 1, 1);
                PRAGMA user_version=2;
            """)
            db.close()
            s = Store(d)
            self.assertEqual(s.player_by_token("old-token-a")["id"], 1000)
            self.assertEqual(s.player_by_token("old-token-b")["id"], 1001)
            self.assertIsNone(s.player_by_token("nope"))
            # tokens are stored hashed in devices
            rows = [r[0] for r in s.db.execute("SELECT token_hash FROM devices")]
            self.assertNotIn("old-token-a", rows)
            # rotation scrubs the legacy copy too
            t2 = s.add_device(1000)
            s.revoke_device(acc.token_hash("old-token-a"))
            self.assertIsNone(s.player_by_token("old-token-a"))
            self.assertEqual(s.player_by_token(t2)["id"], 1000)
            self.assertTrue(s.db.execute("SELECT token FROM players WHERE id=1000").fetchone()[0].startswith("revoked:"))
            s.close()
            self.assertEqual(Store(d).player_by_token(t2)["id"], 1000, "reopen: no second migration")
        finally:
            shutil.rmtree(d, ignore_errors=True)


class Capture(logging.Handler):
    def __init__(self):
        super().__init__(logging.DEBUG)
        self.lines = []

    def emit(self, record):
        self.lines.append(self.format(record))


class AccountsE2E(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        asyncio.get_running_loop().slow_callback_duration = 2.0
        self.dir = tempfile.mkdtemp(prefix="sos_acc_")
        self.log = Capture()
        lg = logging.getLogger("server")
        self._lvl = lg.level
        lg.setLevel(logging.DEBUG)
        lg.addHandler(self.log)
        self.server = await GameServer(self.dir).start("127.0.0.1", 0)
        self.url = "ws://127.0.0.1:%d/ws" % self.server.port
        self.clients = []

    async def asyncTearDown(self):
        for c in self.clients:
            await c.close()
        if self.server:
            await self.server.stop()
        lg = logging.getLogger("server")
        lg.removeHandler(self.log)
        lg.setLevel(self._lvl)
        shutil.rmtree(self.dir, ignore_errors=True)

    async def client(self, name, token=None, ip=None):
        c = await Client(self.url, name, local_ip=ip).connect()
        self.clients.append(c)
        await c.hello(token)
        return c

    async def welcome_after(self, c, n):
        return await c.wait_frame("welcome", after=n)

    def secrets_absent(self, secrets_list):
        """None of these strings (or their bytes) appear in the database files or the server log."""
        self.server.store.db.execute("PRAGMA wal_checkpoint(FULL)")
        blobs = b""
        for f in glob.glob(os.path.join(self.dir, "silicon.db*")):
            with open(f, "rb") as fh:
                blobs += fh.read()
        logs = "\n".join(self.log.lines)
        for s in secrets_list:
            self.assertNotIn(s.encode("utf-8"), blobs, "secret stored in the DB")
            self.assertNotIn(s, logs, "secret in the log")
            if len(s) == 64 and all(ch in "0123456789abcdef" for ch in s):
                self.assertNotIn(bytes.fromhex(s), blobs, "raw derived key bytes stored")
                self.assertNotIn(s.upper().encode(), blobs)

    # ------------------------------------------------------------------------------------------
    async def test_register_login_second_pc_resume(self):
        pw = "Tr0ub4dor&3 sekret"
        a = await self.client("Анна")
        pid = a.welcome["playerId"]
        guest_token = a.welcome["token"]
        self.assertIsNone(a.welcome.get("account"))
        j = await a.create("Нова Лабс")
        code, cid = j["code"], j["companyId"]
        r = await a.act("accountStatus")
        self.assertTrue(r["ok"], r)
        self.assertIsNone(r["data"]["account"])
        self.assertEqual(r["data"]["companies"], 1)
        # register while inside the company: links this player (and its company) to the account
        key = derive("Anna_K", pw)
        r = await a.act("accountRegister", {"username": "Anna_K", "key": key, "kdf": acc.KDF_ID})
        self.assertTrue(r["ok"], r)
        self.assertEqual(r["data"]["username"], "Anna_K")
        new_token = r["data"]["token"]
        self.assertNotEqual(new_token, guest_token, "token rotated on register")
        r = await a.act("accountRegister", {"username": "Other1", "key": key})
        self.assertFalse(r["ok"])
        # bad usernames / taken names (case-insensitive)
        b = await self.client("Bob")
        for bad in ("ab", "with space", "Vasяa"):
            r = await b.act("accountRegister", {"username": bad, "key": derive(bad, pw)})
            self.assertFalse(r["ok"], bad)
        r = await b.act("accountRegister", {"username": "anna_k", "key": derive("anna_k", pw)})
        self.assertFalse(r["ok"])
        self.assertEqual(r["error"], "That username is taken")
        r = await b.act("accountRegister", {"username": "Bob_1", "key": "plain password"})
        self.assertEqual(r["error"], "Bad password key")
        # the old guest token is dead: hello with it creates a fresh player
        g = await self.client("Ghost", guest_token)
        self.assertNotEqual(g.welcome["playerId"], pid)
        # ---- second PC: wrong password and unknown user give the same generic error
        pc2 = await self.client("Someone")
        pc2_guest = pc2.welcome["playerId"]
        r1 = await pc2.act("accountLogin", {"username": "Anna_K", "key": derive("Anna_K", "wrong password")})
        r2 = await pc2.act("accountLogin", {"username": "Nobody_here", "key": derive("Nobody_here", pw)})
        self.assertFalse(r1["ok"])
        self.assertEqual(r1["error"], r2["error"])
        self.assertEqual(r1["error"], "Wrong username or password")
        # correct (username in another case): welcome with the account's player and a fresh token
        n = len(pc2.frames)
        r = await pc2.act("accountLogin", {"username": "ANNA_k", "key": derive("ANNA_k", pw)})
        self.assertTrue(r["ok"], r)
        self.assertFalse(r["data"]["guestKept"], "an empty guest is dropped")
        w = await self.welcome_after(pc2, n)
        self.assertEqual(w["playerId"], pid)
        self.assertEqual(w["account"], {"username": "Anna_K"})
        self.assertEqual(w["lastCompany"], cid)
        pc2_token = w["token"]
        self.assertNotIn(pc2_token, (new_token, guest_token))
        welcomes = [f for f in pc2.frames[n:] if f["t"] in ("welcome", "res")]
        self.assertEqual(welcomes[0]["t"], "welcome", "welcome comes before the answer")
        # the first PC was replaced (one live connection per player), its token stays valid
        await a.wait_for(lambda: a.left is not None or a.closed, 5, "first PC replaced")
        r = await pc2.act("listMyCompanies")
        self.assertEqual([c["companyId"] for c in r["data"]], [cid])
        got = await pc2.resume()
        self.assertEqual(got["t"], "joined")
        self.assertEqual(got["code"], code)
        self.assertEqual(pc2.state["name"], "Нова Лабс")
        r = await pc2.act("setPrice", {"productId": "nope", "price": 1})
        self.assertIn("ok", r)
        # login while in a company is refused
        r = await pc2.act("accountLogin", {"username": "Anna_K", "key": derive("Anna_K", pw)})
        self.assertFalse(r["ok"])
        await pc2.send({"t": "leave"})
        await pc2.wait_for(lambda: pc2.left is not None, 5, "left")
        # several devices: PC1 comes back with its rotated token -> same player
        pc1 = await self.client("Анна", new_token)
        self.assertEqual(pc1.welcome["playerId"], pid)
        self.assertEqual(pc1.welcome["account"], {"username": "Anna_K"})
        # ---- logout on PC1 -> PC1 gets a fresh guest; the token is dead; PC2's token still works
        n = len(pc1.frames)
        r = await pc1.act("accountLogout")
        self.assertTrue(r["ok"], r)
        w = await self.welcome_after(pc1, n)
        self.assertNotEqual(w["playerId"], pid)
        self.assertIsNone(w["account"])
        dead = await self.client("x", new_token)
        self.assertNotEqual(dead.welcome["playerId"], pid)
        again = await self.client("x", pc2_token)
        self.assertEqual(again.welcome["playerId"], pid)
        self.assertNotEqual(pc2_guest, pid)
        self.secrets_absent([pw, derive("Anna_K", pw), derive("Anna_K", "wrong password"), "wrong password"])

    async def test_guest_with_companies_kept_and_restored_on_logout(self):
        pw = "password-123"
        acc_pc = await self.client("Main")
        await acc_pc.act("accountRegister", {"username": "MainUser", "key": derive("MainUser", pw)})
        apid = acc_pc.welcome["playerId"]
        await acc_pc.close()
        g = await self.client("Guest")
        gpid, gtoken = g.welcome["playerId"], g.welcome["token"]
        await g.create("Guest Garage")
        await g.send({"t": "leave"})
        await g.wait_for(lambda: g.left is not None, 5, "left")
        n = len(g.frames)
        r = await g.act("accountLogin", {"username": "mainuser", "key": derive("mainuser", pw)})
        self.assertTrue(r["ok"], r)
        self.assertTrue(r["data"]["guestKept"], "guest with a company keeps its token")
        self.assertEqual((await self.welcome_after(g, n))["playerId"], apid)
        n = len(g.frames)
        r = await g.act("accountLogout", {"guestToken": gtoken})
        self.assertTrue(r["ok"], r)
        self.assertTrue(r["data"]["restored"])
        w = await self.welcome_after(g, n)
        self.assertEqual(w["playerId"], gpid)
        self.assertEqual(w["token"], gtoken)
        r = await g.act("listMyCompanies")
        self.assertEqual([c["name"] for c in r["data"]], ["Guest Garage"])
        # logout as a guest is refused
        r = await g.act("accountLogout")
        self.assertFalse(r["ok"])

    async def test_login_rate_limit(self):
        pw = "hunter2hunter2"
        a = await self.client("A")
        await a.act("accountRegister", {"username": "target", "key": derive("target", pw)})
        await a.close()
        att = await self.client("Attacker")
        for i in range(5):
            r = await att.act("accountLogin", {"username": "target", "key": derive("target", "guess%d" % i)})
            self.assertEqual(r["error"], "Wrong username or password")
        r = await att.act("accountLogin", {"username": "target", "key": derive("target", pw)})
        self.assertFalse(r["ok"], "locked even with the right password")
        self.assertTrue(r["error"].startswith("Too many attempts"), r)
        self.assertEqual(r.get("errorKey"), "err.account_locked")
        # the (username, IP) pair stays locked even when the IP limit is cleared; unknown names lock the same way
        self.server.login_ip = acc.Limiter()
        r = await att.act("accountLogin", {"username": "TARGET", "key": derive("target", pw)})
        self.assertTrue(r["error"].startswith("Too many attempts"))
        for i in range(5):
            await att.act("accountLogin", {"username": "ghost_user", "key": derive("ghost_user", "x%d" % i)})
        self.server.login_ip = acc.Limiter()
        r = await att.act("accountLogin", {"username": "ghost_user", "key": derive("ghost_user", "y")})
        self.assertTrue(r["error"].startswith("Too many attempts"), "no enumeration through the lockout")
        # per-IP: many usernames from one IP
        self.server.login_pair = acc.Limiter()
        for i in range(5):
            await att.act("accountLogin", {"username": "name%d" % i, "key": derive("name%d" % i, "z")})
        r = await att.act("accountLogin", {"username": "fresh_name", "key": derive("fresh_name", "z")})
        self.assertTrue(r["error"].startswith("Too many attempts"))
        # after the lock: back to normal
        self.server.login_ip = acc.Limiter()
        self.server.login_pair = acc.Limiter()
        n = len(att.frames)
        r = await att.act("accountLogin", {"username": "target", "key": derive("target", pw)})
        self.assertTrue(r["ok"], r)
        await self.welcome_after(att, n)

    async def test_change_password_and_delete(self):
        pw, pw2 = "first-password", "second-password"
        a = await self.client("A")
        pid = a.welcome["playerId"]
        r = await a.act("accountRegister", {"username": "Changer", "key": derive("Changer", pw)})
        tok_a = r["data"]["token"]
        b = await self.client("B")
        n = len(b.frames)
        await b.act("accountLogin", {"username": "changer", "key": derive("changer", pw)})
        tok_b = (await self.welcome_after(b, n))["token"]
        await b.close()
        a = await self.client("A", tok_a)
        self.assertEqual(a.welcome["playerId"], pid)
        r = await a.act("accountChangePassword", {"oldKey": derive("Changer", "nope nope"), "newKey": derive("Changer", pw2)})
        self.assertFalse(r["ok"])
        self.assertEqual(r["error"], "Wrong password")
        r = await a.act("accountChangePassword", {"oldKey": derive("Changer", pw), "newKey": derive("Changer", pw2)})
        self.assertTrue(r["ok"], r)
        self.assertEqual(r["data"]["signedOut"], 1)
        c = await self.client("C", tok_b)
        self.assertNotEqual(c.welcome["playerId"], pid, "other devices signed out")
        r = await c.act("accountLogin", {"username": "Changer", "key": derive("Changer", pw)})
        self.assertFalse(r["ok"])
        n = len(c.frames)
        r = await c.act("accountLogin", {"username": "Changer", "key": derive("Changer", pw2)})
        self.assertTrue(r["ok"], r)
        await self.welcome_after(c, n)
        await c.close()
        a = await self.client("A", tok_a)
        self.assertEqual(a.welcome["playerId"], pid, "this device stays logged in")
        # delete: needs the password; the player stays on this PC as a guest, username is free again
        r = await a.act("accountDelete", {"key": derive("Changer", pw)})
        self.assertFalse(r["ok"])
        r = await a.act("accountDelete", {"key": derive("Changer", pw2)})
        self.assertTrue(r["ok"], r)
        r = await a.act("accountStatus")
        self.assertIsNone(r["data"]["account"])
        a2 = await self.client("A", tok_a)
        self.assertEqual(a2.welcome["playerId"], pid)
        r = await a2.act("accountRegister", {"username": "changer", "key": derive("changer", pw)})
        self.assertTrue(r["ok"], r)
        self.secrets_absent([pw, pw2, derive("Changer", pw), derive("Changer", pw2), derive("changer", pw)])

    async def test_transfer_code(self):
        g = await self.client("Guest")
        gpid = g.welcome["playerId"]
        await g.create("Transfer Inc")
        r = await g.act("transferCreate")
        self.assertTrue(r["ok"], r)
        code = r["data"]["code"]
        self.assertRegex(code, r"^[A-Z2-9]{4}-[A-Z2-9]{4}$")
        self.assertEqual(r["data"]["expiresIn"], 600)
        pc2 = await self.client("PC2")
        r = await pc2.act("transferRedeem", {"code": "AAAA-AAAA"})
        self.assertEqual(r["error"], "Wrong or expired code")
        n = len(pc2.frames)
        r = await pc2.act("transferRedeem", {"code": code.lower().replace("-", " ")})
        self.assertTrue(r["ok"], r)
        self.assertIsNone(r["data"]["username"])
        w = await self.welcome_after(pc2, n)
        self.assertEqual(w["playerId"], gpid, "guest -> the same player")
        r = await pc2.act("listMyCompanies")
        self.assertEqual([c["name"] for c in r["data"]], ["Transfer Inc"])
        # single use
        pc3 = await self.client("PC3")
        r = await pc3.act("transferRedeem", {"code": code})
        self.assertFalse(r["ok"])
        # a new code replaces the old one; expired codes fail (and are consumed)
        old = (await pc2.act("transferCreate"))["data"]["code"]
        new = (await pc2.act("transferCreate"))["data"]["code"]
        r = await pc3.act("transferRedeem", {"code": old})
        self.assertFalse(r["ok"], "replaced code")
        self.server.store.db.execute("UPDATE transfer_codes SET expires=?", (time.time() - 1,))
        r = await pc3.act("transferRedeem", {"code": new})
        self.assertFalse(r["ok"], "expired code")
        self.assertEqual(self.server.store.db.execute("SELECT COUNT(*) FROM transfer_codes").fetchone()[0], 0)
        # redeem rate limit per IP (5 failures): AAAA-AAAA, the used code, the replaced code, the expired code and
        # this one. The successful redeem in between does not reset the count.
        r = await pc3.act("transferRedeem", {"code": "BBBB-BBBB"})
        self.assertEqual(r["error"], "Wrong or expired code")
        r = await pc3.act("transferRedeem", {"code": "BBBB-BBBC"})
        self.assertTrue(r["error"].startswith("Too many attempts"), r)
        # creation is rate limited per player (5 per 10 minutes; this player made 3 already)
        for _ in range(2):
            r = await pc2.act("transferCreate")
        self.assertTrue(r["ok"])
        r = await pc2.act("transferCreate")
        self.assertFalse(r["ok"])
        # codes are stored hashed
        rows = [x[0] for x in self.server.store.db.execute("SELECT code_hash FROM transfer_codes")]
        self.assertTrue(all(len(x) == 64 for x in rows))
        self.secrets_absent([code.replace("-", ""), old.replace("-", ""), new.replace("-", "")])

    async def test_account_user_transfer_code(self):
        pw = "transfer-me-pls"
        a = await self.client("A")
        pid = a.welcome["playerId"]
        await a.act("accountRegister", {"username": "Мария", "key": derive("Мария", pw)})
        code = (await a.act("transferCreate"))["data"]["code"]
        b = await self.client("B")
        n = len(b.frames)
        r = await b.act("transferRedeem", {"code": code})
        self.assertTrue(r["ok"], r)
        self.assertEqual(r["data"]["username"], "Мария")
        w = await self.welcome_after(b, n)
        self.assertEqual((w["playerId"], w["account"]), (pid, {"username": "Мария"}))
        # Cyrillic username is case-insensitive too
        c = await self.client("C")
        n = len(c.frames)
        r = await c.act("accountLogin", {"username": "МАРИЯ", "key": derive("МАРИЯ", pw)})
        self.assertTrue(r["ok"], r)

    # ---- security regressions (docs/ACCOUNTS.md "Rate limits") ---------------------------------
    async def test_sec1_username_attack_does_not_lock_owner(self):
        """#1: wrong guesses from other IPs never lock the username for the owner (login or change password)."""
        pw, pw2 = "owner-password-1", "owner-password-2"
        own = await self.client("Owner")
        r = await own.act("accountRegister", {"username": "vasya", "key": derive("vasya", pw)})
        self.assertTrue(r["ok"], r)
        tok = r["data"]["token"]
        att = await self.client("Attacker", ip="127.0.0.2")
        for i in range(5):
            await att.act("accountLogin", {"username": "vasya", "key": derive("vasya", "bad%d" % i)})
        r = await att.act("accountLogin", {"username": "VASYA", "key": derive("vasya", "bad")})
        self.assertTrue(r["error"].startswith("Too many attempts"), "the attacker is locked")
        # a neighbour behind the owner's own IP fails too: the IP is locked for logins, but the logged-in owner
        # can still change the password (limited per player, not per IP / username)
        nat = await self.client("Neighbour", ip="127.0.0.1")
        for i in range(5):
            await nat.act("accountLogin", {"username": "vasya", "key": derive("vasya", "nat%d" % i)})
        r = await own.act("accountChangePassword", {"oldKey": derive("vasya", pw), "newKey": derive("vasya", pw2)})
        self.assertTrue(r["ok"], r)
        r = await own.act("accountDelete", {"key": derive("vasya", "wrong-one")})
        self.assertEqual(r["error"], "Wrong password")
        # the owner on another PC / IP logs in right away
        pc2 = await self.client("Owner PC2", ip="127.0.0.9")
        n = len(pc2.frames)
        r = await pc2.act("accountLogin", {"username": "vasya", "key": derive("vasya", pw2)})
        self.assertTrue(r["ok"], r)
        self.assertEqual((await self.welcome_after(pc2, n))["playerId"], own.welcome["playerId"])
        self.assertNotEqual(tok, "")

    async def test_sec1_soft_delay_for_a_name_under_attack(self):
        """#1: many failures on one name from many IPs only slow it down (never a lock)."""
        pw = "soft-delay-pass"
        own = await self.client("Owner")
        await own.act("accountRegister", {"username": "popular", "key": derive("popular", pw)})
        self.server.login_soft_delay = 0.3
        for i in range(10):
            c = await self.client("A%d" % i, ip="127.0.1.%d" % (i + 1))
            r = await c.act("accountLogin", {"username": "popular", "key": derive("popular", "x%d" % i)})
            self.assertEqual(r["error"], "Wrong username or password")
        pc = await self.client("Owner PC2", ip="127.0.2.1")
        t0 = time.monotonic()
        r = await pc.act("accountLogin", {"username": "popular", "key": derive("popular", pw)})
        self.assertTrue(r["ok"], r)
        self.assertGreaterEqual(time.monotonic() - t0, 0.3, "slowed down")

    async def test_sec2_parallel_logins_cannot_bypass_lockout(self):
        """#2: 30 logins at the same moment from one IP: at most 5 are really checked."""
        own = await self.client("Owner")
        await own.act("accountRegister", {"username": "vasya", "key": derive("vasya", "the-password")})
        conns = [await self.client("P%d" % i, ip="127.0.0.6") for i in range(30)]
        key = derive("vasya", "wrong-guess")
        res = await asyncio.gather(*[c.act("accountLogin", {"username": "vasya", "key": key}) for c in conns])
        wrong = sum(1 for r in res if r.get("error") == "Wrong username or password")
        locked = sum(1 for r in res if str(r.get("error")).startswith("Too many attempts"))
        self.assertLessEqual(wrong, 5, res)
        self.assertEqual(wrong + locked, 30)
        r = await conns[0].act("accountLogin", {"username": "vasya", "key": derive("vasya", "the-password")})
        self.assertTrue(r["error"].startswith("Too many attempts"), r)

    async def test_sec3_own_login_does_not_reset_ip_lock(self):
        """#3: a correct login to your own account does not wipe failures made guessing other names."""
        pw = "attacker-own-pass"
        c = await self.client("Spray", ip="127.0.0.3")
        await c.act("accountRegister", {"username": "atkown", "key": derive("atkown", pw)})
        wrong = locked = 0
        for rnd in range(3):
            for i in range(4):
                name = "victim%d_%d" % (rnd, i)
                r = await c.act("accountLogin", {"username": name, "key": derive(name, "guess")})
                if r.get("error") == "Wrong username or password":
                    wrong += 1
                elif str(r.get("error")).startswith("Too many attempts"):
                    locked += 1
            await c.act("accountLogin", {"username": "atkown", "key": derive("atkown", pw)})
        self.assertLessEqual(wrong, 5)
        self.assertGreater(locked, 0)

    async def test_sec4_own_transfer_code_does_not_reset_lock(self):
        """#4: redeeming your own code does not reset the wrong-code count."""
        g = await self.client("Guest", ip="127.0.0.5")
        answers = []
        for _ in range(3):
            for i in range(4):
                r = await g.act("transferRedeem", {"code": "ZZZZ-ZZZ%d" % (i + 2)})
                answers.append(r.get("error"))
            code = (await g.act("transferCreate"))["data"]["code"]
            await g.act("transferRedeem", {"code": code})
        self.assertLessEqual(answers.count("Wrong or expired code"), 5)
        self.assertTrue(any(str(a).startswith("Too many attempts") for a in answers))
        # plain attempt cap per IP too (20 per 10 minutes)
        self.server.transfer_ip = acc.Limiter()
        g2 = await self.client("Guest2", ip="127.0.0.5")
        for _ in range(20):
            self.server.transfer_ip = acc.Limiter()
            r = await g2.act("transferRedeem", {"code": "ZZZZ-ZZZZ"})
        self.assertTrue(r["error"].startswith("Too many attempts"), r)

    async def test_sec5_register_taken_is_rate_limited(self):
        """#5: "That username is taken" answers count toward a per-IP limit (no free username oracle)."""
        own = await self.client("Owner")
        await own.act("accountRegister", {"username": "Vasya", "key": derive("Vasya", "whatever-pass")})
        g = await self.client("Prober", ip="127.0.0.7")
        errs = []
        for _ in range(25):
            r = await g.act("accountRegister", {"username": "Vasya", "key": "0" * 64})
            errs.append(r["error"])
        self.assertLessEqual(errs.count("That username is taken"), 20)
        self.assertTrue(errs[-1].startswith("Too many attempts"), errs[-1])

    async def test_sec6_lookalike_usernames_refused(self):
        """#6: trailing newline, rare look-alike letters, combining marks, whole-script look-alikes."""
        a = await self.client("A")
        r = await a.act("accountRegister", {"username": "MAKC", "key": derive("MAKC", "password-1")})
        self.assertTrue(r["ok"], r)
        b = await self.client("B", ip="127.0.0.8")
        r = await b.act("accountRegister", {"username": "МАКС", "key": derive("МАКС", "password-1")})
        self.assertEqual(r["error"], "That username is taken", "Cyrillic look-alike of a Latin name")
        for bad in ("Vasya\n", "МАЈЕЅТІС", "Вася\u0483\u0483"):
            r = await b.act("accountRegister", {"username": bad, "key": derive(bad, "password-1")})
            self.assertFalse(r["ok"], repr(bad))
            self.assertTrue(r["error"].startswith("Username:"), r)
        r = await b.act("accountRegister", {"username": "Макс_2", "key": derive("Макс_2", "password-1")})
        self.assertTrue(r["ok"], r)

    async def test_sec8_change_password_is_rate_limited(self):
        """#8: change password / delete are capped per player even with the right key (2 scrypt calls each)."""
        k = derive("busy_one", "busy-password")
        a = await self.client("A")
        await a.act("accountRegister", {"username": "busy_one", "key": k})
        for i in range(5):
            r = await a.act("accountChangePassword", {"oldKey": k, "newKey": k})
            self.assertTrue(r["ok"], (i, r))
        r = await a.act("accountChangePassword", {"oldKey": k, "newKey": k})
        self.assertTrue(r["error"].startswith("Too many attempts"), r)
        r = await a.act("accountDelete", {"key": k})
        self.assertTrue(r["error"].startswith("Too many attempts"), r)
        # account work runs in its own small pool, not the default executor
        self.assertLessEqual(self.server._kdf_pool_slow._max_workers, 1)
        self.assertLessEqual(self.server._kdf_pool._max_workers, 2)

    async def test_old_client_without_accounts(self):
        # a 0.3.0 client: hello with name, keeps the token, never sends account actions
        c = await self.client("Oldie")
        tok, pid = c.welcome["token"], c.welcome["playerId"]
        self.assertIn("account", c.welcome)
        j = await c.create("Old Co")
        await c.close()
        c2 = await self.client("Oldie", tok)
        self.assertEqual(c2.welcome["playerId"], pid)
        self.assertEqual(c2.welcome["lastCompany"], j["companyId"])
        got = await c2.resume()
        self.assertEqual(got["t"], "joined")
        # restart: tokens survive (they live hashed in the devices table)
        await self.server.stop()
        self.server = await GameServer(self.dir).start("127.0.0.1", 0)
        self.url = "ws://127.0.0.1:%d/ws" % self.server.port
        c3 = await self.client("Oldie", tok)
        self.assertEqual(c3.welcome["playerId"], pid)
        self.secrets_absent([tok])


if __name__ == "__main__":
    unittest.main()
