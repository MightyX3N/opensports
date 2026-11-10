#!/usr/bin/env python3
"""Generates the synthesised Open Sports sounds: menu sounds, result tunes and applause.
(The bowling hall sounds are cut from recordings by make_bowling.py.)

Run:  python3 tools/sfx/make_sounds.py        (needs numpy, scipy and ffmpeg)
Writes .ogg files into assets/sounds/. Same seed -> same files.

Techniques:
- impacts: modal synthesis -- a short force pulse (shorter = harder hit = brighter) drives a bank
  of two-pole resonators tuned to the object's vibration modes (van den Doel / Cook style).
  Pin modes come from free-free beam theory for a maple pin (~2.5 kHz, ratios 1 : 2.76 : 5.40).
- rolling: noise through the lane's low resonances, with slow wobble, looped seamlessly.
- applause: many independent clappers, each clap a short band-passed noise burst.
- voices: glottal pulse trains through moving vowel formants, many voices with jitter.
- room: everything in the hall goes through a synthetic hall impulse response.
"""
import os, subprocess, tempfile
import numpy as np
from scipy.signal import lfilter, fftconvolve, butter, sosfilt

SR = 44100
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
OUT = os.path.join(ROOT, "assets", "sounds")
rng = np.random.default_rng(20261110)


# ------------------------------------------------------------------ building blocks
def secs(t):
    return int(round(t * SR))


def tvec(dur):
    return np.arange(secs(dur)) / SR


def lowpass(x, f, order=2):
    return sosfilt(butter(order, f / (SR / 2), "low", output="sos"), x, axis=0)


def highpass(x, f, order=2):
    return sosfilt(butter(order, f / (SR / 2), "high", output="sos"), x, axis=0)


def bandpass(x, lo, hi, order=2):
    return sosfilt(butter(order, [lo / (SR / 2), hi / (SR / 2)], "band", output="sos"), x, axis=0)


def resonator(x, f, decay):
    """two-pole resonator at f Hz whose ring falls 60 dB over `decay` seconds"""
    r = np.exp(-6.91 / (decay * SR))
    w = 2 * np.pi * f / SR
    # b0 = sin(w): a unit impulse rings at amplitude 1 whatever the decay, so `gain` means loudness
    return lfilter([np.sin(w)], [1, -2 * r * np.cos(w), r * r], x)


def pulse(width):
    """contact force of a hit lasting `width` seconds (raised cosine)"""
    n = max(2, secs(width))
    return 0.5 - 0.5 * np.cos(2 * np.pi * np.arange(n) / n)


def modal(force, modes, dur):
    """modes = [(freq, decay, gain)]: run the force through every mode and sum"""
    x = np.zeros(secs(dur))
    x[: len(force)] += force
    y = np.zeros_like(x)
    for f, d, g in modes:
        if f < SR / 2 * 0.95:
            y += g * resonator(x, f, d)
    return y


def pink(n):
    w = rng.standard_normal(n)
    # Paul Kellet's economy pink filter
    b = [0.049922035, -0.095993537, 0.050612699, -0.004408786]
    a = [1, -2.494956002, 2.017265875, -0.522189400]
    return lfilter(b, a, w)


def brown(n):
    x = np.cumsum(rng.standard_normal(n))
    return highpass(x, 15)


def hall_ir(rt60=1.3, dur=None, predelay=0.012, bright=3500, stereo=False):
    dur = dur or rt60 * 1.1
    n = secs(dur)
    t = np.arange(n) / SR
    chans = []
    for _ in range(2 if stereo else 1):
        lo = lowpass(rng.standard_normal(n), 800) * np.exp(-6.91 * t / rt60)
        hi = highpass(rng.standard_normal(n), 800) * np.exp(-6.91 * t / (rt60 * 0.55))
        ir = lowpass(lo * 1.4 + hi * 0.5, bright)
        ir[: secs(0.004)] *= np.linspace(0, 1, secs(0.004))
        ir = np.concatenate([np.zeros(secs(predelay)), ir])
        chans.append(ir / np.sqrt(np.sum(ir * ir)))
    return np.stack(chans, 1) if stereo else chans[0]


IR = None


