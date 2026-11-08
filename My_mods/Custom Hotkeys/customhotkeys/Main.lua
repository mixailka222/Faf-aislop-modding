Version = "1.1.0"

ReUI.Require
{
    "ReUI.Core >= 1.0.0",
    "ReUI.Actions >= 1.3.0",
}

--- Squared horizontal distance between two positions, height is ignored.
--- @param first Vector
--- @param second Vector
--- @return number
local function DistanceSquared(first, second)
    local dx = first[1] - second[1]
    local dz = first[3] - second[3]
    return dx * dx + dz * dz
end

--- Collects every unit that matches the given category expression.
---
--- ASE (Advanced Selection Extension) replaces OnSelectionChanged: it filters
--- the new selection and, when the filter removed something (locked units for
--- example), re-applies the filtered set one frame later. That deferred call
--- would overwrite the single unit we pick below, which is why the temporary
--- "select everything" has to stay invisible for ASE. The game gives us
--- selection.lua / Hidden() for exactly that: ASE's hook checks IsHidden() and
--- returns early, so no filter and no deferred re-selection is scheduled.
--- @param expression string category expression for UI_SelectByCategory
--- @return UserUnit[]?
local function CollectMatchingUnits(expression)
    local units

    local function collect()
        ConExecute("UI_SelectByCategory " .. expression)
        units = GetSelectedUnits()
    end

    -- rawget: a plain read of a missing module field reaches the strict _G and fails.
    local Hidden = rawget(import("/lua/ui/game/selection.lua"), "Hidden")
    if Hidden then
        Hidden(collect)
    else
        WARN("Custom Hotkeys: selection.lua has no Hidden, ASE may undo the selection")
        collect()
    end

    return units
end

--- ASE is optional, so its lock list is asked for once and only if its file
--- exists: import of a missing file writes an error and a stack to the log even
--- under pcall. The field is read plainly, not with rawget: if ASE imported the
--- file lazily, only a field read loads it.
--- Shared state works because FAF caches imported modules per path, and ASE
--- itself reaches the same file as "/mods/ASE/modules/Lock.lua".
local ASE_LOCK_FILE = "/mods/ASE/modules/Lock.lua"
local AseIsLocked
local aseLocksProbed = false

--- @param unit UserUnit
--- @return boolean
local function IsLocked(unit)
    if not aseLocksProbed then
        aseLocksProbed = true

        if DiskGetFileInfo(ASE_LOCK_FILE) then
            local ok, isLocked = pcall(function()
                return import(ASE_LOCK_FILE).IsLocked
            end)
            if ok then
                AseIsLocked = isLocked
            else
                WARN("Custom Hotkeys: ASE locks are not available: " .. tostring(isLocked))
            end
        end
    end

    return AseIsLocked ~= nil and AseIsLocked(unit)
end

--- Selects everything the category expression matches, removes the excluded
--- categories and then keeps only the unit closest to the mouse cursor.
--- Units locked by ASE are skipped, otherwise ASE would remove our pick again
--- and the player would end up with an empty selection.
--- @param expression string category expression for UI_SelectByCategory
--- @param excluded EntityCategory categories that must not stay selected
local function SelectNearest(expression, excluded)
    local candidates = EntityCategoryFilterOut(excluded, CollectMatchingUnits(expression) or {})
    if table.empty(candidates) then
        SelectUnits(nil)
        return
    end

    local mousePosition = GetMouseWorldPos()
    local nearestCandidate
    local nearestDistance

    for _, candidate in candidates do
        if not IsLocked(candidate) then
            local distance = DistanceSquared(mousePosition, candidate:GetPosition())
            if not nearestDistance or distance < nearestDistance then
                nearestCandidate = candidate
                nearestDistance = distance
            end
        end
    end

    if nearestCandidate then
        SelectUnits({ nearestCandidate })
    else
        SelectUnits(nil)
    end
end

--- @param unit UserUnit
--- @param selection UserUnit[]
--- @return boolean
local function IsSelected(unit, selection)
    for _, selected in selection do
        if selected == unit then
            return true
        end
    end

    return false
end

--- Adds the nearest matching unit that is not selected yet and keeps the
--- current selection, so pressing the hotkey again walks outwards from the
--- cursor instead of re-selecting the same unit. The engine's own
--- "UI_SelectByCategory +add +nearest" cannot do this: it seeds the result
--- with the current selection and then adds the nearest match again, which is
--- already selected, so a second press changes nothing.
--- @param expression string category expression for UI_SelectByCategory
--- @param excluded EntityCategory categories that must not be added
local function AddNearest(expression, excluded)
    local selected = GetSelectedUnits() or {}
    local candidates = EntityCategoryFilterOut(excluded, CollectMatchingUnits(expression) or {})

    local mousePosition = GetMouseWorldPos()
    local nearestCandidate
    local nearestDistance

    for _, candidate in candidates do
        if not IsLocked(candidate) and not IsSelected(candidate, selected) then
            local distance = DistanceSquared(mousePosition, candidate:GetPosition())
            if not nearestDistance or distance < nearestDistance then
                nearestCandidate = candidate
                nearestDistance = distance
            end
        end
    end

    if not nearestCandidate then
        return
    end

    local combined = {}
    for _, unit in selected do
        table.insert(combined, unit)
    end
    table.insert(combined, nearestCandidate)

    SelectUnits(combined)
