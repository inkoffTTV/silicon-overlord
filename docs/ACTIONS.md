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
  queueProduction, buyResources.
- Rate limit: 30 requests burst, refill 10/s per connection (`error:"Too many requests"`).
- An action that would need approval returns immediately with `{approvalId, pending:true}`; when the last owner
  approves, the `respondApproval` call returns the executed action's `data` (or its error), and everybody gets a
  `notify` "Request approved and executed" / "Approved request failed".
- Name rules (from Validate.name, ASCII only for now — see docs/REQUESTS.md): blueprint names 1–32,
  renameCompany 1–24 characters of `A-Z a-z 0-9 space - . _ ' & !`. Company names given to `create` may be Cyrillic.
- `res` of a successful action arrives after the `sections` it caused; a failed action changes nothing.

## Time / misc
| action | perm | args | data on success |
|---|---|---|---|
| setSpeed | — | `{speed: 0\|1\|2\|4\|8}` | — (same as the `speed` frame) |
| getSnapshot | — | `{}` | — (server sends a fresh `snapshot` frame) |
| setTutorialStep | — | `{step: 1..20}` (only increases) | — |
| getAudit | — | `{}` | array of audit entries `{transactionId, initiatorUserId, operationType, amount, timestamp, previousStateVersion, newStateVersion, note}` |

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
| buildLine | Construction | `{kind}`: Assembly / CPUFab / GPUFab / DisplayFab / BatteryFab (fabs need research) | `{id, cost}` |
| upgradeLine | Construction | `{lineId}` | `{cost}` |
| queueProduction | Manufacturing | `{productId, lineId, quantity}` e.g. lineId `"line_1"`, quantity ≥ 100 | `{id, unitCost, estimatedCost}` |
| cancelProduction | Manufacturing | `{jobId}` | — |
| setQcLevel | Manufacturing | `{level}` 0..3 | — |
| resolveIncident | Manufacturing | `{incidentId, option}` | `{cost}` |
| setFactoryLayout | Manufacturing | `{cells:[{x,y,kind}]}` (≤ 64) | `{score}` |
| queueFabJob | Manufacturing | `{lineId, componentId, wafers}` | `{id}` |
| sellComponents | Finance | `{offerId, componentId}` | `{units, revenue}` |
| buyResources | Manufacturing | `{resourceId, units}` | `{cost}` |
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
| hire | Hiring | `{candidateId}` (from `state.employees.candidates[].id`) | `{employee}` |
| fire | Hiring | `{employeeId}` | `{severance}` |
| setSalary | Hiring | `{employeeId, salary}` | — |
| setPerks | Hiring | `{monthly}` | — |
| teamParty | Hiring | `{}` | `{cost, morale}` |
| rerollCandidates | Hiring | `{}` | `{candidates:n}` |
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
  `state.projects`: queueProduction (quantity 100..2,000,000) → when `products[id].inventory > 0`: launchProduct →
  sales appear weekly in `products[id].unitsSold` / `finance`.
