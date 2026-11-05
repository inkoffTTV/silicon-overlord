# Visual style — "cosy lo-fi garage" (WORLD agent)

Goal: the *feel* of R.E.P.O. (dim practical-lit interiors, soft deep shadows, haze, chunky physical props,
grainy low-res camera) with our own content. No assets, characters, levels or logos from that game are used.
Everything is procedural (code-built meshes + shaders); no downloaded textures, so there is nothing to license.

## Palette
| Role | Colour | Where |
|---|---|---|
| Tungsten warm | `#FFA85C` (1.0, 0.66, 0.36) | bare bulb, desk lamp, string lights, door leak |
| Street cold | `#A6C7FF` (0.65, 0.78, 1.0) | street lamp beam through the window |
| Monitor blue | `#73B3FF` (0.45, 0.7, 1.0) | CRT/monitor glow, shelf LED strips |
| Fluorescent | `#D1F2FF` (0.82, 0.95, 1.0) | workbench tube (flickers), office panels |
| Board green | `#BFFFCC` | company board text, dashboard |
| Neon (stage) | cyan `#33D9FF`, magenta `#FF33BF` | stage only |
| Dusk sky | top `#0F1740`, horizon `#D96B47` | outside, seen through windows |
| Walls / floor | block `#787D73`, concrete `#666360`, wood `#754D2B`, cardboard `#8F693D` | |

Rule of thumb: every room has ONE warm key, ONE cold counter-light, and small coloured practicals (screens, LEDs).

## Lighting rules
- Lights are *practicals*: every light has a visible source (bulb mesh, tube, lamp shade, screen, street lamp).
- Shadows only on key lights. Garage: bulb (omni, dual paraboloid), workbench tube (spot), desk lamp (spot),
  street-lamp beam through the window (spot) + player flashlight = 5 shadowed. Everything else (screens, LED strips,
  string-light fills, door leak, outside lamps) is unshadowed, small range.
- `omni_attenuation` 1.6 (kit default) → pools of light with dark gaps between them. Ambient is tiny
  (`#525C80` × 0.07); dark corners are intended — the flashlight (F) is part of the game.
- Volumetric fog is always on (density 0.035, anisotropy 0.35). Lights that should make shafts get
  `light_volumetric_fog_energy` > 1 (window beam 1.4, stage heads 14); screens use 0.3–0.4 so the room doesn't go milky.
- No directional light indoors (it would leak through walls without shadows); outdoors is lit by street lamps,
  porch lights and emissive windows only.
- Flicker: `res://fx/flicker.gd` (light + emissive material, 120 Hz buzz + random dropouts).

## Post-processing (`res://fx/post_fx.gd` + `post_fx.gdshader`)
CanvasLayer at layer −1 (below the UI) with a full-screen screen-texture shader.

| Setting | lo-fi (default) | clean |
|---|---|---|
| 3D resolution (`scaling_3d_scale`, bilinear) | 0.5 | 1.0 |
| pixel snap (`pixel_size`) | 2 px | 1 |
| chromatic aberration (px at corners) | 1.3 | 0 |
| film grain | 0.055 | 0 |
| vignette | 0.5 | 0.3 |
| lifted blacks | 0.03 (bluish) | 0.015 |
| saturation / contrast | 0.84 / 1.08 | 0.92 / 1.04 |
| ordered dither (4×4 Bayer) levels | 40 | off |
| screen-space AA | off | FXAA |

Plus split toning (cool shadows, warm highlights). Environment: Filmic tonemap, SSAO (r 0.9, ×1.8), soft-light glow
(threshold 0.9). Preset comes from `user://settings.cfg [graphics] quality` (`lofi`/`lo-fi`/`clean`), polled every
second, or `world.apply_quality(q)`.

## Geometry
- Chunky, slightly toy-like: almost every box is a **chamfered box** (`Meshes.cbox(size, bevel)`), bevel 6–15 mm on
  furniture, 20–100 mm on soft things (sofa, avatar). The bevel faces catch light and get "edge wear" in the shader.
- Real-world scale (1 unit = 1 m). Eye height 1.58 m, doors 0.88 × 2.04, desks 0.76 high, ceiling 2.8–3.0.
- Decals (stains, tape, paper) are thin boxes 1–4 mm above the surface with shadows off.

