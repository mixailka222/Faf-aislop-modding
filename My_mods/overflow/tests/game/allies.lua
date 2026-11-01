-- stand: ai
-- stand: expect OverflowSync: GUARD M

-- A match with two allies: one produces more than its storage holds, the other has room for it. The panel
-- shows its numbers, shows the mass overflow while the storage of the player has room, also once the total
-- income of the player is far above the size of the storage, and shows 0 once that storage is full.
local Test = import("/mods/ModTest/modules/test.lua")

local GIVER = 2
local TAKER = 3
local GIVER_MASS = 80
local GIVER_ENERGY = 500
local FIRST_NUMBERS_SECONDS = 15
local FULL_STORAGE_SECONDS = 6
local LATE_INCOME_RATIO = 1.5
local FULL_ROUNDS = 2
local ROWS_PRESET = "Все строки"

local function Label(panel, row)
    return panel.labels[row]:GetText() or ""
end

local function HasNumber(text, caption, unit)
    return string.find(text, "^" .. caption .. ": %d+%.?%d* " .. unit .. "/s$") ~= nil
end

function Run()
    local Ui = import("/mods/Overflow/modules/ui.lua")
    local Sync = import("/mods/Overflow/modules/sync.lua")
    local panel = Test.Upvalue(Ui.CreatePanel, "G")
    Test.Check(panel ~= nil, "the state of the panel is readable")
    if not panel then
        return
    end

    WaitSeconds(1)
    Test.SetupAllies({ GIVER }, { TAKER }, GIVER_MASS, GIVER_ENERGY)
    WaitSeconds(1)
    Test.Check(IsAlly(GetFocusArmy(), GIVER) and IsAlly(GetFocusArmy(), TAKER), "the armies are allies of the player")

    Test.Check(Test.WaitUntil(function() return panel.win ~= nil end, 5), "the panel exists")
    Test.Check(Test.WaitUntil(function() return Sync.GetResult() ~= nil end, 30), "the first numbers came")
    Test.Step("game time of the first numbers: " .. tostring(GetGameTimeSeconds()))
    WaitSeconds(0.5)
    Test.Step("rows: '" .. Label(panel, "eOverflow") .. "', '" .. Label(panel, "eGo") .. "'")
    Test.Check(GetGameTimeSeconds() <= FIRST_NUMBERS_SECONDS, "the numbers came within 15 seconds of the match")
    Test.Check(HasNumber(Label(panel, "eOverflow"), "E ally overflow", "E"), "the row E ally overflow has a number")
    Test.Check(HasNumber(Label(panel, "eGo"), "E to allies", "E"), "the row E to allies has a number")
    Test.Check(not panel.labels.eOverflow:IsHidden() and not panel.labels.eGo:IsHidden(), "both default rows are shown")
    Test.Check(panel.labels.mOverflow:IsHidden(), "the mass rows are hidden by default")

    UMT.Options.Mods["Overflow"].preset:Set(ROWS_PRESET)

    local function Counters(army)
        return Test.Upvalue(Sync.Reset, "lastRaw")[army]
    end

    -- Room in the storage: the mass is taken away faster than the allies bring it.
    local function TakeAwayMass()
        local economy = GetEconomyTotals()
        if economy.stored.MASS > 300 then
            Test.TakeMass(economy.stored.MASS - 200)
        end
    end

    local seen = false
    local late = false
    local deadline = CurrentTime() + 30
    while CurrentTime() < deadline and not late do
        TakeAwayMass()
        local result = Sync.GetResult()
        local own = Counters(GetFocusArmy())
        if result.ok and result.massIncoming > 0 then
            seen = true
            if own and own.emin > LATE_INCOME_RATIO * own.mmax then
                late = true
                Test.Step("late: income total " .. tostring(own.emin) .. ", storage " .. tostring(own.mmax) ..
                    ", M ally overflow " .. tostring(result.massIncoming))
            end
        end
        WaitSeconds(0.5)
    end
    Test.Check(seen, "M ally overflow is above 0 while the storage has room")
    Test.Check(late, "M ally overflow stays above 0 once the total income is far above the storage")
    WaitSeconds(0.5)
    Test.Step("row: '" .. Label(panel, "mOverflow") .. "'")
    Test.Check(HasNumber(Label(panel, "mOverflow"), "M ally overflow", "M"), "the row M ally overflow has a number")
    Test.Check(not panel.labels.mOverflow:IsHidden(), "the preset shows the mass rows")

    local taker = Counters(TAKER)
    Test.Step("taker: mass " .. tostring(taker.mstore) .. " of " .. tostring(taker.mmax))

    -- The storage of the player gets full while the other ally still takes what the giver produces.
    for round = 1, FULL_ROUNDS do
        Test.GiveMass(GetEconomyTotals().maxStorage.MASS)
        local fullAt = GetGameTimeSeconds()
        local zero = Test.WaitUntil(function() return Sync.GetResult().massIncoming == 0 end, 25)
        local took = GetGameTimeSeconds() - fullAt
        Test.Step("round " .. round .. ": seconds of game time to 0 after the storage got full: " .. tostring(took))
        Test.Check(zero, "M ally overflow goes to 0 with a full storage")
        Test.Check(took <= FULL_STORAGE_SECONDS, "it takes 6 seconds or less")
        WaitSeconds(0.5)
        Test.Step("row: '" .. Label(panel, "mOverflow") .. "'")
        if round < FULL_ROUNDS then
            local back = CurrentTime() + 12
            while CurrentTime() < back and Sync.GetResult().massIncoming == 0 do
                TakeAwayMass()
                WaitSeconds(0.5)
            end
        end
    end
end
