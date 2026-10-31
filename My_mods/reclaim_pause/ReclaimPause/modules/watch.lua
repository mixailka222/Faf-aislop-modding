-- ReclaimPause - модуль слежения за хранилищами.
--
-- ЗАДАЧА. Пока хранилище массы почти полно, реклейм бессмысленен: массу
-- некуда девать, лишнее уходит союзникам или сгорает. Мод ставит
-- реклеймящих инженеров на паузу и снимает ее, как только игрок снова
-- начал тратить массу.
--
-- УСЛОВИЕ ПАУЗЫ. Раньше мод смотрел только на массу, и это
-- было ошибкой: реклейм может давать энергию (сгоревшие генераторы), а
-- энергия может кончиться при полном хранилище массы. На игре это
-- подтвердилось - 2026-10-04 в логе энергия падала с 3400 до 500, пока
-- масса стояла на 100 процентах. Теперь пауза разрешена только когда
-- масса полна И энергии не меньше порога.
--
-- ПОЧЕМУ ПАУЗА, А НЕ СБРОС ПРИКАЗА. В sim/Unit.lua:571-609 при паузе
-- поле EntityBeingReclaimed НЕ обнуляется: останавливаются только
-- эффекты и звук. Снятие паузы (OnUnpaused) возобновляет реклейм того же
-- объекта. Для инженеров на атак-мув это отдельно проверено в игре
-- 2026-10-04: после снятия паузы инженер продолжает маршрут и реклейм.
--
-- КАК НАХОДИМ ИНЖЕНЕРОВ. Отдельной функции движка "дай всех юнитов" НЕТ.
-- GetUnits() в игровом коде отсутствует: функции с таким именем есть
-- только у сторонних модов (UMT.Units.Get). Единственный штатный способ -
-- выделить всех и прочитать GetSelectedUnits(). Так делает мод ui mod
-- tools, modules/units.lua:33-42. Поэтому здесь скрытое выделение, и
-- обход делается РЕДКО: только когда хранилище полно, и не чаще раза в
-- RESCAN_SEC секунд. В остальное время выделение не трогается вообще.
--
-- ВАЖНО. Обход инженеров ТОЛЬКО ДОБАВЛЯЕТ новых. Никто не снимается с паузы
-- из-за того, что его не оказалось в обходе: иначе пауза снималась бы с живых
-- инженеров.
-- Освобождение проверяется напрямую по каждому юниту, у которого уже
-- есть приказ под рукой, - это не стоит обращения к выделению.
--
-- ЭКСПОРТ. Функции объявляются глобальными именами. Возврат return {...}
-- движок FAF отбрасывает (import.lua:61,171), поэтому его писать нельзя.

local GameMain = import('/lua/ui/game/gamemain.lua')
local CommandMode = import('/lua/ui/game/commandmode.lua')

-- ВАЖНО про модули FAF. У каждого файла мода своё окружение, и присваивание
-- "глобального" имени попадает В ТАБЛИЦУ МОДУЛЯ, а не в общий _G.
-- Поэтому соседний файл не видит наших имён как глобальных - он увидит
-- ошибку "access to nonexistent global variable". Правильный способ - самому
-- импортировать нужный файл и обращаться к тому, что вернул import():
--   local Settings = import('.../settings.lua')
--   Settings.Settings.ReclaimPauseLoadSettings()
-- Без этого settings.lua загружается, хук радуется, а
-- ReclaimPauseStart() падал на первой же строке.
local okSet, Settings = pcall(import, '/mods/ReclaimPause/modules/settings.lua')

local PFX = 'ReclaimPause: '
local SCAN_SEC = 1        -- как часто смотрим хранилища и состояние инженеров
-- частота обхода берётся из настроек (rescanSec), а не из константы:
local rescanSec = 3
-- Первые секунды матча обход не делаем НИКОГДА: игрок ставит командира
-- и строит базу, выделение ему важно, а торопиться некуда. Настраивается
-- через startGrace в окне настроек.

-- Числовые коды приказов, sim/commands/shared.lua:280-360. Сверены со
-- справочником референс-мода, расхождений нет.
local BY_ID = {
    [19] = 'Reclaim',
    [16] = 'Patrol',
    [18] = 'FormPatrol',
    [35] = 'AggressiveMove',
    [36] = 'FormAggressiveMove',
}

-- Приказы, которые мод ведёт.
local MANAGED = {
    Reclaim = true,
    reclaim = true,
    AggressiveMove = true,
    FormAggressiveMove = true,
    Patrol = true,
    FormPatrol = true,
}

--------------------------------------------------------------------------------
-- СОСТОЯНИЕ
--------------------------------------------------------------------------------

local running = false
local iterNo = 0
local switchIter = 0
local logTick = 0
local rescanIter = 0
local abortIter = 0
local abortCount = 0
local abortLogTick = 0
local engineerCount = 0
local holding = false      -- сейчас мод держит инженеров на паузе
local held = {}            -- id -> unit, кого мод поставил на паузу
local heldAt = {}          -- id -> номер прохода, на котором поставили
local skipUntil = {}       -- id -> номер прохода, до какого юнита не трогаем
local lowSinceIter = 0     -- с какого прохода условие снятия держится (0 = нет)
local posLast = {}         -- id -> {x, z} последняя замеренная позиция
local posIter = 0          -- проход последнего замера позиций
local posMoved = 0         -- сколько удерживаемых юнитов сдвинулось
local posTotal = 0         -- сколько всего удерживаемых проверено
local posShift = 0         -- наибольший сдвиг, в игровых единицах
local probeDoneIter = 0     -- проход, в котором прибор уже мерил

-- ИЗМЕРЕНИЕ ПОРОГА ИГРЫ: при каком заполнении хранилища игра сама
-- перестаёт отдавать реклейм инженерам на атак-муве.
--
-- Одна таблица, а не две переменные: у TickOnce предел 32 upvalue, и
-- лишняя локальная переменная его упирает в стену.
local gstop = {
    mass = 0,      -- заполнение хранилища на текущем проходе
    fresh = nil,   -- последний обход инженеров: id -> unit
    pos = {},      -- id -> {x, z}, последняя замеренная позиция
    rec = 0,       -- скорость реклейма в секунду (из счётчика игры)
    recPrev = nil, -- предыдущее значение econ.reclaimed.MASS
    recIter = 0,   -- проход, на котором взяли предыдущее значение
    logRec = 0,    -- счётчик компактной строки замера REC
}

