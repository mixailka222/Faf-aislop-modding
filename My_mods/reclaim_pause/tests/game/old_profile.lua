-- stand: profile ReclaimPause = { startGrace = 0, skipSec = 300 }
-- stand: expect ReclaimPause: started

-- A profile saved by an older version holds values the sliders no longer reach. The page reads that profile
-- and copies it into the mod, so the limits have to hold after the page has loaded and after a slider moved.
-- The files of a mod are mounted without the mod too, so the line of its start shows that it was active.
local Test = import("/mods/ModTest/modules/test.lua")
local Prefs = import("/lua/user/prefs.lua")

local SMALLEST_GRACE = 10
local LARGEST_SKIP = 60

local function CheckLimits(moment)
    local Settings = import("/mods/ReclaimPause/modules/settings.lua")
    local cfg = Settings.ReclaimPauseCfg
    Test.Step(moment .. ": " .. tostring(cfg.startGrace) .. ", " .. tostring(cfg.skipSec))
    Test.Check(cfg.startGrace == SMALLEST_GRACE, moment .. ": the start delay is at the smallest value")
    Test.Check(cfg.skipSec == LARGEST_SKIP, moment .. ": the skip time is at the largest value")
end

function Run()
    WaitSeconds(2)
    local options = UMT.Options.Mods["ReclaimPause"]
    CheckLimits("page loaded")
    options.minSec:Set(4)
    CheckLimits("slider moved")
    local saved = Prefs.GetFromCurrentProfile("ReclaimPause")
    Test.Check(saved.startGrace == SMALLEST_GRACE, "the profile has the smallest start delay")
    Test.Check(saved.skipSec == LARGEST_SKIP, "the profile has the largest skip time")
end
