# Open Sports — Architecture

Status: **draft for review**. Nothing here is coded yet. Sections marked **Decide** need a yes/no before work starts.

## 1. Shape of the codebase

One shared Lua core that knows nothing about any engine, and three thin shells.

```
opensports/
  core/                 pure Lua 5.1 / LuaJIT; no love.*, no GMod globals
    math.lua            vec3, quat, mat3, easing curves, random with a seed
    motion.lua          the MotionController object and its filters
    swing.lua           swing and throw detection, shared by all sports
    physics.lua         rigid bodies, ball (Magnus, drag), contacts, surfaces
    sport.lua           sport contract, mode runner, hooks, tuning loader
    mods.lua            add-on discovery, load order, sandbox
    announcer.lua       line table, source choice, cache keys
    avatar.lua          rig contract, hand/foot targets, IK
    net.lua             snapshot and event format (used by GMod)
  sports/
    bowling/            one folder per sport (layout in §5)
    tabletennis/ ...
  shells/
    love/               desktop and Android (LÖVE 12)
      main.lua  render.lua  audio.lua  input/  fs.lua
    gmod/               gamemode (gamemodes/opensports/...)
      init.lua  cl_init.lua  shared.lua  render.lua  input/
  assets/               our own art and audio, by slot name
  tools/
    converter/          disc-to-asset-pack converter (runs on the user's machine)
  docs/
```

**Rules:**
- `core/` and `sports/` never touch an engine API. They get everything through the **shell interface** (§2).
- GMod uses the same files. Its shell includes them with `include` and `AddCSLuaFile`, and `require` is mapped onto that.
- **Decide:** target **Lua 5.1 syntax** (no `goto`, no integer division). LÖVE runs LuaJIT, which is 5.1-compatible, and GMod is also LuaJIT. This keeps one source for all three.

## 2. Shell interface

Each shell implements one small table. The core only calls these.

| Area | Functions |
|---|---|
| Time | `now()`, fixed-step driver |
| Files | `read(path)`, `write(path, data)`, `list(dir)`, `exists(path)` (sandboxed to the save folder) |
| Render | `drawModel(slot, transform, tint)`, `drawLine`, `drawText`, `drawUI(layout)`, `camera(pos, look, fov)` |
| Audio | `play(slot or path, opts)`, `stop(id)`, `listener(pos, dir)` |
| Input | a list of `MotionController` objects, refreshed every step (§3) |
| Speech | `tts(text, voice) -> async audio file` (optional; §8) |

Rendering stays in the shell on purpose. A sport says "pin 7 is here, rotated like this", and the shell draws it in LÖVE (with the 3D layer of our choice) or as a GMod clientside model.

