#!/usr/bin/env python3
"""Export the 0.5.0 interior data (build mode) from the shared Luau modules to JSON for the Godot client.

Same lupa approach as client/tools/export_data.py (Luau types stripped by tools/luau_strip.py, Roblox globals
shimmed by tools/lua_shim.lua). The world mirrors the server's placement rules locally with this data (ghost
tint in build mode); the server stays authoritative.

Writes client/ui/data/interior.json:
  categories, themes, materials, lightPresets, list (every placeable item), legacyMap
  geometry   grid, rotStep, wallSnap, officeHalf, rooms (RoomGeometry.list) and officeByLevel (RoomGeometry.room
             ("office", 2..7) resolved: bounds, reserved zones and maxItems grow with the HQ level)
  expansions Data/Expansions (list, upgradeMult)
  processes  Data/ProductionProcesses.list
  balance    Balance.Interior + Balance.Expansions

Usage:  python3 client/tools/export_interior.py
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import export_data as ed  # noqa: E402  (shares make_runtime / to_py)

OUT = os.path.join(ed.ROOT, "client", "ui", "data", "interior.json")


def main():
    L = ed.make_runtime()
    req = L.eval("function(path) local n = game.ReplicatedStorage.Shared for part in string.gmatch(path, '[^.]+') do n = n[part] end return require(n) end")
    cat = req("Data.Interior")
    geo = req("Data.RoomGeometry")
    exp = req("Data.Expansions")
    proc = req("Data.ProductionProcesses")
    bal = req("Config.Balance")
    office = {}
    for lv in range(2, 8):
        office[str(lv)] = ed.to_py(geo.room("office", lv))
    data = {
        "categories": ed.to_py(cat.categories),
        "themes": ed.to_py(cat.themes),
        "materials": ed.to_py(cat.materials),
        "lightPresets": ed.to_py(cat.lightPresets),
        "list": ed.to_py(cat.list),
        "legacyMap": ed.to_py(cat.legacyMap),
        "geometry": {
            "grid": ed.to_py(geo.grid), "rotStep": ed.to_py(geo.rotStep), "wallSnap": ed.to_py(geo.wallSnap),
            "officeHalf": ed.to_py(geo.officeHalf), "rooms": ed.to_py(geo.list), "officeByLevel": office,
        },
        "expansions": {"list": ed.to_py(exp.list), "upgradeMult": ed.to_py(exp.upgradeMult)},
        "processes": ed.to_py(proc.list),
        "balance": {"Interior": ed.to_py(bal.Interior), "Expansions": ed.to_py(bal.Expansions)},
    }
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
    print("wrote %s (%d KB, %d items, %d rooms)" % (os.path.relpath(OUT, ed.ROOT), os.path.getsize(OUT) // 1024,
                                                   len(data["list"]), len(data["geometry"]["rooms"])))


if __name__ == "__main__":
    main()
