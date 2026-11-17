Version = "1.3.0"

local MOD_NAME = "Somefeatures"

local ReUIAvailable = rawget(_G, "ReUI") ~= nil

if ReUIAvailable then
    ReUI.Require
    {
        "ReUI.Core >= 1.5.0",
        "ReUI.Options >= 2.0.0",
    }
end

---ReUI fills `ReUI.Options.Mods` only after the `Main` of the options module has run,
---so while this file is imported the table is still missing. Options are therefore read
---lazily, and the first read is what makes ReUI load `Options.lua` and register the mod
---on its options page.
---@type table?
local cachedOptions

local warnedNoOptions = false

---@return table?
local function GetOptions()
    if cachedOptions then
        return cachedOptions
    end

    if not ReUIAvailable then
        return nil
    end

    local ok, options = pcall(function()
        ---@diagnostic disable-next-line: undefined-field
        return ReUI.Options.Mods[MOD_NAME]
    end)

    if not ok or not options then
        if not warnedNoOptions then
            warnedNoOptions = true
            local reason = ok and "the mod options are missing" or tostring(options)
            WARN("Some features: " .. reason .. ", all features stay disabled")
        end
        return nil
    end

    cachedOptions = options
    return options
end

---The option is read on every use, so a checkbox takes effect without restarting the game.
---@param name string
---@return boolean
local function IsEnabled(name)
    local options = GetOptions()
    local option = options and options[name]
    return option ~= nil and option:Get()
end

---Buildings that blow up when they are destroyed. A unit that is told to hit power buildings
---should ignore everything that cannot explode, which is what the Volatile preset of Advanced
---Target Priorities Tweaked does.
local ENERGY_ECONOMY = {
    "(ENERGYPRODUCTION * STRUCTURE - TECH1)",
    "ENERGYSTORAGE",
    "MASSFABRICATION",
    "ENERGYPRODUCTION * STRUCTURE",
}

---Roles a structure can be given a target priority for, from the most specific one to the most
---general one. A role is a blueprint category, so the priority covers every faction and tech
---level: a power generator of any faction is a power generator.
local STRUCTURE_ROLES = {
    { category = "SHIELD", name = "Shields" },
    { category = "ANTIMISSILE", name = "Missile defense" },
    { category = "ENERGYPRODUCTION", name = "Energy economy", expressions = ENERGY_ECONOMY },
    { category = "ENERGYSTORAGE", name = "Energy economy", expressions = ENERGY_ECONOMY },
    { category = "MASSFABRICATION", name = "Energy economy", expressions = ENERGY_ECONOMY },
    { category = "MASSSTORAGE", name = "Mass storage" },
    { category = "MASSEXTRACTION", name = "Mass extractors" },
    { category = "ANTIAIR", name = "Static anti-air" },
    { category = "ARTILLERY", name = "Static artillery" },
    { category = "DIRECTFIRE", name = "Point defense" },
    { category = "FACTORY", name = "Factories" },
    { category = "INTELLIGENCE", name = "Intelligence" },
    { category = "ENGINEERSTATION", name = "Engineer stations" },
    { category = "SILO", name = "Missile silos" },
    { category = "DEFENSE", name = "Defenses" },
}

---Roles a mobile unit can be given a target priority for, from the most specific one to the most
---general one. Mobile anti-air of any tech and faction is anti-air, a fighter of any faction is
---a fighter.
local MOBILE_ROLES = {
    { category = "ASF", name = "Air superiority fighters" },
    { category = "BOMBER", name = "Bombers" },
    { category = "GROUNDATTACK", name = "Ground attack aircraft" },
    { category = "TRANSPORTATION", name = "Transports" },
    { category = "ANTIAIR", name = "Anti-air" },
    { category = "SHIELD", name = "Mobile shields", expressions = { "SHIELD * MOBILE", "SHIELD" } },
    { category = "ANTINAVY", name = "Anti-navy" },
    { category = "SUBMERSIBLE", name = "Submarines" },
    { category = "INTELLIGENCE", name = "Intelligence" },
    { category = "ARTILLERY", name = "Artillery" },
    { category = "INDIRECTFIRE", name = "Indirect fire" },
    { category = "DIRECTFIRE", name = "Direct fire" },
    { category = "SCOUT", name = "Scouts" },
    { category = "ENGINEER", name = "Engineers" },
    { category = "EXPERIMENTAL", name = "Experimentals" },
}

