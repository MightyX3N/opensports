#!/usr/bin/env python3
"""Generates the synthesised tennis sounds (our own, like make_sounds.py, whose building
blocks it uses): racket hits, bounces on grass, the net, swishes, applause, the outdoor
ambience and the result tunes.

Run:  python3 tools/sfx/make_tennis.py        (needs numpy, scipy and ffmpeg)
Writes .ogg files into assets/sounds/tennis/.

- racket hit: a short hard contact drives the string bed (a stiff membrane: ~500 Hz and its
  overtones, quick decay), the hollow ball's shell (~1 kHz "pock") and the frame (low, very short).
- bounce: a softer, longer contact into the ball shell only, low-passed (grass absorbs the top).
- net: a soft thud plus the mesh rattling (many tiny band-passed noise ticks).
- outdoors: next to no reverb, a little early reflection from the stands.
"""
import os, sys
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_sounds as S  # noqa: E402
from make_sounds import secs, tvec, lowpass, highpass, bandpass, modal, pulse, pink, brown, norm, fade, trim, mix_at, loopify  # noqa: E402

rng = np.random.default_rng(20261111)
T = "tennis/"


def outdoors(x, wet=0.08):
    """a few early reflections off the stands, no hall tail"""
    y = np.concatenate([x, np.zeros(secs(0.25))])
    for d, g in [(0.031, 0.5), (0.047, 0.35), (0.083, 0.25), (0.121, 0.15)]:
        refl = lowpass(np.concatenate([np.zeros(secs(d)), x]), 3500)[: len(y)]
        y[: len(refl)] += refl * g * wet / 0.5
    return y


def hit(i, hard=1.0):
    width = 0.0045 - 0.0015 * hard + rng.uniform(-0.0003, 0.0003)
    f = pulse(width) * hard
    strings = [(520 * rng.uniform(0.95, 1.05), 0.05, 1.0), (1080, 0.035, 0.55), (1630, 0.025, 0.3), (2400, 0.018, 0.15)]
    shell = [(980 * rng.uniform(0.95, 1.05), 0.03, 0.7), (1950, 0.02, 0.3)]
    frame = [(150, 0.03, 0.6), (330, 0.02, 0.3)]
    y = modal(f, strings + shell + frame, 0.25)
    click = highpass(rng.standard_normal(secs(0.003)) * np.exp(-np.arange(secs(0.003)) / secs(0.0007)), 2500)
    mix_at(y, click * np.max(np.abs(y)) * 0.5 * hard, 0)
    return fade(trim(outdoors(y)), 0.0003, 0.02)


def bounce(i):
    f = pulse(0.006 + rng.uniform(-0.0005, 0.0005))
    y = modal(f, [(280 * rng.uniform(0.9, 1.1), 0.03, 1.0), (950, 0.02, 0.45), (1900, 0.012, 0.15)], 0.15)
    y += bandpass(rng.standard_normal(len(y)), 200, 1500) * np.exp(-np.arange(len(y)) / secs(0.006)) * 0.15
    y = lowpass(y, 2600)
    return fade(trim(outdoors(y, 0.05)), 0.0005, 0.02)


def net():
    dur = 0.6
    y = modal(pulse(0.012), [(90, 0.12, 1.0), (180, 0.08, 0.6), (420, 0.04, 0.3)], dur)
    y = norm(y, 1.0)
    for k in range(70):
        at = rng.exponential(0.07)
        if at > dur - 0.05:
            continue
        m = secs(0.01)
        tick = rng.standard_normal(m) * np.exp(-np.arange(m) / secs(0.002))
        tick = bandpass(tick, 700, 3200)
        mix_at(y, norm(tick, 1) * 0.12 * np.exp(-at / 0.15), at)
    return fade(trim(outdoors(y)), 0.001, 0.05)


def swish(hard=1.0):
    dur = 0.28
    n = secs(dur)
    t = tvec(dur)
    x = rng.standard_normal(n)
    y = np.zeros(n)
    blk = 256
    for s in range(0, n, blk):
        k = s / n
        fc = 450 + 1700 * np.sin(np.pi * k) * hard
        seg = bandpass(x[max(0, s - 512): s + blk], fc * 0.7, fc * 1.4)
        y[s: s + blk] = seg[-len(y[s: s + blk]):]
    env = np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 2
    return fade(y * env, 0.002, 0.03)


def crowd_point(big=False):
    dur = 4.0 if big else 2.6
    y = S.applause(dur, people=40 if big else 22, rate=(3.5, 5.2), bright=1.15)
    y += S.applause(dur, people=30 if big else 14, rate=(3.0, 4.6), bright=0.8) * 0.7
    if big:
        y += S.crowd_voices(dur, "strike", 10) * 0.25
    return fade(outdoors(highpass(y, 150), 0.12), 0.01, 0.3)


def ambience():
    dur = 10.0
    n = secs(dur)
    t = tvec(dur)
    wind = lowpass(brown(n), 400) * (1 + 0.4 * np.sin(2 * np.pi * 0.11 * t) + 0.2 * np.sin(2 * np.pi * 0.27 * t + 1))
    leaves = bandpass(pink(n), 2000, 6000) * 0.04 * (1 + 0.6 * np.sin(2 * np.pi * 0.13 * t + 2))
    murmur = bandpass(pink(n), 250, 900) * 0.12
    y = norm(wind, 1) * 0.5 + norm(leaves, 1) * 0.12 + norm(murmur, 1) * 0.25
    # a few birds far away
    for k in range(6):
        at = rng.uniform(0.3, dur - 0.6)
        f0 = rng.uniform(3000, 4500)
        for c in range(rng.integers(2, 5)):
            m = secs(0.07)
            tt = np.arange(m) / S.SR
            ch = np.sin(2 * np.pi * (f0 + 1500 * tt / 0.07) * tt) * np.sin(np.pi * tt / 0.07) ** 2
            mix_at(y, ch * 0.05, at + c * 0.11)
    return loopify(highpass(y, 40), 0.6)


def main():
    for i in range(3):
        S.save(T + f"hit_{i + 1}", hit(i, 0.7 + 0.15 * i), 0.85)
    for i in range(2):
        S.save(T + f"bounce_{i + 1}", bounce(i), 0.8)
    S.save(T + "net", net(), 0.8)
    S.save(T + "swish", swish(), 0.6)
    S.save(T + "crowd_point", crowd_point(), 0.75)
    S.save(T + "crowd_game", crowd_point(True), 0.8)
    S.save(T + "ambience_loop", ambience(), 0.5)
    S.save(T + "jingle_game", S.jingle("spare"), 0.75)
    S.save(T + "jingle_match", S.jingle("strike"), 0.75)
    S.save(T + "jingle_lose", S.jingle("gutter"), 0.7)
    for name, d in S.written:
        print(f"{name:28s} {d:5.2f}s")


if __name__ == "__main__":
    main()
