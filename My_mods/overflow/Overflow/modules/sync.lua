-- Overflow - чтение синхронизации, версия 2.
--
-- ============================================================================
--  ЧТО БЫЛО СЛОМАНО (версия 15, измерено в игре)
-- ============================================================================
--
--  Панель показывала "own production" то 11.1, то 22.2 вместо ровных 20.
--  Лог это однозначно объяснил:
--
--      win=1.80s tick=85  prevTick=67 | own=22.2
--        #1 E dIn=+40 dOut=+0 dExc=+40 dSt=+0
--      win=1.80s tick=103 prevTick=85 | own=22.2
--        #1 E dIn=+40 ...
--      win=1.80s tick=121 prevTick=103 | own=11.1
--        #1 E dIn=+20 ...
--
--  Окно ВСЕГДА 1.80 с (18 тиков). Прыгает dIn: +40 или +20.
--  Среднее при этом верное: (13*40 + 3*20)/16/1.8 = 20.1/с.
--  То есть неверны не данные и не усреднение, а ДЛИНА ОКНА.
--
--  ПОЧЕМУ ОКНО КОРОТКОЕ. Счётчики в Sync.Score обновляются раз в
--  sim-секунду - sim/score.lua:106, ScoreResourcesThread:
--
--      while not GameIsOver do
--          WaitSeconds(1)
--          ...Score.resources.energyin.total = brain:GetArmyStat(...)
--
--  То есть счётчик - "лестница" со ступенькой в 1 секунду, а значение
--  приходит примерно раз в 1.8 с (scoreInterval = 2, sim/score.lua:2).
--  Границы не совпадают, и окно в 1.8 с попадает то на одну ступеньку
--  (dIn=20), то на две (dIn=40).
--
--  Штатная панель ресурсов от этого свободна: economy.lua:376-391 меряет
--  ЗА ОДИН ТИК и вызывается каждый тик, то есть в масштабе 1 тика.
--
--  ПОЧЕМУ ДЛИННОЕ ОКНО ЛЕЧИТ. Все счётчики - накопительные, разности
--  телескопируются: сумма dIn за все окна равна общему приросту, и деление
--  на суммарное время даёт верную среднюю независимо от ступенек.
--  Ошибка отдельного окна обратно пропорциональна его длине:
--      окно 1.8 с -> до 55% ошибки
--      окно 5   с -> до 20%
--      окно 10  с -> до 10%
--
-- ============================================================================
--  ЧТО ИЗМЕНЕНО
-- ============================================================================
--
--  1. Окно удлинено до WINDOW_TICKS. Дельты копятся между публикациями,
--     публикация происходит только когда набралось достаточно тиков.
--  2. "own production" больше НЕ берётся из dIn, а считается из движка:
--         own = income - входящий_от_союзников
--     income - величина ЗА ТИК (economy.lua:415 умножает её на simFreq),
--     поэтому масштабировать окно не нужно вовсе, и число точное
--     независимо от лестницы счётчиков. Это ровно то значение, которое
--     видит игрок на штатной панели ресурсов.
--
--     Почему так надёжнее: "own" равно income минус то, что пришло от
--     союзников. income включает и перелив ОТ союзников (проверено в игре),
--     поэтому входящий вычитается ровно один раз.
--
--  3. Исходящий и входящий по-прежнему из синхронизации. Им лестница
--     НЕ мешает: dIn и dExc растут вместе, поэтому в разности
--     dIn - dOut - dExc - dSt ступеньки сокращаются. Проверено на данных
--     выше: dIn=+40 при dExc=+40 даёт ровный ноль, и при dIn=+20 при
--     dExc=+20 тоже ноль.
--
-- ============================================================================
--  ЭКСПОРТ: функциями, НЕ через return. Значение return отбрасывается,
--  см. import.lua:61 и 171, а у _G стоит метаметод config.lua:56-61,
--  падающий ошибкой на несуществующем глобале. Подробно методичка 3.23.
-- ============================================================================
--
--  ЗАПРЕЩЁННО: оператор # и %, continue, math.huge, WaitSeconds внутри
--  pcall, локальные имена tag/name/index/count/value/type/end.
-- ============================================================================

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

-- ДЛИНА ОКНА В ТИКАХ. Всё, что короче, ловит ступеньки счётчика.
-- 50 тиков = 5 с при simFreq 10: ошибка отдельного окна до 20%.
-- Больше - честнее, но медленнее реакция на постройки.
local WINDOW_TICKS = 50

-- Порог "это ноль".
local EPS = 0.5

local NERR_LIMIT = 3
local nErrors = 0

-- последний ВИДЕННЫЙ отсчёт по каждой армии (не публикованный)
local lastRaw = {}

-- накопленные дельты с прошлой публикации
local acc = {}

-- тиков накоплено с прошлой публикации
local accTicks = 0

