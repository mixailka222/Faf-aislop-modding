-- stand: profile UserKeyMap = { K = 'reclaimpause_toggle', L = 'reclaimpause_check', J = 'reclaimpause_defaults' }
-- stand: expect ReclaimPause: hotkeys installed: 3

-- A new match with keys assigned before: the lobby drops the keys of a UI mod, so the mod installs them
-- at the start of the match. The profile of this run is what the key window saved in a match before,
-- and the keys are pressed for real.
local Test = import("/mods/ModTest/modules/test.lua")

local KEY_SECONDS = 8

function Run()
    local Watch = import("/mods/ReclaimPause/modules/watch.lua")
    local lines = Test.WatchLog(Watch)
    WaitSeconds(2)

    Test.PressKey("K")
    Test.Check(Test.WaitUntil(function() return Test.Logged(lines, "toggled, enabled=false") end, KEY_SECONDS),
        "the key toggles the mod")
    Test.PressKey("K")
    Test.Check(Test.WaitUntil(function() return Test.Logged(lines, "toggled, enabled=true") end, KEY_SECONDS),
        "the second press toggles it back")
end