---Layers a mobile unit can be limited to, so a land tank does not chase ships.
local LAYERS = {
    { category = "AIR", name = "Air" },
    { category = "LAND", name = "Land" },
    { category = "NAVAL", name = "Naval" },
}

---@param categoriesHash table<string, boolean>
---@param definitions table
---@return table? definition
local function FindFirst(categoriesHash, definitions)
    for _, definition in definitions do
        if categoriesHash[definition.category] then
            return definition
        end
    end

    return nil
end

---Builds a target priority from the role of a blueprint, so the selection shoots at every unit
---of that role instead of the exact unit that was clicked. The exact blueprint is left out on
---purpose: it would outrank the whole role, which is what this feature exists to avoid.
---@param bpId string blueprint id of the unit under the cursor
---@return string? priorities category expression for `SetWeaponPriorities`
---@return string? name text of the priority
function BuildTypePriority(bpId)
    local bp = __blueprints[bpId]
    if not bp then
        return nil, nil
    end

    local categoriesHash = bp.CategoriesHash
    local isStructure = categoriesHash.STRUCTURE == true
    local role = FindFirst(categoriesHash, isStructure and STRUCTURE_ROLES or MOBILE_ROLES)

    if not role then
        return nil, nil
    end

    local priorities = role.expressions
    if not priorities then
        -- A building has no land, air or naval layer, so its role is limited to structures.
        -- A mobile role is limited to its own layer, otherwise land tanks would chase ships.
        local layer
        if isStructure then
            layer = "STRUCTURE"
        else
            local found = FindFirst(categoriesHash, LAYERS)
            layer = found and found.category
        end

        priorities = {}
        if layer then
            table.insert(priorities, string.format("%s * %s", role.category, layer))
        end
        table.insert(priorities, role.category)
    end

    return string.format("{%s}", table.concat(priorities, ", ")), role.name
end

---Applies the target priority of the role of the unit under the cursor to the current selection.
---@return boolean handled
function SetTypePriority()
    local info = GetRolloverInfo()
    if not info or info.blueprintId == "unknown" then
        return false
    end

    local priorities, name = BuildTypePriority(info.blueprintId)
    if not priorities then
        return false
    end

    import("/lua/keymap/misckeyactions.lua").SetWeaponPriorities(priorities, name, false)
    return true
end

---Virtual key code of Ctrl, as in `/lua/ui/controls/worldview.lua`.
local KEY_CTRL = 17

---Frames between repeated writes of the ignore value, in case the game restores it itself.
local REASSERT_FRAMES = 30

---Whether the game ignore mode was switched on by this mod.
local ignoreModeActive = false

local framesSinceAssert = 0

---Frames to wait for the game world view after the interface starts, about ten seconds.
local VIEW_WARN_FRAMES = 600

---Frames the world view was missing, and whether its absence was already reported.
local framesWithoutView = 0
local warnedNoView = false

---@return WorldView|false|nil worldView
local function GetWorldView()
    local ok, gameView = pcall(import, "/lua/ui/game/worldview.lua")
    -- `import` returns an empty module when the file fails to compile, so the field is checked
    -- through `rawget` and a missing view is reported instead of silently doing nothing.
    local view = ok and gameView and rawget(gameView, "viewLeft")

    if not view then
        framesWithoutView = framesWithoutView + 1
        if framesWithoutView > VIEW_WARN_FRAMES and not warnedNoView then
            warnedNoView = true
            WARN("Some features: the game world view is unavailable, Ctrl+Right Click stays disabled")
        end
        return nil
    end

    framesWithoutView = 0
    return view
