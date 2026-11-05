# UI (client/ui, client/net, client/phone)

## Run / test
```
# server
python3 server/main.py --port 7350 --data /tmp/sos
# client (default server ws://127.0.0.1:7350/ws, change in Settings or with env SOO_SERVER=ws://host:port/ws)
<godot> --path client
# tests
<godot> --headless --path client -s tests/ui_smoke.gd        # all screens with fake state, no server
<godot> --headless --path client -s tests/ui_net_test.gd     # starts server/main.py itself (port 7391), skips if it can't
<godot> --headless --path client -s tests/ui_i18n_test.gd    # every UI string in 11 languages, placeholders, CJK glyphs, DE/RU/ZH/JA screens fit
<godot> --headless --path client -s tests/ui_layout_test.gd  # 10 window sizes (1280x720 .. 2560x1440, 21:9, 4:3, 800x600) x 7 languages: nothing off screen
                                                             # (+ title menu pages in EN/RU/DE/ZH, story HUD / repair / counter / goals / final card / loading in RU)
<godot> --headless --path client -s tests/ui_net_test.gd -- --port=7473   # + Story start: clock paused, intro captions -> storyEvent,
                                                             #   chapter 1 with two real repairs (one via the counter + repair bench screens), listMyCompanies
xvfb-run -a -s "-screen 0 1600x900x24" <godot> --path client --resolution 1600x900 -s tools/ui_shot_playtest.gd
                                                             # full game + server: design -> develop -> build -> launch -> sell
# screenshots with fake state
client/tools/ui_shot.sh <screen> <en|ru> <WxH> [--step=N --bp=ID --branch=Silicon ...]   -> client/tools/shots_ui/
client/tools/ui_shot_all.sh                                  # the whole set (slow under lavapipe)
client/tools/ui_shot_iter3.sh [ru] ["1920x1080 1366x768"]   # iteration 3: title menu, slots, story/quick, loading, credits, tracker +
                                                             # dialogue (with the 3D garage), chapter card, captions, repair game,
                                                             # ticket / receipt, skip story, final card, goals, controls -> tools/shots_ui/iter3/
client/tools/ui_shot_iter5.sh [ru] ["1920x1080 1366x768"] [--world]  # 0.5.0: build mode (catalogue, annex lab, walls & floors,
                                                             # placed, error, aiming bar), Grow the base (+ confirm), process table
                                                             # (+ confirm), retooling line, company comfort, quick menu -> tools/shots_ui/iter5/
<godot> --headless --path client -s tests/ui_net_test.gd -- --port=7503   # + 0.5.0: build mode against the live server (place / move /
                                                             #   undo / paint / theme / light / blocked spot / sell), buy the showroom and
                                                             #   furnish it, research Factory Automation 1 and switch line_1 to semi
<godot> --headless --path client -s tools/ui_shot_check.gd   # compile check of every ui/net/phone/tests script
python3 client/tools/export_data.py                          # shared-luau data + Roblox Locale -> client/ui/data/*.json (+ sample_interior.json)
python3 client/tools/export_interior.py                      # (WORLD) 0.5.0 catalogue + room geometry -> client/ui/data/interior.json
```

