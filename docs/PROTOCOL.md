# Wire protocol v1 (WebSocket, JSON text frames)

## Changes (server implementation, v1 — read this first)
Everything below the table keeps working as written; these are additions/clarifications made by the server.
1. **Lua tables in JSON.** A Lua table whose keys are exactly 1..n becomes a JSON array; any other table becomes
   an object with string keys (`owners` is keyed by `"<userId>"`). **An empty table is always sent as `{}`** (Lua
   cannot tell an empty list from an empty map) — clients must treat `{}` and `[]` alike as "empty collection".
   Integral numbers are sent as integers; NaN → 0, ±inf → ±1.7976931348623157e308. Client → server: objects
   become string-keyed tables, arrays become 1-based sequences, `null` members are dropped.
2. **sections**: `data` always contains `stateVersion`. A key whose value is `null` was cleared on the server
   (e.g. `loan` after repayment) — delete it from the cache. The server sends sections right after every
   action (before its `res`) and after every simulated day (≤ 4 per second at speed 8).
3. **welcome** has `lastCompany` (company id or null): if not null, `resume` will work → show "Continue".
4. **joined.you** = `{userId, role, name, color}`; members items = `{userId, name, color, role, title, sharePercent,
   online}`. `role` is "Founder" or "CoFounder". Departed partners are not listed.
5. **notify** = `{kind, title, body, category, sound, key, params, bodyKey, bodyParams}` (localization keys, see 18): `kind` ∈ info/success/warning/error (derived from the Roblox
   sound), `category` = original Roblox notification kind (e.g. Research, Report, Goal, Mission, Governance,
   Award, Achievement, HR, Legacy), `sound` = Roblox sound name (Success, Alert, Error, Launch, ...) or null.
6. New server → client frames:
   - `profile {profile}` — player profile (not company): `legacy {points, perks, challenge, ...}`, `tokenState
     {tokens, missions, ...}` (daily missions / token shop), `companyId`. Sent after hello, after joining and whenever it changes.
   - `boards {money:[{name, value, companyId}], devices:[...]}` — leaderboards (top 10 by cash and by launched
     devices, all companies on this server), sent on join and every 30 s.
7. **left.reason**: `"leave"` (you sent leave), `"leftCompany"` (act leaveCompany: ownership given up), `"sold"`
   (company sold, has `points`), `"replaced"` (same token connected from another window; the old socket closes).
8. **join** accepts the room code with or without the dash, any case (`abc123`, `ABC-123`), and also personal
   invite codes created by the `createInvite` action (6 chars, may contain `L`; only while that company is loaded).
   - Co-founder company: owners re-enter; a new player becomes **CoFounder** with the default ShareRules permissions
     (everything except CorporateGovernance). Share: the first partner gets the founder's reserved stake (50/40/30),
     later partners 10 % from the founder. Max 4 owners ("No free seats").
   - **Solo company: only its owner can enter** (others get `error`). A solo founder can still bring a partner with a
     personal invite code (`createInvite`), which turns the company into a co-founder company (Roblox rule).
9. **leave** only detaches you (ownership kept, company keeps its state, `resume` brings you back). To give up
   ownership use `act leaveCompany`.
10. **create.company** may also contain `shape` (hex/circle/diamond/triangle/ring/square) and `founderShare`
    (co-founder mode: 50/60/70, default 50). Names: player 1–20 chars, company 1–24 chars, letters of any
    alphabet (Cyrillic is fine), digits, spaces and `- . _ ' & !`.
11. **speed**: any member may change it. A rejected speed answers `error`. A company loaded from disk starts at
    speed 1 (Roblox rule). The clock only runs while at least one member is online.
12. **peers**: `list` contains every member with a known position, **including yourself** (filter by your userId).
    Sent at most 10 times per second and only when something moved / someone left.
13. **act** errors: `"Unknown action"` (not in docs/ACTIONS.md), `"Missing permission: X"`, `"Too many requests"`,
    `"Internal error"` (a Lua error inside the rules; logged on the server). Lobby actions of the Roblox router
    (createCompany, joinCompany, leaveLobby, lobbyStatus, playInvite) are the `create` / `join` / `leave` messages.
14. **Limits**: a frame > 64 KB closes the connection (WebSocket code 1009). Rate limit per connection: 30 burst,
    10 per second for all messages except `pos`/`ping` (own bucket: 20 burst, 15/s, excess silently dropped).
    `chat` text is trimmed to 200 characters (control characters removed).
15. `GET /health` on the same port answers `200 ok` (for monitoring). The WebSocket endpoint is `/ws` (also `/`).
16. `error {message}` is used for every failed non-act message (bad JSON, hello first, unknown code, ...).
17. A player may own several companies (unlike Roblox): `create` always founds a new one (max one per 5 s per
    connection) and `resume` returns to the company you entered last; older ones are entered by their room code.
    One live connection per token: a new `hello` with the same token replaces the old socket.
18. **Localization (iteration 2).** English texts keep coming as before, plus stable keys the client can translate
    (key table + rules: docs/LOCALE_KEYS.md, generated from the server sources):
    - `notify`: `key`/`params` for `title`, `bodyKey`/`bodyParams` for `body` (`null` when the text is unknown);
      optional `paramKeys`/`bodyParamKeys` = `{param: key}` when a param is a known data name.
    - failed `res`: `errorKey`, `errorParams` (+ optional `errorParamKeys`); `error` frames: `key`, `params`.
    - `state.news[]` items: `key`/`params`, `bodyKey`/`bodyParams` (or `bodyParts` for a launch review).
    - `products[id].reviews[]`: `headlineKey`/`headlineParams`, `bodyParts:[{key, params}]`.
