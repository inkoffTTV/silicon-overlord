# Story start: "From the repair shop to a phone company" (iteration 3)

The user's long-held idea: the game begins as a story-driven CO-OP TUTORIAL. The players are friends who run a small
electronics repair shop in the garage. Repairing other people's phones teaches every mechanic; they notice the same
flaws in every phone, decide to build their own, and the repair shop smoothly turns into a phone company.
After the last chapter the normal sandbox continues — nothing is lost, the garage is the same place, the sign changes.

## Player experience
- New company → choose **Story start (recommended)** or **Quick start** (current behaviour). Joining friends join the
  story at its current chapter. Old saves and quick starts have `story.done = true`.
- Story start: company cash starts small (`Balance.Story.startCash`, e.g. 6 000) and the game clock is PAUSED until
  chapter 4 (no rivals, no salaries, no rent pressure while learning). Speed buttons show "Story: time starts at chapter 4".
- At the start of chapter 4 an investor (friend's uncle / a bank — decide in the script) believes in them:
  cash is topped up to the normal start cash (`Balance.Start` value used by quick start), clock starts.
- The garage has a "PHONE REPAIR" sign, a customer counter with a bell, a repair bench with a magnifier lamp,
  shelves of broken devices. Customers (original NPCs) walk in, put a broken device on the counter, wait, pay, leave.
- When the story ends: short cutscene — the old sign is taken down, the new company sign/logo goes up (company colours),
  the counter becomes a small reception/showroom. Repair orders stay available as optional side income in the garage
  (less frequent, they stop once HQ level ≥ 2).

## Chapters (server is authoritative; step completion comes from real actions)
| # | Title (RU / EN) | Goal steps (examples) | Teaches |
|---|---|---|---|
| 0 | «Мастерская» / "The Workshop" | intro cutscene; open the shop door; turn on the lights | moving, E, flashlight |
| 1 | «Первый клиент» / "First Customer" | take the device from the counter → carry to the repair bench → repair mini-game → return to counter → get paid (×2 orders; co-op: one takes orders, one repairs) | physics grab, repair, money |
| 2 | «Запчасти» / "Spare Parts" | out of screens/batteries → call the supplier phone → buy parts (Purchasing) → finish the waiting repair | purchasing, materials |
| 3 | «Одна и та же поломка» / "The Same Fault" | notice the pattern (dialogue) → whiteboard: start the first research → (optional) whiteboard challenge | research, challenges |
| 4 | «Свой телефон» / "Our Own Phone" | investor scene → PC: design the first phone (guided defaults) → publish → development on the bench | design studio, development |
| 5 | «Первая партия» / "First Batch" | hand-assembly production on the bench → crates → carry to the van → ship | production, crates, van |
| 6 | «Презентация» / "Launch Night" | launch on stage → critics card → sign changes → story complete | launch, reviews |

## Server contract
- `state.story = { done: bool, chapter: int, step: string, stepsDone: {stepId: true}, flags: {}, startedDay }`
  (CompanyFactory migration: existing companies `done = true`).
- `state.repairs = { orders: [ {id, customer, device, fault, partId?, reward, status: "waiting"|"inRepair"|"ready"|"paid", createdDay} ], done: int }`
- Actions: `createCompany` gets `storyMode: true|false` (default false for old clients) — see PROTOCOL changes.
  `repairTake {orderId}`, `repairFinish {orderId, score}` (score 0..1 from the mini-game; reward × quality, capped;
  may consume a part from inventory: `parts.screen`, `parts.battery`, ... bought via Purchasing as resources
  `repair_screen`, `repair_battery`, `repair_port`), `repairReturn {orderId}` (pays), `storyEvent {id}` for purely
  client-side steps that the server cannot observe (open door, lights on, cutscene seen) — whitelisted ids only,
  each counts once. `storySkip {}` (owner only) completes the story instantly with the quick-start economy.
- Step completion hooks into existing actions (buyResources, startResearch, createBlueprint, publishBlueprint,
  queueProduction, shipCrate, launchProduct). Each completed step → `notify` with key `story.step.done` and the state
  section `story` replicated. Chapter change → notify `story.chapter` (client shows the chapter card).
- Clock paused while `story.done == false and story.chapter < 4` (CompanyService tick), speed actions rejected with a
  friendly reason.

## Client contract
- Story texts live in `client/ui/data/story/<lang>.json` (NARRATIVE agent): chapter titles, objectives, dialogue
  lines `{id, speaker, text}`, NPC customer lines, cutscene captions. All 11 languages; RU and EN carefully written.
- UI: objective tracker (top-left, current chapter + steps with checkmarks), dialogue subtitles (bottom, speaker name,
  typewriter, spoken via `Sfx.speak` with a per-character voice), chapter title cards, repair mini-game
  (Bus.interact("repair_bench", orderId)), "Skip story" in pause menu for the owner (confirm).
- World: `story_stage(chapter, step)` driven by `Game.state.story`; interactables `shop_door`, `light_switch`,
  `counter` (id = orderId of the device lying there), `repair_bench`; NPC customers spawned from `repairs.orders`;
  broken devices are grabbable props tagged with orderId; the sign swap cutscene; Bus signal `story_cutscene(id)`.
- New Bus signals (lead adds): `story_cutscene(id: String)`, `story_dialogue(line_id: String)`.

## Main menu "like a separate game"
The menu must feel like a real game's title screen, not a form:
- Full-screen 3D title scene (WORLD agent: `res://world/title/title_scene.tscn`): the garage repair shop from the
  street at night/rain, neon "PHONE REPAIR" sign flickering, warm light inside, slow camera dolly, friends' silhouettes
  working inside. Lo-fi post FX like in-game.
- UI agent: big game-style menu over it: logo, **Play** (→ company slots: your companies with name, date, money, last
  played, Continue; New company → Story / Quick; Join by code), **Settings**, **Credits**, **Quit**; profile/nickname
  chip; server status dot; version number + "update ready" from Updater. Keyboard/gamepad navigation, hover sounds,
  animated transitions. Loading screen with tips when entering a company.
- Server: action `listMyCompanies {}` (lobby-level, after hello) → `[{companyId, code, name, date, cash, role, lastPlayed}]`.
