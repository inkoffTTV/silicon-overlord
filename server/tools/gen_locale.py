#!/usr/bin/env python3
"""Builds the localization key catalog (server/locale/catalog.json) and docs/LOCALE_KEYS.md.

    python3 server/tools/gen_locale.py          # regenerate both files
    python3 server/tools/gen_locale.py --check  # exit 1 when they are out of date (used by the tests)

Sources of English texts the server can send:
  1. Lua rules / services (shared-luau/**, server/lua/**): `fail(...)`, `return false, ...` (action errors),
     `title = ...` / `body = ...` table fields (notifications), `addNews(...)` (news feed). String literals,
     `..` concatenations and string.format become templates with {param} placeholders.
  2. Python protocol errors (server/sos/server.py): `"message": "..."`, `"error": "..."`.
  3. Data modules (shared-luau/Data/*): texts that are sent whole (event texts, tech descriptions, goal titles...)
     → `data.<module>.<id>.<field>`; review sentences → `review.*` (ReviewGenerator sets these keys itself).
  4. server/locale/manual.json: hand-written keys (they win over generated ones for the same English text).
Keys are derived from the English text (slug), so they stay stable while the text stays the same.
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.dirname(HERE)
ROOT = os.path.dirname(SERVER)
sys.path.insert(0, SERVER)

CATALOG = os.path.join(SERVER, "locale", "catalog.json")
MANUAL = os.path.join(SERVER, "locale", "manual.json")
DOC = os.path.join(ROOT, "docs", "LOCALE_KEYS.md")

LUA_KEYWORDS = {"and", "or", "not", "nil", "true", "false", "function", "end", "local", "return", "if", "then", "else"}
NOISE_IDENTS = {"tostring", "tonumber", "string", "format", "math", "floor", "ceil", "abs", "max", "min", "Format",
                "money", "round", "upper", "lower", "sub", "rep", "c", "s", "state", "self", "def", "p", "cost",
                "MathUtil", "TableUtil", "Enums", "table", "concat", "e6", "e9"}
SPEC_RE = re.compile(r"%(?:%|[-+ #0]*\d*(?:\.\d+)?[sdfgiqxXeEc])")


# ---------------------------------------------------------------------------------------------------------------
# Lua scanning
# ---------------------------------------------------------------------------------------------------------------
def strip_comments(src):
    out, i, n = [], 0, len(src)
    while i < n:
        ch = src[i]
        if ch in "\"'":
            j = i + 1
            while j < n and src[j] != ch:
                j += 2 if src[j] == "\\" else 1
            out.append(src[i:j + 1])
            i = j + 1
        elif src.startswith("--[[", i):
            j = src.find("]]", i)
            i = n if j < 0 else j + 2
        elif src.startswith("--", i):
            j = src.find("\n", i)
            i = n if j < 0 else j
        else:
            out.append(ch)
            i += 1
    return "".join(out)


def tokenize(expr):
    """Very small Lua tokenizer: strings, names, numbers, '..', brackets and single-char operators."""
    toks, i, n = [], 0, len(expr)
    while i < n:
        ch = expr[i]
        if ch.isspace():
            i += 1
        elif ch in "\"'":
            j, buf = i + 1, []
            while j < n and expr[j] != ch:
                if expr[j] == "\\" and j + 1 < n:
                    buf.append({"n": "\n", "t": "\t"}.get(expr[j + 1], expr[j + 1]))
                    j += 2
                else:
                    buf.append(expr[j])
                    j += 1
            toks.append(("str", "".join(buf)))
            i = j + 1
        elif expr.startswith("..", i):
            toks.append(("cat", ".."))
            i += 2
        elif ch.isalpha() or ch == "_":
            j = i
            while j < n and (expr[j].isalnum() or expr[j] == "_"):
                j += 1
            word = expr[i:j]
            toks.append(("kw" if word in LUA_KEYWORDS else "name", word))
            i = j
        elif ch.isdigit():
            j = i
            while j < n and (expr[j].isalnum() or expr[j] == "."):
                j += 1
            toks.append(("num", expr[i:j]))
            i = j
        else:
            toks.append(("op", ch))
            i += 1
    return toks


def read_expr(src, i, stop_newline=True):
    """Returns (expr_text, end) from src[i]: stops at a top-level ',', ')', '}' or (optionally) a newline."""
    depth, j, n = 0, i, len(src)
    while j < n:
        ch = src[j]
        if ch in "\"'":
            k = j + 1
            while k < n and src[k] != ch:
                k += 2 if src[k] == "\\" else 1
            j = k + 1
            continue
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            if depth == 0:
                break
            depth -= 1
        elif ch == "," and depth == 0:
            break
        elif ch == "\n" and depth == 0 and stop_newline:
            break
        j += 1
    return src[i:j].strip(), j


def read_args(src, i):
    """src[i] is just after '('. Returns the list of argument expressions."""
    args = []
    while True:
        expr, j = read_expr(src, i, stop_newline=False)
        args.append(expr)
        if j >= len(src) or src[j] != ",":
            return args
        i = j + 1


def split_top(toks, sep_kind, sep_val=None):
    parts, cur, depth = [], [], 0
    for t in toks:
        if t[0] == "op" and t[1] in "([{":
            depth += 1
        elif t[0] == "op" and t[1] in ")]}":
            depth -= 1
        if depth == 0 and t[0] == sep_kind and (sep_val is None or t[1] in sep_val):
            parts.append(cur)
            cur = []
        else:
            cur.append(t)
    parts.append(cur)
    return parts


def param_name(toks):
    # identifiers outside [index] brackets; a call names the param after the function (finishNowCost(x) -> cost)
    flat, depth = [], 0
    for idx, t in enumerate(toks):
        if t == ("op", "["):
            depth += 1
        elif t == ("op", "]"):
            depth -= 1
        elif depth == 0:
            flat.append(t)
    toks = flat
    for idx in range(len(toks) - 1):
        if toks[idx][0] == "name" and toks[idx + 1] == ("op", "(") and toks[idx][1] not in NOISE_IDENTS:
            m = re.search(r"(Cost|Price|Name|Days|Level|Count)$", toks[idx][1])
            if m:
                return m.group(1).lower()
    idents = [t[1] for t in toks if t[0] == "name" and t[1] not in NOISE_IDENTS]
    if not idents:
        idents = [t[1] for t in toks if t[0] == "name"]
    if not idents:
        return "value"
    for pref in ("name", "title", "days", "level"):
        if pref in idents:
            return pref
    return idents[-1]


def join_toks(toks):
    out = []
    for kind, val in toks:
        out.append(json.dumps(val) if kind == "str" else val)
    return " ".join(out)


def is_format_call(toks):
    return (len(toks) >= 4 and toks[0] == ("name", "string") and toks[1] == ("op", ".") and toks[2] == ("name", "format")
            and toks[3] == ("op", "("))


def format_template(toks):
    """toks = string.format( ... ) → template or None."""
    inner = toks[4:-1] if toks and toks[-1] == ("op", ")") else toks[4:]
    args = split_top(inner, "op", ",")
    if not args or len(args[0]) != 1 or args[0][0][0] != "str":
        return None
    fmt = args[0][0][1]
    rest = args[1:]
    out, k, pos = [], 0, 0
    for m in SPEC_RE.finditer(fmt):
        out.append(fmt[pos:m.start()])
        if m.group(0) == "%%":
            out.append("%")
        else:
            arg = rest[k] if k < len(rest) else []
            k += 1
            sub = expr_templates_from_toks(arg) if arg else []
            if len(sub) == 1 and "{" not in sub[0] and arg and arg[0][0] == "str":
                out.append(sub[0])  # a literal argument is part of the text
            else:
                out.append("{%s}" % param_name(arg))
        pos = m.end()
    out.append(fmt[pos:])
    return "".join(out)


def expr_templates_from_toks(toks):
    """Returns a list of templates for one Lua expression (several for `cond and "a" or "b"`)."""
    if not toks:
        return []
    # a and/or chain at top level: each operand that is text becomes its own template
    alts = split_top(toks, "kw", ("and", "or"))
    if len(alts) > 1:
        out = []
        for a in alts:
            if any(t[0] == "op" and t[1] in "=~<>" for t in a):
                continue
            out.extend(expr_templates_from_toks(a))
        return out
    # strip one level of wrapping parentheses
    if toks[0] == ("op", "(") and toks[-1] == ("op", ")"):
        depth, wrapped = 0, True
        for idx, t in enumerate(toks):
            if t == ("op", "("):
                depth += 1
            elif t == ("op", ")"):
                depth -= 1
                if depth == 0 and idx != len(toks) - 1:
                    wrapped = False
                    break
        if wrapped:
            return expr_templates_from_toks(toks[1:-1])
    parts = split_top(toks, "cat")
    pieces, has_text, names = [], False, {}
    for part in parts:
        if len(part) == 1 and part[0][0] == "str":
            pieces.append(part[0][1])
            has_text = has_text or bool(part[0][1].strip())
        elif is_format_call(part):
            t = format_template(part)
            if t is None:
                pieces.append("{%s}" % param_name(part))
            else:
                pieces.append(t)
                has_text = has_text or bool(re.sub(r"\{\w+\}", "", t).strip())
        else:
            sub = expr_templates_from_toks(part) if (part and part[0] == ("op", "(")) else []
            if len(sub) == 1 and len(parts) > 1 and "{" not in sub[0]:
                pieces.append("{%s}" % param_name(part))
            else:
                pieces.append("{%s}" % param_name(part))
    if not has_text:
        return []
    return [dedupe_params("".join(pieces))]


def dedupe_params(t):
    seen = {}

    def rep(m):
        name = m.group(1)
        seen[name] = seen.get(name, 0) + 1
        return "{%s}" % (name if seen[name] == 1 else "%s%d" % (name, seen[name]))
    return re.sub(r"\{(\w+)\}", rep, t)


def lua_sites(path):
    src = strip_comments(open(path, encoding="utf-8").read())
    found = []  # (category, template)

    def add(cat, expr):
        for t in expr_templates_from_toks(tokenize(expr)):
            found.append((cat, t))

    for m in re.finditer(r"\bfail\(", src):
        add("err", read_args(src, m.end())[0])
    for m in re.finditer(r"\breturn\s+false\s*,\s*", src):
        expr, _ = read_expr(src, m.end())
        add("err", expr)
    for m in re.finditer(r"(?<![\w.])(title|body|detail)\s*=(?!=)\s*", src):
        expr, _ = read_expr(src, m.end())
        add("news" if m.group(1) == "detail" else "note", expr)
    for m in re.finditer(r"(\bCompanySim\.)?\baddNews\(", src):
        args = read_args(src, m.end())
        if m.group(1):
            pick = args[2:4]
        elif len(args) == 2:
            pick = args[:2]
        else:
            pick = []
        for a in pick:
            add("news", a)
    return found


def py_sites(path):
    src = open(path, encoding="utf-8").read()
    out = []
    for m in re.finditer(r'"(?:message|error)":\s*"((?:[^"\\]|\\.)*)"(\s*[%+])?', src):
        if not m.group(2):  # formatted / concatenated messages are in manual.json
            out.append(("err", m.group(1)))
    return out


# ---------------------------------------------------------------------------------------------------------------
# Data modules (through the server's Lua VM)
# ---------------------------------------------------------------------------------------------------------------
DATA_SKIP = {"ComponentCatalog", "Names", "Competitors", "ReviewTemplates", "DeviceSpecs", "Segments", "Finishes"}
DATA_FIELDS = ("name", "title", "text", "description", "desc", "effect", "detail")


def data_entries():
    from sos.lua_host import LuaHost
    from sos.convert import lua_to_py
    lua = LuaHost()
    out = []

    def req(path):
        return lua_to_py(lua.L.execute('return require(game:GetService("ReplicatedStorage").Shared.%s)' % path))

    def walk(module, node, seen_ids):
        if isinstance(node, dict):
            ident = node.get("id")
            if isinstance(ident, str):
                for f in DATA_FIELDS:
                    v = node.get(f)
                    if isinstance(v, str) and v.strip() and (module, ident, f) not in seen_ids:
                        seen_ids.add((module, ident, f))
                        out.append(("data.%s.%s.%s" % (module.lower(), ident, f), v))
            for k in sorted(node, key=str):  # Lua hash order differs between runs
                walk(module, node[k], seen_ids)
        elif isinstance(node, list):
            for v in node:
                walk(module, v, seen_ids)

    data_dir = os.path.join(ROOT, "shared-luau", "Data")
    for fn in sorted(os.listdir(data_dir)):
        mod = fn[:-5]
        if not fn.endswith(".luau") or mod in DATA_SKIP:
            continue
        walk(mod, req("Data." + mod), set())
    # milestones (Progression) and HQ levels (Enums)
    prog = req("Domain.Progression")
    for m in prog.get("milestones") or []:
        out.append(("data.milestone.%s.name" % m["id"], m["name"]))
    for i, name in enumerate(req("Enums.Enums").get("HQLevels") or [], start=1):
        out.append(("data.hqlevel.%d" % i, name))
    # reviews: keys set by ReviewGenerator
    rt = req("Data.ReviewTemplates")
    for fid in sorted(rt["findings"]):
        out.append(("review.finding.%s" % fid, rt["findings"][fid]["text"]))
    for kind in ("Hardcore", "Consumer", "Financial"):
        for tier in ("great", "good", "mixed", "bad"):
            out.append(("review.headline.%s.%s" % (kind, tier), rt["headlines"][kind][tier]))
    out.append(("review.fallback.financial", "A competent product with unremarkable unit economics."))
    out.append(("review.fallback.device", "A competent, if unremarkable, device."))
    return out


# ---------------------------------------------------------------------------------------------------------------
def slug(cat, template):
    text = re.sub(r"\{(\w+)\}", lambda m: " " + m.group(1) + " ", template)
    text = re.sub(r"[^A-Za-z0-9]+", "_", text).strip("_").lower()
    words = [w for w in text.split("_") if w]
    out = ""
    for w in words:
        if len(out) + len(w) + 1 > 48:
            break
        out = w if not out else out + "_" + w
    return "%s.%s" % (cat, out or "text")


def build():
    entries = {}   # en -> {key, group}
    keys = {}      # key -> en
    manual = json.load(open(MANUAL, encoding="utf-8")) if os.path.exists(MANUAL) else []
    for m in manual:
        entries[m["en"]] = {"key": m["key"], "en": m["en"], "group": m.get("group", m["key"].split(".")[0])}
        keys[m["key"]] = m["en"]

    shapes = {}  # template with anonymous placeholders -> en (one key per runtime pattern)

    def shape(en):
        return re.sub(r"\{\w+\}", "{}", en)
    for e in entries.values():
        shapes[shape(e["en"])] = e["en"]

    def put(key, en, group):
        if en in entries or shape(en) in shapes:
            return
        shapes[shape(en)] = en
        base, k, n = key, key, 2
        while k in keys and keys[k] != en:
            k = "%s_%d" % (base, n)
            n += 1
        keys[k] = en
        entries[en] = {"key": k, "en": en, "group": group}

    sites = []
    for base in (os.path.join(ROOT, "shared-luau"), os.path.join(SERVER, "lua")):
        for dp, _, files in os.walk(base):
            for fn in sorted(files):
                if fn.endswith(".luau"):
                    sites.extend(lua_sites(os.path.join(dp, fn)))
    sites.extend(py_sites(os.path.join(SERVER, "sos", "server.py")))
    for cat, t in sites:
        literal = re.sub(r"\{\w+\}", "", t)
        if len(re.sub(r"[^A-Za-z]", "", literal)) < 2:
            continue  # no real text (ids, single symbols, pure placeholders)
        if t in ("CEO", "CTO", "0 / 1") or re.fullmatch(r"[a-z]+", t) or re.search(r"[\u0400-\u04FF]", t):
            continue  # owner titles, internal ids, Russian texts of the Roblox client tutorial (never sent)
        put(slug(cat, t), t, cat)
    for key, en in data_entries():
        put(key, en, "data" if key.startswith("data.") else "review")
    order = {"err": 0, "note": 1, "news": 2, "review": 3, "data": 4}
    out = sorted(entries.values(), key=lambda e: (order.get(e["group"], 9), e["key"]))
    return out


GROUP_TITLES = {
    "err": "Errors (`res.errorKey`, `error.key`)",
    "note": "Notifications (`notify.key` / `notify.bodyKey`)",
    "news": "News feed (`news[].key` / `news[].bodyKey`)",
    "review": "Launch reviews (`headlineKey`, `bodyParts[].key`)",
    "data": "Data texts (sent whole as a title/body, or as a param — see `paramKeys`)",
}

DOC_HEAD = """# Server text keys (localization)

