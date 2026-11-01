-- stand: expect by ExtraMassBlocker, Puffskein

-- The three actions: with nothing that can build they select the unit nearest to the cursor, with Shift
-- they add the next one, with a builder selected they run Hotbuild. One press is a real key, the others run
-- the text of the action as a key does. The cursor and Shift come from the scenario, a message for a key
-- carries neither of them.
local Test = import("/mods/ModTest/modules/test.lua")
local CommandMode = import("/lua/ui/game/commandmode.lua")
local KeyMapper = import("/lua/keymap/keymapper.lua")

local TANK = "uel0201"
local ENGINEER = "uel0208"
local ACTIONS = {
    { name = "Select_nearest_fighter_build_shields", unit = "uea0102" },
    { name = "Select_nearest_bomber_build_TMD", unit = "uea0103" },
    { name = "Select_nearest_air_scout_build_sensors_Custom_", unit = "uea0101" },
}
local NEAR_OFFSET = 8
local FAR_OFFSET = 30
local NEAR_SIDE = { 0, 30, -30 }
local REAL_KEY = "K"
local KEY_SECONDS = 8

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
    local cursor = { 0, 0, 0 }
    local shift = false
    Main.GetMouseWorldPos = function()
        return cursor
    end
    Main.IsKeyDown = function(key)
        return shift and key == "Shift"
    end

    local known = KeyMapper.GetKeyActions()
    for _, action in ACTIONS do
        Test.Check(known[action.name] ~= nil, "the action exists: " .. action.name)
    end

    local function Press(action)
        ConExecute(known[action.name].action)
        WaitSeconds(0.3)
    end

    WaitSeconds(2)
    for index, action in ACTIONS do
        Test.Spawn(action.unit, NEAR_OFFSET, NEAR_SIDE[index])
        Test.Spawn(action.unit, FAR_OFFSET, NEAR_SIDE[index])
    end
    Test.Spawn(TANK, -8, 0)
    Test.Spawn(ENGINEER, -8, 8)
    WaitSeconds(3)

    local air = Test.UnitsOfCategory("AIR")
    local tank = Test.FindById(Test.UnitsOfCategory("LAND MOBILE TECH1 DIRECTFIRE"), TANK)
    local engineer = Test.FindById(Test.UnitsOfCategory("ENGINEER TECH2"), ENGINEER)
    Test.Check(table.getn(air) == 6 and tank and engineer, "the test units exist")
    if table.getn(air) ~= 6 or not tank or not engineer then
        return
    end

    local function PairOf(action)
        local pair = {}
        for _, unit in air do
            if unit:GetUnitId() == action.unit then
                table.insert(pair, unit)
            end
        end
        return pair
    end

    -- A key assigned in the match the way the key window does it, and pressed for real.
    KeyMapper.SetUserKeyMapping(REAL_KEY, nil, ACTIONS[1].name)
    Test.Upvalue(import("/lua/ui/dialogs/keybindings.lua").CreateUI, "ConfirmNewKeyMap")()
    local fighter = PairOf(ACTIONS[1])[1]
    SelectUnits({ tank })
    cursor = fighter:GetPosition()
    Test.PressKey(REAL_KEY)
    Test.Check(Test.WaitUntil(function() return Same({ fighter }) end, KEY_SECONDS),
        "a real key press selects the unit at the cursor")

    for _, action in ACTIONS do
        local pair = PairOf(action)
        local first, second = pair[1], pair[2]

        SelectUnits({ tank })
        cursor = first:GetPosition()
        Press(action)
        Test.Check(Same({ first }), action.name .. ": selects the unit at the cursor")

        SelectUnits({ tank })
        cursor = second:GetPosition()
        Press(action)
        Test.Check(Same({ second }), action.name .. ": another cursor selects the other unit")

        shift = true
        Press(action)
        Test.Check(Same(pair), action.name .. ": Shift adds the next unit")
        Press(action)
        Test.Check(Same(pair), action.name .. ": with nothing left to add the selection stays")
        shift = false

        SelectUnits({ engineer })
        Press(action)
        Test.Step(action.name .. ": command mode " .. tostring(CommandMode.GetCommandMode()[1]) ..
            ", building " .. tostring(CommandMode.GetCommandMode()[2] and CommandMode.GetCommandMode()[2].name))
        Test.Check(CommandMode.GetCommandMode()[1] == "build", action.name .. ": with a builder the key runs Hotbuild")
        Test.Check(Same({ engineer }), action.name .. ": Hotbuild keeps the builder selected")
        CommandMode.EndCommandMode(true)
    end
end