**Decide:** for desktop/Android 3D, use the **g3d-style approach** (our own small mesh/shader renderer on LÖVE 12's 3D-capable `love.graphics`), not a big engine. It is enough for Wii-level art.

## 3. Input: one motion controller for everything

```lua
MotionController = {
  id, kind,            -- "wiimote", "joycon", "joycon2", "gyropad", "phone", "mouse"
  orient,              -- quat, world space, gravity-corrected
  gyro,                -- rad/s, controller space
  accel,               -- m/s², gravity removed
  pointer,             -- {x, y, valid} in 0..1 screen space (IR, or gyro-aimed)
  buttons,             -- logical: a, b, one, two, plus, minus, home, dpad, stick
  stick,               -- nunchuk / joycon stick
  rumble(t, strength),
  calibrate(),         -- "point at screen and press A"
}
```

**Backends.** Each one fills the same fields:

| Device | Desktop/Android (LÖVE) | GMod |
|---|---|---|
| Joy-Con 1, Pro, DualSense, DS4 | SDL sensors (`Joystick:getSensorData`) | binary module, or Steam Input gyro-as-mouse fallback |
| Joy-Con 2 | BLE helper (joycon2cpp-style) | through the same helper |
| Wii Remote + MotionPlus (DolphinBar mode 4) | hidapi via a small native module | same module |
| Phone | `love.sensor` gyro/accel on Android | — |
| Mouse | drag gestures turned into a virtual swing | same |

**Shared filters** (in `core/motion.lua`): a Mahony/Madgwick-style fusion for orientation, drift correction (from the IR pointer where present), and a ring buffer of the last ~1 s of samples, used by swing detection.

**Decide (GMod motion):** a client binary module (`gmcl_opensports`) gives full motion; Steam Input gyro-as-mouse is the no-install fallback with mouse gestures. A separate OmniPlay-style hub app sending UDP to localhost is **not** possible on servers without `-allowlocalhttp`, so the module is the main path.

## 4. Fixed step and physics

- **Simulation:** fixed 120 Hz step, with render interpolation. The originals ran at 60 Hz; all the research constants are converted to per-second SI units on load (`perFrame × 60`, `perFrame² × 3600`).
- **Units:** metres, kilograms, seconds. The original's "1 unit ≈ 10 cm" is converted once, in the tuning files.
- **`core/physics.lua` provides:**
  - spheres, capsules and boxes, plus static meshes for courses and lanes
  - one ball integrator with gravity, drag `k·v` or `k·|v|·v`, Magnus `s × v̂`, and spin decay. Every sport configures it through its tuning table, which is the same model the research found in tennis, baseball and golf.
  - surface materials (friction, restitution, roll resistance), looked up per contact
  - sub-stepping for fast objects (balls hit by bats and clubs)
  - a deterministic mode (fixed seed, no frame-time dependence) for replays and GMod prediction
- **Solved-at-load tables:** shots that must land on a target (tennis course table, CPU throws) are solved at load time from our own physics, so modded gravity, courts and balls still land true.

## 5. Sport contract

Each sport folder follows the four mod layers from the README:

```
sports/bowling/
  sport.lua      -- metadata, which slots and lines it uses, entry points
  tuning.lua     -- every number, with named fields, units and ranges (layer 1)
  setup.lua      -- field as data: lane, pins, gutters (layer 2)
  modes/
    standard.lua -- rules script: turns, scoring, win (layer 3)
    spin.lua
    custom.lua   -- sliders over tuning
  logic.lua      -- swing → throw, CPU player, camera
```

**`sport.lua`** returns:

```lua
return {
  id = "bowling", name = "Bowling",
  players = { min = 1, max = 4, teams = false },
  profiles = { "arcade", "realistic" },
  slots = { "bowling.ball", "bowling.pin", "bowling.lane", ... },
  lines = { "bowling.strike", "bowling.spare", ... },
  new = function(ctx) ... end,   -- ctx gives physics, input, hooks, tuning, rng
}
```

**Hooks:** `ctx.hooks:on("pinDown", fn)` and `ctx.hooks:emit(...)`. Add-ons attach to the same names (`onThrow`, `onBounce`, `onScore`, `onTurnEnd`).

**Profiles:**
- **Arcade** and **Realistic** are two tuning presets over one code path, not two implementations.
- Where the original is random or forgiving and that matters for feel, Arcade keeps it and Realistic replaces it (e.g. golf hook/slice from the twist at impact instead of a coin flip).

**Team sports:**
- The rules script assigns each human exactly one character.
- Empty slots get the sport's CPU controller, using the same input interface as a human (a virtual `MotionController`), so CPU and human code paths match.

## 6. Mods

```
<save>/addons/<name>/
  addon.lua       -- id, version, type(s), dependencies, load order hint
  sports/...      -- new sports, same layout as §5
  patches/...     -- tuning/setup overrides for existing sports
  assets/...      -- asset slots (glTF, PNG, OGG)
  avatars/...     -- avatar styles (§7)
  lines/...       -- announcer text and/or recordings
```

**Loading:**
- Add-ons load in dependency order. Tuning patches are deep-merged, last wins, with a per-field conflict log shown in the menu.
- Rules scripts and sports run in a **sandbox environment**: core and ctx only, no `io`/`os`/`debug`, and file access only through the shell's sandboxed `read`.

**Per platform:**
- **GMod:** add-ons are normal Workshop addons that put files under `lua/opensports/addons/`. The same files run on desktop when copied into `<save>/addons/`.
- **Asset packs** map slot names to files. The game's own assets are just the lowest-priority pack. The disc converter outputs a pack.

## 7. Avatars

- **Rig contract:** `head`, `torso`, `handL`, `handR`, `footL`, `footR`, `equip` (socket on the hand), plus a `scale` for reach.
- Sports animate **targets**, not bones: hand path for the swing, foot plants, look direction.
- **Style handling:**
  - Bean and Peg place floating hands directly on the targets.
  - Sporty solves two-bone IK for arms and legs.
- A style add-on is a model plus a small `style.lua` that maps contract points to its bones and picks the solver.

## 8. Announcer

As specified in the README. Implementation notes:

- **Line table:** `{ id = { text, version } }`, merged from sports and add-ons.
- **Source order:** add-on recording → converted original → cached TTS → generate TTS.
- **Cache key:** `hash(text, version, voiceModel, voiceSettings)`. The file lives in `<save>/voice/<id>.<key>.ogg`, and stale keys are deleted on regeneration.
- **When a sport loads**, a background job pre-generates that sport's lines, time-critical ones first.
- **Desktop/Android:** TTS through a bundled offline model (Piper-class), as a native helper or shared library.
- **GMod:** the server generates lines (pure-GLua model in `data/`, or a binary module) and streams the cached `.ogg` files to clients in net-message chunks. Clients play them with `sound.PlayFile` from `data/`.
- **Decide:** pick the TTS model after a quick size/quality test on Android. This doesn't block anything else.

## 9. Multiplayer

- **Desktop/Android:**
  - Local multiplayer (several controllers on one screen) comes first.
  - **Online:** one player's game acts as the server (a listen server), using the same server-authoritative model as GMod below. It uses UDP through LÖVE's built-in `lua-enet`, so desktop, Android and GMod share one net format.
  - **Reaching the host:** the host can run the **playit.gg** agent, so friends join an address like `name.at.ply.gg:port` with no port forwarding, even behind CGNAT. Custom UDP tunnels are on playit's free tier (TCP needs Premium), so we use UDP only.
  - The game gets a "Host online" screen: it shows the local port to tunnel, a field to paste the playit address, and a join-by-address box. Direct IP and LAN discovery stay available for anyone who doesn't use playit.
  - **playit.gg, current plan (terms checked 2026-11-08):**
    - playit's Terms §3.4 say the service may not be redistributed, and may not be offered "as part of a hosted, managed, bundled, white-labeled, or multi-tenant service", without prior written consent from Developed Methods LLC.
    - The agent's *code* is BSD-2-Clause, but that licence covers the code, not use of their network. **Bundling the agent therefore needs their written permission first.**
    - **What we ship:** a guided "Host online" screen.
      1. A link to the official playit download.
      2. Steps to create a UDP tunnel to the game's port, with the port shown and a copy button.
      3. A field to paste the resulting `*.ply.gg` address, which the game remembers and shows as a join code.
      - The player uses playit's own app under their own account, which is ordinary use.
    - **Bundling is not being pursued**, so the guided screen above is the final design. The game never ships or runs playit's code; it only links to it.
    - **Fallbacks always available:** direct IP, LAN discovery, paste-any-address.
- **GMod:**
  - The server runs the core simulation and is authoritative.
  - Clients read motion locally and send **swing events** (the result of swing detection: release time, velocity, spin, aim), not raw samples. That keeps bandwidth tiny and makes cheating no easier than with mouse input.
  - The server broadcasts compact snapshots at 20–30 Hz. Clients interpolate, and predict their own throw with the deterministic physics so it feels instant.

## 10. Saves and settings

- `<save>/settings.lua`: controllers, calibration, profile defaults, audio.
- `<save>/players/<name>.lua`: avatar style and colours, handedness, skill ratings per sport (Wii-style skill points).
- Everything is plain Lua data written by a small serialiser, so it is readable and safe to load in the sandbox.

## 11. Build order

1. **`core/math`, `core/motion`, LÖVE input backends** (SDL gyro + mouse), and a test scene that shows the controller's orientation as a 3D remote. This proves the input layer on real hardware.
2. **`core/physics`** ball and pins, with a headless test that replays a recorded throw and checks pin counts against the bowling research.
3. **Bowling end to end** on desktop: menus from the design canvas, Arcade profile, 1–4 players, standard mode.
4. **Android build** of the same.
5. **GMod shell** with bowling (mouse/Steam Input first, binary module second).
6. Wii Remote (DolphinBar) and Joy-Con 2 backends.
7. Announcer with TTS.
8. Next sports, in the README order.