GENERATED by `python3 server/tools/gen_locale.py` from the server sources — do not edit by hand
(hand-written keys live in server/locale/manual.json).

## How it works
Everything the server writes in English (notifications, errors, news, launch reviews) also carries a stable **key**
plus **params**. The client looks the key up in its own translation table and fills the `{param}` placeholders; if
the key is missing/unknown (or `null`), it shows the English text that is always sent too.

| where | English (fallback) | key / params |
|---|---|---|
| `notify` frame | `title`, `body` | `key` + `params` (title), `bodyKey` + `bodyParams` (body) |
| failed `res` frame | `error` | `errorKey` + `errorParams` |
| `error` frame | `message` | `key` + `params` |
| `state.news[]` | `title`, `body` | `key` + `params` (title), `bodyKey` + `bodyParams` (body); a launch review's news item has `bodyParts` instead of `bodyKey` |
| `products[id].reviews[]` (also in `launchProduct` data) | `headline`, `body` | `headlineKey` + `headlineParams`, `bodyParts: [{key, params}]` (the body is the parts joined with one space) |

- Params are JSON strings or numbers. Numbers are raw (e.g. `350000`, `12.5`): format them yourself (money, %).
  The template shows where the server put them, e.g. `Not enough cash (${cost})`.
- Some params are names of things that come from game data or from players (product / company / tech / room / goal
  names). When a param is a known data text, the frame also has `paramKeys` / `bodyParamKeys` / `errorParamKeys`
  = `{param: key}` (e.g. `{"name": "data.techtree.arch_arm_2.name"}`) so you can translate the name too; otherwise
  show the value as it is.
