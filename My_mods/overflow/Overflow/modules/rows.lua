-- Overflow - какие строки панели показывать. Версия 1.
--
-- ЗАЧЕМ ОТДЕЛЬНЫЙ ФАЙЛ. Настройка нужна сразу двоим: панели интерфейса
-- (ui.lua) и странице настроек UMT (Options.lua). Если бы список строк и их
-- названия жили в ui.lua, то страница настроек тянула бы весь интерфейс ради
-- констант. Здесь одно определение на обоих.
--
-- ---------------------------------------------------------------------------
-- ЭКСПОРТ ГЛОБАЛАМИ, А НЕ ЧЕРЕЗ return. Значение return движок отбрасывает
-- (import.lua:61 и 171), а у _G стоит метаметод config.lua:56-61, падающий
-- ошибкой на несуществующем глобале. Подробно - методичка 3.23; там же
-- объяснение, почему ui.lua читает поля модуля через rawget.
--
-- Поэтому функции ниже объявлены как `function Visible()`, а в ui.lua берутся
-- через rawget(ИмяМодуля, 'Visible') - ровно как уже сделано для sync.lua.
--
-- ---------------------------------------------------------------------------
-- ГДЕ ЛЕЖАТ ЗНАЧЕНИЯ
--
-- Профиль 'Overflow'. Это ТОТ ЖЕ ключ, которым пользуется UMT:
-- OptionVar:Save() (mods/umt/modules/OptionVar.lua:41-47) делает
--
--     Prefs.GetFromCurrentProfile('Overflow')[имяПоля] = значение
--     Prefs.SetToCurrentProfile('Overflow', таблица)
--
-- То есть окно настроек и мод смотрят в одно хранилище, и мод НЕ зависит от
-- того, установлен ли UMT:
--
--   * UMT установлен и страницу открывали - значения уже в профиле;
--   * UMT есть, но страницу не открывали - OptionVar:Create
--     (OptionVar.lua:88-96) кладёт значения по умолчанию в профиль сам, как
--     только страница загрузится;
--   * UMT не установлен - ключей в профиле нет, и Visible() ниже
--     возвращает значения по умолчанию сама.
--
-- Именно поэтому ЗДЕСЬ НЕТ ни одного обращения к UMT. Если бы rows.lua полез
-- в UMT.Options, а UMT не установлен, чтение несуществующего глобального
-- имени УБИЛО БЫ МОД ЦЕЛИКОМ (методичка 3.6).
--
-- Именно поэтому страница настроек НЕ импортирует ui.lua, а только пишет в
-- профиль. Панель сама замечает изменение по биту игры. Причина не в
-- экономии, а в порядке загрузки: неизвестно, UMT ли загрузится раньше
-- интерфейса игры или позже, и импорт ui.lua из страницы настроек в одном
-- из случаев поймал бы ещё не до конца выполненный модуль.
--
-- КЛЮЧ ПРОФИЛЯ НЕ СОДЕРЖИТ ТОЧЕК: GetFromCurrentProfile читает строку как
-- путь по точкам - методичка 11.1. Положение панели лежит отдельно, в ключе
-- 'OverflowPanelPos' (ui.lua).
--
-- ---------------------------------------------------------------------------
-- ХРАНИТСЯ «КАКИЕ СТРОКИ ВИДНЫ», А НЕ «КАКИЕ СКРЫТЫ»
--
-- Разница видна на старой версии профиля, где полей нет вообще: «не
-- указано» должно значить «как по умолчанию», иначе после обновления мода у
-- всех пропала бы панель.

local Prefs        = import('/lua/user/prefs.lua')
local LOG          = LOG
local TableGetn    = table.getn
local TableConcat  = table.concat
local StringFormat = string.format

local PREFS_KEY = 'Overflow'

--------------------------------------------------------------------------------
-- ОПРЕДЕЛЕНИЕ СТРОК
--------------------------------------------------------------------------------

-- ПОРЯДОК ВАЖЕН: в этом порядке строки идут на панели. Он совпадает с
-- порядком строк в ui.lua и должен совпадать с ним всегда.
local ROWS = { 'eOverflow', 'eGo', 'eOwn', 'mOverflow', 'mGo', 'mOwn', 'total' }

-- Человеческие названия для окна настроек. Ключи обязаны совпадать с ROWS:
-- иначе галочка появится для несуществующей строки, а настоящая останется
-- без настройки.
local TITLES = {
    eOverflow = 'E ally overflow - сколько энергии дают союзники',
    eGo       = 'E to allies - сколько энергии отдаём мы',
    eOwn      = 'E own production - своя выработка энергии',
    mOverflow = 'M ally overflow - сколько массы дают союзники',
    mGo       = 'M to allies - сколько массы отдаём мы',
    mOwn      = 'M own production - своя выработка массы',
    total     = 'reclaim E / M - скорость реклейма',
}

