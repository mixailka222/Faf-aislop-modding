-- The main case of the mod: an engineer reclaims a wreck. A wreck is a prop and not a unit, so GetFocus
-- of the engineer has nothing to give back. The engineer has to count as not building, stop when the
-- reclaim fills mass up to 70% after the first 15 seconds, and go on 3 seconds after mass went down to 65%.
local Test = import("/mods/ModTest/modules/test.lua")

local ENGINEER = "uel0105"
local WRECK = "uel0401"
local GRACE_PASSES = 15
local HOLD_PASSES = 3

local function Reclaimed()
    return GetEconomyTotals().reclaimed.MASS
end

local function MassFill()
    local economy = GetEconomyTotals()
    return economy.stored.MASS / economy.maxStorage.MASS
end

local function TakeMassDownTo(fill)
    local economy = GetEconomyTotals()
    Test.TakeMass(economy.stored.MASS - fill * economy.maxStorage.MASS)
end

function Run()
    local Watch = import("/mods/ReclaimPause/modules/watch.lua")
    local lines = Test.WatchLog(Watch)
    local passes = Test.CountCalls(Watch, "GetEconomyTotals")

    WaitSeconds(2)
    Test.Spawn(ENGINEER, 8, 0)
    TakeMassDownTo(0.4)
    WaitSeconds(2)
    local engineer = Test.FindById(Test.UnitsOfCategory("ENGINEER"), ENGINEER)
    Test.Check(engineer, "the engineer exists")
    if not engineer then
        return
    end

    Test.WaitCalls(passes, GRACE_PASSES + 1 - passes.calls)
    Test.Check(MassFill() < 0.65, "mass is low before the reclaim")
    Test.ForgetLog(lines)

    Test.ReclaimWreck(engineer, WRECK, 14, 0)
    Test.Check(Test.WaitUntil(function() return Reclaimed() > 0 end, 10), "the reclaim of the wreck is running")
    local queue = engineer:GetCommandQueue() or {}
    Test.Step("focus while reclaiming a wreck: " .. tostring(engineer:GetFocus()))
    Test.Check(queue[1] and queue[1].type == "Reclaim", "the first order is the reclaim")

    local paused = Test.WaitUntil(function() return GetIsPausedOfUnit(engineer) end, 20)
    Test.Check(paused, "the engineer on a wreck is paused once mass is at 70%")
    Test.Step("mass at the pause: " .. tostring(MassFill()))
    Test.Check(Test.Logged(lines, "ReclaimPause: PAUSED"), "the log has PAUSED")
    Test.Check(Test.Logged(lines, "nowPaused=1"), "the line of the pause counts the engineer")
    if not paused then
        return
    end

    Test.WaitCalls(passes, 1)
    local stopped = Reclaimed()
    Test.WaitCalls(passes, 3)
    Test.Check(Reclaimed() == stopped, "the reclaim of the wreck stands still during the pause")
    Test.Check(table.getn(engineer:GetCommandQueue() or {}) > 0, "the order survived the pause")

    TakeMassDownTo(0.6)
    WaitSeconds(0.5)
    Test.Check(MassFill() <= 0.65, "mass went down to 65% or lower")
    local low = passes.calls
    Test.Check(Test.WaitUntil(function() return Test.Logged(lines, "ReclaimPause: RELEASED") end, 15),
        "the log has RELEASED")
    Test.Step("passes from low mass to the release: " .. tostring(passes.calls - low))
    Test.Check(passes.calls - low >= HOLD_PASSES, "the release waits for 3 seconds of low mass")
    Test.Check(Test.WaitUntil(function() return not GetIsPausedOfUnit(engineer) end, 5), "the engineer is released")
    Test.Check(Test.WaitUntil(function() return Reclaimed() > stopped end, 15), "the reclaim of the wreck goes on")
end
