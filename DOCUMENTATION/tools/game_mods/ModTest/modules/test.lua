-- Runs inside a match started by DOCUMENTATION/tools/game_test.py, which reads the verdict from the log.
-- The functions are also the API of the scenarios in My_mods/<project>/tests/game: a scenario is a file
-- with a function Run(), it reads this module through import.

local NO_TARGET = "none"
local SIM_HELPER_UID = "modtest-sim-1"
local START_TICKS = 60
local MOUSE_SECONDS = 8
-- The game shows the position of a mouse message only for a moment, see run_game in game_test.py.
local MOUSE_STEP_SECONDS = 0.02
local MOUSE_MARGIN = 2
local END_MESSAGE = "ModTestEnd"

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
function WaitUntil(condition, seconds, step)
    local deadline = CurrentTime() + seconds
    while CurrentTime() < deadline do
        if condition() then
            return true
        end
        WaitSeconds(step or 0.5)
    end
    return condition()
end

--- The UI has no list of units, the only way is a selection that is put back at once. While the game
--- selects the commander at the start of a match, this selection comes back empty.
function UnitsOfCategory(category)
    while GameTick() <= START_TICKS do
        WaitSeconds(0.1)
    end
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

function GiveMass(amount)
    SimCallback({ Func = "ModTestGiveMass", Args = { army = GetFocusArmy(), amount = amount } })
end

--- Creates a wreck of the unit id near the commander, and unit starts to reclaim it. A wreck is a prop,
--- the UI cannot see it, so it stays on the sim side.
function ReclaimWreck(unit, id, dx, dz)
    SimCallback({ Func = "ModTestWreck",
        Args = { army = GetFocusArmy(), unit = unit:GetEntityId(), id = id, dx = dx, dz = dz } })
end

--- Queues a building near the commander and then a patrol, dx, dz and the patrol points are offsets from him.
function Build(unit, id, dx, dz, patrol)
    SimCallback({ Func = "ModTestBuild",
        Args = { army = GetFocusArmy(), unit = unit:GetEntityId(), id = id, dx = dx, dz = dz, patrol = patrol } })
end

--- Makes the armies allies of the player and of each other, and removes all other armies. Needs the
--- line "-- stand: ai", because /noAi leaves no other armies. givers produce the given amount per
--- second, so their storage overflows, the storage of takers always has room.
function SetupAllies(givers, takers, massPerSecond, energyPerSecond)
    SimCallback({ Func = "ModTestAllies", Args = { army = GetFocusArmy(), givers = givers, takers = takers,
        mass = massPerSecond, energy = energyPerSecond } })
end

--- game_test.py reads this line and posts a real key message to the game. The log gets to the disk with a
--- delay of a second or two, so a scenario waits for the effect. One letter, with Ctrl-, Alt- and Shift-
--- before it as in the key map. The key map sees them, IsKeyDown does not.
function PressKey(key)
    Step("PRESS " .. key)
end

--- Moves the cursor of the game over a place of the map near the commander with a real mouse message. It has
--- to be in the view. The height of a flying unit is no use here, the cursor points at the ground below it.
--- A mod reads GetMouseWorldPos, and GetMouseScreenPos can show the cursor of the system at the same moment.
function MoveMouseTo(position)
    local view = import("/lua/ui/game/worldview.lua").viewLeft
    local ground = GetArmyAvatars()[1]:GetPosition()[2]
    local point = view:Project(Vector(position[1], ground, position[3]))
    local x, y = math.floor(point.x), math.floor(point.y)
    Check(x > view.Left() and x < view.Right() and y > view.Top() and y < view.Bottom(), "the place is in the view")
    Step("MOUSE " .. x .. " " .. y)
    Check(WaitUntil(function()
        local mouse = GetMouseWorldPos()
        return math.abs(mouse[1] - position[1]) < MOUSE_MARGIN and math.abs(mouse[3] - position[3]) < MOUSE_MARGIN
    end, MOUSE_SECONDS, MOUSE_STEP_SECONDS), "the cursor came to the place")
end

--- A module of a mod keeps its state in locals, this reads one from a function that uses it.
function Upvalue(func, name)
    local index = 1
    while true do
        local found, value = debug.getupvalue(func, index)
        if found == nil then
            return nil
        end
        if found == name then
            return value
        end
        index = index + 1
    end
end

--- Keeps the lines a module writes to the log. The module table is the environment of its file, so the
--- name changes for that file only. A file that made LOG a local at its top cannot be watched this way.
function WatchLog(module)
    local lines = {}
    module.LOG = function(text)
        table.insert(lines, tostring(text))
        LOG(text)
    end
    return lines
end

function Logged(lines, text)
    for _, line in lines do
        if string.find(line, text, 1, true) then
            return true
        end
    end
    return false
end

function ForgetLog(lines)
    for index = table.getn(lines), 1, -1 do
        table.remove(lines, index)
    end
end

--- Counts the calls a module makes to a function of the game, the same way as WatchLog.
function CountCalls(module, name)
    local original = module[name]
    local counter = { calls = 0 }
    module[name] = function(...)
        counter.calls = counter.calls + 1
        return original(unpack(arg))
    end
    return counter
end

--- Seconds do not work for the order of events: a match started with /map changes its speed. A mod
--- that asks the game once per pass is a clock of its own.
function WaitCalls(counter, count)
    local target = counter.calls + count
    if not WaitUntil(function() return counter.calls >= target end, 5 + 2 * count) then
        Check(false, "the mod keeps making its calls")
    end
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

--- A client that joined a match of several clients plays its army until the host ends the match. If the
--- host never does, game_test.py gives up on this client.
local function WaitForHost()
    local ended = false
    import("/lua/ui/game/gamemain.lua").RegisterChatFunc(function() ended = true end, END_MESSAGE)
    while not ended do
        WaitSeconds(0.1)
    end
end

function Run(scenario, targetUid)
    Step("start scenario=" .. scenario)
    CheckActiveMods(targetUid)
    if scenario == "smoke" then
        WaitSeconds(3)
        Check(GameTick() > 0, "the match is running")
    elseif HasCommandLineArg("/joingame") then
        WaitForHost()
    else
        -- The auto lobby leaves the sim helper out of the match, see game_test.py.
        if not HasCommandLineArg("/hostgame") then
            SimCallback({ Func = "ModTestLogSimMods", Args = {} })
        end
        import("/mods/ModTestScenarios/" .. scenario .. ".lua").Run()
        if HasCommandLineArg("/hostgame") then
            SessionSendChatMessage({ Identifier = END_MESSAGE })
        end
    end
    if failures == 0 then
        Step("PASS")
    end
    Step("END")
    WaitSeconds(0.5)
    ExitApplication()
end
