#!/usr/bin/env bash
# Build the Windows game and publish it to the `builds` branch (download zip + auto-update manifest).
# Usage: tools/release.sh                       (version is read from client/project.godot application/config/version)
#        tools/release.sh --voice-only linux DIR   only assemble the character-voice folder (Linux piper) into DIR,
#                                                  e.g. for SO_VOICE_DIR=DIR client/tests/audio_voice_test.gd
#        tools/release.sh --list-voices            print the voice models that would be shipped (lang name)
#        tools/release.sh --licenses-only DIR      only fetch the third-party licence texts into DIR (pinned sha256)
#        tools/release.sh --vcrt-only DIR          only extract the MSVC runtime DLLs piper.exe needs into DIR
#        tools/release.sh --sources-only DIR       only write the GPL Corresponding Source archives into DIR
#        tools/release.sh --package-only PARENT    zip PARENT/SiliconOverlord into PARENT/SiliconOverlord.zip (full) +
#                                                  PARENT/SiliconOverlord-builds.zip (what goes into the builds branch)
# Needs: Godot 4.5.1 at $GODOT, Windows export templates installed, a checkout of the builds branch at $BUILDS,
#        curl + sha256sum + unzip/zip + git, `zstd` (or python3 with the `zstandard` module) for the MSVC runtime,
#        and `gh` (logged in): every release gets a GitHub Release with the full zip + the GPL source archives.
#
# The full zip contains SiliconOverlord/{SiliconOverlord.exe, SiliconOverlord.pck, voice/}. voice/ = Piper TTS + voice
# model(s) + licence texts (docs/VOICE.md); it is NOT in the .pck, so the pck-only auto-update cannot bring it:
# version.json carries "full_required_min" + "voice_version" and core/updater.gd shows the "full download needed"
# banner to installs whose voice/manifest.json is missing or older.
#
# Download links: README.md, core/updater.gd FULL_DOWNLOAD and 0.3.0 clients all use
# raw/builds/SiliconOverlord.zip, so the builds branch ALWAYS keeps a SiliconOverlord.zip: the full zip when it is
# under ZIP_GIT_LIMIT (GitHub refuses files > 100 MB), else the same game WITHOUT voice/ (the game then shows the
# "full download needed" banner that opens version.json zip_url = the full zip on the GitHub Release).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-/home/user/tools/godot/Godot_v4.5.1-stable_linux.x86_64}"
BUILDS="${BUILDS:-/tmp/claude-0/builds}"
REPO_URL="https://github.com/inkoffTTV/silicon-overlord"
VERSION="$(grep -m1 '^config/version=' "$ROOT/client/project.godot" | cut -d'"' -f2)"
ZIP_GIT_LIMIT="${ZIP_GIT_LIMIT:-95000000}"

# ---- character voice (docs/VOICE.md). Bump VOICE_VERSION when the voice folder changes; FULL_REQUIRED_MIN is the
# oldest full-zip build that has everything the current .pck expects next to the exe (0.3.1 = first zip with voice/).
VOICE_VERSION=1
FULL_REQUIRED_MIN="${FULL_REQUIRED_MIN:-0.3.1}"
PIPER_TAG="2023.11.14-2"
PIPER_WIN_SHA="f3c58906402b24f3a96d92145f58acba6d86c9b5db896d207f78dc80811efcea"
PIPER_LIN_SHA="a50cb45f355b7af1f6d758c1b360717877ba0a398cc8cbe6d2a7a3a26e225992"
HF="https://huggingface.co/rhasspy/piper-voices/resolve/main"
# lang  path-on-huggingface  sha256(onnx)  sha256(onnx.json)
VOICES=(
  "en en/en_US/ljspeech/medium/en_US-ljspeech-medium 6f52a751e2349abe7a76735eb09dc1875298c77ea2342ffd2fef79ff81b87f22 141d612cc0a95ed7efc1ca936b845c2364967f2e9217c5dbfcf69fc4d6c65860"
)
# The only CC0-dataset Russian Piper voices (dmitri, denis) are fine-tuned from the en_US lessac checkpoint, whose
# training data (Blizzard 2013 licence) is "Research Purposes" only, no commercial use, no sub-licence. Until the
# owner decides (docs/VOICE.md "Licences"), Russian lines use the OS voice / robot. Opt-in after a legal OK:
#   SHIP_RU_VOICE=dmitri tools/release.sh
if [[ "${SHIP_RU_VOICE:-}" == dmitri ]]; then
  VOICES+=("ru ru/ru_RU/dmitri/medium/ru_RU-dmitri-medium f073356ebc4bd0f80c5af58df2953a5988bd5bdab1eb38635ce960b071fbefcb 667ef3117bc642c2892dff7690d8bdc8ca4228aeaa783b2dc1416df632855e0d")
