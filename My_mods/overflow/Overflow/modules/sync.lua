-- Overflow - reads the resource counters from the sync.
--
-- Sync.Score counters change once per sim second and the values arrive about every 1.8 s,
-- so a single interval catches one or two steps of a counter: at a steady 20/s dIn jumps
-- between +20 and +40. The counters are cumulative, so their differences add up and a
-- longer window gives the true mean. The error of one window falls with its length: up to
-- 55% at 1.8 s, 20% at 5 s, 10% at 10 s.
--
-- Deltas accumulate between publications, which happen every WINDOW_TICKS ticks.
--
-- "Own production" does not come from dIn: own = income - incoming from allies. income is
-- an engine value per tick, the number the player sees on the game resource panel. It
-- includes overflow from allies (checked in the game), so the incoming part is subtracted
-- once. Reclaim counts as own production.
--
-- Outgoing and incoming come from the sync: dIn and dExc grow together, so the steps cancel
-- out in dIn - dOut - dExc - dSt.
--
-- Functions are exported as globals: the game discards what a module returns.

local PFX = 'OverflowSync'

local LOG                        = LOG
local GameTick                   = GameTick
local GetFocusArmy               = GetFocusArmy
local GetSimTicksPerSecond       = GetSimTicksPerSecond
local GetEconomyTotals           = GetEconomyTotals
local IsAlly                     = IsAlly
local AddOnSyncHashedCallback    = AddOnSyncHashedCallback
local RemoveOnSyncHashedCallback = RemoveOnSyncHashedCallback

local CB_ID = 'Overflow'

local STARTUP_TICKS = 50

-- Window length in ticks: 5 s at simFreq 10, an error of up to 20%. Longer is more accurate
-- but reacts slower to new buildings.
local WINDOW_TICKS = 50

-- Anything below this counts as zero.
local EPS = 0.5

local NERR_LIMIT = 3
local nErrors = 0

-- last sample seen for each army, published or not
local lastRaw = {}

-- deltas accumulated since the last publication
local acc = {}

-- ticks accumulated since the last publication
local accTicks = 0

-- Income accumulated over the window: it is a per-tick value, so it is averaged over time
-- like everything else.
local accIncomeE = 0
local accIncomeM = 0

-- Bounds of our storage over the window, for the log: non-zero incoming while the storage
-- stayed at the ceiling means the incoming is miscounted.
local minStoreE = nil
local maxStoreE = nil
local minStoreM = nil
local maxStoreM = nil

-- Free storage space, the maximum over the window. Zero or less means there was no room at
-- any sample, so nothing could come in from allies.
local maxHeadE = nil
local maxHeadM = nil

-- tick of the last processed payload
local lastTick = nil

local lastSignature = nil
local lastArmy = nil
local result = nil


local function Num(t, a, b)
    local v = t[a]
    if type(v) ~= 'table' then return nil end
    v = v[b]
    if type(v) ~= 'number' then return nil end
    return v
end

local function NonNeg(v)
    if v < 0 then return 0 end
    return v
end

local function Zero(v)
    if v < EPS then return 0 end
    return v
end

local function sd(v)
    if type(v) ~= 'number' then return 'n/a' end
    return string.format('%+.0f', v)
end

local function r1(v)
    if type(v) ~= 'number' then return 'n/a' end
    return string.format('%.1f', v)
end


function Reset()
    lastRaw = {}
    acc = {}
    accTicks = 0
    accIncomeE = 0
    accIncomeM = 0
    minStoreE = nil
    maxStoreE = nil
    minStoreM = nil
    maxStoreM = nil
    maxHeadE = nil
    maxHeadM = nil
    lastTick = nil
    lastSignature = nil
    result = nil
end

-- Reads every army into fresh[armyIdx] and adds its numbers to the signature parts.

local function ReadAll(scoreData, fresh, parts)
    for armyIdx, s in pairs(scoreData) do
        if type(armyIdx) == 'number' and type(s) == 'table'
            and type(s.resources) == 'table' then
            local res = s.resources
            local c = {
                ein    = Num(res, 'energyin',  'total'),
                eout   = Num(res, 'energyout', 'total'),
                eexc   = Num(res, 'energyout', 'excess'),
                estore = Num(res, 'storage',   'storedEnergy'),
                emin   = Num(res, 'massin',    'total'),
                mout   = Num(res, 'massout',   'total'),
                mexc   = Num(res, 'massout',   'excess'),
                mstore = Num(res, 'storage',   'storedMass'),
                -- Storage ceiling: without it a full storage cannot be detected.
                emax   = Num(res, 'storage',   'maxEnergy'),
                mmax   = Num(res, 'storage',   'maxMass'),
                recE   = Num(res, 'energyin',  'reclaimed'),
                recM   = Num(res, 'massin',    'reclaimed'),
            }
            fresh[armyIdx] = c
            table.insert(parts, tostring(armyIdx))
            table.insert(parts, tostring(c.ein))
            table.insert(parts, tostring(c.eout))
            table.insert(parts, tostring(c.eexc))
            table.insert(parts, tostring(c.estore))
            table.insert(parts, tostring(c.emin))
            table.insert(parts, tostring(c.mout))
            table.insert(parts, tostring(c.mexc))
            table.insert(parts, tostring(c.mstore))
        end
    end
