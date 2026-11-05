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
