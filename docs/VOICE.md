# Character voice (owner: AUDIO agent — client/audio/**, docs/VOICE.md)

Chat lines are spoken by the writer's character: synthesized speech that sounds like a little robot talking over a
walkie-talkie — per-player pitch (squeaky … deep), metallic ring, radio band-pass, a short squelch and crackle at the
start/end, played in 3D on the speaker's avatar. **No R.E.P.O assets are used** — it only aims at the same feel,
built from an open TTS engine and our own effect chain.

## How it works
```
chat line ─► voice.gd speak()  ──► queue per speaker (max 4 waiting, 200 chars per line)
                 │ at once: char_tts.gd request(text, ru|en, fx)  ── worker thread ──►  cache user://tts/<md5>.wav ?
                 │                                                                      └─ piper process (one per language,
                 │                                                                         model stays loaded, stdin JSON
                 │                                                                         line → WAV path on stdout)
                 │                                                 ring-mod + squelch/crackle baked into the samples
                 ▼                                                 → AudioStreamWAV
     speaker's turn + stream ready ─► AudioStreamPlayer3D on the avatar (same loudness curve as the robot / OS voice:
                                       full within 4 m, quadratic fade to silence at 30 m; 2D for your own lines /
                                       menus) ─► bus VoiceFx<n> ─► Voice ─► Master
```
- Effect bus per speaker (`VoiceFx0..7`, reused least-recently-used): **PitchShift** (the speaker's pitch) → **Chorus**
  (2 voices, 1.6–7 ms: comb-filter "tin can" ring) → **Distortion** (overdrive 0.22) → **HighPass 330 Hz** →
  **LowPass 3.6 kHz** → **EQ6** (mids up, lows/highs down = radio honk) → **HardLimiter** −1 dB.
  In the samples: ring modulator 32–90 Hz (per player, 28 % mix), 70 ms squelch before, 90 ms crackle after.
  Higher voices also play ~18 % of their pitch change faster (`pitch_scale`) — playful.
- **Pitch**: yours = settings slider "Voice pitch" (`[audio] voice_pitch`, 0.5–2.0). Others: `voicePitch` from the
  server's peers list if a server ever sends it (not yet — see Known issues), else a stable hash of the userId
  (0.62 … 1.6).
- **Language**: Cyrillic (ru, uk) → Russian voice (only if the zip has one — see Licences; else OS voice / robot);
  English → English voice; other Latin-script languages → the OS voice for that language if there is one, else the
  English voice; Chinese/Japanese/Korean and other scripts (Greek, Arabic, Hebrew, Thai, Armenian, Georgian,
  Devanagari… → `el`, `ar`, `he`, `th`…) → OS voice, else robot — never piper (its espeak data has only en/ru).
- **3D loudness**: the 3D player uses `ATTENUATION_DISABLED` + `max_distance` 30 m (Godot then multiplies by
  1 − d/30) and `volume_db = voice.char_volume_db(d)` (updated every frame), so the result equals `distance_volume()`
  of the robot and OS voices at every distance.
- **Fallback chain** (mode "Character"): Piper → OS text-to-speech (`DisplayServer.tts_*`) → robot blips.
  Piper is skipped when the voice folder is missing, a line is not ready after 3.5 s, or a language failed 3 times.
  A piper process that hangs for 8 s is killed by a watchdog and restarted on the next line.
- **Non-blocking**: synthesis starts when the line is queued (not when it is its turn), on one worker thread.
  Identical lines come from the cache (memory: 48 lines, disk: up to 400 WAVs and 64 MB in `user://tts/`, pruned
  oldest-first at start and after every 16 new WAVs; env `SO_TTS_CACHE` moves the folder — tests use their own).
- Avatars' mouths (`world.avatar_talk`) get the real line length; music ducks while anyone talks (as before).
- API additions on `Sfx`: `test_voice(text, lang)` (your voice, your pitch), `voice_status() -> {character, dir, error}`.

### Latency (client/tests/audio_voice_test.gd prints these)
| path | measured here |
|---|---|
| fake in-process synthesizer (150 ms per line) | ~180–200 ms from chat to sound |
| same text again (cache) | ~15 ms |
| piper protocol through a fake process (`audio_fake_piper.py`, 40 ms per line) | ~60–80 ms |
| real piper, medium model | **not measured** — running the downloaded piper binary was not allowed on the build machine. Typical for medium Piper voices on a desktop CPU: ~0.1–0.4 s per short line + ~0.5–1 s model load once per language; the models are loaded when you join a company (`voice.prewarm()`). Expected < 1 s, unverified. |

## Settings (`user://settings.cfg` `[audio]`, Sound tab)
| key | values | |
|---|---|---|
| voice_mode | `character` (default) / `tts` (system voices) / `robot` / `off` | 0.3.0 wrote `tts` as default: migrated once to `character` (`voice_rev = 2`) |
| voice_pitch | 0.5 … 2.0 (default 1.0) | your voice; slider + "Test voice" button (also plays when you release the slider) |
| voice | 0 … 1 | volume of all voices (Voice bus) — unchanged |

## Files in the build (NOT in the .pck)
```
SiliconOverlord/
  SiliconOverlord.exe, SiliconOverlord.pck
  voice/manifest.json            {"version":1,"build":"<game version>","piper":{"windows":"piper/piper.exe"},
                                   "voices":{"en":"en_US-ljspeech-medium.onnx"}}   (+ "ru" only with SHIP_RU_VOICE)
  voice/piper/                   piper.exe, piper_phonemize.dll, espeak-ng.dll, onnxruntime*.dll,
                                 msvcp140.dll, vcruntime140.dll, vcruntime140_1.dll + MSVC-RUNTIME-LICENSE.txt,
                                 espeak-ng-data/ (only the dictionaries of the shipped languages)
  voice/licenses/                full texts: espeak-ng.COPYING.GPL-3.0.txt (+ APACHE, BSD2, UCD), piper / piper-phonemize /
                                 onnxruntime MIT, onnxruntime ThirdPartyNotices.txt, fmt, spdlog (all sha256-pinned)
  voice/SOURCES.txt              where the GPL Corresponding Source is (exact commits, release assets)
  voice/*.onnx + .onnx.json, *.MODEL_CARD.txt, LICENSES.md (= this file)
```
The game looks for the folder in: env `SO_VOICE_DIR`, `<exe dir>/voice`, `<repo>/build/SiliconOverlord/voice` (dev).
`tools/release.sh` downloads everything (pinned sha256), prunes it, writes the manifest and zips it with the game.
**Visual C++ runtime**: piper.exe, piper_phonemize.dll and onnxruntime.dll import MSVCP140 / VCRUNTIME140 /
VCRUNTIME140_1 (checked with `objdump -p`; everything else they import is Windows 10's own UCRT/kernel). A fresh
Windows without the VC++ 2015-2022 Redistributable does not have them and would show a "DLL not found" dialog, so
release.sh puts them app-local next to piper.exe (extracted from conda-forge `vc14_runtime 14.44.35208`, sha256
pinned; needs `zstd` or python `zstandard`). The game additionally checks for them (`char_tts.missing_vc_runtime`,
next to piper.exe or in System32) and does not start piper without them (→ OS voice / robot, no dialog).
`tools/release.sh --voice-only linux DIR` assembles the same folder with the **Linux** piper (for tests:
`SO_VOICE_DIR=DIR <godot> --headless --path client -s tests/audio_voice_test.gd` then also measures real latency).

| part | size on disk |
|---|---|
| piper (Windows) after pruning + MSVC runtime + licences | ~11 MB |
| en_US-ljspeech-medium.onnx | 63.5 MB |
| ru_RU-dmitri-medium.onnx (only with `SHIP_RU_VOICE=dmitri`) | 63.2 MB |
| voice/ total | ~74 MB (~137 MB with the Russian model) |

### Download links
README.md, `core/updater.gd` `FULL_DOWNLOAD` and 0.3.0 clients (their only full-download URL, used when the engine
changes) all point at `raw/builds/SiliconOverlord.zip`, so **the builds branch always keeps a SiliconOverlord.zip**:
- full zip < 95 MB (`ZIP_GIT_LIMIT`) → the full zip itself (as before);
- bigger (the voice makes it ~100–170 MB) → the same game **without** `voice/` (~44 MB). It works (OS voices / robot)
  and its updater sees no `voice/manifest.json` → the "full download needed" banner → `version.json` `zip_url`.
Every release also creates/updates the GitHub Release `v<version>` (needs `gh`) with the full zip and the GPL source
archives; `zip_url` = that release asset when the full zip is not in git. `tools/release.sh --package-only PARENT`
does just the zipping (used by `client/tests/audio_release_test.py`). README could point straight at
`releases/latest/download/SiliconOverlord.zip` to give new players the voice at once (README is not AUDIO's).

### Updates
The auto-updater only swaps the .pck. `version.json` now also has `"full_required_min"` (oldest full zip that has
everything the pack expects next to the exe; 0.3.1 = first zip with voice/ — release.sh refuses to release a lower
version) and `"voice_version"`. `core/updater.gd` reads `voice/manifest.json` next to the exe (missing = "0.0.0" / 0);
if older it still installs the pack but shows the existing "full download needed" banner (opens `zip_url`).
Old 0.3.0 clients ignore the new keys and update the pack as before; the new pack then shows that banner.
Without the voice folder the game keeps working: OS voices or the robot.

## Licences (checked 2026-11-05)
| component | licence | source |
|---|---|---|
| Piper TTS 2023.11.14-2 (piper.exe) | MIT | https://github.com/rhasspy/piper commit `38917ffd8c0e219c6581d73e07b30ef1d572fce1` (tag `2023.11.14-2`): `piper_windows_amd64.zip` sha256 `f3c58906402b24f3a96d92145f58acba6d86c9b5db896d207f78dc80811efcea`, `piper_linux_x86_64.tar.gz` sha256 `a50cb45f355b7af1f6d758c1b360717877ba0a398cc8cbe6d2a7a3a26e225992`. Statically links fmt 10.0.0 (MIT) and spdlog 1.12.0 (MIT). |
| piper-phonemize (piper_phonemize.dll) | MIT | https://github.com/rhasspy/piper-phonemize commit `fccd4f335aa68ac0b72600822f34d84363daa2bf` (tag `2023.11.14-4`; piper's CMake fetched its `master`, which was this commit on 2023-11-14) |
| espeak-ng (espeak-ng.dll + espeak-ng-data; linked into piper_phonemize.dll / piper.exe) | **GPL-3.0-or-later** (+ Apache-2.0 / BSD-2 / Unicode parts) | **the rhasspy fork**, not upstream: https://github.com/rhasspy/espeak-ng commit `0f65aa301e0d6bae5e172cc74197d32a6182200f` (piper-phonemize's CMake fetched the fork's `master`, which was this commit on 2023-11-14). Shipped as built by the piper project. |
| ONNX Runtime 1.14.1 (onnxruntime.dll) | MIT (+ ThirdPartyNotices) | https://github.com/microsoft/onnxruntime/tree/v1.14.1 |
| MSVC runtime 14.44.35208 (msvcp140, vcruntime140, vcruntime140_1) | Microsoft Visual C++ 2015-2022 Runtime licence | conda-forge `vc14_runtime-14.44.35208-h818238b_41.conda` sha256 `ec706fe9368b837fbd05af4851f5ebef12bef8c471a273f4805f7af788407317`; these DLLs are on Microsoft's redistributable ("Distributable Code") list for app-local deployment |
| voice **en_US-ljspeech-medium** | piper-voices repo: MIT; dataset: **public domain** (LJ Speech) | https://huggingface.co/rhasspy/piper-voices/tree/main/en/en_US/ljspeech/medium — MODEL_CARD: "Dataset URL: https://keithito.com/LJ-Speech-Dataset/, License: public domain. Trained from scratch for 1000 epochs." onnx sha256 `6f52a751e2349abe7a76735eb09dc1875298c77ea2342ffd2fef79ff81b87f22` |
| voice ru_RU-dmitri-medium — **NOT shipped by default** | repo MIT, dataset CC0, **but fine-tuned from en_US lessac** | MODEL_CARD: "Finetuned from U.S. English lessac voice (medium quality)". lessac's data is under the Blizzard 2013 licence: "Research Purposes" only, no commercial use incl. "development, marketing, commercialisation … of voice synthesis … products", no sub-licence. onnx sha256 `f073356ebc4bd0f80c5af58df2953a5988bd5bdab1eb38635ce960b071fbefcb` |

**What goes with the zip** (GPL-3 §4/§6, MIT notice conditions): `voice/licenses/` holds the full licence texts
(GPL-3.0, espeak-ng's Apache/BSD2/UCD files, the MIT texts of piper, piper-phonemize, onnxruntime, fmt, spdlog and
onnxruntime's ThirdPartyNotices), `voice/piper/MSVC-RUNTIME-LICENSE.txt`, `voice/SOURCES.txt`. The Corresponding
Source of the piper build (`git archive` of the three exact commits above: espeak-ng fork ~16 MB, piper-phonemize
~10 MB, piper ~25 MB) is attached to every GitHub Release next to the zip (`release.sh --sources-only DIR`).

**Owner decision needed — Russian voice.** Every Russian Piper voice with a clean dataset (dmitri, denis) is
fine-tuned from the lessac checkpoint (research-only, non-commercial data); ruslan is CC BY-NC-SA, irina's dataset
licence is "Unknown". So by default **no Russian model is shipped**: Russian/Ukrainian chat uses the OS voice, else
the robot. Options: (a) keep it so until a Russian voice trained from scratch on CC0/public-domain data exists
(swap it in: one line in `tools/release.sh` VOICES + bump VOICE_VERSION); (b) after your own legal OK ship dmitri
anyway: `SHIP_RU_VOICE=dmitri tools/release.sh` (then bump VOICE_VERSION so existing installs fetch it).

Rejected: ru_RU-ruslan (CC BY-NC-SA, non-commercial), ru_RU-irina (dataset licence "Unknown"), ru_RU-dmitri/denis
(lessac fine-tunes, see above), en_US-ryan (CC BY-NC-SA), en_US-lessac (Blizzard 2013 licence), amy/danny/alan
(Mycroft, "See URL").

## Tests
- `client/tests/audio_voice_test.gd` (headless, ~12 s, 64 checks): JSON/WAV helpers, language mapping, pitch range;
  fake synthesizer: queue per speaker, own effect bus (7 effects, speaker's pitch), 3D player at the avatar with 30 m
  range, avatar_talk length, cache (memory + disk), latency < 1 s; fallbacks (no piper → robot, too slow → robot,
  off); the real pipe protocol through `client/tests/audio_fake_piper.py` (persistent process, temp files moved,
  processes killed on shutdown); voice-folder discovery; real piper when `SO_VOICE_DIR` is set (skipped otherwise);
  settings migration; regressions: other scripts (Greek/Arabic/Hebrew/Thai) never reach piper, 3D loudness =
  `distance_volume()` and smooth to 0 at 30 m, disk cache pruned during a session (files + bytes), missing MSVC
  runtime detected. It runs on its own cache folder (`SO_TTS_CACHE`) and settings file (`Sfx.settings_path`), so
  the game or parallel tests cannot disturb it, and prints the names of failed checks at the end.
- `client/tests/audio_release_test.py` (python3, ~1 min online): `release.sh --package-only` on a fake build (the
  builds branch always gets a SiliconOverlord.zip, without voice/ when too big), no `git rm`, `FULL_DOWNLOAD` link,
  default voices without the lessac-derived Russian model, licence texts + SOURCES.txt (exact fork commits), MSVC
  runtime DLLs extracted. The network parts are skipped offline.
- `client/tests/audio_smoke.gd` unchanged and green; `client/tests/updater_test.gd` + 7 full-download checks.
- `SO_TTS_FAKE=1` makes the running game use the fake synthesizer (no voice folder needed).

## Known issues
- Real piper was **not run** on the build machine (executing the downloaded binary was not permitted), so the real
  voice with our effect chain and its real latency were neither heard nor measured. The pipe protocol is piper's
  documented one (`--json-input --output_dir`, output path printed per line) and is exercised with a fake process.
- Windows: a non-ASCII profile path (e.g. Cyrillic user name → user://) or game folder may make piper fail to open
  paths → fallback to OS voices/robot. Untested.
- Other players hear **your** chosen pitch only if the server relays it (`voicePitch` in peers — not implemented,
  server is not AUDIO's). Until then others hear you with the pitch from your userId; the slider changes how *you*
  hear yourself (and the test button).
- OS TTS lines (fallback / other languages) bypass Godot buses: no radio effect, no 3D.
- The full zip grows from ~44 MB to ~115 MB (~170 MB with the Russian model): too big for git, so the builds branch
  gets the game without voice/; players who download from the README link get the voice only after the in-game
  "full download needed" banner (README is not AUDIO's — pointing it at `releases/latest/download/...` would fix it).
- Russian chat has no character voice until the owner decides (Licences). OS voices for Russian exist on most
  Windows installs (SAPI "Irina"/"Pavel" only with the Russian language pack); otherwise the robot.
- The MSVC runtime from conda-forge is the official redistributable repackaged; whether app-local copies are fine for
  this project under Microsoft's terms is for the owner to confirm. Not tested on a real Windows.
- onnxruntime / fmt / spdlog sources are linked (tags), not attached; they are MIT, not GPL.
