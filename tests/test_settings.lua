-- Headless tests for settings: choices cycling and the saved Joy-Con list.
-- Run: python3 tools/runlua.py tests/test_settings.lua  (or: LUA_PATH="./?.lua;;" luajit tests/test_settings.lua)
local S = require("shells.love.settings")
local fails, passes = 0, 0
local function ok(cond, msg)
  if cond then passes = passes + 1 else fails = fails + 1; print("FAIL: " .. msg) end
end

-- without LÖVE the settings live in memory only
S.load()
ok(S.get("swing") == "normal" and S.get("aimLine") == true and S.get("autoConnect") == true, "defaults")
ok(S.cycle("swing", 1) == "strong", "cycle forward")
ok(S.cycle("swing", 1) == "light", "cycle wraps round")
ok(S.cycle("swing", -1) == "strong", "cycle backward")
ok(S.cycle("aimLine", 1) == false and S.cycle("aimLine", 1) == true, "on/off toggles")
ok(S.get("volume") == "high" and S.cycle("volume", 1) == "medium" and S.cycle("volume", -2) == "off", "sound volume cycles")

-- saved controllers: addresses as numbers (from Bluetooth) or hex strings (from the file)
local list = {}
S.remember(list, 0xA1B2C3D4E5F6, 0x2066, "Joy-Con 2 (R)", 100)
ok(#list == 1 and list[1].addr == "a1b2c3d4e5f6", "remember stores the address as hex")
ok(S.findSaved(list, 0xA1B2C3D4E5F6) ~= nil, "found by number")
ok(S.findSaved(list, "A1B2C3D4E5F6") ~= nil, "found by hex string, any case")
ok(S.findSaved(list, 0x112233445566) == nil, "unknown address isn't found")
S.remember(list, 0x112233445566, 0x2067, "Joy-Con 2 (L)", 200)
S.remember(list, 0xA1B2C3D4E5F6, 0x2066, "Joy-Con 2 (R)", 300)
ok(#list == 2 and list[1].addr == "a1b2c3d4e5f6" and list[1].last == 300, "reconnecting moves it to the top, no duplicate")
S.forget(list, 0x112233445566)
ok(#list == 1 and S.findSaved(list, 0x112233445566) == nil, "forget removes it")
for i = 1, 12 do S.remember(list, 0x100000000000 + i, 0x2066, "pad " .. i, i) end
ok(#list == 8, "keeps at most 8")

-- the saved file round-trips through the serialiser
local ser = require("core.serialize")
local back = ser.load(ser.dump({ saved = list, swing = "light" }))
ok(back and #back.saved == 8 and back.swing == "light" and S.findSaved(back.saved, 0x10000000000c), "settings file round-trip")

print(string.format("%d passed, %d failed", passes, fails))
if fails > 0 then error("tests failed") end
