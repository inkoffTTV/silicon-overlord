#!/usr/bin/env python3
"""Server test runner.

    python3 server/tests/run.py            # unit + end-to-end tests + 30-day soak with 10 companies
    python3 server/tests/run.py --quick    # skip the soak
    python3 server/tests/run.py --soak-only [--companies N --days D]

Unit tests: test_convert.py (Lua <-> JSON), test_rules.py (iteration-2 rules, locale catalog). End-to-end: test_e2e.py (real server on a random port, websocket
clients). Soak: soak.py (prints CPU per tick). Exit code 0 = everything passed.
"""
import logging
import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.dirname(HERE)
sys.path.insert(0, SERVER)
sys.path.insert(0, HERE)


def arg_value(name, default):
    for a in sys.argv[1:]:
        if a.startswith(name + "="):
            return int(a.split("=", 1)[1])
    return default


def main():
    logging.basicConfig(level=logging.WARNING, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    ok = True
    if "--soak-only" not in sys.argv:
        loader = unittest.TestLoader()
        suite = unittest.TestSuite()
        for mod in ("test_convert", "test_rules", "test_e2e"):
            suite.addTests(loader.loadTestsFromName(mod))
        result = unittest.TextTestRunner(verbosity=2).run(suite)
        ok = result.wasSuccessful()
    if "--quick" not in sys.argv:
        import soak
        ok = soak.run(companies=arg_value("--companies", 10), days=arg_value("--days", 30)) and ok
    print("\nALL PASSED" if ok else "\nFAILED")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
