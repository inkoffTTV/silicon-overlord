"""Accounts (docs/ACCOUNTS.md): username + password login so a player can continue on another PC.

The client never sends the password. It sends a *derived key* = PBKDF2-HMAC-SHA256(password,
"silicon-overlord:" + lowercase(username), KDF_ITERATIONS) as 64 hex chars. The server treats that key as the
secret and stores only scrypt(key, random per-user salt, n=2^14, r=8, p=1). Nothing here ever logs a key.

Also: username rules, a failure rate limiter with exponential lockout, transfer codes (one-time 8-char codes).
"""
import hashlib
import hmac
import re
import secrets
import time

KDF_ID = "pbkdf2-sha256-100000"        # what the client derives; stored per account (future migrations)
KDF_ITERATIONS = 100000
SCRYPT_N, SCRYPT_R, SCRYPT_P, SCRYPT_LEN = 2 ** 14, 8, 1, 32
SALT_BYTES = 16

USERNAME_MIN, USERNAME_MAX = 3, 20
PASSWORD_MIN = 8                         # checked by the client (the server never sees the password)
# Cyrillic: only the Russian alphabet plus the Ukrainian / Belarusian letters, no rare look-alikes (Ј Ѕ Һ ...),
# no combining marks or symbols (U+0482..U+0489). Always matched with fullmatch: "$" would accept a final "\n".
CYRILLIC_LETTERS = "А-яЁёІіЇїЄєҐґЎў"
_LATIN = re.compile(r"[A-Za-z]")
_CYRILLIC = re.compile(r"[%s]" % CYRILLIC_LETTERS)
_USERNAME_RE = re.compile(r"[A-Za-z0-9_%s]{%d,%d}" % (CYRILLIC_LETTERS, USERNAME_MIN, USERNAME_MAX))
_KEY_RE = re.compile(r"[0-9a-f]{64}")

# Look-alike folding for usernames ("skeleton"): two names with the same skeleton look the same on screen, so only
# one of them can exist (UNIQUE index on accounts.username_skel). Applied to the lowercase form.
_SKELETON = str.maketrans({
    # Cyrillic that looks like Latin / digits (upper- or lowercase form)
    "а": "a", "б": "6", "в": "b", "г": "r", "ґ": "r", "е": "e", "ё": "e", "є": "e", "з": "3", "и": "u", "й": "u",
    "і": "l", "ї": "l", "к": "k", "м": "m", "н": "h", "о": "o", "п": "n", "р": "p", "с": "c", "т": "t", "у": "y",
    "ў": "y", "х": "x", "ь": "b", "ш": "w",
    # Latin / digits that look alike
    "0": "o", "1": "l", "i": "l",
})

TRANSFER_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"   # no 0/O, 1/I/L: easy to read aloud and type
TRANSFER_LEN = 8
TRANSFER_TTL = 600.0                     # seconds

# generic answers (no username enumeration on login)
ERR_LOGIN = "Wrong username or password"
ERR_LOCKED = "Too many attempts. Try again in {s} s"
ERR_CODE = "Wrong or expired code"
ERR_BUSY = "Busy, try again"


def now():
    return time.time()


def username_error(raw):
    """None when ok, else an English reason."""
    if not isinstance(raw, str):
        return "Username: 3-20 letters, digits or _"
    if not _USERNAME_RE.fullmatch(raw):
        return "Username: 3-20 letters, digits or _"
    if _LATIN.search(raw) and _CYRILLIC.search(raw):
        return "Username: use Latin or Cyrillic letters, not both"
    return None


def canonical(username):
    """Case-insensitive identity of a username (also what the client puts into the PBKDF2 salt)."""
    return username.lower() if isinstance(username, str) else ""


def skeleton(username):
    """Confusable-folded form: "MAKC" (Latin) and "МАКС" (Cyrillic) give the same skeleton."""
    return canonical(username).translate(_SKELETON)


def valid_key(key):
    return isinstance(key, str) and _KEY_RE.fullmatch(key) is not None


def hash_key(key_hex, salt=None):
    """(salt, hash) of a derived key. The key itself is never stored."""
    salt = salt if salt is not None else secrets.token_bytes(SALT_BYTES)
    h = hashlib.scrypt(bytes.fromhex(key_hex), salt=salt, n=SCRYPT_N, r=SCRYPT_R, p=SCRYPT_P, dklen=SCRYPT_LEN,
                       maxmem=64 * 1024 * 1024)
    return salt, h


def verify_key(key_hex, salt, expected):
    _, h = hash_key(key_hex, salt)
    return hmac.compare_digest(h, expected)


_DUMMY_SALT = secrets.token_bytes(SALT_BYTES)
_DUMMY_HASH = hash_key("00" * 32, _DUMMY_SALT)[1]


def burn_time(key_hex):
    """Same work as a real check, for unknown usernames (no timing difference)."""
    verify_key(key_hex if valid_key(key_hex) else "00" * 32, _DUMMY_SALT, _DUMMY_HASH)
    return False


