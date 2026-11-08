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

## Still open
- The exact link from club speed at impact to launch speed, launch angle and starting spin. This is the remaining piece for golf.

## For Open Sports
- Spin decay rates, wind strength and the friction curve are tuning values.
- Surface types become materials in the course file, so add-on courses can define their own.
