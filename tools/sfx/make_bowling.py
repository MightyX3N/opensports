#!/usr/bin/env python3
"""Cuts the recorded bowling sources (tools/sfx/sources/) into the game's bowling sounds.

Run:  python3 tools/sfx/make_bowling.py      (numpy, scipy, ffmpeg)
Writes mono .ogg files to assets/sounds/bowling/. Everything the game places in 3D is mono and dry
(no added reverb): the game puts each sound where it happened and adds the room live.

- crash_*      whole pin crashes (real strikes), started on the ball's first hit on the pins
- clack_*      single pin hits cut from the quiet moments of the strikes
- ball_pin_*   the ball's first knock on a pin (start of a strike recording)
- ball_drop    the ball landing on the lane (start of the roll recording)
- roll_loop    the ball rolling (middle of the roll recording, looped)
- roll_gutter_loop, pit, pin_pit, pin_wall: the same recordings, filtered / pitched
- ambience_loop  other lanes far away, made from the same recordings (stereo, not placed)
"""
import os, subprocess, tempfile
import numpy as np
from scipy.signal import butter, sosfilt, fftconvolve, resample_poly

SR = 44100
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
SRC = os.path.join(ROOT, "tools", "sfx", "sources")
OUT = os.path.join(ROOT, "assets", "sounds", "bowling")
rng = np.random.default_rng(7)


def load(name, mono=True):
    raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", os.path.join(SRC, name), "-f", "f32le",
                          "-ac", "1" if mono else "2", "-ar", str(SR), "-"], capture_output=True, check=True).stdout
    x = np.frombuffer(raw, "<f4").astype(float)
    return x if mono else x.reshape(-1, 2)


def secs(t):
    return int(round(t * SR))


def sos(kind, f, order=2):
    return butter(order, np.array(f) / (SR / 2), kind, output="sos")


def lowpass(x, f, o=2): return sosfilt(sos("low", f, o), x, axis=0)
def highpass(x, f, o=2): return sosfilt(sos("high", f, o), x, axis=0)


def peak_eq(x, f, gain_db, q=1.5):
    """one peaking EQ band (RBJ cookbook)"""
    A = 10 ** (gain_db / 40)
    w = 2 * np.pi * f / SR
    al = np.sin(w) / (2 * q)
    b = [1 + al * A, -2 * np.cos(w), 1 - al * A]
    a = [1 + al / A, -2 * np.cos(w), 1 - al / A]
    from scipy.signal import lfilter
    return lfilter(np.array(b) / a[0], np.array(a) / a[0], x, axis=0)


def pitch(x, ratio):
    """play faster (ratio > 1, higher) or slower; length changes like a tape"""
    up, down = int(round(1000 / ratio)), 1000
    return resample_poly(x, up, down, axis=0)


def cut(x, t0, dur, fin=0.002, fout=0.04):
    y = x[secs(t0):secs(t0 + dur)].copy()
    a, b = secs(fin), secs(fout)
    if a: y[:a] *= np.linspace(0, 1, a)[:, None] if y.ndim == 2 else np.linspace(0, 1, a)
    if b:
        k = np.linspace(1, 0, b) ** 2
        y[-b:] *= k[:, None] if y.ndim == 2 else k
    return y


def tame_spikes(x, ratio=2.6, win=0.003):
    """soften sharp clicks that would stand out when a loop repeats"""
    e = np.sqrt(np.convolve(x ** 2, np.ones(secs(win)) / secs(win), "same"))
    ref = np.sqrt(np.convolve(x ** 2, np.ones(secs(0.25)) / secs(0.25), "same")) + 1e-9
    g = np.minimum(1, ratio * ref / (e + 1e-9))
    g = np.convolve(g, np.ones(secs(0.004)) / secs(0.004), "same")
    return x * g


def loopify(x, xf=0.25):
    n = secs(xf)
    k = np.linspace(0, 1, n)
    if x.ndim == 2: k = k[:, None]
    return np.concatenate([x[-n:] * np.cos(k * np.pi / 2) + x[:n] * np.sin(k * np.pi / 2), x[n:-n]])


def norm(x, peak):
    return x * (peak / (np.max(np.abs(x)) + 1e-12))


written = []


def save(name, x, peak=0.9):
    x = highpass(x, 25)
    x = np.clip(norm(x, peak), -1, 1)
    ch = 1 if x.ndim == 1 else 2
    os.makedirs(OUT, exist_ok=True)
    with tempfile.NamedTemporaryFile(suffix=".raw", delete=False) as f:
        f.write((x * 32767).astype("<i2").tobytes())
        raw = f.name
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le", "-ar", str(SR), "-ac", str(ch), "-i", raw,
                    "-c:a", "libvorbis", "-q:a", "6", os.path.join(OUT, name + ".ogg")], check=True)
    os.unlink(raw)
    written.append((name, len(x) / SR))


