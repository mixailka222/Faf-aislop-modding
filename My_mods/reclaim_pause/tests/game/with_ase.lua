-- stand: mod ASE

-- ASE reworks a selection on its own and takes locked units out of it. The passes of the mod go past that
-- filter: the selection of the player stays, and an engineer locked in ASE is paused like any other.
local Test = import("/mods/ModTest/modules/test.lua")

local PATROL_ENGINEER = "uel0105"
local KEEP_SECONDS = 4
local SCAN_SECONDS = 10

function Run()
    local Settings = import("/mods/ReclaimPause/modules/settings.lua")
    local Watch = import("/mods/ReclaimPause/modules/watch.lua")
    local Lock = import("/mods/ASE/modules/Lock.lua")
    Settings.ReclaimPauseCfg.startGrace = 0
    local lines = Test.WatchLog(Watch)
    local scans = Test.CountCalls(Watch, "UISelectionByCategory")

    WaitSeconds(2)
    Test.TakeMass(600)
    Test.Spawn(PATROL_ENGINEER, 6, 6, { { 30, 30 }, { -10, 30 } })
    WaitSeconds(2)
    local engineer = Test.FindById(Test.UnitsOfCategory("ENGINEER"), PATROL_ENGINEER)
    local commander = Test.UnitsOfCategory("COMMAND")[1]
    Test.Check(engineer and commander, "the test units exist")
    if not (engineer and commander) then
        return
    end

    SelectUnits({ engineer })
    Lock.ToggleUnits()
    Test.Check(Lock.IsLocked(engineer), "ASE locked the engineer")
    SelectUnits({ commander })
    Test.ForgetLog(lines)
    local scansBefore = scans.calls

    Test.GiveMass(600)
    Test.Check(Test.WaitUntil(function() return GetIsPausedOfUnit(engineer) end, 15),
        "the locked engineer is paused")
    Test.Check(Test.WaitUntil(function() return scans.calls > scansBefore end, SCAN_SECONDS),
        "the mod scanned with the locked engineer")
    WaitSeconds(KEEP_SECONDS)
    local selected = GetSelectedUnits() or {}
    Test.Check(table.getn(selected) == 1 and selected[1]:GetEntityId() == commander:GetEntityId(),
        "the selection of the player stays")
    Test.Check(not Test.Logged(lines, "selection NOT restored"), "the mod put the selection back on every pass")
end
