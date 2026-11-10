# Open Sports

A free, open-source motion sports game in the spirit of Wii Sports, made with [Godot](https://godotengine.org).
Swing a real controller to bowl and to play tennis, or play with a mouse or a gamepad.

> **Status: early development.** Bowling (10 frames, one player) and tennis (doubles against the computer) are playable. More sports are planned.

## Playing

**Windows:** download `OpenSports-win64.zip` from the latest run of the [Build workflow](https://github.com/MightyX3N/opensports/actions/workflows/build.yml) (it builds on every push to `main`), unzip it and run `OpenSports.exe`. The exe isn't signed, so Windows SmartScreen may warn on first run: choose *More info → Run anyway*.

Next to the exe:

```
OpenSports.exe
rom/              your own Wii Sports or Wii Sports + Wii Sports Resort disc image (.wbfs or .iso)
packs/textures/   texture packs made for Dolphin (the game ID folder, e.g. RSPE01)
packs/addons/     add-ons
```

With a disc image in `rom/`, the game reads the real bowling alley, tennis court, pins, balls and rackets straight from it when it starts (nothing is extracted or copied). Without one it uses its own alley and court. Texture packs work with the disc's models, and the disc's own textures can be upscaled with xBRZ (Settings → Wii Sports disc and textures).

**From source:** open the folder in Godot 4.7, or run `godot --path .`.

### Bowling

| | Joy-Con 2 (R) | Gamepad | Mouse + keyboard |
| --- | --- | --- | --- |
| Move / turn the aim | Stick; press it in to switch | Stick / D-pad; A switches | Arrow keys; Space switches |
| Throw | Hold the Joy-Con upright in front of your chest, hold **ZR**, swing back and forward, let go | Hold RT, pull the stick back, push it forward | Drag down, then flick up |
| Spin | Twist your wrist as you swing | Push the stick sideways | Flick sideways at the end |
| Pause | **+** | Start | Esc |

### Tennis

You and a partner against two computer players; your players run to the ball by themselves.

| | Motion controller | Gamepad | Mouse + keyboard |
| --- | --- | --- | --- |
| Serve | Swing to toss, swing again at the top of the toss | Flick the stick (or RT) twice | Click twice |
| Hit | Swing as the ball arrives: early sends it across, late down the line | Flick the right stick | Hold the button and flick, or click |
| Topspin / slice / lob | Level swing / high to low / low to high | Flick sideways / down / up | Flick sideways / down / up (W/S + Space) |

### Controllers

- **Joy-Con 2 and Pro Controller 2:** Windows can't pair these as normal gamepads, so the game connects to them itself over Bluetooth: Controllers → Connect Joy-Con 2, press SYNC. Saved controllers reconnect by themselves when you press SYNC.
- **Motion over DSU (cemuhook):** controllers served by DS4Windows, BetterJoy, phone gyro apps and the like join with full motion. The server address is `dsu_server` in the settings file (default `127.0.0.1:26760`).
- **Gamepads** (stick and buttons), **mouse and keyboard.**
- **Check motion** shows where the controller points, its swing speed and the swings it detects; **Change buttons** remaps buttons per controller type.

## Testing

```sh
godot --headless --path . res://tests/run_tests.tscn                 # rules, physics, disc reading, swings, DSU
xvfb-run godot --path . --rendering-driver opengl3 res://tests/play_bowling.tscn   # plays bowling through the menus
xvfb-run godot --path . --rendering-driver opengl3 res://tests/play_tennis.tscn    # plays a tennis match
```

`OPENSPORTS_HOME=<folder>` points the game at another folder with `rom/` and `packs/`. `tools/make_test_disc.py` builds a small encrypted test disc image (ISO and WBFS) from a folder of files, so disc reading can be tested without a real disc.

## Building

`.github/workflows/build.yml` builds `osble.dll` (the Joy-Con 2 Bluetooth bridge, `native/`), a smaller Windows export template from Godot's source with the unused parts left out (`tools/size_profile.py`), runs the tests and exports `OpenSports.exe` with the game packed inside.

## Sounds

The bowling hall sounds are cut from recordings by `tools/sfx/make_bowling.py` (sources and licences in `tools/sfx/sources/`). Menu sounds, result tunes, applause and all the tennis sounds are synthesised by `tools/sfx/make_sounds.py` and `tools/sfx/make_tennis.py`. Sounds are placed in 3D at the camera.

## Original assets

Open Sports ships only its own art and audio. The Wii Sports look comes from the player's own disc, read on their machine. No Nintendo files are, or will be, included in this repository.

## License

[GPL-3.0](LICENSE). Third-party material: [THIRD_PARTY.md](THIRD_PARTY.md).
