#!/usr/bin/env bash
# Iteration 3 screenshots (title menu, story UI, repair game, goals) -> tools/shots_ui/iter3/<n>_<screen>_<lang>_<WxH>.png
# Usage: tools/ui_shot_iter3.sh [lang=ru] [sizes="1920x1080 1366x768"]
cd "$(dirname "$0")/.."
S=tools/ui_shot.sh
L=${1:-ru}
SIZES=${2:-"1920x1080 1366x768"}
O=tools/shots_ui/iter3
mkdir -p $O
for R in $SIZES; do
  $S menu $L $R --wait=2.0 --out=$O/01_title_menu_${L}_${R}.png
  $S menu_play $L $R --wait=1.5 --out=$O/02_company_slots_${L}_${R}.png
  $S menu_new $L $R --out=$O/03_new_company_choice_${L}_${R}.png
  $S menu_create $L $R --out=$O/04_new_company_form_${L}_${R}.png
  $S loading $L $R --out=$O/05_loading_${L}_${R}.png
  $S credits $L $R --wait=3.0 --out=$O/06_credits_${L}_${R}.png
  $S story $L $R --chapter=1 --step=take_device --world --wait=3 --timeout=240 --out=$O/07_tracker_dialogue_${L}_${R}.png
  $S chapter $L $R --chapter=2 --wait=1.4 --out=$O/08_chapter_card_${L}_${R}.png
  $S cutscene $L $R --id=intro --out=$O/09_cutscene_captions_${L}_${R}.png
  $S repair $L $R --phase=diagnose --out=$O/10_repair_diagnose_${L}_${R}.png
  $S repair $L $R --phase=swap --nopart --out=$O/11_repair_no_part_${L}_${R}.png
  $S repair $L $R --phase=result --wait=1.6 --out=$O/12_repair_result_${L}_${R}.png
  $S counter $L $R --status=waiting --out=$O/13_counter_ticket_${L}_${R}.png
  $S counter $L $R --status=paid --out=$O/14_receipt_paid_${L}_${R}.png
  $S skip $L $R --world --wait=2 --timeout=240 --out=$O/15_skip_story_${L}_${R}.png
  $S final $L $R --wait=3.2 --out=$O/16_final_card_${L}_${R}.png
  $S goals $L $R --out=$O/17_goals_gifts_rp_${L}_${R}.png
  $S settings_controls $L $R --out=$O/18_controls_${L}_${R}.png
  $S quick $L $R --out=$O/19_quick_menu_speed_${L}_${R}.png
done
