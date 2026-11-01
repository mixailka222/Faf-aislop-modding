-- An engineer that builds is left alone even with a patrol waiting in its queue. Once the building is
-- finished the patrol is its first order, and only then the mod takes the engineer.
local Test = import("/mods/ModTest/modules/test.lua")

local ENGINEER = "uel0105"
local BUILDING = "ueb1101"
local PATROL = { { 30, 30 }, { -10, 30 } }

function Run()
    local Settings = import("/mods/ReclaimPause/modules/settings.lua")
    local Watch = import("/mods/ReclaimPause/modules/watch.lua")
    Settings.ReclaimPauseCfg.startGrace = 0
    local passes = Test.CountCalls(Watch, "GetEconomyTotals")

    WaitSeconds(2)
    Test.Spawn(ENGINEER, 8, 0)
    WaitSeconds(2)
    local engineer = Test.FindById(Test.UnitsOfCategory("ENGINEER"), ENGINEER)
    Test.Check(engineer, "the engineer exists")
    if not engineer then
        return
    end

    Test.Build(engineer, BUILDING, 14, 0, PATROL)
    local function Target()
        return engineer:GetFocus()
    end
    Test.Check(Test.WaitUntil(function() return Target() ~= nil end, 10), "the building was started")
    local building = Target()
    if not building then
        return
    end

    local queue = engineer:GetCommandQueue() or {}
    Test.Step("orders while building: " .. tostring(queue[1] and queue[1].type) .. ", " ..
        tostring(queue[2] and queue[2].type))
    Test.Check(table.getn(queue) >= 2, "the patrol waits in the queue")

    local checked = 0
    while Target() ~= nil do
        Test.Check(not GetIsPausedOfUnit(engineer), "no pause while building, pass " .. tostring(passes.calls))
        checked = checked + 1
        Test.WaitCalls(passes, 3)
    end
    Test.Step("checks while building: " .. tostring(checked))
    Test.Check(checked >= 3, "the mod scanned several times while the engineer was building")
    Test.Check(building:GetFractionComplete() == 1, "the engineer finished the building")
    local economy = GetEconomyTotals()
    Test.Check(economy.stored.MASS / economy.maxStorage.MASS >= 0.7, "mass stayed at 70% or more")
    Test.Check(Test.WaitUntil(function() return GetIsPausedOfUnit(engineer) end, 12),
        "the finished engineer goes on patrol and is paused")
end
