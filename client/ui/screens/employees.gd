extends "res://ui/screens/screen_base.gd"
## Employees ("job_board"): the candidate pool (hire), your staff grouped by work station (salary, fire),
## new candidates for research points. Actions: hire / fire / setSalary / rerollCandidates (docs/ACTIONS.md "Employees").

const D := preload("res://ui/lib/gdata.gd")
const Portrait := preload("res://ui/lib/portrait.gd")

## role -> [colour, station]
const ROLES := {
	"HardwareEngineer": [Color("#3DD68C"), "design"], "SoftwareEngineer": [Color("#38C6D9"), "design"],
	"Researcher": [Color("#7C5CFF"), "research"], "Worker": [Color("#F0883E"), "assembly"], "QCEngineer": [Color("#F2C94C"), "assembly"],
	"Marketer": [Color("#E85CC4"), "office"], "FinancialAnalyst": [Color("#4F8CFF"), "office"], "LogisticsManager": [Color("#9AA4BF"), "office"],
}
## station -> [icon, title, where]
const STATIONS := {
	"design": ["palette", "Design", "PC desks"], "research": ["flask", "Research", "Whiteboard & lab"],
	"assembly": ["factory", "Assembly", "Workbench & lines"], "office": ["chart", "Office", "Office desks"],
}
const REROLL_RP := 20

var _top: HBoxContainer
var _board: GridContainer
var _team: VBoxContainer
var _confirm_fire := ""
var _busy := {}

func _init() -> void:
	title = "Employees"
	subtitle = "Job board · hire people, set salaries, keep the team happy"
	icon_name = "cv"
	accent = U.ACCENT
	watch_keys = ["employees", "finance", "research", "hq", "time"]

func build_body(b: Control) -> void:
	var v := U.vbox(14)
	b.add_child(v)
	_top = U.hbox(10)
	v.add_child(_top)
	var h := U.hbox(16)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(h)
	var left := U.vbox(10)
	var lw := U.vbox(10)
	lw.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lw.size_flags_stretch_ratio = 1.2
	h.add_child(lw)
	var lh := U.hbox(8)
	lh.add_child(U.icon("cv", U.ACCENT, 16))
	lh.add_child(U.caps(L.t("CANDIDATES"), U.ACCENT, 11))
	lw.add_child(lh)
	_board = U.grid(2, 10, 10)
	left.add_child(_board)
	lw.add_child(U.scroll(U.margin(left, 0, 0, 10, 0)))
	var rw := U.vbox(10)
	rw.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(rw)
	var rh := U.hbox(8)
	rh.add_child(U.icon("team", U.SUCCESS, 16))
	rh.add_child(U.caps(L.t("YOUR TEAM"), U.SUCCESS, 11))
	rw.add_child(rh)
	_team = U.vbox(8)
	rw.add_child(U.scroll(U.margin(_team, 0, 0, 10, 0)))

func _emp() -> Dictionary:
	return U.dict(state().get("employees", {}))

func _staff() -> Array:
	return U.arr(_emp().get("list", []))

func _cap() -> int:
	var lvl := int(U.num(U.dict(state().get("hq", {})).get("level", 1), 1))
	var caps: Array = D.balance("Employees").get("hqStaffCap", [10, 25, 60, 140, 280, 500, 1000])
	return int(caps[clampi(lvl - 1, 0, caps.size() - 1)]) if not caps.is_empty() else 10

const ROLE_NAMES := {"HardwareEngineer": "Hardware engineer", "SoftwareEngineer": "Software engineer", "Researcher": "Researcher",
	"Worker": "Worker", "QCEngineer": "QC engineer", "Marketer": "Marketer", "FinancialAnalyst": "Financial analyst",
	"LogisticsManager": "Logistics manager"}

static func role_name(role: String) -> String:
	if L.lang == "ru":
		return L.t(role)
	return L.t(str(ROLE_NAMES.get(role, role)))

