# Actions (`act`) — names, payloads, results

Send `{"t":"act","id":<int>,"action":"<name>","args":{...}}`. The server replies
`{"t":"res","id":<same>,"ok":true,"data":...}` or `{"t":"res","id":..,"ok":false,"error":"<text>"}`.
Names and payloads are exactly the Roblox `ActionRouter` ones (server/lua/ActionRouter.lua is the port).

General rules
- `args` is a JSON object. Missing fields are treated like in Roblox (`tostring(nil)` = `"nil"`, `tonumber` → 0/-1),
  so the action usually fails validation with a readable `error`.
- State changes are NOT in `res.data`; they arrive as `sections` frames (whole top-level keys) right before
  the `res` frame. Use `res` only for the result/feedback.
- Lua tables become JSON per PROTOCOL.md: a sequence `1..n` → array, anything else → object with string keys,
  an **empty table → `{}`** (client must treat `{}` and `[]` the same: "empty collection").
- `data` is omitted (or `null`) when the action returns nothing.
- **Permission** column: owner permission needed (`state.owners[<userId>].permissions[...]`). `—` = any member.
  Missing permission → `ok:false, error:"Missing permission: X"`.
- **Approval**: in a co-founder company (≥2 active owners) a spend ≥ 30 % of cash or ≥ $5M is not executed
  immediately: `res` is `ok:true, data:{approvalId, pending:true}` and an entry appears in `state.approvals`.
  Other owners answer with `respondApproval`. When everybody approved, the action runs and a `notify` is sent.
  Actions with a cost estimate (can need approval): upgradeHQ, buildRoom, buildLine, upgradeLine, developOS,
  enableCloudService, takeLoan, takeBankLoan, unlockRegion, teamParty, buyFurniture, buyoutRival,
  queueProduction, buyResources, interiorPlace, interiorPaint, interiorTheme, buildExpansion, setLineProcess (0.5.0).
- Rate limit: 30 requests burst, refill 10/s per connection (`error:"Too many requests"`).
- An action that would need approval returns immediately with `{approvalId, pending:true}`; when the last owner
  approves, the `respondApproval` call returns the executed action's `data` (or its error), and everybody gets a
  `notify` "Request approved and executed" / "Approved request failed".
- Name rules (Validate.name, UTF-8 aware): blueprint names 1–32, renameCompany / designChip 1–24 characters
  (not bytes) of any letters (Cyrillic is fine), digits, space and `- . _ ' & !`.
- `res` of a successful action arrives after the `sections` it caused; a failed action changes nothing.
- A failed `res` also carries `errorKey` + `errorParams` (localization, see docs/LOCALE_KEYS.md) when the text is known;
  always keep showing `error` (English) as the fallback.

## Time / misc
| action | perm | args | data on success |
|---|---|---|---|
| setSpeed | — | `{speed: 0\|1\|2\|4\|8}` | — (same as the `speed` frame) |
| getSnapshot | — | `{}` | — (server sends a fresh `snapshot` frame) |
| setTutorialStep | — | `{step: 1..20}` (only increases) | — |
| getAudit | — | `{}` | array of audit entries `{transactionId, initiatorUserId, operationType, amount, timestamp, previousStateVersion, newStateVersion, note}` (`note` ≤ 120 chars, clipped server-side; older oversized notes are clipped on load) |

## Research
| action | perm | args | data |
|---|---|---|---|
| startResearch | Research | `{techId}` e.g. `"arch_arm_2"` | `{cost, days}` |
| joinResearch | Research | `{techId}` | — |
| cancelResearch | Research | `{techId}` | `{refund}` |
| patentTech | Research | `{techId}` (must be unlocked) | `{cost}` |
| licenseTech | CorporateGovernance | `{techId, npcId}` | `{incomePerQuarter}` |
| boostResearch | Research | `{techId, points}` (points multiple of 100) | `{progress}` |

## Design (blueprints, chips)
| action | perm | args | data |
|---|---|---|---|
| createBlueprint | Design | `{name, subtype}` e.g. `{"name":"Nova","subtype":"MidrangePhone"}` | `{id}` |
| copyBlueprint | Design | `{id, name}` | `{id}` |
| deleteBlueprint | Design | `{id}` | — |
| lockBlueprint / unlockBlueprint | Design | `{id}` (edit lock for co-founders, no audit entry) | — |
| updateBlueprint | Design | `{id, slots?:{Slot:componentId}, options?:{...}, priceUSD?, name?}` (only the given fields change; `options` keys as in `blueprint.options`) | evaluation (same as evaluateBlueprint) |
| evaluateBlueprint | — | `{id, slots?, options?, priceUSD?}` read-only preview, nothing saved | evaluation `{ratings:{overall, performance, ...}, cost:{total, ...}, issues:[{code, severity:"error"/"warning", description, ...}], valid, components:{Slot: component}}` (RatingEngine.EvalResult) |
| publishBlueprint | Design | `{id}` | `{productId, projectId?, days}` (product enters Development; a project appears in `state.projects`) |
| designChip | Design | `{kind:"CPU"\|"GPU", name, architecture, processNodeNm, boostClockGHz, pCores?, eCores?, l3MB?, npuTops?, computeUnits?, vramGB?, busWidthBits?, formFactor?, memoryController?}` | `{id, cost}` |

Example phone slots (all available at start):
`{"SoC":"soc_arm_g1_plus","RAM":"ram_lp4x_g1","Storage":"ufs_g1","Display":"disp_phone_lcd_g1","Camera":"cam_dual_g1","Battery":"bat_phone_l_g1","Charger":"charger_25","Cooling":"cool_phone_graphite_g1","Chassis":"chassis_phone_aluminum","OS":"os_mobile_g1"}`

## Development projects
| action | perm | args | data |
|---|---|---|---|
| finishProjectNow | Design | `{projectId}` (costs research points) | `{cost, note}` |
| cancelProject | Design | `{projectId}` | `{spent}` |
| addProjectQuality | Design | `{projectId}` | `{quality}` |
| fixProjectBug | Design | `{projectId}` | `{bugs, toughBugs}` |