-- ПО УМОЛЧАНИЮ ВИДНЫ ДВЕ СТРОКИ: перелив энергии союзникам и перелив энергии
-- от нас. Так хочет игрок - это его рабочий набор, и он должен стоять сразу
-- после установки, без похода в настройки.
--
-- НАБОР ПО УМОЛЧАНИЮ ОБЯЗАН СОВПАДАТЬ С PRESETS[1] (см. ниже): UMT при
-- открытии окна ищет сохранённое значение в списке и, не найдя, молча ставит
-- и сохраняет первый элемент (Views/StringSelector.lua:31-35).
local DEFAULTS = {
    eOverflow = true,
    eGo       = true,
    eOwn      = false,
    mOverflow = false,
    mGo       = false,
    mOwn      = false,
    total     = false,
}

--------------------------------------------------------------------------------
-- ГОТОВЫЕ НАБОРЫ
--
-- Чтобы оставить одну строку, не нужно снимать шесть галочек.
--
-- ПЕРВЫЙ ЭЛЕМЕНТ ОБЯЗАН СОВПАДАТЬ С DEFAULTS. Значение выпадающего списка
-- по умолчанию равно items[1], а UMT при открытии окна ищет текущее
-- значение в списке и, если не нашёл, МОЛЧА ставит первый элемент и
-- сохраняет его (mods/umt/modules/Views/StringSelector.lua:31-35). Поэтому
-- items[1] обязан совпадать со значением по умолчанию.
--
-- ПОСЛЕДНИЙ ЭЛЕМЕНТ - НЕ НАБОР, А СЛУЖЕБНОЕ СОСТОЯНИЕ. Оно показывается,
-- когда игрок собрал комбинацию, которой нет выше. Флагов у него нет, так
-- что щелчок по нему ничего не портит: обработчик разворачивает набор через
-- PresetByName, а тот для этого элемента возвращает nil.
--------------------------------------------------------------------------------

local PRESETS = {
    { label = 'E ally overflow + E to allies',
      flags = { eOverflow = true, eGo = true } },
    { label = 'Все строки',
      flags = { eOverflow = true, eGo = true, eOwn = true,
                mOverflow = true, mGo = true, mOwn = true, total = true } },
    { label = 'Только E ally overflow',
      flags = { eOverflow = true } },
    { label = 'Только перелив союзников',
      flags = { eOverflow = true, mOverflow = true } },
    { label = 'Только энергия',
      flags = { eOverflow = true, eGo = true, eOwn = true } },
    { label = 'Только масса',
      flags = { mOverflow = true, mGo = true, mOwn = true } },
    { label = 'Ничего не показывать',
      flags = {} },
    { label = 'Другой набор',
      flags = nil },
}

--------------------------------------------------------------------------------
-- ДОСТУП К ОПРЕДЕЛЕНИЮ СТРОК
--------------------------------------------------------------------------------

-- Сколько всего строк. Оператор # движком не поддерживается - длина только
-- через table.getn (методичка 3.3).
function HowManyRows()
    return TableGetn(ROWS)
end

-- Имя строки по номеру, начиная с 1.
function RowKeyAt(i)
    return ROWS[i]
end

-- Название строки для окна настроек.
function RowTitleOf(rowKey)
    return TITLES[rowKey]
end

-- Копия значений по умолчанию: копия, а не сам DEFAULTS, чтобы вызывающий
-- код не мог испортить определение.
function RowDefaults()
    local out = {}
    for i = 1, TableGetn(ROWS) do
        local rowKey = ROWS[i]
        out[rowKey] = DEFAULTS[rowKey]
    end
    return out
end

-- Названия готовых наборов в том же порядке, что и в PRESETS.
function PresetNames()
    local out = {}
    for i = 1, TableGetn(PRESETS) do
        out[i] = PRESETS[i].label
    end
    return out
end

--------------------------------------------------------------------------------
-- ЧТЕНИЕ И ЗАПИСЬ
--------------------------------------------------------------------------------

