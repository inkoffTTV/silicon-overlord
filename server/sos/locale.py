"""Localization keys for server-generated English texts (docs/LOCALE_KEYS.md).

The catalog (server/locale/catalog.json, built by server/tools/gen_locale.py) lists `key -> English template` with
`{param}` placeholders. `Locale.tag(text)` finds the template that produced a text and returns (key, params); the
server adds them next to the English text in notify / res / error frames and news items, so the client can
translate. Results are cached (texts repeat a lot: news lists are re-sent with every news change).
"""
import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
CATALOG = os.path.join(os.path.dirname(HERE), "locale", "catalog.json")

PARAM_RE = re.compile(r"\{(\w+)\}")
NUM_RE = re.compile(r"-?\d+(\.\d+)?")
CACHE_MAX = 20000


def _number(v):
    if NUM_RE.fullmatch(v):
        f = float(v)
        return int(f) if f.is_integer() and "." not in v else f
    return v


class Locale:
    def __init__(self, path=CATALOG):
        with open(path, encoding="utf-8") as f:
            entries = json.load(f)
        self.exact = {}        # text without placeholders -> key
        self.patterns = []     # (regex, key, param names), most specific first
        self.name_keys = {}    # data names/titles -> key (for paramKeys)
        for e in entries:
            key, en = e["key"], e["en"]
            names = PARAM_RE.findall(en)
            if not names:
                self.exact.setdefault(en, key)
                if key.startswith("data."):
                    self.name_keys.setdefault(en, key)
                continue
            parts = PARAM_RE.split(en)  # literal, name, literal, name, ...
            rx = "".join(re.escape(p) if i % 2 == 0 else "(.*?)" for i, p in enumerate(parts))
            literal = len(PARAM_RE.sub("", en))
            self.patterns.append((literal, re.compile("^" + rx + "$", re.S), key, names))
        self.patterns.sort(key=lambda p: -p[0])
        self.cache = {}

    def tag(self, text):
        """Returns (key, params, paramKeys) for an English text; (None, None, None) when unknown."""
        if not isinstance(text, str) or not text:
            return None, None, None
        hit = self.cache.get(text)
        if hit is not None:
            return hit
        res = (None, None, None)
        key = self.exact.get(text)
        if key is not None:
            res = (key, {}, None)
        else:
            for _, rx, k, names in self.patterns:
                m = rx.match(text)
                if m:
                    params = {n: _number(v) for n, v in zip(names, m.groups())}
                    pk = {n: self.name_keys[v] for n, v in params.items() if isinstance(v, str) and v in self.name_keys}
                    res = (k, params, pk or None)
                    break
        if len(self.cache) > CACHE_MAX:
            self.cache.clear()
        self.cache[text] = res
        return res

    # ---- frame helpers -------------------------------------------------------------------------------------
    def add(self, obj, text, key_field, params_field, pk_field):
        """Sets obj[key_field]/obj[params_field] (and obj[pk_field] when names were found) unless already set."""
        if obj.get(key_field):
            return
        key, params, pk = self.tag(text)
        obj[key_field] = key
        obj[params_field] = params if key else None
        if pk:
            obj[pk_field] = pk

    def notify(self, frame, note):
        """notify frame: key/params for the title, bodyKey/bodyParams for the body (Lua may preset them)."""
        for src, dst in (("key", "key"), ("params", "params"), ("bodyKey", "bodyKey"), ("bodyParams", "bodyParams")):
            if note.get(src) is not None:
                frame[dst] = note[src]
        self.add(frame, frame.get("title"), "key", "params", "paramKeys")
        self.add(frame, frame.get("body"), "bodyKey", "bodyParams", "bodyParamKeys")
        return frame

    def news(self, items):
        """state.news entries (dicts, modified in place)."""
        if not isinstance(items, list):
            return items
        for it in items:
            if isinstance(it, dict):
                self.add(it, it.get("title"), "key", "params", "paramKeys")
                if not it.get("bodyParts"):
                    self.add(it, it.get("body"), "bodyKey", "bodyParams", "bodyParamKeys")
        return items

    def state(self, data):
        """A snapshot state or a sections payload: tags the news list."""
        if isinstance(data, dict) and isinstance(data.get("news"), list):
            self.news(data["news"])
        return data

    def outgoing(self, obj):
        """res (failed) and error frames, tagged right before sending."""
        t = obj.get("t")
        if t == "res" and obj.get("ok") is False and "errorKey" not in obj:
            key, params, pk = self.tag(obj.get("error"))
            obj["errorKey"] = key
            obj["errorParams"] = params if key else None
            if pk:
                obj["errorParamKeys"] = pk
        elif t == "error" and "key" not in obj:
            key, params, pk = self.tag(obj.get("message"))
            obj["key"] = key
            obj["params"] = params if key else None
            if pk:
                obj["paramKeys"] = pk
        return obj
