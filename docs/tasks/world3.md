# WORLD agent — iteration 3 (port 7472)
Owns: client/world/**, client/player/**, client/fx/**, client/tools/shot*, client/tests/world_*, docs/VISUAL_STYLE.md.
1. Repair-shop dressing of the garage driven by Game.state.story/repairs (see docs/STORY.md "Client contract"):
   "PHONE REPAIR" sign (outside + inside), customer counter with bell, repair bench with magnifier lamp + tools,
   shelves of broken gadgets, interactables shop_door, light_switch (starts dark: chapter 0), counter (id = orderId),
   repair_bench; customer NPCs (original, varied, walk in from the street, wait, react, leave) from repairs.orders;
   broken devices as grabbable props tagged with orderId (carry counter → bench → counter). Call Net.act/storyEvent
   for door/lights per ACTIONS.md. world.story_stage(chapter, step) highlights the current objective object
   (soft glow outline / floating marker).
2. Cutscenes (Bus.story_cutscene): "intro" (street at night → push in through the door, captions are UI's job),
   "investor" (simple staging: a car pulls up / a figure at the door), "sign_swap" (old sign taken down, new company
   sign with company colours/name goes up; counter → reception). Camera paths with the player restored after.
   Emit Bus.story_dialogue(line_id) at cutscene beats if useful.
3. Title-screen 3D scene res://world/title/title_scene.tscn: the repair-shop garage seen from the street at night,
   light rain, wet asphalt reflections, flickering neon sign, warm light inside with 2–3 friends (avatars) tinkering,
   slow camera dolly loop, same lo-fi post FX. Must look like a real game's title screen. Expose set_company_sign(text, color).
4. Tests in world_smoke (counter/bench/door/light interactables per chapter, NPC per order, sign swap) + screenshots:
   title scene (3 angles), chapter 0 dark garage, chapter 1 customer at the counter, repair bench close-up, sign swap.