## Material recipes (`res://world/lib/mats.gd`, shader `res://world/shaders/surface.gdshader`)
One uber-shader, object-space (works on moving props, no UVs): pattern + grime + speckle + worn bevels + floor
dirt + derivative bump. Recipes by name, e.g. `Mats.m("block_wall")`, `Mats.m("cardboard", tint)`,
`Mats.m("metal_red", Color.WHITE, {"albedo": c})`.

| pattern | id | used by |
|---|---|---|
| plain | 0 | plaster, plastic, metal, ceramic |
| brick / block (offset rows, mortar, per-cell tint) | 1 | `block_wall`, `brick`, `roof` |
| wood grain | 2 | `wood`, `wood_dark`, `plywood` |
| planks (random offsets, seams) | 3 | `wood_planks`, `siding` |
| tiles (grid) | 4 | `ceiling_tiles`, `floor_tiles` |
| cardboard (tape band + flap seam) | 5 | `cardboard` |
| fabric weave | 6 | `fabric*`, `carpet`, `grass` |
| concrete (oil stains + expansion joints) | 7 | `concrete_floor`, `asphalt`, `sidewalk` |
| pegboard holes | 8 | `pegboard` |
| corrugated | 9 | `rollup` |

Other materials: `Mats.glow(color, energy)` (bulbs, LEDs, lit windows), `Mats.screen(mode, tint, energy, seed)`
(`screen.gdshader`: 0 code editor, 1 phone CAD, 2 dashboard, 3 blank glow; scanlines + flicker), `Mats.glass()`.
Grime 0.25–0.55 everywhere: nothing is clean.

## Props (physics)
`res://world/props/props.gd` → `Props.make(kind, pos, rot, variant)` returns a `RigidBody3D` in group `grabbable`
(meta `prop` = kind). 27 kinds: boxes (s/m/l/heavy 28 kg), crate, mug, can, bottle, phone prototype, PCB, tools,
toolbox, drill, paint can, pizza box, book, tape, cone, keyboard, ball (bouncy), battery, router, trash bin,
office chair, stool. Masses are realistic: the hold force is capped at 300 N, so heavy boxes sag and drag.

### How to add a prop
1. Add a `match` branch in `props.gd/make()` building meshes with `_box/_cyl` (chamfered, recipe materials) and
   collision with `_shape/_cylshape` (keep 1–4 simple shapes), set `mass`.
2. Add the kind to `KINDS`.
3. Place it in a level: `prop("my_kind", Vector3(x, y, z), Vector3(0, yaw_deg, 0), variant)`.
   Spawn it 1–3 cm above the surface; it settles.

## Levels
`res://world/levels/level_base.gd` holds shared furniture builders (desk+PC with its challenge chair, office chair,
whiteboard with live research + challenge tray, assembly table, prototype shelf, job board, company board, calendar,
door, sofa, fridge, bulb, fluorescent tube, poster, outlet) and the staff slots (`add_slot(station, pos, yaw, pose)`).
`level_1_garage.gd` (full), `level_2_office.gd` (rough, also used for 3–7 with bigger floors and the city
dropping away below the windows). Register new levels in `world.gd LEVELS`. Interactables =
`kit.interactable(parent, kind, id, prompt, pos, rot_y)` + `kit.ia_shape(...)`.

## Avatars and staff (`res://world/actors/`)
One procedural rig (`worker_rig.gd`): chunky worker, two-segment arms/legs (so it can sit, type, scribble, carry,
climb), chamfered "toy" boxes, poses driven by `pose` + `move_speed`, mouth flaps on `talk(seconds)`. Two heads:
- **Players — "Telly"** (`peer_avatar.gd`): beige CRT monitor head with a glowing face (eyes + mouth on the screen,
  blinking), hard hat + work shirt in the player's colour, little headlamp, rabbit-ear antenna poking out of the hat,
  name tag. Anim from the network `anim` (idle/walk/run/crouch/carry/air/sit/climb) + measured velocity; head follows
  pitch. `talk()` = screen-mouth opens + speech bubble (`speech_bubble.gd` + `bubble.gdshader`: warm paper, black
  border, tail; billboard). `world.avatar_talk(user_id, seconds, text)`; your own avatar is not drawn (no bubble).
