-- The mod leaves the selection alone while the player is in command mode. A route abort that falls due
-- meanwhile goes out right after the mode ends, and the manual check says that it did not scan.
local Test = import("/mods/ModTest/modules/test.lua")
local CommandMode = import("/lua/ui/game/commandmode.lua")

local PATROL_ENGINEER = "uel0105"
local ABORT_SEC = 8

local aborts = 0
local passes = 0
local lines = {}

local function Logged(text)
    for _, line in lines do
        if string.find(line, text, 1, true) then
            return true
        end
    end
    return false
end

-- Seconds do not work here: the match runs faster than real time and its speed changes.
local function WaitPasses(count)
    local target = passes + count
    while passes < target do
        WaitSeconds(0.1)
    end
end

function Run()
    local Settings = import("/mods/ReclaimPause/modules/settings.lua")
    local Watch = import("/mods/ReclaimPause/modules/watch.lua")
    Settings.ReclaimPauseCfg.startGrace = 0
    Settings.ReclaimPauseCfg.abortSec = ABORT_SEC

    -- The module table is the environment of watch.lua, so these names change for that file only.
    -- The UI of the game asks for the economy too, a counter in the global table would see that.
    Watch.SimCallback = function(callback, addSelection)
        if callback.Func == "AbortNavigation" then
            aborts = aborts + 1
        end
        SimCallback(callback, addSelection)
    end
    Watch.GetEconomyTotals = function()
        passes = passes + 1
        return GetEconomyTotals()
    end
    Watch.LOG = function(text)
        table.insert(lines, tostring(text))
        LOG(text)
    end

    WaitSeconds(2)
    Test.Spawn(PATROL_ENGINEER, 6, 6, { { 30, 30 }, { -10, 30 } })
    WaitSeconds(2)
    local engineer = Test.FindById(Test.UnitsOfCategory("ENGINEER"), PATROL_ENGINEER)
    Test.Check(engineer, "the engineer exists")
    if not engineer then
        return
    end
    local paused = Test.WaitUntil(function() return GetIsPausedOfUnit(engineer) end, 10)
    Test.Check(paused, "the engineer is paused")
    if not paused then
        return
    end
    Test.Check(Test.WaitUntil(function() return aborts > 0 end, 3), "the pause came with a route abort")

    CommandMode.StartCommandMode("order", { name = "RULEUCC_Move" })
    local before = aborts
    WaitPasses(ABORT_SEC + 1)
    Test.Check(CommandMode.InCommandMode(), "the command mode of the player survived")
    Test.Check(aborts == before, "no route abort during the command mode")
    CommandMode.EndCommandMode(true)
    WaitPasses(2)
    Test.Check(aborts > before, "the abort that fell due goes out right after the command mode")

    CommandMode.StartCommandMode("order", { name = "RULEUCC_Move" })
    lines = {}
    Watch.ReclaimPauseForceCheck()
    Test.Check(Logged("engineersFound=?"), "the manual check says it did not scan in the command mode")
    Test.Check(CommandMode.InCommandMode(), "the manual check left the command mode alone")
    CommandMode.EndCommandMode(true)
    lines = {}
    Watch.ReclaimPauseForceCheck()
    Test.Check(Logged("engineersFound=1"), "the manual check counts the engineer after the command mode")
end