end

--------------------------------------------------------------------------------
-- Computation
--
-- Every payload is compared with the last one seen, the deltas go to acc and are published
-- once WINDOW_TICKS ticks have gathered. Returns true if the window was published.
--
-- Outgoing follows from the balance:
--       dStor = dIn - dConsumed - dExcess - dGiven
--       dGiven = dIn - dConsumed - dExcess - dStor
-- dIn already includes overflow from allies (checked in the game), so it is not added here.
--------------------------------------------------------------------------------

-- Without accumulated deltas there is nothing to publish: the first payload only sets the
-- base of the comparison.
local function HaveMine(accTable, me)
    local a = accTable[me]
    if a == nil then return false end
    return a.ein ~= 0 or a.eout ~= 0 or a.eexc ~= 0 or a.estore ~= 0
end

local function Compute(scoreData, me, tickNow)
    local parts = {}
    local fresh = {}
    ReadAll(scoreData, fresh, parts)

    local nSeen = 0
    for _ in pairs(fresh) do nSeen = nSeen + 1 end
    if nSeen == 0 then return false end

    local signature = table.concat(parts, '|')
    if signature == lastSignature then
        -- the same data: no delta has grown
        return false
    end

    local logLines = {}

    for armyIdx, cur in pairs(fresh) do
        local prv = lastRaw[armyIdx]
        if prv
            and prv.ein and cur.ein
            and prv.eout and cur.eout
            and prv.eexc and cur.eexc
            and prv.estore and cur.estore
            and prv.emin and cur.emin
            and prv.mout and cur.mout
            and prv.mexc and cur.mexc
            and prv.mstore and cur.mstore then

            local a = acc[armyIdx]
            if a == nil then
                a = { ein = 0, eout = 0, eexc = 0, estore = 0,
                      emin = 0, mout = 0, mexc = 0, mstore = 0,
                      recE = 0, recM = 0 }
                acc[armyIdx] = a
            end

            a.ein    = a.ein    + (cur.ein    - prv.ein)
            a.eout   = a.eout   + (cur.eout   - prv.eout)
            a.eexc   = a.eexc   + (cur.eexc   - prv.eexc)
            a.estore = a.estore + (cur.estore - prv.estore)
            a.emin   = a.emin   + (cur.emin   - prv.emin)
            a.mout   = a.mout   + (cur.mout   - prv.mout)
            a.mexc   = a.mexc   + (cur.mexc   - prv.mexc)
            a.mstore = a.mstore + (cur.mstore - prv.mstore)
            if cur.recE and prv.recE then a.recE = a.recE + (cur.recE - prv.recE) end
            if cur.recM and prv.recM then a.recM = a.recM + (cur.recM - prv.recM) end

            table.insert(logLines, '  #' .. tostring(armyIdx) ..
                ' E dIn=' .. sd(a.ein) .. ' dOut=' .. sd(a.eout) ..
                ' dExc=' .. sd(a.eexc) .. ' dSt=' .. sd(a.estore) ..
                ' | M dIn=' .. sd(a.emin) .. ' dOut=' .. sd(a.mout) ..
                ' dExc=' .. sd(a.mexc) .. ' dSt=' .. sd(a.mstore))
        end
        lastRaw[armyIdx] = cur
    end

    -- ticks since the last processed payload
    local dtSec = 0
    if lastTick ~= nil then
        local dtTicks = tickNow - lastTick
        accTicks = accTicks + dtTicks
        dtSec = dtTicks / GetSimTicksPerSecond()
    end
    lastTick = tickNow
    lastSignature = signature

    -- Income is averaged over time: an instant value minus a window average would describe
    -- different moments.
    if dtSec > 0 then
        local okI, econI = pcall(GetEconomyTotals)
        if okI and type(econI) == 'table' then
            local freq = GetSimTicksPerSecond()
            accIncomeE = accIncomeE + econI.income.ENERGY * freq * dtSec
            accIncomeM = accIncomeM + econI.income.MASS * freq * dtSec
        end
    end

    -- bounds of our storage over the window
    local mineNow = fresh[me]
    if mineNow and mineNow.estore and mineNow.mstore then
        if minStoreE == nil or mineNow.estore < minStoreE then minStoreE = mineNow.estore end
        if maxStoreE == nil or mineNow.estore > maxStoreE then maxStoreE = mineNow.estore end
        if minStoreM == nil or mineNow.mstore < minStoreM then minStoreM = mineNow.mstore end
        if maxStoreM == nil or mineNow.mstore > maxStoreM then maxStoreM = mineNow.mstore end
        if mineNow.emax ~= nil then
            local headE = mineNow.emax - mineNow.estore
            if maxHeadE == nil or headE > maxHeadE then maxHeadE = headE end
        end
        if mineNow.mmax ~= nil then
            local headM = mineNow.mmax - mineNow.mstore
            if maxHeadM == nil or headM > maxHeadM then maxHeadM = headM end
        end
    end

    if not HaveMine(acc, me) then return false end

    -- the window is not complete yet
    if accTicks < WINDOW_TICKS then
        return false
    end

    local simFreq = GetSimTicksPerSecond()
    local sec = accTicks / simFreq
    if sec < 1 then
        return false
    end

    local incE, incM = 0, 0
    local goE, goM = 0, 0
    local recE, recM = 0, 0

    for armyIdx, a in pairs(acc) do
        local gE = a.ein - a.eout - a.eexc - a.estore
        local gM = a.emin - a.mout - a.mexc - a.mstore
        if armyIdx == me then
            goE = NonNeg(gE)
            goM = NonNeg(gM)
            recE = a.recE
            recM = a.recM
        else
            local okA, isAlly = pcall(IsAlly, me, armyIdx)
            if okA and isAlly then
                incE = incE + NonNeg(gE)
                incM = incM + NonNeg(gM)
            end
        end
    end

    local incRateE = incE / sec
    local incRateM = incM / sec

    -- A full storage takes no overflow from allies. If there was no free space at any
    -- sample of the window, the incoming has to be zero, so anything else is a computation
    -- error: it is zeroed and goes to the log with its numbers.
    local peggedE = maxHeadE ~= nil and maxHeadE <= 0
    local peggedM = maxHeadM ~= nil and maxHeadM <= 0

    if peggedE and incRateE > EPS then
        LOG(PFX .. ': GUARD E - свободного места не было ни разу (макс. ' ..
            sd(maxHeadE) .. '), входящий невозможен. Было: ' ..
            r1(incRateE) .. '/с -> 0')
        incRateE = 0
    end
    if peggedM and incRateM > EPS then
        LOG(PFX .. ': GUARD M - свободного места не было ни разу (макс. ' ..
            sd(maxHeadM) .. '), входящий невозможен. Было: ' ..
            r1(incRateM) .. '/с -> 0')
        incRateM = 0
    end

    -- Income is averaged over the same window as the incoming overflow and includes it
    -- (checked in the game), so the incoming is subtracted once.
    local incomeRateE = accIncomeE / sec
    local incomeRateM = accIncomeM / sec
    local ownE = incomeRateE - incRateE
    local ownM = incomeRateM - incRateM

    LOG(PFX .. ': win=' .. string.format('%.2f', sec) .. 's tick=' ..
        tostring(tickNow) .. ' | income=' .. r1(incomeRateE) ..
        ' in=' .. r1(incRateE) .. ' out=' .. r1(goE / sec) ..
        ' own=' .. r1(ownE))
    LOG(PFX .. ':   запас E за окно: ' ..
        r1(minStoreE) .. ' .. ' .. r1(maxStoreE) ..
        '   M: ' .. r1(minStoreM) .. ' .. ' .. r1(maxStoreM) ..
        '   своб. место E: ' .. sd(maxHeadE) .. ' M: ' .. sd(maxHeadM) ..
        '   полный: ' .. tostring(peggedE) .. '/' .. tostring(peggedM))
    for _, line in ipairs(logLines) do
        LOG(PFX .. ':   ' .. line)
    end

    result = {
        ok           = true,
        elapsed      = sec,
        incoming     = Zero(incRateE),
        outgoing     = Zero(goE / sec),
        own          = Zero(ownE),
        massIncoming = Zero(incRateM),
        massOutgoing = Zero(goM / sec),
        massOwn      = Zero(ownM),
        reclaim      = Zero(NonNeg(recE) / sec),
        massReclaim  = Zero(NonNeg(recM) / sec),
    }

    -- the window is closed, start over
    acc = {}
    accTicks = 0
    accIncomeE = 0
    accIncomeM = 0
    minStoreE = nil
    maxStoreE = nil
    minStoreM = nil
    maxStoreM = nil
    maxHeadE = nil
    maxHeadM = nil
    return true
