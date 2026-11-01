-- The player holds a building on the cursor while the mod keeps engineers on pause. A restart of the
-- command mode would drop the building from the cursor, so the mode must not end once in the whole time.
local Test = import("/mods/ModTest/modules/test.lua")
local CommandMode = import("/lua/ui/game/commandmode.lua")

local PATROL_ENGINEER = "uel0105"
local BUILDING = "ueb1101"
local HELD_PASSES = 8

function Run()
    local Settings = import("/mods/ReclaimPause/modules/settings.lua")
    local Watch = import("/mods/ReclaimPause/modules/watch.lua")
    Settings.ReclaimPauseCfg.startGrace = 0
    local lines = Test.WatchLog(Watch)
    local passes = Test.CountCalls(Watch, "GetEconomyTotals")

    WaitSeconds(2)
    Test.Spawn(PATROL_ENGINEER, 6, 6, { { 30, 30 }, { -10, 30 } })
    WaitSeconds(2)
    local engineer = Test.FindById(Test.UnitsOfCategory("ENGINEER"), PATROL_ENGINEER)
    Test.Check(engineer, "the engineer exists")
    if not engineer then
        return
    end
    Test.Check(Test.WaitUntil(function() return GetIsPausedOfUnit(engineer) end, 10), "the engineer is paused")

    local commander = Test.UnitsOfCategory("COMMAND")[1]
    SelectUnits({ commander })
    local ended = 0
    CommandMode.AddEndBehavior(function() ended = ended + 1 end, "ModTestBuildPlacement")
    CommandMode.StartCommandMode("build", { name = BUILDING })

    Test.ForgetLog(lines)
    Test.WaitCalls(passes, HELD_PASSES)
    local mode = CommandMode.GetCommandMode()
    Test.Step("passes in the mode: " .. tostring(HELD_PASSES) .. ", periodic lines: " .. tostring(table.getn(lines)))
    Test.Check(table.getn(lines) > 0, "the mod kept working during the mode")
    Test.Check(mode[1] == "build" and mode[2] and mode[2].name == BUILDING, "the building is still on the cursor")
    Test.Check(ended == 0, "the mode did not end once")
    local selected = GetSelectedUnits() or {}
    Test.Check(table.getn(selected) == 1 and selected[1]:GetEntityId() == commander:GetEntityId(),
        "the selection of the player stayed")
    CommandMode.EndCommandMode(true)
end
