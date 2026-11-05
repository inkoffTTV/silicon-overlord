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
    "final_title": "Repair shop → {company}", "final_sub": "…", "customer_waiting": "…",
    "sign": "PHONE REPAIR"              // the old shop sign in this language (world/title sign may use it)
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
- Customer lines: `cust.<id>.arrive` (walks in, device on the counter), `.story` (signature fault story, only when the
  order has that fault; otherwise `fault.<faultId>.story`), `.wait` (waiting a while), `.happy` (paid),
  `.angry` (waited too long / poor repair score).
- Localized shop sign text: `ui.sign` ("PHONE REPAIR", «РЕМОНТ ТЕЛЕФОНОВ», …) — the same words the captions use.

## 4. The script (English master; every language file has the same ids)

Step "done by" = the server rule from docs/ACTIONS.md. RU objectives are shown for the Russian-speaking owner;
all other texts: `client/ui/data/story/<lang>.json`.

### Chapter 0 · The Workshop / «Мастерская» (`workshop`)
*2 a.m., a garage and a hand-painted sign: PHONE REPAIR*

Cutscene `intro`:
- `cut.intro.1` **Night Shift FM**: Night Shift FM, two a.m. Somewhere out there, a phone just slipped into a bathtub.
- `cut.intro.2` **Night Shift FM**: And somewhere, a few friends are opening a repair shop in a garage. Good luck, night owls.
- `cut.intro.3` **narrator**: A quiet street. A rented garage. A hand-painted sign: PHONE REPAIR.
- `cut.intro.4` **Aunt Mira**: The garage is yours, my dears. Rent is cheap: fix my kettle once a month.
- `cut.intro.5` **narrator**: Tonight the shop opens. Tomorrow? Nobody knows yet.

| step | done by | objective | RU | hint |
|---|---|---|---|---|
| `intro_seen` | storyEvent `intro_seen` | Arrive at the garage | Прийти в гараж | — |
| `door_open` | storyEvent `door_open` (shop_door) | Open the shop door | Открыть дверь мастерской | Walk to the door and press E. Too dark? F turns on the flashlight. |
| `lights_on` | storyEvent `lights_on` (light_switch) | Turn on the lights | Включить свет | The switch is on the wall by the door. Look at it and press E. |

- `step.door_open.1` **Aunt Mira**: The door sticks. Lift the handle and push. The garage respects confidence.
- `step.lights_on.1` **Aunt Mira**: Let there be light! A repair shop in the dark is just a scary garage.
- `step.lights_on.2` **Aunt Mira**: Bench, counter, bell. The bell is the most important tool here. Trust me.

### Chapter 1 · First Customer / «Первый клиент» (`first_customer`)
*Somebody dropped something. Again.*

| step | done by | objective | RU | hint |
|---|---|---|---|---|
| `take_device` | `repairTake` | Take the device from the counter | Взять устройство со стойки | Press E at the counter to accept the order, then carry the device to the bench. |
| `repair_device` | `repairFinish` | Repair it at the bench | Починить его за ремонтным столом | Put it on the repair bench and press E: open it up, find the fault, fix it, close it. |
| `get_paid` | `repairReturn` | Return it at the counter and get paid | Вернуть на стойку и получить деньги | Carry it back and press E at the counter. A neater repair pays more. |
| `second_customer` | 2nd repair paid | Fix a second device | Починить второе устройство | Playing together? One of you takes orders, another repairs. Faster than heroics. |

- `step.take_device.1` **Aunt Mira**: Ding-ding! Your first customer. Smile, they can smell fear. And solder.
- `step.repair_device.1` **Aunt Mira**: Lamp on, magnifier down. Screws go in the cup, not in your pocket.
- `step.get_paid.1` **Aunt Mira**: Fixed? Now the best part: a happy face and real money.
- `step.second_customer.1` **Aunt Mira**: Word travels fast on this street. Here comes another one.

### Chapter 2 · Spare Parts / «Запчасти» (`spare_parts`)
*You can't fix a screen with good intentions*

| step | done by | objective | RU | hint |
|---|---|---|---|---|
| `diagnose_part` | `repairTake` of an order that needs a part | Take the new order to the bench | Отнести новый заказ на ремонтный стол | Press E at the counter, then take a close look at the device on the bench. |
| `call_supplier` | storyEvent `supplier_called` | Call the supplier on the wall phone | Позвонить поставщику с настенного телефона | Press E on the phone on the wall. It opens Purchasing. |
| `buy_parts` | `buyResources repair_*` | Buy spare parts in Purchasing | Купить запчасти в Закупках | Find the screens in the list and buy a few. A handful is plenty for now. |
| `fit_part` | `repairFinish` with a part | Fit the new part at the bench | Поставить новую деталь | Back to the bench: the new part goes in during the repair. |
| `paid_with_part` | `repairReturn` of that order | Return the device and get paid | Вернуть устройство и получить деньги | The price covers the part, so you still make a profit. Good business! |