end


local function OnScore(scoreData)
    -- the game calls this callback without pcall
    local ok, err = pcall(function()
        if type(scoreData) ~= 'table' then return end
        if GameTick() <= STARTUP_TICKS then return end

        local me = GetFocusArmy()
        if type(me) ~= 'number' or me < 1 then
            result = { ok = false, observer = true }
            return
        end
        if me ~= lastArmy then
            lastArmy = me
            Reset()
        end

        Compute(scoreData, me, GameTick())
    end)

    if ok then
        nErrors = 0
        return
    end

    nErrors = nErrors + 1
    LOG(PFX .. ': ERROR (' .. tostring(nErrors) .. '/' .. tostring(NERR_LIMIT) ..
        '): ' .. tostring(err))
    if nErrors >= NERR_LIMIT then
        RemoveOnSyncHashedCallback('Score', CB_ID)
        LOG(PFX .. ': too many errors, sync callback removed, panel will stay empty')
    end
end


local started = false

function Start()
    if started then return end
    started = true

    AddOnSyncHashedCallback(OnScore, 'Score', CB_ID)
    LOG(PFX .. ': watching Sync.Score, no unit scan, window=' ..
        tostring(WINDOW_TICKS) .. ' ticks')
end

function GetResult()
    return result
end

function ResetCounters()
    Reset()
end