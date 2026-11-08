# Open Sports

A free, open-source motion sports game in Lua, in the spirit of Wii-era party sports.
Swing a real controller to bowl, serve, putt, slice and throw, alone or with friends.

> **Status: early development.** The input layer and controller test app are in (build step 1 of [docs/architecture.md](docs/architecture.md)). No sports are playable yet.

## Running the input test

**Windows:** download `OpenSports-win64.zip` from the [dev release](https://github.com/MightyX3N/opensports/releases/tag/dev), unzip it and run `OpenSports.exe`. The release is rebuilt on every push to `main`. The exe isn't signed, so Windows SmartScreen may warn on first run: choose *More info → Run anyway*.

**From source:** requires [LÖVE](https://love2d.org) 12 (11.5 also runs it, but without gyro sensors).

```sh
love .
```

Connect a gyro controller (Joy-Con, Pro Controller, DualSense, DualShock 4 or a Bluetooth pad) and it shows up next to the mouse. **Joy-Con 2 and Pro Controller 2** don't appear in Windows Bluetooth settings. Instead, choose **Connect Joy-Con 2** in the game, press the controller's SYNC button, and pick it from the list. Use the D-pad, stick, arrow keys or mouse in the menus. **Tab** / button 2 switches controllers and **R** / button 1 recentres.

The app has four screens:
- **Motion test:** the controller drawn in 3D, live gyro and accelerometer readings, and the last detected swing.
- **Motion check:** finds a missing, frozen, slow or noisy gyro and picks a fallback level.
- **Fix axes:** "tilt forward / turn left / twist right" repairs swapped or flipped axes.
- **Buttons:** remaps buttons for one controller.

Fixes are saved per controller in LÖVE's save folder (`input/<guid>.lua`).

Core tests run under LuaJIT: `python3 tools/runlua.py tests/test_core.lua` (needs `pip install lupa`).

## Platforms

| Target | Engine |
| --- | --- |
| Windows | LÖVE 12 (standalone exe) |
| Android | LÖVE 12 (love-android) |
| Garry's Mod | Gamemode |

All three run the same shared core: sport rules, swing detection and physics are pure Lua with no engine calls.
Each platform only provides rendering, audio, input and file loading.

## Controllers

- Mouse (every sport is playable with drag gestures)
- Gyro gamepads (Switch Pro, DualSense, DualShock 4) via SDL sensors
- Joy-Con (Switch 1), each one usable as its own remote
- Joy-Con 2 (Switch 2)
- Wii Remote with MotionPlus and Nunchuk through a Mayflash DolphinBar (mode 4), including the IR pointer
- Phone gyro on Android

Every device is turned into the same "motion controller": orientation, spin rate, acceleration, pointer, buttons and rumble.
Sports only ever read that, never a specific device.

## Sports (planned)

Bowling first, then table tennis, archery and swordplay, followed by tennis, golf, baseball, boxing, frisbee, basketball and cycling.

Each sport has an **Arcade** profile (forgiving swings, Wii-style feel, the default) and a **Realistic** profile (real masses, drag and spin, 1:1 tracking).
Team sports never make one person control two characters: one human controls one character, and empty slots are filled by CPU players.

## Built to be modded

Every sport is split into four layers, and any of them can be replaced or extended by an add-on:

1. **Tuning table** – every number in one editable data file with named fields
2. **Setup data** – the playing field as data (pin positions, table surfaces, court lines, walls)
3. **Rules script** – scoring, turns and win conditions for a mode
4. **Hooks** – events such as `onThrow`, `onPinDown`, `onBounce` and `onScore`

That makes things like a 1,000-pin lane or a folded table-tennis table for solo practice a small add-on instead of a fork.
Every sport also gets a **Custom** mode with in-game sliders for its tuning table.

- **Sport add-ons** add new sports and run on all three platforms.
- **Asset packs** replace models, textures and sounds by named slot (glTF, PNG, OGG).
- **Avatar styles** add new character styles that every sport can use.

## Avatars

Each player picks an avatar style. Three ship with the game, and add-ons can add more:

- **Bean** – big round head, bean body, floating hands
- **Peg** – peg-doll capsule body, floating hands, no legs
- **Sporty** – about 3.5 heads tall with full arms and legs

Every style follows the same rig contract: head, torso, hands, feet and an equipment socket.
Sport animations move hand and foot targets, and each style reaches them in its own way (floating hands are placed directly, full arms use IK).
That way any style works in any sport, and players with different styles can share a match.

## Announcer

Every announcer line is a named line ID with text, e.g. `bowling.strike = "Strike!"`. When a line plays, the game uses the first source available:

1. A recorded line from an installed voice pack or add-on
2. The original line, if the player converted it from their own disc
3. Offline text-to-speech, generated from the text

Add-ons can just write text for new lines and they'll be spoken automatically, or ship their own recordings.
Speech is generated the first time a line is needed and cached as audio from then on, the same way on desktop, Android and Garry's Mod.
When a sport loads, its lines are also generated in the background ahead of time, so time-critical lines like "Strike!" are usually ready before they're needed.

Every line carries a version number, e.g. `bowling.strike = { text = "Strike!", version = 2 }`.
Each cached file records the line's version, plus the voice model and its settings. When any of them changes, that line is regenerated the next time it's needed and the old file is removed.
Bumping the version also forces a fresh take when the text stays the same, for example after fixing a pronunciation.

## Original assets

Open Sports ships only its own art and audio. An optional converter can turn files from a user's own Wii Sports or Wii Sports Resort disc into an asset pack on their machine.
No Nintendo files are, or will be, included in this repository.

## License

[GPL-3.0](LICENSE)
