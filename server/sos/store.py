"""SQLite persistence: players (token, name, last company, profile) and companies (state JSON + room code).

Schema migrations use PRAGMA user_version. Game-state migrations happen in Lua (CompanyFactory.migrate)
every time a company is loaded, exactly like DataService.loadCompany on Roblox.
All calls are synchronous and short (WAL mode); the server calls them from the asyncio thread.
"""
import json
import os
import secrets
import sqlite3
import time

SCHEMA_VERSION = 2
FIRST_PLAYER_ID = 1000

_MIGRATIONS = {
    1: [
        """CREATE TABLE IF NOT EXISTS players (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            token TEXT NOT NULL UNIQUE,
            name TEXT NOT NULL,
            last_company TEXT,
            profile TEXT,
            created REAL NOT NULL,
            seen REAL NOT NULL
        )""",
        """CREATE TABLE IF NOT EXISTS companies (
            id TEXT PRIMARY KEY,
            code TEXT NOT NULL UNIQUE,
            owner INTEGER NOT NULL,
            members TEXT NOT NULL DEFAULT '[]',
            name TEXT NOT NULL DEFAULT '',
            mode TEXT NOT NULL DEFAULT 'solo',
            state TEXT NOT NULL,
            version INTEGER NOT NULL DEFAULT 0,
            created REAL NOT NULL,
            updated REAL NOT NULL
        )""",
        "CREATE INDEX IF NOT EXISTS companies_owner ON companies(owner)",
        # player ids start at 1000 (they appear as owner keys "1000" in the company state)
        "INSERT INTO sqlite_sequence(name, seq) SELECT 'players', %d WHERE NOT EXISTS "
        "(SELECT 1 FROM sqlite_sequence WHERE name = 'players')" % (FIRST_PLAYER_ID - 1),
    ],
    2: [
        # leaderboard columns (LeaderboardService: cash and launched devices), refreshed on every save
        "ALTER TABLE companies ADD COLUMN cash REAL NOT NULL DEFAULT 0",
        "ALTER TABLE companies ADD COLUMN devices INTEGER NOT NULL DEFAULT 0",
        "ALTER TABLE companies ADD COLUMN liquidated INTEGER NOT NULL DEFAULT 0",
    ],
}


def board_values(state):
    """(cash, launched devices) exactly as LeaderboardService.collect counts them."""
    cash = (state.get("finance") or {}).get("cash") or 0
    products = state.get("products") or {}
    if isinstance(products, list):
        products = dict(enumerate(products))
    devices = sum(1 for p in products.values() if isinstance(p, dict) and (p.get("launchedDay") or 0) > 0)
    return cash, devices


def _dumps(obj):
    return json.dumps(obj, ensure_ascii=False, separators=(",", ":"), allow_nan=False)


class Store:
    def __init__(self, data_dir):
        os.makedirs(data_dir, exist_ok=True)
        self.path = os.path.join(data_dir, "silicon.db")
        self.db = sqlite3.connect(self.path, isolation_level=None, check_same_thread=False)
        self.db.row_factory = sqlite3.Row
        self.db.execute("PRAGMA journal_mode=WAL")
        self.db.execute("PRAGMA synchronous=NORMAL")
        self.db.execute("PRAGMA busy_timeout=5000")
        self._migrate()

    def _migrate(self):
        v = self.db.execute("PRAGMA user_version").fetchone()[0]
        while v < SCHEMA_VERSION:
            v += 1
            with self.db:
                self.db.execute("BEGIN")
                for sql in _MIGRATIONS[v]:
                    self.db.execute(sql)
                self.db.execute("PRAGMA user_version=%d" % v)

    def close(self):
        self.db.close()

    # ---- players -------------------------------------------------------------------------------
    def create_player(self, name):
        token = secrets.token_urlsafe(24)
        now = time.time()
        cur = self.db.execute("INSERT INTO players(token, name, created, seen) VALUES (?,?,?,?)", (token, name, now, now))
        return {"id": cur.lastrowid, "token": token, "name": name, "last_company": None}

    def player_by_token(self, token):
        row = self.db.execute("SELECT id, token, name, last_company FROM players WHERE token=?", (token,)).fetchone()
        return dict(row) if row else None

    def touch_player(self, pid, name):
        self.db.execute("UPDATE players SET name=?, seen=? WHERE id=?", (name, time.time(), pid))

    def last_company(self, pid):
        row = self.db.execute("SELECT last_company FROM players WHERE id=?", (pid,)).fetchone()
        return row[0] if row else None

    def set_last_company(self, pid, company_id):
        self.db.execute("UPDATE players SET last_company=? WHERE id=?", (company_id, pid))

    def load_profile(self, pid):
        row = self.db.execute("SELECT profile FROM players WHERE id=?", (pid,)).fetchone()
        if row and row[0]:
            return json.loads(row[0])
        return None

    def save_profile(self, pid, profile):
        # the profile's companyId is the player's "last company" (null after a sale / leaving)
        self.db.execute("UPDATE players SET profile=?, last_company=? WHERE id=?",
                        (_dumps(profile), profile.get("companyId"), pid))

    # ---- companies -----------------------------------------------------------------------------
    def code_exists(self, code):
        return self.db.execute("SELECT 1 FROM companies WHERE code=?", (code,)).fetchone() is not None

    def company_by_code(self, code):
        row = self.db.execute("SELECT id, code, owner, mode FROM companies WHERE code=?", (code,)).fetchone()
        return dict(row) if row else None

    def company_meta(self, cid):
        row = self.db.execute("SELECT id, code, owner, members, name, mode, version, updated FROM companies WHERE id=?",
                              (cid,)).fetchone()
        return dict(row) if row else None

    def load_company_state(self, cid):
        row = self.db.execute("SELECT state FROM companies WHERE id=?", (cid,)).fetchone()
        return json.loads(row[0]) if row else None

    def insert_company(self, cid, code, owner, members, name, mode, state, version):
        now = time.time()
        cash, devices = board_values(state)
        self.db.execute(
            "INSERT INTO companies(id, code, owner, members, name, mode, state, version, created, updated, cash, devices) "
            "VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
            (cid, code, owner, _dumps(members), name, mode, _dumps(state), version, now, now, cash, devices))

    def save_company(self, cid, members, name, mode, state, version):
        cash, devices = board_values(state)
        self.db.execute("UPDATE companies SET members=?, name=?, mode=?, state=?, version=?, updated=?, cash=?, devices=?, "
                        "liquidated=? WHERE id=?",
                        (_dumps(members), name, mode, _dumps(state), version, time.time(), cash, devices,
                         1 if state.get("liquidated") else 0, cid))

    def board_rows(self):
        """id, name, cash, devices of every company that is still playing (for the leaderboards)."""
        return [dict(r) for r in self.db.execute("SELECT id, name, cash, devices FROM companies WHERE liquidated=0")]

    def counts(self):
        p = self.db.execute("SELECT COUNT(*) FROM players").fetchone()[0]
        c = self.db.execute("SELECT COUNT(*) FROM companies").fetchone()[0]
        return p, c