- A text can be a data text sent whole (e.g. an event's description as a news body): then its key is a `data.*` key.
- Keys never change meaning. New keys may appear; unknown keys → use the English text. Texts with no key → English.
- Prefixes: `err.*` action / protocol errors, `note.*` notifications, `news.*` news feed, `review.*` launch reviews,
  `data.*` game data texts. The same English text has one key everywhere (an error text reused in a notification
  keeps its `err.` key).
- Server-side extraction is automatic; a few texts are assembled in ways the extractor cannot see and arrive with
  `key: null` — show the English text.
"""


def render_doc(entries):
    lines = [DOC_HEAD]
    by = {}
    for e in entries:
        by.setdefault(e["group"], []).append(e)
    lines.append("## Keys (%d)\n" % len(entries))
    for g in ("err", "note", "news", "review", "data"):
        if g not in by:
            continue
        lines.append("### %s — %d\n" % (GROUP_TITLES[g], len(by[g])))
        lines.append("| key | English template |")
        lines.append("|---|---|")
        for e in by[g]:
            lines.append("| %s | %s |" % (e["key"], e["en"].replace("|", "\\|").replace("\n", " ")))
        lines.append("")
    return "\n".join(lines)


def main():
    entries = build()
    cat_text = json.dumps([{"key": e["key"], "en": e["en"], "group": e["group"]} for e in entries],
                          ensure_ascii=False, indent=1) + "\n"
    doc_text = render_doc(entries)
    if "--check" in sys.argv:
        ok = (os.path.exists(CATALOG) and open(CATALOG, encoding="utf-8").read() == cat_text
              and os.path.exists(DOC) and open(DOC, encoding="utf-8").read() == doc_text)
        print("locale catalog up to date" if ok else "locale catalog OUT OF DATE: run server/tools/gen_locale.py")
        sys.exit(0 if ok else 1)
    os.makedirs(os.path.dirname(CATALOG), exist_ok=True)
    with open(CATALOG, "w", encoding="utf-8") as f:
        f.write(cat_text)
    with open(DOC, "w", encoding="utf-8") as f:
        f.write(doc_text)
    print("%d keys -> %s, %s" % (len(entries), CATALOG, DOC))


if __name__ == "__main__":
    main()