## Products
| action | perm | args | data |
|---|---|---|---|
| setPrice | Pricing | `{productId, price, regionMult?:{NA:1.1,...}}` | — |
| setRegions | Marketing | `{productId, regions:{NA:true,EU:true,...}}` | — |
| setMarketing | Marketing | `{productId, weeklyUSD, positioning?}` positioning ∈ Value/Performance/Design/... | — |
| launchProduct | Marketing | `{productId, positioning?}` (needs inventory > 0) | `{reviews:[{score, body, outlet...}], score}` |
| discontinueProduct | AssetManagement | `{productId}` | `{salvage}` |
| recallProduct | CorporateGovernance | `{productId, option}` | `{cost, affected}` |

## Production / supply
| action | perm | args | data |
|---|---|---|---|
| buildLine | Construction | `{kind}`: Assembly / CPUFab / GPUFab / DisplayFab / BatteryFab (fabs need research; Assembly needs the second floor = room AssemblyLine) | `{id, cost}` |
| upgradeLine | Construction | `{lineId}` | `{cost, processCost}` — 0.5.0: the line keeps its `process` (and a running switch: `processFrom`/`processUntil`); `processCost` = setup difference of that process between the new and the old level (included in `cost`, 0 for `hand` and fab lines) |
| queueProduction | Manufacturing | `{productId, lineId, quantity}` e.g. lineId `"line_1"`, quantity ≥ 100 | `{id, unitCost, estimatedCost}` |
| cancelProduction | Manufacturing | `{jobId}` | — |
| setQcLevel | Manufacturing | `{level}` 0..3 | — |
| resolveIncident | Manufacturing | `{incidentId, option}` | `{cost}` — 0.5.0: no option ends a process switch early (`downUntilDay` never drops below `processUntil`) |
| setFactoryLayout | Manufacturing | `{cells:[{x,y,kind}]}` (≤ 64) | `{score}` |
| queueFabJob | Manufacturing | `{lineId, componentId, wafers}` | `{id}` |
| sellComponents | Finance | `{offerId, componentId}` | `{units, revenue}` |
| buyResources | Manufacturing | `{resourceId, units}` (a pending negotiation `supplierDiscount` is applied and used up) | `{cost}` |
| signContract | Manufacturing | `{supplierId, resourceId, unitsPerWeek, weeks}` | `{id, pricePerUnit}` |
| cancelContract | Manufacturing | `{contractId}` | `{penalty}` |

## HQ / office (build mode)
| action | perm | args | data |
|---|---|---|---|
| upgradeHQ | Construction | `{}` | `{level, cost}` |
| buildRoom | Construction | `{roomId}` | `{level, cost}` |
| buyFurniture | Construction | `{itemId, spot?:{x,y}}` | `{placed, comfort, productivity}` |
| sellFurniture | Construction | `{itemId}` | `{refund}` |
| moveFurniture | Construction | `{uid:number, spot:{x,y}}` | placed record |
| removeFurniture | Construction | `{uid}` or `{spot:{x,y}, layer:"floor"}` | `{stored:[...]}` |
| placeFromStorage | Construction | `{itemId, spot?:{x,y}}` | `{placed}` |
| paintFurniture | Construction | `{uid, color}` | `{uid, color}` |
| autoPlace | Construction | `{}` | `{placed:n}` |

## Staff
| action | perm | args | data |
|---|---|---|---|
| hire | Hiring | `{candidateId}` (from `state.employees.candidates[].id`) | `{employee, placedDesk}` (`employee` = the hired record, see Employees below) |
| fire | Hiring | `{employeeId}` (from `state.employees.list[].id`) | `{severance}` (2 monthly salaries, paid now) |
| setSalary | Hiring | `{employeeId, salary}` monthly USD, must be within 50 %..300 % of `marketSalary` | — |
| setPerks | Hiring | `{monthly}` | — |
| teamParty | Hiring | `{}` | `{cost, morale}` |
| rerollCandidates | Hiring | `{}` (costs 20 research points) | `{candidates:n}` |
| setAutoHire | Hiring | `{on:bool}` | `{autoHire}` |

## Ecosystem
| action | perm | args | data |
|---|---|---|---|
| developOS | Design | `{platform}` | `{cost, os}` |
| setCommission | Finance | `{commission}` | — |
| enableCloudService | Construction | `{service}` | `{cost}` |
| setSubscriptionPrice | Finance | `{price}` | — |
| setLockIn | CorporateGovernance | `{lockIn}` | — |

## Finance / world
| action | perm | args | data |
|---|---|---|---|
| takeLoan | Finance | `{amount}` | as takeBankLoan |
| repayLoan | Finance | `{amount}` | as repayBankLoan |
| takeBankLoan | Finance | `{months, amount}` e.g. `{months:12, amount:100000}` | `{loan}` |
| repayBankLoan | Finance | `{}` | `{repaid}` |
| unlockRegion | Finance | `{region}` e.g. `"EMERGING"` | `{cost}` |
| buyoutRival | CorporateGovernance | `{npcId}` | `{price}` |
| setSpecialization | CorporateGovernance | `{title, path}` | — |
| claimDaily | — | `{}` | `{reward, dayIndex, streak, detail, streakBonus}` |

## Empire (late game)
| action | perm | args | data |
|---|---|---|---|
| buildFactory | Construction | `{kind: chip/display/battery}` | `{level, cost}` |
| upgradeFactory | Construction | `{kind}` | `{level, cost}` |
| launchService | Construction | `{id:"cloud"\|"music"\|"arcade"\|"tv"\|"ai"}` | `{cost}` |
| startMegaproject | Construction | `{id:"own_ai"\|"satellite"\|"quantum"\|"lunar"\|"mars"}` | `{cost, months}` |

## Co-founders / governance
| action | perm | args | data |
|---|---|---|---|
| createInvite | CorporateGovernance | `{sharePercent?:50\|40\|30 (first partner) or 5..30, title?:"CEO"\|"CTO", targetUserId?}` | `{code, expiresAt}` — a personal invite code (15 min), usable in `join` while the company is loaded. With ≥2 owners it becomes an approval request instead. |
| cancelInvite | CorporateGovernance | `{code}` | — |
| setPermissions | CorporateGovernance | `{userId, permissions:{Research:true,...}}` | — |
| respondApproval | — | `{id, approve:bool}` | `{pending:true}` / `{rejected:true}` / result of the executed action |
| requestShareChange | CorporateGovernance | `{shares:{"<userId>":percent,...}}` (sum 100) | `{approvalId, pending}` |
| buyoutPartner | CorporateGovernance | `{userId}` | `{price}` or `{approvalId, pending}` |
| transferRole | CorporateGovernance | `{userId, founder?:bool}` | `{approvalId, pending}` |
| liquidateCompany | CorporateGovernance | `{}` | — or `{approvalId, pending}` |
| renameCompany | CorporateGovernance | `{name}` (1–24 chars) | — |
| leaveCompany | — | `{}` | — ; gives up ownership (stake stays dormant), then the server sends `left {reason:"leftCompany"}` |

