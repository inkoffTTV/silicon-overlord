#!/usr/bin/env bash
# Build the Windows game and publish it to the `builds` branch (download zip + auto-update manifest).
# Usage: tools/release.sh            (version is read from client/project.godot application/config/version)
# Needs: Godot 4.5.1 at $GODOT, Windows export templates installed, a checkout of the builds branch at $BUILDS.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-/home/user/tools/godot/Godot_v4.5.1-stable_linux.x86_64}"
BUILDS="${BUILDS:-/tmp/claude-0/builds}"
VERSION="$(grep -m1 '^config/version=' "$ROOT/client/project.godot" | cut -d'"' -f2)"
ENGINE="$("$GODOT" --version | grep -oE '^[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)"
[[ "$ENGINE" =~ ^[0-9]+\.[0-9]+$ ]] && ENGINE="$ENGINE.0"
OUT="$ROOT/build/SiliconOverlord"
mkdir -p "$OUT"
rm -f "$OUT/SiliconOverlord.exe" "$OUT/SiliconOverlord.pck" "$ROOT/build/SiliconOverlord.zip"
( cd "$ROOT/client" && "$GODOT" --headless --path . --export-release "Windows" "$OUT/SiliconOverlord.exe" >/dev/null 2>&1 )
test -s "$OUT/SiliconOverlord.pck"
( cd "$ROOT/build" && zip -9 -qr SiliconOverlord.zip SiliconOverlord )
cp "$ROOT/build/SiliconOverlord.zip" "$OUT/SiliconOverlord.pck" "$BUILDS/"
cd "$BUILDS"
git add SiliconOverlord.zip SiliconOverlord.pck
git commit -qm "Windows build $VERSION

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01GrSxc2FrBZgYuz6Arnf6Xs"
SHA="$(git rev-parse HEAD)"
SUM="$(sha256sum SiliconOverlord.pck | cut -d' ' -f1)"
SIZE="$(stat -c %s SiliconOverlord.pck)"
cat > version.json <<JSON
{
  "version": "$VERSION",
  "engine": "$ENGINE",
  "pck_url": "https://github.com/inkoffTTV/silicon-overlord/raw/$SHA/SiliconOverlord.pck",
  "pck_sha256": "$SUM",
  "pck_size": $SIZE,
  "zip_url": "https://github.com/inkoffTTV/silicon-overlord/raw/$SHA/SiliconOverlord.zip"
}
JSON
git add version.json
git commit -qm "Update manifest $VERSION

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01GrSxc2FrBZgYuz6Arnf6Xs"
git push -q origin builds
echo "released $VERSION (engine $ENGINE) pack $SUM"
