# Baseball (Wii Sports) — pitching and batting

Read from the EU `SportsPackEP.dol`. Units: 1 unit ≈ 10 cm, 60 frames per second.
These are notes on how the original behaves. No Nintendo code or data goes in this repo.

## Pitch choice (`fn_802A4A48`)

**Button held → pitch type:**

| Held | Type |
|---|---|
| nothing | 0 |
| A + B | 1 |
| B | 2 |
| A | 3 |

**Other inputs:**
- The D-pad picks the location: left, middle or right. It is mirrored for left-handed batters.
- Buttons 1 and 2 set another flag (`unk26`). Its purpose isn't confirmed.

Commonly, A and B are described as the two curve directions and A+B as the slow pitch. The tables below agree:

| Type | Speed (units/frame) | Sideways break (rad) | Vertical (min → max) |
|---|---|---|---|
| 0 | 3.0 → 4.4 | −0.014 / 0 / +0.014 | +0.01 → −0.04 |
| 1 (A+B) | 3.0 → 3.3 (slow) | −0.015 / 0 / +0.015 | +0.02 → +0.01 |
| 2 (B) | 2.8 → 4.0 | −0.058 … −0.036 | +0.02 → −0.01 |
| 3 (A) | 2.8 → 4.0 | +0.036 … +0.058 | +0.02 → −0.01 |

3.0–4.4 units/frame is about 18–26 m/s in world units. The game is not to real scale.

## Pitch launch (`fn_802A19C8`)

1. Power comes from the remote's swing strength, clamped to 0–1, then shaped by a curve (×1.4).
2. Speed is blended from the type's min to max by power. Vertical aim is blended the same way.
3. The aim direction is turned by the type's sideways break angle.
4. A small random scatter is added on each axis.
5. A second vector, from a per-type table, gives the curve force applied while the ball flies.

**CPU pitching** (`fn_802A3C8C`) depends on difficulty (0.333 / 0.666 / higher):
- Low difficulty: always type 0, middle location.
- Middle: random power up to 0.2 and random type, but never A+B.
- High: random power up to 0.9, any type, any location.

## Bat contact (`fn_80291C44` → `fn_80292004`)

- **Collision.** The bat is a moving segment (last frame → this frame), tested against the ball as a sphere.
- **Sweet spot** (`fn_80292964`): the position along the bat, from 0 (handle) to 1 (tip), sets how much power the hit gets.
  - 0–0.2: about ×0.2–0.35 (halved)
  - 0.2–0.45: rises from ×0.4 to ×0.8
  - 0.45–0.85: rises to ×1.25 (best around 0.65–0.85)
  - 0.85–1.0 (tip): drops from ×1.25 to ×0.1
- **Exit speed.** Comes from the bat's speed plus the contact point.
  - Above 0.5 it is halved.
  - Below 6.0 it is scaled with 0.4, 0.9 and 0.2 factors.
- **"Just meet"** (perfect hit): plays an effect and counts in the stats. Hit quality = `1 + (π − angle)`, clamped to 1–3.
- **Bounce** (`fn_8028B570`): the speed is reflected around the ground or wall normal, then multiplied by a restitution value.

## Still open
- The per-type curve force vectors are built at run time, so they need a run-time capture or a closer asm read.
- What the 1/2-button flag does.

## For Open Sports
- Put pitch types in a data table (speed range, break, drop, curve force) so add-ons can add new pitches.
- Make the sweet-spot curve a tunable table along the bat.
