# Common rules for iteration-3 agents (story start + title menu)
- Project: /home/user/SiliconOverlordOnline. Read docs/STORY.md FIRST (the design + contracts for this iteration),
  then docs/ARCHITECTURE.md, docs/ACTIONS.md, docs/PROTOCOL.md, client/core/bus.gd, client/audio/sfx.gd, docs/UI.md, docs/VISUAL_STYLE.md, docs/AUDIO.md.
- Godot 4.5.1: /home/user/tools/godot/Godot_v4.5.1-stable_linux.x86_64; render with `xvfb-run -a -s "-screen 0 1600x900x24" <godot> --path client ...` and LOOK at PNGs with the Read tool; iterate until good. Use your own server port (given in your brief) for live tests.
- Stay in your owned paths (in your brief); cross-area needs → docs/REQUESTS.md. Never git commit/push (the lead does).
- Never break existing saves or quick-start play: all existing tests must stay green (server run.py, ui_smoke, ui_layout_test, ui_i18n_test, audio_smoke, updater_test, ui_net_test, world_smoke).
- The user is a non-programmer, Russian-speaking; final report in Russian, short and plain, exact screenshot paths, honest known issues.
- Original content only (no copied characters/brands). Tone: warm, funny, a bit nerdy — friends fixing gadgets at night.
