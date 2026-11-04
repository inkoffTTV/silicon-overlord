#!/usr/bin/env python3
"""Silicon Overlord Online — game server.

    python3 server/main.py --port 7350 --data server/data

Runs the shared Luau game rules (shared-luau/) in a Lua VM (lupa) and serves Godot clients over WebSocket
(docs/PROTOCOL.md). Saves go to SQLite in --data. Stop with Ctrl+C / SIGTERM: every company is saved first.
"""
import argparse
import asyncio
import logging
import os
import signal
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from sos.server import GameServer  # noqa: E402


def parse_args(argv=None):
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser(description="Silicon Overlord Online server")
    ap.add_argument("--host", default="0.0.0.0", help="address to listen on (default 0.0.0.0 = everywhere)")
    ap.add_argument("--port", type=int, default=7350)
    ap.add_argument("--data", default=os.path.join(here, "data"), help="folder for the SQLite database")
    ap.add_argument("--autosave", type=float, default=60.0, help="autosave interval, seconds")
    ap.add_argument("--idle-unload", type=float, default=60.0, help="unload a company this many seconds after its last player left")
    ap.add_argument("--stats-every", type=float, default=300.0, help="log CPU/tick statistics every N seconds")
    ap.add_argument("--log-level", default="INFO")
    return ap.parse_args(argv)


async def run(args):
    server = GameServer(args.data, autosave_seconds=args.autosave, idle_unload_seconds=args.idle_unload,
                        stats_seconds=args.stats_every)
    await server.start(args.host, args.port)
    stop = asyncio.Event()
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            loop.add_signal_handler(sig, stop.set)
        except NotImplementedError:  # Windows
            pass
    await stop.wait()
    logging.getLogger("server").info("shutting down...")
    await server.stop()


def main():
    args = parse_args()
    logging.basicConfig(level=getattr(logging, args.log_level.upper(), logging.INFO),
                        format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    logging.getLogger("websockets").setLevel(logging.WARNING)
    try:
        asyncio.run(run(args))
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
