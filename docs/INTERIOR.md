# Iteration 5 (0.5.0): interior editor, base expansion, production technologies, room design

## 1. Interior editor (build mode)
- Key **B** (or the "Build" button in the Tab menu / any room's job-board-like "Catalog" tablet) toggles build mode
  in first person: a catalog bar at the bottom (categories: Desks & seating, Lab & tools, Production, Storage,
  Decor, Lighting, Plants, Walls & floors), a ghost preview at the aim point that snaps to a 0.25 m grid and 15°
  rotation (R / mouse wheel), green = valid, red = blocked (collision, outside room bounds, blocking doors/paths,
  over budget). LMB place, E pick up an existing item to move it, X sell (refund 50%), C copy, Esc leave.
- Walls & floors: paint/wallpaper/flooring per room surface (materials: concrete, plank, tile, carpet, brick, paint
  colour picker), applied by aiming at a surface.
- Functional items count for the game: desks/seats raise the room's staff capacity, lab benches raise research
  slots/speed a little, shelves raise storage for crates, lights/plants/decor raise the room's **Comfort**.
- Server authoritative: state `interior = { rooms: { [roomId]: { items: [{id, def, x, z, y?, rot, color?}], surfaces:
  { wall?: {mat, color}, floor?: {mat, color} }, theme? } } }`. Actions: `interiorPlace {room, def, x, z, rot, color?}`,
  `interiorMove {room, id, x, z, rot}`, `interiorRemove {room, id}`, `interiorPaint {room, surface, mat, color}`,
  `interiorTheme {room, theme}`. Server validates def exists, cost, room unlocked, bounds (room AABB from
  `Data/RoomGeometry` — a shared table of each room's footprint in local metres), overlap (AABB per def footprint),
  max items per room. Co-op: everyone sees placements live (state sections).
- Existing furniture data (`shared-luau/Data/Furniture.luau`, `buyFurniture` with spot) is migrated into this model.

## 2. Base expansion
The garage grows physically before the move to an office (HQ level ≥ 2 keeps working as today):
| Expansion (room id) | Where | Unlocks | Price (suggested) |
|---|---|---|---|
| Loft (AssemblyLine, exists) | upstairs | production lines | 150 000 |
| Side annex lab (ResearchLab) | new door in the left wall | +research slot, lab benches | 90 000 |
| Basement (Warehouse/ServerRoom) | trapdoor + stairs down | crate storage ×3, server racks (ecosystem) | 120 000 |
| Backyard workshop (QualityControl) | through the back door, a shed | QC line, defect −% | 70 000 |
| Showroom front (Showroom) | the old repair counter area | brand, display your phones | 60 000 |
Action `buildExpansion {id}` (or existing `buildRoom` with these ids + level caps at HQ 1). World builds each one
attached with a real doorway, its own lighting/ambience. Upgrades (`buildRoom` level+1) visibly enlarge/equip it.

## 3. Production technologies
Each production line gets a **process**: `hand` (garage bench) → `semi` (jigs + conveyor) → `robotic` (robot arms)
→ `smart` (lights-out, AI vision QC). Each process has capacity ×, defect ×, energy, staff per line, setup cost,
switch time (line idle N days), and requires a Manufacturing tech (map to existing TechTree ids of the Manufacturing
branch; document the mapping). Action `setLineProcess {lineId, process}`. The world shows a different machine per
process (bench with hand tools / conveyor with jigs / robot arms / enclosed cell with blue scanner light).
UI: production line screen shows a process comparison table and the switch button.

## 4. Room design (lead's ideas)
- **Comfort score** per room 0–100 from decor/light/plants/space per person/theme coherence; effects (capped):
  morale +, research speed + (lab), defect − (production), creativity → design quality + (design room). Shown as a
  small gauge in build mode and in the company board.
- **Themes** per room: Garage Grunge, Cozy Wood, Clean Lab, Neon Cyber, Scandinavian. A theme recolours surfaces and
  unlocks matching decor; coherence bonus when ≥ 60% of decor matches.
- **Living decor**: posters of YOUR launched phones (auto-generated from blueprints), trophy shelf with awards
  and critic scores, a whiteboard history wall, an aquarium, arcade cabinet, coffee machine (staff morale), plants
  that grow over in-game months, a neon sign with the company name.
- **Lighting presets** per room (warm / daylight / neon) and a day–night cycle through the windows.
