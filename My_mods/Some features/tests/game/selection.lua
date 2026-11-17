-- Checks the Shift+Alt selection filter with an engineer, ACU, SACU, and combat unit.
local Test = import("/mods/ModTest/modules/test.lua")
local GameMain = import("/lua/ui/game/gamemain.lua")

local function Contains(units, unit)
    for _, candidate in units do
        if candidate == unit then
            return true
        end
    end
    return false
end

function Run()
    WaitSeconds(2)
    Test.Spawn("uel0105", -6, 0)
    Test.Spawn("uel0001", -2, 0)
    Test.Spawn("uel0301", 2, 0)
    Test.Spawn("uel0201", 6, 0)
    WaitSeconds(3)

    local engineer = Test.FindById(Test.UnitsOfCategory("ENGINEER"), "uel0105")
    local commander = Test.FindById(Test.UnitsOfCategory("COMMAND"), "uel0001")
    local sacu = Test.FindById(Test.UnitsOfCategory("SUBCOMMANDER"), "uel0301")
    local tank = Test.FindById(Test.UnitsOfCategory("LAND MOBILE"), "uel0201")
    Test.Check(engineer and commander and sacu and tank, "all selection test units exist")
    if not (engineer and commander and sacu and tank) then
        return
    end

    -- The mod asks the real keyboard, so the keys are faked for the duration of one call.
    local realIsKeyDown = IsKeyDown
    _G.IsKeyDown = function(key)
        return key == "shift" or key == "menu"
    end
    local result, changed = GameMain.DeselectSelens({ engineer, commander, sacu, tank })
    _G.IsKeyDown = realIsKeyDown

    Test.Check(changed, "Shift+Alt reports a changed selection")
    Test.Check(table.getn(result) == 3, "Shift+Alt keeps three special unit types")
    Test.Check(Contains(result, engineer) and Contains(result, commander) and Contains(result, sacu),
        "Shift+Alt keeps engineer, commander, and SACU")
    Test.Check(not Contains(result, tank), "Shift+Alt removes the combat unit")
end
