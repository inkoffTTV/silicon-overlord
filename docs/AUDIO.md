# Audio (owner: AUDIO agent — client/audio/**, client/tests/audio_*, this file)

Everything goes through the autoload **`Sfx`** (`res://audio/sfx.gd`). All calls are safe at any time
(headless, no audio device, before a level exists). Unknown names never error: they print one debug line
(`[Sfx] unknown sound 'x'`) the first time and are ignored afterwards.

## API
```gdscript
Sfx.play(name: String, at: Variant = null, volume_db := 0.0)   # at = Vector3 → 3D at that point; Node3D → 3D following it; null → 2D
Sfx.ui(name: String)                                            # UI sounds (UI bus). Same as play() with a UI name
Sfx.music(name: String)                                         # "menu" | "game" | "launch" | "" (stop). 2 s crossfade
Sfx.ambient(name: String)                                       # "garage" | "loft" | "stage" | "outdoor" | "" (stop). crossfade
Sfx.speak(user_id: int, display_name: String, text: String, at: Variant = null, lang := "")   # chat line → character voice (lang optional: force a language)
# extras (added in iteration 2, all optional)
Sfx.loop(name: String, parent: Node3D, volume_db := 0.0) -> Node   # looping 3D emitter attached to parent (machine hum, conveyor…)
Sfx.stop_loop(player: Node)                                       # stops/frees what loop() returned (freeing the parent works too)
Sfx.apply_settings()                                              # re-read user://settings.cfg [audio] now (otherwise picked up within 1 s)
Sfx.has_sound(name) -> bool
Sfx.stop_all()                                                    # silence everything (one-shots, music, ambience, voices)
```
`play()` picks a random variant and a small random pitch (±4%) for one-shots so repeated steps/impacts never sound identical.
Players are pooled (12 2D + 24 3D); max 4 copies of one sound at once; the same sound within 35 ms is skipped.
Passing a loop name to `play()` with a Node3D starts `loop()`; music/ambient names given to `play()` are forwarded.

## What Sfx does by itself (do NOT also do it in UI/world code)
- **Chat voices**: Sfx listens to `Net.chat_received` and speaks every line (yours too — the server echoes it).
  The UI must not call `Sfx.speak` for chat. Speaker position: `world.avatar_position(user_id) -> Vector3` if the world
  has it, else the latest `Bus.peers_changed` position of that user (+1.6 m head height), your own lines come from the
  camera. Sfx calls `world.avatar_talk(user_id, seconds, text)` (if the world has it) when a line starts — also when
  voices are muted, so bubbles/mouths still work.
- **Button sounds**: every `BaseButton` added to the tree clicks on press and plays a quiet `hover` on mouse-over;
  CheckBox/CheckButton → `toggle`, OptionButton/TabBar → `tab`, LineEdit typing → `type`.
  Per control: `button.set_meta("sfx", "confirm")` changes the sound, `set_meta("sfx", "")` silences it,
  `set_meta("sfx_hover", false)` disables hover. If the button's handler plays its own `Sfx.ui(...)` in the same
  frame, the default click is skipped automatically (no double sounds).
- **Notifications**: `Bus.notify(kind, title, …)` → `notify` / `success` / `warning` / `error`
  (titles with research/исследован → `research_done`, sale/sold/revenue/продаж/выручк → `cash_register`). Max one per 0.25 s.
- **Music**: `menu` at start; `Net.joined_company` → `game` (+ ambient `garage` if no ambience is set);
  `Net.left_company` → `menu`, ambience off. `Bus.launch_show` → `launch`; `Bus.launch_finished` → back to `game`
  (safety fallback after 45 s). The world may switch ambience itself (`Sfx.ambient("outdoor")` when the player goes outside).
- **Ducking**: while anyone speaks, Music ducks by 8 dB and Ambient by ~3 dB (smooth).

