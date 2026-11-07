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

Still to do: the rest of the table and the CPU bowlers.

## Physics

### Units and steps

- **1 unit ≈ 10 cm.** The ball radius is 1.075, and the pin deck starts at z = −192 (about 19.2 m from the player). The pit is at z ≈ −200.
- **4 physics sub-steps per frame** at 60 fps (2 in some cases), so 240 steps a second.
- Velocities are stored as **distance per step**, not per second.

### Rigid-body step (shared physics library, used by ball and pins)

Each step, in this order:

1. **Sleep check:** if both linear speed and spin are under a threshold, the body is put to rest (velocities zeroed). The spin threshold is the linear one divided by a ratio.
2. **Drag:** velocity and spin each lose a fixed fraction (`v -= v × drag`).
3. **Gravity:** a constant is subtracted from vertical velocity.
4. **Move:** `position += velocity` (semi-implicit Euler).
5. **Rotate:** the orientation matrix is turned by the spin, then re-orthonormalised with cross products, with a fallback for degenerate cases.

The physics engine is small and fixed-step, with no solver iterations. Stability comes from the sub-steps, the drag and the sleep threshold.

### The roll and the pin deck

- **Rolling ball:** the ball's drag is swapped to **0.002** under some conditions, most likely the oiled part of the lane, where a real ball skids instead of hooking. It's restored afterwards.
- **Gutter:** the ball is flagged as a gutter ball once it drifts sideways past a set distance from the lane centre.
- **Pin deck:** the game switches state when the ball passes z = −192. From then on, ball–pin, pin–pin and pin–floor collisions run every sub-step.
- **Settling trick:** about **1 second** after the ball reaches the pins, pin damping starts **ramping up every frame**. The linear part starts at 0.001 and grows by 0.001/120 a frame, and the spin part does the same from 0.07. Pins can't wobble forever, which keeps turns short.
- **End of turn:** the turn ends once the pins have settled or after a timeout (480 frames, 8 s; 900 frames overall).
- **Randomness:** ball–pin hits multiply the impact by a random factor between **0.3 and 0.8**, so identical throws don't always give identical results.
- **Instant replay:** the game stores **15 snapshots** of the ball, every pin and the throw state, which it uses for replays.

### Physics settings

A setup function fills a 720-byte struct with about 180 hardcoded values. These are not in the tuning file. Confirmed so far:

| Value | Meaning |
| --- | --- |
| −192 | Pin-deck start (z) |
| −193 / −197 / −200 | Pin deck back / pit edges |
| 1.075 | Ball radius |
| 0.002 | Ball drag while skidding |
| 0.001 → +0.001/120 per frame | Pin linear-damping ramp after ~1 s |
| 0.07 → +0.07/120 per frame | Pin spin-damping ramp after ~1 s |

The struct also holds two tables of 8 values between 0.3 and 0.65. They're probably pin profile radii: a real pin's belly radius is ≈ 0.6 units and its neck ≈ 0.23. It also has a table of 10 small values (0.007–0.03), one per pin position. Neither is confirmed yet.

### What this means for Open Sports

- A small fixed-step rigid-body solver with drag, a sleep threshold and sub-steps is enough. We don't need a full physics engine, which keeps it identical across LÖVE and GMod.
- Copy the **damping ramp** after impact, so turns end quickly even with 1,000 pins.
- Pins as **stacked spheres** (8 per pin) keep pin-vs-pin collisions cheap.
- Make the **random factor** a tuning value. Arcade keeps it, Realistic can set it to zero or a narrow range.

## What this means for Open Sports

- **Arcade mode** can use the same kind of pendulum model. It needs only an accelerometer, so it works on Wii Remote, Joy-Con, Joy-Con 2 and phones.
- **Realistic mode** can add the gyro for true 1:1 arm tracking and real wrist rotation for spin.
- Every threshold above becomes a named field in our tuning table, so mods and the Custom mode can change them.