- `step.diagnose_part.1` **Aunt Mira**: Ooh, that one's crunchy. I think it needs a new part, not just a screwdriver.
- `step.call_supplier.1` **Aunt Mira**: No screens left? You can't fix glass with good intentions.
- `step.call_supplier.2` **Aunt Mira**: Call Zip. Zip answers at any hour. I'm not sure Zip sleeps at all.
- `step.buy_parts.1` **Zip**: Zip Parts, Zip speaking! Screens, batteries, ports. What broke, friend?
- `step.buy_parts.2` **Zip**: Delivered before your tea gets cold. Unless it's iced tea. Then it's a race.
- `step.fit_part.1` **Aunt Mira**: Old glass out, new glass in. Gently. It's thinner than my patience.
- `step.paid_with_part.1` **Aunt Mira**: Your customer is still waiting. Bravely. Let's not test that bravery.

### Chapter 3 · The Same Fault / «Одна и та же поломка» (`same_fault`)
*Every phone breaks in the same place. Interesting…*

| step | done by | objective | RU | hint |
|---|---|---|---|---|
| `pattern_repair` | `repairReturn` of a ch3 order | Fix another broken charging port | Починить ещё один разъём зарядки | Two customers, two broken ports. Out of ports? Buy more in Purchasing. |
| `notice_pattern` | storyEvent `pattern_noticed` (after its 3 lines) | Talk about the pattern | Обсудить закономерность | Listen to Aunt Mira. Something is going on with these phones. |
| `start_research` | `startResearch` (free) | Start your first research at the whiteboard | Начать первое исследование у доски | Press E at the whiteboard and pick a technology. The first one is free. |
| `research_challenge` (opt) | `challengeReward research` | Brainstorm at the whiteboard | Мозговой штурм у доски | A quick mini-game pushes the research forward. Optional, but fun. |

- `step.pattern_repair.1` **Aunt Mira**: Two customers at once, and both with broken charging ports. Hmm.
- `step.notice_pattern.1` **Aunt Mira**: Same port, same wobble, same model. Third one this week.
- `step.notice_pattern.2` **Aunt Mira**: Phones are designed by people who never drop phones. You drop them daily. That's an advantage.
- `step.notice_pattern.3` **Aunt Mira**: You fix them one by one. What if you built one that doesn't break?
- `step.start_research.1` **Aunt Mira**: Fixing one phone is a repair. Fixing all of them is called research.
- `step.research_challenge.1` **Aunt Mira**: Markers out! Bad ideas first: they're blocking the door for the good ones.

### Chapter 4 · Our Own Phone / «Свой телефон» (`own_phone`)
*What if we built one that doesn't break?*

Cutscene `investor`:
- `cut.investor.1` **narrator**: A very quiet car stops outside. Electric, shiny and clearly expensive.
- `cut.investor.2` **Uncle Felix**: Evening! I'm Felix, Mira's brother. She says you fix phones at 2 a.m. and talk to them kindly.
- `cut.investor.3` **Uncle Felix**: I made my fortune on robot vacuums. They kept getting stuck under sofas, so I fixed that.
- `cut.investor.4` **Uncle Felix**: I don't invest in companies. I invest in people who open things up just to see why they broke.
- `cut.investor.5` **Uncle Felix**: Here's {money}. Build a phone I can't break. I'll try very, very hard.
- `cut.investor.6` **Aunt Mira**: He broke three of my kettles. Believe me, he will try.
- `cut.investor.7` **narrator**: The calendar starts ticking. Rent, rivals and salaries are real from today.

| step | done by | objective | RU | hint |
|---|---|---|---|---|
| `investor_seen` | storyEvent `investor_seen` | Meet the visitor at the door | Встретить гостя у двери | — |
| `design_phone` | `createBlueprint` | Design your first phone on the PC | Спроектировать первый телефон на ПК | PC → Design Studio. The defaults work; just fix what your customers hated. |
| `publish_phone` | `publishBlueprint` | Publish the design | Опубликовать проект | On the last step press "Begin development". Your prototype is on its way. |
| `develop_phone` | project finished | Finish developing the prototype | Закончить разработку прототипа | The clock runs now: speed it up, or help with a bug hunt at the PC. |
| `polish_challenge` (opt) | `challengeReward design` | Hunt bugs at the PC | Охота на баги за ПК | Sit on the PC chair for a quick bug hunt. Optional. |

