# Third-party material

Open Sports runs on [Godot Engine](https://godotengine.org) (MIT, Copyright (c) 2014-present Godot Engine contributors, (c) 2007-2014 Juan Linietsky, Ariel Manzur), which is packed into OpenSports.exe. The exe is built on an export template compiled from Godot's own source with the unused parts left out (`tools/size_profile.py`); it is still Godot Engine under the MIT licence. `osble.dll` is built with godot-cpp (MIT).

| What | Where | Licence |
|---|---|---|
| GamepadMotionHelpers by Julian "Jibb" Smart: sensor fusion, automatic gyro calibration (ported to GDScript) | `core/gmh.gd` | MIT, Copyright (c) 2020-2023 Julian "Jibb" Smart |
| Robot character and its animations from KayKit Character Animations 1.1 by Kay Lousberg ([kaylousberg.com](https://www.kaylousberg.com)) | `assets/characters/robot/` | CC0 1.0 — see `assets/characters/robot/License.txt` |
| Nunito font | `assets/fonts/` | SIL Open Font License 1.1 — see `assets/fonts/Nunito-OFL.txt` |

## Sounds

The menu sounds, result tunes, applause and every tennis sound in `assets/sounds/` are our own, synthesised by `tools/sfx/make_sounds.py` and `tools/sfx/make_tennis.py`. The bowling hall sounds are cut from recordings (`tools/sfx/make_bowling.py`):
- "Bowling Strike Hit" ([OpenGameArt](https://opengameart.org/content/bowling-strike-hit)): recordings by juskiddink (freesound.org 82358, 82359), cut by qubodup. **CC-BY-SA 3.0**; our cuts (`crash_*`, `clack_*`, `ball_pin_*`, `pin_wall_*`, `pin_pit_*`, `ambience_loop`) are adaptations under the same licence.
- "Bowling Ball Rolling" by qubodup ([OpenGameArt](https://opengameart.org/content/bowling-ball-rolling)). **CC0**.

## Reading the player's own disc

No Nintendo files are included. The readers that use the player's own disc follow:
- `wii/` (Yaz0, U8, BRRES/MDL0/SCN0, GX textures) and `wii/gxshader.gd` (the Wii GPU's material stages as shaders) are ported from [noclip.website](https://github.com/magcius/noclip.website) by Jasper St. Pierre and contributors (MIT, Copyright (c) 2018 Jasper St. Pierre).
- `wii/disc.gd` reads ISO and WBFS images and decrypts the game partition the way Dolphin's DiscIO does (GPL-2.0-or-later).
- `wii/xxhash.gd` implements XXH64 from the xxHash specification by Yann Collet (BSD-2-Clause), and `wii/texname.gd` follows the texture naming in Dolphin's `Source/Core/VideoCommon/TextureInfo.cpp` (GPL-2.0-or-later) so Dolphin texture packs match.
- `core/xbrz.gdshader` adapts libretro's `xbrz-freescale.glsl` ([libretro/glsl-shaders](https://github.com/libretro/glsl-shaders)): Hyllian's xBR texel mapping (MIT, Copyright (C) 2011/2016 Hyllian) and xBRZ by Zenju (GPL-3.0, from HqMAME), changed to carry transparency.

## Controllers

`native/` (the Joy-Con 2 / Pro Controller 2 Bluetooth bridge) is our own code. The controller protocol it speaks comes from community reverse engineering:
- [joycon2cpp](https://github.com/TheFrano/joycon2cpp) (MIT): the Windows init sequence and characteristic UUIDs
- [SDL](https://github.com/libsdl-org/SDL) `SDL_hidapi_switch2.c` (zlib): axis order, IMU scales and timestamp handling
- [joycon2android](https://github.com/JoeGeC/joycon2android) (GPL-3.0): the Joy-Con 2 axis frame and IMU scales, measured against Dolphin's pointer
- [linux-switch2](https://github.com/novakpetya/linux-switch2) PROTOCOL.md: the report layout, IMU scales and button bits
- [bit-axis-labs](https://bit-axis-labs.pages.dev/blog/switch-2-ble-controllers.html): the protocol overview

`core/dsu.gd` speaks the DSU (cemuhook) motion protocol ([protocol description](https://v1993.github.io/cemuhook-protocol/)); its axis meanings follow Dolphin's DualShockUDPClient (GPL-2.0-or-later).
