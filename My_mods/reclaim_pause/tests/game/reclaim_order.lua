-- An engineer reclaiming a finished unit counts as reclaiming, not as building: the mod tells them apart
-- by the fraction complete of the unit in focus.
local Test = import("/mods/ModTest/modules/test.lua")

local ENGINEER = "uel0105"
local TARGET = "ueb0101"

function Run()
    local Settings = import("/mods/ReclaimPause/modules/settings.lua")
    Settings.ReclaimPauseCfg.startGrace = 0
    Settings.ReclaimPauseCfg.enabled = false

    WaitSeconds(2)
    Test.Spawn(TARGET, 14, 0)
    Test.Spawn(ENGINEER, 8, 0)
    WaitSeconds(2)
    local engineer = Test.FindById(Test.UnitsOfCategory("ENGINEER"), ENGINEER)
    local target = Test.FindById(Test.UnitsOfCategory("STRUCTURE"), TARGET)
    Test.Check(engineer and target, "the test units exist")
    if not (engineer and target) then
        return
    end

    local fullHealth = target:GetHealth()
    Test.Reclaim(engineer, target)
    Test.Check(Test.WaitUntil(function() return target:GetHealth() < fullHealth end, 8), "the reclaim is running")
    local focus = engineer:GetFocus()
    Test.Check(focus and focus:GetEntityId() == target:GetEntityId(), "the target of the reclaim is in focus")
    Test.Check(target:GetFractionComplete() == 1, "reclaim lowers the health of a unit, not its fraction complete")

    Settings.ReclaimPauseCfg.enabled = true
    Test.Check(Test.WaitUntil(function() return GetIsPausedOfUnit(engineer) end, 8),
        "the engineer with a reclaim order is paused while the storage is full")
end