end

--- Drops the factories that a hotkey must not put into the selection: the ones
--- ASE locked, so its own filter would take them out again.
--- @param factories UserUnit[]
--- @return UserUnit[]
local function SelectableFactories(factories)
    local units = {}
    for _, factory in factories do
        if not IsLocked(factory) then
            table.insert(units, factory)
        end
    end

    return units
end

--- Selects every factory of the player that is not producing anything: land,
--- air and navy alike, all tiers, in one selection.
---
--- The engine answers "which factories are free" with GetIdleFactories(), the
--- same list the army tab and the vanilla idle factory hotkey are built on. A
--- factory that builds, upgrades or waits for its roll-off is not in it, so no
--- extra check of the production queue is needed.
---
--- Quantum gates and orbital systems are dropped the way the army tab drops
--- them: both are factories for the engine, but neither is a production hotkey
--- target.
---
--- A factory that finished its queue is still in the list until the order is
--- cleared, so the factories that hold a build order are dropped as well: those
--- are busy, and a free factory is not one of them.
--- With nothing free the selection is left untouched, so a stray press does
--- not throw away what the player has selected.
local function SelectFreeFactories()
    local idleFactories = GetIdleFactories()
    if not idleFactories then
        return
    end

    local free = EntityCategoryFilterDown(
        categories.ALLUNITS - categories.GATE - categories.ORBITALSYSTEM,
        idleFactories
    )

    local units = SelectableFactories(free)
    if table.empty(units) then
        return
    end

    -- Shift extends the selection instead of replacing it, the same way the
    -- nearest unit hotkeys above do.
    if IsKeyDown("Shift") then
        for _, unit in GetSelectedUnits() or {} do
            if not IsSelected(unit, units) then
                table.insert(units, unit)
            end
        end
    end

    SelectUnits(units)
end

--- True when every selected unit belongs to `included` and none belongs to
--- `excluded`. An empty selection counts as a match: there is nothing to
--- protect, so the caller may pick a unit freely.
--- @param selection UserUnit[]?
--- @param included EntityCategory
--- @param excluded EntityCategory
--- @return boolean
local function UnitsBelongTo(selection, included, excluded)
    if not selection or table.empty(selection) then
        return true
    end

    for _, unit in selection do
        if not EntityCategoryContains(included, unit) or EntityCategoryContains(excluded, unit) then
            return false
        end
    end

    return true
end

--- True when at least one selected unit can build something: an engineer,
--- commander or Megalith (the same test hotbuild itself uses) or a factory.
--- @param selection UserUnit[]?
--- @return boolean
local function SelectionCanBuild(selection)
    if not selection or table.empty(selection) then
        return false
    end

    local engineers = categories.ENGINEER - categories.STRUCTURE + categories.xrl0403
    if not table.empty(EntityCategoryFilterDown(engineers, selection)) then
        return true
    end

    return not table.empty(EntityCategoryFilterDown(categories.FACTORY, selection))
end

--- Matches when nothing in the selection can build, so running Hotbuild would
--- do nothing. The press is then free to select the nearest unit instead.
--- Empty selection counts as "cannot build".
--- @param selection UserUnit[]?
--- @return boolean
local function SelectionCannotBuild(selection)
    return not SelectionCanBuild(selection)
end

--- Same as UnitsBelongTo but only while Shift is held: the press may then
--- extend the selection instead of replacing it.
--- @param included EntityCategory
--- @param excluded EntityCategory
--- @return fun(selection: UserUnit[]?): boolean
local function ShiftSelectionIn(included, excluded)
    return function(selection)
        return IsKeyDown("Shift") and UnitsBelongTo(selection, included, excluded)
    end
end