## Spoken chat details (client/audio/voice.gd)
- Engine: `voice_mode = "tts"` → OS text-to-speech (`DisplayServer.tts_*`, Windows SAPI / macOS / speech-dispatcher)
  when available and a voice exists for the line's language; otherwise the **robot voice** (pitched syllable blips,
  Animal-Crossing style, `voice_blip_*` files). `"robot"` forces it, `"off"` mutes voices.
  OS TTS needs `audio/general/text_to_speech=true` in project.godot (requested from the lead in docs/REQUESTS.md);
  without it the robot voice is used.
- Language: Cyrillic → `ru` (`uk` if it has і ї є ґ), kana → `ja`, Han → `zh`, Hangul → `ko`; Latin text → guessed
  from special letters (ş/ğ/ı → tr, ł/ś/ż → pl, ã/õ → pt, ñ/¿/¡ → es, ä/ö/ü/ß → de, è/ê/ç → fr), else the game
  language if it is a Latin-script one, else `en`; no letters → game language. `Sfx.speak(..., lang)` forces a code.
- OS voice: `[audio] voice_<lang>` (chosen in the settings panel) if set, else one picked per user among that
  language's voices; `uk` falls back to Russian voices and Latin-script languages to English ones; none → robot.
- Per user (hash of userId, stable): TTS pitch 0.7–1.45, rate 0.9–1.3, which OS voice of the language, robot pitch.
- Volume: full within 4 m of the camera, quadratic fade to silent at 30 m (computed when the line starts).
  OS TTS gets volume × voice × master (it bypasses Godot buses); the robot voice plays on the Voice bus.
- Each speaker has a queue (max 4 waiting lines, 200 chars per line). Robot voices of different players can overlap;
  OS TTS says one line at a time, so TTS lines of different speakers wait for each other.

## Buses (created in code at startup)
`Master` → `Music`, `SFX`, `UI`, `Voice`, `Ambient` (Ambient is a child of SFX so the SFX slider controls it too).

## Settings — `user://settings.cfg` section `[audio]` (defaults are written on first start)
| key | type | default | meaning |
|---|---|---|---|
| master | float 0..1 | 0.8 | Master volume |
| music | float 0..1 | 0.5 | Music |
| sfx | float 0..1 | 0.8 | World sounds + ambience |
| ui | float 0..1 | 0.7 | UI clicks |
| voice | float 0..1 | 0.9 | Spoken chat |
| voice_mode | String | "tts" | "tts" (OS text-to-speech, falls back to robot when unavailable) / "robot" (blah-blah voice) / "off" |
| voice_<lang> | String | (none) | OS voice id for that language (`voice_ru`, `voice_en`…), "" = automatic per user |

The UI settings panel writes these keys (e.g. with `Prefs.set_setting("audio", "music", 0.4)`); Sfx notices the file change
within a second, or immediately on `Bus.settings_changed` / `Sfx.apply_settings()`. Suggested UI: 4 sliders
(Master, Music, Sounds = sfx, Voices = voice) + a 3-way "Voice chat": Text-to-speech / Robot voice / Off (`voice_mode`).

## Sound names
### UI — `Sfx.ui(name)` (2D, UI bus)
| name | when |
|---|---|
| `click` | button press |
| `hover` | mouse over a button (quiet) |
| `confirm` | positive confirm (buy, start, save) |
| `back` | close / cancel / back |
| `open` | open a screen / panel |
| `close` | close a screen / panel |
| `tab` | switch tab / segmented control |
| `toggle` | checkbox / switch |
| `type` | keystroke in a text field (very short tick) |
| `error` | invalid action / server error |
| `notify` | neutral toast ping |
| `success` | success toast |
| `warning` | warning toast |
| `coin` | money gained (small) |
| `cash_register` | a sale / big money event |
| `research_done` | research complete chime |
| `level_up` | HQ upgrade / room built / big unlock |
| `chat_open` | chat input opened |
| `countdown` | 3-2-1 beep (one beep per call) |
| `countdown_go` | final "go" beep |
| `challenge_good` | mini-game hit |
| `challenge_bad` | mini-game miss |
| `challenge_done` | mini-game finished |

