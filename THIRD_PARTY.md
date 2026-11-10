# Third-party material

| What | Where | Licence |
|---|---|---|
| GamepadMotionHelpers by Julian "Jibb" Smart: sensor fusion, automatic gyro calibration, player-space gyro (ported to Lua) | `core/gmh.lua` | MIT, Copyright (c) 2020-2023 Julian "Jibb" Smart |
| Robot character and its animations from KayKit Character Animations 1.1 by Kay Lousberg ([kaylousberg.com](https://www.kaylousberg.com)) | `assets/characters/robot/` | CC0 1.0 — see `assets/characters/robot/License.txt` |
| Nunito font (Bold, ExtraBold, Black instances of the variable font) | `assets/fonts/` | SIL Open Font License 1.1 — see `assets/fonts/Nunito-OFL.txt` |

Sounds: the menu sounds, result tunes and applause in `assets/sounds/` are our own (`tools/sfx/make_sounds.py`). The bowling hall sounds are cut from recordings (`tools/sfx/make_bowling.py`):
- "Bowling Strike Hit" ([OpenGameArt](https://opengameart.org/content/bowling-strike-hit)): recordings by juskiddink (freesound.org 82358, 82359), cut by qubodup. **CC-BY-SA 3.0**; our cuts (`crash_*`, `clack_*`, `ball_pin_*`, `pin_wall_*`, `pin_pit_*`, `ambience_loop`) are adaptations under the same licence.
- "Bowling Ball Rolling" by qubodup ([OpenGameArt](https://opengameart.org/content/bowling-ball-rolling)). **CC0**.

`core/wii/` (readers for files from the player's own Wii disc: Yaz0, U8, BRRES/MDL0/SCN0, GX textures) and `shells/love/gxshader.lua` (the Wii GPU's material stages as shaders) are ported from [noclip.website](https://github.com/magcius/noclip.website) by Jasper St. Pierre and contributors (MIT, Copyright (c) 2018 Jasper St. Pierre, see `core/wii/LICENSE-noclip.txt`). No Nintendo files are included.

`core/wii/xxhash.lua` implements XXH64 from the xxHash specification by Yann Collet (BSD-2-Clause), and `core/wii/texname.lua` follows the texture naming in Dolphin's `Source/Core/VideoCommon/TextureInfo.cpp` (GPL-2.0-or-later) so Dolphin texture packs match.

`shells/love/upscale.lua` adapts libretro's `xbrz-freescale.glsl` ([libretro/glsl-shaders](https://github.com/libretro/glsl-shaders)): Hyllian's xBR texel mapping (MIT, Copyright (C) 2011/2016 Hyllian) and xBRZ by Zenju (GPL-3.0, from HqMAME), changed to carry transparency.

`native/osble` (the Joy-Con 2 / Pro Controller 2 Bluetooth bridge) is our own code. The controller protocol it speaks comes from community reverse engineering, credited here:
- [joycon2cpp](https://github.com/TheFrano/joycon2cpp) (MIT): the Windows init sequence and characteristic UUIDs
- [SDL](https://github.com/libsdl-org/SDL) `SDL_hidapi_switch2.c` (zlib): axis order, IMU scales and timestamp handling
- [joycon2android](https://github.com/JoeGeC/joycon2android) (GPL-3.0): the Joy-Con 2 axis frame and IMU scales (`MotionConverter`, docs/dsu-motion.md), measured against Dolphin's pointer
- [linux-switch2](https://github.com/novakpetya/linux-switch2) PROTOCOL.md: the report layout, IMU scales and button bits
- [bit-axis-labs](https://bit-axis-labs.pages.dev/blog/switch-2-ble-controllers.html): the protocol overview

`core/dsu.lua` speaks the DSU (cemuhook) motion protocol. Its packet layout and axis meanings follow Dolphin's DualShockUDPClient (GPL-2.0-or-later).

Online hosting uses the official playit.gg app, downloaded from playit's own releases on the player's machine when they choose to host. No playit code is included in this repository.

## Godot version

The Godot version of Open Sports (`godot/`) runs on [Godot Engine](https://godotengine.org) (MIT, Copyright (c) 2014-present Godot Engine contributors, (c) 2007-2014 Juan Linietsky, Ariel Manzur), which is packed into OpenSports.exe. Its readers for the player's own disc follow the same sources as above: `godot/wii/` ports the noclip.website parsing (MIT), `godot/wii/disc.gd` reads ISO and WBFS images and decrypts the game partition the way Dolphin's DiscIO does (GPL-2.0-or-later), `godot/wii/texname.gd` and `godot/wii/xxhash.gd` name textures like Dolphin for texture packs, `godot/core/xbrz.gdshader` is the xBRZ upscaler (GPL-3.0, see above), and `godot/core/gmh.gd` is a port of GamepadMotionHelpers by Julian "Jibb" Smart (MIT). `osble.dll` is built with godot-cpp (MIT). `godot/core/dsu.gd` speaks the same DSU (cemuhook) protocol as `core/dsu.lua`.

The tennis sounds in `godot/assets/sounds/tennis/` are our own, synthesised by `tools/sfx/make_tennis.py`. The tennis court, net, ball and rackets are read from the player's own disc at run time; without one the game builds its own court in code (`godot/game/tennis/own_court.gd`).

OpenSports.exe is built on an export template compiled from Godot's own source with the unused parts left out (`tools/godot/size_profile.py`); it is still Godot Engine under the MIT licence above.
