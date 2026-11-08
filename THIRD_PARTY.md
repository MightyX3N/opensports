# Third-party material

| What | Where | Licence |
|---|---|---|
| Nunito font (Bold, ExtraBold, Black instances of the variable font) | `assets/fonts/` | SIL Open Font License 1.1 — see `assets/fonts/Nunito-OFL.txt` |

`native/osble` (the Joy-Con 2 / Pro Controller 2 Bluetooth bridge) is our own code. The controller protocol it speaks comes from community reverse engineering, credited here:
- [joycon2cpp](https://github.com/TheFrano/joycon2cpp) (MIT): the Windows init sequence and characteristic UUIDs
- [linux-switch2](https://github.com/novakpetya/linux-switch2) PROTOCOL.md: the report layout, IMU scales and button bits
- [bit-axis-labs](https://bit-axis-labs.pages.dev/blog/switch-2-ble-controllers.html): the protocol overview

Online hosting uses the official playit.gg app, downloaded from playit's own releases on the player's machine when they choose to host. No playit code is included in this repository.