-- Разбор, почему инженер НЕ попал под паузу. Без него на вопрос
-- "почему они не встали" приходится отвечать догадками.
--
-- Три счётчика, а не три переменные: у TickOnce жёсткий предел в 32
-- upvalue, и три отдельных локальных переменных его упирали в стену.
-- Таблица стоит один upvalue вместо трёх.
local why = {
    skip = 0,      -- игрок снял паузу вручную, мод его не трогает
    player = 0,    -- уже на паузе, но не нашей
    other = 0,     -- приказ не наш, и не пустой
}

--------------------------------------------------------------------------------
-- ЧТЕНИЕ ПРИКАЗА
--
-- Собственный код игры читает очередь как unit:GetCommandQueue()[1].type
-- (ui/game/construction.lua:1183, ui/notify/enhancementqueue.lua:60).
-- Поле типа бывает числом или строкой - учитываем оба случая, как это
-- делает референс-мод (queue.lua:21-31).
--------------------------------------------------------------------------------

local function OrderKind(entry)
    if type(entry) ~= 'table' then
        return nil
    end
    local raw = entry.commandType or entry.CommandType or entry.type or entry.Type
    if type(raw) == 'number' then
        return BY_ID[raw]
    end
    if type(raw) == 'string' then
        return raw
    end
    return nil
end

-- Атак-мув часто приходит не как отдельный тип, а как Script-приказ с
-- именем задачи внутри: так делает FAF (core.lua:3784-3798 референс-мода).
local function EntryIsManaged(entry)
    local kind = OrderKind(entry)
    if not kind then
        return false
    end
    if MANAGED[kind] then
        return true
    end
    if kind == 'Script' then
        local params = entry.LuaParams or entry.luaParams or entry.params
        if type(params) == 'table' then
            local task = params.TaskName or params.taskName
            local ability = params.AbilityName or params.abilityName
            if task == 'AttackMove' or ability == 'AttackMove' then
                return true
            end
            if task == 'Patrol' or ability == 'Patrol' then
                return true
            end
        end
    end
    return false
end

-- Возвращает вид приказа и признак "мод им интересуется". Вид приказа
-- нужен для лога: без него невозможно понять, почему инженера отпустили.
local function FrontKind(unit)
    local ok, queue = pcall(function() return unit:GetCommandQueue() end)
    if not ok or type(queue) ~= 'table' then
        return 'queue-error', false
    end
    local first = queue[1]
    if first == nil then
        return 'empty', false
    end
    local kind = OrderKind(first)
    if not kind then
        return 'unknown-type', false
    end
    return kind, EntryIsManaged(first)
end

local function FrontIsManaged(unit)
    local _, managed = FrontKind(unit)
    return managed
end

--------------------------------------------------------------------------------
-- ПРОВЕРКИ ЮНИТА. Каждая обёрнута в pcall: юнит мог умереть между
-- проверкой и вызовом.
--------------------------------------------------------------------------------

local function IsMine(unit)
    local ok, res = pcall(function() return unit:GetArmy() == GetFocusArmy() end)
    if not ok then
        return false
    end
    return res and true or false
end

local function HasCategory(unit, cat)
    local ok, res = pcall(function() return unit:IsInCategory(cat) end)
    if not ok or not res then
        return false
    end
    return true
end

local function IsAlive(unit)
    local ok, res = pcall(function() return unit:IsDead() end)
    if not ok then
        return false
    end
    return not res
end

-- UserUnit has no IsUnitState, that method belongs to the sim layer. A builder
-- has the unfinished unit in focus. A finished unit in focus means other work,
-- for example reclaiming that unit.
local function IsBuilding(unit)
    local ok, res = pcall(function()
        local focus = unit:GetFocus()
        return focus ~= nil and focus:GetFractionComplete() < 1
    end)
    if not ok then
        LOG(PFX .. 'IsBuilding FAILED: ' .. tostring(res))
        return false
    end
    return res
end

-- GetIsPaused принимает СПИСОК юнитов, не один юнит.
-- ЧТЕНИЕ СОСТОЯНИЯ ПАУЗЫ.
--
-- GetIsPaused(list) отвечает на вопрос "хотя бы один в списке на паузе".
-- Для проверки одного юнита это неудобно: таблица { unit } создаётся
-- заново для КАЖДОГО удерживаемого юнита КАЖДУЮ секунду. Движок же имеет
-- одиночный вариант - GetIsPausedOfUnit(unit), и он применяется на UI
-- буквально в игре, ui/game/orders.lua:323:
--
--   if not GetIsPausedOfUnit(silo) then
--
-- ПОЧЕМУ ЧЕРЕЗ pcall. Обращаться к имени, которого нет в сборке движка,
-- нельзя: поиск глобала идёт через метаметод таблицы модуля
-- (lua/system/import.lua:24-26, __index = _G), а на _G висит метаметод,
-- вызывающий error() (lua/system/config.lua:56-61). То есть упоминание
-- отсутствующей функции - это ИСКЛЮЧЕНИЕ, а не nil. Поэтому проверка
-- существования сама идёт через pcall, результат кэшируется.
--
-- Если одиночной функции нет - молча уходим на старый путь, мод работает
-- как раньше. Ошибка невозможна: всё под pcall.
local hasPausedOfUnit = nil   -- nil = ещё не проверяли

local function ProbePausedOfUnit()
    local ok, fn = pcall(function() return GetIsPausedOfUnit end)
    hasPausedOfUnit = (ok and type(fn) == 'function') and true or false
    LOG(PFX .. 'GetIsPausedOfUnit ' ..
        (hasPausedOfUnit and 'available' or 'NOT available, using GetIsPaused'))
end

local function IsCurrentlyPaused(unit)
    if hasPausedOfUnit == nil then
        ProbePausedOfUnit()
    end

    if hasPausedOfUnit then
        local okU, resU = pcall(function() return GetIsPausedOfUnit(unit) end)
        if okU and resU ~= nil then
            return resU and true or false
        end
        -- функция есть, но не сработала: один раз откатываемся назад
        hasPausedOfUnit = false
        LOG(PFX .. 'GetIsPausedOfUnit failed, falling back to GetIsPaused')
    end

    local box = { unit }
    local ok, res = pcall(function() return GetIsPaused(box) end)
    if not ok or res == nil then
        -- не смогли прочитать: считаем, что пауза есть, чтобы не слать
        -- повторные команды паузы подряд
        return true
    end
    return res and true or false
end

--------------------------------------------------------------------------------
-- СКРЫТЫЙ ОБХОД ИНЖЕНЕРОВ
--
-- UISelectionByCategory - штатная функция движка, сама игра так выделяет
-- инженеров горячей клавишей (lua/keymap/misckeyactions.lua:615). Второй
-- параметр addToSelection = false означает "заменить выделение", третий
-- onScreenOnly = false - "все, не только на экране".
--
-- Выделение обязательно возвращается, даже если что-то упало: иначе игрок
-- останется с кучей выделенных инженеров.
--------------------------------------------------------------------------------

