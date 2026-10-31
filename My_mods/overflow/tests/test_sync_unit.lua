-- Юнит-тест настоящего sync.lua на ЗАДАННЫХ числах, где ответ известен заранее.
--
-- Лог игры больше не подходит: предыдущий файл с диагностикой заменён.
-- Зато тут всё детерминировано - ожидания выведены из формулы руками.
--
-- Сценарии (окно 2 с, значит делим на 2, чтобы получить /с):
--
--  A. у союзника есть место, наше хранилище полное
--     ME:   dIn=40  dOut=0  dExc=0  dSt=0   -> исходящий 40/2 = 20/с
--     ALLY: dIn=40  dOut=0  dExc=0  dSt=40  -> союзник отдал 0
--     входящий = 0, своё = 40/2 - 0 = 20/с
--
--  B. оба хранилища полные, излишек уходит в пустоту
--     ME:   dIn=40  dOut=0  dExc=40 dSt=0   -> исходящий 0, всё сгорело
--     входящий = 0, своё = 20/с
--
--  C. мы тратим, союзник делится с нами
--     ME:   dIn=72  dOut=140 dExc=0  dSt=0   -> исходящий 0 (переполнение)
--     ALLY: dIn=40  dOut=8  dExc=0  dSt=0   -> союзник отдал 32/2 = 16/с
--     входящий = 16/с, своё = 36 - 16 = 20/с

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
-- Движок отдаёт income ЗА ТИК. Мод умножает на simFreq (10).
-- Ставим 2.0 -> 20/с, как командир.
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
-- В ФАФ значение return ОТБРАСЫВАЕТСЯ: экспорт идёт через глобалы, потому что
-- doscript выполняет файл с таблицей модуля как окружением. Поэтому и здесь
-- проверяем глобалы, а не результат выполнения.
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

-- Окно теперь 50 тиков, и дельты КОПЯТСЯ. Значит каждый payload добавляет
-- своё, а публикация происходит раз в 50 тиков. Подаём много шагов и смотрим
-- результат после каждой публикации.
local TICK_PER_STEP = 18    -- так приходят payload в игре
local PROD_E = 20           -- 2.0/тик * 10 = 20/с
local PROD_M = 1

-- Прогоняет nSteps payload подряд, возвращает последнюю публикацию.
--
-- СБРОС ОБЯЗАТЕЛЕН: счётчики модуля переживают сценарий, а следующий
-- начинается с меньших тиков, и разности выходят отрицательными.
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

-- A: у союзника есть место. Наш излишек (dSt=0, dExc=0) уходит к нему,
--    у союзника растёт запас.
local function aME(i)
    return mkME(i, 0, 0, 4000, 0, 650, 0)
end
local function aAL(i)
    return mkAL(4000 + PROD_E * ((i + 1) * TICK_PER_STEP) / 10.0, 0,
                PROD_E * ((i + 1) * TICK_PER_STEP) / 10.0)
end

-- B: оба полные, наш излишек сгорает (dExc повторяет dIn)
local function bME(i)
    local dIn = PROD_E * TICK_PER_STEP / 10.0
    return mkME(i, 0, 4000 + dIn * (i + 1), 4000, 0, 650,
                650 + PROD_M * TICK_PER_STEP / 10.0 * (i + 1))
end
local bAL = aAL

-- C: союзник делится с нами: его излишек 20-8=12/с -> к нам
local function cME(i)
    local dIn = PROD_E * TICK_PER_STEP / 10.0
    return mkME(i, 140 * TICK_PER_STEP / 10.0 * (i + 1), 4000 + dIn * (i + 1),
                4000, 0, 650, 0)
end
local function cAL(i)
    -- запас ПОСТОЯННЫЙ: союзник полон и расти не может.
    -- Тогда исходящий союзника = (36 - 14.4 - 0 - 0) / 1.8 = 12/с
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