def room(x, wet=0.22, rt60=1.3, tail=None):
    """put a dry sound into the bowling hall"""
    global IR
    if IR is None or tail:
        IR = hall_ir(rt60)
    tail_n = len(IR)
    dry = np.concatenate([x, np.zeros(tail_n)])
    w = fftconvolve(dry, IR)[: len(dry)]
    w *= np.sqrt(np.mean(dry ** 2) / (np.mean(w ** 2) + 1e-12))
    y = dry * (1 - wet) + w * wet
    return trim(y)


def trim(x, floor=1e-4):
    a = np.abs(x)
    idx = np.nonzero(a > floor * a.max())[0]
    end = idx[-1] + 1 if len(idx) else len(x)
    y = x[:end].copy()
    f = min(len(y), secs(0.02))
    y[-f:] *= np.linspace(1, 0, f)
    return y


def norm(x, peak=0.89):
    return x * (peak / (np.max(np.abs(x)) + 1e-12))


def fade(x, a=0.002, b=0.01):
    x = x.copy()
    na, nb = secs(a), secs(b)
    if na:
        x[:na] *= np.linspace(0, 1, na)
    if nb:
        x[-nb:] *= np.linspace(1, 0, nb)
    return x


def mix_at(dst, src, t, gain=1.0):
    i = secs(t)
    if i >= len(dst):
        return
    n = min(len(src), len(dst) - i)
    if dst.ndim == 2 and src.ndim == 1:
        dst[i:i + n] += gain * src[:n, None]
    else:
        dst[i:i + n] += gain * src[:n]


def loopify(x, xf=0.5):
    """seamless loop: crossfade the tail into the head"""
    n = secs(xf)
    head, tail = x[:n], x[-n:]
    k = np.linspace(0, 1, n)
    if x.ndim == 2:
        k = k[:, None]
    # equal-power crossfade (noise is uncorrelated)
    return np.concatenate([tail * np.cos(k * np.pi / 2) + head * np.sin(k * np.pi / 2), x[n:-n]])


written = []


def save(name, x, peak=0.89, normalize=True):
    path = os.path.join(OUT, name + ".ogg")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    x = highpass(x, 20)
    if normalize:
        x = norm(x, peak)
    x = np.clip(x, -1, 1)
    ch = 1 if x.ndim == 1 else x.shape[1]
    pcm = (x * 32767).astype("<i2").tobytes()
    with tempfile.NamedTemporaryFile(suffix=".raw", delete=False) as f:
        f.write(pcm)
        raw = f.name
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le", "-ar", str(SR), "-ac", str(ch),
                    "-i", raw, "-c:a", "libvorbis", "-q:a", "5", path], check=True)
    os.unlink(raw)
    written.append((name, len(x) / SR))


# ------------------------------------------------------------------ objects
PIN_F1 = 2550.0  # free-free beam, maple, ~38 cm, ~5 cm mean radius
BEAM = [1.0, 2.756, 5.404]


def pin_modes(scale=1.0, damp=1.0, bright=1.0):
    """vibration modes of one pin, randomised a little (orientation, where it was struck)"""
    j = lambda s: 1 + rng.uniform(-s, s)
    f1 = PIN_F1 * scale * j(0.08)
    ms = []
    for k, ratio in enumerate(BEAM):
        ms.append((f1 * ratio * j(0.03), damp * [0.075, 0.035, 0.018][k] * j(0.2),
                   [1.0, 0.55 * bright, 0.25 * bright][k] * j(0.25)))
    # hollow plastic-coated neck/body: a lower "tok", and a couple of shell modes
    ms.append((930 * scale * j(0.1), damp * 0.03 * j(0.2), 0.55 * j(0.3)))
    ms.append((1650 * scale * j(0.1), damp * 0.025 * j(0.2), 0.45 * j(0.3)))
    ms.append((4100 * scale * j(0.1), damp * 0.012, 0.3 * bright * j(0.3)))
    return ms


def lane_modes(gain=1.0):
    """lane boards on their base: low knocks"""
    j = lambda s: 1 + rng.uniform(-s, s)
    return [(95 * j(0.1), 0.18, 1.0 * gain), (155 * j(0.1), 0.12, 0.8 * gain), (240 * j(0.1), 0.09, 0.6 * gain),
            (420 * j(0.1), 0.05, 0.4 * gain), (780 * j(0.1), 0.03, 0.25 * gain)]


