-- stand: mod UMT
-- stand: mod ASE

-- A unit locked in the real ASE is skipped, with keys and the mouse from game_test.py. ASE takes a locked unit
-- out of a selection on its own, so this also shows that the hidden selection of the mod does not run into
-- that filter. The scenario gives the answer of IsKeyDown, see nearest_unit.lua.
local Test = import("/mods/ModTest/modules/test.lua")
local KeyMapper = import("/lua/keymap/keymapper.lua")

local FIGHTER = "uea0102"
local TANK = "uel0201"
local ACTION = "Select_nearest_fighter_build_shields"
local ACTION_KEY = "K"
local LOCK_ACTION = "Toggle units lock"
local LOCK_KEY = "L"
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
    local Lock = import("/mods/ASE/modules/Lock.lua")
    local shift = false
    import("/mods/customhotkeys/Main.lua").IsKeyDown = function(key)
        return shift and key == "Shift"
    end

    local known = KeyMapper.GetKeyActions()
    Test.Check(known[ACTION] ~= nil, "the action exists")
    Test.Check(known[LOCK_ACTION] ~= nil, "the action of ASE exists")
    if not known[ACTION] or not known[LOCK_ACTION] then
        return
    end

    WaitSeconds(2)
    Test.Spawn(FIGHTER, LEFT_OFFSET, 0)
    Test.Spawn(FIGHTER, RIGHT_OFFSET, 0)
    Test.Spawn(TANK, 0, 12)
    WaitSeconds(3)
    local fighters = Test.UnitsOfCategory("AIR")
    local tank = Test.FindById(Test.UnitsOfCategory("LAND MOBILE TECH1 DIRECTFIRE"), TANK)
    Test.Check(table.getn(fighters) == 2 and tank, "the test units exist")
    if table.getn(fighters) ~= 2 or not tank then
        return
    end
    local first, second = fighters[1], fighters[2]

    KeyMapper.SetUserKeyMapping(ACTION_KEY, nil, ACTION)
    KeyMapper.SetUserKeyMapping(LOCK_KEY, nil, LOCK_ACTION)
    Test.Upvalue(import("/lua/ui/dialogs/keybindings.lua").CreateUI, "ConfirmNewKeyMap")()

    local function LockUnit(unit)
        SelectUnits({ unit })
        Test.PressKey(LOCK_KEY)
        Test.Check(Test.WaitUntil(function() return Lock.IsLocked(unit) end, KEY_SECONDS), "ASE locked the unit")
    end

    SelectUnits({ tank })
    Test.MoveMouseTo(first:GetPosition())
    Test.PressKey(ACTION_KEY)
    Test.Check(SelectedAfterKey({ first }), "without a lock the key selects the unit at the cursor")

    LockUnit(first)
    SelectUnits({ tank })
    Test.PressKey(ACTION_KEY)
    Test.Check(SelectedAfterKey({ second }), "the locked unit at the cursor is skipped")

    shift = true
    Test.PressKey("Shift-" .. ACTION_KEY)
    WaitSeconds(NOTHING_HAPPENS_SECONDS)
    Test.Check(Same({ second }), "Shift does not add the locked unit")
    shift = false

    LockUnit(second)
    SelectUnits({ tank })
    Test.PressKey(ACTION_KEY)
    Test.Check(SelectedAfterKey({}), "with all units locked the selection is cleared")
end
