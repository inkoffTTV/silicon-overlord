# Common rules for iteration-2 agents
- Project: /home/user/SiliconOverlordOnline (Godot 4.5.1 client in client/, Python+lupa server in server/, Luau rules in shared-luau/).
- Godot binary: /home/user/tools/godot/Godot_v4.5.1-stable_linux.x86_64. Render with
  `xvfb-run -a -s "-screen 0 1600x900x24" <godot> --path client ...` and LOOK at PNGs with the Read tool; iterate until good.
- Read docs/ARCHITECTURE.md fully (incl. "Iteration 2 contracts" and "Iteration 2b"), docs/ACTIONS.md, docs/PROTOCOL.md, client/core/bus.gd, client/audio/sfx.gd.
- Stay inside your owned paths. Need something elsewhere → append to docs/REQUESTS.md. Never git commit/push (lead does).
- The user is not a programmer and speaks Russian: final report in Russian, short and plain, with exact screenshot paths and honest known issues.
- Original art/design only (no copying R.E.P.O or other games' assets/characters); the vibe is "moody lo-fi R.E.P.O-like".
- Keep all existing tests passing: server `python3 server/tests/run.py`, client `tests/ui_smoke.gd`, `tests/world_smoke.gd` (headless/xvfb).
