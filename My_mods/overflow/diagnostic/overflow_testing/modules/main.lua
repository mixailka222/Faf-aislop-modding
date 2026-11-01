-- Overflow Testing - diagnostic mod: only the log, no math.
--
-- Establishes that the game syncs the full economy of your army and allies, and the meaning
-- of three things:
--   1) energyout.excess / massout.excess - is it filled at all
--   2) energyin.total - does it include overflow from allies
--   3) excess - does it grow when an ally has run out of room
--
-- The mod computes and draws nothing. It writes raw values and the counter differences of
-- the last sync.
--
-- Data comes from AddOnSyncHashedCallback at the moment Sync.Score arrives, not from
-- currentScores: the score beat of the game clears that right after drawing and runs before
-- ours.
--
-- The game calls the callback without pcall and an error would break the sync of the whole
-- game, so the body is under pcall. The first three errors are logged with a trace, then
-- the callback removes itself.

local PFX = 'OverflowTest'

local LOG                        = LOG
local GameTick                   = GameTick
local GetFocusArmy               = GetFocusArmy
local IsAlly                     = IsAlly
local GetEconomyTotals           = GetEconomyTotals
local GetGameTimeSeconds         = GetGameTimeSeconds
local AddOnSyncHashedCallback    = AddOnSyncHashedCallback
local RemoveOnSyncHashedCallback = RemoveOnSyncHashedCallback

-- Callback id. It has to be unique, otherwise the mod overwrites another callback.
local CB_ID = 'OverflowTest'

-- First output: there are no differences yet.
local firstSample = true

-- How many times the data really changed.
local nSyncSamples = 0

-- Errors in a row in the callback. After NERR_LIMIT the mod switches off.
local nErrors = 0
local NERR_LIMIT = 3

-- Signature of the last Sync.Score written. The sync comes every beat while the data is
-- rebuilt about every 2 seconds, so only a real change is logged.
local lastSignature = nil

-- Previous counters by army index, for the differences.
local prevCounters = {}

--------------------------------------------------------------------------------
-- Formatting
--------------------------------------------------------------------------------

-- Tells nil (no field) from 0 (a field equal to zero). For excess that matters: "always
-- zero" and "no such field" are different conclusions.
local function num(v)
    if v == nil then
        return 'nil'
    end
    if type(v) ~= 'number' then
        return tostring(v)
    end
    if v ~= v then
        return 'nan'
    end
    return string.format('%.1f', v)
end

local function delta(newVal, oldVal)
    if type(newVal) ~= 'number' or type(oldVal) ~= 'number' then
        return 'nil'
    end
    return string.format('%+.1f', newVal - oldVal)
end

-- Reads a nested field, nil if a level is absent: field(t, 'energyin') or field(t,
-- 'energyin', 'total').
local function field(t, a, b)
    if type(t) ~= 'table' then return nil end
    local v = t[a]
    if b == nil then return v end
    if type(v) ~= 'table' then return nil end
    return v[b]
end

--------------------------------------------------------------------------------
-- Counters for the differences
--------------------------------------------------------------------------------

local function saveCounters(armyIdx, res)
    local c = {
        ein    = field(res, 'energyin',  'total'),
        eout   = field(res, 'energyout', 'total'),
        eexc   = field(res, 'energyout', 'excess'),
        estore = field(res, 'storage',   'storedEnergy'),
        emin   = field(res, 'massin',    'total'),
        mout   = field(res, 'massout',   'total'),
        mexc   = field(res, 'massout',   'excess'),
        mstore = field(res, 'storage',   'storedMass'),
    }
    prevCounters[armyIdx] = c
    return c
end

--------------------------------------------------------------------------------
-- One army
--------------------------------------------------------------------------------

