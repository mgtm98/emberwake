#!/usr/bin/env python3
"""EMBERWAKE procedural audio (numpy only).

Synthesizes every sound effect (assets/sfx/*.wav, 44.1 kHz mono 16-bit) and
music loop (assets/music/*.wav, 22.05 kHz stereo 16-bit), then verifies them.
When ffmpeg (with libvorbis) or oggenc is on PATH, each music loop is also
written as .ogg next to the .wav.

    python3 tools/gen_audio.py                # regenerate everything
    python3 tools/gen_audio.py laser boss     # only the named sounds
    python3 tools/gen_audio.py --verify       # only check the existing files
    python3 tools/gen_audio.py --stats ch1    # also print per-part mix levels

Music loops are seamless: every track is rendered on a fixed bar grid with
extra tail time, and the tail (note releases, reverb, echoes) is wrapped back
onto the head, so the end of the file flows into its start.
"""
import os
import shutil
import subprocess
import sys
import time
import wave
import zlib
from functools import lru_cache

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SFX_DIR = os.path.join(ROOT, "assets", "sfx")
MUS_DIR = os.path.join(ROOT, "assets", "music")
SR_SFX, SR_MUS = 44100, 22050
SEED = 0xE3B3
TAU = 2.0 * np.pi
STATS = False


def rng_for(*key):
    """Deterministic RNG per sound, independent of generation order."""
    return np.random.default_rng((zlib.crc32(repr(key).encode()) ^ SEED) & 0xFFFFFFFF)


# ------------------------------------------------------------------ pitch

_PC = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def note(s):
    """'C#4' / 'Bb2' -> MIDI number (A4 = 69)."""
    v, i = _PC[s[0]], 1
    while i < len(s) and s[i] in "#b":
        v += 1 if s[i] == "#" else -1
        i += 1
    return v + 12 * (int(s[i:]) + 1)


def notes(s):
    return [note(x) for x in s.split()]


def hz(m):
    return 440.0 * 2.0 ** ((np.asarray(m, float) - 69.0) / 12.0)


MINOR = [0, 2, 3, 5, 7, 8, 10]
MAJOR = [0, 2, 4, 5, 7, 9, 11]


