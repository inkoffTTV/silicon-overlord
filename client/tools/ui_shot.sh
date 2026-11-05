#!/usr/bin/env bash
# Usage: tools/ui_shot.sh <screen> <lang> <WxH> [extra --args]   -> tools/shots_ui/<screen>_<lang>_<WxH>.png
set -e
cd "$(dirname "$0")/.."
GODOT=${GODOT:-/home/user/tools/godot/Godot_v4.5.1-stable_linux.x86_64}
S=$1; LANG_=$2; SIZE=$3; shift 3
W=${SIZE%x*}; H=${SIZE#*x}
xvfb-run -a -s "-screen 0 ${W}x${H}x24" "$GODOT" --path . --resolution "$SIZE" -s tools/ui_shot.gd -- --screen="$S" --lang="$LANG_" --size="$SIZE" "$@" 2>&1 \
  | grep -v -E "ALSA|snd_|^\s*$|Condition \"status < 0\"|at: (open|_open)|Vulkan|Godot Engine|^$|lavapipe|WARNING: GENERAL|xcb|libdecor" || true
