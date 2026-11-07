# Bowling: how the original swing works

Research notes from studying Wii Sports (EU bundle build, `SportsPackEP.dol`) to understand its behaviour.
Written in our own words as a reference for designing Open Sports' own implementation. No original code or data is included.

Wii Sports Resort ships a byte-identical bowling tuning table, so the same model applies to both games.

## Input

- The game keeps a ring buffer of controller samples. Each sample holds the tilt values and an acceleration vector (in g), plus a second vector.
- Arm angle is taken from the direction of gravity: `atan2` of two accelerometer axes.
- Samples with any axis at or above **3.5 g** are treated as clipped (the Wii Remote's accelerometer saturates) and are skipped when judging a release.
- Wii Sports bowling uses **only the accelerometer**, because it predates MotionPlus.

## Swing state machine (one step per frame)

| State | What happens |
| --- | --- |
| 0 Ready | Counts frames where motion stays under **0.06 g**. The arm angle is low-pass filtered (10% per frame). |
| 1 Hold steady | Over the last **30** samples, angle change must stay under **0.08** and motion under **0.08**. Then the hanging-arm angle becomes the baseline. |
| 2 Swing | Pendulum model, not 1:1 tracking (see below). Also counts acceleration peaks over the last 3 samples (thresholds **0.9** and **1.5**). |
| 3 Abort check | If the angle jumps or the motion spikes past limits, the throw is cancelled. |
| 4 Release | Works out power and spin from the recent samples (see below), then hands the result to the ball. |

### Pendulum swing (state 2)

- Swing speed eases toward `|accel| − 1 g` × **0.08**, at 20% per frame.
- Arm angle advances by speed × **0.2** each frame.
- Once the arm passes horizontal (90°), a brake of **0.05** per frame slows it. This gives the "heavy ball" feel.
- Release triggers when the swing speed drops under **0.3** after at least two peaks, with `|accel| − 1 g` above **0.8** and no clipped samples.

### Release (state 4)

- **Power** is the peak acceleration magnitude over the last **6** samples.
- **Spin**: the game takes the 2D cross product of consecutive acceleration samples on the axes that change when you twist your wrist. It sums positive and negative values separately, normalises by peak power and sample count, and compares the result against a threshold. The sign gives the spin direction, and a value under the threshold means a straight ball.
- A second score sorts recent `|accel|` and `|Δaccel|` values from highest to lowest and adds up the top few with two weights. That combines peak force and how sharp the flick was.

## Tuning table (`BowExcelGlobal`)

11,236 bytes of big-endian values exported from a designer spreadsheet. No field names in the file; meanings come from the code that reads them.

| Offset | Value | Meaning |
| --- | --- | --- |
| `0x64` | 0.05 | Swing brake once the arm passes 90° |
| `0x68` | 0.2 | Arm-angle step per frame |
| `0x6C` | 0.08 | Swing gain from acceleration |
| `0x70` | 0.08 | Gain used when measuring release motion |
| `0x74` | 60 | Frame count (not identified yet) |
| `0x98` | 6 | Sample count (not identified yet) |
| `0x9C` | 0.13 | Motion limit in the release check |
| `0xB0` | 0.08 | Motion limit during swing |
| `0xB4` / `0xB8` | 0.15 / 0.08 | Abort limits: angle jump / motion spike |
| `0xBC` | 30 | Hold-steady window (samples) |
| `0xC0` / `0xC4` | 0.08 / 0.08 | Hold-steady tolerances: angle / motion |
| `0xCC` | 30 | Frames of stillness needed |
| `0xD0` | 0.06 | Stillness threshold (g) |

Still to do: the rest of the table, the ball–pin physics, the lane's oil/friction model, and the CPU bowlers.

## What this means for Open Sports

- **Arcade mode** can use the same kind of pendulum model. It needs only an accelerometer, so it works on Wii Remote, Joy-Con, Joy-Con 2 and phones.
- **Realistic mode** can add the gyro for true 1:1 arm tracking and real wrist rotation for spin.
- Every threshold above becomes a named field in our tuning table, so mods and the Custom mode can change them.
