-- The smallest value of the option. The first pass of the mod selects all engineers for a moment, and it must
-- not meet the game selecting the commander, or the player starts the match with nothing selected.
local Test = import("/mods/ModTest/modules/test.lua")

local SMALLEST_GRACE = 5
local SCAN_SECONDS = 15

function Run()
    local Settings = import("/mods/ReclaimPause/modules/settings.lua")
    local Watch = import("/mods/ReclaimPause/modules/watch.lua")
    Settings.ReclaimPauseCfg.startGrace = SMALLEST_GRACE
    local lines = Test.WatchLog(Watch)
    local scans = Test.CountCalls(Watch, "UISelectionByCategory")

    Test.Check(Test.WaitUntil(function() return scans.calls > 0 end, SCAN_SECONDS), "the mod scanned")
    WaitSeconds(1)
    Test.Check(not Test.Logged(lines, "selection NOT restored"), "the first pass puts the selection back")
    Test.Check(table.getn(GetSelectedUnits() or {}) == 1, "the commander stays selected")
end
