extends RefCounted
## Read-only helpers over Game.state.story / Game.state.repairs (WORLD agent, iteration 3).
## Contract: docs/STORY.md "Server contract" + docs/ACTIONS.md "Story & repairs".
##   story   = {done, chapter, step, stepsDone:{stepId:true}, flags:{}, startedDay}
##   repairs = {orders:[{id, customer, device, fault, partId?, reward, status, createdDay}], done}
## No `story` section (old server / old save) = sandbox (story done). Lua sends empty tables as {}.

const HQ := preload("res://world/live/hq_state.gd")

## storyEvent ids the world sends for purely client-side steps (docs/ACTIONS.md "Story & repairs").
const EV_DOOR := "shop_door"
const EV_LIGHTS := "light_switch"
## step ids that mean "the door is open" / "the lights are on" (whatever the server finally names them)
const DOOR_STEPS := ["shop_door", "open_door", "door", "door_open", "shop_open", "open_shop"]
const LIGHT_STEPS := ["light_switch", "lights_on", "lights", "light", "turn_on_lights", "switch_lights"]

const ORDER_LIVE := ["waiting", "inRepair", "ready"]

static func story(s: Dictionary) -> Dictionary:
	return HQ.dict(s.get("story"))

## true while the story tutorial runs (story present and not done)
static func active(s: Dictionary) -> bool:
	var st := story(s)
	return not st.is_empty() and not bool(st.get("done", false))

static func done(s: Dictionary) -> bool:
	return not active(s)

static func chapter(s: Dictionary) -> int:
	if not active(s):
		return 99
	return int(story(s).get("chapter", 0))

static func step(s: Dictionary) -> String:
	return str(story(s).get("step", "")) if active(s) else ""

static func steps_done(s: Dictionary) -> Dictionary:
	return HQ.dict(story(s).get("stepsDone"))

static func flags(s: Dictionary) -> Dictionary:
	return HQ.dict(story(s).get("flags"))

static func any_done(s: Dictionary, ids: Array) -> bool:
	var d := steps_done(s)
	var f := flags(s)
	for id in ids:
		if d.get(id, false) or f.get(id, false):
			return true
	return false

## Shop door (roll-up) open? Always in the sandbox and from chapter 1 on.
static func door_open(s: Dictionary) -> bool:
	if not active(s) or chapter(s) > 0:
		return true
	return any_done(s, DOOR_STEPS)

static func lights_on(s: Dictionary) -> bool:
	if not active(s) or chapter(s) > 0:
		return true
	return any_done(s, LIGHT_STEPS)

## "PHONE REPAIR" look (story running, or no company loaded) vs the company look (story finished / quick start).
static func repair_look(s: Dictionary) -> bool:
	return active(s) or str(s.get("name", "")) == ""

## Story mode keeps the driveway free (no van) until chapter 5 "First Batch".
static func van_visible(s: Dictionary) -> bool:
	return not active(s) or chapter(s) >= 5

## Live repair orders (not paid), oldest first.
static func orders(s: Dictionary) -> Array:
	var out := []
	for o in HQ.arr(HQ.section(s, "repairs").get("orders")):
		if o is Dictionary and str(o.get("id", "")) != "" and str(o.get("status", "waiting")) in ORDER_LIVE:
			out.append(o)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var da := int(a.get("createdDay", 0))
		var db := int(b.get("createdDay", 0))
		return da < db if da != db else str(a.id) < str(b.id))
	return out

static func all_orders(s: Dictionary) -> Dictionary:
	var out := {}
	for o in HQ.arr(HQ.section(s, "repairs").get("orders")):
		if o is Dictionary and str(o.get("id", "")) != "":
			out[str(o.id)] = o
	return out

static func company_name(s: Dictionary) -> String:
	return str(s.get("name", ""))

static func company_colors(s: Dictionary) -> Array:
	var logo := HQ.dict(s.get("logo"))
	var a := Color(0.31, 0.55, 1.0)
	var b := Color(0.69, 0.36, 1.0)
	if str(logo.get("colorA", "")).is_valid_html_color():
		a = Color.html(str(logo.colorA))
	if str(logo.get("colorB", "")).is_valid_html_color():
		b = Color.html(str(logo.colorB))
	return [a, b]

static func company_shape(s: Dictionary) -> String:
	var logo := HQ.dict(s.get("logo"))
	return str(logo.get("shape", s.get("shape", "hex")))

## Device look from free-form server strings: phone | tablet | watch | laptop | handheld | flip
static func device_kind(device: String) -> String:
	var d := device.to_lower()
	if d.contains("tab") or d.contains("pad"):
		return "tablet"
	if d.contains("watch"):
		return "watch"
	if d.contains("laptop") or d.contains("notebook"):
		return "laptop"
	if d.contains("console") or d.contains("game") or d.contains("handheld"):
		return "handheld"
	if d.contains("flip") or d.contains("retro") or d.contains("old") or d.contains("brick"):
		return "flip"
	return "phone"

## Fault look: screen | battery | port | water | button | camera | speaker | other
static func fault_kind(fault: String, part: String = "") -> String:
	var f := (fault + " " + part).to_lower()
	for k in [["screen", "screen"], ["crack", "screen"], ["display", "screen"], ["glass", "screen"], ["batter", "battery"],
			["swoll", "battery"], ["port", "port"], ["charg", "port"], ["water", "water"], ["wet", "water"], ["soup", "water"],
			["tea", "water"], ["button", "button"], ["camera", "camera"], ["lens", "camera"], ["speaker", "speaker"], ["sound", "speaker"]]:
		if f.contains(k[0]):
			return k[1]
	return "other"

# ------------------------------------------------------------------ fake state (tests / screenshots, until the server lands)
static func fake_story(chapter_n: int, step_id: String, done_steps: Array = [], finished: bool = false) -> Dictionary:
	var d := {}
	for id in done_steps:
		d[id] = true
	return {"done": finished, "chapter": chapter_n, "step": step_id, "stepsDone": d, "flags": {}, "startedDay": 1}

static func fake_order(id: String, customer: String, device: String, fault: String, status: String, day: int = 1) -> Dictionary:
	return {"id": id, "customer": customer, "device": device, "fault": fault, "partId": "repair_" + fault_kind(fault),
		"reward": 80, "status": status, "createdDay": day}

## A minimal company state for story tests / shots.
static func fake_state(chapter_n: int, step_id: String, done_steps: Array = [], orders_list: Array = [], finished: bool = false) -> Dictionary:
	return {
		"name": "Pocket Rocket",
		"logo": {"colorA": "#FF7A3D", "colorB": "#2BD1FF", "shape": "hex"},
		"time": {"year": 2016, "day": 3, "speed": 0, "elapsedDays": 2},
		"hq": {"level": 1, "rooms": {}},
		"finance": {"cash": 6000},
		"story": fake_story(chapter_n, step_id, done_steps, finished),
		"repairs": {"orders": orders_list, "done": 0},
	}