-- If the check fails, the selection stays untouched: a missed pass costs one
-- second, a restarted command mode costs the player a build order.
local function PlayerInCommandMode()
    local ok, res = pcall(CommandMode.InCommandMode)
    if not ok then
        LOG(PFX .. 'InCommandMode FAILED: ' .. tostring(res))
        return true
    end
    return res
end

local function CollectEngineers(picked)
    local found = {}
    local n = 0
    local list = picked or {}
    for i = 1, table.getn(list) do
        local unit = list[i]
        if IsMine(unit) and IsAlive(unit) and not IsBuilding(unit) then
            if HasCategory(unit, 'ENGINEER') and not HasCategory(unit, 'COMMAND') then
                local id = unit:GetEntityId()
                found[id] = unit
                n = n + 1
            end
        end
    end
    return found, n
end

-- Скрытое выделение - единственный способ получить список инженеров, но
-- оно очень легко сбивает выделение игрока. На игре 2026-10-05 игрок
-- пожаловался, что мод снимает выделение с командира при старте. Разбор:
--
-- 1) RestoreCommandMode(true) - лишний аргумент. commandmode.lua:243-250
--    показывает, что он сбрасывает issuedOneCommand, а сам StartCommandMode
--    ПЕРЕЗАПУСКАЕТ режим команд. Мы не имеем права трогать состояние, которое
--    не меняли. Вызываем без аргументов.
-- 2) Если у игрока активен режим команд, обход вообще не делаем: кэшировать
--    и перезапускать чужой режим - гарантированная помеха.
-- 3) Возвращаем выделение и ПРОВЕРЯЕМ, что вернулось. Если не совпало -
--    пишем в лог, иначе о такой проблеме узнаём только от игрока.
local function WithAllEngineers(callback)
    if PlayerInCommandMode() then
        return false
    end

    local saved = nil
    local beforeN = 0
    local ok, err = pcall(function()
        CommandMode.CacheAndClearCommandMode()
        GameMain.SetIgnoreSelection(true)
        saved = GetSelectedUnits() or {}
        beforeN = table.getn(saved)
        UISelectionByCategory('ENGINEER', false, false, false, false)
        callback(GetSelectedUnits() or {})
    end)
    if saved then
        pcall(function() SelectUnits(saved) end)
    end
    pcall(function() GameMain.SetIgnoreSelection(false) end)
    pcall(function() CommandMode.RestoreCommandMode() end)
    if not ok then
        LOG(PFX .. 'WithAllEngineers FAILED: ' .. tostring(err))
        return false
    end

    local okSel, after = pcall(function() return GetSelectedUnits() or {} end)
    if okSel and beforeN ~= table.getn(after) then
        LOG(PFX .. 'WARNING: selection NOT restored: was ' ..
            tostring(beforeN) .. ' unit(s), now ' .. tostring(table.getn(after)))
    end
    return true
end

local function EnsureEngineers(force)
    if not force and (iterNo - rescanIter) * SCAN_SEC < rescanSec then
        return nil
    end
    local box = {}
    local ok = WithAllEngineers(function(picked)
        box.found, box.n = CollectEngineers(picked)
    end)
    rescanIter = iterNo
    if not ok then
        return nil
    end
    return box.found, box.n
end

--------------------------------------------------------------------------------
-- ПРИМЕНЕНИЕ ПАУЗЫ
--------------------------------------------------------------------------------

-- ПАУЗОЙ ФЛАГОМ. И только флагом.
--
-- Разбор двух механизмов, проведённый на игре 2026-10-05 и 2026-10-06.
--
-- SetPaused(units, bool) - штатная функция, её же использует сама игра для
-- клавиши паузы (ui/game/construction.lua:1884). Идемпотентна: true ставит,
-- false снимает, повторный вызов ничего не ломает.
--
--   + ПРИКАЗ СОХРАНЯЕТСЯ. Игрок проверил: инженер на атак-муве, поставленный
--     на паузу сразу после выхода с завода, доходит до точки, стоит там и
--     НЕ теряет приказ. Снял паузу - продолжил реклеймить.
--   + РЕКЛЕЙМ ОСТАНАВЛИВАЕТСЯ, то есть цель мода достигнута.
--   - Инженер продолжает идти к точке. Это НЕ беда: дойдя, он останавливается
--     и ждёт. Так же ведёт себя штатная пауза игры, то есть мод здесь не хуже
--     встроенного поведения.
--
-- IssueUnitCommand(list, 'Pause') - команда. Проверено и отброшено:
--   - очередь приказов СНОСИТ. Приказ атак-мув теряется, а это ровно то,
--     ради чего мод затевался. Игрок подтвердил вручную: флаг сохраняет
--     приказ, команда - нет.
--   - как переключатель работает неверно. Команда 'Pause' должна
--     переключать состояние, но по факту состояние расходится с
--     GetIsPaused: мод отпускал инженеров, рассчитывая снять паузу, а они
--     оказывались поставлены на паузу, и следующий проход их пропускал.
--     В логе это выглядело как "найдено 10 инженеров, на паузу поставлено 0".
--
-- Значит команда паузы непригодна ни в чём: и приказ теряет, и состояние
-- путает. Механизм удалён целиком, настройки hardPause больше нет.
local function PauseUnits(list, n)
    if n == 0 then
        return
    end
    local okS, errS = pcall(function() SetPaused(list, true) end)
    if not okS then
        LOG(PFX .. 'SetPaused(true) FAILED: ' .. tostring(errS))
    end
end

local function ResumeUnits(list, n)
    if n == 0 then
        return
    end
    local okS, errS = pcall(function() SetPaused(list, false) end)
    if not okS then
        LOG(PFX .. 'SetPaused(false) FAILED: ' .. tostring(errS))
    end
end

