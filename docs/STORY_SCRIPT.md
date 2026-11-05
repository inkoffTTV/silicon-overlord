# Story script — "From the repair shop to a phone company" (NARRATIVE agent)

Design and server/client contracts: docs/STORY.md. This file is the script: the JSON schema of the story texts, the
cast, every id other agents may reference, and the English master text of every chapter.
Data: `client/ui/data/story/<lang>.json`, one file per language. Checker: `python3 client/tools/check_story.py`.

## 1. JSON schema (`client/ui/data/story/<lang>.json`)
`<lang>` = the client's language code (`L.lang`): `en ru uk de es pt fr pl tr zh ja` (`pt` = Brazilian Portuguese).
`en.json` is the master: every other file has exactly the same ids, structure and non-text fields; only texts differ.

```jsonc
{
  "lang": "en",                         // file language code
  "version": 1,                         // bump when ids change
  "speakers": {                         // everyone who can say a line (customers are in "customers", not here)
    "<speakerId>": {
      "name": "Aunt Mira",              // shown above the subtitle ("" = narrator caption, no name plate)
      "voice": 900573                   // int for Sfx.speak(voice, name, text): stable per-character pitch/rate
    }
  },
  "chapters": [                         // index = story.chapter (0..6)
    {
      "id": 0,                          // == state.story.chapter
      "key": "workshop",                // stable slug (art, sounds, analytics)
      "title": "The Workshop",          // chapter card title, ≤ 40 chars
      "subtitle": "…",                  // chapter card second line, ≤ 80 chars
      "steps": [                        // in order; id == state.story.step / key of state.story.stepsDone
        {
          "id": "open_door",
          "optional": false,            // optional steps never block the chapter (tracker shows "Optional")
          "objective": "Open the shop door",   // tracker line, ≤ 60 chars, imperative
          "hint": "Walk to the door and press E.",  // small grey line under the objective, ≤ 140 chars, may be ""
          "lines": [                    // 0–3 lines, played once when the step becomes current; never block input
            {"id": "step.open_door.1", "speaker": "mira", "text": "…"}   // text ≤ 140 chars
          ]
        }
      ]
    }
  ],
  "customers": [                        // repair-shop NPCs; id == repairs.orders[].customer (server ids)
    {
      "id": "grandma",
      "voice": 900575,                  // Sfx.speak id
      "deviceId": "phone",              // signature device  (phone | tablet | laptop | watch)
      "faultId": "software_glitch",     // signature fault   (a key of "faults")
      "name": "Grandma Rosa",
      "device": "Phone (a gift from her grandson)",       // receipt line for the signature device
      "fault": "Calls her ex-husband by itself. …",       // receipt line for the signature fault, ≤ 80 chars
      "lines": {
        "arrive": "…",                  // walks in, puts the device down: greeting, fits ANY fault
        "story":  "…",                  // tells the signature fault story (only when order.fault == faultId)
        "wait": "…", "happy": "… {money} …", "angry": "…"   // ≤ 140 chars each, fit any fault
      }
    }
  ],
  "devices": {"phone": "Phone", "tablet": "Tablet", "laptop": "Laptop", "watch": "Smartwatch"},
  "faults": {                           // keys == repairs.orders[].fault
    "cracked_screen": {"name": "Cracked screen", "part": "screen", "story": "…"},   // part: screen|battery|port|null
    "water_damage":   {"name": "Water damage",   "part": null,     "story": "…"}    // story: generic fault story,
  },                                                                                 // said by a customer whose
  "parts": {"screen": "Replacement screen", "battery": "…", "port": "…"},           // signature fault differs
  "cutscenes": {                        // Bus.story_cutscene(id); captions shown in order, one per beat
    "intro":     {"captions": [{"id": "cut.intro.1", "speaker": "radio", "text": "…"}]},
    "investor":  {"captions": […]},
    "sign_swap": {"captions": […]}
  },
  "tips": ["…"],                        // loading-screen tips, 25+, ≤ 140 chars each
  "credits": {
    "title": "…",
    "sections": [{"id": "idea", "heading": "Idea & game design", "lines": ["inkoffTTV"]}],
    "closing": "…"
  },
  "ui": {                               // small story-only labels (the UI may use its own i18n instead)
    "chapter": "Chapter {n}", "optional": "Optional", "story_complete": "Story complete",
    "final_title": "Repair shop → {company}", "final_sub": "…", "customer_waiting": "…"
  }
}
```

### Rules
- **Ids** of lines/captions are global and unique in a file: `step.<stepId>.<n>`, `cut.<cutsceneId>.<n>`,
  `cust.<customerId>.<arrive|story|wait|happy|angry>`, `fault.<faultId>.story`. `Bus.story_dialogue(line_id)` may
  carry any of them (customer ids resolve to `customers[i].lines[kind]`, speaker = that customer).
