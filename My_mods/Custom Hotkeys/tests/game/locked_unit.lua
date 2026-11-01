-- A unit locked in ASE is skipped. ASE itself is not part of this run: a stand-in gives the function the
-- mod asks ASE for, so this proves the side of the mod and not that ASE answers the same way.
local Test = import("/mods/ModTest/modules/test.lua")
local KeyMapper = import("/lua/keymap/keymapper.lua")

local FIGHTER = "uea0102"
local TANK = "uel0201"
local ACTION = "Select_nearest_fighter_build_shields"

local function Ids(units)
    local ids = {}
    for _, unit in units or {} do
        table.insert(ids, unit:GetEntityId())
    end
    table.sort(ids)
    return table.concat(ids, ",")
end

local function Same(units)
    return Ids(GetSelectedUnits()) == Ids(units)
end

function Run()
    local Main = import("/mods/customhotkeys/Main.lua")
    local locked = {}
    local cursor = { 0, 0, 0 }
    local shift = false
    local gameImport = import
    Main.import = function(path)
        if path == "/mods/ASE/modules/Lock.lua" then
            return { IsLocked = function(unit) return locked[unit:GetEntityId()] == true end }
        end
        return gameImport(path)
    end
    Main.GetMouseWorldPos = function()
        return cursor
    end
    Main.IsKeyDown = function(key)
        return shift and key == "Shift"
    end

    local action = KeyMapper.GetKeyActions()[ACTION]
    Test.Check(action ~= nil, "the action exists")
    if not action then
        return
    end
    local function Press()
        ConExecute(action.action)
        WaitSeconds(0.3)
    end

    WaitSeconds(2)
    Test.Spawn(FIGHTER, 8, 0)
    Test.Spawn(FIGHTER, 30, 0)
    Test.Spawn(TANK, -8, 0)
    WaitSeconds(3)
    local fighters = Test.UnitsOfCategory("AIR")
    local tank = Test.FindById(Test.UnitsOfCategory("LAND MOBILE TECH1 DIRECTFIRE"), TANK)
    Test.Check(table.getn(fighters) == 2 and tank, "the test units exist")
    if table.getn(fighters) ~= 2 or not tank then
        return
    end
    local first, second = fighters[1], fighters[2]

    SelectUnits({ tank })
    cursor = first:GetPosition()
    Press()
    Test.Check(Same({ first }), "without a lock the key selects the unit at the cursor")

    locked[first:GetEntityId()] = true
    SelectUnits({ tank })
    Press()
    Test.Check(Same({ second }), "the locked unit at the cursor is skipped")

    shift = true
    Press()
    Test.Check(Same({ second }), "Shift does not add the locked unit")
    shift = false

    locked[second:GetEntityId()] = true
    SelectUnits({ tank })
    Press()
    Test.Check(table.getn(GetSelectedUnits() or {}) == 0, "with all units locked the selection is cleared")
end