static func station_of(e: Dictionary) -> String:
	var st := str(e.get("station", ""))
	if STATIONS.has(st):
		return st
	return str(ROLES.get(str(e.get("role", "")), [U.MUTED, "office"])[1])

static func role_color(role: String) -> Color:
	return ROLES.get(role, [U.MUTED, "office"])[0]

func refresh() -> void:
	if state().is_empty() or _board == null:
		return
	_build_top()
	_build_board()
	_build_team()

# ---------------------------------------------------------------- top stats
func _stat(cap: String, val: String, col: Color = U.TEXT) -> void:
	var c := U.card("CardFlat")
	var v := U.vbox(0)
	c.add_child(v)
	v.add_child(U.caps(L.t(cap), U.MUTED, 10))
	v.add_child(U.lbl(val, U.MD, col, "bold"))
	_top.add_child(c)

func _build_top() -> void:
	U.clear(_top)
	var list := _staff()
	var wages := 0.0
	for e in list:
		wages += U.num(e.get("salaryMonthly", 0))
	var morale := U.num(_emp().get("morale", 0))
	_stat("STAFF", "%d / %d" % [list.size(), _cap()], U.DANGER if list.size() >= _cap() else U.TEXT)
	_stat("MORALE", F.pct(morale), U.SUCCESS if morale >= 0.6 else (U.WARNING if morale >= 0.4 else U.DANGER))
	_stat("WAGES / MONTH", F.money(wages))
	_stat("CASH", F.money(U.num(U.dict(state().get("finance", {})).get("cash", 0))), U.SUCCESS)
	_top.add_child(U.spacer())
	var rp := int(U.num(U.dict(state().get("research", {})).get("points", 0)))
	var nv := U.vbox(2)
	nv.alignment = BoxContainer.ALIGNMENT_CENTER
	var refresh_day := int(U.num(_emp().get("candidatesRefreshDay", 0)))
	var every := int(U.num(D.balance("Employees").get("candidateRefreshDays", 30), 30))
	var now := int(U.num(U.dict(state().get("time", {})).get("elapsedDays", 0)))
	var left := maxi(0, refresh_day + every - now) if refresh_day > 0 else every
	var note := U.lbl(L.f("New people arrive in {d}", {"d": F.days(left)}), U.XS + 1, U.MUTED)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	nv.add_child(note)
	_top.add_child(nv)
	var rr := U.btn(L.f("New candidates · {rp} RP", {"rp": REROLL_RP}), "", "spin", 0, 40)
	rr.disabled = rp < REROLL_RP
	rr.tooltip_text = L.t("Replace the whole job board with new people.")
	rr.pressed.connect(func() -> void:
		var r: Dictionary = await run("rerollCandidates", {})
		if r.get("ok", false):
			sfx("paper"))
	_top.add_child(rr)

# ---------------------------------------------------------------- candidates
func _build_board() -> void:
	U.clear(_board)
	var cands := U.arr(_emp().get("candidates", []))
	if cands.is_empty():
		var p := U.para(L.t("Nobody is looking for a job right now. New people arrive every month."), U.SM, U.MUTED)
		p.custom_minimum_size.x = 300
		_board.add_child(p)
		return
	var full := _staff().size() >= _cap()
	for c in cands:
		_board.add_child(_candidate_card(c, full))

func _stars(skill: float) -> String:
	var n := clampi(int(round(skill * 5.0)), 0, 5)
	if skill > 0.02:
		n = maxi(n, 1)
	return "★".repeat(n) + "☆".repeat(5 - n)