-- Relation of an army to us: ME / ALLY / ENEM. The argument order follows the game:
-- IsAlly(myArmy, checked). Under pcall: a failure costs one label, not the whole mod.
local function relation(armyIdx, me)
    if armyIdx == me then
        return 'ME  '
    end
    local ok, isAlly = pcall(IsAlly, me, armyIdx)
    if ok and isAlly then
        return 'ALLY'
    end
    return 'ENEM'
end

-- Economy from the engine, to compare with the sync.
local function dumpOwnEcon()
    local ok, e = pcall(GetEconomyTotals)
    if not ok or type(e) ~= 'table' then
        LOG(PFX .. ':   own econ (engine): unavailable (' .. tostring(e) .. ')')
        return
    end
    LOG(PFX .. ':   own econ (engine): inc E=' .. num(field(e, 'income', 'ENERGY')) ..
        ' M=' .. num(field(e, 'income', 'MASS')) ..
        ' | use E=' .. num(field(e, 'lastUseActual', 'ENERGY')) ..
        ' M=' .. num(field(e, 'lastUseActual', 'MASS')) ..
        ' | st E=' .. num(field(e, 'stored', 'ENERGY')) ..
        ' M=' .. num(field(e, 'stored', 'MASS')) ..
        ' | max E=' .. num(field(e, 'maxStorage', 'ENERGY')) ..
        ' M=' .. num(field(e, 'maxStorage', 'MASS')) ..
        ' | recl E=' .. num(field(e, 'reclaimed', 'ENERGY')) ..
        ' M=' .. num(field(e, 'reclaimed', 'MASS')))
end

local function dumpArmy(armyIdx, s, me)
    local rel = relation(armyIdx, me)
    local armyName = s.name or s.nickname or '?'

    local res = s.resources

    -- For enemies the game sends only {general={}}. This is expected.
    if type(res) ~= 'table' then
        LOG(PFX .. ':   ' .. rel .. ' #' .. tostring(armyIdx) ..
            ' ' .. tostring(armyName) ..
            ' resources=nil  <- так и должно быть для врага')
        return
    end

    if armyIdx == me then
        dumpOwnEcon()
    end

    -- prv has to be read before saveCounters overwrites it, or all differences would be 0.
    local prv = prevCounters[armyIdx]
    local cur = saveCounters(armyIdx, res)

    -- Raw values. in = total / rate, then reclaimed / reclaimRate; out = total / rate, then
    -- excess; st = stored / max.
    LOG(PFX .. ':   ' .. rel .. ' #' .. tostring(armyIdx) ..
        ' ' .. tostring(armyName) ..
        ' | E in=' .. num(field(res, 'energyin', 'total')) ..
        '/' .. num(field(res, 'energyin', 'rate')) ..
        ' rec=' .. num(field(res, 'energyin', 'reclaimed')) ..
        '/' .. num(field(res, 'energyin', 'reclaimRate')) ..
        ' | E out=' .. num(field(res, 'energyout', 'total')) ..
        '/' .. num(field(res, 'energyout', 'rate')) ..
        ' EXC=' .. num(field(res, 'energyout', 'excess')) ..
        ' | E st=' .. num(field(res, 'storage', 'storedEnergy')) ..
        '/' .. num(field(res, 'storage', 'maxEnergy')))

    LOG(PFX .. ':   ' .. rel .. ' #' .. tostring(armyIdx) ..
        ' ' .. tostring(armyName) ..
        ' | M in=' .. num(field(res, 'massin', 'total')) ..
        '/' .. num(field(res, 'massin', 'rate')) ..
        ' rec=' .. num(field(res, 'massin', 'reclaimed')) ..
        '/' .. num(field(res, 'massin', 'reclaimRate')) ..
        ' | M out=' .. num(field(res, 'massout', 'total')) ..
        '/' .. num(field(res, 'massout', 'rate')) ..
        ' EXC=' .. num(field(res, 'massout', 'excess')) ..
        ' | M st=' .. num(field(res, 'storage', 'storedMass')) ..
        '/' .. num(field(res, 'storage', 'maxMass')))

    -- Differences over the last sync, the input of the formula G = P + I_in - E - W - dS. G
    -- itself is computed when the log is analyzed.
    if firstSample or type(prv) ~= 'table' then
        LOG(PFX .. ':   ' .. rel .. ' #' .. tostring(armyIdx) ..
            '  (first sample, no deltas yet)')
        return
    end

    LOG(PFX .. ':   ' .. rel .. ' #' .. tostring(armyIdx) ..
        ' dE: prod=' .. delta(cur.ein, prv.ein) ..
        ' cons=' .. delta(cur.eout, prv.eout) ..
        ' EXC=' .. delta(cur.eexc, prv.eexc) ..
        ' stor=' .. delta(cur.estore, prv.estore))

    LOG(PFX .. ':   ' .. rel .. ' #' .. tostring(armyIdx) ..
        ' dM: prod=' .. delta(cur.emin, prv.emin) ..
        ' cons=' .. delta(cur.mout, prv.mout) ..
        ' EXC=' .. delta(cur.mexc, prv.mexc) ..
        ' stor=' .. delta(cur.mstore, prv.mstore))
