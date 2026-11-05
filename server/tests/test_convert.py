"""Unit tests: Lua <-> JSON conversion rules (server/sos/convert.py, documented in docs/PROTOCOL.md)."""
import json
import math
import unittest

from lupa import LuaRuntime

from sos.convert import lua_to_py, py_to_lua


class LuaToJson(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.L = LuaRuntime(unpack_returned_tuples=True)

    def conv(self, src):
        return lua_to_py(self.L.eval(src))

    def test_scalars(self):
        self.assertEqual(self.conv("1"), 1)
        self.assertEqual(self.conv("2.5"), 2.5)
        self.assertEqual(self.conv("3.0"), 3)            # integral float -> int
        self.assertIsInstance(self.conv("3.0"), int)
        self.assertEqual(self.conv("'привет'"), "привет")
        self.assertIs(self.conv("true"), True)
        self.assertIsNone(self.conv("nil"))

    def test_nan_inf(self):
        self.assertEqual(self.conv("0/0"), 0)
        self.assertEqual(self.conv("math.huge"), 1.7976931348623157e308)
        self.assertEqual(self.conv("-math.huge"), -1.7976931348623157e308)
        json.dumps(self.conv("{a = 0/0, b = math.huge}"), allow_nan=False)  # must not raise

    def test_sequence_becomes_array(self):
        self.assertEqual(self.conv("{10, 20, 30}"), [10, 20, 30])
        self.assertEqual(self.conv("{{a=1}, {a=2}}"), [{"a": 1}, {"a": 2}])

    def test_empty_table_is_object(self):
        self.assertEqual(self.conv("{}"), {})
        self.assertEqual(self.conv("{list = {}, map = {}}"), {"list": {}, "map": {}})

    def test_map_keys_become_strings(self):
        self.assertEqual(self.conv("{a = 1, b = 'x'}"), {"a": 1, "b": "x"})
        self.assertEqual(self.conv("{[1] = 'a', [3] = 'c'}"), {"1": "a", "3": "c"})      # holes -> object
        self.assertEqual(self.conv("{[2] = 'b'}"), {"2": "b"})                           # not starting at 1
        self.assertEqual(self.conv("{[0] = 'z', [1] = 'a'}"), {"0": "z", "1": "a"})
        self.assertEqual(self.conv("{[1] = 'a', x = 1}"), {"1": "a", "x": 1})           # mixed -> object
        self.assertEqual(self.conv("{[true] = 1}"), {"true": 1})
        self.assertEqual(self.conv("{[2.0] = 'x'}"), {"2": "x"})                         # Lua normalises 2.0 -> 2
        self.assertEqual(self.conv("{[2.5] = 'x'}"), {"2.5": "x"})
        self.assertEqual(self.conv("{['1000'] = {role = 'Founder'}}"), {"1000": {"role": "Founder"}})

    def test_functions_dropped(self):
        self.assertEqual(self.conv("{a = 1, f = function() end}"), {"a": 1})
        self.assertEqual(self.conv("{1, function() end}"), [1, None])

    def test_cycle_detected(self):
        t = self.L.eval("(function() local t = {} t.self = t return t end)()")
        with self.assertRaises(ValueError):
            lua_to_py(t)

    def test_nested_roundtrip(self):
        data = {"name": "Nova", "slots": {"SoC": "soc_1", "RAM": "ram_1"}, "list": [1, 2, {"x": [3, 4]}],
                "owners": {"1000": {"sharePercent": 50}}, "flag": False, "price": 399.5}
        t = py_to_lua(self.L, data)
        back = lua_to_py(t)
        self.assertEqual(back, data)


class JsonToLua(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.L = LuaRuntime(unpack_returned_tuples=True)

    def test_arrays_are_one_based(self):
        t = py_to_lua(self.L, [5, 6, 7])
        self.assertEqual(self.L.eval("function(t) return #t, t[1], t[3], t[0] end")(t), (3, 5, 7, None))

    def test_objects_have_string_keys(self):
        t = py_to_lua(self.L, {"1": "a", "x": 2})
        f = self.L.eval("function(t) return t['1'], t[1], t.x end")
        self.assertEqual(f(t), ("a", None, 2))

    def test_null_handling(self):
        t = py_to_lua(self.L, {"a": None, "b": [1, None, 3]})
        f = self.L.eval("function(t) return t.a, t.b[1], t.b[2], t.b[3] end")
        self.assertEqual(f(t), (None, 1, None, 3))

    def test_numbers_and_strings(self):
        t = py_to_lua(self.L, {"i": 7, "f": 1.5, "s": "текст", "b": True})
        f = self.L.eval("function(t) return math.type(t.i), t.f, t.s, t.b end")
        self.assertEqual(f(t), ("integer", 1.5, "текст", True))

    def test_too_deep_rejected(self):
        deep = []
        cur = deep
        for _ in range(100):
            nxt = []
            cur.append(nxt)
            cur = nxt
        with self.assertRaises(ValueError):
            py_to_lua(self.L, deep)

    def test_state_roundtrip_through_real_rules(self):
        """A CompanyState created by CompanyFactory survives Lua -> JSON -> Lua -> JSON unchanged and still ticks."""
        from sos.lua_host import LuaHost
        host = LuaHost()
        host.call("connectPlayer", 1000, "T", None)
        ok, sid = host.call("createCompany", 1000, host.to_lua({"id": "rt1", "name": "Round Trip", "mode": "solo"}))
        self.assertTrue(ok)
        host.drain()
        for _ in range(40):
            host.call("step", 2.0)  # speed 1: one day per call
        host.drain()
        state = host.state_py(sid)
        text = json.dumps(state, allow_nan=False)
        host.call("disconnectPlayer", 1000)
        host.call("unload", sid)
        host.drain()
        host.call("loadCompany", host.to_lua(json.loads(text)))
        again = host.state_py(sid)
        again["time"]["speed"] = state["time"]["speed"]
        self.assertEqual(json.loads(json.dumps(again)), json.loads(text))
        self.assertFalse(math.isnan(again["finance"]["cash"]))


if __name__ == "__main__":
    unittest.main()