func _candidate_card(c: Dictionary, full: bool) -> Control:
	var card := U.card("CardAlt")
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := U.vbox(8)
	card.add_child(v)
	var h := U.hbox(12)
	v.add_child(h)
	var role := str(c.get("role", ""))
	var por := Portrait.new()
	por.seed_text = str(c.get("id", "")) + str(c.get("name", ""))
	por.tint = role_color(role)
	por.custom_minimum_size = Vector2(60, 60)
	h.add_child(por)
	var tv := U.vbox(3)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(tv)
	tv.add_child(U.clip(str(c.get("name", "?")), U.MD, U.TEXT, "bold"))
	var rp := U.pill(role_name(role), role_color(role))
	rp.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	tv.add_child(rp)
	var st: Array = STATIONS[station_of(c)]
	var sh := U.hbox(5)
	sh.add_child(U.icon(st[0], U.DIM, 12))
	sh.add_child(U.clip(L.t(st[2]), U.XS, U.DIM))
	tv.add_child(sh)
	# skill + experience
	var g := U.grid(2, 8, 2)
	v.add_child(g)
	g.add_child(U.lbl(L.t("Skill"), U.XS + 1, U.MUTED))
	g.add_child(U.lbl(_stars(U.num(c.get("skill", 0))), U.SM, U.GOLD))
	g.add_child(U.lbl(L.t("Experience"), U.XS + 1, U.MUTED))
	var eb := U.bar(U.num(c.get("experience", 0)), U.CYAN, 5)
	eb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	g.add_child(eb)
	var row := U.hbox(8)
	v.add_child(row)
	var sal := U.num(c.get("salaryMonthly", 0))
	var sv := U.vbox(0)
	sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sv.add_child(U.lbl(F.money_full(sal), U.MD, U.TEXT, "bold"))
	sv.add_child(U.lbl(L.t("per month"), U.XS, U.MUTED))
	row.add_child(sv)
	var cid := str(c.get("id", ""))
	var hire := U.btn(L.t("Hire"), "BtnPrimary", "plus", 0, 36)
	hire.disabled = full or _busy.has(cid)
	hire.tooltip_text = L.f("Staff cap reached ({n}). Upgrade the HQ.", {"n": _cap()}) if full else L.f("Signing bonus: {amount} (one month's salary)", {"amount": F.money(sal)})
	hire.pressed.connect(func() -> void: _hire(cid, str(c.get("name", ""))))
	row.add_child(hire)
	U.hover_lift(card)
	return card

func _hire(cid: String, who: String) -> void:
	_busy[cid] = true
	var r: Dictionary = await run("hire", {"candidateId": cid})
	_busy.erase(cid)
	if not is_inside_tree():
		return
	if r.get("ok", false):
		sfx("confirm")
		toast("success", L.f("{name} joined the team", {"name": who}), L.t("They will find their desk in the garage."))
	refresh()

# ---------------------------------------------------------------- staff
func _build_team() -> void:
	U.clear(_team)
	var by := {}
	for e in _staff():
		var st := station_of(e)
		if not by.has(st):
			by[st] = []
		by[st].append(e)
	if by.is_empty():
		_team.add_child(U.para(L.t("No staff yet. Hire someone from the job board."), U.SM, U.MUTED))
		return
	for st in ["design", "research", "assembly", "office"]:
		if not by.has(st):
			continue
		var info: Array = STATIONS[st]
		var hh := U.hbox(8)
		hh.add_child(U.icon(info[0], U.MUTED, 14))
		hh.add_child(U.lbl(L.t(info[1]), U.SM, U.TEXT, "bold"))
		hh.add_child(U.lbl("· " + L.t(info[2]) + " · %d" % by[st].size(), U.XS + 1, U.MUTED))
		_team.add_child(hh)
		for e in by[st]:
			_team.add_child(_staff_row(e))

