"""SQLite persistence: players (token, name, last company, profile) and companies (state JSON + room code).

Schema migrations use PRAGMA user_version. Game-state migrations happen in Lua (CompanyFactory.migrate)
every time a company is loaded, exactly like DataService.loadCompany on Roblox.
All calls are synchronous and short (WAL mode); the server calls them from the asyncio thread.
"""
import hashlib
import json
import os
import secrets
import sqlite3
import time

from .accounts import skeleton

SCHEMA_VERSION = 4
LEGACY_TOKEN_GRACE_DAYS = 14   # plaintext players.token copies are overwritten this long after migration 3/4
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
    3: [
        # accounts (docs/ACCOUNTS.md). Device tokens move to their own table, stored as sha256 hashes; several
        # devices per player. players.token stays as it was (rollback safety) but is no longer read for login;
        # a revoked / rotated token is also scrubbed there.
        """CREATE TABLE IF NOT EXISTS devices (
            token_hash TEXT PRIMARY KEY,
            player_id INTEGER NOT NULL,
            created REAL NOT NULL,
            seen REAL NOT NULL
        )""",
        "CREATE INDEX IF NOT EXISTS devices_player ON devices(player_id)",
        """CREATE TABLE IF NOT EXISTS accounts (
            player_id INTEGER PRIMARY KEY,
            username TEXT NOT NULL,
            username_lc TEXT NOT NULL UNIQUE,
            kdf TEXT NOT NULL,
            salt BLOB NOT NULL,
            hash BLOB NOT NULL,
            created REAL NOT NULL,
            changed REAL NOT NULL
        )""",
        """CREATE TABLE IF NOT EXISTS transfer_codes (
            code_hash TEXT PRIMARY KEY,
            player_id INTEGER NOT NULL,
            expires REAL NOT NULL
        )""",
        lambda db: db.executemany(
            "INSERT OR IGNORE INTO devices(token_hash, player_id, created, seen) VALUES (?,?,?,?)",
            [(token_hash(r[1]), r[0], r[2], r[3]) for r in db.execute("SELECT id, token, created, seen FROM players")]),
    ],
    4: [
        # look-alike usernames (docs/ACCOUNTS.md): confusable-folded form, unique. NULL (rows written by a schema-3
        # server after a rollback) is allowed several times.
        "ALTER TABLE accounts ADD COLUMN username_skel TEXT",
        lambda db: _fill_skeletons(db),
        "CREATE UNIQUE INDEX IF NOT EXISTS accounts_skel ON accounts(username_skel)",
        # small key/value table; 'devices_since' = when device tokens moved to `devices` (legacy token scrub timer)
        "CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)",
        lambda db: db.execute("INSERT OR IGNORE INTO meta(key, value) VALUES ('devices_since', ?)", (repr(time.time()),)),
    ],
}


def _fill_skeletons(db):
    seen = set()
    for pid, uname in db.execute("SELECT player_id, username FROM accounts ORDER BY created, player_id").fetchall():
        sk = skeleton(uname)
        if sk in seen:
            sk = "%s#%d" % (sk, pid)      # an existing look-alike pair keeps working; no new ones can be made
        seen.add(sk)
        db.execute("UPDATE accounts SET username_skel=? WHERE player_id=?", (sk, pid))


