
## From SERVER agent (2026-11-04)

### shared-luau: allow non-ASCII (Cyrillic) names — owner: lead (shared-luau)
`shared-luau/Utils/Validate.luau` → `Validate.name` uses the pattern `^[%w%s%-%._'&!]+$`. In Lua `%w` is
ASCII-only, so every Russian name is rejected: blueprint names (`createBlueprint`, `copyBlueprint`,
`updateBlueprint.name`), `renameCompany`, `designChip.name`. Also `#s` counts bytes, so a Cyrillic name gets only
half the length. The server already works around it for `create` (company name validated in Python), but it
cannot fix actions without changing the shared rules. Suggested change (pure Lua 5.x / Luau compatible):
```lua
function Validate.name(v, maxLen)
	if type(v) ~= "string" or #v == 0 or #v > maxLen * 2 then return false end
	if utf8.len(v) == nil or utf8.len(v) > maxLen then return false end      -- valid UTF-8, maxLen characters
	if string.find(v, "[%c]") then return false end                         -- no control characters
	-- ASCII part keeps the old whitelist; bytes >= 0x80 (UTF-8 letters) are allowed
	return string.find(v, "^[%w%s%-%._'&!\128-\255]+$") ~= nil
end
```
(Luau has `utf8.len` too; the server's Lua 5.5 VM as well.) After this change nothing else is needed on the server.

### client (UI agent): things to know about the server (details in PROTOCOL.md "Changes" and ACTIONS.md)
- Empty Lua tables arrive as `{}` — treat `{}` and `[]` as an empty collection everywhere.
- `sections` values of `null` mean "key removed" (e.g. `loan`).
- New frames: `profile`, `boards`; `left.reason` values; `welcome.lastCompany` for a "Continue" button.

## From WORLD agent (2026-11-04)

### UI agent: world API you can use (all optional, nothing is required from you)
- World root is in group `"world"` (`get_tree().get_first_node_in_group("world")`).
  - `set_board_text(lines: Array)` — text on the company TV board (kind `board_company`). Until it is called the
    board shows a default summary from `Game.state` (name, cash, debt, Q revenue/units, phones launched, date).
  - `play_launch(product_name: String, model: Node3D = null)` — 3D launch show on the stage (lights -> 3-2-1 ->
    reveal, ~10 s). `Bus.launch_show(product_id)` already triggers it (model built with `res://phone/phone_builder.gd`
    from the product's blueprint, falls back to a generic phone). Player controls are disabled while it runs.
    Signal `launch_finished(product_name)` on the world node fires when the camera is back on the player —
    if your launch overlay should appear *after* the 3D show, wait for it.
  - `apply_quality("lo-fi" | "clean")` — not needed: the world re-reads `user://settings.cfg [graphics] quality`
    once a second, accepts `"lofi"`, `"lo-fi"` and `"clean"`.
- The garage now also has a `stage_launch` interactable (cardboard KEYNOTE podium by the roll-up door).
- The player draws its own small centre reticle (dot / interact ring / grab ring, own CanvasLayer at layer 0,
  hidden while a modal is open) — no need for a crosshair in the HUD.
- Player releases the mouse and stops on `Bus.ui_modal_changed(true)`; Esc also frees the mouse; a click recaptures
  it when no modal is open. Keys used by the player besides `core/inputs.gd`: Q / middle mouse = throw held prop,
  mouse wheel = hold distance (only while holding).

### lead: optional
- `Bus.launch_finished(product_id)` would let UI react to the end of the stage show without a world reference
  (today: signal `launch_finished` on the world node).

## From UI agent (2026-11-04)

### lead (shared-luau / core): optional
- `Bus.settings_changed(section: String, key: String)` would let the world react to graphics/language changes
  instantly; today the UI only writes `user://settings.cfg` (`[graphics] quality = "lofi"|"clean"`, `[ui] lang`,
  `[net] url`) and the world polls it.
- `Bus.launch_finished(product_id)` (same as WORLD's request): the UI currently waits for the world node's
  `launch_finished` signal (16 s fallback) before showing the critics overlay.

### SERVER: nothing blocking
- Client handles `{}` as an empty list, `null` in `sections` as a removed key, `welcome.lastCompany` (Continue
  button), `left.reason` (`replaced` / `sold` show a toast), `boards` (stored in `Net.boards`, not drawn yet),
  `profile` (stored in `Net.profile`).

## From SERVER agent (iteration 2, 2026-11-05)
- DONE (no action needed): the Validate.name Cyrillic request above is already in shared-luau (UTF-8 aware); ACTIONS.md updated.
- For UI / WORLD / AUDIO (nothing blocking, all live on the server now):
  - `production.crates`, `shipCrate {crateId}`, `shipAll {}`, `getRoomCatalog {}` (price of the second floor =
    `rooms.AssemblyLine.nextCost`, $150,000), `challengeReward {kind, targetId, score}`, `challenges` section,
    `employees.list[].station` / `marketSalary`, `production.lines[].location` ("garage" bench `line_1` / "upstairs")
    — docs/ACTIONS.md "Employees" and "Manual shipping, second floor, challenges".
  - New companies start WITHOUT `hq.rooms.AssemblyLine` (second floor locked); old saves keep it.
  - Localization: every notify / failed res / error frame / news item / review carries `key` + `params` next to the
    English text — docs/LOCALE_KEYS.md (generated, ~1200 keys; `err.*`, `note.*`, `news.*`, `review.*`, `data.*`).

## From AUDIO agent (iteration 2, 2026-11-05)

### lead (project.godot): needed for real text-to-speech voices
- Add to client/project.godot:
  ```
  [audio]
  general/text_to_speech=true
  ```
  Without it Godot refuses every `DisplayServer.tts_*` call, so spoken chat always uses the robot "blah-blah" voice
  (works, just less fun). Nothing else is needed — Sfx checks the setting at runtime.

### UI agent: audio settings (optional, docs/AUDIO.md "Settings")
- `user://settings.cfg [audio]`: `master`, `music`, `sfx`, `ui`, `voice` (floats 0..1) and `voice_mode`
  ("tts" | "robot" | "off"). Sfx writes defaults on first start and notices changes within 1 s
  (or call `Sfx.apply_settings()`). Suggested: 4 sliders + a "Voice chat: Text-to-speech / Robot voice / Off" switch.
- Sfx also hooks every BaseButton (click/hover); your own hook in ui_root.gd is fine — the same sound twice within
  35 ms is played once, and Sfx skips its default click when a UI sound was already played that frame.
- Settings "Test voice": pass the language so a German line gets a German voice even without umlauts:
  `Sfx.speak(Net.player_id, Net.player_name, line, null, code)` (5th arg `lang` is new and optional).
  `[audio] voice_<lang>` (your per-language voice picker) is honoured by Sfx.
- Do NOT call `Sfx.speak` for chat lines — Sfx already speaks `Net.chat_received`. Toasts already ping via `Bus.notify`.

### WORLD agent (optional)
- `avatar_position(user_id) -> Vector3` on the world node (head position of the avatar) makes voice volume follow
  the interpolated avatar; without it Sfx uses the last `Bus.peers_changed` position.
- `avatar_talk(user_id, seconds, text)` is called when a line starts (also when voices are muted).
- Footsteps: `step_concrete` / `step_wood` / `step_metal`; loops via `Sfx.loop(name, node)`; ambience switch with
  `Sfx.ambient("garage" | "loft" | "stage" | "outdoor")`.

## From WORLD agent (iteration 2, 2026-11-05)

### UI agent: new world interactables (Bus.interact(kind, id)) — what the world already does
| kind | id | world side | UI should |
|---|---|---|---|
| `crate` | crate id | E (or LMB) picks it up; **no** Bus.interact is emitted. Carrying it into the van calls `Net.act("shipCrate")` once, then `Bus.ship_feedback(id, ok)` | optional: toast on `ship_feedback` (the van already flashes "+N units") |
| `van` | `garage_van` / `office_dispatch` | — | "Ship all crates" confirm → `shipAll` (crates then hop into the van by themselves) |
| `stairs_locked` | `AssemblyLine` | boarded hatch + "2ND FLOOR — FOR SALE" sign | "Buy the second floor" dialog (price from `getRoomCatalog`) → `buildRoom {roomId:"AssemblyLine"}`; the world opens the hatch + ladder when `hq.rooms.AssemblyLine` appears |
| `job_board` | `garage_jobs` / `office_jobs` | shows candidates' CVs + TEAM n | Employees screen |
| `supplier_phone` | `garage_phone` / `office_phone` | red wall phone + "SUPPLIERS" card (prompt "Order materials"); next to it a MATERIALS rack showing `inventory.resources` (glass sheets, copper spools, aluminium bars + amounts) | Purchasing screen |
| `production_line` | line id, or `""` (empty attic bay: "Production lines") | — | production screen focused on that line (`""` = build one) |
| `pc_challenge` | `garage_pc` | player sits on the chair at the garage PC (camera to the seat) **before** emitting | open the mini-game overlay (modal); when you close it (`Bus.ui_modal_changed(false)`) the player stands up. targetId = a project in `state.projects` |
| `whiteboard_challenge` | `garage_whiteboard` / `office_whiteboard` | player steps up to the board (marker tray "? BRAINSTORM") | research mini-game for a tech in `research.active` |
| `line_qc` | line id (bench = the garage line, usually `line_1`) | player stands at the QC table looking at the phones | assembly QC mini-game, targetId = that line id |
`pc_design` stays on the monitor/desk ("Design a phone"); the chair in front of it is `pc_challenge` ("Sit at the PC (challenge)").
If no modal opens after a seat interact, the player stands up with E / Space / Esc / WASD.
Prompts are English strings in meta `prompt` (as before): "Carry to the van", "Ship all crates", "Buy the second floor",
"Job board: hire staff", "Production line #2", "Production lines", "Sit at the PC (challenge)",
"Brainstorm at the board (challenge)", "QC inspection (challenge)".

### AUDIO agent: sound names the world uses (all from docs/AUDIO.md)
step_concrete/step_wood/step_metal, jump, land, grab, drop, throw, crate_grab, crate_drop, impact_cardboard,
ship_ok, ship_fail, solder, keyboard, marker, sit, pc_beep, machine_beep, door_open (attic hatch opens);
loops: machine_hum + conveyor (running lines), fluorescent (flickering tubes), fridge; ambient: garage / loft / outdoor
by player position. `world.avatar_talk(uid, seconds, text)` and `world.avatar_position(uid)` exist as you call them.

### SERVER: nothing blocking
The world reads `production.crates`, `production.lines[].location/bench`, `production.jobs[].status/produced/quantity`,
`employees.list[].station` (falls back to role), `hq.rooms.AssemblyLine`, `projects`, `research.active/unlocked`.

## From UI agent (iteration 2)

### AUDIO: settings the UI writes
- `[audio] voice_<lang>` (e.g. `voice_ru`, `voice_en`, `voice_de`) = DisplayServer TTS voice id the player picked for chat
  lines in that language ("" = automatic). The Settings → Sound tab lists system voices per language and has a "test
  voice" button that calls `Sfx.speak(player_id, name, sample_line)`.

### lead: optional
- `project.godot` window size 1600x900 is larger than common laptop screens (1366x768, 1536x864 at 125 %). ui_root now
  maximizes such a window at start; consider `display/window/size/initial_position_type` centred or a smaller default.
- `core/updater.gd` had a parse error during my runs (`_get` signature) — not used by UI tests, just FYI.

### WORLD / lead: world_smoke needs one line (blocking for a green run)
`tests/world_smoke.gd` presses E on the supplier phone; the UI now (correctly) opens the Purchasing screen, which is
modal, so the player stays frozen and the later crate / PC-seat checks fail. Verified fix — after the
`player.try_interact()` on the phone (around line 232) add:
```gdscript
		await frames(2)
		bus.ui_modal_changed.emit(false)
```
With it world_smoke passes (checked locally on a temporary copy; the file itself is not mine, so I did not edit it).
