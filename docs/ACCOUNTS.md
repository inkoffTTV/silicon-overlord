# Accounts — play your companies on another PC

Until 0.3.0 a player was only a random **device token** (saved in `user://profile.cfg`, sent in `hello`).
Accounts add a username + password on top of that, plus a passwordless **transfer code**. Old clients keep
working exactly as before with their device token (nothing in `hello` / `welcome` changed for them).

Code: `server/sos/accounts.py` (rules, hashing, rate limiter), `server/sos/store.py` (schema 3 + 4),
`server/sos/server.py` (lobby actions `account*` / `transfer*`), `client/net/kdf.gd` (key derivation),
`client/net/net.gd` (API), `client/ui/menu/account_panel.gd` (UI). Tests: `server/tests/test_accounts.py`,
`client/tests/ui_account_test.gd`.

## Identity model
- **Player** = row in `players` (id, name, profile, companies by owner id). Unchanged.
- **Device token** = random 32-char secret a PC keeps. Stored on the server **only as sha256** in table
  `devices(token_hash, player_id, created, seen)`. A player can have **several devices** (several PCs logged in).
  Migration 3 copies the hash of every existing `players.token` into `devices`, so all 0.3.0 tokens stay valid.
  `players.token` is legacy: kept for rollback safety for old rows, new players get a placeholder `dev:…`, and a
  revoked token is overwritten with `revoked:…`. **The plaintext 0.3.0 tokens stay in `players.token` for
  14 days** after the upgrade (`meta.devices_since`, written by migration 4), so the server can still be rolled back to
  0.3.0 without signing everyone out. After that the server overwrites them with `migrated:<id>` (on start and once an
  hour, `Store.scrub_legacy_tokens`); nobody is signed out, login reads only `devices`. **Rollback to a 0.3.0 server
  is safe only inside those 14 days**; later every old player would get a fresh guest profile.
- **Account** = optional row in `accounts(player_id, username, username_lc UNIQUE, kdf, salt, hash, …)`. Registering
  attaches it to the player you are right now, so every company of this PC's guest profile is in the account.