19. **Iteration 2 state**: `production.crates` (finished goods waiting to ship), `challenges` (mini-game cooldowns),
    `employees.list[].station` / `marketSalary`, `production.lines[].location` — see docs/ACTIONS.md
    "Manual shipping, second floor, challenges" and "Employees". `challenges` is a new top-level section key.

20. **Iteration 3 (story start)** — details in docs/ACTIONS.md "Story & repairs":
    - `create.company.storyMode` (bool, default false): true = story start (small cash, clock paused until chapter 4,
      repair orders); false/missing = quick start exactly as before.
    - New top-level state sections `story` and `repairs` (in the snapshot and in `sections`, like `challenges`).
      Old saves load with `story.done = true`.
    - While a story company is in chapters 0–3 the clock does not run; `speed` frames / `setSpeed` answer
      `error {message:"Story: time starts at chapter 4", key:"err.story_clock_paused"}`.
    - New actions: `repairTake`, `repairFinish`, `repairReturn`, `storyEvent`, `storySkip` (company) and the lobby
      action `listMyCompanies` (allowed right after `hello`, no company needed) → your company slots.
    - New `notify.key`s `story.*` (step done, chapter card, investor, complete, skipped, repair new/paid); `notify` may
      also carry `paramKeys` / `bodyParamKeys` set by the server.

21. **Accounts** (docs/ACCOUNTS.md; fully backward compatible — a client that never sends these keeps using its
    device token exactly as before):
    - `welcome.account` = `{username}` or `null`. Device tokens are now stored hashed and a player may have several
      (several PCs). `hello` is unchanged.
    - New lobby `act` actions (allowed right after `hello`; login / logout / redeem only outside a company):
      `accountStatus`, `accountRegister`, `accountLogin`, `accountLogout`, `accountChangePassword`, `accountDelete`,
      `transferCreate`, `transferRedeem` — payloads in docs/ACTIONS.md "Accounts". Passwords are never sent: `key` =
      PBKDF2-HMAC-SHA256(password, "silicon-overlord:" + lowercase(username), 100000) as 64 hex chars.
    - Login / logout / transfer redeem switch the player of this socket: the server sends a fresh **`welcome`**
      (new playerId, token, name, lastCompany, account) and then the `res`. If that player was online elsewhere the
      other socket gets `left {reason:"replaced"}`.
    - Errors: login always `"Wrong username or password"`; lockouts `"Too many attempts. Try again in {s} s"` with
      `errorKey "err.account_locked"`, `errorParams {s}`. `accountRegister` attempts (also "That username is taken"),
      `accountChangePassword` / `accountDelete` (also with the right key) and `transferRedeem` attempts are capped
      too (table in docs/ACCOUNTS.md "Rate limits"); a username is never locked for everyone. Wire format unchanged.
22. **0.5.0 (interior editor, expansions, production processes)** — fully backward compatible: a 0.4.0 client simply
    ignores the new data and its old actions (`buyFurniture` & co., `buildRoom`) keep working.
    - New replicated top-level section **`interior`** (in snapshots, in `sections` after interior actions, monthly, and
      with the quarterly full refresh). New state fields: `hq.expansions {id: {level, builtDay}}`,
      `production.lines[].process` (+ `processFrom`, `processUntil` after a switch). Old saves are migrated on load.
    - New actions: `interiorPlace`, `interiorMove`, `interiorRemove`, `interiorPaint`, `interiorTheme`, `interiorLight`,
      `buildExpansion`, `getExpansionCatalog`, `setLineProcess` — docs/ACTIONS.md "Interior", "Expansions",
      "Production processes". They share an extra per-connection bucket (12 burst, 4/s): `"Too many build actions, slow down"`.

Endpoint: `ws://<host>:7350/ws` (later `wss://` behind a reverse proxy). One JSON object per frame,
field `t` = message type. Numbers are JSON numbers; Lua maps with non-string keys are sent with string keys.

## Client → server
| t | fields | reply |
|---|---|---|
| hello | v:1, name, token? (saved from a previous welcome) | welcome {playerId, token, name} |
| create | company:{name, colorA:"#RRGGBB", colorB, mode:"solo"/"cofounder", storyMode?:bool} | joined + snapshot |
| join | code:"ABC-123" | joined + snapshot, or error |
| resume | — (rejoin last company of this token) | joined + snapshot, or error |
| leave | — | left |
| act | id:int, action:String, args:Object | res {id, ok, data?, error?} |
| speed | speed: 0/1/2/4/8 | (sections time) |
| pos | p:[x,y,z], yaw, pitch, anim:String (≤10 Hz) | broadcast peers |
| chat | text (≤200 chars) | broadcast chat |
| ping | n | pong {n} |

`act.action` uses the Roblox ActionRouter names (startResearch, createBlueprint, updateBlueprint,
publishBlueprint, launchProduct, setPrice, hire, buildRoom, upgradeHQ, ...) with the same payloads.

## Server → client
| t | fields |
|---|---|
| welcome | playerId:int, token:String, name, lastCompany, account:{username}\|null |
| joined | code, companyId, you:{userId, role}, members:[{userId,name,color,role,online}] |
| snapshot | state: full CompanyState |
| sections | data:{sectionKey: value} — top-level CompanyState keys that changed (replace whole key) |
| res | id, ok, data?, error?, errorKey?, errorParams? |
| notify | kind ("info"/"success"/"warning"/"error"), title, body, category, sound, key, params, bodyKey, bodyParams |
| members | list as in joined |
| peers | list:[{userId, name, color, p, yaw, pitch, anim}] |
| chat | userId, name, text |
| left | reason |
| error | message, key, params |
| pong | n |

Room codes: 6 chars from `ABCDEFGHJKMNPQRSTUVWXYZ23456789`, shown as `ABC-123`.
