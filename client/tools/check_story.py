#!/usr/bin/env python3
"""Checks the story texts in client/ui/data/story/<lang>.json (schema: docs/STORY_SCRIPT.md).

- every file is valid JSON with the documented structure;
- every language has exactly the ids and non-text fields of en.json (steps, lines, speakers, customers, cutscenes...);
- every text keeps the placeholders of its English original ({company}, {player}, {money}, {n});
- lengths: objective <= 60, line / caption / hint / tip / customer line <= 140, fault <= 80, title <= 40, subtitle <= 80;
- line ids are unique and well-formed, speakers exist, step ids are unique;
- fonts (when fontTools is installed): every character is in Inter or the bundled CJK subsets (zh -> SC, ja -> JP);
- step ids are compared with docs/ACTIONS.md "Story & repairs" when that section exists (warning; --strict = error).

Usage: python3 client/tools/check_story.py [--strict]      exit code 0 = all good
"""
import json
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
STORY = os.path.join(ROOT, "client", "ui", "data", "story")
FONTS = os.path.join(ROOT, "client", "ui", "fonts")
ACTIONS = os.path.join(ROOT, "docs", "ACTIONS.md")
LANGS = ["en", "ru", "uk", "de", "es", "pt", "fr", "pl", "tr", "zh", "ja"]
PLACEHOLDERS = {"company", "player", "money", "n"}
LIMITS = {"objective": 60, "hint": 140, "line": 140, "caption": 140, "tip": 140, "cust_line": 140,
          "fault": 80, "title": 40, "subtitle": 80, "device": 80, "name": 40}
CUSTOMER_LINES = ["arrive", "story", "wait", "happy", "angry"]
PARTS = {"screen", "battery", "port"}
PH_RE = re.compile(r"\{([A-Za-z_]+)\}")

errors = []
warnings = []


def err(msg):
    errors.append(msg)


def warn(msg):
    warnings.append(msg)


def walk_texts(doc):
    """Yields (path, kind, text) for every translatable string, in a stable order."""
    for sid, sp in sorted(doc.get("speakers", {}).items()):
        yield f"speakers.{sid}.name", "name", sp.get("name", "")
    for ch in doc.get("chapters", []):
        cid = ch.get("id")
        yield f"chapters[{cid}].title", "title", ch.get("title", "")
        yield f"chapters[{cid}].subtitle", "subtitle", ch.get("subtitle", "")
        for st in ch.get("steps", []):
            sid = st.get("id")
            yield f"step {sid}.objective", "objective", st.get("objective", "")
            yield f"step {sid}.hint", "hint", st.get("hint", "")
            for ln in st.get("lines", []):
                yield ln.get("id", "?"), "line", ln.get("text", "")
    for c in doc.get("customers", []):
        cid = c.get("id")
        yield f"customer {cid}.name", "name", c.get("name", "")
        yield f"customer {cid}.device", "device", c.get("device", "")
        yield f"customer {cid}.fault", "fault", c.get("fault", "")
        for k in CUSTOMER_LINES:
            yield f"cust.{cid}.{k}", "cust_line", c.get("lines", {}).get(k, "")
    for group in ["devices", "parts"]:
        for k, v in sorted(doc.get(group, {}).items()):
            yield f"{group}.{k}", "name", v
    for k, v in sorted(doc.get("faults", {}).items()):
        yield f"faults.{k}.name", "name", v.get("name", "") if isinstance(v, dict) else v
        yield f"fault.{k}.story", "cust_line", v.get("story", "") if isinstance(v, dict) else ""
    for cut, data in sorted(doc.get("cutscenes", {}).items()):
        for cap in data.get("captions", []):
            yield cap.get("id", "?"), "caption", cap.get("text", "")
    for i, tip in enumerate(doc.get("tips", [])):
        yield f"tips[{i}]", "tip", tip
    cr = doc.get("credits", {})
    yield "credits.title", "title", cr.get("title", "")
    for sec in cr.get("sections", []):
        yield f"credits.{sec.get('id')}.heading", "title", sec.get("heading", "")
        for i, line in enumerate(sec.get("lines", [])):
            yield f"credits.{sec.get('id')}.lines[{i}]", "line", line
    yield "credits.closing", "line", cr.get("closing", "")
    for k, v in sorted(doc.get("ui", {}).items()):
        yield f"ui.{k}", "line", v