- **Employees — "bean" NPCs** (`npc_worker.gd`): round putty head with googly eyes, hair/cap from the employee id
  (stable look), clothes by role: researcher = lab coat, worker = hi-vis vest + yellow hard hat, QC = vest + blue cap,
  software = headset, marketer/analyst = tie; shirt colour by station (design teal, research white/blue, assembly
  orange/grey, office blue). Name + role tag fades in within ~3 m (fixed screen size). They mutter a short quip
  bubble now and then when you are close, and make work sounds (keyboard, marker, solder).

## Iteration 2: the HQ shows the company (`res://world/live/`, all read `Game.state` only)
| What | Script | Where (garage) |
|---|---|---|
| Prototypes in development (`projects`) built on the back workbench: parts laid out <30% → open shell + board + screen panel <70% → the real phone (phone_builder, blueprint colours) on a holder; build monitor (name, %, day, bugs), crackling solder light + sparks | `dev_bench.gd` | back workbench, 2 slots |
| Finished prototypes (products out of Development) on the shelf stands with their names | `proto_shelf.gd` | prototype shelf |
| Whiteboard: `research.active` names + marker-drawn progress bars + %, sticky notes for recently finished techs | `research_board.gd` | left wall |
| Hand-assembly bench = garage line (`location:"garage"`): status screen, finished phones pile up in the tray, sparks; QC table (`line_qc`) at its right end | `bench_view.gd` | assembly table |
| Second floor = attic over the garage (`hq.rooms.AssemblyLine`): boarded hatch + "2ND FLOOR — FOR SALE" sign (`stairs_locked`) → when bought: open hatch, wooden ladder, railing, fluorescent tubes (one flickers) + a warm bulb, one line per upstairs `production.lines[]` | `loft.gd` | ceiling hatch right-front |
| Production line: parts bins → belt through 1–3 boxy machines (count/size by level, colour by kind) → QC table → open crate that fills up. Running: rollers spin, phones in the product colour ride the belt, sparks + steam, stack light green, hum. Idle amber / blocked blinking amber / down red beacon | `line_view.gd` | attic |
| Crates (`production.crates`): taped cartons with the product colour band + labels (product × units, FRAGILE) on a pallet in the taped SHIPPING corner; carry one into the van → `shipCrate` | `crate_body.gd`, `shipping.gd` | inside the roll-up door, left |
| Delivery van (original boxy van, company name + logo-colour stripe, rear doors open, ramp, cargo light, hazard blinkers, roof beacon). Ship OK: crate slides in and stays as cargo, green flash, "+N units", van bounces; fail: crate pushed back out, red flash | `ship_dock.gd` (style "van"; "chute" = DISPATCH hatch in offices) | driveway (the roll-up door is now open) |
| Staff NPCs on station slots; overflow sits on cardboard boxes | `staff.gd` | desks, whiteboard, bench/lines, sofa |
| Job board: cork board with pinned CVs (candidates) + TEAM n, clip lamp | `job_board.gd` | back wall by the house door |
| Supplier phone (red rotary wall phone, "SUPPLIERS" card, `supplier_phone`) + MATERIALS rack: glass sheets (1 per 100), copper spools (1 per 50), aluminium bars (1 per 40) from `inventory.resources`, amounts on the shelf lips | `level_base.supplier_phone()`, `stock_rack.gd` | left wall between desk and workbench (office: back wall) |

Seats (`player.sit_at`): interactables with meta `seat` {pos, yaw, eye, pitch, pose}. `pc_challenge` = the office chair
at the garage PC (sit, eye 1.14 m), `whiteboard_challenge` = the marker tray ("? BRAINSTORM"), `line_qc` = QC tables
(stand, look down at the phones). Ladders: nodes in group `ladder` with meta bottom_local/top_local.
Footsteps by surface (`level.surface_at`): concrete / wood (attic, ladder) / metal (van ramp). Room tone by
position (`level.ambient_at`): garage / loft / outdoor.

## Screenshots
`xvfb-run -a -s "-screen 0 1600x900x24" <godot> --path client -s res://tools/shot.gd -- --scene=res://world/world.tscn --out=tools/shots`
Options: `--views=a,b`, `--level=2`, `--peers`, `--show=10,2,2,14`, `--quality=clean`, `--hide-ui --player --flashlight`
and `--grab=box_m` (with `main.tscn`), `--dark`. Viewpoints are `Marker3D`s in group `viewpoint` created by each level/stage.

