# Tennis (Wii Sports) — shot model

Read from the EU `SportsPackEP.dol`. Units: 1 unit ≈ 10 cm, 60 frames per second.
These are notes on how the original behaves, for designing our own code. No Nintendo code or data goes in this repo.

## Player shot (`fn_80251044`)

1. **Power.** `(swing - 0.4) / 0.7`, clamped to 0–1. The swing value is the remote's swing strength.
2. **Second input.** `(value + 0.3) / 1.1`, clamped. This is the spin or "cut" input.
3. **Aim** (`fn_80250BC4`):
   - The sideways angle comes from contact timing: early sends it cross-court, late sends it down the line.
   - When hitting from a wide position, the shot is pulled back toward the centre by `|x| / 60`.
   - Depth is `1.4 × t + 0.1`.
4. **Speed** (`fn_802507E8`):
   - Comes from a 4-D lookup table, 3×3×3×3, with linear blending between entries.
   - The four inputs:
     - distance to target, `(|z| - 10) / 115`
     - power
     - spin
     - contact height / 20
   - The output is the horizontal and vertical launch speed. The table is solved offline, so every shot lands where it was aimed.
5. **Spin** (`fn_802511B8`):
   - A swing measure under 1.7 gives backspin (slice).
   - A measure over 3.14 gives topspin.
   - Each is scaled up to that spin's maximum.

## CPU
- `fn_80252698`: 15 % chance of a special shot, 30 % chance of a random spin.
- Serve: `fn_80250D58`. Training ball feeder: `fn_80264A1C`.

## Hit window
`fn_8025927C` / `fn_802594AC`: the ball must be 0.5–2.5 m from the player, inside a 120° cone in front. Prediction loops rerun the ball step (`fn_8025A758`) to find where the player should run.

## For Open Sports
- Build the course table at load time from our own ball physics. Then add-ons that change gravity, court size or ball bounce still get shots that land on target.
- Expose these as tuning values: the power curve (0.4 / 0.7), the pull to centre (/60) and the spin thresholds.
