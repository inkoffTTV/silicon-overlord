extends "res://ui/screens/screen_base.gd"
## Locked stairs ("stairs_locked"): buy the second floor of the garage = room AssemblyLine (buildRoom).
## Price comes from the server (getRoomCatalog), with Balance as a fallback while it answers.

const D := preload("res://ui/lib/gdata.gd")

var _v: VBoxContainer
var _cost := -1.0
var _reason := ""
var _busy_buy := false

func _init() -> void:
	title = "Second floor"
	subtitle = "Upstairs is still empty and dusty"
	icon_name = "stairs"
	accent = U.ORANGE
	compact_width = 560
	watch_keys = ["hq", "finance"]

func build_body(b: Control) -> void:
	_v = U.vbox(12)
	b.add_child(_v)
	_fetch_price()

func _fetch_price() -> void:
	var r: Dictionary = await Net.act("getRoomCatalog", {})
	if not is_inside_tree():
		return
	if r.get("ok", false):
		var room := U.dict(U.dict(U.dict(r.get("data", {})).get("rooms", {})).get("AssemblyLine", {}))
		if room.has("nextCost") and room.nextCost != null:
			_cost = U.num(room.nextCost)
		if not room.get("canBuild", true):
			_reason = L.t(str(room.get("reason", "")))
		refresh()

func _owned() -> bool:
	return U.dict(U.dict(state().get("hq", {})).get("rooms", {})).has("AssemblyLine")

func price() -> float:
	if _cost >= 0:
		return _cost
	var base := U.dict(D.balance("HQ").get("roomBuildCostBase", {}))
	return U.num(base.get("AssemblyLine", 150000), 150000)

func refresh() -> void:
	if _v == null:
		return
	U.clear(_v)
	if _owned():
		_v.add_child(U.para(L.t("The second floor is yours. Build production lines up there from the workbench screen."), U.SM, U.TEXT))
		var go := U.btn(L.t("Open production"), "BtnPrimary", "factory", 0, 42)
		go.pressed.connect(func() -> void:
			if ui_root and ui_root.has_method("open_screen"):
				ui_root.open_screen("workbench_production", ""))
		_v.add_child(go)
		return
	_v.add_child(U.para(L.t("Buy the floor above the garage and turn it into a small assembly hall."), U.MD, U.TEXT))
	var c := U.card("CardAlt")
	var cv := U.vbox(8)
	c.add_child(cv)
	cv.add_child(U.caps(L.t("WHAT IT UNLOCKS")))
	for it in [["factory", "Real production lines: much faster than building phones by hand"], ["bolt", "+8% line efficiency per room level"],
			["team", "Workers and QC engineers get their own stations upstairs"], ["eye", "Quality checks on the line (a mini-game)"]]:
		var h := U.hbox(10)
		h.add_child(U.icon(it[0], U.ORANGE, 16))
		h.add_child(U.para(L.t(it[1]), U.SM, U.TEXT))
		cv.add_child(h)
	_v.add_child(c)
	var cash := U.num(U.dict(state().get("finance", {})).get("cash", 0))
	var cost := price()
	var ph := U.hbox(10)
	_v.add_child(ph)
	var pv := U.vbox(0)
	pv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pv.add_child(U.caps(L.t("PRICE")))
	pv.add_child(U.lbl(F.money_full(cost), U.XL, U.TEXT, "display"))
	ph.add_child(pv)
	var cv2 := U.vbox(0)
	cv2.add_child(U.caps(L.t("CASH")))
	cv2.add_child(U.lbl(F.money_full(cash), U.LG, U.SUCCESS if cash >= cost else U.DANGER, "bold"))
	ph.add_child(cv2)
	if _reason != "":
		_v.add_child(U.para(_reason, U.SM, U.WARNING))
	elif cash < cost:
		_v.add_child(U.para(L.t("Not enough cash yet: sell some phones or take a bank loan."), U.SM, U.WARNING))
	var row := U.hbox(8)
	_v.add_child(row)
	var buy := U.btn(L.f("Buy the second floor · {cost}", {"cost": F.money(cost)}), "BtnOrange", "stairs", 0, 46)
	buy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buy.disabled = cash < cost or _reason != "" or _busy_buy
	buy.pressed.connect(_buy)
	row.add_child(buy)
	var close := U.btn(L.t("Not now"), "BtnFlat", "", 0, 46)
	close.pressed.connect(request_close)
	row.add_child(close)

func _buy() -> void:
	_busy_buy = true
	refresh()
	var r: Dictionary = await run("buildRoom", {"roomId": "AssemblyLine"})
	_busy_buy = false
	if not is_inside_tree():
		return
	if r.get("ok", false):
		var d := U.dict(r.get("data", {}))
		if d.get("pending", false):
			toast("info", L.t("Waiting for approval"), L.t("Your co-founders have to approve this purchase."))
		else:
			sfx("level_up")
			toast("success", L.t("The second floor is yours"), L.t("Head upstairs: production lines can be built there now."))
		request_close()
	else:
		refresh()
