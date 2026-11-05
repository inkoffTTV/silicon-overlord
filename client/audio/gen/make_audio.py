#!/usr/bin/env python3
"""Procedural sound + music generator for Silicon Overlord Online (AUDIO agent).

Every sound in client/audio/{sfx,loops,ambient,music,voice} is synthesized here from scratch (numpy only),
then encoded to Ogg Vorbis with ffmpeg. Original material, no third-party samples.
Also writes client/audio/bank_data.gd (name -> variant paths) which Sfx loads at runtime.

    python3 client/audio/gen/make_audio.py            # everything
    python3 client/audio/gen/make_audio.py click game  # only these names (bank_data.gd is still rewritten)

Deterministic (fixed seeds), so re-running produces the same files.
"""
import os
import subprocess
import sys

import numpy as np

SR = 44100
HERE = os.path.dirname(os.path.abspath(__file__))
AUDIO = os.path.dirname(HERE)
TWO_PI = 2 * np.pi

# ------------------------------------------------------------------------------------------------
# DSP helpers
# ------------------------------------------------------------------------------------------------


def rng(seed):
    return np.random.default_rng(seed)


def tt(dur):
    return np.arange(int(dur * SR)) / SR


def secs(x):
    return len(x) / SR


def white(n, r):
    return r.standard_normal(n)


