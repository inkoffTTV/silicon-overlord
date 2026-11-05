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