def ball_modes(gain=1.0):
    j = lambda s: 1 + rng.uniform(-s, s)
    return [(2350 * j(0.04), 0.03, 0.3 * gain), (3900 * j(0.04), 0.02, 0.15 * gain)]


def click(width=0.0004, gain=1.0, hp=2000):
    n = secs(0.006)
    x = rng.standard_normal(n) * np.exp(-np.arange(n) / max(1, secs(width)))
    x = highpass(x, hp)
    return x / np.max(np.abs(x)) * gain


def add_click(y, *a, **k):
    """the contact transient, scaled to the body it sits on"""
    c = click(*a, **k) * np.max(np.abs(y))
    y[: len(c)] += c[: len(y)]
    return y


# ------------------------------------------------------------------ bowling sounds
def ball_drop(i):
    dur = 0.9
    f = pulse(0.004 + rng.uniform(0, 0.0015))
    y = modal(f, lane_modes() + ball_modes(0.4), dur)
    # the little second touch as the ball settles onto the lane
    y2 = modal(pulse(0.003) * 0.2, lane_modes(0.8), dur)
    y += np.concatenate([np.zeros(secs(0.055 + 0.02 * i)), y2])[: len(y)]
    y = add_click(y, 0.0008, 0.15, 800)
    return room(y, 0.25)


def ball_pin(i):
    dur = 0.6
    y = modal(pulse(0.0005 + rng.uniform(0, 0.0002)), pin_modes(bright=1.2) + ball_modes(0.6), dur)
    # the ball is heavy: a body thud under the crack
    y += modal(pulse(0.002), [(140, 0.08, 0.5), (230, 0.06, 0.4)], dur)
    y = add_click(y, 0.0003, 0.6)
    return room(y, 0.2)


def pin_pin(i):
    dur = 0.45
    w = 0.0003 + rng.uniform(0, 0.0005)
    y = modal(pulse(w), pin_modes(), dur) + modal(pulse(w), pin_modes(scale=rng.uniform(0.95, 1.05)), dur) * 0.8
    y = add_click(y, 0.0003, 0.4)
    return room(y, 0.2)


def pin_floor(i):
    dur = 0.55
    y = modal(pulse(0.0009 + rng.uniform(0, 0.0005)), pin_modes(damp=0.8, bright=0.7), dur)
    y += modal(pulse(0.0015), [(310 * rng.uniform(0.9, 1.1), 0.06, 0.8), (520, 0.04, 0.5), (180, 0.08, 0.6)], dur)
    # bounce
    b = modal(pulse(0.001) * 0.35, pin_modes(damp=0.7, bright=0.6), dur)
    y += np.concatenate([np.zeros(secs(0.07 + rng.uniform(0, 0.05))), b])[: len(y)]
    return room(y, 0.22)


def pin_wall(i):
    dur = 0.6
    y = modal(pulse(0.0008), pin_modes(bright=0.8), dur) * 0.8
    y += modal(pulse(0.002), [(165 * rng.uniform(0.9, 1.1), 0.12, 1.0), (290, 0.09, 0.7), (470, 0.06, 0.5), (850, 0.03, 0.3)], dur)
    return room(y, 0.25)


def pit_hit(i):
    dur = 1.2
    y = modal(pulse(0.012), [(55, 0.35, 1.0), (82, 0.3, 0.8), (130, 0.2, 0.5), (210, 0.12, 0.3)], dur)
    y += lowpass(rng.standard_normal(len(y)) * np.exp(-tvec(dur) / 0.05), 600) * 0.15  # curtain
    y = lowpass(y, 900)
    return room(y, 0.3)


def pin_pit(i):
    # pins dropping into the pit behind the curtain: muffled clatter
    dur = 0.9
    y = np.zeros(secs(dur))
    for k in range(rng.integers(2, 4)):
        p = modal(pulse(0.001), pin_modes(damp=0.6, bright=0.5), 0.4) * rng.uniform(0.4, 1)
        mix_at(y, p, 0 if k == 0 else rng.uniform(0.03, 0.25))
    y = lowpass(y, 1400)
    return room(y, 0.3)


