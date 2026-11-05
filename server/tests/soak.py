"""Soak: N companies (one websocket client each) play D game days at speed 8 against a real server process.

Measures the server process: CPU per tick (Lua step + outbox dispatch + JSON), CPU per company-day, total CPU
usage (/proc) and resident memory, and checks that every client's replica (snapshot + sections) equals a fresh
snapshot at the end (catches dirty-section bugs before the quarter flush hides them).

    python3 server/tests/run.py --soak-only --companies=10 --days=30
"""
import asyncio
import copy
import os
import re
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time

from client import Client, PHONE_SLOTS

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.dirname(HERE)


def free_port():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    p = s.getsockname()[1]
    s.close()
    return p


def proc_cpu_seconds(pid):
    with open("/proc/%d/stat" % pid) as f:
        parts = f.read().rsplit(")", 1)[1].split()
    tck = os.sysconf("SC_CLK_TCK")
    return (int(parts[11]) + int(parts[12])) / tck


def proc_rss_mb(pid):
    with open("/proc/%d/status" % pid) as f:
        for line in f:
            if line.startswith("VmRSS:"):
                return int(line.split()[1]) / 1024
    return 0.0


def norm(v):
    if isinstance(v, dict):
        return [] if not v else {k: norm(x) for k, x in v.items()}
    if isinstance(v, list):
        return [norm(x) for x in v]
    return v


async def play(url, i, days, results):
    c = await Client(url, "Soak%d" % i).connect()
    try:
        await c.hello()
        await c.create("Soak Company %d" % i, mode="solo" if i % 2 else "cofounder")
        await c.act("startResearch", {"techId": "arch_arm_2"})
        r = await c.act("createBlueprint", {"name": "Phone %d" % i, "subtype": "MidrangePhone"})
        bp = r["data"]["id"]
        await c.act("updateBlueprint", {"id": bp, "slots": PHONE_SLOTS, "priceUSD": 349 + i * 10})
        r = await c.act("publishBlueprint", {"id": bp})
        pid, proj = r["data"]["productId"], r["data"].get("projectId")
        await c.act("claimDaily")
        # 0.5.0: a bit of build mode (the interior section must stay in sync through the soak)
        await c.act("interiorPlace", {"room": "garage", "def": "plant_pothos", "x": -2.5, "z": -1.5, "rot": 0})
        await c.act("interiorTheme", {"room": "garage", "theme": ["grunge", "wood", "lab", "neon", "scandi"][i % 5]})
        await c.act("buildExpansion", {"id": ["annex", "shed", "showroom", "basement"][i % 4]})
        cash0 = c.state["finance"]["cash"]
        await c.speed(8)
        t0 = time.time()
        if days >= 60:
            # full loop: development -> production -> launch -> sales
            await c.wait_for(lambda: proj not in (c.state.get("projects") or {}), 40, "project done")
            await c.act("queueProduction", {"productId": pid, "lineId": "line_1", "quantity": 3000})
            await c.wait_for(lambda: c.state["products"][pid]["inventory"] > 0 or any(
                cr["productId"] == pid for cr in (c.state["production"].get("crates") or [])), 40, "units")
            await c.act("launchProduct", {"productId": pid, "positioning": "Value"})
        await c.wait_for(lambda: c.state["time"]["elapsedDays"] >= days, days / 4 * 3 + 30, "%d days" % days)
        took = time.time() - t0
        await c.speed(0)
        await asyncio.sleep(0.5)
        replica = copy.deepcopy(c.state)
        n = len(c.frames)
        await c.act("getSnapshot")
        snap = (await c.wait_frame("snapshot", after=n))["state"]
        bad = [k for k in snap if k not in ("lastSaveAt", "idCounter") and norm(snap.get(k)) != norm(replica.get(k))]
        results.append({"i": i, "days": replica["time"]["elapsedDays"], "took": took, "mismatch": bad,
                        "cashDelta": replica["finance"]["cash"] - cash0, "sections": c.sections_count,
                        "sold": replica["products"][pid]["unitsSold"]})
    finally:
        await c.close()


async def soak_async(companies, days):
    port = free_port()
    data = tempfile.mkdtemp(prefix="sos_soak_")
    proc = subprocess.Popen([sys.executable, os.path.join(SERVER, "main.py"), "--host", "127.0.0.1", "--port", str(port),
                             "--data", data, "--stats-every", "100000"], stderr=subprocess.PIPE, stdout=subprocess.DEVNULL,
                            text=True)
    try:
        url = "ws://127.0.0.1:%d/ws" % port
        for _ in range(100):
            try:
                _r, w = await asyncio.open_connection("127.0.0.1", port)
                w.close()
                break
            except OSError:
                await asyncio.sleep(0.1)
        cpu0, wall0 = proc_cpu_seconds(proc.pid), time.time()
        results = []
        await asyncio.gather(*[play(url, i, days, results) for i in range(companies)])
        cpu, wall = proc_cpu_seconds(proc.pid) - cpu0, time.time() - wall0
        rss = proc_rss_mb(proc.pid)
    finally:
        proc.send_signal(signal.SIGTERM)
        try:
            _out, err = proc.communicate(timeout=20)
        except subprocess.TimeoutExpired:
            proc.kill()
            _out, err = proc.communicate()
        shutil.rmtree(data, ignore_errors=True)
    stats = [l for l in err.splitlines() if "stats:" in l]
    errors = [l for l in err.splitlines() if " ERROR " in l or "Traceback" in l]
    return results, cpu, wall, rss, stats, errors


def run(companies=10, days=30):
    print("\n=== soak: %d companies x %d game days at speed 8 (server in a separate process) ===" % (companies, days))
    results, cpu, wall, rss, stats, errors = asyncio.run(soak_async(companies, days))
    ok = len(results) == companies
    for r in sorted(results, key=lambda x: x["i"]):
        line = "  company %2d: day %3d in %5.1f s, cash %+12.0f, units sold %6d, %4d sections frames" % (
            r["i"], r["days"], r["took"], r["cashDelta"], r["sold"], r["sections"])
        if r["mismatch"]:
            line += "  REPLICA MISMATCH: %s" % r["mismatch"]
            ok = False
        print(line)
    for s in stats:
        m = re.search(r"stats: (.*)", s)
        print("  server " + (m.group(1) if m else s))
    print("  server process: %.2f s CPU over %.1f s wall = %.1f%% of one core, RSS %.0f MB" % (
        cpu, wall, 100 * cpu / wall if wall else 0, rss))
    if errors:
        ok = False
        print("  SERVER ERRORS:\n    " + "\n    ".join(errors[:20]))
    print("  soak %s" % ("OK" if ok else "FAILED"))
    return ok


if __name__ == "__main__":
    sys.path.insert(0, SERVER)
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 10
    d = int(sys.argv[2]) if len(sys.argv) > 2 else 30
    sys.exit(0 if run(n, d) else 1)
