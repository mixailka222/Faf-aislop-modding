-- With all rows shown, reclaim shows up in the row of its own and in own production: an engineer on a
-- wreck adds to both, and a second engineer adds to both again.
local Test = import("/mods/ModTest/modules/test.lua")
local Panel = import("/mods/ModTestScenarios/support/panel.lua")

local ENGINEER = "uel0105"
local SECOND_ENGINEER = "uel0208"
local WRECK = "uel0401"

function Run()
    local panel = Panel.State()
    Test.Check(panel ~= nil, "the state of the panel is readable")
    if not panel then
        return
    end
    local Sync = import("/mods/Overflow/modules/sync.lua")

    local function KeepRoom()
        local economy = GetEconomyTotals()
        if economy.stored.MASS > 300 then
            Test.TakeMass(economy.stored.MASS - 100)
        end
    end

    -- Waits for two published windows: the first one may have started before the change.
    local function NextResult()
        local tick = GameTick()
        local windows = 0
        local last = Sync.GetResult()
        while windows < 2 do
            KeepRoom()
            WaitSeconds(0.5)
            if Sync.GetResult() ~= last then
                last = Sync.GetResult()
                windows = windows + 1
            end
        end
        Test.Step("ticks of the two windows: " .. tostring(GameTick() - tick))
        return last
    end

    local function Report(name, result)
        Test.Step(name .. ": reclaim " .. tostring(result.massReclaim) .. ", own " .. tostring(result.massOwn) ..
            " | '" .. tostring(panel.labels.total:GetText()) .. "' '" .. tostring(panel.labels.mOwn:GetText()) .. "'")
    end

    Panel.WaitForNumbers(panel)
    Panel.ShowAllRows(panel)
    Test.Spawn(ENGINEER, 8, 0)
    Test.Spawn(SECOND_ENGINEER, -8, 0)
    WaitSeconds(2)
    local engineers = Test.UnitsOfCategory("ENGINEER")
    local first = Test.FindById(engineers, ENGINEER)
    local second = Test.FindById(engineers, SECOND_ENGINEER)
    Test.Check(first and second, "the engineers exist")
    if not (first and second) then
        return
    end

    local quiet = NextResult()
    Report("no reclaim", quiet)
    Test.Check(quiet.massReclaim == 0, "no reclaim before the order")

    Test.ReclaimWreck(first, WRECK, 14, 0)
    local one = NextResult()
    Report("one engineer", one)
    Test.Check(one.massReclaim > quiet.massReclaim, "reclaim grows with one engineer")
    Test.Check(one.massOwn >= quiet.massOwn + 0.9 * one.massReclaim, "own production grows by the reclaim")
    Test.Check(string.find(panel.labels.total:GetText(), "reclaim E", 1, true) ~= nil,
        "the row of reclaim has its text")

    Test.ReclaimWreck(second, WRECK, -14, 0)
    local two = NextResult()
    Report("two engineers", two)
    Test.Check(two.massReclaim > one.massReclaim, "reclaim grows with the second engineer")
    Test.Check(two.massOwn > one.massOwn, "own production grows with it")
end