def roll_loop(gutter=False):
    dur = 6.0
    n = secs(dur)
    t = np.arange(n) / SR
    src = brown(n) * 0.03 + pink(n) * 0.6
    if not gutter:
        modes = [(62, 0.5, 1.0), (96, 0.4, 0.9), (151, 0.35, 0.7), (228, 0.25, 0.5), (340, 0.18, 0.35), (520, 0.1, 0.2)]
        y = sum(g * resonator(src, f, d) for f, d, g in modes)
        y += bandpass(pink(n), 500, 2200) * 0.05  # urethane on the lane surface
        wob = 1 + 0.12 * np.sin(2 * np.pi * 1.0 * t) + 0.06 * np.sin(2 * np.pi * 2.5 * t + 1)
    else:
        modes = [(120, 0.25, 0.8), (240, 0.2, 0.8), (380, 0.15, 0.9), (610, 0.1, 0.6), (900, 0.06, 0.4)]
        y = sum(g * resonator(src, f, d) for f, d, g in modes)
        y += bandpass(pink(n), 800, 3500) * 0.12
        # rattles against the channel walls
        for k in range(int(dur * 7)):
            r = modal(pulse(0.002) * rng.uniform(0.2, 0.6), [(300 * rng.uniform(0.8, 1.2), 0.04, 1), (750, 0.02, 0.5)], 0.08)
            mix_at(y, norm(r, 1) * np.max(np.abs(y)) * 0.08 * rng.uniform(0.3, 1), rng.uniform(0, dur - 0.1))
        wob = 1 + 0.15 * np.sin(2 * np.pi * 1.6 * t)
    y = highpass(y * wob, 35)
    y = loopify(y, 0.5)
    return y


def sweep():
    # pinsetter: clunk, motor run with the bar sweeping, clunk
    dur = 2.4
    t = tvec(dur)
    env = np.clip(t / 0.15, 0, 1) * np.clip((2.0 - t) / 0.3, 0, 1)
    f0 = 48 + 6 * np.clip(t / 0.4, 0, 1)
    ph = 2 * np.pi * np.cumsum(f0) / SR
    motor = sum(np.sin(k * ph) / k for k in range(1, 12)) * 0.4
    motor += bandpass(rng.standard_normal(len(t)), 900, 3000) * 0.05 * (1 + 0.5 * np.sin(2 * np.pi * 23 * t))
    y = lowpass(motor, 1500) * env * 0.5
    for at, g in [(0.02, 1.0), (1.95, 0.8)]:
        c = modal(pulse(0.003), [(110, 0.15, 1), (260, 0.1, 0.8), (640, 0.05, 0.6), (1300, 0.03, 0.3)], 0.5) * g
        mix_at(y, norm(c, 1) * np.max(np.abs(y)) * 1.3, at)
    # the bar shoving fallen wood: a soft rattle in the middle
    for k in range(10):
        p = modal(pulse(0.001), pin_modes(damp=0.5, bright=0.5), 0.3) * rng.uniform(0.1, 0.3)
        mix_at(y, norm(lowpass(p, 2000), 1) * np.max(np.abs(y)) * 0.25 * rng.uniform(0.3, 1), rng.uniform(0.5, 1.4))
    return room(y, 0.3)


# ------------------------------------------------------------------ crowd
def applause(dur, people=14, rate=(3.2, 4.8), env=None, bright=1.0):
    n = secs(dur)
    y = np.zeros(n)
    for p in range(people):
        hz = rng.uniform(*rate)
        fc = rng.uniform(900, 2400) * bright
        start = rng.uniform(0, 0.25)
        stop = dur * rng.uniform(0.55, 0.95)
        t = start
        loud = rng.uniform(0.5, 1.0)
        while t < stop:
            m = secs(0.03)
            c = rng.standard_normal(m) * np.exp(-np.arange(m) / secs(rng.uniform(0.004, 0.009)))
            c = bandpass(c, fc * 0.55, min(fc * 1.8, 9000))
            g = loud * (1 - 0.7 * max(0, (t - stop * 0.6) / (stop * 0.4 + 1e-3)))
            mix_at(y, c * g * rng.uniform(0.7, 1.0), t)
            t += (1 / hz) * rng.uniform(0.85, 1.15)
    if env is not None:
        y *= env(np.arange(n) / SR)
    return y


VOWELS = {  # F1, F2, F3 (adult male); scaled up for higher voices
    "i": (270, 2290, 3010), "e": (480, 1900, 2500), "ae": (660, 1720, 2410), "a": (730, 1090, 2440),
    "o": (500, 850, 2400), "u": (320, 870, 2240), "aw": (600, 900, 2450),
}


