-- stand: expect by ExtraMassBlocker, Puffskein

-- The three actions with keys and the mouse from game_test.py, the keys are assigned the way the key window
-- does it. With nothing that can build a key selects the unit nearest to the cursor, with Shift it adds the
-- next one, with a builder selected it runs Hotbuild. The engine takes Shift from the keyboard of the system
-- and only with the focus, which the stand does not take, so the scenario gives the state of Shift.
local Test = import("/mods/ModTest/modules/test.lua")
local CommandMode = import("/lua/ui/game/commandmode.lua")
local KeyMapper = import("/lua/keymap/keymapper.lua")

local TANK = "uel0201"
local ENGINEER = "uel0208"
local ACTIONS = {
    { name = "Select_nearest_fighter_build_shields", unit = "uea0102", key = "K", side = 0 },
    { name = "Select_nearest_bomber_build_TMD", unit = "uea0103", key = "J", side = -7 },
    { name = "Select_nearest_air_scout_build_sensors_Custom_", unit = "uea0101", key = "Y", side = 7 },
}
local LEFT_OFFSET = -7
local RIGHT_OFFSET = 7
local KEY_SECONDS = 8
local NOTHING_HAPPENS_SECONDS = 4

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

local function SelectedAfterKey(units)
    return Test.WaitUntil(function() return Same(units) end, KEY_SECONDS)
end

function Run()
    local shift = false
    import("/mods/customhotkeys/Main.lua").IsKeyDown = function(key)
        return shift and key == "Shift"
    end

    local known = KeyMapper.GetKeyActions()
    for _, action in ACTIONS do
        Test.Check(known[action.name] ~= nil, "the action exists: " .. action.name)
    end

    WaitSeconds(2)
    for _, action in ACTIONS do
        Test.Spawn(action.unit, LEFT_OFFSET, action.side)
        Test.Spawn(action.unit, RIGHT_OFFSET, action.side)
    end
    Test.Spawn(TANK, 0, 12)
    Test.Spawn(ENGINEER, 3, 12)
    WaitSeconds(3)

    local air = Test.UnitsOfCategory("AIR")
    local tank = Test.FindById(Test.UnitsOfCategory("LAND MOBILE TECH1 DIRECTFIRE"), TANK)
    local engineer = Test.FindById(Test.UnitsOfCategory("ENGINEER TECH2"), ENGINEER)
    Test.Check(table.getn(air) == 6 and tank and engineer, "the test units exist")
    if table.getn(air) ~= 6 or not tank or not engineer then
        return
    end

    for _, action in ACTIONS do
        KeyMapper.SetUserKeyMapping(action.key, nil, action.name)
    end
    Test.Upvalue(import("/lua/ui/dialogs/keybindings.lua").CreateUI, "ConfirmNewKeyMap")()

    local function PairOf(action)
        local pair = {}
        for _, unit in air do
            if unit:GetUnitId() == action.unit then
                table.insert(pair, unit)
            end
        end
        return pair
    end

    for _, action in ACTIONS do
        local pair = PairOf(action)
        local first, second = pair[1], pair[2]

        SelectUnits({ tank })
        Test.MoveMouseTo(first:GetPosition())
        Test.PressKey(action.key)
        Test.Check(SelectedAfterKey({ first }), action.name .. ": selects the unit at the cursor")

        SelectUnits({ tank })
        Test.MoveMouseTo(second:GetPosition())
        Test.PressKey(action.key)
        Test.Check(SelectedAfterKey({ second }), action.name .. ": another cursor selects the other unit")

        shift = true
        Test.PressKey(action.key)
        Test.Check(SelectedAfterKey(pair), action.name .. ": Shift adds the next unit")
        Test.PressKey(action.key)
        WaitSeconds(NOTHING_HAPPENS_SECONDS)
        Test.Check(Same(pair), action.name .. ": with nothing left to add the selection stays")
        shift = false

        SelectUnits({ engineer })
        Test.PressKey(action.key)
        local built = Test.WaitUntil(function() return CommandMode.GetCommandMode()[1] == "build" end, KEY_SECONDS)
        Test.Step(action.name .. ": building " .. tostring(CommandMode.GetCommandMode()[2] and
            CommandMode.GetCommandMode()[2].name))
        Test.Check(built, action.name .. ": with a builder the key runs Hotbuild")
        Test.Check(Same({ engineer }), action.name .. ": Hotbuild keeps the builder selected")
        CommandMode.EndCommandMode(true)
    end
end