elif [[ -n "${SHIP_RU_VOICE:-}" ]]; then
  echo "SHIP_RU_VOICE: only 'dmitri' is known" >&2; exit 1
fi
CACHE="${VOICE_CACHE:-$ROOT/build/voice_cache}"

# ---- third-party licence texts that go into voice/licenses/ (name  url  sha256), all pinned to the exact sources
# of piper 2023.11.14-2 (piper @38917ff, piper-phonemize @fccd4f3 = tag 2023.11.14-4 = its master on 2023-11-14,
# espeak-ng = the rhasspy fork @0f65aa30 = its master on 2023-11-14, onnxruntime 1.14.1, fmt 10.0.0, spdlog 1.12.0).
GH_RAW="https://raw.githubusercontent.com"
ESPEAK_FORK_COMMIT="0f65aa301e0d6bae5e172cc74197d32a6182200f"
PHONEMIZE_COMMIT="fccd4f335aa68ac0b72600822f34d84363daa2bf"
PIPER_COMMIT="38917ffd8c0e219c6581d73e07b30ef1d572fce1"
LICENSE_TEXTS=(
  "piper.LICENSE.md $GH_RAW/rhasspy/piper/$PIPER_COMMIT/LICENSE.md 4cd71dece7037f1d6d93cce7570c57ab75ea9ac566fd4990be2f3ab08d15b47f"
  "piper-phonemize.LICENSE.md $GH_RAW/rhasspy/piper-phonemize/$PHONEMIZE_COMMIT/LICENSE.md 13746d509d74e55ea2265fbef204bb7cdbf84a8315b0207e988326cb54387028"
  "espeak-ng.COPYING.GPL-3.0.txt $GH_RAW/rhasspy/espeak-ng/$ESPEAK_FORK_COMMIT/COPYING 8ceb4b9ee5adedde47b31e975c1d90c73ad27b6b165a1dcd80c7c545eb65b903"
  "espeak-ng.COPYING.APACHE $GH_RAW/rhasspy/espeak-ng/$ESPEAK_FORK_COMMIT/COPYING.APACHE cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30"
  "espeak-ng.COPYING.BSD2 $GH_RAW/rhasspy/espeak-ng/$ESPEAK_FORK_COMMIT/COPYING.BSD2 a8b0c1c7d7af6c0415c068be8cf373799d1a42b0707b79dc4ccfcaf593cd902d"
  "espeak-ng.COPYING.UCD $GH_RAW/rhasspy/espeak-ng/$ESPEAK_FORK_COMMIT/COPYING.UCD be029c50df83105a810e391778b6edcb522d6cb4b4e142332aca54437a499bf7"
  "onnxruntime.LICENSE $GH_RAW/microsoft/onnxruntime/v1.14.1/LICENSE 2f07c72751aed99790b8a4869cf2311df85a860b22ded05fa22803587a48922c"
  "onnxruntime.ThirdPartyNotices.txt $GH_RAW/microsoft/onnxruntime/v1.14.1/ThirdPartyNotices.txt cc63920441c5681cfb1663caf1de1858349b517fc1bed9ca669a85bc526cd13e"
  "fmt.LICENSE.rst $GH_RAW/fmtlib/fmt/10.0.0/LICENSE.rst 07580f2a3b35709ce703d523f447b242f6dfec7582a8c0df102c7fa2849375f8"
  "spdlog.LICENSE $GH_RAW/gabime/spdlog/v1.12.0/LICENSE a7241a379cb98d37788f82c2fc2e484c3ae85dae881fd3406f0637644850926f"
)
# GPL-3 Corresponding Source of the shipped piper build (espeak-ng is GPL-3, piper_phonemize.dll and piper.exe link it):
# name  git repo  commit. Archived with `git archive` (the commit hash pins the content) and attached to the release.
SOURCES=(
  "espeak-ng https://github.com/rhasspy/espeak-ng.git $ESPEAK_FORK_COMMIT"
  "piper-phonemize https://github.com/rhasspy/piper-phonemize.git $PHONEMIZE_COMMIT"
  "piper https://github.com/rhasspy/piper.git $PIPER_COMMIT"
)
# piper.exe / piper_phonemize.dll / onnxruntime.dll import MSVCP140, VCRUNTIME140, VCRUNTIME140_1 (Visual C++ 2015-2022
# runtime), which a fresh Windows does not have: ship them app-local next to piper.exe (conda-forge's repack of the
# official redistributable, pinned).
VCRT_URL="https://conda.anaconda.org/conda-forge/win-64/vc14_runtime-14.44.35208-h818238b_41.conda"
VCRT_SHA="ec706fe9368b837fbd05af4851f5ebef12bef8c471a273f4805f7af788407317"
VCRT_DLLS=(msvcp140.dll vcruntime140.dll vcruntime140_1.dll)