- `step.design_phone.1` **Uncle Felix**: Remember the wobbly ports and the batteries that die by noon? Start there.
- `step.publish_phone.1` **Aunt Mira**: A name, a price and one button. The scariest button in this garage.
- `step.develop_phone.1` **Uncle Felix**: Development is like soup. Don't lift the lid every five minutes.
- `step.polish_challenge.1` **Uncle Felix**: Found a bug? Good. Better you than the critics.

### Chapter 5 · First Batch / «Первая партия» (`first_batch`)
*Handmade, one tiny screw at a time*

| step | done by | objective | RU | hint |
|---|---|---|---|---|
| `queue_batch` | `queueProduction` | Start a batch at the workbench | Запустить партию на верстаке | Press E at the workbench, pick your phone and a quantity. Materials come from Purchasing. |
| `first_crate` | a crate appears | Wait for the first crate | Дождаться первого ящика | Finished phones are packed into crates next to the workbench. |
| `ship_crate` | `shipCrate` / `shipAll` | Carry a crate to the van and ship it | Отнести ящик в фургон и отправить | Grab the crate and put it in the van. Careful handling gives +5% units. |
| `qc_challenge` (opt) | `challengeReward assembly` | QC inspection at the bench | Проверка качества у верстака | Spot the faulty phones for a few extra units. Optional. |

- `step.queue_batch.1` **Aunt Mira**: Hand assembly! Like the old days, only with fewer burns. Hopefully.
- `step.first_crate.1` **Aunt Mira**: Every phone in that crate was made by your hands. Strange feeling, right?
- `step.ship_crate.1` **Uncle Felix**: Gently! That box is our future. And my investment. Mostly my investment.
- `step.qc_challenge.1` **Aunt Mira**: Check every phone as if a customer will drop it. Because they will.

### Chapter 6 · Launch Night / «Презентация» (`launch_night`)
*Spotlights, critics and a brand-new sign*

| step | done by | objective | RU | hint |
|---|---|---|---|---|
| `launch_phone` | `launchProduct` | Launch your phone on stage | Представить телефон на сцене | Press E at the stage when you're ready. The critics are already seated. |
| `reviews_seen` | storyEvent `reviews_seen` | Read what the critics say | Прочитать, что пишут критики | Whatever the score, you shipped a real phone. Most people only talk about it. |
| `sign_swapped` | storyEvent `sign_swapped` → story complete | Hang up the new company sign | Повесить новую вывеску компании | Watch the old sign come down. |

- `step.launch_phone.1` **Vera Benchmark**: Good evening, I'm Vera Benchmark. Three thousand phones reviewed. Every single one dropped.
- `step.launch_phone.2` **Vera Benchmark**: A team from a garage? Let's see if it survives my pocket. And my stairs.
- `step.reviews_seen.1` **Vera Benchmark**: Off the record: I dropped it twice on the way here. Respect.
- `step.sign_swapped.1` **Aunt Mira**: One more thing, my dears. That old sign doesn't fit you anymore.

Cutscene `sign_swap` (after `reviews_seen`, completes `sign_swapped`):
- `cut.sign_swap.1` **Aunt Mira**: Careful with the old sign. It's older than your soldering iron.
- `cut.sign_swap.2` **narrator**: PHONE REPAIR comes down. {company} goes up.
- `cut.sign_swap.3` **Uncle Felix**: Same garage, bigger plans. I'll be in the car. Crying a little.
- `cut.sign_swap.4` **Aunt Mira**: Keep the counter, though. Old customers will still bring you cracked screens.
- `cut.sign_swap.5` **Night Shift FM**: Night Shift FM: a brand-new phone company on our street. Two a.m. never looked so bright.
- `cut.sign_swap.6` **narrator**: The story is over. The garage is yours. Now build something huge.

