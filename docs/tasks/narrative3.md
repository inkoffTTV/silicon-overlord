# NARRATIVE agent — iteration 3
Owns: client/ui/data/story/** and docs/STORY_SCRIPT.md.
Write the full story script for docs/STORY.md chapters 0–6 (wait for the step ids in docs/ACTIONS.md "Story & repairs"
from the SERVER agent; until then draft with the step names from STORY.md and align later):
- Characters: the 2–4 founders are the PLAYERS (address them as a team, no fixed names; lines are spoken by
  original NPCs: customers (10+ distinct with personalities and their broken gadgets and funny fault stories),
  a mentor-ish neighbour or the landlord, the investor, a critic voice at launch). Warm, funny, short lines (≤140 chars),
  never block gameplay; each step: objective text (≤60 chars) + 0–3 dialogue lines + optional hint.
- Output JSON per language client/ui/data/story/<lang>.json with a documented schema (write the schema at the top of
  docs/STORY_SCRIPT.md): chapters[{id,title,subtitle,steps[{id,objective,hint,lines[{id,speaker,text}]}]}],
  customers[{id,name,device,fault,lines{arrive,wait,happy,angry}}], cutscenes{intro,investor,sign_swap: captions[]},
  tips[] (loading screen, 20+), credits text.
- Languages: ru, en written natively and carefully; then uk, de, es, pt_BR, fr, pl, tr, zh, ja translations
  (keep placeholders like {company}, {player}, {money}). Validate JSON and that every id exists in every language
  (write a tiny checker script in client/tools/check_story.py and run it).
