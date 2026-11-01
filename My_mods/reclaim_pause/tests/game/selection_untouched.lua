-- The mod looks for engineers by selecting them, so it may do that only while it holds a pause. With low
-- mass and with the mod switched off the selection of the player is not touched at all.
local Test = import("/mods/ModTest/modules/test.lua")

local PATROL_ENGINEER = "uel0105"
local QUIET_PASSES = 7

function Run()
    local Settings = import("/mods/ReclaimPause/modules/settings.lua")
    local Watch = import("/mods/ReclaimPause/modules/watch.lua")
    Settings.ReclaimPauseCfg.startGrace = 0
    local lines = Test.WatchLog(Watch)
    local passes = Test.CountCalls(Watch, "GetEconomyTotals")
    local scans = Test.CountCalls(Watch, "UISelectionByCategory")
    local selects = Test.CountCalls(Watch, "SelectUnits")

    WaitSeconds(2)
    Test.Spawn(PATROL_ENGINEER, 6, 6, { { 30, 30 }, { -10, 30 } })
    Test.TakeMass(400)
    WaitSeconds(1)
    local commander = Test.UnitsOfCategory("COMMAND")[1]
    SelectUnits({ commander })
    local function StartPauseIsOver()
        return not Test.Logged(lines, "PAUSED") or Test.Logged(lines, "RELEASED")
    end
    Test.Check(Test.WaitUntil(StartPauseIsOver, 10), "the pause from the start of the match is over")

    local function SelectionIsKept()
        local selected = GetSelectedUnits() or {}
        return table.getn(selected) == 1 and selected[1]:GetEntityId() == commander:GetEntityId()
    end

    local function QuietPhase(name)
        Test.ForgetLog(lines)
        local scansBefore = scans.calls
        local selectsBefore = selects.calls
        Test.WaitCalls(passes, QUIET_PASSES)
        Test.Step(name .. ": passes " .. tostring(QUIET_PASSES) .. ", selection calls " ..
            tostring(scans.calls - scansBefore + selects.calls - selectsBefore))
        Test.Check(scans.calls == scansBefore and selects.calls == selectsBefore,
            name .. ": the mod did not touch the selection")
        Test.Check(SelectionIsKept(), name .. ": the selection stayed")
        Test.Check(not Test.Logged(lines, "PAUSED"), name .. ": no PAUSED in the log")
    end

    local economy = GetEconomyTotals()
    Test.Check(economy.stored.MASS / economy.maxStorage.MASS < 0.65, "mass is below 65%")
    QuietPhase("low mass")

    -- The counters have to work, or the quiet phases prove nothing.
    Test.GiveMass(400)
    Test.Check(Test.WaitUntil(function() return scans.calls > 0 end, 10), "with full storage the mod does scan")
    Test.Check(Test.WaitUntil(function() return Test.Logged(lines, "PAUSED") end, 5),
        "with full storage the log has PAUSED")
    Test.Check(SelectionIsKept(), "the scan puts the selection back")

    ConExecute('UI_Lua import("/mods/ReclaimPause/modules/watch.lua").ReclaimPauseToggle()')
    Test.Check(Test.WaitUntil(function() return Test.Logged(lines, "toggled, enabled=false") end, 5), "the mod is off")
    Test.WaitCalls(passes, 1)
    QuietPhase("mod switched off")
end