### World — `Sfx.play(name, pos)` (3D when `pos` given, SFX bus)
| name | when |
|---|---|
| `step_concrete` | footstep on concrete (garage floor) |
| `step_wood` | footstep on wood (stairs, loft, stage) |
| `step_metal` | footstep on metal (ramp, van floor) |
| `jump` | jump effort (soft) |
| `land` | landing |
| `grab` | pick up a generic prop |
| `drop` | release a prop |
| `throw` | throw a prop (whoosh) |
| `impact_cardboard` | cardboard box / crate hits something |
| `impact_wood` | wooden thing hits something |
| `impact_metal` | metal thing hits something |
| `impact_soft` | small light thing (phone, paper) |
| `crate_grab` | pick up a crate (cardboard rustle) |
| `crate_drop` | crate put down |
| `ship_ok` | crate accepted by the van (ship_feedback ok) |
| `ship_fail` | crate rejected |
| `van_door_open` | van rear doors open |
| `van_door_close` | van doors slam |
| `van_start` | engine start (then drive away) |
| `door_open` / `door_close` | normal door |
| `rollup_door` | garage roll-up door |
| `solder` | soldering hiss/crackle |
| `keyboard` | typing burst at a PC |
| `pc_beep` | computer beep |
| `marker` | whiteboard marker squeak |
| `stamp` | job board / paper stamp |
| `paper` | paper / CV rustle |
| `sit` | sit on chair |
| `switch` | light switch / button |
| `machine_beep` | production line beep |
| `whoosh` | stage reveal whoosh |
| `crowd_cheer` | stage crowd cheer |
| `applause` | applause |
| `confetti` | confetti pop |

### Loops — `Sfx.loop(name, node)` (3D, attached to the node)
| name | what |
|---|---|
| `machine_hum` | production line / server hum |
| `conveyor` | conveyor belt rattle |
| `fluorescent` | buzzing fluorescent tube |
| `van_idle` | van engine idling |
| `fridge` | small fridge / PC fan hum |
| `crowd_murmur` | audience murmur (stage) |

### Ambient — `Sfx.ambient(name)` (2D loop, Ambient bus)
`garage` (room tone + distant traffic), `loft` (bigger room tone), `stage` (hall + murmur), `outdoor` (night: crickets, wind), `""` stops.

### Music — `Sfx.music(name)`
`menu`, `game`, `launch`, `""` stops.

## Sources and licenses
**Every sound and all music is original, synthesized from scratch** by `client/audio/gen/make_audio.py`
(numpy + ffmpeg/libvorbis; deterministic seeds). No third-party samples, recordings or loops are used, so there
are no licence obligations: treat the files as part of the game (the project's own licence).
CC0 packs were considered (kenney.nl was blocked from the build machine) — not needed.

| folder | content | how it is made |
|---|---|---|
| `client/audio/sfx/` | UI + world one-shots, 1–5 variants each (`name_1.ogg`…) | modal resonators (wood/metal/cardboard), filtered noise, FM bells, marimba, sweeps |
| `client/audio/loops/` | 3D loops (4–12 s, seamless) | integer-cycle tones + circular FFT filtering, babble from formant-filtered pulses |
| `client/audio/ambient/` | stereo room tones (30–40 s, seamless) | brown/pink noise beds, car passes, crickets, babble, circular reverb |
| `client/audio/music/` | `menu` 66 bpm (58 s), `game` 78 bpm lo-fi hip-hop (49 s), `launch` 92 bpm (42 s) | FM electric piano, saw pads, plucks, synthesized drums, tape wow, vinyl crackle |
| `client/audio/voice/` | 12 robot syllables | formant-filtered square/saw source, light bit-crush |

Total size ≈ 5.5 MB (limit 25 MB). `client/audio/bank_data.gd` (name → files) is generated together with the sounds.

### Regenerating / adding a sound
```
python3 client/audio/gen/make_audio.py              # all (≈2 min)
python3 client/audio/gen/make_audio.py click menu   # re-encode only these names (bank_data.gd is always rewritten)
<godot> --headless --path client --import            # create .import files for new files
<godot> --headless --path client -s tests/audio_smoke.gd
```
Add a new sound by writing a generator snippet that calls `emit(kind, name, [variants], peak_db)`.
