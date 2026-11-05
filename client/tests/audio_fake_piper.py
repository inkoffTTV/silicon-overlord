#!/usr/bin/env python3
"""Stand-in for piper (used by client/tests/audio_voice_test.gd on machines without piper).

Speaks the same protocol the game uses with the real piper:
    fake_piper.py --model X.onnx --json-input --output_dir DIR --quiet
stdin: one JSON object per line ({"text": "..."}); for every line a 22050 Hz mono 16-bit WAV is written to
DIR/<timestamp>.wav and its path printed on stdout. Takes ~40 ms per line (piper medium needs 0.1-0.4 s).
"""
import json
import math
import os
import struct
import sys
import time


def main() -> None:
    args = sys.argv[1:]
    out_dir = "."
    if "--output_dir" in args:
        out_dir = args[args.index("--output_dir") + 1]
    os.makedirs(out_dir, exist_ok=True)
    rate = 22050
    for raw in sys.stdin:
        raw = raw.strip()
        if not raw:
            continue
        try:
            text = json.loads(raw).get("text", "")
        except ValueError:
            text = raw
        time.sleep(0.04)
        n = int(rate * min(12.0, 0.3 + 0.05 * len(text)))
        cyr = any("Ѐ" <= ch <= "ӿ" for ch in text)
        f0 = 120.0 if cyr else 170.0
        frames = bytearray()
        for i in range(n):
            ph = (i % 2400) / 2400.0
            s = math.sin(2 * math.pi * f0 * i / rate) * math.sin(math.pi * ph) * 0.5
            frames += struct.pack("<h", int(s * 32000))
        path = os.path.join(out_dir, "%d.wav" % time.time_ns())
        with open(path, "wb") as f:
            f.write(b"RIFF" + struct.pack("<I", 36 + len(frames)) + b"WAVE")
            f.write(b"fmt " + struct.pack("<IHHIIHH", 16, 1, 1, rate, rate * 2, 2, 16))
            f.write(b"data" + struct.pack("<I", len(frames)) + frames)
        sys.stdout.write(path + "\n")
        sys.stdout.flush()


if __name__ == "__main__":
    main()
