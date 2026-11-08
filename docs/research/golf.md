# Golf (Wii Sports) — swing and ball

Read from the EU `SportsPackEP.dol`. Units: 1 unit ≈ 10 cm, 60 frames per second.
Much of golf uses paired-single math, which the decompiler can't read, so parts were read from the assembly. No Nintendo code or data goes in this repo.

## Swing tracking (`fn_802EB9FC`, `fn_802EB548`, `fn_802EBE64`)

- **Club angle.** The remote's pitch drives a backswing angle (`unkC0`).
  - Each frame the club's angular speed is pushed toward the remote and damped: ×0.99 per frame, rising to ×0.999 when the swing is steady.
  - The angle is clamped between −0.06 and +0.12 rad per frame of change.
- **Backswing amount** (`unkC4`): `0.5 × (1 + angle / max)`, clamped 0–1. This is what fills the power meter.
- **Shaping.** A soft power curve `sign(x)·|x|^k` (`fn_802DB8A4`) is used throughout to ease the inputs.
- **Holding still.** While the remote is still, the speed is damped between 0.95 and 0.99 depending on how still it is.
- **Putting** (mode 3) uses its own branch. The meter maps to 0–0.1 instead of the full range.

## Ball in flight and rolling (`fn_802D0ADC`)

Each frame:
1. **Spin curve.** Velocity += a sideways direction × `0.0012 × spinA × k`. spinA decays ×0.9985 per frame.
2. **Second spin.** Velocity += the flat perpendicular `(vz, 0, −vx)` × `0.001 × spinB × k`. spinB decays ×0.997 per frame.
   - So one spin bends the ball sideways (hook/slice) and the other lifts or drops it, with slow decay.
3. **Wind**, only while in the air: velocity += `0.00008 × (0.6 × a + b)`, using the course wind object (`fn_802C9280`).
4. **Stopping.** The ball counts as stopped after 20 frames below 0.0015 units/frame (0.05 on surface type 14).
5. **Time-out.** The ball is forced to stop after 7,200 frames (2 minutes).

**Bounce** (`fn_802D0698`):
- Friction is blended from 0.07 to 1.0 by how steeply the ball hits; 0.25 of the normal speed gives full grip.
- Spin is cleared on every bounce.

**Lie.** Surface types are a bitmask (`0x1CE5E` = surfaces where the ball may rest), with a separate rule for water and out-of-bounds (`fn_802D11B0`).

## Course data
`fn_802D6030` writes a table of hole positions (tee and pin points, e.g. `(93, 140.3, −1522.8)`). The course converter can read these from the user's own disc at run time.

## Shot launch (solved)

**Club set-up.** Four club objects are built in `fn_802E2150`: wood, iron, sand wedge and putter.
- Each has its own vtable.
- Slot `+0x0C` launches the ball, slot `+0x10` sets side spin and slot `+0x14` measures the swing error.

**Launch** (`fn_802DF824`):
1. `p = curve(k, min(power, 1))`, where power is the meter reading and `curve` is `fn_802DB8A4`, the soft power curve.
2. Direction = the aim direction, tilted up by the club's loft.
3. Speed = `min + p × (max − min)`.
4. Ball spin A (lift; decays ×0.9985 per frame) = `lift × p`.
5. Ball spin B (side) starts at 0.

| Club | Curve k | Min speed | Max speed | Loft | Lift spin factor | Side spin factor |
|---|---|---|---|---|---|---|
| Wood | 0.70 | 0.02 | 3.32 | 11° | 0.7 | 0.5 |
| Iron | 0.656 | 0.02 | 2.30 | 25° | 0.5 | 0.6 |
| Sand wedge | 0.64 | 0.01 | 1.28 | 43° | 0 | 0.6 |
| Putter | 0.63 | 0.004 | 0.41 | 0° | 0 | 0 |

Speeds are in units per frame. The golf course is not at real scale, so these numbers only make sense against the game's own courses.

**Hook and slice** (`fn_802EAC94`, `fn_802EDD98`, `fn_802D1880`):
- The meter can go up to 1.25, so you can overswing past 100 %.
- When the swing doesn't match the meter, the error `d` is mapped to a curve strength:
  - `d < 0.25`: 0.2 rising to 1.0
  - `d ≥ 0.25`: 1.0 rising to a cap of 2.6
- After launch, side spin = the club's side spin factor × that strength.
- The direction (hook or slice) comes from whether a swing frame counter is odd or even at that moment. In practice that is a coin flip, not something the player controls.
- Another branch (`fn_802DFA98`) handles putting and an accuracy mode: the miss is eased with distance bands of 5–150 and 20–75.

## Still open
- Nothing major is left for golf. `fn_802DFA10`, which gives the actual swing value compared against the meter, is a jump-table function that the decompiler couldn't handle. Its exact formula would need an asm read.

## For Open Sports
- The club table above is plain data, so add-ons can add clubs (a driver, a 5-iron, a lob wedge).
- Our Arcade mode can keep the random hook/slice; Realistic mode should base it on the remote's twist at impact.
- Spin decay rates, wind strength and the friction curve are tuning values.
- Surface types become materials in the course file, so add-on courses can define their own.