Permissions (Enums.Permissions): Research, Design, Pricing, Marketing, Manufacturing, Construction, Hiring, Finance,
AssetManagement, CorporateGovernance. Founder has all; co-founders get all except CorporateGovernance.

## Legacy / profile / tokens (player profile, not company state)
| action | perm | args | data |
|---|---|---|---|
| getProfile | — | `{}` | player profile `{userId, legacy:{points, perks, challenge,...}, tokenState:{tokens, missions,...}, ...}` |
| takePerk | — | `{id}` | `{perks, points}` |
| takeChallenge | CorporateGovernance | `{id}` | `{challenge}` |
| sellCompany | CorporateGovernance (founder only) | `{}` | `{points}` (then everyone gets `left {reason:"sold"}`) or `{approvalId, pending}` |
| buyTokenItem | — | `{id}` | `{item, tokens}` |

The profile is also pushed as a `profile` frame (see PROTOCOL.md Changes) whenever it changes.

## Employees (state paths) — iteration 2
- Hired staff: `state.employees.list` (array). Job board / candidate pool: `state.employees.candidates` (array, 8
  people, refreshed every 30 game days or with `rerollCandidates`). Other fields: `employees.morale` 0..1,
  `employees.perksBudgetMonthly`, `employees.candidatesRefreshDay`.
- Every entry (hired or candidate) is `{id, name, role, station, skill 0..1, experience 0..1, satisfaction 0..1,
  salaryMonthly, marketSalary, hiredDay}` (+ `friend/userId/username` for Roblox friends, never set online).
  - `role` ∈ HardwareEngineer, SoftwareEngineer, Researcher, Worker, Marketer, FinancialAnalyst, LogisticsManager, QCEngineer.
  - `station` (stable, derived from role; the world uses it to place the person):
    `"design"` = HardwareEngineer, SoftwareEngineer (PC desks) · `"research"` = Researcher (whiteboard / lab) ·
    `"assembly"` = Worker, QCEngineer (workbench / upstairs lines) · `"office"` = Marketer, FinancialAnalyst,
    LogisticsManager (generic desk). Old saves get it on load.
  - `marketSalary` = fair monthly salary for this role+skill; `setSalary` accepts 0.5x..3x of it. Hiring pays a
    signing bonus of one `salaryMonthly`.
- Staff cap: `Balance.Employees.hqStaffCap` by HQ level (10 at HQ 1) → `"Staff cap reached (10). Upgrade the HQ."`.

## Manual shipping, second floor, challenges — iteration 2
### State
- `production.crates`: array of `{id, productId, units, day, bonusPct?}` — finished goods waiting in the garage.
  Production output goes here first (at most one crate per product per game day; at most
  `Balance.Production.maxOpenCrates` = 20 open crates — when full, new output is merged into that product's newest
  crate). Units in crates are NOT sellable until shipped (`products[id].inventory` is what the market sells).
  `bonusPct` (0..0.1) = extra units from an assembly challenge, applied when the crate ships.
- Auto-ship: crates older than `Balance.Production.autoShipDays` (7) ship by themselves without the bonus; every crate
  ships the same day once the company owns a `LogisticsCenter` room. `production.lastAutoShip = {day, crates, units}`.
- `production.lines[]` have `location`: `"garage"` for the starting hand-assembly workbench `line_1` (also `bench:true`,
  always available) and `"upstairs"` for lines bought with `buildLine` (they need the second floor).
- `production.shippedTotal` = units shipped so far (manual + auto).
- Second floor = room `AssemblyLine`: `hq.rooms.AssemblyLine` exists ⇔ bought. New companies start WITHOUT it.
  Price `Balance.HQ.roomBuildCostBase.AssemblyLine` = $150,000 (level 1), allowed at HQ level 1. Use `getRoomCatalog`
  for the live price. Old saves that already had the room keep it.
- `challenges`: `{cooldowns:{"<kind>:<targetId>": readyDay}, supplierDiscount, retailerPremium, crateBonus:{productId:
  pct}, history:[{day, kind, targetId, score}]}` (history keeps the last 10). Cooldown left = `readyDay -
  time.elapsedDays` (game days); a key whose readyDay has passed may still be listed (= ready). `supplierDiscount` /
  `retailerPremium` > 0 = a negotiation bonus waiting for the next purchase / manual shipment; `crateBonus` = assembly
  bonus waiting for that product's next crate.

### Actions
| action | perm | args | data |
|---|---|---|---|
| shipCrate | — | `{crateId}` | `{crateId, productId, units, bonusUnits, premium}` — units moved into `products[productId].inventory` (incl. +5 % `Balance.Production.manualShipBonus` "careful handling", rounded down, at least +1 when units ≥ 1); `premium` = cash from a negotiation challenge (0 usually). Error `"Unknown crate"`. |
| shipAll | — | `{}` | `{shipped:n, units, bonusUnits, premium, crates:[{crateId, productId, units}]}` — ships every crate with the manual bonus. Error `"No crates to ship"`. |
| getRoomCatalog | — | `{}` (read-only) | `{rooms:{<roomId>:{name, effect, level, maxLevel, minHQLevel, nextCost, canBuild, reason?}}, hqLevel}` — `nextCost` = price of the next level (`null` at max); `reason` = why `canBuild` is false. |
| challengeReward | — | `{kind, targetId, score}` | `{kind, targetId, score, applied:{...}, cooldownDays, readyDay}` (see below) |
| buildRoom | Construction | `{roomId:"AssemblyLine"}` = buy the second floor | `{level, cost}` |
| buildLine | Construction | `{kind:"Assembly"}` needs the second floor: else error `"Build the Assembly Line first"` | `{id, cost}` |

`launchProduct` first ships every crate of that product (no bonus), then needs `inventory > 0`.
`discontinueProduct` ships that product's crates first (they are salvaged with the rest).

