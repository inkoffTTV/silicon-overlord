"""Lua <-> JSON-able Python conversion.

Rules (documented in docs/PROTOCOL.md, "Lua tables in JSON"):
  * Lua table whose keys are exactly 1..n (n >= 1)  -> JSON array
  * any other non-empty table                        -> JSON object, keys converted to strings
                                                        (integer 5 -> "5", float 2.0 -> "2", true -> "true")
  * EMPTY table                                      -> {}  (Lua cannot tell an empty list from an empty map;
                                                        clients must accept both [] and {} as "empty collection")
  * integral floats -> JSON integers; NaN -> 0; +-inf -> +-1.7976931348623157e308 (JSON has no NaN/inf)
  * functions / userdata / threads are dropped (object members) or become null (array items)

JSON -> Lua (py_to_lua): objects -> tables with STRING keys (as in Roblox DataStore JSON), arrays -> 1-based
sequences, null -> nil (object members are omitted; array items leave a hole), numbers/strings/bools as-is.
"""
import math

import lupa

_lua_type = lupa.lua_type
MAX_DEPTH = 64
BIG = 1.7976931348623157e308


def _num(v):
    if isinstance(v, float):
        if v != v:
            return 0
        if v in (math.inf, -math.inf):
            return BIG if v > 0 else -BIG
        if v.is_integer() and abs(v) < 9007199254740992:
            return int(v)
    return v


def _key(k):
    if isinstance(k, str):
        return k
    if isinstance(k, bool):
        return "true" if k else "false"
    if isinstance(k, float):
        k = _num(k)
    if isinstance(k, bytes):
        return k.decode("utf-8", "replace")
    return str(k)


_TABLE_TYPES = set()   # lupa's table wrapper class(es), learned on first sight (one per Lua version module)


def _is_table(v):
    tv = type(v)
    if tv in _TABLE_TYPES:
        return True
    if _lua_type(v) == "table":
        _TABLE_TYPES.add(tv)
        return True
    return False


def lua_to_py(v, _depth=0):
    """Convert a Lua value (as returned by lupa) into JSON-serialisable Python."""
    tv = type(v)
    if tv is str or tv is int or tv is bool or v is None:
        return v
    if tv is float:
        return _num(v)
    if tv is bytes:
        return v.decode("utf-8", "replace")
    if not _is_table(v):
        return None
    if _depth > MAX_DEPTH:
        raise ValueError("Lua table nested deeper than %d (cycle?)" % MAX_DEPTH)
    items = list(v.items())
    if not items:
        return {}
    n = len(items)
    seq = True
    for k, _ in items:
        if type(k) is not int or k < 1 or k > n:
            seq = False
            break
    d = _depth + 1
    if seq:
        out = [None] * n
        for k, val in items:
            t = type(val)
            if t is str or t is int or t is bool:
                out[k - 1] = val
            else:
                out[k - 1] = lua_to_py(val, d)
        return out
    obj = {}
    for k, val in items:
        if type(k) is not str:
            k = _key(k)
        t = type(val)
        if t is str or t is int or t is bool:
            obj[k] = val
        elif t is float:
            obj[k] = _num(val)
        elif t in _TABLE_TYPES or _is_table(val):
            obj[k] = lua_to_py(val, d)
        elif t is bytes:
            obj[k] = val.decode("utf-8", "replace")
        # functions, userdata, threads: dropped
    return obj


def py_to_lua(L, obj, _depth=0):
    """Convert JSON-decoded Python into Lua values for runtime L (dict -> string-keyed table, list -> sequence)."""
    if isinstance(obj, dict):
        if _depth > MAX_DEPTH:
            raise ValueError("JSON nested too deep")
        t = L.table()
        for k, val in obj.items():
            if val is None:
                continue
            t[str(k)] = py_to_lua(L, val, _depth + 1)
        return t
    if isinstance(obj, (list, tuple)):
        if _depth > MAX_DEPTH:
            raise ValueError("JSON nested too deep")
        t = L.table()
        for i, val in enumerate(obj, 1):
            if val is not None:
                t[i] = py_to_lua(L, val, _depth + 1)
        return t
    return obj