-- Какие строки показывать.
--
-- Отсутствующий ключ читается как значение по умолчанию, а не как «скрыть»:
-- так же ведёт себя и UMT, и старый профиль без этих полей. Различать «поле равно
-- false» и «поля нет» здесь обязательно - иначе обновление мода погасило бы
-- панель у всех, кто ни разу не открывал настройки.
function VisibleRows()
    local saved = nil
    local ok, res = pcall(function()
        return Prefs.GetFromCurrentProfile(PREFS_KEY)
    end)
    if ok then
        saved = res
    else
        LOG('Overflow: rows read error, showing defaults: ' .. tostring(res))
    end

    local out = {}
    for i = 1, TableGetn(ROWS) do
        local rowKey = ROWS[i]
        local v
        if type(saved) == 'table' then
            v = saved[rowKey]
        end
        if v == nil then
            v = DEFAULTS[rowKey]
        end
        out[rowKey] = v and true or false
    end
    return out
end

-- Записать набор строк в профиль.
--
-- ЧИТАЕМ ТАБЛИЦУ И ПИШЕМ ЕЁ ОБРАТНО, а не затираем целиком: тем же профилем
-- 'Overflow' пользуется UMT для своих полей, и полное затирание снесло бы
-- их. Ровно так же поступает сам UMT - OptionVar.lua:42-44 читает текущую
-- таблицу и меняет в ней один ключ.
function SaveRows(vis)
    local ok, err = pcall(function()
        local profile = Prefs.GetFromCurrentProfile(PREFS_KEY)
        if type(profile) ~= 'table' then
            profile = {}
        end
        for i = 1, TableGetn(ROWS) do
            local rowKey = ROWS[i]
            profile[rowKey] = vis[rowKey] and true or false
        end
        Prefs.SetToCurrentProfile(PREFS_KEY, profile)
    end)
    -- ошибку не глотаем молча: иначе непонятно, почему галочка не сработала
    if not ok then
        LOG('Overflow: rows Save FAILED: ' .. tostring(err))
        return false
    end
    return true
end

--------------------------------------------------------------------------------
-- СООТВЕТСТВИЕ НАБОРОВ
--------------------------------------------------------------------------------

-- Название готового набора, совпадающего с vis, или nil.
--
-- Совпадение проверяется по ВСЕМ строкам, а не по тем, что перечислены в
-- наборе: нельзя пропустить строку, которая в наборе не упомянута, но
-- включена у игрока.
function PresetFor(vis)
    for i = 1, TableGetn(PRESETS) do
        local preset = PRESETS[i]
        -- служебный элемент набором не является и совпасть не может
        if preset.flags ~= nil then
            local same = true
            for j = 1, TableGetn(ROWS) do
                local rowKey = ROWS[j]
                local want = preset.flags[rowKey]
                if want == nil then
                    want = false
                end
                if (vis[rowKey] and true or false) ~= want then
                    same = false
                    break
                end
            end
            if same then
                return preset.label
            end
        end
    end
    return nil
end

-- Подпись служебного состояния «ни один набор не совпал». Её показывает
-- страница настроек, когда игрок собрал комбинацию вручную.
function PresetOther()
    return PRESETS[TableGetn(PRESETS)].label
end

-- Развернуть название набора в таблицу флагов, или nil если названия нет
-- (неизвестное название или служебный элемент).
function PresetByName(label)
    for i = 1, TableGetn(PRESETS) do
        if PRESETS[i].label == label then
            -- служебный элемент: разворачивать нечего, и это не ошибка
            if PRESETS[i].flags == nil then
                return nil
            end
            local out = {}
            for j = 1, TableGetn(ROWS) do
                local rowKey = ROWS[j]
                local want = PRESETS[i].flags[rowKey]
                out[rowKey] = want and true or false
            end
            return out
        end
    end
    return nil
end

--------------------------------------------------------------------------------
-- КОРОТКИЕ ВСПОМОГАТЕЛЬНЫЕ
--------------------------------------------------------------------------------

-- Подпись набора строк из семи символов: по '1' или '0' на строку.
--
-- Панель сравнивает его со своим и перерисовывает раскладку, только когда
-- набор реально изменился. Строка вместо таблицы - потому что сравнение
-- таблиц в этом движке делается по ссылке и всегда даёт «разные».
function RowsSignature(vis)
    local parts = {}
    for i = 1, TableGetn(ROWS) do
        local rowKey = ROWS[i]
        if vis[rowKey] then
            parts[i] = '1'
        else
            parts[i] = '0'
        end
    end
    return TableConcat(parts)
end

-- Короткая строка для лога: какие строки видны.
function DescribeRows(vis)
    local parts = {}
    local howMany = 0
    for i = 1, TableGetn(ROWS) do
        local rowKey = ROWS[i]
        if vis[rowKey] then
            howMany = howMany + 1
            parts[howMany] = rowKey
        end
    end
    if howMany == 0 then
        return 'none'
    end
    return StringFormat('%d/%d [%s]', howMany, TableGetn(ROWS),
        TableConcat(parts, ' '))
end
