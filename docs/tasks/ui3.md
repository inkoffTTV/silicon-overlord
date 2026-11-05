# UI agent — iteration 3 (port 7473)
Owns: client/ui/**, client/net/**, client/phone/**, client/tests/ui_*, client/tools/ui_shot*, docs/UI.md
(except client/ui/data/story/** which NARRATIVE owns — read it).
1. Main menu "like a separate game" per docs/STORY.md: over the WORLD title scene (res://world/title/title_scene.tscn —
   use a fallback backdrop until it exists): big logo, Play / Settings / Credits / Quit, Play → company slots from
   listMyCompanies (Continue, New company → Story (recommended) / Quick start, Join by code), nickname chip, server
   status, version + Updater status, keyboard/gamepad navigation, hover/confirm sounds, animated transitions,
   loading screen with tips (11 languages). Credits screen.
2. Story UI: objective tracker, dialogue subtitles with speaker + typewriter + Sfx.speak per character voice,
   chapter title cards, story notifications, "Skip story" (owner, confirm) in pause, speed buttons disabled with
   reason while the clock is paused, smooth transition card at the end ("Repair shop → <Company>").
3. Repair mini-game (Bus.interact("repair_bench", orderId)): open the device (screws), diagnose the fault, swap the
   part (needs the part in stock → else link to Purchasing), close up; 30–60 s; score → repairFinish. Counter
   interaction (repairTake / repairReturn) handled via Bus.interact("counter", orderId) with a small receipt popup.
4. Tests: ui_smoke/ui_layout/ui_i18n extended to the new menu, story UI and repair game (all 11 languages fit);
   ui_net_test: create story company → complete chapter 1 via actions. Screenshots (RU 1920x1080 + 1366x768):
   title menu, slots, new-company choice, loading screen, objective tracker + dialogue, chapter card, repair game,
   receipt, skip dialog, final transition card.
