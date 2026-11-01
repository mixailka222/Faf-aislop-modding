-- Runs inside a match started by DOCUMENTATION/tools/game_test.py, which reads the verdict from the log.
-- The functions are also the API of the scenarios in My_mods/<project>/tests/game: a scenario is a file
-- with a function Run(), it reads this module through import.

local NO_TARGET = "none"
local SIM_HELPER_UID = "modtest-sim-1"

local failures = 0

function Step(text)
    LOG("[MODTEST] " .. text)
end

function Check(condition, label)
    if condition then
        Step("OK   " .. label)
    else
        Step("FAIL " .. label)
        failures = failures + 1
    end
end

--- Returns the last result of condition. The time is real, as for the WaitSeconds of a mod.
function WaitUntil(condition, seconds)
    local deadline = CurrentTime() + seconds
    while CurrentTime() < deadline do
        if condition() then
            return true
        end
        WaitSeconds(0.5)
    end
    return condition()
end

--- The UI has no list of units, the only way is a selection that is put back at once.
function UnitsOfCategory(category)
    local saved = GetSelectedUnits() or {}
    UISelectionByCategory(category, false, false, false, false)
    local units = GetSelectedUnits() or {}
    SelectUnits(saved)
    return units
end

function FindById(units, id)
    for _, unit in units do
        if unit:GetUnitId() == id then
            return unit
        end
    end
end

--- Creates a unit near the commander, dx and dz are offsets from him. A patrol needs two points.
function Spawn(id, dx, dz, patrol)
    SimCallback({ Func = "ModTestSpawn", Args = { army = GetFocusArmy(), id = id, dx = dx, dz = dz, patrol = patrol } })
end

--- From the UI a reclaim order takes its target from the cursor, so the sim side gives it.
function Reclaim(unit, target)
    SimCallback({ Func = "ModTestReclaim", Args = { unit = unit:GetEntityId(), target = target:GetEntityId() } })
end

function TakeMass(amount)
    SimCallback({ Func = "ModTestTakeMass", Args = { army = GetFocusArmy(), amount = amount } })
end

local function CheckActiveMods(targetUid)
    local target = nil
    local simMods = {}
    for _, mod in __active_mods do
        if mod.uid == targetUid then
            target = mod
        end
        if not mod.ui_only and mod.uid ~= SIM_HELPER_UID then
            table.insert(simMods, mod.uid)
        end
    end
    Check(table.getn(simMods) == 0, "no sim mods besides the helper [" .. table.concat(simMods, " ") .. "]")
    if targetUid ~= NO_TARGET then
        Check(target ~= nil, "the tested mod is active")
        Check(target and target.ui_only, "the tested mod is a UI mod")
    end
end

function Run(scenario, targetUid)
    Step("start scenario=" .. scenario)
    CheckActiveMods(targetUid)
    if scenario == "smoke" then
        WaitSeconds(3)
        Check(GameTick() > 0, "the match is running")
    else
        SimCallback({ Func = "ModTestLogSimMods", Args = {} })
        import("/mods/ModTestScenarios/" .. scenario .. ".lua").Run()
    end
    if failures == 0 then
        Step("PASS")
    end
    Step("END")
    WaitSeconds(0.5)
    ExitApplication()
end