def deg(tonic, scale, d):
    return tonic + 12 * (d // 7) + scale[d % 7]


# ------------------------------------------------------------ oscillators

def _blep(t, dt):
    """PolyBLEP residual: removes most aliasing from saw/square edges."""
    y = np.zeros_like(t)
    m = t < dt
    x = t[m] / dt[m]
    y[m] = x + x - x * x - 1.0
    m = t > 1.0 - dt
    x = (t[m] - 1.0) / dt[m]
    y[m] = x * x + x + x + 1.0
    return y


def osc(kind, freq, n, sr, ph0=0.0):
    """Oscillator; freq is a scalar or a per-sample array (sweeps)."""
    f = np.asarray(freq, float)
    if f.ndim == 0:
        t = (ph0 + np.arange(n) * (float(f) / sr)) % 1.0
    else:
        t = (ph0 + np.cumsum(f[:n]) / sr) % 1.0
    if kind == "sin":
        return np.sin(TAU * t)
    if kind == "tri":
        return 4.0 * np.abs(t - 0.5) - 1.0
    dt = np.broadcast_to(np.minimum(np.abs(f) / sr, 0.5), t.shape)
    if kind == "saw":
        return 2.0 * t - 1.0 - _blep(t, dt)
    if kind == "sqr":
        return np.where(t < 0.5, 1.0, -1.0) + _blep(t, dt) - _blep((t + 0.5) % 1.0, dt)
    raise ValueError(kind)


def sweep_sin(f, sr):
    """Sine following a per-sample frequency curve."""
    return np.sin(TAU * np.cumsum(f) / sr)


def white(n, rng):
    return rng.uniform(-1.0, 1.0, n)


# -------------------------------------------------------------- envelopes

def adsr(n_on, n, sr, a=0.005, d=0.1, s=0.7, r=0.1):
    """ADSR over n samples; the gate closes at n_on, release ends at exactly 0."""
    t = np.arange(n) / sr
    a, d, r = max(a, 1e-4), max(d, 1e-4), max(r, 1e-4)

    def ads(x):
        return np.where(x < a, x / a, s + (1.0 - s) * np.exp(-(x - a) * 5.0 / d))

    ton = n_on / sr
    voff = float(ads(np.array(ton)))
    u = np.clip((t - ton) / r, 0.0, 1.0)
    return np.where(t < ton, ads(t), voff * np.exp(-4.0 * u) * (1.0 - u))


def decay(n, sr, tau, attack=0.001):
    t = np.arange(n) / sr
    return np.minimum(t / attack, 1.0) * np.exp(-t / tau)


def fade(x, sr, fin=0.002, fout=0.01):
    x = np.array(x, float)
    n = x.shape[-1]
    a, b = min(int(fin * sr), n), min(int(fout * sr), n)
    if a > 0:
        x[..., :a] *= np.linspace(0.0, 1.0, a)
    if b > 0:
        x[..., n - b:] *= np.linspace(1.0, 0.0, b)
    return x


# ---------------------------------------------------------------- filters
# All recursive filters reduce to the first-order recurrence
#     y[n] = p[n] * y[n-1] + x[n]
# (p real for one-pole filters, complex for resonant two-pole ones). It is
# solved in chunks with cumprod/cumsum, so time-varying cutoffs stay vectorized.

def _scan(p, x, chunk=64):
    x = np.asarray(x)
    n = len(x)
    dt = np.result_type(np.asarray(p), x, np.float64)
    p = np.broadcast_to(np.asarray(p, dt), (n,))
    pad = (-n) % chunk
    X = np.concatenate([x.astype(dt), np.zeros(pad, dt)]).reshape(-1, chunk)
    P = np.cumprod(np.concatenate([p, np.ones(pad, dt)]).reshape(-1, chunk), axis=1)
    Y = P * np.cumsum(X / P, axis=1)            # each chunk from a zero state
    lastY, lastP = Y[:, -1].tolist(), P[:, -1].tolist()
    state, acc = [0.0] * len(lastY), 0.0
    for k in range(len(lastY)):                 # carry the state across chunks
        state[k] = acc
        acc = lastY[k] + lastP[k] * acc
    Y += P * np.asarray(state, dt)[:, None]
    return Y.ravel()[:n]


def lp1(x, fc, sr):
    p = np.exp(-TAU * np.clip(fc, 1.0, 0.45 * sr) / sr)
    return _scan(p, (1.0 - p) * x)


def hp1(x, fc, sr):
    return x - lp1(x, fc, sr)


def _pole(fc, sr, q):
    w = TAU * np.clip(fc, 20.0, 0.42 * sr) / sr
    q = max(q, 0.55)
    return np.exp(-w / (2 * q)) * np.exp(1j * w * np.sqrt(1.0 - 1.0 / (4 * q * q)))


def _allpole2(x, p):
    """1 / ((1 - p z^-1)(1 - p* z^-1)) via partial fractions on a complex one-pole."""
    a = p / (p - np.conj(p))
    return 2.0 * np.real(a * _scan(p, np.asarray(x, complex)))


def lp2(x, fc, sr, q=0.707):
    """Resonant 2-pole low-pass, unity DC gain; fc may be a per-sample array."""
    p = _pole(fc, sr, q)
    return _allpole2(x, p) * np.abs(1.0 - p) ** 2


def bp2(x, fc, sr, bw):
    """2-pole band-pass (zeros at DC and Nyquist), ~unity peak gain."""
    th = TAU * np.clip(fc, 20.0, 0.45 * sr) / sr
    r = np.exp(-np.pi * np.clip(bw, 5.0, sr / 4) / sr)
    y = _allpole2(x, r * np.exp(1j * th))
    out = y.copy()
    out[2:] -= y[:-2]
    return out * (1.0 - r * r) / 2.0


def drive(x, k):
    return np.tanh(k * x) / np.tanh(k)


def fftconv(x, h):
    n = len(x) + len(h) - 1
    nf = 1 << (n - 1).bit_length()
    return np.fft.irfft(np.fft.rfft(x, nf) * np.fft.rfft(h, nf), nf)[:n]


# ---------------------------------------------------------- reverb / echo

def reverb_ir(sr, length, rng, damp=0.35):
    """Synthetic hall: decaying noise, highs dying faster than lows."""
    n = int(sr * length * 1.15)
    t = np.arange(n) / sr
    w = rng.standard_normal(n)
    lo = lp1(w, 1600.0, sr)
    ir = lo * np.exp(-6.9 * t / length) + (w - lo) * np.exp(-6.9 * t / (length * damp))
    pre = int(0.012 * sr)
    ir = np.concatenate([np.zeros(pre), ir * np.minimum(t / 0.025, 1.0)])
    return ir / np.sqrt(np.sum(ir * ir))


def echo_ir(sr, delay, fb, side, taps=8, damp=3500.0):
    """Ping-pong echo: side 0 gets odd repeats, side 1 even ones, each darker."""
    d = int(delay * sr)
    h = np.zeros(d * taps + 512)
    k = np.zeros(512)
    k[0] = 1.0
    for i in range(1, taps + 1):
        k = lp1(k, damp, sr)
        if i % 2 == (1 - side):
            h[i * d:i * d + 512] += k * fb ** (i - 1)
    return h


def loop_noise(n, sr, lo, hi, rng):
    """Band-limited noise that is exactly periodic over n samples (FFT-filtered)."""
    spec = np.fft.rfft(rng.standard_normal(n))
    f = np.fft.rfftfreq(n, 1.0 / sr) + 1e-3
    spec *= 1.0 / (1.0 + (lo / f) ** 4) / (1.0 + (f / hi) ** 4)
    y = np.fft.irfft(spec, n)
    return y / (np.std(y) + 1e-12)


# ============================================================== instruments
# inst(midi, dur_seconds, vel, sr, **params) -> mono (n,) or stereo (2, n),
# including its release tail.

def _len(dur, rel, sr):
    n_on = max(1, int(dur * sr))
    return n_on, n_on + int(rel * sr)


def inst_pluck(m, dur, vel, sr, bright=1.0, dec=0.16, q=1.5, rel=0.06, wave="saw", sus=0.3):
    f = float(hz(m))
    n_on, n = _len(dur, rel, sr)
    t = np.arange(n) / sr
    x = 0.5 * (osc(wave, f * 1.004, n, sr) + osc(wave, f * 0.996, n, sr, 0.37))
    y = lp2(x, f * 1.5 + 300 + bright * vel * 5000 * np.exp(-t / dec), sr, q)
    return y * adsr(n_on, n, sr, 0.002, dec * 1.5, sus, rel) * vel


def inst_bass(m, dur, vel, sr, wave="saw", base=2.5, env=8.0, dec=0.1, q=1.0, drv=1.5,
              sub=0.6, a=0.003, rel=0.05, sus=0.8):
    f = float(hz(m))
    n_on, n = _len(dur, rel, sr)
    t = np.arange(n) / sr
    x = osc(wave, f, n, sr) + sub * osc("sin", f, n, sr)
    y = drive(lp2(x, f * (base + env * vel * np.exp(-t / dec)), sr, q), drv)
    return y * adsr(n_on, n, sr, a, 0.25, sus, rel) * vel


def inst_sub(m, dur, vel, sr, a=0.08, rel=0.5, tri=0.15):
    f = float(hz(m))
    n_on, n = _len(dur, rel, sr)
    x = osc("sin", f, n, sr) + tri * osc("tri", f, n, sr)
    return x * adsr(n_on, n, sr, a, 0.5, 1.0, rel) * vel


def inst_lead(m, dur, vel, sr, saw=0.6, sqr=0.4, tri=0.0, sub=0.0, bright=4.0, q=1.0,
              vib=0.15, rate=5.5, a=0.02, d=0.3, sus=0.8, rel=0.25):
    f = float(hz(m))
    n_on, n = _len(dur, rel, sr)
    t = np.arange(n) / sr
    ramp = np.clip((t - 0.2) / 0.4, 0.0, 1.0)            # delayed vibrato
    fm = f * 2.0 ** (vib * ramp * np.sin(TAU * rate * t) / 12.0)
    x = np.zeros(n)
    if saw:
        x += saw * osc("saw", fm * 1.003, n, sr)
    if sqr:
        x += sqr * osc("sqr", fm * 0.997, n, sr, 0.25)
    if tri:
        x += tri * osc("tri", fm, n, sr)
    if sub:
        x += sub * osc("sin", fm * 0.5, n, sr)
    y = lp2(x, f * bright * (1.0 + 1.2 * np.exp(-t / 0.12)) + 300, sr, q)
    return y * adsr(n_on, n, sr, a, d, sus, rel) * vel


def inst_pad(m, dur, vel, sr, voices=5, spread=0.15, wave="saw", cut=3.0, q=0.8, a=0.6,
             rel=1.5, sus=0.9, lfo=0.13, width=0.85):
    """Detuned supersaw-style pad, voices spread across the stereo field."""
    f = float(hz(m))
    n_on, n = _len(dur, rel, sr)
    t = np.arange(n) / sr
    rng = rng_for("pad", m, voices)
    out = np.zeros((2, n))
    for v in range(voices):
        k = v / (voices - 1) * 2 - 1 if voices > 1 else 0.0
        x = osc(wave, f * 2.0 ** (spread * k / 12.0), n, sr, rng.random())
        ang = (width * k + 1.0) * np.pi / 4
        out[0] += np.cos(ang) * x
        out[1] += np.sin(ang) * x
    fc = min(f * cut + 250, 0.4 * sr) * (1.0 + 0.25 * np.sin(TAU * lfo * t + rng.random() * TAU))
    out[0], out[1] = lp2(out[0], fc, sr, q), lp2(out[1], fc, sr, q)
    return out * adsr(n_on, n, sr, a, 1.0, sus, rel) * (vel * np.sqrt(2.0 / voices))


# The Choir's voice: near-harmonic sine partials plus a faint inharmonic one,
# two copies detuned a few cents so the chord beats slowly like glass.
GLASS = ((1.0, 1.0), (2.0, 0.3), (3.0, 0.12), (4.95, 0.04))


def inst_glass(m, dur, vel, sr, a=1.5, rel=2.5, cents=6.0, trem=4.0):
    f = float(hz(m))
    n_on, n = _len(dur, rel, sr)
    t = np.arange(n) / sr
    rng = rng_for("glass", m)
    ch = []
    for side, c in enumerate((-cents, cents)):
        fv = f * 2.0 ** (c / 1200.0)
        y = 0.35 * osc("tri", fv, n, sr, rng.random())
        for k, amp in GLASS:
            if fv * k < 0.45 * sr:
                y += amp * np.sin(TAU * fv * k * t + rng.random() * TAU)
        ch.append(y * (1.0 + 0.15 * np.sin(TAU * (trem + 0.3 * side) * t + 1.7 * side)))
    out = np.vstack([0.85 * ch[0] + 0.35 * ch[1], 0.85 * ch[1] + 0.35 * ch[0]])
    return out * adsr(n_on, n, sr, a, 1.0, 1.0, rel) * (vel * 0.4)


def inst_bell(m, dur, vel, sr, ratio=3.5, index=2.0, dec=1.2, bright=0.3):
    """Two-operator FM bell; rings for its own decay regardless of note length."""
    f = float(hz(m))
    n = int((dur + dec * 3.0) * sr)
    t = np.arange(n) / sr
    idx = index * min(1.0, 1500.0 / f) * np.exp(-t / (dec * 0.25))
    y = np.sin(TAU * f * t + idx * np.sin(TAU * f * ratio * t))
    if 2 * f < 0.45 * sr:
        y += bright * np.sin(TAU * 2 * f * t) * np.exp(-t / (dec * 0.3))
    return fade(y * decay(n, sr, dec, 0.002) * vel, sr, 0.0, 0.05)


# ------------------------------------------------------------------ drums
# Cached one-shots normalized to peak 1; `var` selects a different noise seed.

def _peak1(y):
    return y / (np.max(np.abs(y)) + 1e-12)


def hp2(x, fc, sr):
    """Steeper high-pass: the input minus its resonance-free 2-pole low-pass."""
    return x - lp2(x, fc, sr, 0.6)


@lru_cache(None)
def d_kick(sr, f0=150.0, f1=45.0, pdec=0.035, dec=0.3, click=0.3, drv=1.6, var=0):
    n = int(sr * dec * 3.5)
    t = np.arange(n) / sr
    body = sweep_sin(f1 + (f0 - f1) * np.exp(-t / pdec), sr) * np.exp(-t / dec)
    cl = hp1(white(n, rng_for("kick", var)), 1500.0, sr) * np.exp(-t / 0.004) * click
    return _peak1(fade(drive(body + cl, drv), sr, 0.0005, 0.02))


@lru_cache(None)
def d_snare(sr, tone=185.0, dec=0.17, noise=1.0, drv=1.2, var=0):
    n = int(sr * dec * 4)
    t = np.arange(n) / sr
    nz = hp1(lp1(white(n, rng_for("snare", var)), 9000.0, sr), 900.0, sr) * np.exp(-t / dec)
    f = tone * (1.0 + 0.3 * np.exp(-t / 0.01))
    body = (sweep_sin(f, sr) + 0.5 * sweep_sin(f * 1.78, sr)) * np.exp(-t / 0.06)
    return _peak1(fade(drive(0.9 * noise * nz + 0.6 * body, drv), sr, 0.0005, 0.02))


@lru_cache(None)
def d_hat(sr, dec=0.045, var=0, metal=0.3):
    n = int(sr * max(dec * 6, 0.06))
    w = white(n, rng_for("hat", var))
    if metal:
        sq = sum(osc("sqr", f, n, sr) for f in (205.3, 304.4, 369.6, 522.7, 540.0, 800.0))
        w = (1 - metal) * w + metal * sq / 3.0
    y = hp2(hp1(w, 3000.0, sr), 5500.0, sr)
    return _peak1(fade(y * decay(n, sr, dec, 0.0005), sr, 0.0, 0.01))


@lru_cache(None)
def d_clap(sr, dec=0.12, var=0):
    n = int(sr * 0.5)
    t = np.arange(n) / sr
    env = sum(np.where(t >= o, np.exp(-(t - o) / 0.004), 0.0) for o in (0.0, 0.011, 0.022))
    env += np.where(t >= 0.03, np.exp(-(t - 0.03) / dec), 0.0)
    return _peak1(fade(bp2(white(n, rng_for("clap", var)), 1300.0, sr, 1400.0) * env, sr, 0.0, 0.02))


@lru_cache(None)
def d_rim(sr, var=0):
    n = int(sr * 0.08)
    t = np.arange(n) / sr
    y = bp2(white(n, rng_for("rim", var)), 2200.0, sr, 1500.0) * np.exp(-t / 0.006) * 2.0
    y += 0.6 * np.sin(TAU * 820.0 * t) * np.exp(-t / 0.015)
    return _peak1(fade(y, sr, 0.0, 0.01))


@lru_cache(None)
def d_tom(sr, f=100.0, dec=0.32, var=0):
    n = int(sr * dec * 3.5)
    t = np.arange(n) / sr
    y = sweep_sin(f * (1.0 + 0.6 * np.exp(-t / 0.05)), sr) * np.exp(-t / dec)
    y += 0.25 * lp1(white(n, rng_for("tom", var)), 3000.0, sr) * np.exp(-t / 0.03)
    return _peak1(fade(drive(y, 1.3), sr, 0.0005, 0.02))


@lru_cache(None)
def d_crash(sr, dec=1.6, var=0):
    n = int(sr * dec * 3.5)
    t = np.arange(n) / sr
    w = white(n, rng_for("crash", var))
    sq = sum(osc("sqr", f, n, sr) for f in (511.0, 743.0, 1032.0, 1487.0)) / 4.0
    y = hp2(0.7 * w + 0.3 * sq * w, 3500.0, sr)
    return _peak1(fade(y * decay(n, sr, dec, 0.001) * (1.0 + 1.5 * np.exp(-t / 0.08)), sr, 0.0, 0.1))


@lru_cache(None)
def d_metal(sr, f=420.0, ratio=1.414, dec=0.15, var=0):
    """Clank: ring-modulated squares plus an FM 'anvil' partial."""
    n = int(sr * dec * 4)
    t = np.arange(n) / sr
    ring = osc("sqr", f, n, sr) * osc("sqr", f * ratio, n, sr, 0.3)
    fm = np.sin(TAU * f * t + 2.5 * np.exp(-t / 0.03) * np.sin(TAU * f * 2.41 * t))
    y = 0.6 * bp2(ring, f * 3.0, sr, f * 2.0) + 0.5 * fm
    y += 0.3 * hp1(white(n, rng_for("metal", var)), 4000.0, sr) * np.exp(-t / 0.004)
    return _peak1(fade(y * decay(n, sr, dec, 0.0005), sr, 0.0, 0.02))


@lru_cache(None)
def d_riser(sr, length, f0=400.0, f1=6000.0, var=0):
    n = int(sr * length)
    u = np.arange(n) / n
    fc = f0 * (f1 / f0) ** u
    y = bp2(white(n, rng_for("riser", var)), fc, sr, fc * 0.6) * u ** 2
    return fade(y / (np.max(np.abs(y)) + 1e-9), sr, 0.0, 0.01)


@lru_cache(None)
def d_swell(sr, length, var=0):
    """Reverse-cymbal swell that stops dead on the downbeat."""
    n = int(sr * length)
    u = np.arange(n) / n
    y = hp1(white(n, rng_for("swell", var)), 3000.0, sr) * u ** 3
    return fade(y / (np.max(np.abs(y)) + 1e-9), sr, 0.0, 0.005)


@lru_cache(None)
def d_steam(sr, length=1.2, var=0):
    n = int(sr * length)
    t = np.arange(n) / sr
    y = bp2(white(n, rng_for("steam", var)), 5000.0, sr, 4000.0)
    y *= np.minimum(t / 0.08, 1.0) * np.exp(-t / (length * 0.3))
    return fade(y / (np.max(np.abs(y)) + 1e-9), sr, 0.0, 0.05)


# =============================================================== sequencer

def P(root, voicing):
    """A chord: (bass root, voicing notes)."""
    return (note(root), notes(voicing))


# Ember's theme: scale degrees (0 = tonic) and lengths in beats. Phrase A is the
# 8-note motif, phrase B its answer. Every chapter that uses it harmonizes it
# i-VII-VI-VII (minor) or I-V-IV-V (major).
THEME_A = [(4, 1.5), (3, 0.5), (2, 1), (0, 1), (1, 1), (2, 0.5), (1, 0.5), (-1, 2)]
THEME_B = [(4, 1.5), (3, 0.5), (2, 1), (4, 1), (3, 1), (2, 0.5), (1, 0.5), (0, 2)]


def theme(tonic, scale, beat0, phrase=None, shift=0, vel=1.0, legato=0.92, stretch=1.0):
    """Note events for the theme; shift=-2 gives a diatonic third below."""
    ev, b = [], beat0
    for d, length in phrase or THEME_A + THEME_B:
        ev.append((b, length * stretch * legato, deg(tonic, scale, d + shift), vel))
        b += length * stretch
    return ev


def line(beat0, spec, vel=1.0, legato=0.95):
    """'G5:4 A5:2 -:2 B5:1' -> note events ('-' is a rest)."""
    ev, b = [], beat0
    for tok in spec.split():
        name, length = tok.split(":")
        length = float(length)
        if name != "-":
            ev.append((b, length * legato, note(name), vel))
        b += length
    return ev


_VEL = {"x": 1.0, "X": 1.25, "o": 0.6, "g": 0.35}


def hits(pattern, bars, step=0.25, offset=0.0):
    """Drum pattern string (x accent, o medium, g ghost, . rest) per bar."""
    p = pattern.replace(" ", "")
    return [(bar * 4 + offset + i * step, _VEL[c]) for bar in bars for i, c in enumerate(p) if c in _VEL]


def arp_ev(harm, bars, pattern, step=0.25, gate=0.8, vel=1.0, accent=(1.0,), octave=0, span=3):
    ev = []
    for bar in bars:
        c = harm[bar][1]
        ext = [m + 12 * o for o in range(span) for m in c]
        for i, ix in enumerate(pattern):
            ev.append((bar * 4 + i * step, step * gate, ext[ix] + 12 * octave,
                       vel * accent[i % len(accent)]))
    return ev


def bass_ev(harm, bars, pattern, step=0.5, gate=0.8, vel=1.0, accent=(1.0,)):
    """pattern: semitone offsets from the bar's root, None = rest."""
    return [(bar * 4 + i * step, step * gate, harm[bar][0] + p, vel * accent[i % len(accent)])
            for bar in bars for i, p in enumerate(pattern) if p is not None]


def pad_ev(harm, bars, vel=1.0, octave=0):
    """Hold each chord for as many consecutive bars as it lasts."""
    bars, ev, i = list(bars), [], 0
    while i < len(bars):
        j = i
        while j + 1 < len(bars) and bars[j + 1] == bars[j] + 1 and harm[bars[j + 1]] == harm[bars[i]]:
            j += 1
        for m in harm[bars[i]][1]:
            ev.append((bars[i] * 4, (j - i + 1) * 4, m + 12 * octave, vel))
        i = j + 1
    return ev


def chord_at(beat, beats, voicing, vel=1.0):
    return [(beat, beats, m, vel) for m in notes(voicing)]


class Song:
    """A loop of `bars` 4/4 bars. Parts are placed onto dry/reverb/echo buses."""

    def __init__(self, name, bpm, bars, rev=2.5, dly=0.75, fb=0.35, damp=0.35, tail=12.0, sr=SR_MUS):
        self.name, self.sr, self.spb = name, sr, 60.0 / bpm
        self.beats = bars * 4
        self.L = int(round(self.beats * self.spb * sr))
        self.N = self.L + int(tail * sr)
        self.bus = {k: np.zeros((2, self.N)) for k in ("dry", "rev", "dly")}
        self.fx = (rev, dly, fb, damp)
        self.cache, self.stats, self.pump = {}, {}, None
        self.rng = rng_for("song", name)

    def at(self, beat):
        return int(round(beat * self.spb * self.sr))

    def add(self, sig, beat, gain=1.0, pan=0.0, rev=0.0, dly=0.0, duck=False, part="misc"):
        i = self.at(beat)
        if i >= self.N or i < 0:
            return
        if sig.ndim == 1:
            ang = (pan + 1.0) * np.pi / 4
            st = np.vstack([np.cos(ang) * sig, np.sin(ang) * sig]) * np.sqrt(2.0)
        else:
            st = sig * np.array([[min(1.0, 1.0 - pan)], [min(1.0, 1.0 + pan)]])
        n = min(st.shape[1], self.N - i)
        st = st[:, :n] * gain
        if duck and self.pump is not None:
            st = st * self.pump[i:i + n]
        self.bus["dry"][:, i:i + n] += st
        if rev:
            self.bus["rev"][:, i:i + n] += rev * st
        if dly:
            self.bus["dly"][:, i:i + n] += dly * st
        if STATS:
            self._stat(part, st)

    def _stat(self, part, st):
        """Loudness-ish energy: the mono sum with lows rolled off below ~120 Hz."""
        w = hp1(hp1(st.sum(axis=0), 120.0, self.sr), 120.0, self.sr)
        self.stats[part] = self.stats.get(part, 0.0) + float(np.sum(w * w))

    def play(self, inst, events, part, gain=1.0, pan=0.0, rev=0.0, dly=0.0, duck=False, **kw):
        for b, d, m, v in events:
            key = (inst.__name__, m, round(d, 4), round(v, 3), tuple(sorted(kw.items())))
            sig = self.cache.get(key)
            if sig is None:
                sig = self.cache[key] = inst(m, d * self.spb, v, self.sr, **kw)
            self.add(sig, b, gain, pan, rev, dly, duck, part)

    def hit(self, sigs, events, part, gain=1.0, pan=0.0, rev=0.0, dly=0.0, duck=False):
        sigs = sigs if isinstance(sigs, list) else [sigs]
        pans = pan if isinstance(pan, (list, tuple)) else [pan]
        for k, (b, v) in enumerate(events):
            self.add(sigs[k % len(sigs)], b, gain * v, pans[k % len(pans)], rev, dly, duck, part)

    def add_loop(self, sig, gain=1.0, rev=0.0, part="ambience"):
        """A texture exactly one loop long (already periodic)."""
        st = (sig if sig.ndim == 2 else np.vstack([sig, sig]))[:, :self.L] * gain
        self.bus["dry"][:, :self.L] += st
        if rev:
            self.bus["rev"][:, :self.L] += rev * st
        if STATS:
            self._stat(part, st)

    def stereo_noise(self, lo, hi, cycles=2):
        g = [loop_noise(self.L, self.sr, lo, hi, self.rng) for _ in range(2)]
        u = np.arange(self.L) / self.L
        lfo = 0.6 + 0.4 * np.sin(TAU * cycles * u)
        return np.vstack(g) * lfo

    def set_pump(self, beats, depth=0.45, release=0.16):
        """Sidechain-style ducking keyed to the given beats (and their next-loop copies)."""
        imp = np.zeros(self.N)
        for b in beats:
            for off in (0, self.beats):
                i = self.at(b + off)
                if i < self.N:
                    imp[i] = 1.0
        t = np.arange(int(release * 5 * self.sr)) / self.sr
        kern = np.minimum(t / 0.004, 1.0) * np.exp(-t / release)
        self.pump = 1.0 - depth * np.clip(fftconv(imp, kern)[:self.N], 0.0, 1.0)

    def render(self, drive_amt=1.4, peak_db=-6.0):
        rev, dly, fb, damp = self.fx
        rng = rng_for("fx", self.name)
        out = self.bus["dry"].copy()
        if rev and self.bus["rev"].any():
            for c in range(2):
                out[c] += fftconv(self.bus["rev"][c], reverb_ir(self.sr, rev, rng, damp))[:self.N]
        if dly and self.bus["dly"].any():
            mono = self.bus["dly"].mean(axis=0)
            for c in range(2):
                out[c] += fftconv(mono, echo_ir(self.sr, dly * self.spb, fb, c))[:self.N]
        # wrap everything past the loop end back onto the start (circular mix)
        loop = out[:, :self.L].copy()
        for k in range(self.L, self.N, self.L):
            seg = out[:, k:k + self.L]
            loop[:, :seg.shape[1]] += seg
        loop -= loop.mean(axis=1, keepdims=True)
        if STATS:
            tot = sum(self.stats.values()) + 1e-12
            print(f"  [{self.name}] part levels (dB re total):")
            for k, v in sorted(self.stats.items(), key=lambda kv: -kv[1]):
                print(f"     {k:12s} {10 * np.log10(v / tot + 1e-12):6.1f}")
        loop /= np.max(np.abs(loop)) + 1e-12
        loop = drive(loop, drive_amt)                  # gentle master saturation
        return loop * (10 ** (peak_db / 20) / np.max(np.abs(loop)))


def choir(s, voicing, beat, beats, vel=1.0, gain=0.15, a=3.0, rel=3.0, rev=0.8, part="choir"):
    s.play(inst_glass, chord_at(beat, beats, voicing, vel), part, gain=gain, rev=rev, a=a, rel=rel)


# ================================================================== music

def song_title():
    """A minor, 70 bpm. A dying sun: pads, music-box arpeggio, Ember's theme."""
    s = Song("title", 70, 16, rev=4.5, dly=0.75, fb=0.42)
    sr = s.sr
    Am, G, F, G2 = (P("A1", "A3 C4 E4 B4"), P("G1", "G3 B3 D4 A4"),
                    P("F1", "F3 A3 C4 E4"), P("G1", "G3 B3 D4 G4"))
    harm = [Am, G, F, G2] * 4
    every = range(16)
    s.play(inst_pad, pad_ev(harm, every), "pad", gain=0.24, rev=0.5,
           a=1.5, rel=2.5, cut=2.0, voices=6, spread=0.16)
    s.play(inst_sub, bass_ev(harm, every, [0], step=4, gate=1.0), "sub", gain=0.30, a=0.4, rel=1.2)
    arp = arp_ev(harm, every, [0, 1, 2, 3, 4, 3, 2, 1], step=0.5, gate=0.9, octave=1, span=2)
    arp = [(b, d, m, v * (0.5 if 16 <= b < 48 else 1.0)) for b, d, m, v in arp]
    s.play(inst_bell, arp, "musicbox", gain=0.13, pan=0.25, rev=0.35, dly=0.3,
           ratio=2.0, index=1.0, dec=0.9)

    lead = dict(saw=0.3, sqr=0.0, tri=0.85, bright=3.0, q=0.9, vib=0.18, a=0.06, rel=0.6, sus=0.85)
    A4 = note("A4")
    s.play(inst_lead, theme(A4, MINOR, 16) + theme(A4, MINOR, 32), "lead", gain=0.48,
           rev=0.4, dly=0.3, **lead)
    s.play(inst_lead, theme(A4, MINOR, 32, shift=-2, vel=0.8), "lead2", gain=0.22, pan=-0.35,
           rev=0.5, dly=0.2, **lead)
    s.play(inst_bell, theme(note("A5"), MINOR, 32, vel=0.7), "leadbell", gain=0.10, pan=0.35,
           rev=0.4, ratio=3.0, index=1.0, dec=1.0)
    s.play(inst_lead, theme(A4, MINOR, 48, phrase=THEME_A[:4] + [(1, 4)]), "lead", gain=0.36,
           rev=0.5, dly=0.35, **lead)

    kick = d_kick(sr, 105.0, 40.0, 0.05, 0.35, 0.0, 1.0)
    s.hit(kick, hits("x.........o.....", range(8, 12)), "kick", gain=0.75, rev=0.15)
    s.hit(d_snare(sr, 170.0, 0.25, 1.0, 1.0), hits("........x.......", range(8, 12)), "snare",
          gain=0.22, rev=0.6)
    s.hit([d_hat(sr, 0.05, v) for v in range(4)], hits("..o...o...o...o.", range(8, 12)), "hat",
          gain=0.10, pan=0.3, rev=0.2)
    s.hit(d_swell(sr, 2 * s.spb), [(14, 1.0), (30, 1.0)], "swell", gain=0.10, rev=0.3)
    s.add_loop(s.stereo_noise(150.0, 900.0, cycles=3), gain=0.035, rev=0.3, part="wind")
    return s


def song_ch1():
    """D minor, 128 bpm. Departure: driving arpeggio, hopeful, Ember's theme."""
    s = Song("ch1", 128, 32, rev=2.0, dly=0.75, fb=0.3)
    sr = s.sr
    Dm, C, Bb = P("D2", "D4 F4 A4"), P("C2", "C4 E4 G4"), P("Bb1", "Bb3 D4 F4")
    Gm, F = P("G1", "G3 Bb3 D4"), P("F1", "F3 A3 C4")
    A, B = [Dm, C, Bb, C], [Gm, Bb, F, C]
    harm = A * 5 + B * 2 + A
    s.set_pump([b * 4 + k for b in range(32) for k in range(4)], 0.5, 0.14)

    K = d_kick(sr, 150.0, 45.0, 0.035, 0.22, 0.3, 1.6)
    s.hit(K, hits("x...x...x...x...", list(range(0, 20)) + list(range(28, 32)))
          + hits("x...x...x...x.x.", range(20, 28)), "kick", gain=1.0)
    s.hit([d_clap(sr, 0.12, v) for v in range(2)], hits("....x.......x...", range(4, 30)),
          "clap", gain=0.5, rev=0.25)
    s.hit(d_snare(sr, 190.0, 0.15), hits("....x.......x...", range(4, 30)), "snare", gain=0.45, rev=0.2)
    roll = [(120 + i * 0.5, 0.3 + i * 0.04) for i in range(8)]
    roll += [(124 + i * 0.25, 0.45 + i * 0.03) for i in range(16)]
    s.hit(d_snare(sr, 190.0, 0.12), roll, "snare", gain=0.55, rev=0.25)
    hats = [d_hat(sr, 0.04, v) for v in range(4)]
    s.hit(hats, hits("g.o.g.o.g.o.g.o.", range(0, 4)) + hits("goxggoxggoxggoxg", range(4, 32)),
          "hat", gain=0.22, pan=[0.25, 0.15])
    s.hit(d_hat(sr, 0.22, 7), hits("..x...x...x...x.", range(4, 28)), "ohat", gain=0.12, pan=-0.2)
    s.hit(d_crash(sr), [(b * 4, 1.0) for b in (0, 4, 12, 20, 28)], "crash", gain=0.28, rev=0.3)
    s.hit(d_riser(sr, 8 * s.spb), [(120, 1.0)], "riser", gain=0.16, rev=0.3)
    toms = [(108 + o, v) for o, v in ((2, 0.9), (2.5, 0.8), (3, 0.9), (3.5, 1.0))]
    for (b, v), f in zip(toms, (180.0, 150.0, 120.0, 95.0)):
        s.hit(d_tom(sr, f), [(b, v)], "tom", gain=0.6, rev=0.2)

    s.play(inst_bass, bass_ev(harm, range(32), [0, 0, 12, 0, 0, 0, 12, 0], step=0.5, gate=0.75,
                              accent=(1.0, 0.7)), "bass", gain=0.55, duck=True,
           base=2.0, env=7.0, dec=0.09, q=1.2, drv=1.8, sub=0.6)
    s.play(inst_pad, pad_ev(harm, range(4, 32)), "pad", gain=0.15, rev=0.4, duck=True,
           a=0.4, rel=0.9, cut=3.5, voices=5, spread=0.18)
    pat = [0, 1, 2, 3, 4, 3, 2, 1] * 2
    acc = (1.0, 0.6, 0.75, 0.6)
    s.play(inst_pluck, arp_ev(harm, range(0, 4), pat, accent=acc, octave=0), "arp",
           gain=0.70, rev=0.25, dly=0.25, pan=0.15, duck=True, bright=0.45)
    s.play(inst_pluck, arp_ev(harm, list(range(4, 12)) + list(range(20, 32)), pat, accent=acc),
           "arp", gain=0.62, rev=0.25, dly=0.25, pan=0.15, duck=True, bright=0.9)
    s.play(inst_pluck, arp_ev(harm, range(12, 20), pat, accent=acc, vel=0.75), "arp",
           gain=0.55, rev=0.25, dly=0.25, pan=0.15, duck=True, bright=0.7)

    lead = dict(saw=0.6, sqr=0.4, bright=4.5, q=1.1, vib=0.15, a=0.015, rel=0.3)
    D5 = note("D5")
    s.play(inst_lead, theme(D5, MINOR, 48) + theme(D5, MINOR, 64), "lead", gain=0.38,
           rev=0.3, dly=0.3, **lead)
    s.play(inst_lead, theme(D5, MINOR, 64, shift=-2, vel=0.8), "lead2", gain=0.18, pan=-0.4,
           rev=0.3, dly=0.2, **lead)
    s.play(inst_lead, theme(note("D4"), MINOR, 64, vel=0.8), "lead2", gain=0.16, pan=0.4,
           rev=0.3, **lead)
    counter = line(80, "D5:4 F5:4 A5:2 G5:2 E5:4 D5:4 F5:4 C6:2 A5:2 G5:2 E5:2")
    s.play(inst_lead, counter, "counter", gain=0.30, rev=0.4, dly=0.35, **dict(lead, a=0.08))
    return s


def song_ch2():
    """B minor, 110 bpm. Mareth's ice ring: pulsing bass, sparse cold bells."""
    s = Song("ch2", 110, 32, rev=3.5, dly=0.75, fb=0.45)
    sr = s.sr
    Bm, Gmaj7, Em9 = P("B1", "B3 D4 F#4 C#5"), P("G1", "G3 B3 D4 F#4"), P("E2", "E3 G3 B3 F#4")
    Fsus, Fs = P("F#1", "F#3 B3 C#4 E4"), P("F#1", "F#3 A#3 C#4 E4")
    harm = [Bm, Bm, Gmaj7, Gmaj7, Em9, Em9, Fsus, Fs] * 4
    s.set_pump([b * 4 + k for b in range(32) for k in range(4)], 0.55, 0.2)

    s.play(inst_bass, bass_ev(harm, range(32), [0, 0, 0, 0, 0, 0, 12, 0], step=0.5, gate=0.6,
                              accent=(1.0, 0.65)), "bass", gain=0.75, duck=True,
           wave="sqr", base=2.0, env=4.0, dec=0.08, q=0.9, drv=1.2, sub=0.8)
    s.play(inst_pad, pad_ev(harm, range(32)), "pad", gain=0.15, rev=0.6,
           wave="tri", voices=4, spread=0.1, cut=5.0, a=2.0, rel=3.0)

    cycle = [(0, "F#6"), (1.5, "D6"), (3, "B5"), (6, "C#6"), (8, "B5"), (9.5, "F#5"), (11, "D6"),
             (14.5, "A5"), (16, "E6"), (17.5, "B5"), (19, "G5"), (22, "F#6"), (24, "C#6"),
             (25.5, "B5"), (28, "A#5"), (30, "C#6"), (31.5, "F#6")]
    bells = []
    for c, vel in ((0, 0.8), (1, 1.0), (2, 1.0), (3, 0.75)):
        for i, (b, nm) in enumerate(cycle):
            if c == 0 and i % 2:
                continue
            bells.append((c * 32 + b, 0.5, note(nm), vel))
    s.play(inst_bell, bells, "bells", gain=0.20, rev=0.5, dly=0.45, pan=0.2,
           ratio=3.5, index=1.8, dec=1.3)
    s.play(inst_bell, [(b + 0.75, d, m - 12, v * 0.6) for b, d, m, v in bells if 64 <= b < 96],
           "bells", gain=0.14, rev=0.5, pan=-0.35, ratio=2.0, index=1.0, dec=1.0)

    K = d_kick(sr, 120.0, 45.0, 0.04, 0.35, 0.15, 1.3)
    s.hit(K, hits("x.........x.....", range(8, 16)) + hits("x.........x..x..", range(16, 24)),
          "kick", gain=0.9)
    s.hit(d_snare(sr, 200.0, 0.14, 1.0, 1.0), hits("........x.......", range(8, 24)), "snare",
          gain=0.45, rev=0.5)
    s.hit(d_rim(sr), hits("........x.......", range(24, 32)) + hits("...x..x....x..x.", range(16, 24)),
          "rim", gain=0.35, rev=0.4, pan=[-0.3, 0.3])
    s.hit([d_hat(sr, 0.035, v, 0.15) for v in range(4)], hits("g.o.g.g.g.o.g.g.", range(8, 32)),
          "hat", gain=0.13, pan=[0.35, -0.2])
    s.hit(d_swell(sr, 4 * s.spb), [(28, 1.0), (60, 1.0), (92, 1.0)], "swell", gain=0.12, rev=0.4)
    s.add_loop(s.stereo_noise(2500.0, 7000.0, cycles=4), gain=0.012, rev=0.2, part="ice")
    return s


def song_ch3():
    """C phrygian, 120 bpm. Hesper Relay: sequenced acid bass, metallic percussion."""
    s = Song("ch3", 120, 32, rev=1.6, dly=0.5, fb=0.35)
    sr = s.sr
    C, Db, Ab, G = P("C2", "C3 G3 C4"), P("Db2", "Db3 Ab3 Db4"), P("Ab1", "Ab2 Eb3 Ab3"), P("G1", "G2 D3 G3")
    harm = [C, C, Db, C] * 4 + [Ab, Ab, G, G] * 2 + [C, C, Db, C] * 2
    s.set_pump([b * 4 + k for b in range(2, 32) for k in range(4)], 0.35, 0.12)

    pat = [0, 0, 12, 0, 3, 0, 1, 0, 0, 12, 0, -5, 0, -2, 1, 0]
    acc = [1, .55, .9, .55, .8, .55, 1, .55, .6, .9, .55, .7, .55, .8, .9, .55]
    ev = [(bar * 4 + i * 0.25, 0.2, harm[bar][0] + p, acc[i]) for bar in range(32) for i, p in enumerate(pat)]
    s.play(inst_bass, ev, "acid", gain=0.5, duck=True, wave="saw", base=1.4, env=14.0, dec=0.07,
           q=3.0, drv=2.5, sub=0.4)
    s.play(inst_pad, pad_ev(harm, range(32)), "drone", gain=0.13, rev=0.4, duck=True,
           voices=4, spread=0.2, cut=1.6, a=0.8, rel=1.5)

    K = d_kick(sr, 140.0, 42.0, 0.03, 0.25, 0.4, 2.0)
    s.hit(K, hits("x...x...x...x...", range(2, 31)) + hits("x...x...x.x.x...", [31]), "kick", gain=1.0)
    s.hit(d_snare(sr, 160.0, 0.16, 1.2, 3.0), hits("....x.......x...", range(8, 32)), "snare",
          gain=0.36, rev=0.35)
    s.hit([d_hat(sr, 0.03, v, 0.7) for v in range(4)], hits("x.o.x.o.x.o.x.oo", range(0, 32)),
          "hat", gain=0.2, pan=[0.3, -0.1])
    clank = [d_metal(sr, 420.0, 1.414, 0.12, v) for v in range(3)]
    s.hit(clank, hits("..x..x....x..x..", range(0, 32)), "clank", gain=0.42, pan=[-0.5, 0.5, 0.0],
          rev=0.25, dly=0.15)
    s.hit(d_metal(sr, 1150.0, 2.41, 0.4), hits("..............x.", range(1, 32, 2)), "anvil",
          gain=0.22, pan=0.4, rev=0.4, dly=0.3)
    s.hit(d_steam(sr, 1.6), [(b * 4 + 2, 1.0) for b in range(2, 32, 4)], "steam", gain=0.10,
          pan=-0.5, rev=0.3)
    s.hit(clank, [(124 + i * 0.25, 0.5 + 0.03 * i) for i in range(8, 16)], "clank", gain=0.3,
          pan=[-0.6, 0.6])

    stab_bars = list(range(8, 16)) + list(range(24, 32))
    stabs = [(bar * 4 + o, 0.2, harm[bar][0] + 36 + iv, 1.0) for bar in stab_bars
             for o in (0.75, 2.75) for iv in (0, 1, 7)]
    s.play(inst_pluck, stabs, "stab", gain=0.24, rev=0.3, dly=0.3, pan=-0.2, bright=0.6, q=2.0)

    arp_harm = [None] * 16 + [P("Ab1", "Ab4 C5 Eb5 G5")] * 2 + [P("G1", "G4 B4 D5 F5")] * 2
    arp_harm = arp_harm + arp_harm[16:20]
    s.play(inst_pluck, arp_ev(arp_harm, range(16, 24), [0, 2, 1, 3, 2, 0, 3, 1], step=0.5, span=1),
           "sqarp", gain=0.20, rev=0.3, dly=0.35, pan=0.3, wave="sqr", bright=0.7, dec=0.12)
    return s


def song_ch4():
    """E minor, 90 bpm. The Violet Reach: wide pads, heartbeat, distant Choir."""
    s = Song("ch4", 90, 24, rev=5.0, dly=1.0, fb=0.5)
    sr = s.sr
    Em, Cmaj, Am, Bb = (P("E2", "E3 B3 D4 F#4 G4"), P("C2", "C3 G3 B3 E4 F#4"),
                        P("A1", "A2 E3 G3 B3 C4"), P("Bb1", "Bb2 F3 A3 D4 E4"))
    harm = ([Em] * 2 + [Cmaj] * 2 + [Am] * 2 + [Bb] * 2) * 3
    s.play(inst_pad, pad_ev(harm, range(24)), "pad", gain=0.22, rev=0.7, voices=7, spread=0.35,
           cut=2.2, a=2.5, rel=3.5, width=1.0, lfo=0.07)
    s.play(inst_sub, bass_ev(harm, range(24), [0], step=4, gate=1.0), "sub", gain=0.30, a=0.5, rel=1.0)
    lub = d_kick(sr, 80.0, 38.0, 0.05, 0.2, 0.0, 1.2)
    s.hit(lub, hits("x.o.............", range(24), step=0.2), "heart", gain=0.85, rev=0.15)
    for start in (2, 10, 18):
        choir(s, "E5 A#5 B5 F#6", start * 4, 16, gain=0.16, a=5.0, rel=5.0, rev=1.0)
    s.play(inst_bell, theme(note("E5"), MINOR, 32, phrase=THEME_A, stretch=2, vel=0.9)
           + theme(note("E5"), MINOR, 64, phrase=THEME_B, stretch=2, vel=0.8),
           "bell", gain=0.17, pan=-0.25, rev=0.6, dly=0.4, ratio=2.0, index=0.8, dec=1.8)
    s.add_loop(s.stereo_noise(80.0, 500.0, cycles=3), gain=0.06, rev=0.4, part="wind")
    s.add_loop(s.stereo_noise(3000.0, 6000.0, cycles=5), gain=0.008, rev=0.5, part="glitter")
    s.hit(d_swell(sr, 4 * s.spb), [(28, 1.0), (60, 1.0)], "swell", gain=0.07, rev=0.6)
    return s


def song_boss():
    """F minor, 140 bpm. Driving and aggressive; the Choir's chord swells on top."""
    s = Song("boss", 140, 32, rev=1.8, dly=0.75, fb=0.3)
    sr = s.sr
    Fm, Db, Eb, C = P("F2", "F3 Ab3 C4"), P("Db2", "Db3 F3 Ab3"), P("Eb2", "Eb3 G3 Bb3"), P("C2", "C3 E3 G3")
    harm = [Fm, Db, Eb, C] * 8
    full = list(range(0, 16)) + list(range(24, 32))
    brk = range(16, 24)
    s.set_pump([b * 4 + k for b in range(32) for k in range(4)], 0.45, 0.11)

    K = d_kick(sr, 160.0, 48.0, 0.03, 0.2, 0.35, 2.0)
    s.hit(K, hits("x...x...x...x.x.", full) + hits("x.......x.......", brk), "kick", gain=1.0)
    SN = [d_snare(sr, 200.0, 0.15, 1.1, 1.8, v) for v in range(2)]
    s.hit(SN, hits("....x.......x...", full) + hits("........x.......", brk), "snare",
          gain=0.6, rev=0.25)
    s.hit([d_hat(sr, 0.03, v) for v in range(4)], hits("xgxgxgxgxgxgxgxg", range(32)), "hat",
          gain=0.2, pan=[0.3, 0.2])
    s.hit(d_hat(sr, 0.2, 9), hits("..x...x...x...x.", full), "ohat", gain=0.11, pan=-0.25)
    s.hit(d_crash(sr, 1.4), [(b * 4, 1.0) for b in (0, 8, 16, 24)], "crash", gain=0.3, rev=0.3)
    for bar in (7, 15, 23, 31):
        for i, f in enumerate((220.0, 180.0, 150.0, 120.0, 100.0, 85.0, 75.0, 65.0)):
            s.hit(d_tom(sr, f, 0.25), [(bar * 4 + 2 + i * 0.25, 0.8 + 0.03 * i)], "tom",
                  gain=0.5, pan=0.5 - i * 0.14, rev=0.2)

    s.play(inst_bass, bass_ev(harm, range(32), [0, 0, 12, 0, 0, 12, 0, 0, 0, 0, 12, 0, 0, 12, 0, 12],
                              step=0.25, gate=0.7, accent=(1.0, 0.6, 0.85, 0.6)),
           "bass", gain=0.5, duck=True, base=1.8, env=7.0, dec=0.07, q=1.4, drv=3.0, sub=0.5)
    s.play(inst_pluck, arp_ev(harm, full, [0, 1, 2, 3, 1, 2, 3, 4, 2, 3, 4, 5, 3, 4, 5, 6],
                              accent=(1.0, 0.6), octave=1),
           "arp", gain=0.40, rev=0.2, dly=0.2, pan=-0.2, duck=True, bright=0.9, q=2.0)
    stab_bars = list(range(8, 16)) + list(range(24, 32))
    stabs = [(bar * 4 + o, 0.3, m + 12, 1.0) for bar in stab_bars for o in (0, 0.75, 1.5)
             for m in harm[bar][1]]
    s.play(inst_pad, stabs, "stab", gain=0.2, rev=0.2, duck=True, a=0.004, rel=0.12,
           voices=3, cut=6.0, spread=0.12)
    riff = line(64, "F5:1 Ab5:0.5 G5:0.5 F5:1 C6:1 Db6:1.5 C6:0.5 Bb5:1 G5:1 "
                    "Eb5:1 G5:0.5 F5:0.5 Eb5:1 Bb5:1 C6:1.5 B5:0.5 G5:1 E5:1", legato=0.85)
    riff += [(b + 16, d, m, v) for b, d, m, v in riff]
    s.play(inst_lead, riff, "riff", gain=0.30, rev=0.3, dly=0.3,
           saw=0.3, sqr=0.7, bright=5.0, q=1.6, vib=0.1, a=0.005, rel=0.12)

    choir(s, "F5 C6 G6 B6", 32, 32, vel=1.0, gain=0.24, a=12.0, rel=1.2, rev=0.6)
    choir(s, "F5 C6 G6 B6", 64, 32, vel=0.8, gain=0.24, a=1.5, rel=1.5, rev=0.6)
    choir(s, "F5 C6 G6 B6 F6", 96, 32, vel=1.0, gain=0.26, a=12.0, rel=0.8, rev=0.6)
    s.hit(d_riser(sr, 8 * s.spb), [(56, 1.0), (120, 1.0)], "riser", gain=0.15, rev=0.3)
    return s


def song_ch5():
    """E minor, 132 bpm. The Aperture: Ember's theme, heroic, over the Choir's chord."""
    s = Song("ch5", 132, 32, rev=2.8, dly=0.75, fb=0.32)
    sr = s.sr
    Em, D, C = P("E2", "E3 G3 B3"), P("D2", "D3 F#3 A3"), P("C2", "C3 E3 G3")
    Bm = P("B1", "B2 D3 F#3")
    A, B = [Em, D, C, D], [C, D, Bm, Em]
    harm = A * 3 + B * 2 + A * 3
    main = list(range(4, 28))
    s.set_pump([b * 4 + k for b in range(32) for k in range(4)], 0.4, 0.13)

    K = d_kick(sr, 150.0, 42.0, 0.04, 0.35, 0.3, 1.8)
    s.hit(K, hits("x.......x.......", range(0, 4)) + hits("x.....x.x...x...", main)
          + hits("x...x...x...x...", range(28, 32)), "kick", gain=1.0)
    SN = [d_snare(sr, 180.0, 0.2, 1.0, 1.5, v) for v in range(2)]
    s.hit(SN, hits("....x.......x...", main), "snare", gain=0.6, rev=0.45)
    roll = [(112 + i * 0.5, 0.35 + 0.025 * i) for i in range(16)] + [(120 + i * 0.25, 0.5 + 0.015 * i) for i in range(32)]
    s.hit(SN, roll, "snare", gain=0.5, rev=0.4)
    s.hit([d_hat(sr, 0.04, v) for v in range(4)], hits("x.o.x.o.x.o.x.o.", main), "hat",
          gain=0.16, pan=[0.25, -0.15])
    s.hit(d_crash(sr, 2.0), [(b * 4, 1.0) for b in (4, 12, 20, 28)], "crash", gain=0.3, rev=0.4)
    s.hit(d_tom(sr, 95.0, 0.3), hits("x.x.x.x.x.x.x.x.", range(0, 4)), "tom", gain=0.4, rev=0.3)
    s.hit(d_tom(sr, 130.0, 0.25), hits("..x...x.x..x..xx", range(12, 20)), "tom", gain=0.4,
          pan=-0.3, rev=0.3)
    s.hit(d_tom(sr, 85.0, 0.35), hits("x.....x...x.....", range(12, 20)), "tom", gain=0.5,
          pan=0.3, rev=0.3)
    s.hit(d_riser(sr, 8 * s.spb), [(120, 1.0)], "riser", gain=0.16, rev=0.3)

    s.play(inst_bass, bass_ev(harm, range(32), [0, 0, 0, 12, 0, 0, 12, 0], step=0.5, gate=0.7,
                              accent=(1.0, 0.7)), "bass", gain=0.5, duck=True,
           base=2.0, env=6.0, dec=0.1, q=1.1, drv=2.0, sub=0.7)
    s.play(inst_pad, pad_ev(harm, range(32), octave=1), "pad", gain=0.16, rev=0.4, duck=True,
           a=0.3, rel=1.0, cut=3.0, voices=5, spread=0.2)
    s.play(inst_pluck, arp_ev(harm, main, [0, 1, 2, 3, 4, 5, 4, 3] * 2, accent=(1.0, 0.6), octave=1),
           "arp", gain=0.36, rev=0.25, dly=0.25, pan=0.2, duck=True, bright=0.8)

    # The Choir's chord: always there, swelling into each section.
    for beat, vel, a in ((0, 1.0, 6.0), (16, 0.55, 1.0), (32, 0.55, 1.0), (48, 1.0, 5.0),
                         (64, 1.0, 1.0), (80, 0.6, 1.0), (96, 0.6, 1.0), (112, 1.0, 6.0)):
        choir(s, "E5 B5 F#6 A#6", beat, 16, vel=vel, gain=0.22, a=a, rel=2.0, rev=0.6)

    brass = dict(saw=0.85, sqr=0.15, sub=0.25, bright=5.0, q=1.0, vib=0.2, rate=5.0, a=0.04,
                 d=0.4, sus=0.85, rel=0.35)
    E5, E4 = note("E5"), note("E4")
    s.play(inst_lead, theme(E5, MINOR, 16) + theme(E5, MINOR, 32) + theme(E5, MINOR, 80)
           + theme(E5, MINOR, 96), "lead", gain=0.36, rev=0.35, dly=0.25, **brass)
    s.play(inst_lead, theme(E4, MINOR, 16) + theme(E4, MINOR, 32), "lead2", gain=0.20, pan=-0.3,
           rev=0.3, **brass)
    s.play(inst_lead, theme(E5, MINOR, 80, shift=-2) + theme(E5, MINOR, 96, shift=-2), "lead2",
           gain=0.20, pan=-0.35, rev=0.35, **brass)
    s.play(inst_bell, theme(note("E6"), MINOR, 96, vel=0.8), "bell", gain=0.16, pan=0.4, rev=0.4,
           ratio=3.0, index=1.0, dec=0.8)
    counter = line(48, "G5:4 A5:4 B5:2 D6:2 E6:4 G5:3 A5:1 F#5:2 A5:2 D6:2 B5:2 E6:4")
    s.play(inst_lead, counter, "counter", gain=0.32, rev=0.45, dly=0.3, **brass)
    return s


def song_ending():
    """D major, 76 bpm. A new star: Ember's theme resolved, warm."""
    s = Song("ending", 76, 16, rev=3.5, dly=0.75, fb=0.4)
    sr = s.sr
    D, A, G, A7 = (P("D2", "D3 F#3 A3 E4"), P("A1", "A2 E3 A3 C#4"),
                   P("G1", "G2 D3 B3 F#4"), P("A1", "A2 E3 G3 C#4"))
    Bm, G2, D2 = P("B1", "B2 F#3 A3 D4"), P("G1", "G2 D3 G3 B3"), P("D2", "D3 F#3 A3 D4")
    harm = [D, A, G, A7] * 3 + [Bm, G2, D2, A]
    every = range(16)
    s.play(inst_pad, pad_ev(harm, every), "pad", gain=0.30, rev=0.5, a=1.2, rel=2.0, cut=2.5,
           voices=6, spread=0.14, wave="saw")
    s.play(inst_sub, bass_ev(harm, every, [0, None, None, 0], step=1, gate=1.8), "sub",
           gain=0.30, a=0.1, rel=0.8)
    s.play(inst_pluck, arp_ev(harm, every, [0, 1, 2, 3, 4, 3, 2, 1], step=0.5, gate=0.9, octave=1,
                              span=2, accent=(1.0, 0.7)),
           "arp", gain=0.34, rev=0.4, dly=0.35, pan=0.25, wave="tri", bright=0.4, dec=0.3, sus=0.2)

    warm = dict(saw=0.25, sqr=0.0, tri=0.9, bright=3.5, q=0.8, vib=0.2, rate=5.0, a=0.05, rel=0.6, sus=0.85)
    D5 = note("D5")
    s.play(inst_lead, theme(D5, MAJOR, 16) + theme(D5, MAJOR, 32), "lead", gain=0.40, rev=0.45,
           dly=0.3, **warm)
    s.play(inst_lead, theme(D5, MAJOR, 32, shift=-2, vel=0.8), "lead2", gain=0.22, pan=-0.35,
           rev=0.45, **warm)
    s.play(inst_bell, theme(note("D6"), MAJOR, 32, vel=0.7), "bell", gain=0.14, pan=0.35, rev=0.5,
           ratio=2.0, index=0.8, dec=1.2)
    s.play(inst_lead, line(48, "F#5:2 D5:1 E5:1 D5:2 B4:2 A4:2 D5:1 F#5:1 E5:4"), "lead",
           gain=0.36, rev=0.5, dly=0.35, **warm)

    s.hit(d_kick(sr, 110.0, 42.0, 0.05, 0.3, 0.05, 1.1), hits("x.......x.......", range(8, 16)),
          "kick", gain=0.75, rev=0.15)
    s.hit(d_rim(sr), hits("....x.......x...", range(8, 16)), "rim", gain=0.3, rev=0.5)
    s.hit([d_hat(sr, 0.05, v, 0.0) for v in range(4)], hits("g.o.g.o.g.o.g.o.", range(8, 16)),
          "shaker", gain=0.09, pan=0.3)
    s.hit(d_swell(sr, 2 * s.spb), [(14, 1.0), (30, 1.0)], "swell", gain=0.10, rev=0.4)
    s.add_loop(s.stereo_noise(200.0, 1500.0, cycles=2), gain=0.015, rev=0.3, part="air")
    return s


MUSIC = {"title": song_title, "ch1": song_ch1, "ch2": song_ch2, "ch3": song_ch3,
         "ch4": song_ch4, "boss": song_boss, "ch5": song_ch5, "ending": song_ending}


# ==================================================================== sfx
# Each returns a mono float signal at 44.1 kHz; finish_sfx() fades and
# normalizes it.

def crackle(n, sr, rng, density, tau):
    t = np.arange(n) / sr
    imp = (rng.random(n) < density / sr * np.exp(-t / tau)) * rng.uniform(-1.0, 1.0, n)
    k = int(0.003 * sr)
    kern = rng.uniform(-1.0, 1.0, k) * np.exp(-np.arange(k) / (0.0008 * sr))
    return hp1(np.convolve(imp, kern)[:n], 1500.0, sr)


def glass_strike(f, n, sr, rng, dec=0.25, cents=7.0):
    """A struck Choir chime: GLASS partials, higher ones dying faster."""
    t = np.arange(n) / sr
    y = np.zeros(n)
    for c in (-cents, cents):
        fv = f * 2.0 ** (c / 1200.0)
        y += 0.3 * osc("tri", fv, n, sr) * np.exp(-t / dec)
        for k, amp in GLASS + ((2.76, 0.15),):
            if fv * k < 0.45 * sr:
                y += amp * np.sin(TAU * fv * k * t + rng.random() * TAU) * np.exp(-t / (dec / k ** 0.7))
    return y * np.minimum(t / 0.0015, 1.0)


def mix_at(y, x, k, g=1.0):
    """y[k:] += g * x, clipped to y's length."""
    n = min(len(x), len(y) - k)
    y[k:k + n] += g * x[:n]


def boom(sr, rng, T, f0, f1, pdec, body_dec, nz_dec, cut0, cut1, crack=0.3, crack_dec=0.3,
         rumble=0.0, rumble_dec=0.5, drv=1.5):
    n = int(T * sr)
    t = np.arange(n) / sr
    body = sweep_sin(f1 + (f0 - f1) * np.exp(-t / pdec), sr) * np.exp(-t / body_dec)
    nz = lp2(white(n, rng), cut1 + (cut0 - cut1) * np.exp(-t / (nz_dec * 0.6)), sr, 0.7)
    nz *= 0.6 / (np.std(nz[:int(0.03 * sr)]) + 1e-9) * np.exp(-t / nz_dec)
    y = body + nz + crack * crackle(n, sr, rng, 500.0, crack_dec)
    if rumble:
        rb = lp1(lp1(white(n, rng), 160.0, sr), 160.0, sr)
        y += rumble * rb / (np.std(rb) + 1e-9) * 0.35 * np.exp(-t / rumble_dec)
    return drive(y, drv) * np.minimum(t / 0.001, 1.0)


def sfx_laser(sr, rng):
    n = int(0.12 * sr)
    t = np.arange(n) / sr
    f = 300.0 + 1500.0 * np.exp(-t / 0.025)
    x = 0.5 * osc("sqr", f, n, sr) + 0.35 * osc("saw", f * 1.007, n, sr) + 0.4 * osc("sin", f * 0.5, n, sr)
    x = lp2(x, 700.0 + 6000.0 * np.exp(-t / 0.03), sr, 1.1)
    return x * decay(n, sr, 0.045, 0.001)


def sfx_enemy_shot(sr, rng):
    n = int(0.42 * sr)
    t = np.arange(n) / sr
    y = np.zeros(n)
    for m, off in zip(notes("A5 E6 B6"), (0.0, 0.012, 0.024)):
        k = int(off * sr)
        y[k:] += glass_strike(float(hz(m)), n - k, sr, rng, dec=0.16)
    y += 0.4 * hp1(white(n, rng), 5000.0, sr) * np.exp(-t / 0.003)
    return y


def sfx_hit(sr, rng):
    n = int(0.12 * sr)
    t = np.arange(n) / sr
    y = sum(a * np.sin(TAU * f * t + rng.random() * TAU) * np.exp(-t / d)
            for f, a, d in ((1830.0, 1.0, 0.035), (2710.0, 0.7, 0.025), (4020.0, 0.5, 0.018),
                            (5530.0, 0.35, 0.012)))
    y += 0.8 * hp1(white(n, rng), 3000.0, sr) * np.exp(-t / 0.004)
    return y * np.minimum(t / 0.0005, 1.0)


def sfx_hurt(sr, rng):
    n = int(0.42 * sr)
    t = np.arange(n) / sr
    thump = sweep_sin(40.0 + 90.0 * np.exp(-t / 0.04), sr) * np.exp(-t / 0.14)
    buzz = (osc("sqr", 72.0 * (1.0 + 0.3 * np.exp(-t / 0.05)), n, sr) + 0.7 * osc("saw", 97.0, n, sr))
    buzz *= np.exp(-t / 0.1)
    nz = lp1(white(n, rng), 2500.0, sr) * np.exp(-t / 0.07)
    y = np.tanh(4.0 * (thump + 0.7 * buzz + 1.0 * nz))
    hold = 5                                           # sample-and-hold + 4-bit crunch
    y = np.round(y[(np.arange(n) // hold) * hold] * 8.0) / 8.0
    y = lp1(y, 6000.0, sr) * np.exp(-t / 0.15)
    return y * np.minimum(t / 0.001, 1.0)


def sfx_explode_small(sr, rng):
    return boom(sr, rng, 0.6, 130.0, 42.0, 0.04, 0.12, 0.13, 6000.0, 300.0, crack=0.35,
                crack_dec=0.18, rumble=0.4, rumble_dec=0.2)


def sfx_explode_big(sr, rng):
    y = boom(sr, rng, 1.2, 110.0, 32.0, 0.06, 0.3, 0.3, 5000.0, 180.0, crack=0.45,
             crack_dec=0.45, rumble=0.9, rumble_dec=0.45, drv=1.8)
    k = int(0.07 * sr)
    mix_at(y, boom(sr, rng, 1.2 - 0.07, 140.0, 50.0, 0.03, 0.12, 0.15, 7000.0, 400.0, crack=0.3), k, 0.6)
    return y


def sfx_explode_boss(sr, rng):
    T = 2.6
    n = int(T * sr)
    t = np.arange(n) / sr
    y = np.zeros(n)
    for off, g, cut in ((0.0, 0.5, 6000.0), (0.22, 0.55, 5000.0), (0.45, 0.6, 7000.0), (0.7, 0.65, 5500.0)):
        k = int(off * sr)
        mix_at(y, boom(sr, rng, T - off, 140.0, 45.0, 0.03, 0.12, 0.14, cut, 300.0, crack=0.4,
                       crack_dec=0.2), k, g)
    k = int(0.95 * sr)
    mix_at(y, boom(sr, rng, T - 0.95, 90.0, 24.0, 0.08, 0.7, 0.55, 4500.0, 120.0, crack=0.5,
                   crack_dec=0.9, rumble=1.2, rumble_dec=0.9, drv=2.0), k)
    # the Conductor's dying chord, sliding down an octave
    fall = 2.0 ** (-np.clip(t - 0.3, 0.0, None) / (T - 0.3))
    song = np.zeros(n)
    for m in notes("A4 E5 B5 D#6"):
        for c in (-8.0, 8.0):
            f = float(hz(m)) * 2.0 ** (c / 1200.0) * fall
            song += sweep_sin(f, sr) + 0.3 * sweep_sin(2 * f, sr) + 0.1 * sweep_sin(3 * f, sr)
    env = np.clip((t - 0.1) / 0.6, 0.0, 1.0) * np.exp(-np.clip(t - 0.7, 0.0, None) / 0.7)
    y += 0.06 * song * env
    return fade(y, sr, 0.0, 0.4)


def sfx_roll(sr, rng):
    T = 0.5
    n = int(T * sr)
    t = np.arange(n) / sr
    u = t / T
    fc = np.where(u < 0.45, 600.0 + 2200.0 * (u / 0.45) ** 1.5, 2800.0 - 1900.0 * ((u - 0.45) / 0.55))
    w = white(n, rng)
    y = bp2(w, fc, sr, fc * 0.5) + 0.35 * bp2(w, fc * 1.5, sr, 60.0) + 0.1 * hp1(w, 6000.0, sr)
    return y * np.sin(np.pi * u) ** 1.5


def sfx_boost(sr, rng):
    T = 0.75
    n = int(T * sr)
    t = np.arange(n) / sr
    u = t / T
    f = 50.0 + 110.0 * (1.0 - np.exp(-t / 0.25))
    x = osc("saw", f, n, sr) + 0.6 * osc("sqr", f * 1.502, n, sr) + 0.5 * osc("saw", f * 2.01, n, sr)
    x = lp2(x, 250.0 + 2800.0 * u ** 0.7, sr, 1.3)
    nz = lp2(white(n, rng), 600.0 + 5000.0 * u, sr, 0.8)
    y = np.tanh(2.0 * (0.6 * x + 0.5 * nz))
    y += 0.4 * sweep_sin(40.0 + 80.0 * np.exp(-t / 0.03), sr) * np.exp(-t / 0.08)
    env = np.minimum(t / 0.03, 1.0) * (0.3 + 0.7 * np.clip(t / 0.45, 0.0, 1.0))
    return y * env * (1.0 - np.clip((t - 0.45) / 0.3, 0.0, 1.0)) ** 1.5


def sfx_bomb(sr, rng):
    T = 1.6
    n = int(T * sr)
    t = np.arange(n) / sr
    y = boom(sr, rng, T, 100.0, 26.0, 0.07, 0.5, 0.35, 3500.0, 120.0, crack=0.25, crack_dec=0.4,
             rumble=1.0, rumble_dec=0.6, drv=2.0)
    sh = np.zeros(n)
    for _ in range(24):
        f = rng.uniform(1800.0, 6500.0)
        sh += np.sin(TAU * f * t + rng.random() * TAU) * (1.0 + 0.8 * np.sin(TAU * rng.uniform(6, 14) * t))
    sh += 2.0 * crackle(n, sr, rng, 900.0, 0.6)
    sh *= np.clip((t - 0.04) / 0.1, 0.0, 1.0) * np.exp(-np.clip(t - 0.14, 0.0, None) / 0.45)
    return y + 0.5 * sh / (np.max(np.abs(sh)) + 1e-9)


def sfx_pickup(sr, rng):
    n = int(0.5 * sr)
    y = np.zeros(n)
    for i, m in enumerate(notes("C6 E6 G6 C7")):
        k = int(i * 0.05 * sr)
        L = n - k
        t = np.arange(L) / sr
        f = float(hz(m))
        tone = 0.6 * np.sin(TAU * f * t) + 0.25 * lp1(osc("sqr", f, L, sr), 4000.0, sr)
        tone += 0.2 * np.sin(TAU * 2 * f * t)
        y[k:] += tone * decay(L, sr, 0.09 if i < 3 else 0.2, 0.002)
    e = int(0.06 * sr)
    y[e:] += 0.25 * y[:-e]                            # a single sparkle echo
    return y


def sfx_alarm(sr, rng):
    n = int(0.35 * sr)
    x = 0.6 * osc("sqr", 740.0, n, sr) + 0.3 * osc("sin", 1480.0, n, sr)
    x = lp2(x, 3000.0, sr, 0.8)
    return x * adsr(int(0.17 * sr), n, sr, 0.004, 0.05, 0.8, 0.02)


def sfx_ui_move(sr, rng):
    n = int(0.06 * sr)
    t = np.arange(n) / sr
    y = np.sin(TAU * 1500.0 * t) + 0.3 * osc("tri", 3000.0, n, sr)
    return y * decay(n, sr, 0.012, 0.0008)


def sfx_ui_select(sr, rng):
    n = int(0.25 * sr)
    y = np.zeros(n)
    for m, off, length, vel in ((note("A5"), 0.0, 0.06, 0.8), (note("E6"), 0.07, 0.16, 1.0)):
        k = int(off * sr)
        L = n - k
        f = float(hz(m))
        tone = 0.6 * osc("sin", f, L, sr) + 0.3 * lp1(osc("sqr", f, L, sr), 3500.0, sr)
        y[k:] += vel * tone * adsr(int(length * sr), L, sr, 0.002, 0.06, 0.6, 0.04)
    return y


def sfx_radio(sr, rng):
    T = 0.32
    n = int(T * sr)
    st = bp2(white(n, rng), 1800.0, sr, 2200.0) * 2.0
    hold = int(sr / 70)
    flutter = np.repeat(rng.uniform(0.35, 1.0, n // hold + 1), hold)[:n]
    st = st * lp1(flutter, 200.0, sr) + 0.6 * crackle(n, sr, rng, 300.0, 1.0)
    st *= adsr(int(0.25 * sr), n, sr, 0.004, 0.1, 0.8, 0.02)
    for off in (0.0, 0.272):                          # key-down / key-up clicks
        k = int(off * sr)
        L = int(0.006 * sr)
        st[k:k + L] += 0.9 * lp1(np.where(np.arange(L) < L // 3, 1.0, -0.5), 3000.0, sr) * np.exp(-np.arange(L) / (0.002 * sr))
    return st


def sfx_warning(sr, rng):
    T = 1.6
    n = int(T * sr)
    t = np.arange(n) / sr
    y = np.zeros(n)
    for start in (0.0, 0.8):                         # two klaxon blasts
        k = int(start * sr)
        L = min(int(0.72 * sr), n - k)
        tt = np.arange(L) / sr
        f = (330.0 + 120.0 * (1.0 - np.exp(-tt / 0.06))) * (1.0 + 0.01 * np.sin(TAU * 7.0 * tt))
        x = osc("saw", f, L, sr) + 0.8 * osc("sqr", f * 1.005, L, sr) + 0.5 * osc("saw", f * 1.26, L, sr)
        x = np.tanh(2.0 * lp2(x, 2200.0, sr, 2.0))
        y[k:k + L] += 0.5 * x * adsr(int(0.62 * sr), L, sr, 0.02, 0.2, 0.85, 0.09)
    rise = 2.0 ** ((5.0 / 12.0) * t / T)            # the Choir's chord rising a fourth
    ch = np.zeros(n)
    for m in notes("E5 B5 F#6 A#6"):
        for c in (-6.0, 6.0):
            f = float(hz(m)) * 2.0 ** (c / 1200.0) * rise
            ch += sweep_sin(f, sr) + 0.3 * sweep_sin(2 * f, sr) + 0.12 * sweep_sin(3 * f, sr)
    ch *= (t / T) ** 1.2 * (1.0 + 0.15 * np.sin(TAU * 5.0 * t))
    return y + 0.7 * ch / (np.max(np.abs(ch)) + 1e-9)


SFX = {"laser": sfx_laser, "enemy_shot": sfx_enemy_shot, "hit": sfx_hit, "hurt": sfx_hurt,
       "explode_small": sfx_explode_small, "explode_big": sfx_explode_big,
       "explode_boss": sfx_explode_boss, "roll": sfx_roll, "boost": sfx_boost, "bomb": sfx_bomb,
       "pickup": sfx_pickup, "alarm": sfx_alarm, "ui_move": sfx_ui_move,
       "ui_select": sfx_ui_select, "radio": sfx_radio, "warning": sfx_warning}

# fade-out lengths (s); everything else gets 12 ms
SFX_FADE = {"explode_boss": 0.4, "explode_big": 0.15, "bomb": 0.2, "warning": 0.12,
            "boost": 0.05, "roll": 0.03}


def finish_sfx(y, sr, fout=0.012, peak_db=-3.0):
    y = fade(hp1(y, 20.0, sr), sr, 0.0005, fout)
    return y * (10 ** (peak_db / 20) / (np.max(np.abs(y)) + 1e-12))


# ===================================================================== io

def write_wav(path, x, sr):
    data = x.T if x.ndim == 2 else x[:, None]
    pcm = np.clip(np.round(data * 32767.0), -32768, 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(data.shape[1])
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(pcm.tobytes())


def read_wav(path):
    with wave.open(path, "rb") as w:
        ch, sr, n = w.getnchannels(), w.getframerate(), w.getnframes()
        x = np.frombuffer(w.readframes(n), "<i2").reshape(-1, ch).T.astype(float) / 32768.0
    return x, sr


def ogg_encoder():
    """('ffmpeg' | 'oggenc', path) when an Ogg Vorbis encoder is available."""
    ff = shutil.which("ffmpeg")
    if ff:
        try:
            enc = subprocess.run([ff, "-hide_banner", "-encoders"], capture_output=True, text=True).stdout
            if "libvorbis" in enc:
                return ("ffmpeg", ff)
        except OSError:
            pass
    oe = shutil.which("oggenc")
    return ("oggenc", oe) if oe else None


def write_ogg(enc, wav_path):
    out = wav_path[:-4] + ".ogg"
    if enc[0] == "ffmpeg":
        cmd = [enc[1], "-y", "-loglevel", "error", "-i", wav_path, "-c:a", "libvorbis", "-q:a", "5", out]
    else:
        cmd = [enc[1], "-Q", "-q", "5", "-o", out, wav_path]
    subprocess.run(cmd, check=True)
    return out


def db(v):
    return 20.0 * np.log10(max(v, 1e-9))


def verify():
    ok = True
    print("\n== verify ==")
    print(f"{'file':28s} {'ch':>2s} {'rate':>6s} {'dur s':>7s} {'peak dB':>8s} {'rms dB':>7s} {'size KB':>8s}  notes")
    for d, names, is_music in ((SFX_DIR, SFX, False), (MUS_DIR, MUSIC, True)):
        for name in names:
            path = os.path.join(d, name + ".wav")
            if not os.path.exists(path):
                print(f"{name:28s} MISSING")
                ok = False
                continue
            x, sr = read_wav(path)
            peak = np.max(np.abs(x))
            rms = np.sqrt(np.mean(x * x))
            clipped = int(np.sum(np.abs(x) >= 32767 / 32768.0))
            note_s = []
            if clipped:
                note_s.append(f"CLIPPED x{clipped}")
                ok = False
            if peak < 0.01:
                note_s.append("SILENT")
                ok = False
            if is_music:
                k = int(0.05 * sr)
                a = np.sqrt(np.mean(x[:, :k] ** 2))
                b = np.sqrt(np.mean(x[:, -k:] ** 2))
                mid = x.shape[1] // 2                  # an internal bar line, for reference
                c = np.sqrt(np.mean(x[:, mid - k:mid] ** 2))
                e = np.sqrt(np.mean(x[:, mid:mid + k] ** 2))
                diffs = np.abs(np.diff(x, axis=1))
                jump = np.max(np.abs(x[:, 0] - x[:, -1])) / (np.percentile(diffs, 99) + 1e-9)
                note_s.append(f"seam 50ms rms tail {db(b):.1f} -> head {db(a):.1f} dB "
                              f"(mid bar line {db(c):.1f} -> {db(e):.1f}); end->start step {jump:.2f}x p99")
                if jump > 1.0:
                    note_s.append("SEAM JUMP")
                    ok = False
            print(f"{name + '.wav':28s} {x.shape[0]:2d} {sr:6d} {x.shape[1] / sr:7.3f} {db(peak):8.2f} "
                  f"{db(rms):7.1f} {os.path.getsize(path) / 1024:8.0f}  {'; '.join(note_s)}")
    total = sum(os.path.getsize(os.path.join(MUS_DIR, f)) for f in os.listdir(MUS_DIR))
    wavs = sum(os.path.getsize(os.path.join(MUS_DIR, f)) for f in os.listdir(MUS_DIR) if f.endswith(".wav"))
    print(f"assets/music total: {total / 1e6:.1f} MB (wav {wavs / 1e6:.1f} MB)")
    print("verify:", "OK" if ok else "PROBLEMS FOUND")
    return ok


def main(argv):
    global STATS
    flags = {a for a in argv if a.startswith("-")}
    names = [a for a in argv if not a.startswith("-")]
    STATS = "--stats" in flags
    unknown = [n for n in names if n not in SFX and n not in MUSIC]
    if unknown:
        sys.exit(f"unknown sound(s): {', '.join(unknown)}\nknown: {', '.join(list(SFX) + list(MUSIC))}")
    if "--verify" in flags:
        return 0 if verify() else 1
    os.makedirs(SFX_DIR, exist_ok=True)
    os.makedirs(MUS_DIR, exist_ok=True)
    t_all = time.time()
    for name, fn in SFX.items():
        if names and name not in names:
            continue
        t0 = time.time()
        y = finish_sfx(fn(SR_SFX, rng_for("sfx", name)), SR_SFX, SFX_FADE.get(name, 0.012))
        write_wav(os.path.join(SFX_DIR, name + ".wav"), y, SR_SFX)
        print(f"sfx   {name:14s} {len(y) / SR_SFX:6.3f} s  ({time.time() - t0:.2f} s)")
    enc = ogg_encoder()
    for name, fn in MUSIC.items():
        if names and name not in names:
            continue
        t0 = time.time()
        song = fn()
        y = song.render()
        path = os.path.join(MUS_DIR, name + ".wav")
        write_wav(path, y, song.sr)
        extra = ""
        if enc:
            write_ogg(enc, path)
            extra = f" + .ogg ({enc[0]})"
        print(f"music {name:14s} {y.shape[1] / song.sr:6.2f} s  ({time.time() - t0:.2f} s){extra}")
    if not enc:
        print("no Ogg Vorbis encoder (ffmpeg+libvorbis / oggenc) on PATH: WAV only")
    print(f"generated in {time.time() - t_all:.1f} s")
    return 0 if verify() else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
