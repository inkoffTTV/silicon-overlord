# Silicon Overlord Online — architecture

Standalone online version of the Roblox game in /home/user/PhoneTycoon (same rules, new client).

```
shared-luau/   game rules, data and balance (copied from the Roblox project's src/shared).
               Pure Luau modules: Domain/*, Data/*, Config/*. THE single source of game rules.
tools/         luau_strip.py (Luau -> plain Lua), lua_shim.lua (Roblox globals for pure modules)
server/        Python 3.11+ authoritative server: lupa (Lua VM) runs shared-luau,
               websockets for clients, SQLite saves, room codes. Runs on the Linux VPS.
client/        Godot 4.5 project (GDScript, Forward+). First-person 3D world, UI. Talks to the
               server over WebSocket only; never decides game outcomes itself.
docs/          this file, PROTOCOL.md (wire format), VISUAL_STYLE.md, DEPLOY.md
```

## Ownership (parallel work)
| Area | Owner | Paths |
|---|---|---|
| Server, protocol implementation, saves, deploy | SERVER agent | server/**, docs/DEPLOY.md |
| 3D world, player controller, look/post-processing, props, avatars of other players | WORLD agent | client/world/**, client/player/**, client/fx/**, client/tools/shot*, docs/VISUAL_STYLE.md |
| Menus, HUD, screens (designer, research, market...), networking client, phone 3D preview model | UI agent | client/ui/**, client/net/**, client/phone/** |
| Shared skeleton (project.godot, main.tscn, core/*) | lead | client/project.godot, client/main.tscn, client/core/** |

Rules: do not edit another owner's paths. If you need something there, add a TODO in docs/REQUESTS.md.

## Client contracts (between WORLD and UI)
- `res://main.tscn`: Main (Node3D) → World (instance of res://world/world.tscn), Player (res://player/player.tscn),
  UI (CanvasLayer, res://ui/ui_root.tscn). Autoloads: `Inputs` (core/inputs.gd), `Bus` (core/bus.gd),
  `Net` (net/net.gd, UI agent), `Game` (core/game.gd: replicated state cache).
- `Bus` signals (core/bus.gd) are the ONLY coupling between world and UI:
  - `interact(kind: String, id: String)` — player pressed E on an interactable. kinds: "pc_design",
    "whiteboard_research", "workbench_production", "phone_shelf", "door_exit", "board_company", "stage_launch".
  - `ui_modal_changed(open: bool)` — UI opened/closed a full-screen screen; player releases/captures the mouse
    and stops moving while open.
  - `state_changed(keys: Array)` — Game cache updated (emitted by Game).
  - `notify(kind: String, title: String, body: String)`
  - `launch_show(product_id: String)` — UI asks the world to play the launch-on-stage sequence.
  - `world_rebuild()` — HQ level / rooms changed.
- Interactables: any node in group "interactable" with metadata `kind`, `id`, `prompt` (shown by UI as
  "[E] prompt"). Player raycasts and emits `Bus.interact`, and `Bus.focus_changed(prompt or "")`.

## Server
Authoritative. Each company = session with a Lua CompanyState, ticking days at speed 0/1/2/4/8
(same Balance as Roblox). Clients send actions (same names/payloads as the Roblox ActionRouter) and
receive snapshot + changed sections. See PROTOCOL.md.

## Iteration 2 contracts (production you can see, employees, manual shipping)

### State additions (server, Luau shared rules)
- `production.crates`: array of `{id, productId, units, day}` — finished batches waiting in the garage/warehouse.
  Production output goes HERE first (not straight into `products[id].inventory`). Units are sellable only after shipping.
- Action `shipCrate {crateId}` → moves the crate's units into `products[productId].inventory`, removes the crate,
  returns `{units, productId}`. Any member may ship. Fails if crate unknown.
- Auto-shipping: crates older than `Balance.Production.autoShipDays` (default 7 game days) ship automatically
  (so an AFK company still sells), and instantly once the company owns a LogisticsCenter room. Manual shipping is
  the fast path and gives `Balance.Production.manualShipBonus` (default +5% units, "careful handling") — small but real.
- "Second floor" of the garage = room `AssemblyLine` (bought with `buildRoom {roomId:"AssemblyLine"}`), allowed at
  HQ level 1. Production lines (`buildLine`) require it. World shows the upper floor locked until `hq.rooms.AssemblyLine`.
- Employees already exist: `employees.list` (hired) and `employees.candidates` (or whatever the state uses — see
  docs/ACTIONS.md hire/fire). Each employee gets a stable `station` field the world uses to place them:
  "design" (PC desks), "research" (whiteboard/lab), "assembly" (workbench / upstairs lines), "office" (generic desk).

### World interactables (new kinds)
- `crate` (id = crate id) — a grabbable crate RigidBody3D; carrying it into the van's cargo area ships it
  (world calls `Net.act("shipCrate", {crateId})`, never decides itself). E on a crate shows "Carry to the van".
- `van` — the delivery van at the garage door (prompt "Ship all crates" → UI confirm → shipCrate for each).
- `stairs_locked` — stairs/trapdoor to the second floor while not bought → UI "Buy the second floor" dialog
  (cost from server data) → `buildRoom AssemblyLine`.
- `job_board` — cork board / laptop with CVs → UI Employees screen (hire/fire/salary).
- `production_line` (id = line id), upstairs — UI production screen focused on that line.

### Bus additions
- `ship_feedback(crate_id: String, ok: bool)` — world plays a sound/flash when a shipment is accepted.

## Iteration 2b: challenges (mini-games), audio, spoken chat
- Ownership: AUDIO agent owns client/audio/** (autoload `Sfx`, API in client/audio/sfx.gd) and the chat→voice feature.
- Challenges are short skill mini-games that speed things up; the server caps rewards (anti-cheat).
  Server action `challengeReward {kind, targetId, score}` (score 0..1 computed by the client mini-game) →
  applies a capped bonus and returns `{applied, cooldownDays}`. kinds:
  - "research" (sit at the PC/whiteboard while a tech is researching) → research progress boost on targetId (techId)
  - "design" (bug hunt / polish while a product is in development) → project quality or bug fix on targetId (projectId)
  - "assembly" (QC inspection at the bench/line) → fewer defects / small output bonus for targetId (lineId or productId)
  - "negotiation" (shipping van / supplier phone call) → small price/cost bonus
  Caps: per kind per company a cooldown in game days and max bonus — defined in Balance.Challenges.
- World: interactable kinds `pc_challenge` (sit at the PC: camera moves to the chair, player seated, Esc stands up),
  `whiteboard_challenge`, `line_qc`. On sit, world emits Bus.interact(kind, id); UI opens the mini-game overlay and
  on finish calls Net.act("challengeReward", ...), then Bus.ui_modal_changed(false) → world stands the player up.
- Spoken chat (like R.E.P.O): every chat line is spoken aloud by the speaker's character: OS text-to-speech
  (DisplayServer.tts_*; Windows SAPI has Russian/English voices), per-player pitch/rate from userId, volume by distance
  to the speaker's avatar, speech bubble + mouth/jaw anim on the avatar (world exposes `world.avatar_talk(user_id, seconds)`).
  Setting to mute/adjust voice volume. Own messages are spoken from the local player.
