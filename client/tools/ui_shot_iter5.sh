#!/usr/bin/env bash
# Iteration 5 (0.5.0) screenshots: build mode, walls & floors, room style, expansions, production processes, company
# comfort -> tools/shots_ui/iter5/<n>_<screen>_<lang>_<WxH>.png
# Usage: tools/ui_shot_iter5.sh [lang=ru] [sizes="1920x1080 1366x768"] [--world]
cd "$(dirname "$0")/.."
S=tools/ui_shot.sh
L=${1:-ru}
SIZES=${2:-"1920x1080 1366x768"}
W=${3:-}
O=tools/shots_ui/iter5
mkdir -p $O
for R in $SIZES; do
  $S build $L $R $W --timeout=240 --wait=2 --def=plant_monstera --out=$O/01_build_catalog_${L}_${R}.png
  $S build $L $R $W --timeout=240 --wait=2 --cat=lab --def=lab_bench --room=annex --out=$O/02_build_annex_lab_${L}_${R}.png
  $S build $L $R $W --timeout=240 --wait=2 --cat=surfaces --out=$O/03_build_walls_floors_${L}_${R}.png
  $S build $L $R $W --timeout=240 --wait=2 --cat=placed --out=$O/04_build_placed_${L}_${R}.png
  $S build $L $R $W --timeout=240 --wait=2 --def=desk_pine --error="Blocked: doorway" --out=$O/05_build_error_${L}_${R}.png
  $S build $L $R $W --timeout=240 --wait=2 --slim --def=desk_pine --hover="Blocked: walkway" --out=$O/06_build_aiming_${L}_${R}.png
  $S expansions $L $R --id=basement --out=$O/07_grow_the_base_${L}_${R}.png
  $S expansions $L $R --id=shed --confirm=shed --out=$O/08_expansion_confirm_${L}_${R}.png
  $S process $L $R --line=line_2 --out=$O/09_process_table_${L}_${R}.png
  $S process $L $R --line=line_2 --robotic --confirm=robotic --out=$O/10_process_confirm_${L}_${R}.png
  $S production $L $R --retool --out=$O/11_production_retooling_${L}_${R}.png
  $S company $L $R --out=$O/12_company_comfort_${L}_${R}.png
  $S quick $L $R --out=$O/13_quick_menu_${L}_${R}.png
done