end

---Keeps the game ignore mode on while Ctrl is held. In that mode the engine picks no unit under
---the cursor, so a right click on an enemy unit becomes a Move instead of an Attack: the units
---fly to the point and shoot at everything on the way. The mode has to be on before the click,
---because the engine reads it while it processes the click itself.
function UpdateCtrlMoveClick()
    local view = GetWorldView()
    if not view then
        return
    end

    local wantIgnored = IsEnabled("ctrlRightClickMove") and IsKeyDown(KEY_CTRL)

    if not wantIgnored then
        if ignoreModeActive then
            ignoreModeActive = false
            framesSinceAssert = 0
            view:EnableIgnoreMode(false)
        end
        return
    end

    framesSinceAssert = framesSinceAssert + 1
    if not ignoreModeActive or framesSinceAssert >= REASSERT_FRAMES then
        ignoreModeActive = true
        framesSinceAssert = 0
        view:EnableIgnoreMode(true)
    end
end

local clickThreadStarted = false

local function StartCtrlMoveClickThread()
    if clickThreadStarted then
        return
    end

    clickThreadStarted = true

    ForkThread(function()
        while true do
            UpdateCtrlMoveClick()
            WaitFrames(1)
        end
    end)
end

local function HookSelection()
    ReUI.Core.Hook("/lua/ui/game/gamemain.lua", "DeselectSelens", function(oldFunction)
        return function(selection)
            if IsEnabled("engineerSelection") and IsKeyDown("shift") and IsKeyDown("menu") then
                local filtered = EntityCategoryFilterDown(
                    categories.ENGINEER + categories.COMMAND + categories.SUBCOMMANDER,
                    selection
                )
                -- An empty or complete result keeps the game's own behaviour: the selection is
                -- never cleared just because nothing matched.
                if table.getn(filtered) == 0 or table.getn(filtered) == table.getn(selection) then
                    return selection, false
                end
                return filtered, true
            end

            return oldFunction(selection)
        end
    end)
end

local function HookWorldView()
    ReUI.Core.Hook("/lua/ui/controls/worldview.lua", "WorldView", function(WorldView)
        local oldHandleEvent = WorldView.HandleEvent
        local oldEnableIgnoreMode = WorldView.EnableIgnoreMode

        return Class(WorldView)
        {
            ---The game turns its own ignore mode off every time the cursor changes, for example
            ---when it hovers an enemy unit, so the engine would pick that unit again and turn the
            ---right click into an Attack. While Ctrl is held the mode has to stay on.
            EnableIgnoreMode = function(self, enabled)
                if enabled or (IsEnabled("ctrlRightClickMove") and IsKeyDown(KEY_CTRL)) then
                    oldEnableIgnoreMode(self, true)
                else
                    oldEnableIgnoreMode(self, false)
                end
            end,

            HandleEvent = function(self, event)
                local result = oldHandleEvent(self, event)

                if event.Type ~= "ButtonPress" then
                    return result
                end

                -- Middle click gives the selection the weapon priority of the unit role under
                -- the cursor. An active build template owns the middle click, so the game's
                -- template rotation wins and nothing is changed here.
                if event.Modifiers.Middle and IsEnabled("middleClickPriority") then
                    local template = GetActiveBuildTemplate()
                    local info = GetRolloverInfo()
                    if (not template or table.empty(template)) and info and info.blueprintId ~= "unknown" then
                        if SetTypePriority() then
                            return true
                        end
                    end
                end

                return result
            end,
        }
    end)
end

function Main(isReplay)
    if not ReUIAvailable then
        WARN("Some features: ReUI is not loaded, all features are disabled")
        return
    end

    -- Also registers the mod on the ReUI options page.
    GetOptions()

    HookSelection()
    HookWorldView()
    StartCtrlMoveClickThread()
end
