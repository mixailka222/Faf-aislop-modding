-- stand: players 2

-- A real match of two clients on one team, without the sim helper. The second client is the giver: its
-- commander keeps producing while its storage is full. The commander of the host starts an enhancement
-- that costs more than it produces, so its storage gets room for what the giver overflows.
local Test = import("/mods/ModTest/modules/test.lua")

local GIVER = 2
local CLIENTS = 2
-- 210 energy and 8 mass per second, far above the 20 and 1 a commander produces.
local ENHANCEMENT = "AdvancedEngineering"
local NUMBERS_SECONDS = 40

local function Rate(label)
    local _, _, number = string.find(label:GetText() or "", ": (%d+%.?%d*) ")
    return tonumber(number) or 0
end

local function Rows(panel)
    return "'" .. panel.labels.eOverflow:GetText() .. "', '" .. panel.labels.eGo:GetText() .. "'"
end

function Run()
    local Ui = import("/mods/Overflow/modules/ui.lua")
    local Sync = import("/mods/Overflow/modules/sync.lua")
    local panel = Test.Upvalue(Ui.CreatePanel, "G")
    Test.Check(panel ~= nil, "the state of the panel is readable")
    if not panel then
        return
    end

    Test.Check(SessionIsMultiplayer(), "the match is multiplayer")
    Test.Check(table.getsize(GetSessionClients()) == CLIENTS, "two clients play the match")
    Test.Check(IsAlly(GetFocusArmy(), GIVER), "the army of the other client is an ally")
    local exists = Test.WaitUntil(function() return panel.win ~= nil end, 5)
    Test.Check(exists, "the panel exists")
    if not exists then
        return
    end

    -- Both storages are full, nothing can go from one client to the other.
    Test.Check(Test.WaitUntil(function() return Sync.GetResult() ~= nil end, NUMBERS_SECONDS), "the first numbers came")
    WaitSeconds(0.5)
    Test.Step("rows while the storage is full: " .. Rows(panel))
    Test.Check(Rate(panel.labels.eOverflow) == 0, "E ally overflow is 0 while the storage is full")

    local commander = Test.UnitsOfCategory("COMMAND")[1]
    SelectUnits({ commander })
    -- The build panel fills these fields when a player opens its enhancement tab, and its queue reads them.
    local enhancement = commander:GetBlueprint().Enhancements[ENHANCEMENT]
    enhancement.ID = ENHANCEMENT
    enhancement.UnitID = commander:GetBlueprint().BlueprintId
    IssueCommand("UNITCOMMAND_Script", { TaskName = "EnhanceTask", Enhancement = ENHANCEMENT }, false)

    local arrived = Test.WaitUntil(function() return Rate(panel.labels.eOverflow) > 0 end, NUMBERS_SECONDS)
    Test.Step("rows while the storage has room: " .. Rows(panel))
    Test.Step("income per second: " .. tostring(GetEconomyTotals().income.ENERGY * GetSimTicksPerSecond()))
    Test.Check(arrived, "E ally overflow is above 0 while the storage has room")
end
