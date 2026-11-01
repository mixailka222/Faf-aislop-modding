-- stand: expect ReclaimPause: hotkeys installed: 0

-- The mod has no default keys: its actions exist, but nothing is bound to them, also not the key it
-- used to have. keys_in_match.lua shows that the same press reaches an action once it is bound.
local Test = import("/mods/ModTest/modules/test.lua")
local KeyMapper = import("/lua/keymap/keymapper.lua")

local ACTIONS = { "reclaimpause_toggle", "reclaimpause_check", "reclaimpause_defaults" }
local NOTHING_HAPPENS_SECONDS = 4

function Run()
    local lines = Test.WatchLog(import("/mods/ReclaimPause/modules/watch.lua"))
    WaitSeconds(2)
    local known = KeyMapper.GetKeyActions()
    for _, action in ACTIONS do
        Test.Check(known[action] ~= nil, "the action exists: " .. action)
        Test.Check(not KeyMapper.GetCurrentKeyBinding(action), "no key for the action: " .. action)
    end
    Test.Check(KeyMapper.GetCurrentKeyMap()["Ctrl-Alt-R"] == nil, "Ctrl-Alt-R is not in the key map")
    Test.PressKey("Ctrl-Alt-R")
    WaitSeconds(NOTHING_HAPPENS_SECONDS)
    Test.Check(not Test.Logged(lines, "toggled"), "Ctrl-Alt-R does nothing")
end
