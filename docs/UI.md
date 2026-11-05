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
xvfb-run -a -s "-screen 0 1600x900x24" <godot> --path client --resolution 1600x900 -s tools/ui_shot_playtest.gd
                                                             # full game + server: design -> develop -> build -> launch -> sell
# screenshots with fake state
client/tools/ui_shot.sh <screen> <en|ru> <WxH> [--step=N --bp=ID --branch=Silicon ...]   -> client/tools/shots_ui/
client/tools/ui_shot_all.sh                                  # the whole set (slow under lavapipe)
<godot> --headless --path client -s tools/ui_shot_check.gd   # compile check of every ui/net/phone/tests script
python3 client/tools/export_data.py                          # shared-luau data + Roblox Locale -> client/ui/data/*.json
```

## Structure
| file | what |
|---|---|
| net/net.gd | autoload `Net`: WebSocket client. `await Net.create_company/join/resume`, `await Net.act(action, args)` (id matching, 10 s timeout), `set_speed`, `send_pos` (10 Hz), `chat`, `leave`; reconnect with backoff 1-2-4-8-15 s + auto `resume`; token in `user://profile.cfg`. `Net.mock_handler` replaces the socket in tests. |
| ui/ui_root.gd | CanvasLayer: 1440x810 logical canvas scaled to the window (viewport oversampling keeps text crisp); main menu / HUD / screens / toasts / chat / pause (Esc) / quick menu (Tab) / launch overlay; emits `Bus.ui_modal_changed`. |
| ui/lib/uit.gd | design tokens, Theme resource (button variants BtnPrimary/BtnWhite/BtnSeg/BtnRow/...), widget factories, tweens |
| ui/lib/loc.gd + loc_extra.gd | EN->RU: Roblox phrase table with `#` (numbers) / `@` (text) templates + client-only phrases. Default language from OS locale, saved in `[ui] lang`. |
| ui/lib/wizard.gd | port of DesignWizard (steps, option rows, lock reasons, facets, quick picks, finishes) |
| ui/lib/research_layout.gd | port of ResearchLayout (lanes, tiers, in-lane links only, effect texts EN/RU) |
| ui/lib/gdata.gd | read-only game data from ui/data/*.json |
| ui/menu/* | main menu (name, Continue, New company: name + 2 colours + solo/co-op, Join by code, Settings, Quit), settings panel |
| ui/hud/* | top bar (company, room code + copy, date, cash, RP, team, reputation, speed, members), [E] prompt, dev chip, toasts (coalesced), chat |
| ui/screens/designer.gd | Design Studio, 13 steps, live 3D model, cost card, critics preview (server evaluateBlueprint), undo/redo, concept shelf, publish |
| ui/screens/research.gd | research board + details (startResearch / cancelResearch) |
| ui/screens/production.gd | dev projects (finish now / fix bug / add quality / cancel), batches (queueProduction), lines, incidents, launch |
| ui/screens/shelf.gd | your devices: sales chart, reviews, price (setPrice), launch, discontinue, rivals |
| ui/screens/company.gd | money, weekly revenue, market share, reputation, team, owners, bank loan, news |
| ui/screens/launch_overlay.gd | critics' score /10 + stars + verdict + quotes, after the world's stage show |
| phone/phone_builder.gd | procedural device model (port of DeviceModelBuilder): bevelled body, accent frame, glass, live home screen, camera bump/lenses/OIS/flash, selfie hole, side buttons, port + speaker holes, logo styles, finishes (brushed, carbon, pearl...), foldable; simple laptop/box fallbacks |
| phone/phone_preview.gd | SubViewport stage: lights, pedestal, orbit camera, view presets, auto-spin |

## Bus usage
- listens: `interact(kind, id)` (pc_design, whiteboard_research, workbench_production, phone_shelf, stage_launch,
  board_company, door_exit -> pause menu), `focus_changed`, `notify`, `state_changed`.
- emits: `ui_modal_changed`, `launch_show(product_id)` (own launches and launches by co-founders).