end

--------------------------------------------------------------------------------
-- Contents of Sync.Score
--------------------------------------------------------------------------------

-- Returns the counts of me, allies, enemies and records with resources.
local function countArmies(scoreData)
    local nAlly, nMe, nEnem, nRes = 0, 0, 0, 0
    local me = GetFocusArmy()
    for armyIdx, s in scoreData do
        if type(armyIdx) == 'number' and type(s) == 'table' then
            local rel = relation(armyIdx, me)
            if rel == 'ME  ' then
                nMe = nMe + 1
            elseif rel == 'ALLY' then
                nAlly = nAlly + 1
            else
                nEnem = nEnem + 1
            end
            if type(s.resources) == 'table' then
                nRes = nRes + 1
            end
        end
    end
    return nMe, nAlly, nEnem, nRes
end

-- Sorted army indexes, for a stable output order.
local function sortedIndexes(scoreData)
    local idxs = {}
    for armyIdx in scoreData do
        if type(armyIdx) == 'number' then
            table.insert(idxs, armyIdx)
        end
    end
    table.sort(idxs)
    return idxs
end

-- Signature of the key numbers of all armies. Allies are included: if our own record has no
-- resources, the signature would never change.
local function makeSignature(scoreData)
    local parts = {}
    for _, armyIdx in ipairs(sortedIndexes(scoreData)) do
        local res = scoreData[armyIdx].resources
        table.insert(parts, tostring(armyIdx))
        table.insert(parts, tostring(field(res, 'energyin', 'total')))
        table.insert(parts, tostring(field(res, 'energyout', 'total')))
        table.insert(parts, tostring(field(res, 'energyout', 'excess')))
        table.insert(parts, tostring(field(res, 'storage', 'storedEnergy')))
        table.insert(parts, tostring(field(res, 'massin', 'total')))
        table.insert(parts, tostring(field(res, 'massout', 'total')))
        table.insert(parts, tostring(field(res, 'massout', 'excess')))
        table.insert(parts, tostring(field(res, 'storage', 'storedMass')))
    end
    return table.concat(parts, '|')
end

--------------------------------------------------------------------------------
-- Main dump
--------------------------------------------------------------------------------

