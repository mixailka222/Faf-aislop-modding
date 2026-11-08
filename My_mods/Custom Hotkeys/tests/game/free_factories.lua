-- stand: expect by ExtraMassBlocker, Puffskein
-- The hotkey reads GetIdleFactories. A factory keeps the last order in its queue, and the engine holds it
-- in the idle list until that order is cleared: a factory is made busy with IssueBlueprintCommandToUnits,
-- which takes the unit list instead of the selection, so the scenario does not have to juggle the selection
-- to fill the production queue. A press with Shift goes through a real key message, but IsKeyDown sees such
-- a Shift only with the focus, which the stand does not take, so the scenario gives its answer, see
-- nearest_unit.lua.
local Test = import("/mods/ModTest/modules/test.lua")
local KeyMapper = import("/lua/keymap/keymapper.lua")

local ACTION = "Select_all_free_factories"
local KEY = "R"
local TANK = "uel0201"
-- T1 factories of the UEF: land ueb0101, air ueb0102, naval ueb0103, the order
-- of the last two is easy to mix up.
local LAND = "ueb0101"
local AIR = "ueb0102"
local NAVAL = "ueb0103"
-- A unit every T1 factory can produce, it keeps a factory busy.
local QUEUE = "uel0201"
local LEFT_OFFSET = -7
local RIGHT_OFFSET = 7
local LEFT_SIDE = -14
local RIGHT_SIDE = 14
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

--- The engine reports a factory in the idle list until its last order is
--- cleared, so a factory that just got an order may still show up there. The
--- hotkey drops the factories with a build order, and this is the check of a
--- real free factory.
local function FreeFactories()
    local free = {}
    for _, factory in GetIdleFactories() or {} do
        if table.getn(factory:GetCommandQueue() or {}) == 0 then
            table.insert(free, factory)
        end
    end
    return free
end

function Run()
    local shift = false
    import("/mods/customhotkeys/Main.lua").IsKeyDown = function(key)
        return shift and key == "Shift"
    end

    local known = KeyMapper.GetKeyActions()
    Test.Check(known[ACTION] ~= nil, "the action exists")
    if not known[ACTION] then
        return
    end

    WaitSeconds(2)
    Test.Spawn(LAND, LEFT_OFFSET, LEFT_SIDE)
    Test.Spawn(AIR, LEFT_OFFSET, 0)
    Test.Spawn(NAVAL, LEFT_OFFSET, RIGHT_SIDE)
    Test.Spawn(TANK, RIGHT_OFFSET, 0)
    WaitSeconds(3)

    local land = Test.FindById(Test.UnitsOfCategory("FACTORY LAND TECH1"), LAND)
    local air = Test.FindById(Test.UnitsOfCategory("FACTORY AIR TECH1"), AIR)
    local naval = Test.FindById(Test.UnitsOfCategory("FACTORY NAVAL TECH1"), NAVAL)
    local tank = Test.FindById(Test.UnitsOfCategory("LAND MOBILE TECH1 DIRECTFIRE"), TANK)
    Test.Check(land and air and naval and tank, "the test units exist")
    if not (land and air and naval and tank) then
        return
    end

    KeyMapper.SetUserKeyMapping(KEY, nil, ACTION)
    Test.Upvalue(import("/lua/ui/dialogs/keybindings.lua").CreateUI, "ConfirmNewKeyMap")()

    Test.Step("three free factories")
    SelectUnits({ tank })
    Test.PressKey(KEY)
    Test.Check(SelectedAfterKey({ land, air, naval }), "the key selects all three factories")

    Test.Step("one factory is busy")
    IssueBlueprintCommandToUnits({ land }, "UNITCOMMAND_BuildFactory", QUEUE, 1)
    Test.Check(Test.WaitUntil(function()
        return table.getn(GetIdleFactories() or {}) == 2
    end, KEY_SECONDS), "the factory with the order left the idle list")
    Test.Step(table.getn(FreeFactories()) .. " free factories after the order, the queue of the land factory: " ..
        table.getn(land:GetCommandQueue() or {}))

    SelectUnits({ tank })
    Test.PressKey(KEY)
    Test.Check(SelectedAfterKey({ air, naval }), "the busy factory is not selected")

    Test.Step("Shift adds the free factories")
    shift = true
    SelectUnits({ tank })
    Test.PressKey(KEY)
    Test.Check(SelectedAfterKey({ tank, air, naval }), "the free factories are added to the selection")
    shift = false

    Test.Step("every factory is busy, the selection stays")
    IssueBlueprintCommandToUnits({ air, naval }, "UNITCOMMAND_BuildFactory", QUEUE, 1)
    Test.Check(Test.WaitUntil(function()
        return table.getn(GetIdleFactories() or {}) == 0
    end, KEY_SECONDS), "the other factories left the idle list")
    SelectUnits({ tank })
    Test.PressKey(KEY)
    WaitSeconds(NOTHING_HAPPENS_SECONDS)
    Test.Check(Same({ tank }), "the selection did not change")

    Test.Step("cleared factories are busy until the order is gone")
    IssueBlueprintCommandToUnits({ land, air, naval }, "UNITCOMMAND_ClearCommands", QUEUE, 0)
    Test.Check(Test.WaitUntil(function()
        return table.getn(GetIdleFactories() or {}) == 3
    end, KEY_SECONDS), "the cleared factories are in the idle list again")
    Test.Step(table.getn(FreeFactories()) .. " free factories after clearing the orders")
    Test.PressKey(KEY)
    Test.Check(SelectedAfterKey({ land, air, naval }), "all three factories are selected again")
end