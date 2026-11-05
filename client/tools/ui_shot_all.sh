#!/usr/bin/env bash
# Renders the main UI screenshots into tools/shots_ui/ (EN + RU, 1280x720 + 1920x1080).
cd "$(dirname "$0")/.."
S=tools/ui_shot.sh
for L in en ru; do
  for R in 1280x720 1920x1080; do
    $S menu $L $R
    $S hud $L $R
    $S designer $L $R --step=6 --bp=bp_84_5 --out=tools/shots_ui/designer_cameras_${L}_${R}.png
    $S research $L $R
  done
  $S designer $L 1920x1080 --step=12 --bp=bp_84_5 --out=tools/shots_ui/designer_branding_${L}_1920x1080.png
  $S designer $L 1920x1080 --step=13 --bp=bp_84_5 --out=tools/shots_ui/designer_review_${L}_1920x1080.png
  $S production $L 1920x1080
  $S shelf $L 1920x1080
  $S company $L 1920x1080
  $S launch $L 1920x1080 --wait=2.2
  $S menu_create $L 1920x1080
  $S menu_join $L 1280x720
  $S settings $L 1280x720
  $S pause $L 1280x720
  $S quick $L 1280x720
done
# iteration 2: new screens (RU 1920x1080), long-word / CJK checks, small-screen designer
R=1920x1080
$S purchasing ru $R --material=Glass --out=tools/shots_ui/purchasing_ru_1920x1080.png
$S purchasing ru $R --tab=suppliers --material=lithium --out=tools/shots_ui/purchasing_suppliers_ru_1920x1080.png
$S employees ru $R
$S van ru $R
$S stairs ru $R --no_floor
$S line ru $R --out=tools/shots_ui/production_line_ru_1920x1080.png
$S challenge ru $R --out=tools/shots_ui/challenge_pick_ru_1920x1080.png
for G in circuit signal bughunt; do $S challenge ru $R --game=$G --wait=2 --out=tools/shots_ui/challenge_${G}_ru_1920x1080.png; done
$S challenge ru $R --source=whiteboard_challenge --game=ideas --out=tools/shots_ui/challenge_ideas_ru_1920x1080.png
$S challenge ru $R --source=line_qc --id=line_2 --game=qc --wait=3 --out=tools/shots_ui/challenge_qc_ru_1920x1080.png
$S challenge ru $R --source=negotiation --id=retailer --game=haggle --out=tools/shots_ui/challenge_haggle_ru_1920x1080.png
$S challenge ru $R --game=circuit --result=0.82 --out=tools/shots_ui/challenge_result_ru_1920x1080.png
$S settings_audio ru $R
$S langpick ru $R
$S designer ru 1366x768 --step=6 --bp=bp_84_5 --out=tools/shots_ui/designer_cameras_ru_1366x768.png
$S designer de $R --step=10 --bp=bp_84_5 --out=tools/shots_ui/designer_specs_de_1920x1080.png
$S employees de $R
$S hud zh $R
$S research zh $R
$S challenge zh $R --source=whiteboard_challenge --game=ideas --out=tools/shots_ui/challenge_ideas_zh_1920x1080.png
$S menu ja $R