-- income - величина ЗА ТИК, поэтому усреднять её нужно так же, как всё
-- остальное: по времени, а не как одно мгновенное значение.
-- Накопленный доход за текущее окно.
local accIncomeE = 0
local accIncomeM = 0

-- границы запаса нашей армии за окно. Нужны для диагностики: если входящий
-- перелив ненулевой, а запас всё окно стоял на потолке, значит входящий
-- посчитан неверно. Если запас плавал - значит всё верно.
local minStoreE = nil
local maxStoreE = nil
local minStoreM = nil
local maxStoreM = nil

-- ЗАПАС СВОБОДНОГО МЕСТА, максимум за окно.
--
-- Считаем по каждому отсчёту ceiling - stored и берём МАКСИМУМ. Ноль или
-- меньше значит: свободного места не было НИ РАЗУ за окно, то есть запас
-- стоял на потолке все окно и принимать перелив от союзников было некуда.
--
-- Именно максимум, а не минимум: «ни разу не было места» означает, что
-- самая большая из всех величин неположительна.
--
-- Раньше здесь стоял грубый признак minStore >= minCeil. Он ошибается в
-- сторону ложного срабатывания: если потолок вырос в середине окна (бонус
-- за соседство, достроенный генератор), то минимум потолка остаётся низким
-- и запас объявляется полным, хотя место во второй половине окна было.
local maxHeadE = nil
local maxHeadM = nil

-- тик последнего обработанного payload
local lastTick = nil

local lastSignature = nil
local lastArmy = nil
local result = nil

--------------------------------------------------------------------------------
-- ВСПОМОГАТЕЛЬНОЕ
--------------------------------------------------------------------------------

local function Num(t, a, b)
    if type(t) ~= 'table' then return nil end
    local v = t[a]
    if b == nil then return v end
    if type(v) ~= 'table' then return nil end
    v = v[b]
    if type(v) ~= 'number' then return nil end
    return v
end

local function NonNeg(v)
    if type(v) ~= 'number' then return 0 end
    if v < 0 then return 0 end
    return v
end

local function Zero(v)
    if type(v) ~= 'number' then return 0 end
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

--------------------------------------------------------------------------------
-- СБРОС
--------------------------------------------------------------------------------

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

--------------------------------------------------------------------------------
-- ЧТЕНИЕ ВСЕХ АРМИЙ В ОТСЧЁТЫ
-- ----------------------------------------------------------------------------
--  возвращает подпись и заполняет fresh[armyIdx]
--------------------------------------------------------------------------------

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
                -- ПОТОЛОК ХРАНИЛИЩА. sim/score.lua:141-142 отдаёт его в
                -- синхронизацию, мод его не читал, а без него нельзя
                -- проверить, что запас стоял на полном.
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
-- РАСЧЁТ
-- ----------------------------------------------------------------------------
--  Возвращает true, если окно опубликовано.
--
--  КАК РАБОТАЕТ ОКНО. Каждый payload сравнивается с ПОСЛЕДНИМ ВИДЕННЫМ,
--  дельты копятся в acc, а публикуются только когда набралось
--  WINDOW_TICKS тиков. Сумма дельт телескопируется, поэтому среднее за
--  окно точное независимо от ступенек счётчика.
--
--  БАЗА ИСХОДЯЩЕГО И ВХОДЯЩЕГО - тождество баланса:
--      dStor = dIn - dConsumed - dExcess - dGiven
--      => dGiven = dIn - dConsumed - dExcess - dStor
--
--  ЛОВУШКА, КОТОРОЙ НЕТ: складывать сюда I_in НЕЛЬЗЯ. dIn УЖЕ ВКЛЮЧАЕТ
--  перелив от союзников (проверено в игре), поэтому свой перелив здесь
--  уже сидит внутри dIn.
--------------------------------------------------------------------------------