local function DumpScore(scoreData)
    if type(scoreData) ~= 'table' then
        LOG(PFX .. ': Sync.Score пришёл не-таблицей: ' .. tostring(scoreData))
        return
    end

    local sig = makeSignature(scoreData)
    if sig == lastSignature then
        -- The data was not rebuilt: stay silent to keep the log readable.
        return
    end

    local me = GetFocusArmy()
    local nMe, nAlly, nEnem, nRes = countArmies(scoreData)

    LOG(PFX .. ': ===== t=' .. num(GetGameTimeSeconds()) ..
        's tick=' .. tostring(GameTick()) ..
        ' me=' .. tostring(me) ..
        ' armies=' .. tostring(nMe + nAlly + nEnem) ..
        ' (me=' .. tostring(nMe) ..
        ' ally=' .. tostring(nAlly) ..
        ' enem=' .. tostring(nEnem) ..
        ') withResources=' .. tostring(nRes) .. ' =====')

    -- Each army has its own pcall: one bad army must not kill the output.
    for _, armyIdx in ipairs(sortedIndexes(scoreData)) do
        local s = scoreData[armyIdx]
        if type(s) == 'table' then
            local okA, errA = pcall(dumpArmy, armyIdx, s, me)
            if not okA then
                LOG(PFX .. ':   army ' .. tostring(armyIdx) ..
                    ' dump failed, skipped: ' .. tostring(errA))
            end
        end
    end

    lastSignature = sig
    firstSample = false
    nSyncSamples = nSyncSamples + 1
end

--------------------------------------------------------------------------------
-- Callback
--------------------------------------------------------------------------------

local function OnScore(scoreData)
    -- The game calls this callback without pcall, and an error would break the sync of the
    -- game. No waits here.
    local ok, err = pcall(DumpScore, scoreData)
    if ok then
        nErrors = 0
        return
    end

    nErrors = nErrors + 1
    LOG(PFX .. ': ERROR in OnScore (' .. tostring(nErrors) .. '/' ..
        tostring(NERR_LIMIT) .. '): ' .. tostring(err))
    local okTB, tb = pcall(debug.traceback)
    if okTB then
        LOG(PFX .. ': ' .. tostring(tb))
    end

    if nErrors >= NERR_LIMIT then
        pcall(RemoveOnSyncHashedCallback, 'Score', CB_ID)
        LOG(PFX .. ': too many errors, callback removed, no more logging')
    end
end

--------------------------------------------------------------------------------
-- Start
--------------------------------------------------------------------------------

local started = false

-- Only the registration of the callback, no waits.
local function Start()
    if started then
        return
    end
    started = true

    if type(AddOnSyncHashedCallback) ~= 'function' then
        error('AddOnSyncHashedCallback is not a function - cannot watch Sync.Score')
    end

    AddOnSyncHashedCallback(OnScore, 'Score', CB_ID)
    LOG(PFX .. ': registered AddOnSyncHashedCallback(key="Score", id="' .. CB_ID .. '")')
    LOG(PFX .. ': waiting for Sync.Score. Logging only, nothing is computed.')
end

-- Watchdog: no data within 40 seconds is a result of its own. Outside pcall, because it
-- waits.
local function Watchdog()
    WaitSeconds(40)
    if lastSignature == nil then
        LOG(PFX .. ': WARNING: no Sync.Score in 40 seconds.')
        LOG(PFX .. ': либо alliesScore выключен, либо ключ не "Score",')
        LOG(PFX .. ': либо игра вообще не шлёт экономику через синхронизацию.')
    else
        LOG(PFX .. ': sync is alive, ' .. tostring(nSyncSamples) ..
            ' samples, ' .. tostring(nErrors) .. ' errors so far')
    end
end

--------------------------------------------------------------------------------
-- Phase mark for a manual test
--------------------------------------------------------------------------------

-- One game has three phases, so a mark goes to the same log to tell them apart. Call it
-- from the game console (F10):
--
--   UI_Lua import('/mods/overflow_testing/modules/main.lua').Mark("PHASE 2")
function Mark(text)
    LOG(PFX .. ': ############ ' .. tostring(text) ..
        ' ############  t=' .. num(GetGameTimeSeconds()) ..
        's  tick=' .. tostring(GameTick()))
end

function OnCreateUI()
    -- No wait here: the registration has to happen before the first sync arrives.
    local ok, err = pcall(Start)
    if not ok then
        LOG(PFX .. ': start FAILED: ' .. tostring(err))
        return
    end

    ForkThread(Watchdog)
end
