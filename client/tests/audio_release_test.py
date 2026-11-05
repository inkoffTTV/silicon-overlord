#!/usr/bin/env python3
"""Release-packaging regressions for the character voice (docs/VOICE.md). Run: python3 client/tests/audio_release_test.py

1. download link: raw/builds/SiliconOverlord.zip (README, core/updater.gd FULL_DOWNLOAD, 0.3.0 clients) must always
   exist: release.sh never removes it from the builds branch; a zip too big for git is replaced there by the same game
   without voice/ (checked by running `release.sh --package-only` on a fake build).
2. licences: the voice folder carries the full GPL-3.0 / MIT / Apache texts and the onnxruntime notices, and the
   espeak-ng source points at the rhasspy fork commit piper was built from (needs network; skipped offline).
3. the Russian model fine-tuned from lessac (research-only data) is not shipped unless the owner opts in.
4. the Visual C++ runtime DLLs piper.exe imports are extracted (needs network + zstd/zstandard; skipped otherwise).
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
RELEASE = os.path.join(ROOT, "tools", "release.sh")
checks = 0
failures = []


def check(ok, what):
    global checks
    checks += 1
    print(("  ok   " if ok else "  FAIL ") + what)
    if not ok:
        failures.append(what)


def run(*args, env=None):
    e = dict(os.environ)
    e.update(env or {})
    return subprocess.run(["bash", RELEASE, *args], capture_output=True, text=True, env=e, timeout=600)


def read(path):
    with open(os.path.join(ROOT, path), encoding="utf-8") as f:
        return f.read()


def online():
    try:
        r = subprocess.run(["curl", "-fsS", "-o", "/dev/null", "--max-time", "10",
                            "https://raw.githubusercontent.com/rhasspy/piper/master/LICENSE.md"], capture_output=True)
        return r.returncode == 0
    except OSError:
        return False


def main():
    script = read("tools/release.sh")
    updater = read("client/core/updater.gd")
    voice_md = read("docs/VOICE.md")

    print("audio_release_test: download link")
    full = re.search(r'const FULL_DOWNLOAD := "([^"]+)"', updater)
    check(full is not None and full.group(1).endswith("/raw/builds/SiliconOverlord.zip"),
          "updater FULL_DOWNLOAD = raw/builds/SiliconOverlord.zip (the link 0.3.0 clients and README use)")
    check("git rm" not in script, "release.sh never removes SiliconOverlord.zip from the builds branch")
    check(re.search(r'cp "\$ROOT/build/SiliconOverlord-builds.zip" "\$BUILDS/SiliconOverlord.zip"', script) is not None
          and re.search(r'^git add SiliconOverlord.zip SiliconOverlord.pck$', script, re.M) is not None,
          "release.sh always commits a SiliconOverlord.zip to the builds branch")
    tmp = tempfile.mkdtemp(prefix="so_release_test_")
    try:
        game = os.path.join(tmp, "SiliconOverlord")
        os.makedirs(os.path.join(game, "voice", "piper"))
        with open(os.path.join(game, "SiliconOverlord.exe"), "wb") as f:
            f.write(b"MZ" + b"\0" * 1000)
        with open(os.path.join(game, "SiliconOverlord.pck"), "wb") as f:
            f.write(b"GDPC" + b"\1" * 1000)
        with open(os.path.join(game, "voice", "model.onnx"), "wb") as f:
            f.write(os.urandom(400000))   # incompressible "voice model"
        with open(os.path.join(game, "voice", "manifest.json"), "w") as f:
            f.write('{"version": 1}')
        r = run("--package-only", tmp, env={"ZIP_GIT_LIMIT": "200000"})
        names_full = zipfile.ZipFile(os.path.join(tmp, "SiliconOverlord.zip")).namelist() if r.returncode == 0 else []
        names_git = zipfile.ZipFile(os.path.join(tmp, "SiliconOverlord-builds.zip")).namelist() if r.returncode == 0 else []
        check(r.returncode == 0 and r.stdout.strip() == "lite", "zip over the git limit -> builds branch gets the game without voice/ (%s)" % r.stdout.strip())
        check("SiliconOverlord/voice/model.onnx" in names_full and "SiliconOverlord/SiliconOverlord.pck" in names_git
              and "SiliconOverlord/SiliconOverlord.exe" in names_git and not any("/voice/" in n for n in names_git),
              "full zip has voice/, the builds-branch zip has exe + pck and no voice/")
        r = run("--package-only", tmp, env={"ZIP_GIT_LIMIT": "95000000"})
        same = r.returncode == 0 and open(os.path.join(tmp, "SiliconOverlord.zip"), "rb").read() == \
            open(os.path.join(tmp, "SiliconOverlord-builds.zip"), "rb").read()
        check(r.stdout.strip() == "full" and same, "small zip -> the full zip itself goes into the builds branch")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    print("audio_release_test: Russian voice licence")
    r = run("--list-voices")
    langs = [l.split()[0] for l in r.stdout.splitlines() if l.strip()]
    check(r.returncode == 0 and langs == ["en"] and "dmitri" not in r.stdout,
          "default release ships no lessac-derived Russian model (%s)" % r.stdout.strip().replace("\n", ", "))
    r = run("--list-voices", env={"SHIP_RU_VOICE": "dmitri"})
    check(r.returncode == 0 and "ru ru_RU-dmitri-medium" in r.stdout, "owner opt-in SHIP_RU_VOICE=dmitri adds it")
    check(run("--list-voices", env={"SHIP_RU_VOICE": "ruslan"}).returncode != 0, "unknown SHIP_RU_VOICE is refused")

    print("audio_release_test: licence texts")
    check("github.com/espeak-ng/espeak-ng " not in voice_md and "rhasspy/espeak-ng" in voice_md
          and "0f65aa301e0d6bae5e172cc74197d32a6182200f" in voice_md, "docs/VOICE.md names the rhasspy espeak-ng fork commit")
    if online():
        lic = tempfile.mkdtemp(prefix="so_release_lic_")
        try:
            r = run("--licenses-only", lic)
            check(r.returncode == 0, "licence texts fetched (sha256 pinned) " + r.stderr.strip()[-200:])

            def txt(n):
                p = os.path.join(lic, n)
                return open(p, encoding="utf-8", errors="replace").read() if os.path.exists(p) else ""
            gpl = txt("espeak-ng.COPYING.GPL-3.0.txt")
            check("GNU GENERAL PUBLIC LICENSE" in gpl and "Version 3, 29 June 2007" in gpl, "full GPL-3.0 text")
            for n in ["piper.LICENSE.md", "piper-phonemize.LICENSE.md", "onnxruntime.LICENSE"]:
                check("MIT License" in txt(n) and "Permission is hereby granted" in txt(n), "MIT text: " + n)
            check("Permission is hereby granted" in txt("fmt.LICENSE.rst") and "Permission is hereby granted" in txt("spdlog.LICENSE"),
                  "fmt + spdlog licences (statically linked into piper)")
            check(len(txt("onnxruntime.ThirdPartyNotices.txt")) > 100000, "onnxruntime ThirdPartyNotices")
            check("Apache License" in txt("espeak-ng.COPYING.APACHE") and txt("espeak-ng.COPYING.BSD2") != "" and txt("espeak-ng.COPYING.UCD") != "",
                  "espeak-ng's other licence files")
            src = txt("SOURCES.txt")
            check("rhasspy/espeak-ng commit 0f65aa301e0d6bae5e172cc74197d32a6182200f" in src
                  and "rhasspy/piper-phonemize commit fccd4f335aa68ac0b72600822f34d84363daa2bf" in src
                  and "github.com/espeak-ng/espeak-ng" not in src, "SOURCES.txt: exact fork commits, not upstream espeak-ng")
        finally:
            shutil.rmtree(lic, ignore_errors=True)
        have_zstd = shutil.which("zstd") is not None or subprocess.run(
            [sys.executable, "-c", "import zstandard"], capture_output=True).returncode == 0
        if have_zstd:
            vc = tempfile.mkdtemp(prefix="so_release_vc_")
            try:
                r = run("--vcrt-only", vc, env={"PATH": os.path.dirname(sys.executable) + os.pathsep + os.environ.get("PATH", "")})
                ok = r.returncode == 0
                for dll in ["msvcp140.dll", "vcruntime140.dll", "vcruntime140_1.dll"]:
                    p = os.path.join(vc, dll)
                    ok = ok and os.path.exists(p) and open(p, "rb").read(2) == b"MZ"
                check(ok and os.path.exists(os.path.join(vc, "MSVC-RUNTIME-LICENSE.txt")),
                      "MSVC runtime DLLs piper.exe imports are extracted next to it " + r.stderr.strip()[-200:])
            finally:
                shutil.rmtree(vc, ignore_errors=True)
        else:
            print("  skip  MSVC runtime: no zstd / zstandard")
    else:
        print("  skip  licence texts / MSVC runtime: offline")
    check(re.search(r'add_vc_runtime "\$dest/piper"', script) is not None, "Windows voice folder always gets the MSVC runtime")
    check(re.search(r'add_licenses "\$dest/licenses"', script) is not None, "voice folder always gets the licence texts")

    print("audio_release_test: %d checks, %d failures" % (checks, len(failures)))
    for f in failures:
        print("  FAILED: " + f)
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