- **A repair order** `{customer, device, fault}` (server picks the combination; scripted orders in chapters 1–3 always
  use the customer's signature pair, random side orders may not):
  1. customer walks in → speak `lines.arrive`, then `lines.story` if `order.fault == faultId`, else
     `faults[order.fault].story` (same speaker/voice — the customer tells it);
  2. receipt: `name`; device = `device` if `order.device == deviceId` else `devices[order.device]`;
     fault = `fault` if `order.fault == faultId` else `faults[order.fault].name`; part needed = `parts[faults[..].part]`;
  3. waiting long → `wait`; `repairReturn` → `happy` ({money} = payout); a poor score (< 0.4) or a customer who
     leaves → `angry`. An unknown customer id → generic: name = devices/faults names only, no lines.
- **Placeholders** (filled by the UI, kept verbatim in every language): `{company}` company name, `{player}` nickname
  of the player the line is about (the one who acted; else the local player), `{money}` formatted amount
  (repair reward in customer `happy` lines, investor top-up in `cut.investor.*`), `{n}` a number (ui.chapter).
- **Speakers**: `narrator` has an empty name (render as an italic caption without a name plate). A customer speaks
  with its own `name` and `voice`. Lines never name the founders: the players are addressed as a team ("you").
- **Step lines** play once when the step becomes the current step (`state.story.step`). Steps can complete in any
  order (co-op), so a step finished before it became current simply skips its lines. `notice_pattern` is the dialogue
  itself: play its 3 lines, then send `storyEvent {id:"pattern_noticed"}`.
- **Lengths** (checked): objective ≤ 60, line / caption / hint / tip / customer line ≤ 140, fault ≤ 80, title ≤ 40,
  subtitle ≤ 80 characters, in every language.
- Missing language file or id → fall back to `en.json` (the checker guarantees this never happens in the repo).
- zh / ja texts only use characters the bundled CJK subsets contain (the checker verifies this with fontTools).

## 2. Cast (original characters)
| id | EN name | RU name | who | voice |
|---|---|---|---|---|
| `narrator` | — | — | caption voice for cutscenes | 901709 |
| `radio` | Night Shift FM | Радио «Ночная смена» | the 2 a.m. radio DJ playing in the garage | 900977 |
| `mira` | Aunt Mira | тётя Мира | the landlady next door, retired electronics engineer, the mentor; tea, sarcasm, a soft heart | 900573 |
| `felix` | Uncle Felix | дядя Феликс | Mira's younger brother, got rich on robot vacuums ("they got stuck under sofas, so I fixed that"); the investor of chapter 4; breaks everything he touches | 901266 |
| `zip` | Zip | Зип | the parts supplier on the phone, talks very fast, never sleeps | 901509 |
| `critic` | Vera Benchmark | Вера Бенчмарк | famous phone reviewer at the launch; has dropped every phone she ever reviewed | 901258 |

### Customers (`repairs.orders[].customer`, ids from shared-luau/Data/Story.luau)
| id | EN name | RU name | signature device / fault | personality | voice |
|---|---|---|---|---|---|
| `grandma` | Grandma Rosa | Бабушка Роза | phone / software_glitch: calls her ex-husband by itself (split up in 1979) | sweet, sharp, uses the phone as a walnut cracker | 900575 |
| `student` | Max the Student | Студент Макс | phone / stuck_button: a thousand snoozed alarms | sleepy, broke, noodle budget | 900621 |
| `courier` | Dina the Courier | Курьер Дина | phone / cracked_screen: dropped it carrying a cake up nine floors | always in a hurry, counts minutes | 901656 |
| `teacher` | Mr. Pell the Teacher | Учитель Пелл | phone / broken_port: thirty years of chalk dust | patient, grades everything | 900906 |
| `gamer` | Kit the Gamer | Геймер Кит | phone / broken_port: "didn't throw it, it flew" | 14, blames lag | 901217 |
| `barista` | Lou the Barista | Бариста Лу | watch / water_damage: dipped it in the milk jug | bubbly, coffee everything | 901011 |
| `taxi_driver` | Sam the Taxi Driver | Таксист Сэм | phone / dead_battery: navigation 16 hours a day | chatty, knows every pothole | 901313 |
| `musician` | Jo the Drummer | Барабанщица Джо | laptop / cracked_screen: drumstick flew off in a solo | loud, cheerful | 900431 |
| `chef` | Chef Arno | Шеф Арно | tablet / broken_port: port packed with flour | warm, dough metaphors | 901216 |
| `blogger` | Mia the Blogger | Блогерша Мия | phone / cracked_screen: selfie stick vs ceiling fan | films everything | 900873 |
Scripted orders (server) use exactly these pairs: ch1 grandma, student; ch2 courier (needs a screen); ch3 teacher and
gamer (both broken ports: "the same fault"). Generic stories for other combinations: `faults.<id>.story`
(goat yoga, 40 000 steps, banana charger, "waterproof" lake, phone that speaks only German, a cat sleeping on it).

## 3. Ids other agents use
- Chapters `0..6`, keys: `workshop`, `first_customer`, `spare_parts`, `same_fault`, `own_phone`, `first_batch`,
  `launch_night`.
- Step ids: see the table in section 4 (they are the server's ids from docs/ACTIONS.md "Story & repairs").
- Cutscene captions (WORLD may emit `Bus.story_dialogue(id)` at these beats; otherwise the UI paces them itself):
  `cut.intro.1..5` (1–2 radio over the night street, 3 the sign, 4 Mira at the door, 5 push in through the door),
  `cut.investor.1..7` (1 a quiet car pulls up, 2–5 Felix at the door, 6 Mira, 7 the calendar starts),
  `cut.sign_swap.1..6` (1 Mira, 2 old sign down / new sign up, 3 Felix, 4 the counter stays, 5 radio, 6 the end).
- Customer lines: `cust.<id>.arrive` (walks in, device on the counter), `.wait` (waiting a while), `.happy` (paid),
  `.angry` (waited too long / poor repair score).
