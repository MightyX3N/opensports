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

## From swing to shot

Each swing produces four measurements on the player's racket state. They're turned into the table inputs like this:

| Shot input | Built from |
| --- | --- |
| **Sidespin** (−1 to 1) | `0.8 × a + 0.8 × b`, clamped. `a` is a racket angle past a **±10** dead zone, scaled 0.008 per unit. `b` is a second angle past a **±30** dead zone, scaled 0.01 per unit. The sign flips depending on table side. |
| **Topspin / backspin** | Half of `b`. So the same tilt past the 30 dead zone adds both spin and curve. This is likely the racket face opening or closing. |
| **Power** (−1 to 1) | `2 × (swing strength − 0.5)`, from a 0–1 swing strength. |

- **Smash:** when the ball is high (between two height thresholds), the game rolls a random chance from 50% to 100% that grows with height. On success it blends the shot toward a flat, hard hit: sidespin → 0, the spin input → +1, power → 0.
- **Assist:** under some conditions it blends power and sidespin halfway toward safer values. This is probably help for weaker players or slower returns. One check uses `0.866`, which is cos 30°.
- A separate path, used by the CPU or a training mode, blends toward the opposite corner (−1 values).

## Ball flight

Each frame, scaled by a time factor (a game-speed value times a per-shot value):

- **Air drag:** velocity × **0.9986** per time unit.
- **Gravity:** vertical velocity − **0.00221** × time factor. The time factor scales how fast the rally plays, so the effective gravity can't be read off this number alone.
- **Magnus effect:** a cross product of spin × velocity is added to the velocity, so topspin dips, backspin floats and sidespin curves.
- **Spin decay:** spin is reduced slightly each frame (constant 0.0001).

## Bounces

Collision meshes are checked each frame (table, then field), and each surface type has its own restitution and friction:

| Surface | Restitution | Friction |
| --- | --- | --- |
| Table | 0.82 | 0.2 |
| Surface type 1 (likely grass) | 0.65 | 0.1 |
| Surface type 2 | 0.95 | 0.3 |
| Second mesh group (likely racket or net) | 0.95 | 0.3 |

Bounces set flags that the rules code reads (own side, opponent side, edge, out).

## Scale

The table's top surface measures about ±7.6 × ±13.2 units, close to a real table's 1.525 × 2.74 m. So Resort also uses **1 unit ≈ 10 cm**, the same as Wii Sports bowling.

## What this means for Open Sports

- Copy the idea of **"pick a target, then solve the launch"**. It's why Resort table tennis feels forgiving yet controlled. Swing timing and racket angle choose where the ball goes and with what spin, and the game makes sure the arc fits.
- **We shouldn't ship fixed tables.** Our engine can build them at load time with a small solver: simulate shots with our own physics and search for the speed and angles that hit each grid target. That's how the **folded-table practice mode** and modded tables of any size will work. A new table shape gets its own course table automatically.
- **Arcade mode** uses the solved launch (always lands where you aimed, if you timed it). **Realistic mode** can skip the solver and launch straight from racket speed and angle, so misses are possible.

Still to do: which MotionPlus readings feed the four racket measurements, how the aim target is chosen from swing timing, the serve table's axes, and the CPU data.