def token_hash(token):
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def new_transfer_code():
    return "".join(secrets.choice(TRANSFER_ALPHABET) for _ in range(TRANSFER_LEN))


def normalize_transfer(raw):
    if not isinstance(raw, str):
        return None
    c = re.sub(r"[\s\-]", "", raw).upper()
    if len(c) != TRANSFER_LEN or any(ch not in TRANSFER_ALPHABET for ch in c):
        return None
    return c


def format_transfer(code):
    return code[:4] + "-" + code[4:]


class Limiter:
    """Failure counter with exponential lockout, per key (IP, (username, IP), player, ...).

    `max_fail` failures inside `window` seconds lock the key for `base_lock` s; every further lockout doubles it
    (capped at `max_lock`). Strikes are forgotten after `max_lock` s without a new lockout. `check` returns 0 when
    allowed, else seconds to wait. `success` resets the key (callers decide when that is safe).

    Slow checks (scrypt in a thread) must use `acquire` before the await and `release` after it: an attempt that is
    still running counts as a failure for admission, so parallel requests cannot all pass `check` first.
    """

    def __init__(self, max_fail=5, window=60.0, base_lock=60.0, max_lock=3600.0, clock=None):
        self.max_fail, self.window, self.base_lock, self.max_lock = max_fail, window, base_lock, max_lock
        self.clock = clock or time.monotonic
        self.items = {}   # key -> {"fails": [t...], "until": t, "strikes": n}
        self.pending = {}  # key -> attempts reserved by acquire() and not released yet

    def acquire(self, key):
        """Reserve one attempt. 0 = go (call release or cancel later), else seconds to wait (nothing reserved)."""
        w = self.check(key)
        if w:
            return w
        it = self.items.get(key)
        t = self.clock()
        fails = sum(1 for x in it["fails"] if t - x < self.window) if it else 0
        pend = self.pending.get(key, 0)
        if fails + pend >= self.max_fail:
            return 1
        self.pending[key] = pend + 1
        return 0

    def cancel(self, key):
        """Give back a reservation without counting anything."""
        p = self.pending.get(key, 0) - 1
        if p > 0:
            self.pending[key] = p
        else:
            self.pending.pop(key, None)

    def release(self, key, ok, reset=False):
        """End a reserved attempt: a failure is recorded; a success resets the key only when `reset`."""
        self.cancel(key)
        if not ok:
            self.fail(key)
        elif reset:
            self.success(key)

    def check(self, key):
        it = self.items.get(key)
        if not it:
            return 0
        t = self.clock()
        if it["until"] > t:
            return int(it["until"] - t) + 1
        return 0

    def fail(self, key):
        t = self.clock()
        it = self.items.setdefault(key, {"fails": [], "until": 0.0, "strikes": 0})
        it["fails"] = [x for x in it["fails"] if t - x < self.window]
        it["fails"].append(t)
        if it["strikes"] and t - it["until"] > self.max_lock:
            it["strikes"] = 0          # long quiet period: the next lockout starts small again
        if len(it["fails"]) >= self.max_fail:
            lock = min(self.max_lock, self.base_lock * (2 ** it["strikes"]))
            it["strikes"] += 1
            it["until"] = t + lock
            it["fails"] = []
        self._gc(t)

    def success(self, key):
        self.items.pop(key, None)

    def _gc(self, t):
        if len(self.items) < 5000:
            return
        for k in [k for k, it in self.items.items()
                  if it["until"] + self.max_lock < t and not any(t - x < self.window for x in it["fails"])]:
            self.items.pop(k, None)


class Counter:
    """Plain attempts-per-window cap (registrations, transfer codes created), no lockout growth."""

    def __init__(self, max_hits, window, clock=None):
        self.max_hits, self.window = max_hits, window
        self.clock = clock or time.monotonic
        self.items = {}

    def hit(self, key):
        """True when allowed (and counted)."""
        t = self.clock()
        hits = [x for x in self.items.get(key, []) if t - x < self.window]
        if len(hits) >= self.max_hits:
            self.items[key] = hits
            return False
        hits.append(t)
        self.items[key] = hits
        if len(self.items) > 5000:
            for k in [k for k, v in self.items.items() if not v or t - v[-1] >= self.window]:
                self.items.pop(k, None)
        return True

    def add(self, key):
        """Record a hit even when over the cap (failure log)."""
        t = self.clock()
        hits = [x for x in self.items.get(key, []) if t - x < self.window][-(self.max_hits * 4):]
        hits.append(t)
        self.items[key] = hits
        if len(self.items) > 5000:
            for k in [k for k, v in self.items.items() if not v or t - v[-1] >= self.window]:
                self.items.pop(k, None)

    def count(self, key):
        t = self.clock()
        return sum(1 for x in self.items.get(key, []) if t - x < self.window)

    def wait(self, key):
        hits = self.items.get(key) or []
        if not hits:
            return 0
        return max(1, int(self.window - (self.clock() - hits[0])) + 1)
