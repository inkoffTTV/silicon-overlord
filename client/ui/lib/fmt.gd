extends RefCounted
## Number / money / date formatting (port of shared Utils/Format.luau), language aware.

const L := preload("res://ui/lib/loc.gd")

const MONTHS_EN := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
const MONTHS_RU := ["янв", "фев", "мар", "апр", "мая", "июн", "июл", "авг", "сен", "окт", "ноя", "дек"]
const MONTHS := {
	"ru": MONTHS_RU,
	"uk": ["січ", "лют", "бер", "кві", "тра", "чер", "лип", "сер", "вер", "жов", "лис", "гру"],
	"de": ["Jan.", "Feb.", "März", "Apr.", "Mai", "Juni", "Juli", "Aug.", "Sep.", "Okt.", "Nov.", "Dez."],
	"es": ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sept", "oct", "nov", "dic"],
	"pt": ["jan", "fev", "mar", "abr", "mai", "jun", "jul", "ago", "set", "out", "nov", "dez"],
	"fr": ["janv.", "févr.", "mars", "avr.", "mai", "juin", "juil.", "août", "sept.", "oct.", "nov.", "déc."],
	"pl": ["sty", "lut", "mar", "kwi", "maj", "cze", "lip", "sie", "wrz", "paź", "lis", "gru"],
	"tr": ["Oca", "Şub", "Mar", "Nis", "May", "Haz", "Tem", "Ağu", "Eyl", "Eki", "Kas", "Ara"],
}
## short "days" unit per language (n is put in front)
const DAYS_UNIT := {"ru": "дн.", "uk": "дн.", "de": "Tg.", "es": "d", "pt": "d", "fr": "j", "pl": "dni", "tr": "gün", "zh": "天", "ja": "日"}

static func money(v: float, decimals: int = 0) -> String:
	# same compact format as the Roblox version in both languages ($2.50M, $750.0K)
	var neg := v < 0
	var a := absf(v)
	var s := ""
	if a >= 1e12:
		s = "$%.2fT" % (a / 1e12)
	elif a >= 1e9:
		s = "$%.2fB" % (a / 1e9)
	elif a >= 1e6:
		s = "$%.2fM" % (a / 1e6)
	elif a >= 1e4:
		s = "$%.1fK" % (a / 1e3)
	else:
		s = ("$%." + str(decimals) + "f") % a
	return ("-" if neg else "") + s

static func money_full(v: float) -> String:
	var a := int(round(absf(v)))
	return ("-$" if v < 0 else "$") + group(a)

static func group(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var count := 0
	var sep := ","
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = sep + out
	return ("-" if n < 0 else "") + out

static func number(v: float) -> String:
	var a := absf(v)
	if a >= 1e9:
		return "%.2fB" % (v / 1e9)
	if a >= 1e6:
		return "%.2fM" % (v / 1e6)
	if a >= 1e4:
		return "%.1fK" % (v / 1e3)
	return group(int(round(v)))

static func pct(v: float, decimals: int = 0) -> String:
	return ("%." + str(decimals) + "f%%") % (v * 100.0)

static func score(v: float) -> String:
	return "%.1f" % v

## day = day of year (1..360, 30-day months as in Balance.Time)
static func date(year: int, day: int) -> String:
	var q := int((day - 1) / 90)
	var dq := ((day - 1) % 90)
	var month := q * 3 + int(dq / 30)
	var dm := (dq % 30) + 1
	if L.lang == "zh" or L.lang == "ja":
		return "%d年%d月%d日" % [year, clampi(month, 0, 11) + 1, dm]
	var names: Array = MONTHS.get(L.lang, MONTHS_EN)
	if L.lang == "de":
		return "%d. %s %d" % [dm, names[clampi(month, 0, 11)], year]
	return "%d %s %d" % [dm, names[clampi(month, 0, 11)], year]

## Date of an absolute game day (elapsed days since start, day 0 = 1 Jan startYear).
static func day_date(elapsed: int, start_year: int = 2016) -> String:
	var y := start_year + int(elapsed / 360)
	var d := (elapsed % 360) + 1
	return date(y, d)

static func quarter(year: int, day: int) -> String:
	return "Q%d %d" % [int((day - 1) / 90) + 1, year]

static func days(n: int) -> String:
	if DAYS_UNIT.has(L.lang):
		return ("%d%s" if L.is_cjk() else "%d %s") % [n, DAYS_UNIT[L.lang]]
	return "%d day%s" % [n, "" if n == 1 else "s"]

static func plural_ru(n: int, one: String, few: String, many: String) -> String:
	var n10 := n % 10
	var n100 := n % 100
	if n10 == 1 and n100 != 11:
		return one
	if n10 >= 2 and n10 <= 4 and (n100 < 12 or n100 > 14):
		return few
	return many