fetch() {  # url sha256 target — downloads once, always verifies
  local url="$1" sum="$2" out="$3"
  if [[ -f "$out" ]] && echo "$sum  $out" | sha256sum -c --status; then return 0; fi
  mkdir -p "$(dirname "$out")"
  curl -fsSL --retry 3 -o "$out.part" "$url"
  echo "$sum  $out.part" | sha256sum -c --status || { echo "checksum mismatch: $url" >&2; rm -f "$out.part"; exit 1; }
  mv "$out.part" "$out"
}

untar_zst() {  # file.tar.zst dest-dir member...
  local f="$1" d="$2"; shift 2
  mkdir -p "$d"
  if command -v zstd >/dev/null; then
    zstd -dcq "$f" | tar -x -C "$d" "$@"
  else
    python3 -I -c 'import sys, tarfile, zstandard
r = zstandard.ZstdDecompressor().stream_reader(open(sys.argv[1], "rb"))
want = set(sys.argv[3:])
with tarfile.open(fileobj=r, mode="r|") as t:
    for m in t:
        if m.name in want:
            t.extract(m, sys.argv[2], filter="data")' "$f" "$d" "$@" \
      || { echo "need zstd (or python3 -m pip install zstandard) to unpack $f" >&2; exit 1; }
  fi
}

add_licenses() {  # dest-dir — full licence texts (GPL-3, MIT, Apache, notices), see docs/VOICE.md
  local dest="$1"
  mkdir -p "$dest"
  for l in "${LICENSE_TEXTS[@]}"; do
    read -r name url sum <<<"$l"
    fetch "$url" "$sum" "$CACHE/licenses/$name"
    cp "$CACHE/licenses/$name" "$dest/$name"
  done
}

add_vc_runtime() {  # dest-dir (= the folder with piper.exe) — app-local MSVC runtime + its licence
  local dest="$1" tmp
  fetch "$VCRT_URL" "$VCRT_SHA" "$CACHE/vc14_runtime.conda"
  tmp="$(mktemp -d)"
  unzip -q "$CACHE/vc14_runtime.conda" 'pkg-*.tar.zst' 'info-*.tar.zst' -d "$tmp"
  untar_zst "$tmp"/pkg-*.tar.zst "$tmp/pkg" "${VCRT_DLLS[@]}"
  untar_zst "$tmp"/info-*.tar.zst "$tmp/info" info/licenses/LICENSE.TXT
  mkdir -p "$dest"
  for f in "${VCRT_DLLS[@]}"; do
    test -s "$tmp/pkg/$f" || { echo "MSVC runtime: $f missing in $VCRT_URL" >&2; exit 1; }
    cp "$tmp/pkg/$f" "$dest/"
  done
  cp "$tmp/info/info/licenses/LICENSE.TXT" "$dest/MSVC-RUNTIME-LICENSE.txt"
  rm -rf "$tmp"
}

make_sources() {  # out-dir — <name>-<commit8>-src.tar.gz for every SOURCES entry (git archive of the exact commit)
  local out="$1"
  mkdir -p "$out"
  for s in "${SOURCES[@]}"; do
    read -r name repo commit <<<"$s"
    local tgt="$out/$name-${commit:0:8}-src.tar.gz" git_dir="$CACHE/src/$name.git"
    [[ -s "$tgt" ]] && continue
    if [[ ! -d "$git_dir" ]]; then git clone -q --bare --filter=blob:none "$repo" "$git_dir"; fi
    git -C "$git_dir" cat-file -e "$commit^{commit}" 2>/dev/null || git -C "$git_dir" fetch -q origin "$commit"
    git -C "$git_dir" archive --format=tar.gz --prefix="$name-$commit/" -o "$tgt.part" "$commit"
    mv "$tgt.part" "$tgt"
  done
}