-- ОБРЫВ МАРШРУТА.
--
-- Флаговая пауза останавливает РЕКЛЕЙМ, но не ДВИЖЕНИЕ: инженер на
-- атак-муве продолжает идти к точке и там встаёт. Формально это безвредно,
-- приказ сохраняется, но выглядит как поломка.
--
-- В игре есть ВСТРОЕННАЯ команда, которая останавливает движение и НЕ трогает
-- очередь приказов: sim/commands/abort-navigation.lua
--
--   function AbortNavigation(units, doPrint)
--       local navigator = unit:GetNavigator()
--       navigator:AbortMove()
--       unit:RefocusAssisters()
--   end
--
-- Её докстринг прямо про наш случай: "For engineers that are on a patrol or
-- an attack move the engineer can start reclaiming from further away".
-- Это штатная функция с горячей клавишей игрока, см.
-- ui/keymap/misckeyactions.lua:538-540:
--
--   AbortNavigation = function()
--       SimCallback({ Func = 'AbortNavigation', Args = {} }, true)
--   end
--
-- SimCallback с признаком true применяется к ТЕКУЩЕМУ ВЫДЕЛЕНИЮ, поэтому
-- нужные юниты надо на секунду выделить и вернуть выделение обратно. Тот же
-- приём, что и при обходе инженеров.
--
-- Итог: флаг останавливает реклейм, обрыв маршрута останавливает движение,
-- приказ атак-мув остаётся в очереди в обоих случаях.
local function AbortMove(list, n)
    if n == 0 then
        return
    end
    if not Settings.ReclaimPauseCfg.abortMove then
        return
    end
    if PlayerInCommandMode() then
        return
    end
    local saved = nil
    local beforeN = 0
    local ok, err = pcall(function()
        CommandMode.CacheAndClearCommandMode()
        GameMain.SetIgnoreSelection(true)
        saved = GetSelectedUnits() or {}
        beforeN = table.getn(saved)
        SelectUnits(list)
        SimCallback({ Func = 'AbortNavigation', Args = {} }, true)
    end)
    if saved then
        pcall(function() SelectUnits(saved) end)
    end
    pcall(function() GameMain.SetIgnoreSelection(false) end)
    pcall(function() CommandMode.RestoreCommandMode() end)
    if not ok then
        LOG(PFX .. 'AbortMove FAILED: ' .. tostring(err))
        return
    end
    -- Считаем обрывы и печатаем их раз в 10 штук. Иначе по логу нельзя
    -- понять, работает обрыв вообще или нет: инженер с приказом идёт к
    -- точке либо потому, что обрыва не было, либо потому, что приказ
    -- восстановился после него.
    -- Раз в десять обрывов, а не по модулю: оператор '%' движок не
    -- поддерживает.
    abortCount = abortCount + 1
    abortLogTick = abortLogTick + 1
    if abortLogTick >= 10 then
        abortLogTick = 0
        LOG(PFX .. 'abort issued x' .. tostring(abortCount) ..
            ' last for ' .. tostring(n) .. ' unit(s)')
    end
    local okSel, after = pcall(function() return GetSelectedUnits() or {} end)
    if okSel and beforeN ~= table.getn(after) then
        LOG(PFX .. 'WARNING: selection NOT restored after abort: was ' ..
            tostring(beforeN) .. ', now ' .. tostring(table.getn(after)))
    end
end

-- Сколько секунд инженер провисел на паузе. -1 если неизвестно.
local function HeldSecs(id)
    local at = heldAt[id]
    if at == nil then
        return -1
    end
    return (iterNo - at) * SCAN_SEC
end

-- Кого игрок снял с паузы вручную - не трогаем, но НЕ НАВСЕГДА.
--
-- Теперь это только страховка на случай, когда приказ прочитать нельзя.
-- Раньше флаг ставился навсегда, и одно случайное нажатие исключало
-- инженера до конца матча: он оставался с приказом, а мод его не видел.
-- Теперь помним только на skipSec секунд.
local function IsSkipped(id)
    local untilNo = skipUntil[id]
    if untilNo == nil then
        return false
    end
    if iterNo >= untilNo then
        skipUntil[id] = nil
        return false
    end
    return true
end

-- ПРИБОР: СТОИТ ЛИ ИНЖЕНЕР НА МЕСТЕ.
--
-- Реклейм прибор не меряет: Sync.Reclaim содержит только пропы, изменившиеся за
-- последнюю синхронизацию, и живой признак из него не собрать. Скорость реклейма
-- даёт счётчик игры econ.reclaimed, см. TickOnce.
--
-- Вопрос, который закрывает лог: останавливает ли флаг SetPaused ДВИЖЕНИЕ.
-- От ответа зависит судьба настройки abortMove:
--   - если флаг движение НЕ останавливает - обрыв обязателен, иначе
--     инженер уедет к точке, а "рывки" это окно между обрывами;
--   - если флаг движение ОСТАНАВЛИВАЕТ - обрыв не нужен вовсе, и рывки
--     уходят вместе с ним.
--
-- Ответ берётся не на глаз, а из координат: раз в posProbeSec секунд
-- меряем положение удерживаемых юнитов и считаем, кто сдвинулся.
--
-- GetPosition() у UserUnit подтверждён игровым кодом:
-- ui/game/selection.lua:494 (units[i]:GetPosition() по выделению),
-- ui/game/unittext.lua:19 и :78 (GetUnitById(...):GetPosition()).
-- Координаты это Vector, где X = [1] и Z = [3] - подтверждено тем, что
-- sim/Prop.lua:36,50 читает CachePosition[1] и CachePosition[3].
-- В пределах одного прохода прибор меряет ОДИН раз.
local function RunProbe()
    if probeDoneIter == iterNo then
        return
    end
    probeDoneIter = iterNo
    local moved = 0
    local total = 0
    local far = 0
    for id, unit in pairs(held) do
        local okP, p = pcall(function() return unit:GetPosition() end)
        if okP and type(p) == 'table' and type(p[1]) == 'number'
            and type(p[3]) == 'number' then
            total = total + 1
            local prev = posLast[id]
            if prev then
                local dx = p[1] - prev.x
                local dz = p[3] - prev.z
                local dist = math.sqrt(dx * dx + dz * dz)
                if dist > 0.5 then
                    moved = moved + 1
                end
                if dist > far then
                    far = dist
                end
            end
            -- Именно именованные поля. Конструктор { p[1], p[3] } создал бы
            -- таблицу с ключами 1 и 2, и prev.z был бы nil: такую ошибку
            -- поймал только юнит-тест, в игре она выглядела бы как молчащий
            -- прибор.
            posLast[id] = { x = p[1], z = p[3] }
        end
    end
    -- забываем о тех, кого уже отпустили
    for id in pairs(posLast) do
        if held[id] == nil then
            posLast[id] = nil
        end
    end
    posMoved = moved
    posTotal = total
    posShift = far
end

local function HeldCount()
    local n = 0
    for _ in pairs(held) do
        n = n + 1
    end
    return n
end

--------------------------------------------------------------------------------
-- ОСВОБОЖДЕНИЕ ВСЕХ
--------------------------------------------------------------------------------

local function ReleaseAll(why)
    local list = {}
    local n = 0
    for id, unit in pairs(held) do
        if IsCurrentlyPaused(unit) then
            list[n + 1] = unit
            n = n + 1
        end
    end
    ResumeUnits(list, n)
    local wasN = HeldCount()
    held = {}
    skipUntil = {}
    if wasN > 0 then
        LOG(PFX .. 'released ' .. tostring(wasN) .. ' engineer(s): ' .. tostring(why))
    end
