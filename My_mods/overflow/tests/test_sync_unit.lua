-- Unit test of the real sync.lua on fixed numbers whose answers are known in advance: the
-- expected values are worked out from the formulas by hand. Our income is 20/s.
--
-- Scenarios (all rates per second):
--
--   A. The ally has room, our storage is full.
--      We: dIn=20, dOut=0, dExc=0, dSt=0 -> outgoing 20.
--      Ally: dIn=20, dSt=20 -> it gives nothing. Incoming 0, own = 20 - 0 = 20.
--
--   B. Both storages are full, the surplus burns.
--      We: dExc equals dIn -> outgoing 0. Incoming 0, own 20.
--
--   C. We spend more than we earn, the ally shares with us.
--      We: dOut=140, dExc equals dIn -> the balance is negative, outgoing 0.
--      Ally: dIn=20, dOut=8, storage constant -> it gives 12.
--      Incoming 12, own = 20 - 12 = 8.

local function ReadFile(path)
    local file = assert(io.open(path, 'rb'))
    local text = file:read('*a')
    file:close()
    return text
end

local msgs = {}
local tick = 0
local callback = nil

local env = setmetatable({}, { __index = _G })
env.LOG = function(m) table.insert(msgs, tostring(m)) end
env.GameTick = function() return tick end
env.GetFocusArmy = function() return 1 end
env.GetSimTicksPerSecond = function() return 10 end
env.IsAlly = function(a, b) return a == 1 and b == 2 end
env.AddOnSyncHashedCallback = function(cb, cat, id) callback = cb end
env.RemoveOnSyncHashedCallback = function(cat, id) callback = nil end
env.import = function(p) return {} end
-- The engine returns income per tick and the mod multiplies it by simFreq (10): 2.0 gives
-- 20/s, as for a commander.
env.GetEconomyTotals = function()
    return { income = { ENERGY = 2.0, MASS = 0.1 },
             reclaimed = { ENERGY = 0.0, MASS = 0.0 },
             stored = { ENERGY = 4000.0, MASS = 650.0 },
             maxStorage = { ENERGY = 4000.0, MASS = 650.0 },
             lastUseActual = { ENERGY = 0.0, MASS = 0.0 } }
end

local chunk = assert(loadstring(ReadFile('../Overflow/modules/sync.lua'), 'sync.lua'))
setfenv(chunk, env)
local ret = chunk()
-- The game discards the return value of a module: exports go through globals, because
-- doscript runs the file with the module table as its environment. So the globals are
-- checked here, not the result.
assert(ret == nil, 'модуль не должен ничего возвращать: экспорт через глобалы')
assert(type(rawget(env, 'Start')) == 'function', 'экспорт Start отсутствует')
assert(type(rawget(env, 'GetResult')) == 'function', 'экспорт GetResult отсутствует')
print('экспорт на месте: Start, GetResult')

env.Start()
if callback == nil then
    print('[FAIL] нет колбэка')
    os.exit(1)
end

local function payload(me, ally)
    return {
        [1] = { resources = {
            energyin = { total = me.ein, reclaimed = 0 },
            energyout = { total = me.eout, excess = me.eexc },
            massin = { total = me.emin, reclaimed = 0 },
            massout = { total = me.mout, excess = me.mexc },
            storage = { storedEnergy = me.est, storedMass = me.mstore },
        } },
        [2] = { resources = {
            energyin = { total = ally.ein, reclaimed = 0 },
            energyout = { total = ally.eout, excess = ally.eexc },
            massin = { total = 0, reclaimed = 0 },
            massout = { total = 0, excess = 0 },
            storage = { storedEnergy = ally.est, storedMass = 0 },
        } },
    }
end

-- The window is 50 ticks and the deltas accumulate: each payload adds its own, and a result
-- is published once per window. Many steps are fed and the last published result is
-- checked.
local TICK_PER_STEP = 18    -- ticks between payloads in the game
local PROD_E = 20           -- 2.0 per tick * 10 = 20/s
local PROD_M = 1

-- Feeds nSteps payloads in a row and returns the last publication and the number of
-- publications.
--
-- The reset is required: module counters outlive a scenario, and the next one starts with
-- smaller ticks, so the differences come out negative.
local function series(nSteps, meFn, allyFn)
    env.ResetCounters()
    local last = nil
    local count = 0
    tick = 60
    for i = 0, nSteps - 1 do
        tick = tick + TICK_PER_STEP
        callback(payload(meFn(i), allyFn(i)))
        local r = env.GetResult()
        if r ~= nil then
            count = count + 1
            last = r
        end
    end
    return last, count