Iteration 2: `res://tools/shot_iter2.gd -- --shots=all` (or build,whiteboard,loft,van,van_fp,crate_fp,staff,avatars,
avatar_close,seat,jobs,shelf,locked,office) loads main.tscn with a rich fake company (`fake_state()`: sample state +
2 projects, 5 crates, bench + 2 upstairs lines, 10 staff) and writes `tools/shots/iter2_*.png` +
`tools/shots/avatars_showcase.png`.

## Iteration 3: story start — the garage is a PHONE REPAIR shop (`res://world/live/repair_shop.gd`, `res://world/story/`)
All driven by `Game.state.story` / `Game.state.repairs` (helpers `world/live/story_state.gd`); no `story` = sandbox.
| What | Where (garage, level space) | Notes |
|---|---|---|
| Outside sign | gable over the roll-up door | story: neon "PHONE REPAIR" (pink letters, cyan tube border + phone/wrench icon, the "I" buzzes); after the story / quick start: backlit company lightbox (name in colour A, logo shape A/B, two gooseneck lamps). `set_sign_override()` for title/cutscenes |
| Shop door `shop_door` | the roll-up door | chapter 0: closed ("CLOSED — back at 9 (probably)" note inside); E rolls it up + `storyEvent door_open` |
| Light switch `light_switch` | front wall by the door (x 0.95) | chunky box, red lever, amber pilot lamp in the dark (green when on). Chapter 0 starts dark: every light/emissive inside the room is off except standby LEDs, the light under the house door and the switch. E = fluorescent tubes stutter on, bulbs/strings pop on, `storyEvent lights_on` |
| Counter `counter` | x[-1.75,-0.05] z≈1.1, faces the door | glass display (cases, cables, earbuds) + teal kick panel, butcher-block top, DROP-OFF tray, grabbable service bell (dings), price stand, candy; hanging lightbox "PHONE REPAIR — while u wait • since last tuesday". Reception look: logo plaque, product on a turntable (real phone model when one exists), plant, "WELCOME!" |
| Repair bench `repair_bench` | right wall, faces -X | ESD mat + phone holder (devices snap in), magnifier ring lamp (shadowed spot), soldering station (350°), drawers, screwdriver fan, multimeter, heat gun, pegboard, "IF IN DOUBT: TURN IT OFF AND ON AGAIN"; SCREENS / BATTERIES / PORTS bins show `inventory.resources.repair_*` ("— OUT!" in red); stool = seat (sit, look down at the device) |
| Gadget shelf | right wall next to the bench | decor: phones with tickets, radio, flip phones, cracked tablet, "FIX ME" laptop, cable spaghetti |
| Customers | from the street | `world/actors/customer_npc.gd`: original bean people, look from the customer id (grandma: bun + glasses + handbag, student: beanie + backpack, courier/taxi: cap, teacher: glasses + briefcase, gamer: kid in a huge hoodie, barista: apron + coffee, musician: beret + scarf, chef: toque, blogger: sunglasses + phone); walk in, ring the bell, hand over the device, wait (phone / tapping foot / crossed arms, "..." after a while), "!" when fixed, cheer + take it when paid, angry exit if the order vanishes |
| Devices | counter tray / bench holder / carried | `world/live/broken_device.gd`: phone / tablet / watch / laptop; cracked screen (star crack), swollen battery, lint in the port, water drops (+ a noodle), glitchy magenta screen, taped button; paper ticket "#3 SCREEN"; fixed = clean glowing screen + green FIXED sticker |
| Objective | any target | `world/story/objective.gd`: pulsing amber rim + outline (material_overlay, shaders `rim` + `outline`) and a floating chevron marker (no depth test, constant size) |
| Van | driveway | hidden in story chapters 0–4 (free driveway for customers / the investor's car) |

Cutscenes (`world/story/cutscenes.gd`, camera paths, paced to the UI captions): intro (night street → the dark sign
sputters → through the window to the friends by the house door), investor (headlights sweep, a long dark car, a figure
in a hat tips it at the door), sign_swap (neon dies, the old sign drops, the company lightbox comes down and lights up
with sparks, counter → reception). The world sends the `*_seen` / `sign_swapped` storyEvent when one ends.

Title screen `res://world/title/title_scene.tscn` (`title_scene.gd`): the same garage built as scenery (`decor_only`:
no collision, groups or state parts) 3 km off the origin, night sky, SSR on wet asphalt/driveway + mirror puddles,
CPU rain streaks + splashes + gutter drips, a buzzing street lamp, house next door, trees and a far skyline, four
"Telly" friends (counter, whiteboard, back workbench, one carrying a box), 72 s Catmull-Rom dolly loop with sway.

Safety nets (0.2.0 "fell out of the world" fix): the outside driveway / sidewalk / street now collide (they did not:
the hole), a thick slab under the whole lot, extra bounds closing the gaps beside the garage corners and over the
van roof, thick invisible panes in windows; `player.gd` respawns at the level spawn below y = -8 (fade from black),
`world.gd` puts fallen props / crates / devices back home. Test: `tests/world_bounds_test.gd`.

Screenshots: `res://tools/shot_story.gd -- --shots=all` (or title,dark,counter,bench,outside,swap,investor,intro) →
`tools/shots/story_*.png`, `tools/shots/title_*.png`.

## Iteration 5 (0.5.0): interior editor, garage expansions, production processes (`res://world/build/`, `world/live/expansions.gd`)
| What | Script | Notes |
|---|---|---|
| Interior data + local rule mirror | `world/build/interior_data.gd` | reads `ui/data/interior.json` (`client/tools/export_interior.py`: lupa export of `Data/Interior`, `Data/RoomGeometry`, `Data/Expansions`, `Data/ProductionProcesses`, `Balance.Interior`). `validate()` = the server's `Interior.check` + role / minHQ / max / room full / cash, same English errors |
| Catalogue meshes | `world/build/interior_items.gd` | all 81 items procedural, chamfered toy boxes + recipe materials; origin = footprint centre (wall items: centre, back on −Z; ceiling items hang from y 0). Lights are small and unshadowed; screens use `Mats.screen` |
| Living decor | `world/build/living_decor.gd` | launch poster = the real phone (phone_builder) rendered ONCE in a SubViewport photo studio on a backdrop in the phone colour + name / year / ★ score; display case + demo table = launched phones on stands; trophy shelf = gold (device of the year) / silver (best of kind) cups + critic plaques (score ≥ 6); history wall = marker timeline (founded, launches, milestones, company news); neon sign = company name in the logo colour; aquarium with swimming fish + bubbles; plants grow 50 → 100 % over `def.grow` days |
| Interior renderer | `world/build/interior_view.gd` | per room: items + pick bodies (layer 10; floor items ≥ 0.3 m also solid), painted wall / floor skins that leave doors, windows and the trapdoor open (`OPENINGS`), lighting preset rigs (warm: amber key + cove strip; daylight: cool overhead; neon: magenta / cyan + strip). Co-op placements pop in with a dust puff (`puff.gd`) |
| Build mode | `world/build/build_mode.gd` (+ `build_inputs.gd`, `ghost.gdshader`) | ghost = additive hologram (green valid / red blocked / cyan carried) + pulsing footprint, room outline + hatched no-build zones (red: doors / stairs / walkway; amber: built-ins), hover outline (`outline.gdshader`), paint highlight of the aimed surface |
| Expansions | `world/live/expansions.gd` | annex lab (cold tube + LED panel, warm sconce; L2 ESD floor, extractor fan, 2nd panel; L3 skylight, HEPA unit, blue strip), basement (block walls, joists, pipes, two bare bulbs; alcoves: shelves L1, server racks L2, cold aisle L3), backyard + board-and-batten shed (L2 lean-to canopy with returns, L3 white interior, LED panels, AC box, lit QUALITY CONTROL sign), glass showroom (track spots; L2 awning + uplights; L3 rooftop totem, red carpet, searchlights). Locked: door shut with a cardboard FOR SALE tag (interactable `expansion_locked`), plot outside staked with caution tape + realtor sign |
| Production processes | `world/live/line_view.gd` | hand = wooden roller bench + 3 lamp-lit hand stations; semi = belt with orange jig plates + 2 pneumatic press gantries; robotic = 2–3 animated orange arms behind a yellow mesh fence; smart = enclosed glass cell, blue strip lights, sweeping blue AI-vision scanner gantry. Retooling: cones, tape, crate of parts, stack light amber/red |
| Day–night | `world/day_night.gd` | one slow cycle per in-game month (≥ 90 s real), dusk at phase 0; sky colours + ambient + `level.daylight_windows()` spots; dark during the early story chapters |

Screenshots: `res://tools/shot_iter5.gd -- --shots=all` → `tools/shots/iter5/*.png`.