end

--------------------------------------------------------------------------------
-- ЧТЕНИЕ ХРАНИЛИЩ
--------------------------------------------------------------------------------

local function FillOf(econ, res)
    if type(econ.maxStorage) ~= 'table' or type(econ.stored) ~= 'table' then
        return nil
    end
    local mx = econ.maxStorage[res]
    local st = econ.stored[res]
    if type(mx) ~= 'number' or type(st) ~= 'number' or mx <= 0 then
        return nil
    end
    return st / mx
end

--------------------------------------------------------------------------------
-- ОСНОВНОЙ ШАГ
--------------------------------------------------------------------------------

-- РУЧНАЯ ПРОВЕРКА по горячей клавише.
--
-- Главный инструмент отладки: показывает, что мод видит ПРЯМО СЕЙЧАС, и
-- называет причину, по которой он не сработал. Без неё приходится ждать,
-- пока хранилище дойдёт до порога, а это минуты матча.
local function Explain(cfg, massFill, energyFill)
    if not cfg.enabled then
        return 'MOD-DISABLED'
    end
    if massFill < cfg.highMass / 100 then
        return 'WAIT-MASS ' .. string.format('%.0f', massFill * 100) .. '%' ..
            ' (need ' .. string.format('%.0f', cfg.highMass) .. '%)'
    end
    if energyFill < cfg.energyMin / 100 then
        -- Оба числа обязательны. Раньше здесь печатался только требуемый
        -- порог, и по строке 'WAIT-ENERGY (need 50%)' нельзя было понять
        -- главное: масса давно выше порога, и паузу задерживает энергия.
        -- Игрок решил, что мод неправильно считает порог по массе.
        return 'WAIT-ENERGY ' .. string.format('%.0f', energyFill * 100) .. '%' ..
            ' (need ' .. string.format('%.0f', cfg.energyMin) .. '%)' ..
            ', mass ' .. string.format('%.0f', massFill * 100) .. '%' ..
            ' of ' .. string.format('%.0f', cfg.highMass) .. '% - mass OK'
    end
    return 'THRESHOLDS-OK'
end

-- Строка прибора для лога. Прибор выключен или мод никого не держит - пишем
-- pos=off, потому что posMoved=0/0 читается как "никто не двигался", а на самом
-- деле позиции не мерили вообще. Разница важна при разборе лога.
local function ProbeLine(probeSec)
    if probeSec == nil or probeSec <= 0 or posTotal == 0 then
        return 'pos=off'
    end
    return 'posMoved=' .. tostring(posMoved) .. '/' .. tostring(posTotal) ..
        ' posShift=' .. string.format('%.1f', posShift)
end

-- ПОЧЕМУ МЫ ВСЁ ЕЩЁ ДЕРЖИМ. Отдельная строка: без неё в логе
-- не видно, ждём мы положенного срока или условие уже выполнено.
local function ExplainHold(cfg, massFill, holdSec)
    if not holding then
        return 'not-holding'
    end
    if massFill > cfg.lowMass / 100 then
        return 'mass-above-low'
    end
    local left = cfg.releaseHoldSec - holdSec
    if left < 0 then
        left = 0
    end
    return 'release-in ' .. tostring(math.floor(left)) .. 's'
end

function ReclaimPauseForceCheck()
    Settings.ReclaimPauseLoadSettings()
    local cfg = Settings.ReclaimPauseCfg

    local okE, econ = pcall(function() return GetEconomyTotals() end)
    if not okE or type(econ) ~= 'table' then
        LOG(PFX .. 'CHECK: economy unavailable')
        return
    end
    local massFill = FillOf(econ, 'MASS') or 0
    local energyFill = FillOf(econ, 'ENERGY') or 1

    local got, n = EnsureEngineers(true)

    LOG(PFX .. 'CHECK mass=' .. string.format('%.1f', massFill * 100) .. '%' ..
        ' energy=' .. string.format('%.1f', energyFill * 100) .. '%' ..
        ' needMass=' .. tostring(cfg.highMass) ..
        ' needEnergy=' .. tostring(cfg.energyMin) ..
        ' engineersFound=' .. tostring(got and n or 0) ..
        ' held=' .. tostring(HeldCount()) ..
        ' verdict=' .. Explain(cfg, massFill, energyFill) ..
        ' | ' .. Settings.ReclaimPauseSettingsLine())
end

-- ПЕРИОДИЧЕСКАЯ СТРОКА ЛОГА.
--
-- Вынесена из TickOnce не ради красоты: у Lua жёсткий предел в 32 upvalue
-- на функцию, и TickOnce дошёл до 31. Добавление одной переменной состояния
-- ломало бы файл ЦЕЛИКОМ, причём ошибкой времени компиляции в игре.
-- Логика вынесения - обычная: переменные состояния уезжают вместе с кодом,
-- который их использует.
--
-- Вердикт и прибор пишем ВСЕГДА: игрок не обязан знать про горячую
-- клавишу, чтобы понять, работает мод или нет.
local function PeriodicLog(cfg, massFill, energyFill, holdSec, probeSec,
    movN, movM, movFar, rec)
    logTick = logTick + 1
    -- У порога пишем чаще. Именно в этом окне решается, кто кого обгонит:
    -- мод или игра. При редком логе момент остановки реклейма просто не
    -- попадает в строку, и потом нечего разбирать.
    local logEvery = 15
    if massFill >= cfg.lowMass / 100 then
        logEvery = 5
    end
    if logTick < logEvery then
        return
    end
    logTick = 0
    -- Приводим прибор в актуальное состояние ПЕРЕД записью строки.
    -- Раньше прибор срабатывал раз в probeSec секунд, а строка печаталась
    -- раз в 15 проходов, и в строке оказывались числа из прошлого замера:
    -- в логе встречалось held=0 при posMoved=0/12. Для разбора момента,
    -- когда игра остановила реклейм, отставание недопустимо.
    if probeSec > 0 then
        RunProbe()
    end
    LOG(PFX .. 'mass=' .. string.format('%.1f', massFill * 100) .. '%' ..
        ' energy=' .. string.format('%.1f', energyFill * 100) .. '%' ..
        ' engineers=' .. (engineerCount >= 0 and tostring(engineerCount) or '?') ..
        -- Скорость реклейма из счётчика самой игры. Это ПРЯМОЙ признак
        -- "реклеймят ли сейчас", в отличие от mov, который говорит
        -- только "идут ли".
        ' rec=' .. string.format('%.0f', rec) ..
        ' mov=' .. tostring(movN) .. '/' .. tostring(movM) ..
        ' far=' .. string.format('%.1f', movFar) ..
        ' held=' .. tostring(HeldCount()) ..
        ' verdict=' .. Explain(cfg, massFill, energyFill) ..
        ' hold=' .. ExplainHold(cfg, massFill, holdSec) ..
        ' ' .. ProbeLine(probeSec) ..
        ' why=skip:' .. tostring(why.skip) ..
        ' player:' .. tostring(why.player) ..
        ' other:' .. tostring(why.other) ..
        ' | ' .. Settings.ReclaimPauseSettingsLine())