def voice(dur, f0_curve, vowel_path, fscale=1.0, breath=0.15, loud_curve=None):
    """one shouting voice: glottal pulses through moving formants (block-wise filter update)"""
    n = secs(dur)
    t = np.arange(n) / SR
    f0 = f0_curve(t) * (1 + 0.012 * np.sin(2 * np.pi * rng.uniform(4.5, 6.5) * t + rng.uniform(0, 6)))
    f0 *= 1 + 0.004 * rng.standard_normal(n).cumsum() / np.sqrt(np.arange(1, n + 1))  # drift
    ph = np.cumsum(f0) / SR % 1.0
    # Rosenberg glottal pulse, then its derivative (lip radiation)
    op = 0.55
    g = np.where(ph < op, 0.5 * (1 - np.cos(np.pi * ph / op)), np.cos(np.pi * (ph - op) / (2 * (1 - op))).clip(0))
    src = np.diff(g, prepend=g[0]) * 30
    src += rng.standard_normal(n) * breath * 0.3
    # formant trajectory: vowel_path = [(time_fraction, vowel)]
    keys = [(a * dur, np.array(VOWELS[v]) * fscale) for a, v in vowel_path]

    def formants_at(tt):
        for (ta, fa), (tb, fb) in zip(keys, keys[1:]):
            if tt <= tb:
                k = 0 if tb == ta else np.clip((tt - ta) / (tb - ta), 0, 1)
                k = k * k * (3 - 2 * k)
                return fa + (fb - fa) * k
        return keys[-1][1]

    bws = (90, 110, 160)
    gains = (1.0, 0.6, 0.3)
    out = np.zeros(n)
    blk = 256
    zis = [np.zeros(2) for _ in range(3)]
    for s in range(0, n, blk):
        e = min(n, s + blk)
        F = formants_at(t[s])
        for k in range(3):
            r = np.exp(-np.pi * bws[k] / SR)
            w = 2 * np.pi * F[k] / SR
            a = [1, -2 * r * np.cos(w), r * r]
            b = [(1 - r) * gains[k] * 2]
            yk, zis[k] = lfilter(b, a, src[s:e], zi=zis[k])
            out[s:e] += yk
    env = np.clip(t / 0.06, 0, 1) * np.clip((dur - t) / 0.18, 0, 1)
    if loud_curve:
        env *= loud_curve(t)
    return highpass(out * env, 90)


def crowd_voices(dur, kind, people):
    y = np.zeros(secs(dur))
    for p in range(people):
        female = rng.random() < 0.45
        base = rng.uniform(200, 270) if female else rng.uniform(105, 150)
        fs = rng.uniform(1.12, 1.2) if female else rng.uniform(0.95, 1.05)
        st = rng.uniform(0, 0.35)
        d = rng.uniform(0.7, 1.3) if kind != "aww" else rng.uniform(1.0, 1.6)
        d = min(d, dur - st - 0.05)
        if kind == "yeah":
            hi = base * rng.uniform(1.5, 1.9)
            f0c = lambda t, b=base, h=hi, d=d: b + (h - b) * np.clip(t / (0.25 * d), 0, 1) - (h - b) * 0.4 * np.clip((t - 0.5 * d) / (0.5 * d), 0, 1)
            path = [(0, "i"), (0.15, "e"), (0.4, "ae"), (1, "ae")] if rng.random() < 0.6 else [(0, "u"), (0.5, "u"), (1, "u")]
        elif kind == "aww":
            hi = base * rng.uniform(1.35, 1.6)
            f0c = lambda t, b=base, h=hi, d=d: h - (h - b * 0.85) * np.clip(t / d, 0, 1) ** 0.8
            path = [(0, "a"), (0.5, "aw"), (1, "o")]
        else:  # "ooh" -- impressed
            hi = base * rng.uniform(1.4, 1.6)
            f0c = lambda t, b=base, h=hi, d=d: b * 1.1 + (h - b) * np.sin(np.pi * np.clip(t / d, 0, 1))
            path = [(0, "o"), (0.4, "u"), (1, "u")]
        v = voice(d, f0c, path, fs, breath=rng.uniform(0.1, 0.3))
        v = norm(v, 1) * rng.uniform(0.35, 1.0)
        mix_at(y, v, st)
    return y