def skeleton(doc):
    """Everything except the texts: must be identical in every language."""
    sk = {"speakers": {k: v.get("voice") for k, v in doc.get("speakers", {}).items()}}
    sk["chapters"] = [{"id": c.get("id"), "key": c.get("key"),
                       "steps": [{"id": s.get("id"), "optional": s.get("optional"),
                                  "lines": [(ln.get("id"), ln.get("speaker")) for ln in s.get("lines", [])]}
                                 for s in c.get("steps", [])]} for c in doc.get("chapters", [])]
    sk["customers"] = [(c.get("id"), c.get("voice"), c.get("deviceId"), c.get("faultId"),
                        sorted(c.get("lines", {}).keys())) for c in doc.get("customers", [])]
    for g in ["devices", "parts", "ui"]:
        sk[g] = sorted(doc.get(g, {}).keys())
    sk["faults"] = sorted((k, v.get("part") if isinstance(v, dict) else None) for k, v in doc.get("faults", {}).items())
    sk["cutscenes"] = {k: [(c.get("id"), c.get("speaker")) for c in v.get("captions", [])]
                       for k, v in doc.get("cutscenes", {}).items()}
    sk["tips"] = len(doc.get("tips", []))
    cr = doc.get("credits", {})
    sk["credits"] = [(s.get("id"), len(s.get("lines", []))) for s in cr.get("sections", [])]
    return sk


def check_structure(lang, doc):
    for key in ["lang", "version", "speakers", "chapters", "customers", "devices", "faults", "parts", "cutscenes",
                "tips", "credits", "ui"]:
        if key not in doc:
            err(f"{lang}: missing top-level key '{key}'")
    if doc.get("lang") != lang:
        err(f"{lang}: \"lang\" is {doc.get('lang')!r}")
    speakers = set(doc.get("speakers", {}).keys())
    line_ids, step_ids = set(), set()

    def add_line(lid, speaker, where):
        if lid in line_ids:
            err(f"{lang}: duplicate line id {lid}")
        line_ids.add(lid)
        if speaker not in speakers:
            err(f"{lang}: {lid}: unknown speaker {speaker!r} ({where})")

    for i, ch in enumerate(doc.get("chapters", [])):
        if ch.get("id") != i:
            err(f"{lang}: chapters[{i}].id is {ch.get('id')!r}, expected {i}")
        if not ch.get("steps"):
            err(f"{lang}: chapter {i} has no steps")
        for st in ch.get("steps", []):
            sid = st.get("id")
            if not isinstance(sid, str) or not re.fullmatch(r"[a-z0-9_]+", sid or ""):
                err(f"{lang}: bad step id {sid!r}")
            if sid in step_ids:
                err(f"{lang}: duplicate step id {sid}")
            step_ids.add(sid)
            if len(st.get("lines", [])) > 3:
                err(f"{lang}: step {sid} has more than 3 lines")
            for n, ln in enumerate(st.get("lines", []), 1):
                if ln.get("id") != f"step.{sid}.{n}":
                    err(f"{lang}: step {sid}: line id {ln.get('id')!r}, expected step.{sid}.{n}")
                add_line(ln.get("id"), ln.get("speaker"), f"step {sid}")
    cust_ids = set()
    for c in doc.get("customers", []):
        cid = c.get("id")
        if cid in cust_ids:
            err(f"{lang}: duplicate customer {cid}")
        cust_ids.add(cid)
        if c.get("deviceId") not in doc.get("devices", {}):
            err(f"{lang}: customer {cid}: deviceId {c.get('deviceId')!r} not in devices")
        if c.get("faultId") not in doc.get("faults", {}):
            err(f"{lang}: customer {cid}: faultId {c.get('faultId')!r} not in faults")
        if not isinstance(c.get("voice"), int):
            err(f"{lang}: customer {cid}: voice must be an int")
        if sorted(c.get("lines", {}).keys()) != sorted(CUSTOMER_LINES):
            err(f"{lang}: customer {cid}: lines must be exactly {CUSTOMER_LINES}")
    for fid, f in doc.get("faults", {}).items():
        if not isinstance(f, dict) or not {"name", "part", "story"} <= set(f.keys()):
            err(f"{lang}: faults.{fid} must be {{name, part, story}}")
        elif f.get("part") is not None and (f["part"] not in PARTS or f["part"] not in doc.get("parts", {})):
            err(f"{lang}: faults.{fid}: unknown part {f.get('part')!r}")
    if len(cust_ids) < 10:
        err(f"{lang}: only {len(cust_ids)} customers (need 10+)")
    for cut in ["intro", "investor", "sign_swap"]:
        caps = doc.get("cutscenes", {}).get(cut, {}).get("captions")
        if not caps:
            err(f"{lang}: cutscene {cut} has no captions")
            continue
        for n, cap in enumerate(caps, 1):
            if cap.get("id") != f"cut.{cut}.{n}":
                err(f"{lang}: cutscene {cut}: caption id {cap.get('id')!r}, expected cut.{cut}.{n}")
            add_line(cap.get("id"), cap.get("speaker"), f"cutscene {cut}")
    if len(doc.get("tips", [])) < 20:
        err(f"{lang}: only {len(doc.get('tips', []))} tips (need 20+)")
    for sid, sp in doc.get("speakers", {}).items():
        if not isinstance(sp.get("voice"), int):
            err(f"{lang}: speaker {sid}: voice must be an int")
    return step_ids