-- Есть ли накопленные дельты по своей армии. Пока их нет, публиковать
-- нечего: первый payload только заводит базу сравнения.
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
        -- данные те же: ни одна дельта не выросла
        return false
    end

    -- ---- шаг 1: копим дельты -------------------------------------------
    local logLines = {}
    local haveMine = false

    for armyIdx, cur in pairs(fresh) do
        local prv = lastRaw[armyIdx]
        if prv and cur
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

    -- тики, прошедшие с прошлого обработанного payload
    local dtSec = 0
    if lastTick ~= nil then
        local dtTicks = tickNow - lastTick
        accTicks = accTicks + dtTicks
        dtSec = dtTicks / GetSimTicksPerSecond()
    end
    lastTick = tickNow
    lastSignature = signature

    -- ДОХОД ИЗ ДВИЖКА усредняем по времени. Раньше здесь бралось мгновенное
    -- значение income и вычиталось среднее за окно, то есть величины
    -- описывали разные моменты. На практике это выглядело как "входящий
    -- 546.7 при полном хранилище 24000/24000".
    if dtSec > 0 then
        local okI, econI = pcall(GetEconomyTotals)
        if okI and type(econI) == 'table' then
            local freq = GetSimTicksPerSecond()
            accIncomeE = accIncomeE + econI.income.ENERGY * freq * dtSec
            accIncomeM = accIncomeM + econI.income.MASS * freq * dtSec
        end
    end

    -- границы запаса нашей армии за окно
    local mineNow = fresh[me]
    if mineNow and mineNow.estore and mineNow.mstore then
        if minStoreE == nil or mineNow.estore < minStoreE then minStoreE = mineNow.estore end
        if maxStoreE == nil or mineNow.estore > maxStoreE then maxStoreE = mineNow.estore end
        if minStoreM == nil or mineNow.mstore < minStoreM then minStoreM = mineNow.mstore end
        if maxStoreM == nil or mineNow.mstore > maxStoreM then maxStoreM = mineNow.mstore end
        if mineNow.emax ~= nil and mineNow.estore ~= nil then
            local headE = mineNow.emax - mineNow.estore
            if maxHeadE == nil or headE > maxHeadE then maxHeadE = headE end
        end
        if mineNow.mmax ~= nil then
            local headM = mineNow.mmax - mineNow.mstore
            if maxHeadM == nil or headM > maxHeadM then maxHeadM = headM end
        end
    end

    haveMine = HaveMine(acc, me)
    if not haveMine then return false end

    -- ---- шаг 2: окно ещё не набрано -------------------------------------
    if accTicks < WINDOW_TICKS then
        return false
    end

    local simFreq = GetSimTicksPerSecond()
    local sec = accTicks / simFreq
    if sec < 1 then
        return false
    end

    -- ---- шаг 3: считаем ------------------------------------------------
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

    ------------------------------------------------------------------
    -- ФИЗИЧЕСКОЕ ОГРАНИЧЕНИЕ, КОТОРОЕ МОЖНО ПРОВЕРИТЬ
    ------------------------------------------------------------------
    --
    -- Синхронизация отдаёт потолок хранилища: sim/score.lua:141-142,
    -- storage.maxEnergy и storage.maxMass. Если свободного места не было НИ
    -- РАЗУ за окно (maxHead <= 0), то физически нечего было принимать:
    -- полное хранилище перелив от союзников не впускает. Значит входящий
    -- обязан быть нулём, а ненулевое значение - ошибка расчёта, а не
    -- реальность.
    --
    -- Именно это и наблюдалось в командной игре 2026-10-05: полное хранилище
    -- с избытком, а мод показывает входящий и исходящий одновременно.
    --
    -- При нарушении входящий обнуляется, но сырое значение и все числа
    -- пишутся в лог. Гасить ошибку молча нельзя: непонятно, что именно
    -- не так, а лог для того и нужен.
    --
    -- Чего этот запрет НЕ доказывает: что формула исходящего неверна. Он
    -- говорит только то, что входящий в такой ситуации физически невозможен.
    -- Что в сумме остатков союзников перемешано «отдали» и «отдали мне» -
    -- см. комментарий к gE выше; это отдельный вопрос, и он виден по
    -- тому, что покажет этот лог.
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

    -- ---- шаг 4: своё производство ИЗ ДВИЖКА ---------------------------
    -- ВАЖНО: доход усреднён за ТО ЖЕ окно, что и входящий перелив.
    -- Раньше здесь стояло econ.income * simFreq - incRateE, где первое было
    -- мгновенным значением, а второе - средним за окно. Величины описывали
    -- разные моменты, и результат получался неверным.
    --
    -- income ВКЛЮЧАЕТ перелив от союзников (проверено в игре), поэтому
    -- входящий вычитается ровно один раз.
    local incomeRateE = accIncomeE / sec
    local incomeRateM = accIncomeM / sec
    local ownE = incomeRateE - incRateE
    local ownM = incomeRateM - incRateM

    -- ---- лог ------------------------------------------------------------
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

    -- ---- шаг 5: окно закрыто, копим заново ------------------------------
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

--------------------------------------------------------------------------------
-- КОЛБЭК СИНХРОНИЗАЦИИ
--------------------------------------------------------------------------------

local function OnScore(scoreData)
    -- колбэк зовётся изнутри игры без pcall, ловим всё здесь
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
        pcall(RemoveOnSyncHashedCallback, 'Score', CB_ID)
        LOG(PFX .. ': too many errors, sync callback removed, panel will stay empty')
    end
end

--------------------------------------------------------------------------------
-- ЗАПУСК
--------------------------------------------------------------------------------

local started = false

function Start()
    if started then return end
    started = true

    import('/lua/UserSync.lua')
    if type(AddOnSyncHashedCallback) ~= 'function' then
        LOG(PFX .. ': START FAILED - AddOnSyncHashedCallback missing')
        return
    end

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