def crowd(kind):
    """applause only (synthesised voices sounded fake); dry -- the game adds the room"""
    if kind == "strike":
        y = applause(3.4, 18, (3.8, 5.2))
    else:
        y = applause(2.6, 11, (3.4, 4.6))
    return trim(lowpass(y, 7000))


def ambience():
    """30 s of the rest of the hall: other lanes rolling and striking, far away. Stereo."""
    dur = 30.0
    n = secs(dur)
    y = np.zeros((n, 2))
    # room tone
    tone = lowpass(pink(n), 300) * 0.02 + lowpass(brown(n), 120) * 0.0004
    y += tone[:, None]
    roll = roll_loop()
    t = 0.4
    while t < dur - 1:
        pan = rng.uniform(-1, 1)
        L, R = np.sqrt((1 - pan) / 2), np.sqrt((1 + pan) / 2)
        dist = rng.uniform(0.25, 1.0)
        rd = rng.uniform(2.0, 2.8)
        seg = roll[: secs(rd)].copy() * np.clip(np.arange(secs(rd)) / secs(0.4), 0, 1)
        ev = np.zeros(secs(rd + 1.0))
        ev[: len(seg)] += seg * 0.25
        # the crash at the end: a burst of pin clacks
        hits = rng.integers(4, 22)
        for k in range(hits):
            p = modal(pulse(0.0004 + rng.uniform(0, 0.0005)), pin_modes(), 0.3)
            mix_at(ev, norm(p, 1) * rng.uniform(0.2, 1.0) * np.max(np.abs(seg)) * 0.35, rd + rng.exponential(0.12))
        ev = lowpass(ev, 2500 + 3000 * (1 - dist))
        ev *= dist * 0.5
        mix_at(y, np.stack([ev * L, ev * R], 1), t)
        t += rng.uniform(1.5, 4.5)
    irs = hall_ir(2.2, stereo=True)
    wet = np.stack([fftconvolve(y[:, c], irs[:, c])[:n] for c in range(2)], 1)
    # wrap the reverb tail round so the loop is seamless
    tail = np.stack([fftconvolve(y[:, c], irs[:, c])[n:] for c in range(2)], 1)
    wet[: len(tail)] += tail
    out = y * 0.35 + wet * 1.2
    return loopify(out, 1.0)


# ------------------------------------------------------------------ music stingers
def note_hz(n):
    return 440 * 2 ** ((n - 69) / 12)


def mallet(f, dur=0.9, bright=1.0):
    """marimba-ish: tuned bar modes 1 : 3.93 : 9.2 (Rossing)"""
    return modal(pulse(0.0012 / bright), [(f, 0.5 * dur, 1.0), (f * 3.93, 0.12 * dur, 0.35 * bright),
                                          (f * 9.2, 0.04 * dur, 0.1 * bright)], dur)


def brass(f, dur, attack=0.03):
    t = tvec(dur)
    ph = 2 * np.pi * np.cumsum(f * (1 + 0.004 * np.sin(2 * np.pi * 5.5 * t) * np.clip(t / 0.3, 0, 1))) / SR
    saw = sum(np.sin(k * ph) / k * (0.92 ** k) for k in range(1, 20))
    env = np.clip(t / attack, 0, 1) * np.clip((dur - t) / 0.12, 0, 1)
    # opening filter like a brass swell
    cut = 600 + 3500 * np.clip(t / 0.12, 0, 1)
    out = np.zeros_like(saw)
    blk = 512
    for s in range(0, len(saw), blk):
        e = min(len(saw), s + blk)
        out[s:e] = lowpass(saw[max(0, s - 2048):e], min(cut[s], 18000))[-(e - s):]
    return out * env


def chord(notes, fn, **kw):
    parts = [fn(note_hz(n), **kw) for n in notes]
    m = max(len(p) for p in parts)
    y = np.zeros(m)
    for p in parts:
        y[: len(p)] += p
    return y