- One live connection per player stays the rule: logging in on PC 2 while PC 1 is connected sends PC 1
  `left {reason:"replaced"}` and closes it (PC 1's token stays valid; it can come back later).

## Password handling
The connection is plain `ws://` today, so the password itself is never sent:
1. Client: `key = PBKDF2-HMAC-SHA256(password, salt = "silicon-overlord:" + lowercase(username), 100 000 iterations,
   32 bytes)` as 64 lowercase hex chars (`kdf: "pbkdf2-sha256-100000"`). GDScript benchmark: ~0.19–0.32 s for 100k
   iterations (Godot 4.5, desktop CPU) — fast enough, so the full 100 000 are used; it runs on a thread
   (`Net.derive_key`), the UI keeps animating. Lower-casing makes the username case-insensitive (Cyrillic too).
2. Server: stores `scrypt(bytes(key), salt = 16 random bytes per user, n = 2^14, r = 8, p = 1, 32 bytes)`
   (`hashlib.scrypt`, run in a worker thread) and compares with `hmac.compare_digest`. The derived key, the
   password and transfer codes are never stored or logged (tests read the DB files and the log to make sure).
   Transfer codes are stored as sha256.
3. Unknown usernames still cost one scrypt (`burn_time`), so timing does not reveal which names exist.
- Username: 3–20 chars: Latin letters, Cyrillic letters of the Russian alphabet plus `Ё ё І і Ї ї Є є Ґ ґ Ў ў`,
  digits, `_` (checked with `re.fullmatch`, so no trailing newline; no rare look-alikes like `Ј Ѕ Һ`, no combining
  marks). Latin and Cyrillic letters may not be mixed in one name ("Vasyа" with a Cyrillic "а"). Unique
  case-insensitively (`str.lower`, `username_lc`) **and by look-alike skeleton** (`username_skel`, UNIQUE, migration 4):
  `accounts.skeleton` folds Cyrillic letters that look like Latin ones (а→a, в→b, к→k, м→m, н→h, о→o, р→p, с→c, т→t,
  х→x, у→y, …) and `0→o`, `1→l`, `i→l`, so "МАКС" is taken when "MAKC" exists. Accounts created before migration 4
  that already look alike both keep working (the second one gets a `#<player id>` suffix in its skeleton).
- Password: at least 8 characters (checked by the client; the server only sees the key).

### Residual risk (read this)
On plain `ws://` the **derived key is a password equivalent**: someone who can sniff the traffic (same Wi-Fi,
a hostile router) can replay `accountLogin` with the captured key, or just steal the device token, which is sent in
every `hello` anyway. What the derivation does buy: the real password is not exposed (no reuse on other sites),
and a database leak gives only scrypt hashes of 256-bit random-looking keys plus sha256 of random tokens.
**Recommendation: put the server behind TLS (`wss://`, e.g. Caddy/nginx reverse proxy with Let's Encrypt) before
advertising accounts widely**, then change `Prefs.DEFAULT_URL` to `wss://…`. Nothing in the protocol has to change.
Behind a proxy the per-IP limits see the proxy address unless the server is taught to trust `X-Forwarded-For`
(not done yet: today clients connect directly).

## Rate limits (in memory, reset on restart)
| what | key | rule |
|---|---|---|
| login: wrong key | IP | 5 failures within 60 s → locked 60 s, every next lock doubles (max 1 h). **Not** reset by a success (a login to your own account must not wipe guesses at other names); strikes are forgotten after 1 h without a lock |
| login: wrong key | lowercase username **+ IP** | same rule; a success on that pair resets it |
| login: wrong key | lowercase username, all IPs | soft: after 10 failures in 10 minutes each login of that name waits 1 s more. **Never a lock**, so nobody can lock someone else's account |
| login attempts | IP | 30 per minute, right or wrong (caps scrypt CPU) |
| change password / delete: wrong key | player (only a device logged in to the account gets here) | 5 failures within 60 s → lock 60 s, doubling. Failed logins from other IPs never block the owner |
| change password / delete | player | 5 per 10 minutes, right or wrong (each costs 1–2 scrypt) |
| register: accounts created | IP | 5 per 10 minutes |
| register: attempts (incl. "That username is taken") | IP | 20 per 10 minutes (no free username oracle) |
| transfer code redeem: wrong / expired code | IP | 5 failures within 60 s → lock 60 s, doubling; **not** reset by a successful redeem |
| transfer code redeem: attempts | IP | 20 per 10 minutes, right or wrong |
| transfer code create | player | 5 per 10 minutes |
Every scrypt check **reserves** its attempt before it starts (`Limiter.acquire` → counted as a failure while it runs,
`release` after): parallel requests cannot all pass the check before the first failure is recorded, so 30 logins sent
at the same moment from one IP give at most 5 real password checks.
scrypt runs in two small thread pools: 2 threads for login / register, 1 thread for change password / delete, so
account work can never take every CPU or starve the other kind.
Locked answers: `"Too many attempts. Try again in {s} s"` (`errorKey: "err.account_locked"`, `errorParams: {s}`).
The (username, IP) limiter also counts unknown names, so a lockout does not reveal whether a name exists.
Login failures always answer `"Wrong username or password"`.
What is left: an attacker with many IPs still gets about 5 guesses per IP per minute (fewer after the doubling) on a
name; with a decent password and scrypt that is far from enough, but there is no captcha.

## Token rules
- **Register**: links the current player, and **rotates** this device's token (the answer carries the new one;
  stray copies of the old guest token stop working).
- **Login**: issues a **new** device token for the account's player (several devices allowed). The token this PC
  used before is revoked — except when it belongs to a *guest that owns companies*: then it is kept and the client
  saves it as `guest_token`, so **Log out** brings that guest profile back (`guestKept: true` in the answer).
  An empty guest's token is simply revoked.
- **Logout**: revokes this device's token; the PC becomes the saved guest (`guestToken`) or a fresh guest.
- **Change password**: needs the old password; signs out every *other* device and drops live transfer codes.
- **Delete account** (password confirm): erases username + password hash, signs out other devices; the player and
  its companies stay on this PC as a guest. The username becomes free.
- Login, logout and transfer-code redeem are **lobby only** (`"Leave the company first"`), register / change
  password / delete / transfer-code create also work inside a company.

## Transfer code
`transferCreate` (guest or account) → 8 characters from `ABCDEFGHJKMNPQRSTUVWXYZ23456789` shown as `ABCD-EFGH`,
valid **10 minutes**, **single use** (a wrong-but-existing expired code is consumed too), one live code per player
(a new one replaces the old). `transferRedeem {code}` on another PC (any case, dash/spaces optional) gives that PC a
new device token of the same player — for a guest that is the only way to move without an account. Anyone who
sees the code can take over the profile within 10 minutes: the UI says so ("don't show it on stream").

## Protocol (details in docs/PROTOCOL.md §21 and docs/ACTIONS.md "Accounts")
- `welcome.account` = `{username}` or `null` (new field, old clients ignore it).
- Lobby `act` actions: `accountStatus`, `accountRegister {username, key, kdf}`, `accountLogin {username, key, kdf}`,
  `accountLogout {guestToken?}`, `accountChangePassword {oldKey, newKey}`, `accountDelete {key}`,
  `transferCreate {}`, `transferRedeem {code}`.
- Identity switches (login, logout, redeem) send a **new `welcome`** (new playerId / token / lastCompany / account)
  **before** the `res` of the action, on the same socket. Clients just handle `welcome` again.

## Client
- Title menu: an **account chip** next to the nickname (Guest / username) opens the **Account** page; Settings has an
  **Account** tab with the same panel. Guest view: "Your progress is tied to this PC…" + Create account / Log in /
  Use transfer code / Create transfer code. Logged in: username, Create transfer code (big code + countdown + Copy),
  Change password, Log out, Delete account. Masked password fields with a show toggle, Enter moves to the next field
  / submits, Esc goes back, errors in a red line under the form. Texts in 11 languages (`ui/i18n/account.json`).
- `user://profile.cfg [profile]`: `token` (device token), `account` (username shown while offline), `guest_token`
  (only while a guest with companies is "parked" by a login).

## Known limits
- Rate limits are per process and in memory (a restart clears them). Behind NAT, people share one IP: a neighbour's
  wrong logins can lock the shared IP for logins for a while (not the logged-in owner's password change / delete).
- No e-mail / password reset: a forgotten password can only be bypassed with a transfer code from a PC that is still
  logged in. Write the password down.
- Two PCs of the same account cannot play at the same moment (one live connection per player).
