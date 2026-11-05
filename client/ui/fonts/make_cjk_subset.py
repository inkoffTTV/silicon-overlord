#!/usr/bin/env python3
"""Rebuild the CJK fallback fonts (Noto Sans SC / JP Medium, SIL OFL 1.1, see NotoSansCJK-LICENSE.txt) as small subsets.

Kept glyphs: ASCII, CJK punctuation, full-width forms, GB2312 level-1 hanzi (3755 common characters) for SC,
kana + JIS level-1 kanji (2965) for JP, plus every character used by the zh / ja columns of client/ui/i18n/*.json.
Players' chat in rarer characters falls back to the operating system's fonts (Godot system fallback).

Usage: python3 client/ui/fonts/make_cjk_subset.py <dir with NotoSansSC-Medium.otf and NotoSansJP-Medium.otf>
       (full fonts: https://github.com/notofonts/noto-cjk/tree/main/Sans/SubsetOTF) — needs fontTools (pyftsubset).
"""
import glob
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = sys.argv[1] if len(sys.argv) > 1 else "."


def base_chars():
    s = set(chr(c) for c in range(0x20, 0x7F))
    for a, b in [(0x3000, 0x303F), (0xFF00, 0xFFEF), (0x2010, 0x2027), (0x2190, 0x2193), (0x25A0, 0x25FF)]:
        s |= set(chr(c) for c in range(a, b + 1))
    s |= set("·×÷…★☆✓—–«»“”‘’")
    return s


def i18n_chars(col):
    out = set()
    for f in glob.glob(os.path.join(HERE, "..", "i18n", "*.json")):
        data = json.load(open(f, encoding="utf-8"))
        cols = ["ru", "uk", "de", "es", "pt", "fr", "pl", "tr", "zh", "ja"]
        off = 1 if f.endswith("server.json") else 0
        for k, row in data.items():
            if isinstance(row, list) and len(row) > cols.index(col) + off:
                out |= set(row[cols.index(col) + off])
    # language names in the picker + voice test lines
    out |= set("简体中文日本語")
    out |= set("你好！我们来造一部手机吧？こんにちは！スマホを作ろうか？")
    return out


def sc_set():
    s = base_chars()
    for hi in range(0xB0, 0xD8):
        for lo in range(0xA1, 0xFF):
            try:
                s.add(bytes([hi, lo]).decode("gb2312"))
            except UnicodeDecodeError:
                pass
    return s | i18n_chars("zh") | i18n_chars("ja")


def jp_set():
    s = base_chars() | set(chr(c) for c in range(0x3040, 0x3100)) | set(chr(c) for c in range(0x31F0, 0x3200))
    for hi in range(0x88, 0x99):
        for lo in list(range(0x40, 0x7F)) + list(range(0x80, 0xFD)):
            try:
                ch = bytes([hi, lo]).decode("shift_jis")
            except UnicodeDecodeError:
                continue
            if 0x4E00 <= ord(ch) <= 0x9FFF:
                s.add(ch)
    return s | i18n_chars("ja") | i18n_chars("zh")


def run(name, chars):
    txt = os.path.join(SRC, name + ".txt")
    open(txt, "w", encoding="utf-8").write("".join(sorted(chars)))
    subprocess.check_call(["pyftsubset", os.path.join(SRC, name + ".otf"), "--text-file=" + txt,
                           "--output-file=" + os.path.join(HERE, name + ".otf"), "--layout-features=*", "--no-hinting"])
    print(name, len(chars), "chars ->", os.path.getsize(os.path.join(HERE, name + ".otf")), "bytes")


if __name__ == "__main__":
    run("NotoSansSC-Medium", sc_set())
    run("NotoSansJP-Medium", jp_set())
