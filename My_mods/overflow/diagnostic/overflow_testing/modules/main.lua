-- ============================================================================
--  Overflow Testing - ДИАГНОСТИЧЕСКИЙ мод. Только лог, никакой математики.
--  Версия 2. Правка: math.huge в LuaPlus не существует.
-- ============================================================================
--
--  ЗАЧЕМ
--
--  Проверяем, что игра синхронизирует на клиент полную экономику своей
--  армии и союзников, и устанавливаем смысл трёх вещей:
--
--    1) energyout.excess / massout.excess - заполняется ли вообще
--    2) energyin.total - входит ли туда перелив ОТ союзников
--    3) excess - растёт ли, когда у союзника кончилось место
--
--  Мод ничего не вычисляет и ничего не рисует. Только пишет в лог сырые
--  значения и разности счётчиков за последнюю синхронизацию.
--
--  ОТКУДА БЕРЁМ ДАННЫЕ
--
--  Не из currentScores! Штатный код /lua/ui/game/score.lua:712 обнуляет его
--  сразу после отрисовки, а штатный beat зарегистрирован на score.lua:137,
--  то есть раньше нашего OnCreateUI, и выполняется первым.
--
--  Используем штатный API синхронизации, /lua/UserSync.lua:39:
--
--      AddOnSyncHashedCallback(cb, 'Score', 'OverflowTest')
--
--  Вызывается на UserSync.lua:155-162, в цикле `for k, data in Sync`,
--  то есть РОВНО в момент прихода Sync.Score, и получает data = Sync.Score.
--  Это строка 155, а присваивание currentScores - строка 376.
--
--  Совместимость: SupremeScoreBoard2 перехватывает OnSync и читает
--  Sync.Score ПОСЛЕ оригинального OnSync (его hook/lua/UserSync.lua:13-15),
--  а наш колбэк срабатывает ВНУТРИ оригинала. Конфликта нет, отключать
--  SSB2 не нужно.
--
--  ВАЖНО: этот колбэк зовётся НАПРЯМУЮ, без pcall (UserSync.lua:158).
--  Ошибка внутри него сломает синхронизацию всей игры. Поэтому всё тело
--  обёрнуто в pcall. Отдельные ошибки не роняют мод сразу: первые три
--  печатаются с трассировкой, потом колбэк снимает сам себя.
--
--  ЗАПРЕЩЁННО В ЭТОМ ФАЙЛЕ (движок FAF):
--
--    * оператор #      - длина таблицы. Вместо него table.insert / pairs
--    * оператор %      - остаток от деления
--    * continue        - в Lua 5.1 нет такого слова
--    * math.huge       - НЕ СУЩЕСТВУЕТ, см. ниже
--    * локальные имена tag, name, index, count, value, type, end
--    * WaitSeconds внутри pcall - pcall это C-функция
--
--  ПРО math.huge - ровно то, на что упала версия 1:
--
--      main.lua(101): attempt to perform arithmetic on field `huge' (a nil value)
--
--  math.huge == nil, поэтому `-math.huge` это `-nil`. Подтверждено
--  комментарием разработчиков в самой игре,
--  nx2/lua/Projectile.lua:975:
--
--      Since `math.huge` does not exist (and does not cover the #IND case)
--
--  math.floor, math.abs, math.pi в игре используются сотни раз - а вот
--  math.huge нигде. Проверки бесконечности здесь просто убраны: счётчики
--  экономики бесконечными не бывают.
-- ============================================================================

-- Префикс строк лога. Не называем TAG - tag служебный идентификатор.
local PFX = 'OverflowTest'

-- Локализуем глобалы. Проверены по исходникам игры:
--   IsAlly, GetGameTimeSeconds       - sim/score.lua:298, ui/game/score.lua:197
--   AddOnSyncHashedCallback          - UserSync.lua:39
--   RemoveOnSyncHashedCallback       - UserSync.lua:47
local LOG                        = LOG
local GameTick                   = GameTick
local GetFocusArmy               = GetFocusArmy
local IsAlly                     = IsAlly
local GetEconomyTotals           = GetEconomyTotals
local GetGameTimeSeconds         = GetGameTimeSeconds
local AddOnSyncHashedCallback    = AddOnSyncHashedCallback
local RemoveOnSyncHashedCallback = RemoveOnSyncHashedCallback

-- Идентификатор колбэка. Должен быть уникальным, иначе мод затрёт чужой.
local CB_ID = 'OverflowTest'

-- Первый ли вывод. В первый раз разностей ещё нет.
local firstSample = true

-- Сколько раз данные реально обновились.
local nSyncSamples = 0

-- Сколько ошибок подряд было в колбэке. После NERR_LIMIT отключаемся.
local nErrors = 0
local NERR_LIMIT = 3

-- Подпись последнего выведенного Sync.Score. Синхронизация приходит каждый
-- бит, а данные пересобираются примерно раз в 2 секунды (sim/score.lua:2).
-- Чтобы в лог не сыпалось по 60 одинаковых строк в секунду, пишем только
-- когда содержимое реально изменилось.
local lastSignature = nil

-- Предыдущие значения счётчиков, по индексу армии, для разностей.
local prevCounters = {}

-- ---------------------------------------------------------------------------
--  ФОРМАТИРОВАНИЕ
-- ---------------------------------------------------------------------------

-- Отличаем nil (поля нет) от 0 (поле есть и равно нулю). Для excess это
-- принципиально: "всегда ноль" и "поля не существует" - разные выводы.
--
-- Спецификаторы в string.format разрешены, это не оператор остатка.
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

-- Безопасное чтение вложенного поля: t.a.b -> nil, если уровня нет.
-- Один уровень: field(t, 'energyin') ; два: field(t, 'energyin', 'total')
local function field(t, a, b)
    if type(t) ~= 'table' then return nil end
    local v = t[a]
    if b == nil then return v end
    if type(v) ~= 'table' then return nil end
    return v[b]
end

-- ---------------------------------------------------------------------------
--  СЧЁТЧИКИ ДЛЯ РАЗНОСТЕЙ
-- ---------------------------------------------------------------------------

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

-- ---------------------------------------------------------------------------
--  ОДНА АРМИЯ
-- ---------------------------------------------------------------------------

-- Отношение армии к нам: ME / ALLY / ENEM.
-- Направление аргументов как в игре: IsAlly(мояАрмия, проверяемая).
-- Сверяется с sim/score.lua:298.
-- pcall на всякий случай: если IsAlly споткнётся о нестандартный индекс,
-- потеряется одна метка в шапке, а не весь мод.
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

-- Собственная экономика движка, для сверки с синхронизацией.
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
    -- s.name, но name - служебное имя, поэтому в другую переменную
    local armyName = s.name or s.nickname or '?'

    local res = s.resources

    -- Для врагов игра шлёт только {general={}} (sim/score.lua:301).
    -- Это НЕ ошибка, это ожидаемое поведение. Фиксируем и идём дальше.
    if type(res) ~= 'table' then
        LOG(PFX .. ':   ' .. rel .. ' #' .. tostring(armyIdx) ..
            ' ' .. tostring(armyName) ..
            ' resources=nil  <- так и должно быть для врага')
        return
    end

    if armyIdx == me then
        dumpOwnEcon()
    end

    -- ВАЖНО: prv читается ДО saveCounters. saveCounters перезаписывает
    -- prevCounters[armyIdx], и если взять prv после, prv окажется тем же
    -- самым значением и все разности будут 0. На этом провалилась версия 2.
    local prv = prevCounters[armyIdx]
    local cur = saveCounters(armyIdx, res)

    -- ------------------------------------------------------------------
    --  СЫРЫЕ ЗНАЧЕНИЯ.  in = total / rate, затем reclaimed / reclaimRate;
    --  out = total / rate, затем excess;  st = stored / max
    -- ------------------------------------------------------------------
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

    -- ------------------------------------------------------------------
    --  РАЗНОСТИ ЗА ПОСЛЕДНУЮ СИНХронизацию.
    --  Это входные данные формулы
    --      G = P + I_in - E - W - dS
    --  Саму G здесь НЕ считаем - это делаем после разбора логов.
    -- ------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
--  СЧИТЫВАНИЕ СОСТАВА Sync.Score
-- ---------------------------------------------------------------------------

-- Возвращает: сколько меня, сколько союзников, сколько врагов,
-- и сколько записей вообще имеют поле resources.
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

-- Отсортированные индексы армий. Стабильный порядок вывода.
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

-- Подпись содержимого: ключевые числа ВСЕХ армий.
-- Берём не только свою армию: если у своей нет resources, подпись по ней
-- была бы постоянной и мод почти не писал бы. Союзники нужны и здесь.
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

-- ---------------------------------------------------------------------------
--  ОСНОВНОЙ ДАМП
-- ---------------------------------------------------------------------------

local function DumpScore(scoreData)
    if type(scoreData) ~= 'table' then
        LOG(PFX .. ': Sync.Score пришёл не-таблицей: ' .. tostring(scoreData))
        return
    end

    local sig = makeSignature(scoreData)
    if sig == lastSignature then
        -- Данные не пересобирались - молчим, чтобы лог оставался читаемым
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

    -- Каждая армия - в своём pcall. Одна плохая армия не должна убивать
    -- весь вывод: ради остальных и затевался мод.
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

-- ---------------------------------------------------------------------------
--  КОЛБЭК
-- ---------------------------------------------------------------------------

local function OnScore(scoreData)
    -- HashSync-колбэк зовётся напрямую (UserSync.lua:158-160), БЕЗ pcall.
    -- Ошибка здесь поедет по всей синхронизации игры. Поэтому pcall внутри,
    -- и он синхронный: WaitSeconds не нужен и недопустим.
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

-- ---------------------------------------------------------------------------
--  ЗАПУСК
-- ---------------------------------------------------------------------------

local started = false

-- Синхронная часть: только регистрация колбэка, ни одного ожидания.
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

-- Сторож: если за 40 секунд данные не пришли, это само по себе результат
-- эксперимента и его надо явно зафиксировать.
-- ВНЕ pcall - здесь есть ожидание.
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

-- ---------------------------------------------------------------------------
--  МЕТКА ФАЗЫ ДЛЯ РУЧНОГО ТЕСТА
-- ---------------------------------------------------------------------------

-- Одна игра, три фазы - лог делить нечем. Метка пишется прямо в тот же
-- лог, поэтому разбор получается однозначным.
--
-- Вызов из консоли игры (F10):
--
--   UI_Lua import('/mods/overflow_testing/modules/main.lua').Mark("PHASE 2")
--
-- Ничего не вычисляет, только пишет. Ждать нечего.
function Mark(text)
    LOG(PFX .. ': ############ ' .. tostring(text) ..
        ' ############  t=' .. num(GetGameTimeSeconds()) ..
        's  tick=' .. tostring(GameTick()))
end

function OnCreateUI()
    -- Никакого ожидания здесь: регистрация должна пройти раньше первого
    -- прихода синхронизации.
    local ok, err = pcall(Start)
    if not ok then
        LOG(PFX .. ': start FAILED: ' .. tostring(err))
        return
    end

    ForkThread(Watchdog)
end