def token_hash(token):
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


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
    def __init__(self, data_dir, legacy_grace_days=LEGACY_TOKEN_GRACE_DAYS):
        self.legacy_grace_days = legacy_grace_days
        os.makedirs(data_dir, exist_ok=True)
        self.path = os.path.join(data_dir, "silicon.db")
        self.db = sqlite3.connect(self.path, isolation_level=None, check_same_thread=False)
        self.db.row_factory = sqlite3.Row
        self.db.execute("PRAGMA journal_mode=WAL")
        self.db.execute("PRAGMA synchronous=NORMAL")
        self.db.execute("PRAGMA busy_timeout=5000")
        self._migrate()
        self.scrub_legacy_tokens()

    def scrub_legacy_tokens(self, force=False):
        """Overwrites the plaintext 0.3.0 device tokens still kept in players.token (rollback copy for a schema-2
        server) once `legacy_grace_days` have passed since the move to `devices`. Login uses only the hashes in
        `devices`, so nobody is signed out. Returns the number of rows scrubbed."""
        row = self.db.execute("SELECT value FROM meta WHERE key='devices_since'").fetchone()
        since = float(row[0]) if row else 0.0
        if not force and time.time() - since < self.legacy_grace_days * 86400:
            return 0
        return self.db.execute("UPDATE players SET token='migrated:' || id WHERE token NOT LIKE 'dev:%' "
                               "AND token NOT LIKE 'revoked:%' AND token NOT LIKE 'migrated:%'").rowcount

    def _migrate(self):
        v = self.db.execute("PRAGMA user_version").fetchone()[0]
        while v < SCHEMA_VERSION:
            v += 1
            with self.db:
                self.db.execute("BEGIN")
                for sql in _MIGRATIONS[v]:
                    if callable(sql):
                        sql(self.db)
                    else:
                        self.db.execute(sql)
                self.db.execute("PRAGMA user_version=%d" % v)

    def close(self):
        self.db.close()

    # ---- players -------------------------------------------------------------------------------
    def create_player(self, name):
        token = secrets.token_urlsafe(24)
        now = time.time()
        with self.db:
            self.db.execute("BEGIN")
            # players.token is legacy (schema 1-2); new players keep only the hash in devices
            cur = self.db.execute("INSERT INTO players(token, name, created, seen) VALUES (?,?,?,?)",
                                  ("dev:" + secrets.token_hex(16), name, now, now))
            self.db.execute("INSERT INTO devices(token_hash, player_id, created, seen) VALUES (?,?,?,?)",
                            (token_hash(token), cur.lastrowid, now, now))
        return {"id": cur.lastrowid, "token": token, "name": name, "last_company": None}

    def player_by_token(self, token):
        """The player a device token belongs to (token is the plain value the client keeps), or None."""
        th = token_hash(token)
        row = self.db.execute("SELECT p.id, p.name, p.last_company FROM devices d JOIN players p ON p.id = d.player_id "
                              "WHERE d.token_hash=?", (th,)).fetchone()
        if not row:
            return None
        self.db.execute("UPDATE devices SET seen=? WHERE token_hash=?", (time.time(), th))
        out = dict(row)
        out["token"] = token
        out["token_hash"] = th
        return out

    def player(self, pid):
        row = self.db.execute("SELECT id, name, last_company FROM players WHERE id=?", (pid,)).fetchone()
        return dict(row) if row else None

    # ---- device tokens -------------------------------------------------------------------------
    def add_device(self, pid):
        """A new device token for pid (login / transfer code / rotation). Returns the plain token."""
        token = secrets.token_urlsafe(24)
        now = time.time()
        self.db.execute("INSERT INTO devices(token_hash, player_id, created, seen) VALUES (?,?,?,?)",
                        (token_hash(token), pid, now, now))
        return token

    def revoke_device(self, th):
        """Invalidates one device token (by its hash); also scrubs the legacy players.token copy."""
        row = self.db.execute("SELECT player_id FROM devices WHERE token_hash=?", (th,)).fetchone()
        self.db.execute("DELETE FROM devices WHERE token_hash=?", (th,))
        if row:
            self._scrub_legacy(row[0], keep=None, only=th)

    def revoke_other_devices(self, pid, keep_th):
        n = self.db.execute("DELETE FROM devices WHERE player_id=? AND token_hash<>?", (pid, keep_th)).rowcount
        self._scrub_legacy(pid, keep=keep_th)
        return n

    def _scrub_legacy(self, pid, keep=None, only=None):
        row = self.db.execute("SELECT token FROM players WHERE id=?", (pid,)).fetchone()
        if not row or row[0].startswith(("revoked:", "dev:", "migrated:")):
            return
        th = token_hash(row[0])
        if (only is not None and th == only) or (only is None and th != keep):
            self.db.execute("UPDATE players SET token=? WHERE id=?", ("revoked:" + secrets.token_hex(16), pid))

    def device_count(self, pid):
        return self.db.execute("SELECT COUNT(*) FROM devices WHERE player_id=?", (pid,)).fetchone()[0]

    # ---- accounts ------------------------------------------------------------------------------
    def account_of(self, pid):
        row = self.db.execute("SELECT player_id, username, username_lc, kdf, salt, hash, created, changed FROM accounts "
                              "WHERE player_id=?", (pid,)).fetchone()
        return dict(row) if row else None

    def account_by_username(self, username_lc):
        row = self.db.execute("SELECT player_id, username, username_lc, kdf, salt, hash, created, changed FROM accounts "
                              "WHERE username_lc=?", (username_lc,)).fetchone()
        return dict(row) if row else None

    def username_taken(self, username_lc, username_skel):
        """True when the name or a look-alike of it (same skeleton) is registered."""
        return self.db.execute("SELECT 1 FROM accounts WHERE username_lc=? OR username_skel=?",
                               (username_lc, username_skel)).fetchone() is not None

    def create_account(self, pid, username, username_lc, kdf, salt, h):
        """False when the username or a look-alike of it is taken (case-insensitive)."""
        now = time.time()
        try:
            self.db.execute("INSERT INTO accounts(player_id, username, username_lc, username_skel, kdf, salt, hash, "
                            "created, changed) VALUES (?,?,?,?,?,?,?,?,?)",
                            (pid, username, username_lc, skeleton(username), kdf, salt, h, now, now))
        except sqlite3.IntegrityError:
            return False
        return True

    def set_password(self, pid, kdf, salt, h):
        self.db.execute("UPDATE accounts SET kdf=?, salt=?, hash=?, changed=? WHERE player_id=?",
                        (kdf, salt, h, time.time(), pid))

    def delete_account(self, pid):
        self.db.execute("DELETE FROM accounts WHERE player_id=?", (pid,))

    # ---- transfer codes ------------------------------------------------------------------------
    def put_transfer(self, code_hash, pid, expires):
        """One live code per player: a new one replaces the old."""
        with self.db:
            self.db.execute("BEGIN")
            self.db.execute("DELETE FROM transfer_codes WHERE player_id=? OR expires<?", (pid, time.time()))
            self.db.execute("INSERT INTO transfer_codes(code_hash, player_id, expires) VALUES (?,?,?)",
                            (code_hash, pid, expires))

    def take_transfer(self, code_hash):
        """Single use: the code is deleted whether or not it is still valid. pid or None."""
        row = self.db.execute("SELECT player_id, expires FROM transfer_codes WHERE code_hash=?", (code_hash,)).fetchone()
        if not row:
            return None
        self.db.execute("DELETE FROM transfer_codes WHERE code_hash=?", (code_hash,))
        return row[0] if row[1] >= time.time() else None

    def drop_transfers(self, pid):
        self.db.execute("DELETE FROM transfer_codes WHERE player_id=?", (pid,))

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

    def companies_of(self, pid):
        """id, code, name, mode, updated of companies whose saved member list (active owners) contains pid."""
        out = []
        for r in self.db.execute("SELECT id, code, owner, members, name, mode, updated FROM companies "
                                 "WHERE liquidated=0 AND (owner=? OR members LIKE ?)", (pid, "%" + str(pid) + "%")):
            try:
                members = json.loads(r["members"] or "[]")
            except ValueError:
                members = []
            if pid in members or r["owner"] == pid:
                out.append(dict(r))
        return out

    def board_rows(self):
        """id, name, cash, devices of every company that is still playing (for the leaderboards)."""
        return [dict(r) for r in self.db.execute("SELECT id, name, cash, devices FROM companies WHERE liquidated=0")]

    def counts(self):
        p = self.db.execute("SELECT COUNT(*) FROM players").fetchone()[0]
        c = self.db.execute("SELECT COUNT(*) FROM companies").fetchone()[0]
        return p, c