write_sources_note() {  # dest-file
  {
    echo "Source code of the GPL-3.0 parts of this voice folder (espeak-ng, linked into piper_phonemize.dll / piper.exe)."
    echo "The exact sources of the shipped piper $PIPER_TAG build are attached to the game's GitHub Release"
    echo "  $REPO_URL/releases/tag/v$VERSION"
    for s in "${SOURCES[@]}"; do
      read -r name repo commit <<<"$s"
      echo "  $name-${commit:0:8}-src.tar.gz  =  ${repo%.git} commit $commit"
    done
    echo "Also in the build (MIT; onnxruntime prebuilt, fmt/spdlog statically linked): onnxruntime 1.14.1 https://github.com/microsoft/onnxruntime/tree/v1.14.1,"
    echo "fmt 10.0.0 https://github.com/fmtlib/fmt/tree/10.0.0, spdlog 1.12.0 https://github.com/gabime/spdlog/tree/v1.12.0."
    echo "Licence texts: licenses/ (GPL-3.0 full text: licenses/espeak-ng.COPYING.GPL-3.0.txt)."
  } > "$1"
}

assemble_voice() {  # os(windows|linux) dest-dir
  local os="$1" dest="$2" exe
  rm -rf "$dest"; mkdir -p "$dest"
  if [[ "$os" == windows ]]; then
    fetch "https://github.com/rhasspy/piper/releases/download/$PIPER_TAG/piper_windows_amd64.zip" "$PIPER_WIN_SHA" "$CACHE/piper_windows_amd64.zip"
    unzip -q "$CACHE/piper_windows_amd64.zip" -d "$dest"
    exe="piper/piper.exe"
    add_vc_runtime "$dest/piper"
  else
    fetch "https://github.com/rhasspy/piper/releases/download/$PIPER_TAG/piper_linux_x86_64.tar.gz" "$PIPER_LIN_SHA" "$CACHE/piper_linux_x86_64.tar.gz"
    tar xzf "$CACHE/piper_linux_x86_64.tar.gz" -C "$dest"
    exe="piper/piper"
  fi
  # only the shipped languages are spoken: drop the other espeak dictionaries and the Arabic diacritizer (~20 MB)
  local keep=()
  for v in "${VOICES[@]}"; do keep+=(! -name "${v%% *}_dict"); done
  find "$dest/piper/espeak-ng-data" -maxdepth 1 -name '*_dict' "${keep[@]}" -delete
  rm -rf "$dest/piper/pkgconfig" "$dest/piper/libtashkeel_model.ort"
  local json_voices=""
  for v in "${VOICES[@]}"; do
    read -r lang path sum_onnx sum_json <<<"$v"
    local name; name="$(basename "$path")"
    fetch "$HF/$path.onnx" "$sum_onnx" "$CACHE/$name.onnx"
    fetch "$HF/$path.onnx.json" "$sum_json" "$CACHE/$name.onnx.json"
    cp "$CACHE/$name.onnx" "$CACHE/$name.onnx.json" "$dest/"
    curl -fsSL "$HF/$(dirname "$path")/MODEL_CARD" -o "$dest/$name.MODEL_CARD.txt" || true
    json_voices+="${json_voices:+, }\"$lang\": \"$name.onnx\""
  done
  cp "$ROOT/docs/VOICE.md" "$dest/LICENSES.md"
  add_licenses "$dest/licenses"
  write_sources_note "$dest/SOURCES.txt"
  cat > "$dest/manifest.json" <<JSON
{"version": $VOICE_VERSION, "build": "$VERSION", "piper": {"$os": "$exe"}, "voices": {$json_voices}}
JSON
}

package_zips() {  # parent-dir (holds SiliconOverlord/) — writes SiliconOverlord.zip (full) and
                  # SiliconOverlord-builds.zip (full if < ZIP_GIT_LIMIT, else without voice/); prints "full" or "lite"
  local parent="$1"
  rm -f "$parent/SiliconOverlord.zip" "$parent/SiliconOverlord-builds.zip"
  ( cd "$parent" && zip -9 -qr SiliconOverlord.zip SiliconOverlord )
  if (( $(stat -c %s "$parent/SiliconOverlord.zip") < ZIP_GIT_LIMIT )); then
    cp "$parent/SiliconOverlord.zip" "$parent/SiliconOverlord-builds.zip"
    echo full
  else
    ( cd "$parent" && zip -9 -qr SiliconOverlord-builds.zip SiliconOverlord -x 'SiliconOverlord/voice/*' )
    if (( $(stat -c %s "$parent/SiliconOverlord-builds.zip") >= ZIP_GIT_LIMIT )); then
      echo "even the zip without voice/ is over $ZIP_GIT_LIMIT bytes" >&2; exit 1
    fi
    echo lite
  fi
}