end

local function TickOnce()
    local okE, econ = pcall(function() return GetEconomyTotals() end)
    if not okE or type(econ) ~= 'table' then
        return
    end
    local massFill = FillOf(econ, 'MASS')
    if not massFill then
        return
    end
    local energyFill = FillOf(econ, 'ENERGY') or 1

    -- Прибор должен знать заполнение хранилища на СВОЕМ проходе, иначе в
    -- строке GAME-STOP окажется число из прошлой секунды.
    gstop.mass = massFill

    -- СКОРОСТЬ РЕКЛЕЙМА из счётчика самой игры.
    --
    -- econ.reclaimed - накопительный счётчик, из которого работает
    -- колонка "реклейм" в панели ресурсов игры (ui/game/economy.lua:
    -- 382-394). Прирост счётчика за секунду и есть текущая добыча
    -- реклеймом. Когда игра прекращает реклейм, прирост становится
    -- нулём - это и есть тот сигнал, который мы ищем.
    --
    -- Считаем здесь же, где уже взят econ ради процента заполнения,
    -- поэтому лишней работы почти нет.
    gstop.rec = 0
    local okR, recNow = pcall(function() return econ.reclaimed.MASS end)
    if okR and type(recNow) == 'number' then
        if gstop.recPrev ~= nil then
            -- span - сколько проходов прошло между отсчётами. Делим на
            -- него, чтобы скорость была "в секунду" независимо от того,
            -- сколько секунд между проходами.
            local span = iterNo - gstop.recIter
            if span > 0 then
                gstop.rec = (recNow - gstop.recPrev) / span
            end
        end
        gstop.recPrev = recNow
        gstop.recIter = iterNo
    end

    iterNo = iterNo + 1
    local cfg = Settings.ReclaimPauseCfg
    rescanSec = cfg.rescanSec
    local probeSec = cfg.probeSec
    if probeSec == nil or probeSec < 0 then
        probeSec = 0
    end

    -- гистерезис по массе: два порога, иначе мод дергается
    -- ТАЙМЕР УДЕРЖАНИЯ УСЛОВИЯ СНЯТИЯ.
    --
    -- Раньше мод отпускал инженеров в тот же проход, где масса впервые
    -- упала ниже lowMass, и тут же ставил обратно, если она вернулась
    -- выше highMass: игрок видел, как инженеры дёргаются на границе.
    --
    -- Теперь условие снятия должно ПРОДЕРЖАТЬСЯ releaseHoldSec секунд.
    -- Короткий провал ниже lowMass ничего не отменяет, устойчивое низкое
    -- хранилище отпускает всегда. Значение 0 = старое поведение.
    local holdSec = 0
    local holdCfg = cfg.releaseHoldSec
    if holdCfg == nil or holdCfg < 0 then
        holdCfg = 0
    end
    local want = holding
    if holding then
        if massFill <= cfg.lowMass / 100 then
            if lowSinceIter == 0 then
                lowSinceIter = iterNo
            end
            holdSec = (iterNo - lowSinceIter) * SCAN_SEC
            if holdSec >= holdCfg then
                want = false
            end
        else
            lowSinceIter = 0
            holdSec = 0
        end
    else
        lowSinceIter = 0
        if massFill >= cfg.highMass / 100 then
            want = true
        end
    end

    -- ЭНЕРГИЯ. Пауза разрешена, только если энергии хватает. Иначе мы бы
    -- мешали инженерам собирать её. Проверка зеркальна: если энергия
    -- упала ниже порога, пока инженеры на паузе, тоже отпускаем.
    local energyOk = energyFill >= cfg.energyMin / 100
    if want and not energyOk then
        want = false
    end

    -- и не переключаться чаще отведённого интервала
    local minSec = cfg.minSec
    if minSec < 0 then
        minSec = 0
    end
    local sinceSec = (iterNo - switchIter) * SCAN_SEC
    if want ~= holding and sinceSec < minSec then
        want = holding
    end

    if not cfg.enabled then
        want = false
    end

    why.skip = 0
    why.player = 0
    why.other = 0

    -- Переключение фиксируем ДО обхода: в момент перехода обход должен
    -- произойти сразу, а не ждать своей очереди.
    local changed = (want ~= holding)
    if changed then
        holding = want
        if not holding then
            lowSinceIter = 0
        end
        switchIter = iterNo
        rescanIter = iterNo - rescanSec
    end

    -- Пока снимать нечего, инженеров НЕ обходим.
    local fresh = nil
    local foundN = -1
    local graceLeft = cfg.startGrace - iterNo * SCAN_SEC
    -- Обход трогает выделение (WithAllEngineers), поэтому он идёт только
    -- при активной паузе. Прибор сам обход не запускает: иначе выделение
    -- подменялось бы весь матч, даже у выключенного мода.
    if want and graceLeft <= 0 then
        local got, n = EnsureEngineers()
        if got then
            fresh = got
            foundN = n
            engineerCount = n
            gstop.fresh = got
        end
    else
        -- Обхода не было. -1 означает "не искали", и в логе печатается
        -- как "?", а не как 0. Ноль и отсутствие данных - не одно и то же.
        foundN = -1
        engineerCount = -1
    end

    -- ДВИЖЕНИЕ ИНЖЕНЕРОВ - признак, по которому ищем порог игры.
    --
    -- Пока инженер реклеймит, он стоит. Когда игра прекращает реклейм,
    -- инженер на атак-муве идёт к точке. Значит резкий рост доли
    -- движущихся при высоком заполнении хранилища и есть тот порог.
    --
    -- Меряем unit:GetPosition() - он в слое интерфейса работает, доказано
    -- в игре (posMoved=28/32 posShift=5.2).
    --
    -- Состояние 'Reclaiming' и событие OnStopReclaim недоступны из
    -- интерфейса: в игре recl=0/0 при engineers=120 и
    -- "attempt to call method `AddUnitCallback' (a nil value)". Оба
    -- метента принадлежат слою симуляции.
    local movN = 0
    local movM = 0
    local movFar = 0
    if gstop.fresh ~= nil then
        for id, unit in pairs(gstop.fresh) do
            local okP, p = pcall(function() return unit:GetPosition() end)
            if okP and type(p) == 'table' and type(p[1]) == 'number'
                and type(p[3]) == 'number' then
                movM = movM + 1
                local prev = gstop.pos[id]
                if prev ~= nil then
                    local dx = p[1] - prev.x
                    local dz = p[3] - prev.z
                    local dist = math.sqrt(dx * dx + dz * dz)
                    if dist > 0.5 then
                        movN = movN + 1
                    end
                    if dist > movFar then
                        movFar = dist
                    end
                end
                gstop.pos[id] = { x = p[1], z = p[3] }
            end
        end
        for id in pairs(gstop.pos) do
            if gstop.fresh[id] == nil then
                gstop.pos[id] = nil
            end
        end
    end

    local release = {}
    local releaseN = 0
    local topause = {}
    local pauseN = 0

    if not want then
        -- Снимаем паузу со всех, кого держим. Обход для этого не нужен.
        for id, unit in pairs(held) do
            if IsCurrentlyPaused(unit) then
                release[releaseN + 1] = unit
                releaseN = releaseN + 1
            end
            LOG(PFX .. 'unit ' .. tostring(id) .. ' release, held ' ..
                tostring(HeldSecs(id)) .. 's')
            held[id] = nil
            heldAt[id] = nil
            skipUntil[id] = nil
        end
    else
        -- 1. Уже известные инженеры проверяем напрямую, без выделения.
        --    Обход не имеет права никого отпускать.
        for id, unit in pairs(held) do
            if not IsAlive(unit) then
                held[id] = nil
                heldAt[id] = nil
            else
                local kind, managed = FrontKind(unit)
                local actuallyPaused = IsCurrentlyPaused(unit)
                if managed then
                    if actuallyPaused then
                        held[id] = unit
                        -- ДИАГНОСТИКА: первые две проверки после паузы
                        -- пишем приказ как есть. Так видно, приказ СБРОШЕН
                        -- или просто не читается.
                        if HeldSecs(id) <= 1 then
                            LOG(PFX .. 'unit ' .. tostring(id) ..
                                ' check after pause +' .. tostring(HeldSecs(id)) ..
                                's, order=' .. tostring(kind))
                        end
                    else
                        -- Игрок снял паузу вручную, НО ПРИКАЗ НА МЕСТЕ.
                        --
                        -- Значит он хочет, чтобы инженер работал, и мод для
                        -- того и нучен: хранилище полно. Игнорировать здесь
                        -- нечего - приказ есть, и приказ наш.
                        --
                        -- Раньше здесь стоял skipUntil на skipSec секунд.
                        -- Это была дыра: игрок снимал паузу и отправлял
                        -- инженеров в атак-мув, а мод игнорировал их минуту.
                        -- За это время они дореклеймивали, доезжали до
                        -- точки и теряли приказ - после чего мод уже не
                        -- понимал, что они его.
                        --
                        -- Если игрок хочет, чтобы мод не вмешивался, есть
                        -- горячая клавиша вкл/выкл.
                        topause[pauseN + 1] = unit
                        pauseN = pauseN + 1
                        held[id] = unit
                        heldAt[id] = iterNo
                        LOG(PFX .. 'unit ' .. tostring(id) ..
                            ' manual unpause, but order=' .. tostring(kind) ..
                            ' - pause returned')
                    end
                elseif kind == 'empty' or kind == 'queue-error' then
                    -- ВАЖНО (найдено в игре 2026-10-05). У юнита, стоящего на
                    -- паузе, очередь приказов ЧИТАЕТСЯ ПУСТОЙ. Это не значит,
                    -- что приказ выполнен: sim/Unit.lua:514-515 показывает, что
                    -- пауза вызывает только SetPaused(true) и очередь не
                    -- трогает. За секунду инженер не может дойти до цели.
                    --
                    -- Прежняя версия принимала 'empty' за "приказ слетел" и
                    -- тут же снимала паузу - инженеры уходили к точке
                    -- атак-мува. Теперь пустая очередь на паузе означает
                    -- "ничего не знаю", и мы продолжаем держать инженера.
                    if actuallyPaused then
                        held[id] = unit
                        if HeldSecs(id) <= 1 then
                            LOG(PFX .. 'unit ' .. tostring(id) ..
                                ' check after pause +' .. tostring(HeldSecs(id)) ..
                                's, order=' .. tostring(kind) ..
                                ' (empty is normal for a paused unit)')
                        end
                    else
                        skipUntil[id] = iterNo + cfg.skipSec
                        held[id] = nil
                        heldAt[id] = nil
                    end
                else
                    -- Конкретный чужой приказ (Guard, Build, Attack) - это
                    -- достоверное чтение, освобождаем.
                    local secs = HeldSecs(id)
                    if actuallyPaused then
                        release[releaseN + 1] = unit
                        releaseN = releaseN + 1
                    end
                    held[id] = nil
                    heldAt[id] = nil
                    LOG(PFX .. 'unit ' .. tostring(id) ..
                        ' released, current order=' .. tostring(kind) ..
                        ', held ' .. tostring(secs) .. 's')
                end
            end
        end

        -- 2. Новые кандидаты - только из свежего обхода
        if fresh then
            for id, unit in pairs(fresh) do
                -- уже стоящих на паузе (например, поставил игрок) трогать
                -- нельзя: SetPaused идемпотентна, но смысла в повторе нет
                local alreadyPaused = IsCurrentlyPaused(unit)
                -- Инженер без приказа модом НЕ трогается. Раньше для
                -- такого был флаг pauseIdle - он удалён по требованию
                -- игрока. Обоснование простое: без приказа инженер и так
                -- ничего не делает, а ставить его на паузу бессмысленно -
                -- он уже стоит, и мод только засоряет лог.
                --
                -- Берём только тех, у кого приказ наш: реклейм, атак-мув,
                -- патруль и то же через Script-задачу.
                local kindC, managedC = FrontKind(unit)
                local worth = managedC
                if held[id] == nil and IsSkipped(id) then
                    why.skip = why.skip + 1
                elseif held[id] == nil and alreadyPaused then
                    why.player = why.player + 1
                elseif held[id] == nil and not worth then
                    why.other = why.other + 1
                end
                if held[id] == nil and not IsSkipped(id) and not alreadyPaused
                    and worth then
                    local kind = kindC
                    topause[pauseN + 1] = unit
                    pauseN = pauseN + 1
                    held[id] = unit
                    heldAt[id] = iterNo
                    LOG(PFX .. 'unit ' .. tostring(id) ..
                        ' PAUSE issued, order=' .. tostring(kind))
                end
            end
        end
    end

    -- Прибор меряем ДО применения пауз, чтобы видеть и движение
    -- уже удерживаемых, и только что поставленных.
    -- Прибор меряет НЕЗАВИСИМО от того, держит мод кого-то или нет.
    --
    -- Раньше здесь стояло "if holding and ...". Для замера порога игры
    -- это ломало всё: момент, когда игра перестала отдавать реклейм,
    -- проходит ДО того, как мод возьмёт кого-то на паузу. Прибор
    -- включался бы слишком поздно и момент пропускал бы.
    if probeSec > 0 and (iterNo - posIter) * SCAN_SEC >= probeSec then
        posIter = iterNo
        RunProbe()
    end

    if releaseN > 0 then
        ResumeUnits(release, releaseN)
    end
    if pauseN > 0 then
        PauseUnits(topause, pauseN)
        AbortMove(topause, pauseN)
        abortIter = iterNo
    elseif cfg.abortMove and holding then
        -- Обрыв маршрута ОДНОРАЗОВЫЙ: прерванный атак-мув снова находит путь
        -- и юнит идёт дальше. Поэтому пока хранилище полно, обрыв повторяется
        -- каждые abortSec секунд - иначе инженер дойдёт до точки.
        if (iterNo - abortIter) * SCAN_SEC >= cfg.abortSec then
            abortIter = iterNo
            local alist = {}
            local an = 0
            for _id, aunit in pairs(held) do
                if IsCurrentlyPaused(aunit) then
                    an = an + 1
                    alist[an] = aunit
                end
            end
            if an > 0 then
                AbortMove(alist, an)
            end
        end
    end

    -- 3. Лог
    if changed then
        local what = 'RELEASED'
        if want then
            what = 'PAUSED'
        end
        LOG(PFX .. what .. ' mass=' .. string.format('%.1f', massFill * 100) .. '%' ..
            ' energy=' .. string.format('%.1f', energyFill * 100) .. '%' ..
            ' verdict=' .. Explain(cfg, massFill, energyFill) ..
            ' hold=' .. ExplainHold(cfg, massFill, holdSec) ..
            ' engineers=' .. (foundN >= 0 and tostring(foundN) or '?') ..
            ' nowPaused=' .. tostring(pauseN) ..
            ' nowReleased=' .. tostring(releaseN))
    end

    -- Компактная строка замера, раз в probeSec секунд.
    --
    -- Главная строка состояния идёт раз в logEvery проходов, а
    -- logEvery становится 5 только когда масса не ниже lowMass
    -- (строка PeriodicLog). В замере lowMass стоит высоко, и тогда
    -- строки идут раз в 15 секунд - за это время хранилище уезжает на
    -- треть, и момент остановки реклейма между ними не попадает.
    --
    -- Именно так и вышло в замере 2026-10-10: rec упал со 156 до 10
    -- между двумя замерами, и где именно - не видно.
    gstop.logRec = gstop.logRec + 1
    if probeSec ~= nil and probeSec > 0 and gstop.logRec >= probeSec then
        gstop.logRec = 0
        LOG(PFX .. 'REC mass=' .. string.format('%.1f', massFill * 100) .. '%' ..
            ' rec=' .. string.format('%.0f', gstop.rec) ..
            ' mov=' .. tostring(movN) .. '/' .. tostring(movM))
    end

    PeriodicLog(cfg, massFill, energyFill, holdSec, probeSec, movN, movM, movFar,
        gstop.rec)