### Customers (EN)
| id | arrive | story (signature fault) | wait | happy | angry |
|---|---|---|---|---|---|
| `grandma` Grandma Rosa | Good evening, dears! My grandson says this is a phone. I mostly use it to crack walnuts. | It keeps calling my ex-husband all by itself. We split up in 1979! He's very confused. | Take your time. I brought pies. Well, I brought pies for me. | Wonderful! Here's {money}. And a pie. Don't tell my grandson about the walnuts. | In my day repairs were quicker. And walnuts were softer. |
| `student` Max the Student | Hi… sorry, I slept two hours. Can phones be fixed on a student budget? | I snoozed my alarm so many times the button just gave up. Now it's stuck forever. | I'll just close my eyes for a second. Wake me when it's ready. Or never. | You're heroes! Here's {money}. That was my whole noodle budget for the week. | I could have slept through this whole repair. I almost did. |
| `courier` Dina the Courier | Quick, quick! I've got four minutes and eleven parcels. | I carried a cake up nine floors and dropped my phone on the last step. The cake survived! | My break is four minutes. Three now. Two and a half… | Like new! Here's {money}. Five stars, and I'm giving them fast! | Too slow! I could have delivered forty pizzas by now. |
| `teacher` Mr. Pell the Teacher | Good evening. No rush, please. Patience is the first thing I teach. Spelling is the second. | The charging port is full of chalk dust. Thirty years at the blackboard. The chalk finally won. | While we wait: who can name three parts of a phone? Hands up, please. | Excellent work. Here's {money}. An A-plus, and I almost never give those. | I will grade this repair later. Expect a C minus. |
| `gamer` Kit the Gamer | Hey. Okay, first of all: I didn't throw it. It flew. | The cable stayed in the wall and the charging port kind of… went with it. Lag did this. | Is there Wi-Fi here? Asking for my other phone. | GG! It charges! Here's {money}. That's a week of lunch money, you know. | Laaag. Even my grandma's router is faster. |
| `barista` Lou the Barista | Hi-hi! I brought you coffee. Well, I brought me coffee, but you can smell it. | I was drawing a heart on a latte and dipped my wrist right into the milk. Now it's a milkshake watch. | This is longer than a triple espresso. But shorter than decaf. I'm fine. | You're the best! Here's {money}. Free cappuccinos for you all week. | My coffee went cold. My heart did too. A little. |
| `taxi_driver` Sam the Taxi Driver | Evening, chief! Sam the taxi. I know every street in this city and every pothole by name. | Navigation runs sixteen hours a day. This battery has seen more of the city than I have. | I once drove a famous singer down this street. Can't say who. Starts with a letter. | Top service! Here's {money}. Need a ride anywhere? Half price, for you. | The meter's running, friends! Well, it would be, in my taxi. |
| `musician` Jo the Drummer | Yo! Jo, drummer. Don't worry, I left my drums at home. Mostly. | Epic drum solo, the stick slipped and flew straight into my laptop screen. Best solo of my life, though. | Ba-dum-tss. Sorry, I drum on everything when I wait. | Sounds perfect! Here's {money}. You're all on the guest list now. | This repair is slower than our bass player. And that's saying something. |
| `chef` Chef Arno | Good evening, my friends! Chef Arno. I trust you with this like I trust my best knife. | My tablet helped me make dumplings. Now the charging port is packed with flour. | Patience is like dough, my friends. Leave it alone and it rises. | Chef's kiss! Here's {money}. Come eat at my place. Tablets stay away from the dough. | Overcooked! Like this repair. Far too long, my friends. |
| `blogger` Mia the Blogger | Hiii, chat! We're at a real repair shop! Say hi to my followers! | My selfie stick met a ceiling fan. The fan won. Can I film you fixing it? | Waiting content! So authentic. Okay, I'm bored. | Obsessed! Here's {money}. I'm tagging you in everything. | Unfollowing you. Emotionally. |

Generic fault stories (`fault.<id>.story`): `cracked_screen` Long story. Goat yoga. A goat stepped on it. The goat is fine. · `dead_battery` It counted forty thousand steps and died. I think it's just tired. · `broken_port` A toddler at a party tried to charge it with a banana. The banana is fine. · `water_damage` The box said waterproof. The lake disagreed. · `software_glitch` Since Tuesday it only speaks German. I don't. It seems happy, though. · `stuck_button` My cat slept on it all week. The button gave up before the cat did.

Loading tips: 27 per language (`tips`). Credits: `credits` (idea, made with, tech, cast, thanks).

## 5. Editing
- Edit the JSON files directly (UTF-8, keep ids). Change a line in `en.json` and the same id in the 10 other files.
- Run `python3 client/tools/check_story.py` (add `--strict` to fail when a step id is missing from docs/ACTIONS.md).
  It checks JSON, ids/structure vs en.json, placeholders, lengths and CJK glyph coverage (needs `pip install fonttools`).
- A new zh/ja character outside the CJK subsets → either reword, or ask the UI owner to rebuild
  `client/ui/fonts/make_cjk_subset.py` with the story files included.
- New step id from the server → add the step (objective, hint, lines) to every file in the same position; the UI
  falls back to English for anything missing, but the checker will fail until all 11 files have it.