def main():
    s2 = load("juskiddink-strike2.wav")
    s3 = load("juskiddink-strike3.wav")
    roll = load("qubodup-bowling-roll.ogg")
    for f in os.listdir(OUT) if os.path.isdir(OUT) else []:
        if f.endswith(".ogg") and not f.startswith(("jingle_", "crowd_")):
            os.remove(os.path.join(OUT, f))

    # whole crashes
    save("crash_1", cut(s2, 0.0, 1.68, 0.0005, 0.25))
    save("crash_2", cut(s3, 0.0, 1.88, 0.0005, 0.3))

    # single clacks from the quiet moments (onsets found by envelope jumps)
    clacks = [(s2, 0.397, 0.17), (s2, 0.826, 0.2), (s2, 1.277, 0.2), (s3, 0.669, 0.15), (s3, 0.732, 0.16)]
    for i, (src, t, d) in enumerate(clacks):
        save(f"clack_{i + 1}", cut(src, t - 0.003, d, 0.001, 0.06), 0.85)

    # the ball's first knock (start of the strike, before the pins pile in)
    save("ball_pin_1", cut(s2, 0.027, 0.13, 0.0005, 0.06))
    save("ball_pin_2", pitch(cut(s2, 0.027, 0.13, 0.0005, 0.06), 0.93))

    # ball landing on the lane: the start of the roll recording
    drop = cut(roll, 0.0, 0.42, 0.0005, 0.2)
    save("ball_drop", drop)

    # rolling: the steadiest stretch, clicks softened, looped
    body = tame_spikes(roll[secs(0.75):secs(2.66)])
    save("roll_loop", loopify(body, 0.25), 0.8)

    # gutter: the same roll in the hollow channel -- thinner, with a ring, a little higher
    g = peak_eq(highpass(body, 180), 520, 9, 2.5)
    g = peak_eq(g, 1300, 5, 3)
    save("roll_gutter_loop", loopify(pitch(g, 1.12), 0.25), 0.8)

    # the ball dropping into the pit behind the curtain: deep and muffled
    save("pit", lowpass(pitch(drop, 0.72), 900, 4))

    # pins: against the side boards (a little duller), dropping into the pit (muffled)
    for i, (src, t, d) in enumerate(clacks[:3]):
        c = cut(src, t - 0.003, d, 0.001, 0.06)
        save(f"pin_wall_{i + 1}", lowpass(pitch(c, 0.88), 3500), 0.85)
        save(f"pin_pit_{i + 1}", lowpass(pitch(c, 0.8), 1100, 4), 0.85)

    # the rest of the hall: other lanes rolling and crashing, far away, in stereo
    dur = 32.0
    n = secs(dur)
    amb = np.zeros((n, 2))
    rl = loopify(body, 0.25)
    t = 0.3
    while t < dur - 3.5:
        pan = rng.uniform(-0.9, 0.9)
        far = rng.uniform(0.35, 1.0)
        rd = rng.uniform(1.8, 2.6)
        r = np.tile(rl, 2)[:secs(rd)] * np.linspace(0.3, 1, secs(rd)) * 0.35
        crash = [s2, s3][rng.integers(2)][: secs(1.7)] * rng.uniform(0.5, 1.0)
        ev = np.zeros(secs(rd) + len(crash))
        ev[: len(r)] += r
        ev[secs(rd):secs(rd) + len(crash)] += crash
        ev = lowpass(ev, 1800 + 2500 * (1 - far), 2) * (1.1 - far)
        L, R = np.sqrt((1 - pan) / 2), np.sqrt((1 + pan) / 2)
        i = secs(t)
        m = min(len(ev), n - i)
        amb[i:i + m, 0] += ev[:m] * L
        amb[i:i + m, 1] += ev[:m] * R
        t += rng.uniform(1.4, 4.0)
    # distance: a soft tail of the room, made from decaying noise
    ir_n = secs(1.6)
    tt = np.arange(ir_n) / SR
    out = np.zeros_like(amb)
    for c in range(2):
        ir = lowpass(rng.standard_normal(ir_n), 2500) * np.exp(-6.9 * tt / 1.6)
        ir /= np.sqrt(np.sum(ir ** 2))
        wet = fftconvolve(amb[:, c], ir)
        w = wet[:n].copy()
        w[: len(wet) - n] += wet[n:]  # wrap the tail round so the loop is seamless
        out[:, c] = amb[:, c] * 0.45 + w * 0.9
    save("ambience_loop", loopify(out, 1.0), 0.6)

    for name, d in written:
        print(f"{name:20s} {d:5.2f}s")


if __name__ == "__main__":
    main()