end

--------------------------------------------------------------------------------
-- ЦИКЛ. WaitSeconds НЕЛЬЗЯ оборачивать в pcall - внутри pcall он fatal.
--------------------------------------------------------------------------------

local function Loop()
    while running do
        -- Корутина умирает МОЛЧА на любой ошибке: движок не пишет ничего.
        -- Один nil-вызов - и мод перестаёт работать без единого слова в логе.
        -- Поэтому TickOnce под pcall, а ошибка печатается.
        local ok, err = pcall(TickOnce)
        if not ok then
            LOG(PFX .. 'CRASH in TickOnce: ' .. tostring(err))
        end
        -- WaitSeconds внутри pcall fatal, поэтому он ВНЕ pcall.
        WaitSeconds(SCAN_SEC)
    end
end

--------------------------------------------------------------------------------
-- ТОЧКИ ВХОДА
--------------------------------------------------------------------------------

---Применить изменившиеся настройки на ходу. Вызывает страница настроек.
function ReclaimPauseApplySettings()
    if not running then
        return
    end
    if Settings.ReclaimPauseCfg.enabled then
        switchIter = iterNo - Settings.ReclaimPauseCfg.minSec
        return
    end
    ReleaseAll('mod disabled')
    holding = false
end

function ReclaimPauseStart()
    if running then
        return
    end
    if not okSet or type(Settings) ~= 'table'
        or type(Settings.ReclaimPauseLoadSettings) ~= 'function' then
        LOG(PFX .. 'settings module unusable: ' .. tostring(Settings))
        return
    end
    Settings.ReclaimPauseLoadSettings()
    running = true
    iterNo = 0
    ProbePausedOfUnit()
    -- Считаем, что последнее переключение было давно: иначе первое
    -- срабатывание ждало бы minSec.
    switchIter = -(Settings.ReclaimPauseCfg.minSec)
    rescanIter = 0 - Settings.ReclaimPauseCfg.rescanSec
    logTick = 0
    engineerCount = 0
    holding = false
    held = {}
    heldAt = {}
    skipUntil = {}
    lowSinceIter = 0
    posLast = {}
    posIter = 0
    probeDoneIter = 0
    posMoved = 0
    posTotal = 0
    posShift = 0
    gstop.mass = 0
    gstop.pos = {}
    gstop.rec = 0
    gstop.recPrev = nil
    gstop.recIter = 0
    gstop.logRec = 0
    gstop.fresh = nil
    why.skip = 0
    why.player = 0
    why.other = 0
    LOG(PFX .. 'started, ' .. Settings.ReclaimPauseSettingsLine())
    ForkThread(Loop)
end

function ReclaimPauseStop()
    if not running then
        return
    end
    running = false
    ReleaseAll('mod stopped')
    holding = false
    LOG(PFX .. 'stopped')
end

function ReclaimPauseToggle()
    if Settings.ReclaimPauseCfg.enabled then
        Settings.ReclaimPauseCfg.enabled = false
        ReleaseAll('toggled off')
        holding = false
    else
        Settings.ReclaimPauseCfg.enabled = true
    end
    Settings.ReclaimPauseSaveSettings()
    Settings.ReclaimPausePushToWindow()
    switchIter = iterNo - Settings.ReclaimPauseCfg.minSec
    LOG(PFX .. 'toggled, ' .. Settings.ReclaimPauseSettingsLine())
end

function ReclaimPauseOnCreateUI()
    ReclaimPauseStart()
end