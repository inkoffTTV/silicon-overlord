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
`res://world/levels/level_base.gd` holds shared furniture builders (desk+PC, whiteboard, assembly table,
prototype shelf, company board, calendar, door, sofa, fridge, bulb, fluorescent tube, poster, outlet).
`level_1_garage.gd` (full), `level_2_office.gd` (rough, also used for 3–7 with bigger floors and the city
dropping away below the windows). Register new levels in `world.gd LEVELS`. Interactables =
`kit.interactable(parent, kind, id, prompt, pos, rot_y)` + `kit.ia_shape(...)`.

## Avatars
"Telly": chunky worker with a CRT-monitor head (glowing face in the player's colour, blinking eyes), rabbit-ear
antenna, hoodie tinted by the player's colour, mitten hands, stubby legs; name tag above. Original design.

## Screenshots
`xvfb-run -a -s "-screen 0 1600x900x24" <godot> --path client -s res://tools/shot.gd -- --scene=res://world/world.tscn --out=tools/shots`
Options: `--views=a,b`, `--level=2`, `--peers`, `--show=10,2,2,14`, `--quality=clean`, `--hide-ui --player --flashlight`
(with `main.tscn`), `--dark`. Viewpoints are `Marker3D`s in group `viewpoint` created by each level/stage.
