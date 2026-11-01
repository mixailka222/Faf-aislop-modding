-- stand: expect ReclaimPause: hotkeys installed: 0

-- The mod has no default keys: its actions exist, but nothing is bound to them, also not the key it
-- used to have. A real key press is not part of this run.
local Test = import("/mods/ModTest/modules/test.lua")
local KeyMapper = import("/lua/keymap/keymapper.lua")

local ACTIONS = { "reclaimpause_toggle", "reclaimpause_check", "reclaimpause_defaults" }

function Run()
    WaitSeconds(2)
    local known = KeyMapper.GetKeyActions()
    for _, action in ACTIONS do
        Test.Check(known[action] ~= nil, "the action exists: " .. action)
        Test.Check(not KeyMapper.GetCurrentKeyBinding(action), "no key for the action: " .. action)
    end
    Test.Check(KeyMapper.GetCurrentKeyMap()["Ctrl-Alt-R"] == nil, "Ctrl-Alt-R is not in the key map")
end