end

local function mkME(i, eout, eexc, est, mout, mstore, mexc)
    return { ein = 4000 + PROD_E * ((i + 1) * TICK_PER_STEP) / 10.0,
             eout = eout, eexc = eexc, est = est,
             emin = 650 + PROD_M * ((i + 1) * TICK_PER_STEP) / 10.0,
             mout = mout, mexc = mexc, mstore = mstore }
end

local function mkAL(ein, eout, est)
    return { ein = ein, eout = eout, eexc = 0, est = est }
end

-- A: the ally has room. Our surplus (dSt=0, dExc=0) goes to the ally, whose stock grows.
local function aME(i)
    return mkME(i, 0, 0, 4000, 0, 650, 0)
end
local function aAL(i)
    return mkAL(4000 + PROD_E * ((i + 1) * TICK_PER_STEP) / 10.0, 0,
                PROD_E * ((i + 1) * TICK_PER_STEP) / 10.0)
end

-- B: both are full, our surplus burns (dExc repeats dIn).
local function bME(i)
    local dIn = PROD_E * TICK_PER_STEP / 10.0
    return mkME(i, 0, 4000 + dIn * (i + 1), 4000, 0, 650,
                650 + PROD_M * TICK_PER_STEP / 10.0 * (i + 1))
end
local bAL = aAL

-- C: the ally shares with us: its surplus 20-8=12/s comes to us.
local function cME(i)
    local dIn = PROD_E * TICK_PER_STEP / 10.0
    return mkME(i, 140 * TICK_PER_STEP / 10.0 * (i + 1), 4000 + dIn * (i + 1),
                4000, 0, 650, 0)
end
local function cAL(i)
    -- The stock is constant: the ally is full and cannot grow.
    -- Its outgoing is then (36 - 14.4 - 0 - 0) / 1.8 = 12/s.
    return mkAL(4000 + PROD_E * ((i + 1) * TICK_PER_STEP) / 10.0,
                8 * TICK_PER_STEP / 10.0 * (i + 1), 0)
end

local a, nA = series(8, aME, aAL)
local b, nB = series(8, bME, bAL)
local c, nC = series(8, cME, cAL)
print(string.format('публикаций: A=%d B=%d C=%d', nA, nB, nC))

local failed = {}

local function check(name, got, want)
    local ok = got ~= nil and math.abs(got - want) <= 0.01
    print(string.format('  [%s] %-34s получено %-8s ожидалось %s',
                        ok and 'OK  ' or 'FAIL', name,
                        got == nil and 'None' or string.format('%.2f', got), tostring(want)))
    if not ok then
        table.insert(failed, name)
    end
end

print('')
print('=== Сценарий A: место у союзника есть ===')
check('исходящий, /с', a and a.outgoing, 20)
check('входящий, /с', a and a.incoming, 0)
check('своё, /с', a and a.own, 20)

print('')
print('=== Сценарий B: место НИ У КОГО НЕТ, излишек сгорает ===')
check('исходящий, /с', b and b.outgoing, 0)
check('входящий, /с', b and b.incoming, 0)
check('своё, /с', b and b.own, 20)

print('')
print('=== Сценарий C: союзник отдаёт 12/с ===')
check('входящий, /с', c and c.incoming, 12)
check('исходящий, /с', c and c.outgoing, 0)
check('своё, /с = income(20) - входящий(12)', c and c.own, 8)

print('')
print('=== МАССА: сценарий A ===')
check('исходящий M, /с', a and a.massOutgoing, 1)

print('')
local errors = 0
for _, m in ipairs(msgs) do
    if string.find(m, 'ERROR', 1, true) or string.find(m, 'FAILED', 1, true) then
        errors = errors + 1
        if errors <= 5 then
            print('   ' .. m)
        end
    end
end
print('ошибок модуля: ' .. tostring(errors))
print('')
if table.getn(failed) > 0 or errors > 0 then
    print('ИТОГ: провалено: ' .. table.concat(failed, ', '))
    os.exit(1)
end
print('ИТОГ: все проверки пройдены')
