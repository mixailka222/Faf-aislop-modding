-- Exercises the mouse features of the mod.
-- The game_test harness can move the cursor but cannot press mouse buttons itself, so synthetic
-- events and stubs are used here: the scenario checks what the mod asks the game to do, not how
-- the real click feels. A real in-match check is still needed for the order the engine picks.
local Test = import("/mods/ModTest/modules/test.lua")
local Mod = import("/mods/Somefeatures/Main.lua")
local WorldView = import("/lua/ui/game/worldview.lua").viewLeft
local Actions = import("/lua/keymap/misckeyactions.lua")

---Ctrl, as in `/lua/ui/controls/worldview.lua`.
local KEY_CTRL = 17

local function Contains(text, part)
    return string.find(text, part, 1, true) ~= nil
end

function Run()
    WaitSeconds(2)

    -- Ctrl plus right click must keep the engine away from the unit under the cursor. The mod
    -- switches the game ignore mode on while Ctrl is held: in that mode the engine picks no unit,
    -- so a right click on an enemy becomes a Move. The mode has to be on before the click, because
    -- the engine reads it while it processes the click itself.
    local realIsKeyDown = _G.IsKeyDown
    local realConExecute = _G.ConExecute
    local executed = {}

    _G.ConExecute = function(command)
        table.insert(executed, command)
    end

    local function SawCommand(command)
        for _, seen in executed do
            if seen == command then
                return true
            end
        end

        return false
    end

    WorldView.SelectionTolerance = nil

    -- Resets the state the mod remembers from the previous frames.
    _G.IsKeyDown = function()
        return false
    end
    Mod.UpdateCtrlMoveClick()

    executed = {}
    _G.IsKeyDown = function(keyCode)
        return keyCode == KEY_CTRL
    end
    Mod.UpdateCtrlMoveClick()

    Test.Check(SawCommand("ui_SelectTolerance -1000"), "Ctrl makes the engine ignore units under the cursor")

    -- The game switches its ignore mode off whenever the cursor changes, which happens right
    -- before the click; while Ctrl is held that must not turn the mode off again.
    WorldView:EnableIgnoreMode(false)
    Test.Check(
        WorldView.SelectionTolerance == -1000,
        "The game cannot switch the ignore mode off while Ctrl is held"
    )

    _G.IsKeyDown = realIsKeyDown
    Mod.UpdateCtrlMoveClick()

    Test.Check(SawCommand("ui_CommandClickScale 1"), "Releasing Ctrl restores the game cursor behaviour")
    Test.Check(WorldView.SelectionTolerance ~= -1000, "Releasing Ctrl restores unit picking")

    _G.ConExecute = realConExecute

    -- The target priority is based on the role of the unit, not on the exact blueprint, so the
    -- selection shoots at every faction and tech level of that role.
    local fighterPriority = Mod.BuildTypePriority("xsa0303")
    Test.Check(fighterPriority ~= nil, "A Seraphim air superiority fighter has a role priority")
    Test.Check(
        fighterPriority and Contains(fighterPriority, "ASF * AIR"),
        "A fighter sets the priority to fighters, not to one blueprint"
    )
    Test.Check(
        fighterPriority and not Contains(fighterPriority, "xsa0303"),
        "The clicked blueprint itself does not outrank the role"
    )

    local antiAirPriority = Mod.BuildTypePriority("dslk004")
    Test.Check(
        antiAirPriority and Contains(antiAirPriority, "ANTIAIR * LAND"),
        "A mobile anti-air sets the priority to land anti-air of every faction and tech"
    )

    -- A power generator is economy, not a generic structure: units then shoot at buildings that
    -- explode and leave the rest alone.
    local energyPriority = Mod.BuildTypePriority("ueb1101")
    Test.Check(
        energyPriority
            == "{(ENERGYPRODUCTION * STRUCTURE - TECH1), ENERGYSTORAGE, MASSFABRICATION, ENERGYPRODUCTION * STRUCTURE}",
        "A power generator prioritizes economy buildings, not every structure"
    )

    local extractorPriority = Mod.BuildTypePriority("ueb1103")
    Test.Check(
        extractorPriority == "{MASSEXTRACTION * STRUCTURE, MASSEXTRACTION}",
        "A mass extractor sets its own priority instead of an economy one"
    )

    -- Middle click applies that priority to the selection and consumes the click.
    local realTemplate = _G.GetActiveBuildTemplate
    local realRollover = _G.GetRolloverInfo
    local realSetPriority = Actions.SetWeaponPriorities
    local appliedPriority = nil
    local appliedName = nil

    _G.GetActiveBuildTemplate = function()
        return nil
    end
    _G.GetRolloverInfo = function()
        return { blueprintId = "xsa0303" }
    end
    Actions.SetWeaponPriorities = function(priorities, name)
        appliedPriority = priorities
        appliedName = name
    end

    local middleHandled = WorldView:HandleEvent({
        Type = "ButtonPress",
        Modifiers = { Middle = true },
    })

    _G.GetActiveBuildTemplate = realTemplate
    _G.GetRolloverInfo = realRollover
    Actions.SetWeaponPriorities = realSetPriority

    Test.Check(middleHandled, "Middle Click is consumed by the mod")
    Test.Check(
        appliedPriority and Contains(appliedPriority, "ASF * AIR"),
        "Middle Click applies the role priority to the selection"
    )
    Test.Check(appliedName ~= nil and appliedName ~= "", "The applied priority has a readable name")

    -- An active build template keeps the middle click: the game rotates the template with it.
    local realTemplateWithValue = _G.GetActiveBuildTemplate
    local realRolloverWithUnit = _G.GetRolloverInfo
    local realSetTemplate = _G.SetActiveBuildTemplate
    local priorityWhileTemplate = nil

    _G.GetActiveBuildTemplate = function()
        return { { 0, 0, 0, 0 }, { 0, 0, 0, 0 } }
    end
    _G.GetRolloverInfo = function()
        return { blueprintId = "xsa0303" }
    end
    -- The game rotates the template through this call, the scenario only tracks the priority.
    _G.SetActiveBuildTemplate = function()
    end
    Actions.SetWeaponPriorities = function(priorities)
        priorityWhileTemplate = priorities
    end

    local templateHandled = WorldView:HandleEvent({
        Type = "ButtonPress",
        Modifiers = { Middle = true },
    })

    _G.GetActiveBuildTemplate = realTemplateWithValue
    _G.GetRolloverInfo = realRolloverWithUnit
    _G.SetActiveBuildTemplate = realSetTemplate
    Actions.SetWeaponPriorities = realSetPriority

    Test.Check(priorityWhileTemplate == nil, "An active build template keeps its middle click")
    Test.Check(not templateHandled, "The template middle click is not consumed by the mod")
end