def check_texts(lang, doc, en_texts):
    texts = list(walk_texts(doc))
    for path, kind, text in texts:
        if not isinstance(text, str):
            err(f"{lang}: {path}: not a string")
            continue
        en = en_texts.get(path)
        if text.strip() == "" and en not in (None, ""):
            err(f"{lang}: {path}: empty (English has text)")
        if text != text.strip():
            err(f"{lang}: {path}: leading/trailing spaces")
        if "  " in text or "\n" in text:
            err(f"{lang}: {path}: double space or line break")
        limit = LIMITS.get(kind)
        if limit and len(text) > limit:
            err(f"{lang}: {path}: {len(text)} chars > {limit}: {text}")
        ph = set(PH_RE.findall(text))
        unknown = ph - PLACEHOLDERS
        if unknown:
            err(f"{lang}: {path}: unknown placeholder(s) {sorted(unknown)}")
        if en is not None and ph != set(PH_RE.findall(en)):
            err(f"{lang}: {path}: placeholders {sorted(ph)} differ from English {sorted(set(PH_RE.findall(en)))}")
        if text.count("{") != text.count("}"):
            err(f"{lang}: {path}: unbalanced braces")
    return texts


def load_cmap(name):
    try:
        from fontTools.ttLib import TTFont
    except ImportError:
        return None
    path = os.path.join(FONTS, name)
    if not os.path.exists(path):
        return None
    return set(TTFont(path, lazy=True).getBestCmap().keys())


def check_fonts(per_lang):
    inter = load_cmap("Inter-Medium.ttf")
    sc = load_cmap("NotoSansSC-Medium.otf")
    jp = load_cmap("NotoSansJP-Medium.otf")
    if inter is None or sc is None or jp is None:
        warn("fontTools or fonts missing: glyph coverage not checked")
        return
    for lang, texts in per_lang.items():
        own = sc if lang == "zh" else jp if lang == "ja" else set()
        other = jp if lang == "zh" else sc
        bad, foreign = {}, {}
        for path, _kind, text in texts:
            for ch in text:
                cp = ord(ch)
                if cp in inter or cp in own or ch.isspace():
                    continue
                if cp in other:
                    foreign.setdefault(ch, path)
                else:
                    bad.setdefault(ch, path)
        for ch, path in sorted(bad.items()):
            err(f"{lang}: {path}: character {ch!r} (U+{ord(ch):04X}) is in no bundled font")
        for ch, path in sorted(foreign.items()):
            warn(f"{lang}: {path}: character {ch!r} only in the other CJK font (wrong glyph style)")


def server_step_ids():
    """Backticked ids from docs/ACTIONS.md section 'Story & repairs' (empty if the section does not exist)."""
    if not os.path.exists(ACTIONS):
        return None
    text = open(ACTIONS, encoding="utf-8").read()
    m = re.search(r"^##+\s*Story & repairs.*?$(.*?)(?=^## |\Z)", text, re.M | re.S)
    if not m:
        return None
    return set(re.findall(r"`([a-z][a-z0-9_]*)`", m.group(1)))


def main():
    strict = "--strict" in sys.argv
    docs = {}
    for lang in LANGS:
        path = os.path.join(STORY, lang + ".json")
        if not os.path.exists(path):
            err(f"{lang}: file missing ({path})")
            continue
        try:
            docs[lang] = json.load(open(path, encoding="utf-8"))
        except json.JSONDecodeError as e:
            err(f"{lang}: invalid JSON: {e}")
    extra = sorted(f for f in os.listdir(STORY) if f.endswith(".json") and f[:-5] not in LANGS) \
        if os.path.isdir(STORY) else []
    for f in extra:
        warn(f"unexpected file {f} (languages are {' '.join(LANGS)}; pt = Brazilian Portuguese)")
    if "en" not in docs:
        report()
        return
    en = docs["en"]
    en_texts = {p: t for p, _k, t in walk_texts(en)}
    en_skel = skeleton(en)
    per_lang = {}
    step_ids = set()
    for lang, doc in docs.items():
        ids = check_structure(lang, doc)
        if lang == "en":
            step_ids = ids
        per_lang[lang] = check_texts(lang, doc, en_texts)
        sk = skeleton(doc)
        for key in en_skel:
            if sk.get(key) != en_skel[key]:
                err(f"{lang}: ids/structure of '{key}' differ from en.json")
        paths = {p for p, _k, _t in per_lang[lang]}
        for p in en_texts:
            if p not in paths:
                err(f"{lang}: missing {p}")
    check_fonts(per_lang)
    server = server_step_ids()
    if server is None:
        warn("docs/ACTIONS.md has no 'Story & repairs' section yet: step ids not compared with the server")
    else:
        missing = sorted(step_ids - server)
        if missing:
            (err if strict else warn)(f"step ids not mentioned in ACTIONS.md 'Story & repairs': {missing}")
    report(len(docs), sum(len(v) for v in per_lang.values()))


def report(files=0, strings=0):
    for w in warnings:
        print("WARN ", w)
    for e in errors:
        print("ERROR", e)
    if errors:
        print(f"check_story: {len(errors)} error(s)")
        sys.exit(1)
    print(f"check_story: OK ({files} languages, {strings} strings, {len(warnings)} warning(s))")


if __name__ == "__main__":
    main()
