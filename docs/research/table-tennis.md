# Table tennis: how the original shots work

Research notes from studying Wii Sports Resort (EU bundle build, `WiiSports2P.dol`, table tennis code around `0x8044D000`–`0x80480000`).
Written in our own words as a reference for designing Open Sports' own implementation. No original code or data is included.

## Files

| File | What it is |
| --- | --- |
| `courseTable.dat` (4,860 bytes) | Rally shot lookup table |
| `serveCourseTable.dat` (2,700 bytes) | Serve lookup table |
| `Sp2PngCpuData.exbin` | CPU opponent tuning |
| `WS2_png_table.kcl`, `WS2_png_field.kcl` | Collision for table and ground |

## Shots are solved in advance, not left to the physics

The ball doesn't simply fly off the racket wherever the physics sends it. The game first decides **where the shot should land**. It then looks up **launch values that make the ball land there**, and only then lets physics fly the ball.

### The course table

- A **5-dimensional grid** of 3 × 3 × 3 × 3 × 5 cells (405 entries). Each cell holds three values: **launch speed, elevation angle and side angle** (in degrees).
- The game blends smoothly between the 32 surrounding grid corners (multilinear interpolation). Inputs between grid points still give an exact arc.
- The angles are converted to the engine's 256-units-per-circle format before use.

### The five inputs (as far as identified)

1. **Shot distance** to the target spot, mapped to 0–1: about 1 m → 0, 2 m → 0.5, 3.5 m → 1 (clamped at 2).
2. **Contact height**, the ball's height when hit, mapped so a higher ball gives a lower value. That's how high balls become flatter, faster shots.
3. and 4. Two **shot modifiers** passed in from the swing, most likely power and topspin/backspin. Both are reduced by 70% of the sidespin amount.
5. **Sidespin**, the 5-point axis, signed.

### After the lookup

- The velocity is built from speed, elevation and side angle, then turned to face the target.
- **Sidespin** is added to the ball's spin: −30 units per unit of sidespin for normal shots, −37.5 for the second shot type (likely smashes). The sign flips depending on which side of the table the player is on.

## What this means for Open Sports

- Copy the idea of **"pick a target, then solve the launch"**. It's why Resort table tennis feels forgiving yet controlled. Swing timing and racket angle choose where the ball goes and with what spin, and the game makes sure the arc fits.
- **We shouldn't ship fixed tables.** Our engine can build them at load time with a small solver: simulate shots with our own physics and search for the speed and angles that hit each grid target. That's how the **folded-table practice mode** and modded tables of any size will work. A new table shape gets its own course table automatically.
- **Arcade mode** uses the solved launch (always lands where you aimed, if you timed it). **Realistic mode** can skip the solver and launch straight from racket speed and angle, so misses are possible.

Still to do: how the swing picks the target, power and spin (racket orientation from MotionPlus), the ball physics (drag, Magnus effect, bounce), the serve table's axes, and the CPU data.