function Main()
    ReUI.Core.OnPostCreateUI(function()
        local CategoryMatcher = ReUI.Actions.CategoryMatcher
        local CategoryAction = ReUI.Actions.CategoryAction
        local Hotbuild = import("/lua/keymap/hotbuild.lua")

        local function AlwaysMatches()
            return true
        end

        -- Shift and Alt have to be declared here, not detected inside the action:
        -- a key press is looked up in the engine key map as an exact combination.
        -- Without these flags only the bare key is bound, so Shift+key and Alt+key
        -- hit nothing and the action never runs. With them ReUI.Actions hooks
        -- keymapper.GenerateHotbuildModifiers and adds "Shift-<key>" and
        -- "Alt-<key>" bindings for whatever key the player assigned, after which
        -- the action runs and hotbuild itself sees IsKeyDown("Shift") / ("MENU").
        local fighterMatcher = CategoryMatcher("Select nearest fighter / build shields")
        fighterMatcher:Modifiers { shift = true, alt = true }

        -- A fighter is any air unit with ANTIAIR: T1 interceptor, T2
        -- fighter/bombers and the Aeon combat fighter, T3 air superiority
        -- fighter. Experimentals (Czar, Soul Ripper) are left out.
        local fighterIncluded = categories.AIR * categories.ANTIAIR
        local fighterExcluded = categories.EXPERIMENTAL
        local AddsNearestFighter = ShiftSelectionIn(fighterIncluded, fighterExcluded)

        -- Nothing in the selection can build: nearest fighter. Anything that
        -- can build: Hotbuild "Shields".
        fighterMatcher
        {
            -- Shift with a fighter selection: add the next nearest one instead
            -- of running the build command, which a fighter cannot execute.
            CategoryAction()
                :Match(AddsNearestFighter)
                :Action(function()
                    AddNearest("AIR ANTIAIR", fighterExcluded)
                end),
            -- Bare press while nothing can build (including "a fighter, or a
            -- bomber of the other hotkey, is selected") selects the nearest one
            -- instead of doing nothing.
            CategoryAction()
                :Match(SelectionCannotBuild)
                :Action(function()
                    SelectNearest("AIR ANTIAIR", fighterExcluded)
                end),
            CategoryAction()
                :Match(AlwaysMatches)
                :Action(function()
                    Hotbuild.buildAction("Shields")
                end),
        }

        local bomberMatcher = CategoryMatcher("Select nearest bomber / build TMD")
        bomberMatcher:Modifiers { shift = true, alt = true }

        local bomberIncluded = categories.AIR * categories.BOMBER
            + categories.AIR * categories.ANTIAIR * categories.TECH2
        local bomberExcluded = categories.ANTINAVY + categories.EXPERIMENTAL
        local AddsNearestBomber = ShiftSelectionIn(bomberIncluded, bomberExcluded)

        -- Nothing in the selection can build: nearest bomber (T1 attack bomber,
        -- T2 fighter/bomber, T3 strategic bomber; torpedo bombers are excluded).
        -- Anything that can build: Hotbuild "TMD".
        bomberMatcher
        {
            -- Shift with a bomber selection: add the next nearest one.
            CategoryAction()
                :Match(AddsNearestBomber)
                :Action(function()
                    AddNearest("AIR BOMBER, AIR ANTIAIR TECH2", bomberExcluded)
                end),
            -- Bare press while nothing can build re-selects the nearest bomber,
            -- so a selected fighter does not swallow this hotkey.
            CategoryAction()
                :Match(SelectionCannotBuild)
                :Action(function()
                    SelectNearest("AIR BOMBER, AIR ANTIAIR TECH2", bomberExcluded)
                end),
            CategoryAction()
                :Match(AlwaysMatches)
                :Action(function()
                    Hotbuild.buildAction("TMD")
                end),
        }

        -- The last branch of AKA's own hotkey "Select nearest air scout / build
        -- sensors" always runs Hotbuild "Sensors", which only does something for
        -- engineers and factories, so with a fighter selected the press does
        -- nothing. AKA is a third-party mod and is not patched here, so the same
        -- hotkey is offered with the rule above.
        -- The description differs on purpose: ReUI.Actions keeps actions by
        -- name, and two equal names would overwrite each other in whatever
        -- order the mods happen to load.
        local scoutMatcher = CategoryMatcher("Select nearest air scout / build sensors (Custom)")
        scoutMatcher:Modifiers { shift = true, alt = true }

        -- A scout is any air unit with INTELLIGENCE: T1 air scouts and T3 spy
        -- planes, all four factions.
        local scoutIncluded = categories.AIR * categories.INTELLIGENCE
        local scoutExcluded = categories.EXPERIMENTAL
        local AddsNearestScout = ShiftSelectionIn(scoutIncluded, scoutExcluded)

        scoutMatcher
        {
            -- Shift with a scout selection: add the next nearest one, the same
            -- way the fighter and bomber hotkeys do.
            CategoryAction()
                :Match(AddsNearestScout)
                :Action(function()
                    AddNearest("AIR INTELLIGENCE", scoutExcluded)
                end),
            -- Nothing in the selection can build: nearest air scout or spy
            -- plane (AIR INTELLIGENCE, all four factions).
            CategoryAction()
                :Match(SelectionCannotBuild)
                :Action(function()
                    SelectNearest("AIR INTELLIGENCE", scoutExcluded)
                end),
            CategoryAction()
                :Match(AlwaysMatches)
                :Action(function()
                    Hotbuild.buildAction("Sensors")
                end),
        }

        -- Every free factory at once. No modifiers are declared: the result does
        -- not depend on what is selected, so a bare key is enough, and Shift is
        -- read inside the action to extend the selection.
        local factoriesMatcher = CategoryMatcher("Select all free factories")

        factoriesMatcher
        {
            CategoryAction()
                :Match(AlwaysMatches)
                :Action(function()
                    SelectFreeFactories()
                end),
        }
    end)
end