def jingle(kind):
    if kind == "strike":
        y = np.zeros(secs(2.2))
        for i, n in enumerate([60, 64, 67, 72, 76]):
            mix_at(y, mallet(note_hz(n + 12), 0.6), i * 0.065, 0.6)
        mix_at(y, chord([60, 64, 67, 72], brass, dur=1.3) * 0.12, 0.33)
        mix_at(y, chord([72, 76, 79, 84], mallet, dur=1.4) * 0.35, 0.33)
    elif kind == "spare":
        y = np.zeros(secs(1.6))
        for i, n in enumerate([67, 72, 76]):
            mix_at(y, mallet(note_hz(n + 12), 0.6), i * 0.07, 0.6)
        mix_at(y, chord([72, 76, 79], mallet, dur=1.2) * 0.4, 0.21)
        mix_at(y, chord([60, 67, 72], brass, dur=0.9) * 0.08, 0.21)
    elif kind == "gutter":
        # sad "wah wah": two falling brass notes with a slide
        y = np.zeros(secs(1.6))
        for i, (a, b) in enumerate([(58, 57), (55, 52)]):
            d = 0.45 if i == 0 else 0.9
            t = tvec(d)
            fcur = note_hz(a) + (note_hz(b) - note_hz(a)) * np.clip((t - 0.1) / (d - 0.1), 0, 1)
            ph = 2 * np.pi * np.cumsum(fcur * (1 + 0.012 * np.sin(2 * np.pi * 6 * t))) / SR
            saw = sum(np.sin(k * ph) / k for k in range(1, 16))
            wah = lowpass(saw, 1400) * (0.6 + 0.4 * np.sin(np.pi * np.clip(t / d, 0, 1)))
            wah *= np.clip(t / 0.03, 0, 1) * np.clip((d - t) / 0.1, 0, 1)
            mix_at(y, wah, 0 if i == 0 else 0.5)
    elif kind == "split":
        y = np.zeros(secs(1.0))
        for i, n in enumerate([71, 65]):
            mix_at(y, mallet(note_hz(n + 12), 0.5), i * 0.12)
    elif kind == "gameover":
        y = np.zeros(secs(2.6))
        for i, n in enumerate([60, 62, 64, 67, 69, 72]):
            mix_at(y, mallet(note_hz(n + 12), 0.5), i * 0.09, 0.5)
        mix_at(y, chord([60, 64, 67, 71, 74], mallet, dur=1.8) * 0.35, 0.56)
        mix_at(y, chord([48, 60, 64, 67], brass, dur=1.5, attack=0.08) * 0.09, 0.56)
    return room(y, 0.18, rt60=1.0)


# ------------------------------------------------------------------ menu sounds
def ui(kind):
    if kind == "move":
        y = modal(pulse(0.0006), [(1850, 0.05, 1.0), (1850 * 2.76, 0.02, 0.3)], 0.12)
    elif kind == "select":
        y = np.zeros(secs(0.35))
        mix_at(y, mallet(note_hz(79), 0.35), 0)
        mix_at(y, mallet(note_hz(84), 0.45), 0.06)
    elif kind == "back":
        y = np.zeros(secs(0.35))
        mix_at(y, mallet(note_hz(79), 0.35), 0)
        mix_at(y, mallet(note_hz(74), 0.45), 0.06)
    elif kind == "toggle":
        y = mallet(note_hz(81), 0.3)
    elif kind == "start":
        y = np.zeros(secs(1.0))
        for i, n in enumerate([72, 76, 79, 84]):
            mix_at(y, mallet(note_hz(n), 0.6), i * 0.05, 0.7)
    elif kind == "error":
        y = np.zeros(secs(0.4))
        mix_at(y, mallet(note_hz(62), 0.3, 0.6), 0)
        mix_at(y, mallet(note_hz(61), 0.35, 0.6), 0.09)
    elif kind == "connect":
        y = np.zeros(secs(0.7))
        for i, n in enumerate([76, 83, 88]):
            mix_at(y, mallet(note_hz(n), 0.4), i * 0.08, 0.7)
    return fade(trim(y), 0.0005, 0.02)


# ------------------------------------------------------------------ write everything
def main():
    # the bowling hall sounds (pins, ball, roll, ambience) come from recordings: make_bowling.py
    B = "bowling/"
    for k in ["strike", "spare"]:
        save(B + f"crowd_{k}", crowd(k), 0.8)
    for k in ["strike", "spare", "gutter", "split", "gameover"]:
        save(B + f"jingle_{k}", jingle(k), 0.75)
    for k in ["move", "select", "back", "toggle", "start", "error", "connect"]:
        save("ui/" + k, ui(k), 0.6)
    for name, d in written:
        print(f"{name:28s} {d:5.2f}s")


if __name__ == "__main__":
    main()