func _staff_row(e: Dictionary) -> Control:
	var eid := str(e.get("id", ""))
	var c := U.card("CardFlat")
	var v := U.vbox(8)
	c.add_child(v)
	var h := U.hbox(10)
	v.add_child(h)
	var role := str(e.get("role", ""))
	var por := Portrait.new()
	por.seed_text = eid + str(e.get("name", ""))
	por.tint = role_color(role)
	por.mood = U.num(e.get("satisfaction", 0.6), 0.6)
	por.custom_minimum_size = Vector2(42, 42)
	h.add_child(por)
	var tv := U.vbox(1)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(tv)
	var nh := U.hbox(6)
	nh.add_child(U.clip(str(e.get("name", "?")), U.SM, U.TEXT, "semibold"))
	nh.add_child(U.lbl(_stars(U.num(e.get("skill", 0))), U.XS + 1, U.GOLD))
	tv.add_child(nh)
	tv.add_child(U.clip(role_name(role), U.XS + 1, role_color(role).lightened(0.1), "semibold"))
	var sat := U.num(e.get("satisfaction", 0.6), 0.6)
	var mb := U.hbox(6)
	mb.add_child(U.lbl(L.t("Happiness"), U.XS, U.DIM))
	mb.add_child(U.bar(sat, U.SUCCESS if sat >= 0.6 else (U.WARNING if sat >= 0.4 else U.DANGER), 4))
	tv.add_child(mb)
	# salary stepper
	var sal := U.num(e.get("salaryMonthly", 0))
	var market := U.num(e.get("marketSalary", sal), sal)
	var step := maxf(100.0, snappedf(market * 0.05, 100.0))
	var sv := U.vbox(0)
	var sh := U.hbox(2)
	var minus := U.icon_btn("minus", "BtnFlat", 26, L.t("Lower salary"))
	var val := U.lbl(F.money_full(sal), U.SM, U.TEXT, "bold")
	val.custom_minimum_size.x = 64
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var plus := U.icon_btn("plus", "BtnFlat", 26, L.t("Raise salary"))
	minus.disabled = sal - step < market * 0.5 - 0.5
	plus.disabled = sal + step > market * 3.0 + 0.5
	minus.pressed.connect(func() -> void: _set_salary(eid, sal - step))
	plus.pressed.connect(func() -> void: _set_salary(eid, sal + step))
	sh.add_child(minus)
	sh.add_child(val)
	sh.add_child(plus)
	sv.add_child(sh)
	var ml := U.lbl(L.f("market {amount}", {"amount": F.money_full(market) if market < 1e5 else F.money(market)}), U.XS, U.WARNING if sal < market * 0.95 else U.DIM)
	ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sv.add_child(ml)
	h.add_child(sv)
	if _confirm_fire == eid:
		var box := U.hbox(8)
		var q := U.para(L.f("Fire {name}? Severance: {amount}.", {"name": str(e.get("name", "")), "amount": F.money(sal * 2.0)}), U.XS + 1, U.TEXT)
		box.add_child(q)
		var yes := U.btn(L.t("Fire"), "BtnDanger", "", 0, 30)
		yes.pressed.connect(func() -> void: _fire(eid, str(e.get("name", ""))))
		box.add_child(yes)
		var no := U.btn(L.t("Cancel"), "BtnGhost", "", 0, 30)
		no.pressed.connect(func() -> void:
			_confirm_fire = ""
			refresh())
		box.add_child(no)
		v.add_child(box)
	else:
		var fire := U.icon_btn("close", "BtnFlat", 30, L.t("Fire"))
		fire.pressed.connect(func() -> void:
			_confirm_fire = eid
			refresh())
		h.add_child(fire)
	return c

func _set_salary(eid: String, salary: float) -> void:
	await run("setSalary", {"employeeId": eid, "salary": int(round(salary))})
	if is_inside_tree():
		sfx("click")

func _fire(eid: String, who: String) -> void:
	_confirm_fire = ""
	var r: Dictionary = await run("fire", {"employeeId": eid})
	if not is_inside_tree():
		return
	if r.get("ok", false):
		toast("info", L.f("{name} left the company", {"name": who}), L.f("Severance paid: {amount}", {"amount": F.money(U.num(U.dict(r.get("data", {})).get("severance", 0)))}))
	refresh()

func on_escape() -> bool:
	if _confirm_fire != "":
		_confirm_fire = ""
		refresh()
		return true
	return false
