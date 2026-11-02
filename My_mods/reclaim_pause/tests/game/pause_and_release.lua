-- The mod pauses engineers on patrol while mass and energy are above 70%, leaves the first 15 seconds
-- of a match alone, and releases them once mass has stayed at 65% or lower for 3 seconds.
local Test = import("/mods/ModTest/modules/test.lua")

local PATROL_ENGINEER = "uel0105"
local IDLE_ENGINEER = "uel0208"

local function MassFill()
    local economy = GetEconomyTotals()
    return economy.stored.MASS / economy.maxStorage.MASS
end

function Run()
    WaitSeconds(2)
    Test.Spawn(PATROL_ENGINEER, 6, 6, { { 30, 30 }, { -10, 30 } })
    Test.Spawn(IDLE_ENGINEER, -6, -6)
    WaitSeconds(5)

    local engineers = Test.UnitsOfCategory("ENGINEER")
    local patrol = Test.FindById(engineers, PATROL_ENGINEER)
    local idle = Test.FindById(engineers, IDLE_ENGINEER)
    local commander = Test.UnitsOfCategory("COMMAND")[1]
    Test.Check(patrol and idle and commander, "the test units exist")
    if not (patrol and idle and commander) then
        return
    end

    Test.Check(not GetIsPausedOfUnit(patrol), "no pause during the first 15 seconds")
    local paused = Test.WaitUntil(function() return GetIsPausedOfUnit(patrol) end, 22)
    Test.Check(paused, "the engineer on patrol is paused while the storage is full")
    Test.Check(not GetIsPausedOfUnit(idle), "the engineer without orders is not paused")
    Test.Check(not GetIsPausedOfUnit(commander), "the commander is not paused")
    if not paused then
        return
    end

    Test.TakeMass(600)
    WaitSeconds(1)
    Test.Check(MassFill() <= 0.65, "mass went down to 65% or lower")
    Test.Check(Test.WaitUntil(function() return not GetIsPausedOfUnit(patrol) end, 10),
        "the engineer is released after mass went down")
    Test.Check(table.getn(patrol:GetCommandQueue() or {}) > 0, "the patrol order survived the pause")
end
