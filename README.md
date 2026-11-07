# Open Sports

A free, open-source motion sports game in Lua, in the spirit of Wii-era party sports.
Swing a real controller to bowl, serve, putt, slice and throw, alone or with friends.

> **Status: design stage.** Architecture and art direction are being settled before any code is written.

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
Speech is generated once and cached as audio, so it costs nothing at runtime. Only dynamic lines, such as player names, are generated on the fly.

## Original assets

Open Sports ships only its own art and audio. An optional converter can turn files from a user's own Wii Sports or Wii Sports Resort disc into an asset pack on their machine.
No Nintendo files are, or will be, included in this repository.

## License

[GPL-3.0](LICENSE)
