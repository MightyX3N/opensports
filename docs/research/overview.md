# Research overview: every sport

A survey of both games on the Wii Sports + Wii Sports Resort disc (EU bundle): `SportsPackEP.dol` and `WiiSports2P.dol`.
About 12,900 functions across all sport code regions were decompiled and scanned, along with every data file.
Written in our own words. No original code or data is included.

Depth varies by sport:
- **Deep:** behaviour read in detail. Bowling, table tennis and archery each have their own notes.
- **Survey:** key systems and values found, but not traced end to end.
- **Data only:** files identified and read, no code traced yet.

## Shared foundations

- **Scale:** 1 unit ≈ 10 cm in both games (bowling ball radius, lane length and table tennis table all match).
- **60 fps, fixed steps.** Physics often runs several sub-steps per frame (bowling 4, archery very fine steps).
- **Simple, hand-tuned physics everywhere.** Per-axis damping factors (0.9–0.9999), small per-step gravity constants, sleep thresholds. There's no general physics engine, just one small rigid-body step shared in a utility library.
- **Shared ball model.** Tennis and table tennis use almost the same flight: gravity −0.00216 / −0.00221 per frame × time scale, spin decay ×0.995 per frame, and a Magnus term from spin × velocity.
- **Collision meshes (KCL) with a material per triangle.** Golf holes use about 12 surface types (fairway, rough, bunker, green, water and so on). Archery and table tennis also pick effects and bounce from the material.
- **Tuning data:** some sports ship spreadsheet exports (`.bin` / `.exbin` with a `1010 1010` header in Resort). Most physics values, though, are hardcoded in one big setup function per sport.
- **Skill rating:** most Resort sports have a `SkillData.exbin` with level thresholds.
- **CPU players:** `cpuData.bin` (Wii Sports) and per-sport `CpuData` / `Sp2*CpuData` tables (Resort). There are also 100 CPU Mii files (`.rcd` / `.rsd`).
- **Mii parts:** `RFL_Res.dat` (686 KB) holds the Mii face and body part library. That's useful for the optional Mii converter.
- **Menus:** 1,295 layouts and 5,519 animations. Resort's numbered layouts lay out the full menu flow.
- **Island:** `WS2_common_island.brres` (7 MB) plus props, landmark data (`LandMarkData.exbin`, used by air sports' sightseeing points) and per-sport stage placement files (`.pmp`).

## Wii Sports

| Sport | Depth | Findings |
| --- | --- | --- |
| Bowling | Deep | See [bowling.md](bowling.md): pendulum swing from the accelerometer, power from peak, spin from wrist twist, a small rigid-body solver with 4 sub-steps, a pin damping ramp after impact, ±random hit factor, 15-snapshot replays. Training layouts in `GateChallengeData` / `TrialData`. |
| Tennis | Survey | Ball: spin decays ×0.995 per frame, gravity −0.00216 × time scale, Magnus lift = 5.73 × spin × speed / 1000, with separate topspin and backspin handling. Two collision meshes (court and net). Players move automatically, as known. |
| Golf | Survey | 14 holes, each with its own collision mesh and placement file. Ground roll damps velocity ×0.9985 / ×0.997 per frame and adds a slope force (0.00008 × surface normal). The ball stops below a speed threshold. A large setup function (228 values) holds camera, tee and pin data per hole. |
| Baseball | Survey | Pitch and hit tables use angle cosines (cos 25°, cos 12° and so on), probably for pitch types and hit cones. A large setup function (~220 values) holds field and timing data. One collision mesh for the ballpark. |
| Boxing | Survey | One tuning block (~30 values: reaction times, guard and punch strengths, damping 0.93 / 0.9). Punch physics are damped springs (0.98 / 0.985). |

## Wii Sports Resort

| Sport | Depth | Findings |
| --- | --- | --- |
| Bowling | Deep | Same tuning table as Wii Sports. `ThrowData.exbin` is a long table of value pairs, most likely a precomputed hook curve for MotionPlus spin. `StageData` covers the spin-control and 100-pin layouts (91 pins). |
| Table tennis | Deep | See [table-tennis.md](table-tennis.md): pick a target, then solve the launch from a 5-D course table. Spin from racket twist and sweep over the last half second, timing aims the shot, smash chance, bounce materials. |
| Archery | Deep | See [archery.md](archery.md): the whole path is pre-simulated at release (drag ×0.9999, gravity 0.0002 per fine step, wind), materials per surface, bonus targets. |
| Swordplay | Data + survey | Speed Slice objects are 24 small definition files (bamboo, melon, cake, clock, diamond…), each 144 bytes holding cut geometry and angles. Large CPU behaviour tables for Duel (`Sp2SwfCpuData`, 26 KB) and Showdown (`Sp2SwfKumiteData`, 17 KB). The sword uses 1:1 MotionPlus orientation. |
| Frisbee (dog) | Survey | Disc physics uses **per-axis drag**: very low drag along the disc's plane (×0.99993) and higher drag across it (×0.997). That one difference makes it glide and float. Eight drag sets exist for different flight states or discs. |
| Disc golf | Survey | Same disc model as Frisbee, on golf-style courses with terrain materials. |
| Basketball | Survey | The hoop **net is a cloth simulation**: points with gravity −0.001 / −0.003, damping ×0.995 and soft constraints. There's a CPU behaviour table (`CpuData.exbin`). |
| Canoe | Data | `BoatParam.dat` has one block per boat size (1, 2 and 4 rowers): linear damping ×0.9985, turn damping ×0.97, paddle force 0.025, and stroke timing. Water surface data (`.fywtr`). |
| Cycling | Survey | Speed damping in the 0.93–0.99 range, stamina, and a pedal-rhythm smoother (0.05 lerp). 12 collision meshes and 15 placement files for the courses. |
| Air sports | Survey | Plane flight has its own damping set and a camera path table (`GameManagerData`). `FlightRecordData` (48 KB) stores records. Landmark data drives the sightseeing points. |
| Power cruising | Survey | Water craft physics with damping 0.97–0.998 and small gravity and buoyancy constants. 12 collision meshes and 22 placement files. |
| Wakeboarding | Survey | Shares the water stage and code area with Power cruising; it has its own skill data. |
| Golf | Survey | 21 Wuhu holes (each with collision and placement) plus the Wii Sports-style hole set. |
| Skydiving (intro) | Data | Physics data (fall speeds, damping 0.08–0.6), hand-linking data (`DockingData`) and scoring data. |

## What this means for Open Sports

1. **One shared physics core** fits all of it. A fixed-step body with per-axis damping, gravity, spin and Magnus effect, a sleep threshold and sub-steps covers balls, pins, discs, arrows, boats and the basketball net.
2. **Surface materials** on every collision mesh: bounce, friction and roll damping, plus sound and effect names.
3. **Named tuning tables** per sport, replacing Nintendo's unnamed blocks. Mods and the Custom mode edit them.
4. **Shot solvers** (table tennis, likely tennis) built at load time instead of shipped tables, so modded courts and tables just work.
5. **Pre-simulated paths** (archery, aim guides) are cheap and give Arcade previews.
6. **CPU players** are data-driven per sport, like Nintendo's CPU tables.

## Still open

- Tennis shot targeting (whether it uses a course table like table tennis).
- The baseball pitch and hit model in detail.
- Golf swing → power / hook / slice, and the ball's flight in the air.
- How the swordplay sword is checked against cut objects.
- How cycling, canoe and air sports controls map to motion.