### challengeReward (mini-game results; the server caps everything)
`score` is clamped to 0..1 (non-numbers → 0). Cooldown is per company, per `kind` + `targetId`, in game days
(`Balance.Challenges.<kind>.cooldownDays`); a rejected call does not start a cooldown.
| kind | targetId | reward (scales with score) | cooldown |
|---|---|---|---|
| research | techId being researched (`research.active[].techId`) | + up to 8 % of the tech's total progress → `applied:{techId, progress, added}` | 5 days |
| design | projectId in `state.projects` | score ≥ 0.5 and the project has bugs → fixes one bug for free (`applied:{fixed:"bug"\|"toughBug", bugs, toughBugs}`; tough bugs need score ≥ 0.8); otherwise + up to 3 quality (`applied:{quality, added}`) | 5 days |
| assembly | lineId (`production.lines[].id`, must have a batch running) or productId | + up to 10 % units on that product's newest open crate (or the next crate if none) → `applied:{productId, crateId?, bonusPct}` | 5 days |
| negotiation | `"supplier"` (phone) or `"retailer"` (van; alias `"van"`) | supplier: next `buyResources` up to −10 % (`applied:{supplierDiscount}`); retailer: next shipment pays a cash premium of up to 3 % of its retail value (`applied:{retailerPremium}`) | 10 days |

Errors (friendly, with `errorKey`/`errorParams`, see docs/LOCALE_KEYS.md):
`"Unknown challenge"`, `"Already done: try again in 3 days"` (cooldown, `params.days`),
`"That technology is not being researched"`, `"That project is not in development"`,
`"Nothing is being assembled there"`, `"Talk to the supplier or the retailer"`, `"Nothing left to polish on this project"`.

## Not actions (protocol messages instead)
| Roblox lobby action | use |
|---|---|
| createCompany | `{"t":"create","company":{...}}` |
| joinCompany | `{"t":"join","code":"ABC-123"}` (room code or personal invite code) |
| leaveLobby | `{"t":"leave"}` (detach) or act `leaveCompany` (give up ownership) |
| lobbyStatus | `welcome.lastCompany` + `{"t":"resume"}` |
| playInvite | not supported (no in-server player list); share the room code instead |
| setSpeed | also available as `{"t":"speed","speed":8}` |

## Useful ids at the start of a company
- Assembly line: `"line_1"`. Starting techs: arch_arm_1, arch_x86_1, gpu_arch_1, disp_ips, disp_tn, bat_1, cool_1,
  mem_1, cam_1, mat_2, biz_intel (first research to try: `arch_arm_2`).
