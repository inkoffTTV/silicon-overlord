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
Sfx.speak(user_id: int, display_name: String, text: String, at: Variant = null)   # chat line → character voice
# extras (added in iteration 2, all optional)
Sfx.loop(name: String, parent: Node3D, volume_db := 0.0) -> Node   # looping 3D emitter attached to parent (machine hum, conveyor…)
Sfx.stop_loop(player: Node)                                       # stops/frees what loop() returned (freeing the parent works too)
Sfx.apply_settings()                                              # re-read user://settings.cfg [audio] (UI calls after changing it)
```
`play()` picks a random variant and a small random pitch (±4%) for one-shots so repeated steps/impacts never sound identical.

## What Sfx does by itself (do NOT also do it in UI/world code)
- **Chat voices**: Sfx listens to `Net.chat_received` and speaks every line (yours too — the server echoes it).
  The UI must not call `Sfx.speak` for chat. Speaker position: `world.avatar_position(user_id)` if the world has it,
  else the latest `Bus.peers_changed` position of that user, else the listener (full volume).
- **Notifications**: `Bus.notify(kind, …)` → `notify` / `success` / `warning` / `error` UI sound
  (research titles → `research_done`, sale/revenue titles → `cash_register`). Max one per 0.25 s.
- **Launch show music**: `Bus.launch_show` → music "launch"; `Bus.launch_finished` (or the world's `launch_finished`) → back to "game".
- **Ducking**: music (and ambient a bit) duck by ~8 dB while someone is speaking.

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
The UI settings panel writes these keys and then calls `Sfx.apply_settings()` (Sfx also re-reads on `Bus.settings_changed`).

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
All sounds and music are synthesized procedurally in code at startup (`client/audio/synth.gd`) — original,
no third-party files, no license obligations. (Details below are filled in when the implementation lands.)
