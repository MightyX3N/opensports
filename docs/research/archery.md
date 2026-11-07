# Archery: how the original works

Research notes from studying Wii Sports Resort (EU bundle build, `WiiSports2P.dol`, archery code around `0x80538000`–`0x8057A000`).
Written in our own words as a reference for designing Open Sports' own implementation. No original code or data is included.

## Files

| File | What it is |
| --- | --- |
| `SkillData.exbin` | Skill-rating tables: point thresholds per level, rising from 30 to 144 in steps. Not physics. |
| `WS2_arc_target*.kcl` | Collision for targets: plain, on a pole, on a piston, on a tackle dummy |
| `WS2_arc_melon/orange/watermelon/cake/bread/tv.kcl` | Bonus targets, each with its own hit effect |
| `WS2_arc_island_rope.kcl`, `WS2_arc_tree*.kcl` | Scenery the arrow can hit |
| `Map/WS2_arc_island.pmp`, `_tag.pmp` | Stage object placement |

Hit effects exist per surface: leaf, soil, sand, water, waterfall, wood, lava and spark. That means the stage collision carries a material per triangle.

## Arrow flight

- The arrow's whole path is **simulated ahead of time** into a long array of points as soon as it's released. The arrow then plays back along that path, and each segment is checked against the target and scenery collision with an arrow radius of **0.07** units (7 mm).
- Each simulation step: velocity × **0.9999** (air drag), vertical velocity − **0.0002** (gravity), then the **wind** vector is added when the stage has wind.
- The steps are very fine. If 0.0002 per step is real gravity at 1 unit = 10 cm, that works out to roughly 700 steps a second. The array holds thousands of points, so a fast arrow gets a smooth, accurate arc.
- Launch speed comes from a per-stage table blended with distance, then scaled. Full draw gives about **1.1×** the base speed.
- Because the path exists before the arrow lands, the game knows straight away what it will hit. That's how it can set up the camera and effects (like the slow-motion bullseye shot) in advance.

## What this means for Open Sports

- **Pre-simulating the path** is cheap and deterministic, and it gives us aim previews for free. An Arcade aim guide can draw the first part of the real path.
- Wind becomes a per-stage vector in the setup data, so add-on stages can define their own wind.
- Surface materials on stage collision (leaf, sand, water…) choose hit sounds and effects. The same material system the table tennis bounces use.
- Bonus targets are just collision meshes with a score and an effect, an easy thing for add-ons.

Still to do: the draw mechanic (Nunchuk pull and hold), aim sway and the "concentration" steadying effect, scoring rings, and the time limit.