- Typical first loop: createBlueprint → updateBlueprint (slots + priceUSD) → publishBlueprint (a 30+ day
  development project starts; `finishProjectNow` costs research points) → when the project disappears from
  `state.projects`: queueProduction (quantity 100..2,000,000) on `line_1` (the garage workbench) → crates appear in
  `production.crates` → shipCrate / shipAll (or launchProduct, which ships that product's crates) → launchProduct →
  sales appear weekly in `products[id].unitsSold` / `finance`.

## Purchasing (materials)
- `getMaterialQuotes {}` (read-only) → `{materials:[{id,name,unit,stock,basePrice,spotPrice,supplyMult,dailyNeed,daysLeft,usedBy:[productName],offers:[{supplierId,name,reliability,minWeeks,pricePerUnit,pricePerUnitLong}]}], contracts:[{id,supplierId,resourceId,unitsPerWeek,pricePerUnit,weeksLeft}], billPerUnit:{Category:{resourceId:unitsPerDevice}}, supplierDiscount, cash}`.
  `daysLeft` = -1 when nothing currently consumes it. `spotPrice` already includes events, research and a pending negotiation discount.
- Buy now: `buyResources {resourceId, units}` (spot price). Contract: `signContract {supplierId, resourceId, unitsPerWeek, weeks}` (weeks ≥ supplier.minWeeks; longer = up to 10% cheaper, delivered weekly). Cancel: `cancelContract {contractId}`.
- Production jobs block with `blockedReason = "Out of <material>"` when stock is short.

## Story & repairs — iteration 3 (story start: "From the repair shop to a phone company")
Design: docs/STORY.md. The server is authoritative: a step is completed only by a real action (or a whitelisted
`storyEvent` for things only the client can see). Quick start, old saves and joined friends work as before.

### New company: story or quick start
`{"t":"create","company":{..., "storyMode": true}}` → story start. `storyMode` missing/false = quick start (old clients).
| | story start | quick start (unchanged) |
|---|---|---|
| cash | `Balance.Story.startCash` = **6 000** | `Balance.Start.cash` = 2 500 000 (+ legacy perk) |
| credit line | 0 (the investor brings the normal 1 000 000) | 1 000 000 |
| staff | 2 helpers: Researcher + Worker | 5 (2 engineers, researcher, 2 workers) |
| clock | **paused** (`time.speed = 0`) until chapter 4 | speed 1 |
| repair orders | yes (scripted in chapters 1–3, then random side income) | none |
| `story` | `{done:false, mode:"story", chapter:0, ...}` | `{done:true, mode:"quick", chapter:7, ...}` |
Old saves (no `story` key) load as `{done:true, mode:"legacy", chapter:7}` and never get repair orders.

### State (both are replicated top-level sections, like `challenges`)
`state.story`
| field | meaning |
|---|---|
| `done` | true = story finished / skipped / quick start / old save → sandbox; hide the objective tracker |
| `mode` | `"story"` (created with storyMode), `"quick"`, `"legacy"` (old save) |
| `chapter` | 0..6 while playing; **7** when done |
| `chapterId` | id of the chapter (table below; `"done"` when done) — use it for texts |
| `step` | id of the first unfinished **required** step of the current chapter (`""` when done) |
| `objectives` | current chapter's steps in display order: `[{id, done, optional}]` (`[]`/`{}` when done) |
| `stepsDone` | `{stepId: true}` — every step completed so far (ids are unique over all chapters) |
| `flags` | `{investor?:true, skipped?:true, freeResearch?:bool, ...}` (`freeResearch` = the first research is still free) |
| `startedDay` | `time.elapsedDays` when the story started (0) |
Steps of a chapter may be completed **in any order** by **any member** (co-op: one takes orders, one repairs).
When all required steps are done the next chapter starts at once (optional steps may be skipped). Steps of later
chapters never complete early; on entering a chapter, steps whose result already exists are completed immediately
(e.g. a research that is already running completes `start_research`).

`state.repairs` = `{orders:[...], done, earned, nextDay}` — `done` = repairs paid so far, `earned` = $ earned,
`nextDay` = earliest game day of the next random order (internal: `seq`, `rng`). Each order:
`{id, customer, device, fault, partId?, reward, status, createdDay, chapter?, takenBy?, quality?, payout?, paid?}`
- `id` e.g. `"rep_3"`; `status`: `"waiting"` (customer at the counter, device on the counter) → `"inRepair"` (taken
  to the bench) → `"ready"` (repaired, back to the counter) → `"paid"` (customer pays and leaves). Paid orders stay in
  the list briefly (the 3 newest) so the world can play the "pay & leave" moment, then disappear.
- `customer` ∈ `grandma, student, courier, teacher, gamer, barista, taxi_driver, musician, chef, blogger`
  (original NPCs; English fallback names in `shared-luau/Data/Story.luau`, keys `data.story.<id>.name`).
- `device` ∈ `phone, tablet, laptop, watch`. `fault` ∈ `cracked_screen` (part `screen`), `dead_battery` (part
  `battery`), `broken_port` (part `port`), `water_damage`, `software_glitch`, `stuck_button` (no part).
- `partId` (only for faults that need one) → the part resource is `"repair_" .. partId`.
- `reward` = the price the customer agreed to; `quality` (0..1) and `payout` are set by `repairFinish`; `paid` by `repairReturn`.
- `chapter` = story chapter of a scripted order (nil for random side orders); `takenBy` = userId.
- Random side orders (clock running, story companies only): one every 5–9 game days, at most 2 open, only while
  `hq.level < 2`; a waiting customer leaves after 30 game days.

### Actions (any member unless noted)
| action | args | data | errors (`errorKey`) |
|---|---|---|---|
| repairTake | `{orderId}` | `{order}` → status `inRepair` (device taken from the counter to the bench) | `err.repair_unknown_order`, `err.repair_busy` (not waiting) |
| repairFinish | `{orderId, score}` score 0..1 from the mini-game (clamped, non-number → 0) | `{order, quality, payout, partUsed, rp}` → status `ready`; consumes 1 `repair_<partId>`; `rp` = research points earned (see Research points) | `err.repair_unknown_order`, `err.repair_not_in_repair` (already finished), `err.repair_no_part` `{part}` (= part resource name: buy it in Purchasing) |
| repairReturn | `{orderId}` | `{order, paid, cash}` → status `paid`, cash += payout | `err.repair_unknown_order`, `err.repair_not_ready`, `err.repair_already_paid` |
| storyEvent | `{id}` — whitelist below | `{id, counted}` (`counted` = it completed a step now; repeats / other chapters → `false`) | `err.story_unknown_event` |
| storySkip | `{}` — **founder only** | `{skipped:true, investor}` → story done instantly with the quick-start economy (cash topped up, team hired, clock running) | `err.story_founder_only`, `err.story_already_done` |
| listMyCompanies | `{}` — **lobby**: works right after `hello`, also inside a company | `[{companyId, code, name, date:{year, day, elapsedDays}, cash, role, lastPlayed, mode, logo, story:{done, chapter}, online}]` newest first | — |
`listMyCompanies`: every company where you are an active owner (not liquidated, not left); `code` = room code
`"ABC-123"` (enter with `join`), `role` = "Founder"/"CoFounder", `lastPlayed` = unix seconds of the last save
(now for a company that is loaded with players online), `online` = members online now.

Payout: `payout = round(reward × (0.4 + 0.6 × score))` — never more than `reward` (Balance.Story.repairs.minQuality).
Speed while the clock is paused (story, chapter < 4): `setSpeed` / `speed` frame → error
`"Story: time starts at chapter 4"` (`err.story_clock_paused`). In chapters 0–3 the first `startResearch` is free
(`data.free = true`; cancelling it refunds nothing).

### Purchasing: repair parts (resources)
`repair_screen` "Replacement Screen" (base $38), `repair_battery` "Replacement Battery" ($22), `repair_port`
"Charging Port" ($9). They appear in `getMaterialQuotes` (spot = base × 1.15, supplier `parts_depot` "Gadget Parts
Depot" contracts from 4 weeks) and are bought with `buyResources {resourceId:"repair_screen", units:n}`; stock is
`inventory.resources.repair_screen`. No production uses them. A new story company has 0 of each.

### storyEvent whitelist (client-only moments; each counts once, only in its chapter)
`intro_seen`, `door_open`, `lights_on`, `supplier_called`, `pattern_noticed`, `investor_seen`, `reviews_seen`, `sign_swapped`

### Chapters and step ids (exact; `opt` = optional)
| # | chapterId | step id | completed by |
|---|---|---|---|
| 0 | `workshop` | `intro_seen` | storyEvent `intro_seen` (intro cutscene watched) |
| | | `door_open` | storyEvent `door_open` (interactable `shop_door`) |
| | | `lights_on` | storyEvent `lights_on` (interactable `light_switch`) |
| 1 | `first_customer` | `take_device` | `repairTake` (any order) |
| | | `repair_device` | `repairFinish` (any order) |
| | | `get_paid` | `repairReturn` (any order) |
| | | `second_customer` | a 2nd repair paid (`repairs.done ≥ 2`) |
| 2 | `spare_parts` | `diagnose_part` | `repairTake` of an order that needs a part |
| | | `call_supplier` | storyEvent `supplier_called` (supplier phone used) — also done by `buy_parts` |
| | | `buy_parts` | `buyResources` of any `repair_*` resource |
| | | `fit_part` | `repairFinish` of an order with a part (the part is used) |
| | | `paid_with_part` | `repairReturn` of an order with a part |
| 3 | `same_fault` | `pattern_repair` | `repairReturn` of a chapter-3 order (the same fault again) |
| | | `notice_pattern` | storyEvent `pattern_noticed` (the "same fault" dialogue) |
| | | `start_research` | `startResearch` (free) — or a research already running |
| | | `research_challenge` opt | `challengeReward {kind:"research"}` |
| 4 | `own_phone` | `investor_seen` | storyEvent `investor_seen` (investor cutscene; the money already arrived on entering chapter 4) |
| | | `design_phone` | `createBlueprint` / `copyBlueprint` (or a blueprint exists) |
| | | `publish_phone` | `publishBlueprint` (or a product exists) |
| | | `develop_phone` | a product's development project finished (days pass now; `finishProjectNow` too) |
| | | `polish_challenge` opt | `challengeReward {kind:"design"}` |
| 5 | `first_batch` | `queue_batch` | `queueProduction` (or a production job exists) |
| | | `first_crate` | a crate appears in `production.crates` (or units were shipped) |
| | | `ship_crate` | `shipCrate` / `shipAll` / auto-ship / launch (`production.shippedTotal > 0`) |
| | | `qc_challenge` opt | `challengeReward {kind:"assembly"}` |
| 6 | `launch_night` | `launch_phone` | `launchProduct` (or a product is launched) |
| | | `reviews_seen` | storyEvent `reviews_seen` (critics card closed) |
| | | `sign_swapped` | storyEvent `sign_swapped` (sign-change cutscene done) → **story complete** |

Scripted orders: ch1 start → `grandma/phone/software_glitch` $60; when it is taken → `student/phone/stuck_button`
$50. Ch2 start → `courier/phone/cracked_screen` (part `screen`) $140. Ch3 start → `teacher/phone/broken_port` and
`gamer/phone/broken_port` (part `port`) $70 each. From chapter 4 on (clock running) random side orders.
Entering chapter 4 = the investor: cash += max(normal start cash − cash, normal start − 6 000) (so earnings are kept and
cash is at least the quick-start amount), credit line 1 000 000, the rest of the starting team is hired, `time.speed` = 1.

### Notifications (`notify.key`, English `title`/`body` as fallback; category `Story` / `Repair`)
| key | params | when |
|---|---|---|
| `story.step.done` | `{chapter, step}` (`bodyKey` = `data.story.<step>.title`) | a step completed |
| `story.chapter` | `{chapter, id, title}` (`bodyKey` = `data.story.<id>.description`) | a new chapter started (show the chapter card) |
| `story.investor` | `{amount}` | chapter 4 investor money arrived, clock started |
| `story.complete` | `{name}` | story finished (after `sign_swapped`) |
| `story.skipped` | `{}` | founder skipped the story |
| `story.repair.new` | `{orderId, customer, device, fault}` + `paramKeys` (`data.story.<id>.name` for customer/device/fault) | a customer put a device on the counter |
| `story.repair.paid` | `{orderId, amount}` | a repaired device was returned and paid |

## Research points (RP) — iteration 3
`state.research.points` (whole number; `research.rpFraction` keeps the fractional remainder, internal). RP are spent on
`boostResearch` (100 RP = +25 % progress), `finishProjectNow`, `fixProjectBug` / `addProjectQuality` (30 / 60 RP),
`rerollCandidates` (20 RP) and the token shop. Sources:
| source | amount | where |
|---|---|---|
| research staff (passive) | every employee with `station:"research"`: `Balance.Research.rpPerResearcherPerDay` (1.0) × (1 + 0.15 × ResearchLab level) RP per game day (lab 1 → 1.15) | every simulated day (not while the story clock is paused) |
| a technology finishes | `5 × tier` RP (`Balance.Research.rpPerTechTier`) | the day the research completes (notify "Research complete: …") |
| repair orders (story companies) | `3 × score` RP per finished repair (perfect repair = 3; `Balance.Story.repairs.rpPerfect`) | `repairFinish` → `data.rp` = whole points added now |
| daily gift | `claimDaily {}` → `{reward:{name, kind, amount}, dayIndex, streak, detail, streakBonus}`; kinds `cash` / `rp` / `mystery` / `influencer` / `gold`. Once per real (UTC) day per company; one missed day per week keeps the streak; error `"Already claimed today"` (`err.already_claimed_today`). Button state: claimable when `state.daily.lastClaimUnix` is 0 or on an earlier UTC day; next gift = `daily.dayIndex` (1..7, `shared-luau/Data/DailyRewards.luau`) | any member, any time (also during the story) |
| goals / missions / challenges | as before (goal rewards, token-shop items, research challenge credit) | — |
The `research` section is replicated on every day the points change.

## Accounts — lobby actions (docs/ACCOUNTS.md)
Sent as `act` like `listMyCompanies`; no company needed. `key` / `oldKey` / `newKey` = 64 lowercase hex chars,
PBKDF2-HMAC-SHA256(password, "silicon-overlord:" + lowercase(username), 100000) — never the password itself.
`kdf` is optional (`"pbkdf2-sha256-100000"`, the only value accepted).

| action | args | data | notes |
|---|---|---|---|
| accountStatus | `{}` | `{account: {username, created} \| null, devices, companies}` | |
| accountRegister | `{username, key, kdf?}` | `{username, token}` | links the current player (+ companies); rotates this device token (store `token`). Errors: `"You already have an account"`, `"That username is taken"`, `"Username: 3-20 letters, digits or _"`, `"Username: use Latin or Cyrillic letters, not both"`, `"Bad password key"`, lockout |
| accountLogin | `{username, key, kdf?}` | `{username, guestKept}` | lobby only. Sends `welcome` (account's player, new token) before `res`. `guestKept`: this PC's previous guest (with companies) keeps its token — keep it for `accountLogout.guestToken`. Error always `"Wrong username or password"` (or lockout) |
| accountLogout | `{guestToken?}` | `{guest: true, restored}` | lobby only; revokes this token; `welcome` of the saved guest (`restored: true`) or a new guest |
| accountChangePassword | `{oldKey, newKey}` | `{signedOut}` | `"Wrong password"`; other devices are signed out |
| accountDelete | `{key}` | `{signedOut}` | erases the credentials; player + companies stay on this PC as a guest |
| transferCreate | `{}` | `{code: "ABCD-EFGH", expiresIn: 600}` | guests too; one live code per player; 5 per 10 min |
| transferRedeem | `{code}` | `{username \| null, guestKept, same?}` | lobby only; single use, 10 min; `welcome` of that player before `res`. Error `"Wrong or expired code"` (5 per minute per IP, then lockout) |

## Interior — 0.5.0 (build mode: docs/INTERIOR.md §1, §4)
Data for the client (export these Luau modules with the other Data tables; they are pure data + tiny helpers):
`shared-luau/Data/Interior.luau` (catalogue `list`, `categories`, `themes`, `materials`, `lightPresets`, `legacyMap`),
`shared-luau/Data/RoomGeometry.luau` (`list`, `officeHalf`, `grid` 0.25, `rotStep` 15, `wallSnap`; office rooms
change size with the HQ level: use `officeHalf[hq.level]`), `shared-luau/Data/Expansions.luau`,
`shared-luau/Data/ProductionProcesses.luau`. Numbers: `Balance.Interior` in `shared-luau/Config/Balance.luau`.

### Rooms and coordinates
Room ids (`RoomGeometry.list`): HQ 1 = `garage` (always), `loft` (needs `hq.rooms.AssemblyLine`), `annex`, `basement`,
`shed`, `showroom` (need that expansion, see "Expansions"); HQ 2..7 = `office` (one open floor, x[-hw,hw] z[-hd,hd],
`officeHalf`). A room is an axis-aligned box: `origin {x,y,z}` = where its local (0,0,0) is in the level scene
(garage scene for HQ 1, office scene for HQ ≥ 2), `bounds {x0,x1,z0,z1}` = usable floor in local metres, `height`.
Items store LOCAL `x`/`z` = centre of the footprint (sent as JSON numbers: numeric strings are `"Bad position"`), `rot` in degrees (multiple of 15, 0..345). At rot 0 the
footprint is `w` along X and `d` along Z; for other angles the server uses the axis-aligned box of the rotated
rectangle (`w' = |w·cos| + |d·sin|`, `d' = |w·sin| + |d·cos|`). x/z are snapped to 0.25 m by the server.
`reserved` zones: `door`, `stairs`, `ramp`, `path` block every layer; `fixture` (built-in benches, counters, the
loft's line bays...) blocks floor items only. World agent: build the expansions' doorways where the zones say.

### State (`interior`, a replicated top-level section)
```
interior = {
  version = 1, nextId = <n>,
  rooms = { [roomId] = {
      items = [ { id = "i12", def = "<Data/Interior id>", x, z, rot, y? (wall items: centre height), color? "#RRGGBB",
                  day = <elapsedDays when placed>, ref? (living poster: productId), paid (USD, refund base),
                  legacy? true, uid? (old office uid), stored? true (piece that arrived without a free spot / over a cap:
                  not shown, no comfort, no seats; interiorMove it to a free spot to show it, or sell it) } ],
      surfaces = { wall? = {mat, color}, floor? = {mat, color} },  -- {} = the level's default look
      theme? = "grunge"|"wood"|"lab"|"neon"|"scandi", light? = "warm"|"daylight"|"neon",
      comfort = 0..100, parts = { decor, light, plants, space, theme }, seats = n, coherence = 0..1 } },
  summary = { seats, staffBonus, labSlots, storage, comfortAvg,
              effects = { morale, research, defects, design, brand } },   -- already capped
}
```
Rooms appear in `interior.rooms` once something was placed/painted there (treat a missing room as empty).
`legacy:true` items mirror the old grid office (`state.office`, 0.4.0 `buyFurniture` & co.): old saves are migrated
once into the main room (`garage` at HQ 1, `office` later); later buys from 0.4.0 clients appear there too.
A mirrored piece lands on its old grid cell mapped to metres (cell centre, rot 0 or 90); when that spot is taken it gets
a free-spot search (at most `Balance.Interior.legacySearchBudget` = 12 searches per pass), else `stored:true`. Room
`maxItems`, the 400 total and `def.max` hold for mirrored pieces too (overflow → `stored`). A mirrored piece that stands
in the interior gives its comfort / research through the interior only: the old office ratings
(`office.comfort` → morale, non-computer research pieces) skip it (`Office.mirrored`), so nothing counts twice.
Moving out of the garage (HQ 1 → 2): every piece of the garage rooms (garage, loft, annex, basement, shed, showroom)
moves into `office` — same local x/z when free there, else a free spot, else `stored` — so it can still be placed or sold.
Rooms that are not part of the current HQ do not count toward the 400 total.
Malformed saved records are repaired on load (non-table rooms dropped, items without numeric x/z → `stored` at 0,0,
office records without a numeric uid dropped, expansion levels clamped to 0..maxLevel).
Plants: `growth = clamp((time.elapsedDays - item.day) / def.grow, 0, 1)` (client scales the model 0.5 → 1).

### Actions (Construction permission; any co-owner with it; everybody sees the result via the `interior` section)
| action | args | data |
|---|---|---|
| interiorPlace | `{room, def, x, z, rot, color?, y?, ref?}` | `{item, cost, comfort}` — buys and places one item. `y` only for wall items (default `def.y`). `ref` = productId for `living:"poster"` items |
| interiorMove | `{room, id, x, z, rot, toRoom?, y?}` | `{item, room}` — free; `toRoom` moves it into another unlocked room |
| interiorRemove | `{room, id}` | `{refund}` — sells it for `Balance.Interior.refundShare` (50 %) of its price |
| interiorPaint | `{room, surface:"wall"\|"floor", mat, color}` | `{cost, surface}` — material price from `Interior.materials` (`color` = `#RRGGBB`) |
| interiorTheme | `{room, theme}` (`theme:""` clears) | `{cost, theme}` — sets the theme AND repaints both surfaces + light preset to the theme's (cost = both materials) |
| interiorLight | `{room, preset}` (`""` clears) | `{light}` — free (a preset or theme alone does not make an empty room comfortable) |

Checks, in order: room exists / is part of this HQ / is built → def exists → `minHQ` → room role (`def.roles`) →
room item cap (`maxItems`, 400 in total) → `def.max` per room → colour → position (snap, bounds, height, wall contact,
reserved zones, overlap with items of the same layer; wall items also compare heights) → cash.
Validation errors (all with `errorKey`): `"Pick a wall or the floor"`, `"Unknown room"`, `"That room is not built yet"`, `"That room is not part of this HQ"`,
`"Unknown item"`, `"Needs HQ level 2"`, `"That does not belong in this room"`, `"Outside the room"`, `"Too tall for this room"`,
`"Blocked: doorway"` / `"Blocked: stairs"` / `"Blocked: van ramp"` / `"Blocked: walkway"` / `"Blocked: something built in"`,
`"Overlaps another item"`, `"Wall items must touch a wall"`, `"The room is full (40 items)"`, `"Only 1 of these per room"`,
`"Not enough cash ($1800)"`, `"Unknown item id"`, `"Bad position"`, `"Unknown material"`, `"That material does not go on this surface"`,
`"Pick a colour"`, `"Unknown theme"`, `"Unknown lighting preset"`, `"Unknown product"`, `"Too many build actions, slow down"`.
Rate limit: besides the connection bucket, interior* actions + buildExpansion + setLineProcess have their own bucket (12 burst, 4/s per connection) →
`ok:false, error:"Too many build actions, slow down"`. Approvals: interiorPlace / interiorPaint / interiorTheme have a cost
estimate (co-founder large-spend rule applies, practically never).

### Comfort (per room, 0..100) and effects (capped)
`comfort = decor (≤45) + light (≤15) + plants (≤15) + space (≤15) + theme (≤10)`:
decor = item comfort points of non-plant, non-lighting items with diminishing returns `45·(1−e^(−pts/18))`;
light = lighting items' points + the light preset's points, `15·(1−e^(−pts/6))`; plants = plant points × growth,
`15·(1−e^(−pts/6))`; space = free floor m² per seat (at least 1 person): 0 at ≤ 2 m², 15 at ≥ 8 m²;
theme = 10 when a theme is set and ≥ 60 % of the themed-capable items match it (`coherence` = share), 0 below.
Negative item comfort (a noisy compressor) subtracts from decor points. A room without a standing (non-stored) item has
comfort 0 whatever its light preset / theme, and does not count in `comfortAvg`. No catalogue item with seats is free
(`desk_door_trestle` costs 450).
Effects (`interior.summary.effects`, all capped in `Balance.Interior.caps`):
- morale (+ to the monthly morale drift; max +0.05): seat-weighted average comfort of rooms × 0.05 + item `fx.morale` (≤ 0.02).
- research (lab speed, max +10 %): best comfort of `lab`/`mixed` rooms × 0.10 + item `fx.research` % (≤ +6 %).
- defects (max −15 %): best comfort of `production`/`mixed` rooms × 0.15 + item `fx.defects` % (≤ 8 %).
- design (design quality gain while developing, max +8 %): best comfort of `design`/`mixed` rooms × 0.08 + `fx.design` % (≤ 4 %).
- brand (+ recognition per quarter, max +1): showroom comfort × 0.6 + `fx.brand` × 0.1 (≤ 0.4).
- seats → `summary.staffBonus` = min(`Balance.Interior.staffBonusMax[hq.level]`, floor(seats / 2)) extra staff cap;
  seats also count as desks for the "no desk" penalty. labSlots (lab benches) → `summary.labSlots` = min(1, Σ) extra
  research slot. storage → crate space: `summary.storage` extra open crates (`maxOpenCrates` + storage, ≤ +20).

## Expansions — 0.5.0 (docs/INTERIOR.md §2)
State: `hq.expansions = { [id] = {level, builtDay} }` (missing = not built; `loft` is not stored here: it is `hq.rooms.AssemblyLine`).
| id | room (interior) | counts as hq room | price L1 (then ×1.8 per level) | max level | effect |
|---|---|---|---|---|---|
| loft | loft | AssemblyLine | 150 000 | 2 (HQ 1 rule) | production lines upstairs (= `buildRoom AssemblyLine`) |
| annex | annex | — (own effect) | 90 000 | 3 | +1 research slot (+2 at level 3), +4 % research speed per level, lab benches |
| basement | basement | ServerRoom | 120 000 | 3 | open-crate limit ×3, warehouse capacity ×3, ServerRoom level = basement level (cloud services, eco users) |
| shed | shed | QualityControl | 70 000 | 3 | QualityControl level = shed level (−12 % defects per level) |
| showroom | showroom | Showroom | 60 000 | 3 | Showroom level = showroom level (+1.5 brand per level and quarter) |
Rules: `CompanySim.roomLevel(room) = max(hq.rooms[room].level, expansion level)` for shed/showroom/basement while the
company is in the garage (HQ 1). After the move to an office the garage rooms are gone: shed/showroom/basement still
count as at most level `Balance.Expansions.keptRoomLevel` (= 1) of their room (higher levels: `buildRoom` under the
normal HQ rules), and the annex research slots/speed and the basement ×3 crates/warehouse stop (garage only). Expansions can be bought/upgraded only at HQ 1 (`"Expansions are for the garage. Build rooms in the office."`).
| action | perm | args | data |
|---|---|---|---|
| buildExpansion | Construction | `{id}` | `{id, level, cost}` — builds level 1 or upgrades +1. Errors `"Unknown expansion"`, `"Expansion at max level"`, `"Not enough cash ($90000)"` |
| buildRoom | Construction | `{roomId: "QualityControl"\|"Showroom"\|"ServerRoom"}` at HQ 1 | routed to `buildExpansion shed/showroom/basement` (these rooms could not be built at HQ 1 before). `{level, cost, expansion}` |
| getExpansionCatalog | — | `{}` (read-only) | `{expansions:{<id>:{name, room, hqRoom, level, maxLevel, nextCost, canBuild, reason?}}, hqLevel}` |

## Production processes — 0.5.0 (docs/INTERIOR.md §3)
State: every ASSEMBLY line in `production.lines[]` has `process` ∈ `"hand" | "semi" | "robotic" | "smart"`, plus after a
switch `processFrom` (previous) and `processUntil` (game day the switch is done; the line is down until then:
`downUntilDay`). Fab lines have no `process`. Old saves: every assembly line migrates to `"hand"` (multipliers 1.0 = the
old behaviour). Table `Data/ProductionProcesses.luau`:
| process | capacity × | defects × | energy × | worker need × | operators | setup $ (× (1 + 0.5·(level−1))) | switch days | tech (all required) |
|---|---|---|---|---|---|---|---|---|
| hand | 1.0 | 1.0 | 1.0 | 1.0 | 4 | 0 | 2 | — |
| semi | 1.3 | 0.9 | 1.15 | 0.8 | 3 | 40 000 | 3 | `mfg_auto_1` Factory Automation 1 |
| robotic | 1.75 | 0.7 | 1.5 | 0.45 | 2 | 250 000 | 7 | `mfg_auto_3` Factory Automation 3 |
| smart | 2.4 | 0.45 | 1.9 | 0.2 | 1 | 900 000 | 10 | `mfg_auto_4` Factory Automation 4 + `mfg_qc_3` Quality Systems 3 |
Switching down is free (still downtime). "worker need" divides the Worker staff a line needs (robots need fewer hands).
| action | perm | args | data |
|---|---|---|---|
| setLineProcess | Manufacturing | `{lineId, process}` | `{lineId, process, cost, downtimeDays, untilDay}`. Errors `"Unknown line"`, `"Only assembly lines have a process"`, `"Unknown process"`, `"Already using that process"`, `"Research Factory Automation 3 first"`, `"Not enough cash ($250000)"` |