case "${1:-}" in
  --voice-only)
    assemble_voice "${2:-linux}" "${3:-$ROOT/build/voice-${2:-linux}}"
    echo "voice folder ready: ${3:-$ROOT/build/voice-${2:-linux}}"; exit 0 ;;
  --list-voices)
    for v in "${VOICES[@]}"; do read -r lang path _ <<<"$v"; echo "$lang $(basename "$path")"; done; exit 0 ;;
  --licenses-only)
    add_licenses "${2:?dir}"; write_sources_note "$2/SOURCES.txt"; exit 0 ;;
  --vcrt-only)
    add_vc_runtime "${2:?dir}"; exit 0 ;;
  --sources-only)
    make_sources "${2:?dir}"; exit 0 ;;
  --package-only)
    package_zips "${2:?parent dir}"; exit 0 ;;
  "") ;;
  *) echo "unknown option $1" >&2; exit 1 ;;
esac

if [[ "$(printf '%s\n%s\n' "$FULL_REQUIRED_MIN" "$VERSION" | sort -V | head -1)" != "$FULL_REQUIRED_MIN" ]]; then
  echo "version $VERSION is below FULL_REQUIRED_MIN $FULL_REQUIRED_MIN: bump config/version first" >&2; exit 1
fi
ENGINE="$("$GODOT" --version | grep -oE '^[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)"
[[ "$ENGINE" =~ ^[0-9]+\.[0-9]+$ ]] && ENGINE="$ENGINE.0"
OUT="$ROOT/build/SiliconOverlord"
mkdir -p "$OUT"
rm -f "$OUT/SiliconOverlord.exe" "$OUT/SiliconOverlord.pck" "$ROOT/build/SiliconOverlord.zip"
( cd "$ROOT/client" && "$GODOT" --headless --path . --export-release "Windows" "$OUT/SiliconOverlord.exe" >/dev/null 2>&1 )
test -s "$OUT/SiliconOverlord.pck"
assemble_voice windows "$OUT/voice"
test -s "$OUT/voice/piper/piper.exe" && test -s "$OUT/voice/manifest.json" && test -s "$OUT/voice/piper/vcruntime140.dll"
test -s "$OUT/voice/licenses/espeak-ng.COPYING.GPL-3.0.txt"
make_sources "$ROOT/build/sources"
IN_GIT="$(package_zips "$ROOT/build")"
ZIP_SIZE="$(stat -c %s "$ROOT/build/SiliconOverlord.zip")"
cp "$OUT/SiliconOverlord.pck" "$BUILDS/"
# raw/builds/SiliconOverlord.zip is the README / FULL_DOWNLOAD / 0.3.0 link: it must never disappear (see the top).
cp "$ROOT/build/SiliconOverlord-builds.zip" "$BUILDS/SiliconOverlord.zip"
cd "$BUILDS"
git add SiliconOverlord.zip SiliconOverlord.pck
git commit -qm "Windows build $VERSION

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01GrSxc2FrBZgYuz6Arnf6Xs"
SHA="$(git rev-parse HEAD)"
git push -q origin builds
# The full zip (with voice/, ~170 MB) and the GPL-3 Corresponding Source archives are attached to the GitHub
# Release by the `builds` branch workflow (.github/workflows/release.yml there): this session cannot create
# releases, and the full zip is too big for git. The workflow rebuilds voice/ with `tools/release.sh --voice-only`
# from the same pinned sources, so its zip is identical in content to the local one.
ZIP_URL="$REPO_URL/releases/download/v$VERSION/SiliconOverlord.zip"
SUM="$(sha256sum SiliconOverlord.pck | cut -d' ' -f1)"
SIZE="$(stat -c %s SiliconOverlord.pck)"
cat > version.json <<JSON
{
  "version": "$VERSION",
  "engine": "$ENGINE",
  "pck_url": "$REPO_URL/raw/$SHA/SiliconOverlord.pck",
  "pck_sha256": "$SUM",
  "pck_size": $SIZE,
  "zip_url": "$ZIP_URL",
  "zip_size": $ZIP_SIZE,
  "full_required_min": "$FULL_REQUIRED_MIN",
  "voice_version": $VOICE_VERSION,
  "date": "$(date -u +%Y-%m-%d)"
}
JSON
git add version.json
git commit -qm "Update manifest $VERSION

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01GrSxc2FrBZgYuz6Arnf6Xs"
git push -q origin builds
echo "released $VERSION (engine $ENGINE) pack $SUM, zip $((ZIP_SIZE / 1000000)) MB -> $ZIP_URL"
echo "GitHub Actions on the builds branch now creates the release v$VERSION (notes: docs/releases/v$VERSION.md) if missing"