## Structure
| file | what |
|---|---|
| net/net.gd | autoload `Net`: WebSocket client. `await Net.create_company/join/resume`, `await Net.act(action, args)` (id matching, 10 s timeout), `set_speed`, `send_pos` (10 Hz), `chat`, `leave`; reconnect with backoff 1-2-4-8-15 s + auto `resume`; token in `user://profile.cfg`. `Net.mock_handler` replaces the socket in tests. |
| ui/ui_root.gd | CanvasLayer: 1440x810 logical canvas scaled to the window (viewport oversampling keeps text crisp); main menu / HUD / screens / toasts / chat / pause (Esc) / quick menu (Tab) / launch overlay; emits `Bus.ui_modal_changed`. |
| ui/lib/uit.gd | design tokens, Theme resource (button variants BtnPrimary/BtnWhite/BtnSeg/BtnRow/...), widget factories, tweens |
| ui/lib/loc.gd + loc_extra.gd | English source text -> 11 languages (en ru uk de es pt fr pl tr zh ja). RU: Roblox phrase table + loc_extra; all languages: `ui/i18n/*.json` rows `"English": [ru, uk, de, es, pt, fr, pl, tr, zh, ja]` ("" = English fallback), `#` numbers / `@` text templates. Server texts by key (`L.server(key, params, english)`, `ui/i18n/server.json`, docs/LOCALE_KEYS.md). Default language from the OS locale, saved in `[ui] lang`. |
| ui/i18n/*.json | translations: client_a/b (core UI), iter2 (new screens, mini-games), game (designer steps, research tracks, tech names), world (world prompts), purchasing, server (server keys) |
| ui/lib/lang_picker.gd | language picker overlay (native names), used by the main menu and Settings |
| ui/fonts/Noto*.otf | CJK fallback (Noto Sans SC / JP Medium subsets, OFL, ~1 MB each), rebuilt by ui/fonts/make_cjk_subset.py |
| ui/lib/wizard.gd | port of DesignWizard (steps, option rows, lock reasons, facets, quick picks, finishes) |
| ui/lib/research_layout.gd | port of ResearchLayout (lanes, tiers, in-lane links only, effect texts EN/RU) |
| ui/lib/gdata.gd | read-only game data from ui/data/*.json |
| ui/menu/main_menu.gd | title screen "like a separate game": backdrop + logo + big items Continue / Play / Settings / Credits / Quit; Play = company slots (`listMyCompanies`: name, date, money, role, story chapter, last played) + New company (Story start (recommended) / Quick start -> name, colours, solo/co-op; `create.storyMode`) + Join by code; nickname chip, language, server status + Retry, version + updater state, rolling credits (story file `credits`). Keyboard / gamepad: focus moves with arrows / d-pad, Enter / A selects, Esc / B goes back; hovering a slot / typing a name previews it on the shop sign |
| ui/menu/title_backdrop.gd | WORLD's `res://world/title/title_scene.tscn` in a SubViewport (threaded load, fades in, root 3D off while it covers the screen); painted rainy-street fallback with a flickering neon sign until it exists |
| ui/menu/loading_screen.gd | entering a company: name, progress, rotating tips (story file `tips` + key tips, 11 languages); ui_root shows it on `menu.enter_started`, `done()` / `cancel()` |
| ui/menu/settings_panel.gd | tabs General / Sound / Controls (every key incl. time keys 1-4, P/0, +/-) / Server |
| ui/story/story_data.gd | read-only story texts `ui/data/story/<lang>.json` (NARRATIVE, docs/STORY_SCRIPT.md): chapters, steps, lines, speakers + voices, customers, devices / faults / parts, cutscene captions, tips, credits; English / built-in fallback |
| ui/story/story_ui.gd | story director (one thing at a time): chapter cards, cutscene captions (follows the world's camera; alone + storyEvent when no world plays it; Esc skips), dialogue subtitles (typewriter + `Sfx.speak` per character voice), customer lines from `repairs.orders`, story banners for `story.*` notifies, `notice_pattern` dialogue -> storyEvent, the modal "Repair shop -> company" card when the story ends (sections only) |
| ui/story/objective_tracker.gd | HUD top-left: chapter + steps (server `story.objectives`) with checkmarks, hint, repair orders, "time starts at chapter 4" |
| ui/story/counter_dialog.gd | `counter` (orderId): paper ticket / receipt, repairTake, repairReturn -> PAID stamp |
| ui/story/repair_game.gd + repair_board.gd | `repair_bench` (orderId): unscrew -> probe -> swap part (stock, "Order parts" -> Purchasing) or hold to clean / reflash / free -> close up; 30-60 s; score -> repairFinish |
| ui/screens/goals.gd | "Goals & gifts" (quick menu, HUD RP chip): current goal + all 28 (ui/data/goals.json), daily gift strip + claimDaily, where research points come from (rate per day) |
| ui/hud/* | top bar (company, room code + copy, date, cash, RP chip (tooltip: RP sources + rate, click = Goals & gifts), team, reputation, speed with key labels P/1-4 (locked with a reason while the story clock is paused), members), left column (objective tracker, goal card, daily gift ready, dev chip, crates), [E] prompt, toasts (coalesced), chat |
| ui/screens/designer.gd | Design Studio, 13 steps, live 3D model, cost card, critics preview (server evaluateBlueprint), undo/redo, concept shelf, publish |
| ui/screens/research.gd | research board + details (startResearch / cancelResearch, "Boost +25% · 100 RP" = boostResearch) |
| ui/screens/production.gd | dev projects (finish now / fix bug / add quality / cancel), batches (queueProduction), lines, incidents, launch; 0.5.0: each assembly line shows its process + a retooling countdown, "Production process" opens the comparison table (capacity /week, defects, energy, operators, setup cost for this line, downtime, required techs with links to the research board) -> confirm -> `setLineProcess` |
| ui/screens/shelf.gd | your devices: sales chart, reviews, price (setPrice), launch, discontinue, rivals |
| ui/screens/company.gd | money, comfort & rooms (average ring, capped effects: morale / research / defects / design / brand, staff / lab / crate bonuses, comfort per room, Furnish + Grow the base), weekly revenue, market share, reputation, team, owners, bank loan, news |
| ui/screens/employees.gd | "job_board": candidates (portrait, role, skill, salary, Hire), staff by station (salary -/+, Fire), new candidates for RP |
| ui/screens/purchasing.gd | "supplier_phone" / quick menu / production / blocked toast: materials (stock, need/day, days left, spot price, used by, Buy 1/7/30 days or custom) and suppliers (offers, contract form with weeks slider + discount, active contracts) |
| ui/screens/dialog_van.gd, dialog_stairs.gd | "van": ship all crates (+5%), haggle; "stairs_locked": buy the second floor (getRoomCatalog price) |
| ui/challenges/* | mini-games: challenge_screen (pick -> intro -> 3-2-1 -> play -> result -> challengeReward; Esc = no reward), circuit + signal_match (PC research), bug_hunt (PC design), ideas (whiteboard), qc_line (line_qc), haggle (van / supplier negotiation) |
| ui/screens/launch_overlay.gd | critics' score /10 + stars + verdict + quotes, after the world's stage show |
| ui/hud/build_hud.gd | 0.5.0 build mode (key **B**, quick menu, company board, a `build_catalog` interactable): room tabs (locked expansions -> Grow the base), comfort gauge 0–100 with the 5 parts + preview of the selected item + the room's effect + "What to add"; budget, undo (Ctrl+Z: last placement sold back 50 % / last move reverted), room style (5 themes, light preset); catalogue (search, 8 categories + "Placed here" with Sell / Copy / Move, item cards: thumbnail, price, comfort, effects, HQ / room locks), Walls & floors (wall / floor, materials, swatches + any colour), the selected item's card (size, comfort, effects, themes, max, growth, living decor, colour, Place automatically / Aim). Tab = catalogue open (modal, mouse free) / closed (slim bar with the world's hover status, the player aims). Server errors in a banner. World contract (`build_mode`, `build_select`, `build_hover`, `build_request`, `build_result`) in docs/REQUESTS.md |
| ui/lib/interior_rules.gd | client mirror of Domain/Interior (check, autoSpot, comfort + parts, suggestions, expansion / process costs) over `ui/data/interior.json` |
| ui/lib/item_thumb.gd, ui_ring.gd, base_diagram.gd | code-drawn catalogue thumbnails / material swatches, the comfort ring, the "Grow the base" blueprint picture |
| ui/screens/expansions.gd | "Grow the base" (`expansions`, `expansion_locked` id, `stairs_locked` = loft): 5 cards (picture, where, what it does now / next level, room size, price, level pips, lock reason), confirm -> `buildExpansion`, Furnish -> build mode in that room |
| phone/phone_builder.gd | procedural device model (port of DeviceModelBuilder): bevelled body, accent frame, glass, live home screen, camera bump/lenses/OIS/flash, selfie hole, side buttons, port + speaker holes, logo styles, finishes (brushed, carbon, pearl...), foldable; simple laptop/box fallbacks |
| phone/phone_preview.gd | SubViewport stage: lights, pedestal, orbit camera, view presets, auto-spin |

## Bus usage
- listens: `interact(kind, id)` (pc_design, whiteboard_research, workbench_production, phone_shelf, stage_launch,
  board_company, job_board, van, stairs_locked, production_line, supplier_phone, pc_challenge, whiteboard_challenge,
  line_qc, counter, repair_bench, door_exit -> pause menu; 0.5.0: build_catalog -> build mode, expansions / expansion_locked (id) /
  stairs_locked -> Grow the base), `focus_changed`, `notify`, `state_changed`,
  `story_dialogue(line_id)` (step / cutscene / `cust.<id>.<kind>` lines, `customer:<id>:wait`), `story_cutscene(id)` (captions).
- story events the UI sends (`storyEvent`): `intro_seen` / `investor_seen` / `sign_swapped` only when no world played the
  cutscene, `pattern_noticed` after the chapter-3 dialogue, `supplier_called` (supplier phone), `reviews_seen` (critics card closed).
- `Net.set_speed` is not sent while the story clock is paused (chapters 0-3); the first try shows one friendly toast.
- Pause and quick menus have a game-speed row (the HUD bar is under their dimmer); pause has "Skip story" for the founder
  (confirm -> `storySkip`).
- Settings write `[audio] master/music/sfx/ui/voice`, `voice_mode` (tts/robot/off) and `voice_<lang>` (TTS voice id per
  language) and call `Sfx.apply_settings()` + emit `Bus.settings_changed`. Chat lines are spoken by Sfx itself (docs/AUDIO.md).
- Every UI button gets `Sfx.ui("click")` / `"hover"` through one hook in ui_root; screens play open/close.
- emits: `ui_modal_changed`, `launch_show(product_id)` (own launches and launches by co-founders).
