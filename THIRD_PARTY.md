# Third-party material

| What | Where | Licence |
|---|---|---|
| GamepadMotionHelpers by Julian "Jibb" Smart: sensor fusion, automatic gyro calibration, player-space gyro (ported to Lua) | `core/gmh.lua` | MIT, Copyright (c) 2020-2023 Julian "Jibb" Smart |
| Robot character and its animations from KayKit Character Animations 1.1 by Kay Lousberg ([kaylousberg.com](https://www.kaylousberg.com)) | `assets/characters/robot/` | CC0 1.0 — see `assets/characters/robot/License.txt` |
| Nunito font (Bold, ExtraBold, Black instances of the variable font) | `assets/fonts/` | SIL Open Font License 1.1 — see `assets/fonts/Nunito-OFL.txt` |

Sounds: the menu sounds, result tunes and applause in `assets/sounds/` are our own (`tools/sfx/make_sounds.py`). The bowling hall sounds are cut from recordings (`tools/sfx/make_bowling.py`):
- "Bowling Strike Hit" ([OpenGameArt](https://opengameart.org/content/bowling-strike-hit)): recordings by juskiddink (freesound.org 82358, 82359), cut by qubodup. **CC-BY-SA 3.0**; our cuts (`crash_*`, `clack_*`, `ball_pin_*`, `pin_wall_*`, `pin_pit_*`, `ambience_loop`) are adaptations under the same licence.
- "Bowling Ball Rolling" by qubodup ([OpenGameArt](https://opengameart.org/content/bowling-ball-rolling)). **CC0**.

`native/osble` (the Joy-Con 2 / Pro Controller 2 Bluetooth bridge) is our own code. The controller protocol it speaks comes from community reverse engineering, credited here:
- [joycon2cpp](https://github.com/TheFrano/joycon2cpp) (MIT): the Windows init sequence and characteristic UUIDs
- [SDL](https://github.com/libsdl-org/SDL) `SDL_hidapi_switch2.c` (zlib): axis order, IMU scales and timestamp handling
- [joycon2android](https://github.com/JoeGeC/joycon2android) (GPL-3.0): the Joy-Con 2 axis frame and IMU scales (`MotionConverter`, docs/dsu-motion.md), measured against Dolphin's pointer
- [linux-switch2](https://github.com/novakpetya/linux-switch2) PROTOCOL.md: the report layout, IMU scales and button bits
- [bit-axis-labs](https://bit-axis-labs.pages.dev/blog/switch-2-ble-controllers.html): the protocol overview

`core/dsu.lua` speaks the DSU (cemuhook) motion protocol. Its packet layout and axis meanings follow Dolphin's DualShockUDPClient (GPL-2.0-or-later).

Online hosting uses the official playit.gg app, downloaded from playit's own releases on the player's machine when they choose to host. No playit code is included in this repository.