def spectral(x, fn, circular=False):
    """Filter x by a magnitude response fn(freqs) in the FFT domain. Circular=True keeps loops seamless."""
    n = len(x)
    pad = 0 if circular else min(n, SR // 2)
    X = np.fft.rfft(np.concatenate([x, np.zeros(pad)]))
    f = np.fft.rfftfreq(n + pad, 1 / SR)
    y = np.fft.irfft(X * fn(f), n + pad)
    return y[:n]


def lp_resp(fc, order=2):
    return lambda f: 1 / np.sqrt(1 + (f / fc) ** (2 * order))


def hp_resp(fc, order=2):
    return lambda f: 1 / np.sqrt(1 + (fc / np.maximum(f, 1e-3)) ** (2 * order))


def bp_resp(fc, q):
    # gaussian bump on a log-frequency axis; q ~ fc / bandwidth
    w = 1.0 / (q * 1.2)
    return lambda f: np.exp(-0.5 * (np.log2(np.maximum(f, 1) / fc) / w) ** 2)


def lp(x, fc, order=2, circular=False):
    return spectral(x, lp_resp(fc, order), circular)


def hp(x, fc, order=2, circular=False):
    return spectral(x, hp_resp(fc, order), circular)


def bp(x, fc, q=2.0, circular=False):
    return spectral(x, bp_resp(fc, q), circular)


def pink(n, r, circular=True):
    return norm(spectral(white(n, r), lambda f: 1 / np.sqrt(np.maximum(f, 20)), circular))


def brown(n, r, circular=True):
    return norm(spectral(white(n, r), lambda f: 1 / np.maximum(f, 15), circular))


def norm(x, peak=1.0):
    m = np.max(np.abs(x)) if len(x) else 0
    return x * (peak / m) if m > 0 else x


def db(v):
    return 10 ** (v / 20)


def env_exp(n, decay, attack=0.002):
    t = np.arange(n) / SR
    a = np.clip(t / max(attack, 1e-5), 0, 1)
    return a * np.exp(-t / decay)


def env_ar(n, attack, release_start, release):
    t = np.arange(n) / SR
    a = np.clip(t / max(attack, 1e-5), 0, 1)
    r = np.clip(1 - (t - release_start) / max(release, 1e-5), 0, 1)
    return a * np.where(t < release_start, 1.0, r)


def fade(x, fin=0.003, fout=0.01):
    x = x.copy()
    a, b = int(fin * SR), int(fout * SR)
    if a > 0:
        x[:a] *= np.linspace(0, 1, a)
    if b > 0:
        x[-b:] *= np.linspace(1, 0, b)
    return x


def osc(freq, n, shape="sine", phase0=0.0):
    """freq: scalar or per-sample array."""
    f = np.broadcast_to(np.asarray(freq, dtype=float), (n,))
    ph = phase0 + np.cumsum(f) / SR
    if shape == "sine":
        return np.sin(TWO_PI * ph)
    if shape == "saw":
        return 2 * (ph % 1.0) - 1
    if shape == "square":
        return np.sign(np.sin(TWO_PI * ph))
    if shape == "tri":
        return 2 * np.abs(2 * (ph % 1.0) - 1) - 1
    raise ValueError(shape)


def glide(f0, f1, n, curve=1.0):
    k = np.linspace(0, 1, n) ** curve
    return f0 * (f1 / f0) ** k


def mix_at(buf, x, start, gain=1.0, wrap=False):
    s = int(start)
    n = len(x)
    if wrap:
        idx = (np.arange(n) + s) % len(buf)
        np.add.at(buf, idx, x * gain)
        return
    if s >= len(buf):
        return
    e = min(len(buf), s + n)
    buf[s:e] += x[: e - s] * gain


def reverb_ir(dur, decay, r, bright=6000, predelay=0.0):
    n = int(dur * SR)
    ir = white(n, r) * np.exp(-np.arange(n) / SR / decay)
    ir = lp(ir, bright, 1)
    ir[: int(predelay * SR)] = 0
    return ir / np.sqrt(np.sum(ir ** 2))


def convolve(x, ir, circular=False):
    if circular:
        n = len(x)
        irp = np.zeros(n)
        m = min(n, len(ir))
        irp[:m] = ir[:m]
        return np.fft.irfft(np.fft.rfft(x) * np.fft.rfft(irp), n)
    n = len(x) + len(ir) - 1
    nfft = 1 << int(np.ceil(np.log2(n)))
    y = np.fft.irfft(np.fft.rfft(x, nfft) * np.fft.rfft(ir, nfft), nfft)
    return y[:n]


def room(x, wet=0.25, dur=0.6, decay=0.15, seed=7, bright=5000, circular=False, keep_len=False):
    ir = reverb_ir(dur, decay, rng(seed), bright)
    if circular:
        return x + wet * convolve(x, ir, True)
    y = convolve(x, ir) * wet
    y[: len(x)] += x
    return y[: len(x)] if keep_len else trim_tail(y)


def add(*xs):
    """Sum arrays of different lengths (zero-padded)."""
    n = max(len(x) for x in xs)
    out = np.zeros(n)
    for x in xs:
        out[:len(x)] += x
    return out


def trim_tail(x, thresh_db=-60):
    a = np.abs(x)
    th = np.max(a) * db(thresh_db) if len(a) else 0
    idx = np.nonzero(a > th)[0]
    end = idx[-1] + int(0.01 * SR) if len(idx) else len(x)
    return x[: min(len(x), end)]


def softclip(x, drive=1.0):
    return np.tanh(x * drive) / np.tanh(drive)


def resonator(x, freqs, decays, gains, circular=False):
    """Bank of decaying modes driven by x (via FFT conv with each mode's impulse response)."""
    out = np.zeros(len(x))
    for f, d, g in zip(freqs, decays, gains):
        n = int(min(d * 6, 4.0) * SR)
        t = np.arange(n) / SR
        ir = np.sin(TWO_PI * f * t) * np.exp(-t / d)
        y = convolve(x, ir, circular)
        out += g * (y[: len(x)])
    return out


# ------------------------------------------------------------------------------------------------
# tonal building blocks
# ------------------------------------------------------------------------------------------------


def midi(m):
    return 440.0 * 2 ** ((m - 69) / 12)


def bell(freq, dur, bright=1.0, decay=None):
    n = int(dur * SR)
    t = np.arange(n) / SR
    d = decay or dur * 0.35
    mod = np.sin(TWO_PI * freq * 1.4 * t) * (2.5 * bright) * np.exp(-t / (d * 0.5))
    y = np.sin(TWO_PI * freq * t + mod) * np.exp(-t / d)
    y += 0.25 * np.sin(TWO_PI * freq * 2.76 * t) * np.exp(-t / (d * 0.3))
    return fade(y * env_exp(n, 10, 0.001), 0.001, 0.02)


def marimba(freq, dur=0.5):
    n = int(dur * SR)
    t = np.arange(n) / SR
    y = np.sin(TWO_PI * freq * t) * np.exp(-t / 0.18)
    y += 0.35 * np.sin(TWO_PI * freq * 3.93 * t) * np.exp(-t / 0.04)
    y += 0.15 * np.sin(TWO_PI * freq * 9.2 * t) * np.exp(-t / 0.015)
    return fade(y * np.clip(t / 0.0015, 0, 1), 0.0005, 0.02)


def blip(f0, f1, dur, shape="sine", decay=None):
    n = int(dur * SR)
    y = osc(glide(f0, f1, n), n, shape)
    return fade(y * env_exp(n, decay or dur * 0.4, 0.001), 0.0005, 0.005)


def rhodes(freq, dur, vel=1.0, r=None):
    """Electric-piano-ish FM tone."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    idx = (1.6 * vel) * np.exp(-t / 0.35) + 0.2
    mod = np.sin(TWO_PI * freq * t) * idx
    y = np.sin(TWO_PI * freq * t + mod)
    y += 0.12 * np.sin(TWO_PI * freq * 2.0 * t) * np.exp(-t / 0.5)
    tine = 0.08 * vel * np.sin(TWO_PI * freq * 7.0 * t) * np.exp(-t / 0.03)
    trem = 1 + 0.12 * np.sin(TWO_PI * 4.2 * t)
    e = np.clip(t / 0.004, 0, 1) * np.exp(-t / 1.8)
    return fade((y + tine) * e * trem * vel, 0.0005, 0.08)


def pad_voice(freq, dur, r, bright=1800):
    n = int(dur * SR)
    t = np.arange(n) / SR
    y = np.zeros(n)
    for det in (-0.06, 0.0, 0.07):
        fm = freq * 2 ** (det / 12) * (1 + 0.002 * np.sin(TWO_PI * (0.3 + r.random() * 0.2) * t))
        y += osc(fm, n, "saw", r.random())
    y = lp(y, bright, 2)
    return y * env_ar(n, dur * 0.3, dur * 0.6, dur * 0.4) / 3


def pluck(freq, dur, bright=3000):
    n = int(dur * SR)
    t = np.arange(n) / SR
    y = osc(freq, n, "saw") * np.exp(-t / 0.25)
    y = lp(y, bright, 2)
    return fade(y * np.clip(t / 0.002, 0, 1), 0.0005, 0.03)


def sub_bass(freq, dur):
    n = int(dur * SR)
    t = np.arange(n) / SR
    y = np.sin(TWO_PI * freq * t) + 0.2 * np.sin(TWO_PI * 2 * freq * t)
    e = np.clip(t / 0.01, 0, 1) * np.exp(-t / (dur * 0.8))
    return fade(softclip(y * e, 1.5), 0.002, 0.05)


# drums
def kick(r, punch=1.0):
    n = int(0.45 * SR)
    t = np.arange(n) / SR
    f = 45 + 110 * np.exp(-t / 0.035) * punch
    y = np.sin(TWO_PI * np.cumsum(f) / SR) * np.exp(-t / 0.18)
    y += 0.3 * lp(white(n, r), 1200) * np.exp(-t / 0.006)
    return softclip(y, 1.6)


def snare(r, soft=False):
    n = int(0.35 * SR)
    t = np.arange(n) / SR
    body = np.sin(TWO_PI * 185 * t) * np.exp(-t / 0.05)
    nz = bp(white(n, r), 2500 if not soft else 1800, 0.6) * np.exp(-t / (0.09 if not soft else 0.14))
    y = 0.6 * body + nz * 1.2
    return lp(y, 5000 if not soft else 3200, 2)


def hat(r, open_=False):
    n = int((0.25 if open_ else 0.06) * SR)
    t = np.arange(n) / SR
    y = hp(white(n, r), 7000, 2) * np.exp(-t / (0.08 if open_ else 0.015))
    return lp(y, 11000, 1)


def shaker(r):
    n = int(0.09 * SR)
    t = np.arange(n) / SR
    return bp(white(n, r), 6000, 1.0) * np.sin(np.pi * np.clip(t / 0.09, 0, 1)) ** 2


def vinyl(n, r, density=6.0, circular=True):
    y = 0.15 * lp(pink(n, r), 3000, 1, circular=circular)
    k = int(density * n / SR)
    pos = r.integers(0, n, k)
    clicks = np.zeros(n)
    clicks[pos] = r.standard_normal(k) * (r.random(k) ** 3) * 6
    clicks = bp(clicks, 3000, 0.7, circular=circular)
    return y + clicks


# ------------------------------------------------------------------------------------------------
# output
# ------------------------------------------------------------------------------------------------
OUT = {}  # name -> list of res:// paths
LOOPS = set()
KIND = {}  # name -> "sfx" | "ui" | "loop" | "ambient" | "music" | "voice"


def write_ogg(path, x, q=4):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    x = np.asarray(x, dtype=np.float32)
    ch = 1 if x.ndim == 1 else x.shape[1]
    peak = float(np.max(np.abs(x))) if x.size else 0
    if peak > 0.999:
        x = x * (0.98 / peak)
    p = subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "f32le", "-ar", str(SR), "-ac", str(ch), "-i", "-",
                        "-c:a", "libvorbis", "-q:a", str(q), path], input=x.tobytes())
    if p.returncode != 0:
        raise RuntimeError("ffmpeg failed for " + path)


def emit(kind, name, variants, peak_db=-3.0, loop=False, q=4):
    """variants: list of numpy arrays (mono 1-D or stereo (n,2))."""
    folder = {"ui": "sfx", "sfx": "sfx", "loop": "loops", "ambient": "ambient", "music": "music", "voice": "voice"}[kind]
    paths = []
    for i, v in enumerate(variants):
        v = np.asarray(v, dtype=float)
        if not loop:
            v = fade(v, 0.0005, 0.01) if v.ndim == 1 else np.stack([fade(v[:, 0], 0.0005, 0.01), fade(v[:, 1], 0.0005, 0.01)], 1)
        if peak_db is not None:
            v = norm(v, db(peak_db))
        fname = name + ("" if len(variants) == 1 else "_%d" % (i + 1)) + ".ogg"
        rel = folder + "/" + fname
        if SELECT is None or name in SELECT:
            write_ogg(os.path.join(AUDIO, rel), v, q)
        paths.append("res://audio/" + rel)
    OUT[name] = paths
    KIND[name] = kind
    if loop:
        LOOPS.add(name)


SELECT = None
GENERATORS = []


def gen(fn):
    GENERATORS.append(fn)
    return fn


# ------------------------------------------------------------------------------------------------
# UI sounds
# ------------------------------------------------------------------------------------------------
@gen
def ui_sounds():
    r = rng(1)

    def tick(f, dur=0.03, noise=0.2, seed=0):
        n = int(dur * SR)
        y = blip(f, f * 0.92, dur, "sine", dur * 0.25)
        y += noise * bp(white(n, rng(seed)), f * 2, 1.5) * env_exp(n, 0.004)
        return y

    emit("ui", "click", [tick(1700, seed=1), tick(1550, seed=2), tick(1850, seed=3)], -8)
    emit("ui", "hover", [tick(2600, 0.018, 0.1, 4)], -20)
    seq = lambda notes, gap, fn=marimba, dur=0.5: _seq([fn(midi(m), dur) for m in notes], gap)
    emit("ui", "confirm", [room(seq([76, 83], 0.07), 0.15, seed=11)], -7)
    emit("ui", "back", [room(seq([79, 72], 0.07), 0.15, seed=12)], -9)
    # open/close: soft filtered swish + blip
    def swish(up=True):
        n = int(0.18 * SR)
        t = np.arange(n) / SR
        nz = white(n, r)
        fc = glide(600, 3500, n) if up else glide(3500, 600, n)
        y = np.zeros(n)
        # chunked time-varying bandpass
        step = 512
        for i in range(0, n, step):
            seg = nz[i:i + step]
            y[i:i + step] = bp(np.pad(seg, (0, step - len(seg))), fc[i], 1.2)[:len(seg)]
        y *= np.sin(np.pi * t / t[-1]) ** 2
        b = blip(500 if up else 900, 900 if up else 500, 0.12, "sine", 0.05)
        out = 0.6 * y
        out[:len(b)] += 0.5 * b
        return out
    emit("ui", "open", [swish(True)], -12)
    emit("ui", "close", [swish(False)], -12)
    emit("ui", "tab", [tick(1200, 0.04, 0.5, 5)], -10)
    emit("ui", "toggle", [_seq([tick(1400, 0.02, 0.3, 6), tick(2000, 0.02, 0.3, 7)], 0.035)], -10)
    emit("ui", "type", [tick(f, 0.015, 1.2, s) for f, s in ((3200, 8), (2900, 9), (3500, 10))], -18)

    def bonk(f):
        n = int(0.14 * SR)
        y = lp(osc(glide(f, f * 0.85, n), n, "square"), 1400, 2) * env_exp(n, 0.06)
        return y
    emit("ui", "error", [_seq([bonk(196), bonk(147)], 0.12)], -8)
    emit("ui", "notify", [room(bell(midi(88), 0.9, 0.6), 0.2, seed=13)], -10)
    emit("ui", "success", [room(_seq([bell(midi(m), 0.8, 0.5) for m in (84, 88, 91)], 0.075), 0.25, seed=14)], -9)
    emit("ui", "warning", [room(_seq([marimba(midi(81)), marimba(midi(77))], 0.11), 0.2, seed=15)], -8)

    def coin():
        a = blip(midi(83), midi(83), 0.07, "square", 0.05)
        b = blip(midi(88), midi(88), 0.35, "square", 0.12)
        return lp(_seq([a, b], 0.065), 6000, 1)
    emit("ui", "coin", [coin()], -12)

    def register():
        rr = rng(21)
        # mechanical key clunks
        out = np.zeros(int(1.6 * SR))
        for k, at in enumerate((0.0, 0.06, 0.12)):
            n = int(0.05 * SR)
            c = bp(white(n, rr), 1800 - k * 300, 1.2) * env_exp(n, 0.008)
            mix_at(out, c, at * SR, 0.6)
        # drawer: low thump + slide
        n = int(0.35 * SR)
        slide = bp(white(n, rr), 900, 0.8) * env_ar(n, 0.03, 0.15, 0.2) * 0.35
        mix_at(out, slide, 0.22 * SR)
        thump = resonator(np.r_[1.0, np.zeros(int(0.25 * SR))], [140, 330], [0.05, 0.03], [1, 0.4])
        mix_at(out, norm(thump) * 0.7, 0.5 * SR)
        # the "ka-ching" bell
        ding = bell(2093, 1.1, 1.3, 0.4)
        mix_at(ding, 0.6 * bell(2637, 1.0, 1.0, 0.35), 0)
        mix_at(out, ding * 0.6, 0.22 * SR)
        return room(out, 0.2, seed=22)
    emit("ui", "cash_register", [register()], -6)

    def chime():
        notes = [72, 76, 79, 83, 86, 91]
        out = np.zeros(int(2.6 * SR))
        for i, m in enumerate(notes):
            mix_at(out, bell(midi(m), 1.8, 0.5, 0.7), i * 0.085 * SR, 0.7)
        sh = hp(white(len(out), r), 6000) * env_ar(len(out), 0.3, 0.6, 1.5) * 0.03
        return room(out + sh, 0.45, 2.0, 0.6, seed=23)
    emit("ui", "research_done", [chime()], -6)

    def levelup():
        out = np.zeros(int(2.4 * SR))
        for i, m in enumerate((67, 72, 76, 79, 84)):
            mix_at(out, marimba(midi(m), 0.4), i * 0.07 * SR, 0.8)
        rr = rng(24)
        for m in (60, 64, 67, 72):
            mix_at(out, pad_voice(midi(m), 1.6, rr, 2600), 0.35 * SR, 0.35)
        return room(out, 0.35, 1.5, 0.4, seed=25)
    emit("ui", "level_up", [levelup()], -6)

    def pop():
        n = int(0.09 * SR)
        return blip(300, 900, 0.09, "sine", 0.03) + 0.3 * bp(white(n, r), 2000, 1) * env_exp(n, 0.005)
    emit("ui", "chat_open", [pop()], -12)

    def beep(f, dur):
        n = int(dur * SR)
        y = 0.7 * osc(f, n, "sine") + 0.3 * lp(osc(f, n, "square"), 3000)
        return fade(y * env_ar(n, 0.005, dur - 0.05, 0.05), 0.001, 0.02)
    emit("ui", "countdown", [room(beep(880, 0.16), 0.25, 1.0, 0.25, seed=26)], -8)
    go = beep(1760, 0.55) + 0.5 * beep(1318.5, 0.55) + 0.4 * beep(880, 0.55)
    emit("ui", "countdown_go", [room(go, 0.3, 1.2, 0.3, seed=27)], -7)
    emit("ui", "challenge_good", [_seq([blip(midi(84), midi(84), 0.08, "tri", 0.05), blip(midi(91), midi(91), 0.2, "tri", 0.08)], 0.06)], -10)
    emit("ui", "challenge_bad", [lp(blip(220, 110, 0.3, "saw", 0.12), 1500)], -10)
    emit("ui", "challenge_done", [room(_seq([marimba(midi(m), 0.6) for m in (72, 76, 79, 84, 79, 84)], 0.09), 0.3, seed=28)], -7)


def _seq(parts, gap):
    total = int((gap * (len(parts) - 1)) * SR) + max(len(p) for p in parts) + int(gap * SR * len(parts))
    out = np.zeros(total)
    for i, p in enumerate(parts):
        mix_at(out, p, i * gap * SR)
    return trim_tail(out)


# ------------------------------------------------------------------------------------------------
# world one-shots
# ------------------------------------------------------------------------------------------------
@gen
def world_sounds():
    def step_concrete(seed):
        r = rng(seed)
        n = int(0.16 * SR)
        thump = lp(white(n, r), 260 + r.random() * 80, 2) * env_exp(n, 0.025, 0.003)
        scuff = bp(white(n, r), 2500 + r.random() * 1500, 1.0) * env_exp(n, 0.018 + r.random() * 0.01, 0.006)
        grit = hp(white(n, r) * (r.random(n) > 0.97), 3000) * env_exp(n, 0.03) * 0.6
        return room(norm(thump) * 1.0 + scuff * 0.5 + grit, 0.12, 0.4, 0.08, seed=seed + 100)
    emit("sfx", "step_concrete", [step_concrete(30 + i) for i in range(5)], -6)

    def step_wood(seed):
        r = rng(seed)
        n = int(0.25 * SR)
        exc = white(n, r) * env_exp(n, 0.006, 0.002)
        body = resonator(exc, [180 + r.random() * 40, 420 + r.random() * 80, 950], [0.05, 0.03, 0.015], [1.0, 0.6, 0.25])
        scuff = bp(white(n, r), 2000, 1.0) * env_exp(n, 0.02) * 0.08
        y = norm(body) + scuff
        if r.random() < 0.4:  # occasional creak
            m = int(0.18 * SR)
            cr = bp(osc(glide(300, 340, m) * (1 + 0.05 * np.sign(np.sin(TWO_PI * 28 * np.arange(m) / SR))), m, "saw"), 900, 1.5)
            mix_at(y, cr * env_ar(m, 0.03, 0.1, 0.08) * 0.15, 0.04 * SR)
        return room(y, 0.15, 0.5, 0.1, seed=seed + 100)
    emit("sfx", "step_wood", [step_wood(40 + i) for i in range(5)], -6)

    def step_metal(seed):
        r = rng(seed)
        n = int(0.4 * SR)
        exc = white(n, r) * env_exp(n, 0.003)
        fs = [520 + r.random() * 60, 1130 + r.random() * 90, 1870, 2950 + r.random() * 200]
        ring = resonator(exc, fs, [0.08, 0.06, 0.04, 0.03], [1, 0.7, 0.4, 0.3])
        thump = lp(white(n, r), 200) * env_exp(n, 0.02)
        return room(norm(ring) * 0.5 + norm(thump) * 0.8, 0.15, seed=seed + 100)
    emit("sfx", "step_metal", [step_metal(50 + i) for i in range(4)], -6)

    def whoosh(dur, f0, f1, seed, q=1.0):
        r = rng(seed)
        n = int(dur * SR)
        nz = white(n, r)
        fc = glide(f0, f1, n)
        y = np.zeros(n)
        step = 1024
        for i in range(0, n, step):
            seg = nz[i:i + step]
            y[i:i + len(seg)] = bp(np.pad(seg, (0, step - len(seg))), fc[i], q)[:len(seg)]
        t = np.arange(n) / SR
        return y * np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 1.5

    def thud(seed, f=120, dur=0.3, q=0.9):
        r = rng(seed)
        n = int(dur * SR)
        y = bp(white(n, r), f, q) * env_exp(n, dur * 0.2, 0.002)
        y += 0.4 * np.sin(TWO_PI * np.cumsum(glide(f * 0.9, f * 0.6, n)) / SR) * env_exp(n, dur * 0.15)
        return norm(y)

    jump = whoosh(0.25, 500, 1500, 60) * 0.5
    mix_at(jump, step_concrete(61) * 0.4, 0)
    emit("sfx", "jump", [jump], -12)
    emit("sfx", "land", [room(add(thud(62, 90, 0.3), 0.5 * norm(step_concrete(63))), 0.12, seed=64), room(add(thud(65, 100, 0.3), 0.5 * norm(step_concrete(66))), 0.12, seed=67)], -5)

    def rustle(seed, dur=0.25, f=3000, dens=0.4):
        r = rng(seed)
        n = int(dur * SR)
        grains = white(n, r) * (r.random(n) < dens)
        am = np.abs(lp(white(n, r), 30)) * 3
        y = bp(grains, f, 0.8) * am
        t = np.arange(n) / SR
        return norm(y * np.sin(np.pi * t / dur) ** 0.7)

    emit("sfx", "grab", [rustle(70, 0.18, 2200, 0.3), rustle(71, 0.15, 2600, 0.3)], -12)
    emit("sfx", "drop", [room(thud(72, 160, 0.2), 0.12, seed=73), room(thud(74, 190, 0.2), 0.12, seed=75)], -8)
    emit("sfx", "throw", [whoosh(0.35, 400, 2500, 76, 0.9), whoosh(0.3, 500, 3000, 77, 0.9)], -10)

    def impact_cardboard(seed, heavy=1.0):
        r = rng(seed)
        n = int(0.5 * SR)
        exc = white(n, r) * env_exp(n, 0.004)
        body = resonator(exc, [110 * (1.3 - 0.3 * heavy) + r.random() * 20, 260 + r.random() * 40, 520], [0.06, 0.035, 0.02], [1.0, 0.5, 0.2])
        crackle = bp(white(n, r) * (r.random(n) < 0.15), 3500, 0.8) * env_exp(n, 0.04) * 0.25
        return room(norm(body) + crackle, 0.15, seed=seed + 100)
    emit("sfx", "impact_cardboard", [impact_cardboard(80 + i) for i in range(3)], -5)

    def impact_wood(seed):
        r = rng(seed)
        n = int(0.4 * SR)
        exc = white(n, r) * env_exp(n, 0.002)
        body = resonator(exc, [310 + r.random() * 50, 760 + r.random() * 80, 1650, 2700], [0.045, 0.03, 0.018, 0.01], [1, 0.7, 0.4, 0.2])
        return room(norm(body), 0.15, seed=seed + 100)
    emit("sfx", "impact_wood", [impact_wood(90 + i) for i in range(3)], -5)

    def impact_metal(seed):
        r = rng(seed)
        n = int(1.0 * SR)
        exc = white(n, r) * env_exp(n, 0.002)
        base = 380 + r.random() * 120
        ratios = [1.0, 2.32, 4.25, 6.63, 9.38]
        ring = resonator(exc, [base * k for k in ratios], [0.35, 0.25, 0.15, 0.1, 0.06], [1, 0.8, 0.6, 0.4, 0.3])
        thump = lp(white(n, r), 300) * env_exp(n, 0.01)
        return room(norm(ring) * 0.6 + norm(thump) * 0.6, 0.18, seed=seed + 100)
    emit("sfx", "impact_metal", [impact_metal(100 + i) for i in range(3)], -6)
    emit("sfx", "impact_soft", [room(add(thud(110, 600, 0.08, 1.5) * 0.6, 0.4 * rustle(111, 0.06, 4000)), 0.1, seed=112), room(thud(113, 700, 0.08, 1.5) * 0.6, 0.1, seed=114)], -12)
    emit("sfx", "crate_grab", [add(rustle(120, 0.35, 2400, 0.25), 0.3 * rustle(121, 0.35, 900, 0.3)), rustle(122, 0.3, 2800, 0.25)], -9)
    emit("sfx", "crate_drop", [impact_cardboard(123, 0.0), impact_cardboard(124, 0.0)], -4)

    def ship_ok():
        out = np.zeros(int(1.4 * SR))
        mix_at(out, impact_cardboard(130, 0.0), 0, 0.8)
        mix_at(out, bell(midi(84), 0.9, 0.5) * 0.35, 0.18 * SR)
        mix_at(out, bell(midi(91), 0.9, 0.5) * 0.35, 0.28 * SR)
        return out
    emit("sfx", "ship_ok", [ship_ok()], -5)

    def ship_fail():
        out = np.zeros(int(0.8 * SR))
        mix_at(out, impact_cardboard(131, 0.0), 0, 0.8)
        n = int(0.35 * SR)
        buzz = lp(osc(150, n, "square"), 900) * env_ar(n, 0.01, 0.25, 0.1)
        mix_at(out, buzz * 0.3, 0.15 * SR)
        return out
    emit("sfx", "ship_fail", [ship_fail()], -6)

    def latch(seed):
        r = rng(seed)
        n = int(0.12 * SR)
        exc = white(n, r) * env_exp(n, 0.001)
        return norm(resonator(exc, [1800, 3300, 5200], [0.02, 0.012, 0.008], [1, 0.6, 0.3]))

    def creak(seed, dur=0.6, f=210):
        r = rng(seed)
        n = int(dur * SR)
        t = np.arange(n) / SR
        rate = 18 + 10 * np.sin(TWO_PI * 1.3 * t + r.random())  # stick-slip pulses
        pulses = (np.sin(TWO_PI * np.cumsum(rate) / SR) > 0.97).astype(float)
        y = resonator(pulses, [f, f * 2.6, f * 4.1], [0.03, 0.02, 0.012], [1, 0.5, 0.3])
        return norm(y) * env_ar(n, 0.05, dur - 0.15, 0.15)

    def van_door_open():
        out = np.zeros(int(1.2 * SR))
        mix_at(out, latch(140), 0, 0.7)
        mix_at(out, creak(141, 0.7, 300) * 0.4, 0.08 * SR)
        n = int(0.5 * SR)
        mix_at(out, bp(white(n, rng(142)), 700, 0.6) * env_ar(n, 0.1, 0.3, 0.2) * 0.2, 0.15 * SR)
        return room(out, 0.12, seed=143)
    emit("sfx", "van_door_open", [van_door_open()], -5)

    def slam(seed, low=70):
        r = rng(seed)
        n = int(1.0 * SR)
        exc = white(n, r) * env_exp(n, 0.003)
        body = resonator(exc, [low, low * 2.2, 410, 980, 1720], [0.12, 0.08, 0.15, 0.09, 0.06], [1.0, 0.6, 0.35, 0.25, 0.15])
        return norm(body)

    def van_door_close():
        out = np.zeros(int(1.3 * SR))
        mix_at(out, slam(144), 0)
        mix_at(out, latch(145) * 0.4, 0.01 * SR)
        return room(out, 0.15, seed=146)
    emit("sfx", "van_door_close", [van_door_close()], -3)

    def engine(dur, rpm_curve, seed, rough=0.3):
        """rpm_curve: per-sample firing frequency in Hz."""
        r = rng(seed)
        n = int(dur * SR)
        ph = np.cumsum(rpm_curve) / SR
        pulse = np.maximum(0, np.sin(TWO_PI * ph)) ** 6
        jitter = 1 + rough * lp(white(n, r), 20)
        y = pulse * jitter
        y = lp(y, 900, 2) + 0.4 * lp(osc(rpm_curve * 0.5, n, "saw"), 300)
        y += 0.05 * bp(white(n, r), 1800, 0.7) * (0.5 + pulse)
        return y

    def van_start():
        dur = 3.2
        n = int(dur * SR)
        t = np.arange(n) / SR
        out = np.zeros(n)
        # starter motor: whirring ~12 Hz cranking for 0.8 s
        m = int(0.85 * SR)
        tm = np.arange(m) / SR
        crank = (np.sin(TWO_PI * np.cumsum(glide(9, 13, m)) / SR) > 0.6).astype(float)
        whir = bp(osc(glide(330, 380, m), m, "saw"), 600, 1.0) * 0.3
        crank_snd = lp(crank, 600) + whir
        mix_at(out, norm(crank_snd) * 0.6 * np.clip(tm / 0.05, 0, 1), 0)
        # catch, rev, settle to idle
        rpm = np.where(t < 0.8, 12, 0) + np.interp(t, [0, 0.8, 1.1, 1.5, 2.2, dur], [0, 18, 60, 48, 26, 24])
        eng = engine(dur, np.maximum(rpm, 1), 147) * np.clip((t - 0.75) / 0.08, 0, 1)
        out += norm(eng) * 0.9
        return room(fade(out, 0.002, 0.4), 0.1, seed=148)
    emit("sfx", "van_start", [van_start()], -3)

    def door(open_=True):
        out = np.zeros(int(1.1 * SR))
        if open_:
            mix_at(out, latch(150), 0, 0.5)
            mix_at(out, creak(151, 0.8, 190) * 0.35, 0.1 * SR)
        else:
            mix_at(out, slam(152, 95) * 0.8, 0)
            mix_at(out, latch(153) * 0.5, 0.005 * SR)
        return room(out, 0.15, seed=154)
    emit("sfx", "door_open", [door(True)], -6)
    emit("sfx", "door_close", [door(False)], -4)

    def rollup():
        r = rng(155)
        dur = 3.0
        n = int(dur * SR)
        t = np.arange(n) / SR
        rate = np.interp(t, [0, 0.3, 2.6, dur], [6, 16, 15, 4])
        clicks = (np.diff(np.floor(np.cumsum(rate) / SR), prepend=0) > 0).astype(float)
        clicks *= 0.6 + 0.4 * r.random(n)
        rattle = resonator(clicks, [480, 1250, 2300, 3700], [0.05, 0.04, 0.03, 0.02], [1, 0.8, 0.5, 0.3])
        motor = lp(osc(np.interp(t, [0, 0.3, dur], [60, 110, 100]), n, "saw"), 500) * 0.25
        rumble = lp(white(n, r), 200) * 0.3
        y = (norm(rattle) + motor + norm(rumble) * 0.4) * env_ar(n, 0.15, dur - 0.5, 0.5)
        mix_at(y, slam(156, 80) * 0.6, (dur - 0.45) * SR)
        return room(y, 0.2, seed=157)
    emit("sfx", "rollup_door", [rollup()], -4)

    def solder(seed):
        r = rng(seed)
        dur = 1.3
        n = int(dur * SR)
        hiss = bp(white(n, r), 6000, 0.6) * (0.4 + 0.6 * np.abs(lp(white(n, r), 8)) * 3)
        crack = bp(white(n, r) * (r.random(n) < 0.004) * 8, 3000, 0.5)
        return (norm(hiss) * 0.5 + norm(crack) * 0.6) * env_ar(n, 0.08, dur - 0.3, 0.3)
    emit("sfx", "solder", [solder(160), solder(161)], -10)

    def keyboard(seed):
        r = rng(seed)
        out = np.zeros(int(1.2 * SR))
        tpos = 0.0
        while tpos < 1.0:
            n = int(0.04 * SR)
            exc = white(n, r) * env_exp(n, 0.002)
            k = resonator(exc, [1900 + r.random() * 800, 4200 + r.random() * 600], [0.008, 0.005], [1, 0.5])
            k += 0.4 * lp(white(n, r), 400) * env_exp(n, 0.005)
            big = r.random() < 0.08
            mix_at(out, norm(k) * (1.0 if big else 0.5 + r.random() * 0.3), tpos * SR)
            tpos += 0.06 + r.random() * 0.1 + (0.2 if r.random() < 0.1 else 0)
        return room(out, 0.1, seed=seed + 100)
    emit("sfx", "keyboard", [keyboard(170 + i) for i in range(3)], -8)
    n = int(0.12 * SR)
    emit("sfx", "pc_beep", [lp(osc(1000, n, "square"), 4000) * env_ar(n, 0.002, 0.1, 0.02)], -14)

    def marker(seed):
        r = rng(seed)
        dur = 0.45 + r.random() * 0.2
        n = int(dur * SR)
        f = 1900 + 500 * lp(white(n, r), 6) * 4
        sq = osc(f, n, "saw") * (0.5 + 0.5 * (np.abs(lp(white(n, r), 25)) * 4 > 0.3))
        y = bp(sq, 2400, 1.2) * 0.6 + bp(white(n, r), 5000, 0.8) * 0.4
        return norm(y) * env_ar(n, 0.02, dur - 0.1, 0.1)
    emit("sfx", "marker", [marker(180), marker(181)], -14)
    emit("sfx", "stamp", [room(add(thud(182, 220, 0.25), 0.5 * rustle(183, 0.08, 3000, 0.5)), 0.12, seed=184)], -6)
    emit("sfx", "paper", [rustle(185, 0.4, 3500, 0.35), rustle(186, 0.35, 3000, 0.35)], -12)

    def sit():
        out = np.zeros(int(0.8 * SR))
        mix_at(out, thud(187, 110, 0.3), 0)
        mix_at(out, creak(188, 0.4, 260) * 0.25, 0.05 * SR)
        return room(out, 0.12, seed=189)
    emit("sfx", "sit", [sit()], -7)
    emit("sfx", "switch", [latch(190) * 0.8], -10)
    emit("sfx", "machine_beep", [_seq([blip(1500, 1500, 0.08, "sine", 0.1), blip(1500, 1500, 0.08, "sine", 0.1)], 0.13)], -12)
    emit("sfx", "whoosh", [room(whoosh(1.3, 200, 6000, 191, 0.7), 0.35, 1.5, 0.4, seed=192)], -4)

    emit("sfx", "applause", [applause(4.5, 193)], -5)
    emit("sfx", "crowd_cheer", [crowd_cheer(3.5, 194)], -4)

    def confetti():
        r = rng(195)
        out = np.zeros(int(1.6 * SR))
        n = int(0.06 * SR)
        pop = lp(white(n, r), 2500) * env_exp(n, 0.008) + np.sin(TWO_PI * 90 * np.arange(n) / SR) * env_exp(n, 0.02)
        mix_at(out, norm(pop), 0)
        mix_at(out, rustle(196, 1.3, 4500, 0.08) * 0.35, 0.05 * SR)
        return room(out, 0.2, seed=197)
    emit("sfx", "confetti", [confetti()], -5)


def applause(dur, seed, circular=False):
    r = rng(seed)
    n = int(dur * SR)
    out = np.zeros(n)
    rate = 260
    k = int(rate * dur)
    starts = r.integers(0, n, k)
    clap_len = int(0.012 * SR)
    claps = []
    for c in range(12):
        cr = rng(seed * 100 + c)
        x = bp(white(clap_len * 3, cr), 900 + cr.random() * 1800, 1.2)[:clap_len * 3] * env_exp(clap_len * 3, 0.006 + cr.random() * 0.006, 0.0005)
        claps.append(x)
    for s in starts:
        mix_at(out, claps[r.integers(0, 12)], s, 0.4 + r.random() * 0.6, wrap=circular)
    if not circular:
        t = np.arange(n) / SR
        out *= np.interp(t, [0, 0.4, dur * 0.55, dur], [0, 1, 0.8, 0]) ** 1.2
    return room(out, 0.3, 1.2, 0.35, seed=seed + 1, circular=circular, keep_len=True)


FORMANTS = {  # (F1, F2, F3)
    "a": (750, 1200, 2600), "e": (500, 1800, 2500), "i": (300, 2200, 2900),
    "o": (500, 900, 2400), "u": (350, 800, 2300), "ae": (650, 1700, 2500),
}


def formant_voice(f0, n, vowel, r, breath=0.1):
    f1, f2, f3 = FORMANTS[vowel]
    src = osc(f0, n, "saw", r.random()) + breath * white(n, r)
    y = bp(src, f1, 2.5) + 0.6 * bp(src, f2, 3.0) + 0.25 * bp(src, f3, 3.5)
    return y


def crowd_cheer(dur, seed):
    r = rng(seed)
    n = int(dur * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for v in range(36):
        f0 = (110 + r.random() * 120) if r.random() < 0.6 else (200 + r.random() * 160)
        start = r.random() * 0.4
        length = 1.0 + r.random() * (dur - 1.4)
        m = int(length * SR)
        tm = np.arange(m) / SR
        vib = 1 + 0.02 * np.sin(TWO_PI * (5 + r.random() * 2) * tm)
        rise = 1 + 0.25 * np.clip(tm / 0.3, 0, 1) - 0.15 * np.clip((tm - length * 0.6) / (length * 0.4), 0, 1)
        vow = ["a", "e", "o", "ae"][r.integers(0, 4)]
        y = formant_voice(f0 * vib * rise, m, vow, r, 0.3)
        y = norm(y) * env_ar(m, 0.08, length * 0.5, length * 0.5)
        mix_at(out, y, start * SR, 0.4 + r.random() * 0.6)
    # whistles
    for w in range(3):
        m = int((0.5 + r.random() * 0.5) * SR)
        f = glide(1800 + r.random() * 600, 2800 + r.random() * 600, m, 0.5)
        mix_at(out, osc(f, m) * env_ar(m, 0.03, len(f) / SR - 0.15, 0.15) * 0.25, (0.3 + r.random() * 1.5) * SR)
    breath = bp(white(n, r), 1500, 0.5) * 0.1
    out = norm(out) + breath * np.interp(t, [0, 0.3, dur], [0, 1, 0])
    out = add(out, 0.3 * applause(dur, seed + 5))[:n]
    out *= np.interp(t, [0, 0.2, dur * 0.6, dur], [0, 1, 0.8, 0])
    return room(out, 0.35, 1.5, 0.45, seed=seed + 2)


# ------------------------------------------------------------------------------------------------
# 3D loops (mono, seamless)
# ------------------------------------------------------------------------------------------------
def snapf(f, L):
    """Round a frequency so it completes an integer number of cycles in L seconds (seamless loop)."""
    return max(1, round(f * L)) / L


@gen
def loops():
    L = 8.0
    n = int(L * SR)
    t = np.arange(n) / SR
    r = rng(300)
    # machine hum: transformer hum + motor whine + slow mechanical cycle
    hum = sum(a * np.sin(TWO_PI * snapf(f, L) * t) for f, a in ((60, 1.0), (120, 0.6), (180, 0.3), (240, 0.2), (360, 0.08)))
    whine = 0.05 * np.sin(TWO_PI * snapf(1430, L) * t) * (1 + 0.3 * np.sin(TWO_PI * snapf(0.5, L) * t))
    air = lp(white(n, r), 900, 2, circular=True)
    cycle = 0.5 + 0.5 * np.sin(TWO_PI * snapf(0.75, L) * t) ** 8
    clunk = np.zeros(n)
    for k in range(int(L * 0.75)):
        mix_at(clunk, norm(resonator(np.r_[1.0, np.zeros(int(0.2 * SR))], [210, 530], [0.04, 0.02], [1, 0.4])), (k / 0.75 + 0.3) * SR, 0.3, wrap=True)
    emit("loop", "machine_hum", [hum * 0.5 + whine + norm(air) * 0.25 * cycle + clunk], -8, loop=True)
    # conveyor: rollers rattle + belt seam clicks + motor
    rattle = bp(white(n, r), 1400, 0.8, circular=True) * (0.6 + 0.4 * np.abs(np.sin(TWO_PI * snapf(11, L) * t)))
    seams = np.zeros(n)
    period = 0.5
    for k in range(int(L / period)):
        exc = np.r_[1.0, np.zeros(int(0.1 * SR))]
        mix_at(seams, norm(resonator(exc, [900, 2100], [0.015, 0.01], [1, 0.5])), k * period * SR, 0.6 if k % 2 else 0.4, wrap=True)
    motor = 0.25 * np.sin(TWO_PI * snapf(100, L) * t) + 0.08 * np.sin(TWO_PI * snapf(200, L) * t)
    emit("loop", "conveyor", [norm(rattle) * 0.35 + seams + motor + 0.2 * norm(lp(white(n, r), 250, circular=True))], -9, loop=True)
    # fluorescent buzz: 100 Hz rectified buzz, bright harmonics, rare flicker ticks
    L2 = 6.0
    n2 = int(L2 * SR)
    t2 = np.arange(n2) / SR
    buzz = np.abs(np.sin(TWO_PI * snapf(50, L2) * t2)) ** 0.3
    buzz = hp(buzz - buzz.mean(), 90, circular=True)
    buzz = lp(buzz, 4500, 1, circular=True) * (1 + 0.15 * np.sin(TWO_PI * snapf(0.33, L2) * t2))
    ticks = np.zeros(n2)
    for at in (1.3, 1.36, 4.1):
        mix_at(ticks, latch_tick(rng(int(at * 100))), at * SR, 0.3, wrap=True)
    emit("loop", "fluorescent", [norm(buzz) + ticks], -16, loop=True)
    # van idle
    L3 = 4.0
    n3 = int(L3 * SR)
    t3 = np.arange(n3) / SR
    f = snapf(24, L3)
    pulse = np.maximum(0, np.sin(TWO_PI * f * t3)) ** 6 * (1 + 0.25 * np.sin(TWO_PI * snapf(3, L3) * t3))
    eng = lp(pulse, 800, 2, circular=True) + 0.35 * lp(osc(f * 0.5, n3, "saw"), 250, circular=True)
    eng += 0.05 * bp(white(n3, r), 1800, 0.7, circular=True)
    emit("loop", "van_idle", [eng], -8, loop=True)
    # fridge / pc fan
    L4 = 6.0
    n4 = int(L4 * SR)
    t4 = np.arange(n4) / SR
    fr = 0.6 * np.sin(TWO_PI * snapf(50, L4) * t4) + 0.2 * np.sin(TWO_PI * snapf(100, L4) * t4)
    fan = bp(white(n4, r), 700, 0.5, circular=True)
    emit("loop", "fridge", [fr + norm(fan) * 0.5 + 0.03 * np.sin(TWO_PI * snapf(2200, L4) * t4)], -14, loop=True)
    emit("loop", "crowd_murmur", [murmur(12.0, 310)], -10, loop=True)


def latch_tick(r):
    n = int(0.03 * SR)
    return bp(white(n, r), 3000, 1.0) * env_exp(n, 0.004)


def murmur(L, seed, voices=26):
    r = rng(seed)
    n = int(L * SR)
    out = np.zeros(n)
    vows = list(FORMANTS)
    for v in range(voices):
        f0 = 100 + r.random() * 150
        tpos = r.random() * L
        talked = 0.0
        while talked < L * 0.7:
            m = int((0.09 + r.random() * 0.15) * SR)
            tm = np.arange(m) / SR
            y = formant_voice(f0 * (1 + 0.1 * (r.random() - 0.5)) * (1 - 0.1 * tm), m, vows[r.integers(0, len(vows))], r, 0.4)
            y = norm(y) * np.abs(np.sin(np.pi * tm / tm[-1])) ** 1.5
            mix_at(out, y, tpos * SR, 0.3 + r.random() * 0.4, wrap=True)
            gap = 0.03 + r.random() * 0.05 + (0.5 + r.random() if r.random() < 0.12 else 0)
            tpos = (tpos + m / SR + gap) % L
            talked += m / SR + gap
    out = lp(out, 2500, 2, circular=True)
    return room(norm(out), 0.5, 1.5, 0.5, seed=seed + 1, circular=True, bright=3000)


# ------------------------------------------------------------------------------------------------
# ambience (stereo, seamless)
# ------------------------------------------------------------------------------------------------
def stereo(l, r_):
    return np.stack([l, r_], 1)


def car_pass(dur, r):
    n = int(dur * SR)
    t = np.arange(n) / SR
    y = lp(white(n, r), 500, 2) + 0.4 * lp(osc(np.interp(t, [0, dur], [62, 48]), n, "saw"), 300)
    env = np.exp(-((t - dur / 2) / (dur / 5)) ** 2)
    return norm(y) * env


@gen
def ambience():
    def base_room(L, seed, rumble=0.3, air=0.08, hum=0.04, cars=3, pan_cars=True):
        r = rng(seed)
        n = int(L * SR)
        t = np.arange(n) / SR
        chans = []
        for c in range(2):
            b = lp(brown(n, r), 180, 1, circular=True) * rumble
            a = lp(pink(n, r), 2500, 1, circular=True) * air
            chans.append(b + a)
        h = hum * (np.sin(TWO_PI * snapf(60, L) * t) + 0.5 * np.sin(TWO_PI * snapf(120, L) * t))
        L_, R_ = chans[0] + h, chans[1] + h
        for k in range(cars):
            cp = car_pass(5 + r.random() * 3, r) * 0.25
            start = r.random() * L
            p = r.random()
            mix_at(L_, cp * (1 - p) * 1.4, start * SR, wrap=True)
            mix_at(R_, cp * p * 1.4, start * SR + int(0.15 * SR * (p - 0.5)), wrap=True)
        return L_, R_

    L = 40.0
    l, r_ = base_room(L, 400)
    emit("ambient", "garage", [room_st(l, r_, 401, 0.25, 0.6)], -18, loop=True, q=3)
    l, r_ = base_room(L, 410, rumble=0.25, air=0.12, hum=0.02, cars=5)
    emit("ambient", "loft", [room_st(l, r_, 411, 0.45, 1.4)], -18, loop=True, q=3)
    L2 = 30.0
    l, r_ = base_room(L2, 420, rumble=0.2, air=0.05, hum=0.0, cars=0)
    m1, m2 = murmur(L2, 421, 30), murmur(L2, 422, 30)
    emit("ambient", "stage", [room_st(l + 0.6 * m1, r_ + 0.6 * m2, 423, 0.5, 1.8)], -14, loop=True, q=3)
    # outdoor night: crickets + wind + far traffic
    r = rng(430)
    n = int(L * SR)
    t = np.arange(n) / SR
    chans = [np.zeros(n), np.zeros(n)]
    for c in range(7):
        f = 3800 + r.random() * 1200
        rate = snapf(14 + r.random() * 8, L)       # chirp pulse rate
        group = snapf(0.6 + r.random() * 0.8, L)   # groups of chirps
        gate = (np.sin(TWO_PI * rate * t) > 0.2).astype(float) * (np.sin(TWO_PI * group * t + r.random() * 6) > 0.3)
        gate = lp(gate, 200, 1, circular=True)
        ch = np.sin(TWO_PI * snapf(f, L) * t) * gate * (0.3 + r.random() * 0.4)
        p = r.random()
        chans[0] += ch * (1 - p)
        chans[1] += ch * p
    for c in range(2):
        wind = bp(white(n, r), 500, 0.5, circular=True) * (0.5 + 0.5 * np.abs(lp(white(n, r), 0.3, 1, circular=True)) * 30)
        chans[c] += norm(wind) * 0.35 + lp(brown(n, r), 150, 1, circular=True) * 0.4
    for k in range(4):
        cp = car_pass(7 + r.random() * 3, r) * 0.18
        start = r.random() * L
        p = r.random()
        mix_at(chans[0], cp * (1 - p), start * SR, wrap=True)
        mix_at(chans[1], cp * p, start * SR, wrap=True)
    emit("ambient", "outdoor", [room_st(chans[0], chans[1], 431, 0.3, 1.0)], -16, loop=True, q=3)


def room_st(l, r_, seed, wet, decay):
    irl = reverb_ir(min(decay * 4, 4.0), decay, rng(seed), 4000)
    irr = reverb_ir(min(decay * 4, 4.0), decay, rng(seed + 1), 4000)
    return stereo(l + wet * convolve(l, irl, True), r_ + wet * convolve(r_, irr, True))


# ------------------------------------------------------------------------------------------------
# music (stereo, seamless loops)
# ------------------------------------------------------------------------------------------------
class Song:
    def __init__(self, bpm, bars, seed, swing=0.0):
        self.bpm, self.bars = bpm, bars
        self.beat = 60.0 / bpm
        self.L = self.beat * 4 * bars
        self.n = int(round(self.L * SR))
        self.l = np.zeros(self.n)
        self.r = np.zeros(self.n)
        self.rng = rng(seed)
        self.swing = swing

    def at(self, bar, beat):
        b = beat
        frac = b % 1.0
        if abs(frac - 0.5) < 1e-6 and self.swing:
            b += self.swing * 0.5
        return (bar * 4 + b) * self.beat

    def add(self, x, time, gain=1.0, pan=0.0):
        s = int(round(time * SR)) % self.n
        gl, gr = np.cos((pan + 1) * np.pi / 4), np.sin((pan + 1) * np.pi / 4)
        mix_at(self.l, x, s, gain * gl * 1.414, wrap=True)
        mix_at(self.r, x, s, gain * gr * 1.414, wrap=True)

    def render(self, wet=0.25, decay=0.9, lofi=4500, crackle=0.2, seed=0, wow=True):
        l, r_ = self.l, self.r
        if wow:  # gentle tape wow: resample with a slow sinusoidal time warp (whole cycles -> seamless)
            t = np.arange(self.n)
            dev = 0.0012 * SR * np.sin(TWO_PI * t / self.n * max(1, round(self.L / 2.7)))
            l = np.interp((t + dev) % self.n, t, l, period=self.n)
            r_ = np.interp((t + dev) % self.n, t, r_, period=self.n)
        irl = reverb_ir(3.0, decay, rng(seed + 1), 3500, 0.02)
        irr = reverb_ir(3.0, decay, rng(seed + 2), 3500, 0.025)
        l = l + wet * convolve(l, irl, True)
        r_ = r_ + wet * convolve(r_, irr, True)
        l, r_ = lp(l, lofi, 1, circular=True), lp(r_, lofi, 1, circular=True)
        l, r_ = hp(l, 35, 1, circular=True), hp(r_, 35, 1, circular=True)
        v1, v2 = vinyl(self.n, rng(seed + 3)), vinyl(self.n, rng(seed + 4))
        pk = max(np.max(np.abs(l)), np.max(np.abs(r_)))
        l, r_ = l / pk + crackle * 0.25 * v1, r_ / pk + crackle * 0.25 * v2
        return stereo(softclip(l, 1.2), softclip(r_, 1.2))


def chord_notes(root, kind):
    iv = {"maj7": [0, 4, 7, 11], "m7": [0, 3, 7, 10], "7": [0, 4, 7, 10], "m9": [0, 3, 7, 10, 14],
          "maj9": [0, 4, 7, 11, 14], "9": [0, 4, 7, 10, 14], "m": [0, 3, 7], "M": [0, 4, 7], "sus": [0, 5, 7, 10],
          "m11": [0, 3, 7, 10, 17], "13": [0, 4, 10, 14, 21], "add9": [0, 4, 7, 14]}[kind]
    return [root + i for i in iv]


def voice_chord(notes, lo=55, hi=72):
    out = []
    for m in notes[1:] + notes[:1]:
        while m < lo:
            m += 12
        while m > hi:
            m -= 12
        out.append(m)
    return sorted(set(out))


@gen
def music():
    # ---- menu: slow, dreamy, no drums, rhodes + pad + soft bass, 66 bpm
    s = Song(66, 16, 500)
    prog = [(62, "m9"), (67, "13"), (60, "maj9"), (57, "m11"), (65, "maj9"), (64, "m7"), (62, "m9"), (67, "sus")] * 2
    mel = {9: [(0, 74, 1.5), (2, 72, 1.5)], 11: [(1, 76, 2.5)], 13: [(0, 79, 1), (1.5, 76, 1), (3, 74, 1)], 15: [(0, 72, 3)],
           3: [(2, 69, 2)], 7: [(1, 67, 2.5)]}
    for bar, (root, kind) in enumerate(prog):
        notes = voice_chord(chord_notes(root, kind), 57, 74)
        for i, m in enumerate(notes):
            s.add(rhodes(midi(m), s.beat * 4 + 1.5, 0.55), s.at(bar, 0) + i * 0.025, 0.22, -0.3 + 0.15 * i)
            s.add(pad_voice(midi(m), s.beat * 4.2, s.rng, 1200), s.at(bar, 0), 0.12, 0.4 - 0.2 * i)
        s.add(sub_bass(midi(root - 24 if root - 24 >= 33 else root - 12), s.beat * 3.8), s.at(bar, 0), 0.5)
        for (b, m, d) in mel.get(bar, []):
            s.add(bell(midi(m), s.beat * d + 1.0, 0.25, 0.6), s.at(bar, b), 0.13, 0.2)
        for k in range(8):  # soft shaker texture
            if s.rng.random() < 0.6:
                s.add(shaker(s.rng), s.at(bar, k * 0.5), 0.05 + 0.03 * (k % 2), 0.4)
    emit("music", "menu", [s.render(0.45, 1.6, 3800, 0.25, 501)], -4, loop=True, q=4)

    # ---- game: lo-fi hip hop, 78 bpm, swung drums
    s = Song(78, 16, 510, swing=0.16)
    prog = [(65, "maj9"), (64, "m7"), (62, "m9"), (60, "maj9")] * 2 + [(58, "maj9"), (57, "m7"), (62, "m9"), (67, "13")] * 2
    for bar, (root, kind) in enumerate(prog):
        notes = voice_chord(chord_notes(root, kind), 55, 72)
        for i, m in enumerate(notes):
            s.add(rhodes(midi(m), s.beat * 2 + 1.0, 0.6), s.at(bar, 0) + i * 0.018, 0.2, -0.25 + 0.12 * i)
            if bar % 2 == 1:
                s.add(rhodes(midi(m), s.beat * 1.5 + 0.8, 0.45), s.at(bar, 2.5) + i * 0.015, 0.14, -0.25 + 0.12 * i)
        broot = root - 24 if root - 24 >= 33 else root - 12
        for (b, d, off) in ((0, 1.4, 0), (1.5, 0.45, 0), (2.5, 1.2, 7 if bar % 4 == 3 else 0)):
            s.add(sub_bass(midi(broot + off), s.beat * d), s.at(bar, b), 0.55)
        # drums
        s.add(kick(s.rng), s.at(bar, 0), 0.75)
        s.add(kick(s.rng), s.at(bar, 1.5 if bar % 2 else 2.5), 0.55)
        if bar % 4 == 3:
            s.add(kick(s.rng), s.at(bar, 2.75), 0.4)
        s.add(snare(s.rng, True), s.at(bar, 1), 0.5, 0.05)
        s.add(snare(s.rng, True), s.at(bar, 3), 0.5, 0.05)
        for k in range(8):
            s.add(hat(s.rng, k == 7 and bar % 2 == 1), s.at(bar, k * 0.5), 0.12 if k % 2 == 0 else 0.07, 0.25)
        # melody in the second half: pentatonic noodles on a soft pluck
        if bar >= 8:
            scale = [72, 74, 76, 79, 81, 84]
            for k in range(4):
                if s.rng.random() < 0.55:
                    m = scale[s.rng.integers(0, len(scale))]
                    s.add(bell(midi(m), s.beat * 1.5, 0.35, 0.35), s.at(bar, k + (0.5 if s.rng.random() < 0.3 else 0)), 0.1, 0.3)
    emit("music", "game", [s.render(0.3, 1.0, 4200, 0.3, 511)], -4, loop=True, q=4)

    # ---- launch: brighter, 92 bpm, arps + punchy drums
    s = Song(92, 16, 520, swing=0.08)
    prog = [(57, "m7"), (65, "maj7"), (60, "add9"), (67, "M")] * 4
    for bar, (root, kind) in enumerate(prog):
        notes = voice_chord(chord_notes(root, kind), 57, 76)
        for i, m in enumerate(notes):
            s.add(pad_voice(midi(m), s.beat * 4.2, s.rng, 2200), s.at(bar, 0), 0.13, -0.4 + 0.25 * i)
        arp = notes + [notes[0] + 12]
        for k in range(8):
            m = arp[(k if (bar // 2) % 2 == 0 else 7 - k) % len(arp)] + 12
            s.add(pluck(midi(m), 0.4, 3500), s.at(bar, k * 0.5), 0.12, 0.35 if k % 2 else -0.35)
        broot = root - 24 if root - 24 >= 33 else root - 12
        for b in (0, 1.5, 2, 3.5):
            s.add(sub_bass(midi(broot), s.beat * 0.9), s.at(bar, b), 0.5)
        if bar >= 2:
            s.add(kick(s.rng, 1.2), s.at(bar, 0), 0.8)
            s.add(kick(s.rng, 1.2), s.at(bar, 2), 0.7)
            if bar % 2:
                s.add(kick(s.rng, 1.2), s.at(bar, 2.5), 0.5)
            s.add(snare(s.rng), s.at(bar, 1), 0.5)
            s.add(snare(s.rng), s.at(bar, 3), 0.5)
            for k in range(8):
                s.add(hat(s.rng, k % 4 == 3), s.at(bar, k * 0.5), 0.13 if k % 2 else 0.08, -0.2)
        if bar % 8 == 7:
            for k in range(4):
                s.add(snare(s.rng), s.at(bar, 3 + k * 0.25), 0.2 + k * 0.08)
    emit("music", "launch", [s.render(0.25, 1.1, 6000, 0.15, 521)], -4, loop=True, q=4)


# ------------------------------------------------------------------------------------------------
# robot "blah-blah" voice syllables (runtime pitches them per user)
# ------------------------------------------------------------------------------------------------
@gen
def voice():
    r = rng(600)
    sylls = []
    cons = ["b", "m", "n", "d", "t", "k", "", "l"]
    vows = ["a", "e", "i", "o", "u", "ae"]
    for k in range(12):
        c = cons[k % len(cons)]
        v = vows[(k * 5) % len(vows)]
        dur = 0.14
        n = int(dur * SR)
        tm = np.arange(n) / SR
        f0 = 220 * (1 + 0.04 * np.sin(TWO_PI * 6 * tm)) * glide(1.06, 0.94, n)
        src = 0.6 * osc(f0, n, "square") + 0.4 * osc(f0, n, "saw")
        f1, f2, f3 = FORMANTS[v]
        y = bp(src, f1, 2.2) + 0.7 * bp(src, f2, 2.8) + 0.3 * bp(src, f3, 3.2)
        y = norm(y) * env_ar(n, 0.012, dur - 0.05, 0.05)
        onset = np.zeros(n)
        m = int(0.025 * SR)
        if c in ("t", "k", "d"):
            onset[:m] = bp(white(m, r), {"t": 4000, "k": 2200, "d": 1500}[c], 1.2) * env_exp(m, 0.006)
            y[:m] *= np.linspace(0, 1, m)
        elif c in ("m", "n", "b", "l"):
            onset[:m] = np.sin(TWO_PI * np.cumsum(f0[:m]) / SR) * np.linspace(0.6, 0.2, m)
            y[:m] *= np.linspace(0, 1, m)
        y = y + onset * 0.7
        # bitcrush a little: robot flavour
        y = np.round(y * 24) / 24
        sylls.append(lp(y, 6000))
    emit("voice", "voice_blip", sylls, -6)


# ------------------------------------------------------------------------------------------------
def write_bank():
    lines = ["extends RefCounted", "## GENERATED by client/audio/gen/make_audio.py - do not edit by hand.", "",
             "const SOUNDS := {"]
    for name in sorted(OUT):
        lines.append('\t"%s": [%s],' % (name, ", ".join('"%s"' % p for p in OUT[name])))
    lines.append("}")
    lines.append("")
    lines.append("const KIND := {")
    for name in sorted(KIND):
        lines.append('\t"%s": "%s",' % (name, KIND[name]))
    lines.append("}")
    lines.append("")
    lines.append("const LOOPS := [%s]" % ", ".join('"%s"' % n for n in sorted(LOOPS)))
    with open(os.path.join(AUDIO, "bank_data.gd"), "w") as f:
        f.write("\n".join(lines) + "\n")


def main():
    global SELECT
    if len(sys.argv) > 1:
        SELECT = set(sys.argv[1:])
    for g in GENERATORS:
        print("..", g.__name__, flush=True)
        g()
    write_bank()
    total = 0
    for root, _, files in os.walk(AUDIO):
        for f in files:
            if f.endswith(".ogg"):
                total += os.path.getsize(os.path.join(root, f))
    print("sounds: %d names, total ogg size %.2f MB" % (len(OUT), total / 1e6))


if __name__ == "__main__":
    main()
