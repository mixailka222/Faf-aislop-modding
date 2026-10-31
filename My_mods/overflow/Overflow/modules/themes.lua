-- Overflow - оформление панели: стиль, рамка, мигание. Версия 2.
--
-- ЗАЧЕМ ОТДЕЛЬНЫЙ ФАЙЛ. Ровно как у rows.lua: оформление нужно двоим - панели
-- интерфейса (ui.lua) и странице настроек UMT (Options.lua). Если бы палитра
-- жила в ui.lua, страница настроек тянула бы весь интерфейс ради списка названий.
--
-- ---------------------------------------------------------------------------
-- ЭКСПОРТ ГЛОБАЛАМИ, А НЕ ЧЕРЕЗ return. Значение return движок отбрасывает
-- (import.lua:61 и 171), а на _G висит метаметод config.lua:56-61, падающий
-- ошибкой на несуществующем глобале (методичка 3.23). Поэтому функции ниже
-- объявлены как `function StyleX()` и берутся в ui.lua через rawget - так же,
-- как уже сделано для sync.lua и rows.lua.
--
-- ---------------------------------------------------------------------------
-- ЧТО ТЕПЕРЬ НАЗЫВАЕТСЯ ОФОРМЛЕНИЕМ. Раньше тема была единым целым: и рамка,
-- и шрифт, и цвета одним пунктом списка. Это плохо совпадало с требованиями,
-- потому что шрифт с цветами и рамка - разные вещи:
--
--   ПРЕСЕТ (StyleNames) - шрифт и цвета ТЕКСТА. Два варианта:
--       Vanilla - как в игре: цвета из скина, размер 10 (см. ниже).
--       Minimal - наш: размер 11 и цвета, которые раньше жили в теме «Неон».
--       По умолчанию Minimal.
--
--   РАМКА (FrameNames) - как выглядит само окно. Два варианта:
--       Vanilla - игровое окно с игровым бордером (текстуры миникарты).
--       Minimal - плоская заливка без объёмных игровых рамок.
--       По умолчанию Minimal.
--
-- Фракционных тем больше нет: рамка и так берётся из папки скина, и отдельный
-- пункт «тема под фракцию» игроку ничего не давал.
--
-- ---------------------------------------------------------------------------
-- ОТКУДА ЦВЕТА И РАЗМЕРЫ. Ничего не выдумано, всё взято из игры:
--
--   Размер 10 для Vanilla - это ровно то, чем игра рисует свои мелкие числа
--   в панели ресурсов: economy.lua:144-160 (curStorage, maxStorage, income,
--   expense, reclaimDelta, reclaimTotal). Шрифт тот же - UIUtil.bodyFont.
--
--   Цвета состояний Vanilla - из скина default (lua/skins/skins.lua:152-177):
--   disabledColor в разделитель, dialogCaptionColor в заголовок и обычный
--   текст, transparentPanelColor в фон окна. Опечатка в числе невозможна, а
--   если FAF поменяет скин, мод пойдёт за ним.
--
--   Цвета состояний из игры (без исключений, одинаково для обоих пресетов):
--   SAFE  ffb7e75f  economy_mini.lua:12, цвет числа массы в игре
--   WARN  yellow    economy.lua:262, цвет отрицательного темпа
--   BAD   red       economy.lua:264, цвет пустого хранилища
--
--   Игра передаёт движку не только hex, но и ИМЕНА цветов: 'red' и 'yellow'
--   уходят в Text:SetColor как есть (economy.lua:456). Движок их принимает, и
--   наши подписи - тот же Text из uiutil.CreateText.
--
--   СМЫСЛ ТРЁХ ЦВЕТОВ ОДИНАКОВ У ЛЮБОГО ПРЕСЕТА, и это проверяется отдельно:
--   зелёный - перелива нет, жёлтый - союзники переливают тебе, красный - ты
--   слишком зависишь от перелива союзников. Пресет меняет ОТТЕНОК, а не
--   СПИСОК СОСТОЯНИЙ. Список состояний и порог живут в ui.lua (StatusColor),
--   а сюда попадают только цвета.
--
-- ---------------------------------------------------------------------------
-- ПРО НАСТРОЙКУ faction_font_color. Она ВЫКЛЮЧЕНА ПО УМОЛЧАНИЮ
-- (options.lua:1217-1221, default = false). Когда она выключена, игра рисует
-- серым skins.default.fontColor вместо цвета фракции (uiutil.lua:301-305).
-- Поэтому пресет повторяет эту проверку: если игрок выключил настройку, мы
-- показываем серый - ровно то, что видит он.
--
-- Проверка надёжна: Prefs.GetOption возвращает значение по умолчанию, если
-- опции нет (prefs.lua:116-132), то есть nil здесь невозможен.
--
-- ---------------------------------------------------------------------------
-- ЧТО ЗДЕСЬ НЕТ
--
-- Ни одного обращения к UMT - по той же причине, что в rows.lua: если UMT не
-- установлен, чтение несуществующего глобального имени УБИЛО БЫ МОД ЦЕЛИКОМ
-- (методичка 3.6). Здесь только профиль.
--
-- КЛЮЧ ПРОФИЛЯ 'Overflow' НЕ СОДЕРЖИТ ТОЧЕК: GetFromCurrentProfile читает
-- строку как путь по точкам (методичка 11.1). Это тот же ключ, что у rows.lua
-- и у UMT, поэтому все трое мирно делят одну таблицу.
--
-- ---------------------------------------------------------------------------
-- НАЗВАНИЯ ПРЕСЕТОВ И РАМОК НЕЛЬЗЯ ПЕРЕИМЕНОВЫВАТЬ. UMT при открытии окна
-- ищет сохранённое значение в списке и, если не нашёл, МОЛЧА ставит первый
-- пункт и сохраняет его (mods/umt/modules/Views/StringSelector.lua:31-35).

local Prefs        = import('/lua/user/prefs.lua')
local LOG          = LOG
-- MathFloor берётся ИЗ МАТЕМАТИКИ, а не из глобала. Глобала MathFloor в ФАФ
-- нет: каждый файл игры пишет ровно это же (defaultexplosions.lua:661,
-- maui/layouthelpers.lua:20, maui/statusbar.lua:3, forms.lua:30). Написать
-- `local MathFloor = MathFloor` - значит прочитать несуществующий глобал, а
-- LuaPlus на этом падает ФАТАЛЬНО: файл не грузится и рушится весь мод.
local MathFloor    = math.floor
local TableGetn    = table.getn

local PrefsKey = 'Overflow'

-- Скины игры. import может не сработать, поэтому берём под pcall и молча
-- остаёмся на своих числах, если не вышло.
local Skins = nil
do
    local okSkins, resSkins = pcall(function()
        return import('/lua/skins/skins.lua').skins
    end)
    if okSkins and type(resSkins) == 'table' then
        Skins = resSkins
    else
        LOG('Overflow: skins.lua did not load, Vanilla style will use ' ..
            'fallback colours')
    end
end

--------------------------------------------------------------------------------
-- ЧТЕНИЕ ИЗ СКИНА
--------------------------------------------------------------------------------

-- Взять поле скина строкой. Любое несовпадение - берём запасное значение:
-- панель без своих цветов лучше, чем панель с прозрачным текстом.
local function SkinField(skinName, fieldName, fallback)
    if Skins == nil then
        return fallback
    end
    local sk = Skins[skinName]
    if type(sk) ~= 'table' then
        return fallback
    end
    local got = sk[fieldName]
    if type(got) ~= 'string' or got == '' then
        return fallback
    end
    return got
end

-- Цвет шрифта фракции - с той же проверкой, что и в игре (uiutil.lua:301-305).
local function FontColorFor(skinName)
    local plain = SkinField('default', 'fontColor', 'FFbadbdb')
    local wantFaction = false
    local okOpt, resOpt = pcall(function()
        return Prefs.GetOption('faction_font_color')
    end)
    if okOpt and resOpt then
        wantFaction = true
    end
    if wantFaction then
        return SkinField(skinName, 'fontColor', plain)
    end
    return plain
end

--------------------------------------------------------------------------------
-- СПИСОКИ
--
-- ПОРЯДОК ОБЯЗАН БЫТЬ ТАКИМ ЖЕ, КАК В Options.lua: первый элемент - вариант по
-- умолчанию, потому что UMT ставит items[1], если сохранённого значения в
-- списке нет. То же правило уже записано в rows.lua:103-107.
--------------------------------------------------------------------------------

-- ПРЕСЕТЫ: шрифт и цвета текста.
local STYLES = {
    -- MINIMAL - НАШ ПРЕСЕТ И ВЫБОР ПО УМОЛЧАНИЮ. Размер 11 и палитра,
    -- которая раньше была темой «Неон».
    --
    -- ИМЯ ПОЛЯ ПИШЕМ ЗАГЛАВНЫМИ, как его читает Build. Строчными поле
    -- называлось в первой редакции, и кегль Minimal молча оставался от
    -- пресета Vanilla - без единой ошибки в логе.
    { label = 'Minimal',
      FONT = 11,
      DIVIDER = 'FF405060',
      TITLE   = 'FF8FD0FF',
      SAFE    = 'FF5CE07A',
      WARN    = 'FFFFD24A',
      BAD     = 'FFEF5350',
      NEUTRAL = 'FF8A96A3',
      TOTAL   = 'FFFFD24A',
      CLOSED  = 'FF1E2A34' },

    -- VANILLA - как в игре. Размер 10 взят из economy.lua:144-160, это те же
    -- мелкие числа, которыми игра рисует свои показатели.
    { label = 'Vanilla',
      FONT = 10,
      skin = true },
}

-- ПОЧЕМУ У ПРЕСЕТА НЕТ ПОЛЯ BG. BG - это ЦВЕТ ОКНА, и задаёт его настройка
-- «Рамка окна», а не «Пресет оформления». Когда BG жил в пресете, выбор
-- «рамка Minimal + пресет Vanilla» красил окно прозрачной панелью игры
-- AA4A5D6B (skins.lua:172) - серое пятно, цвет которого зависел от карты.
-- Теперь рамку красит её собственная подложка (ui.lua, ApplyFrameBackground),
-- и пресет о раме не знает.
--
-- BG остаётся в палитре как цвет кнопки возврата по умолчанию: при
-- пресете Vanilla кнопка возврата красится игровым цветом панели.

-- РАМКИ: как выглядит само окно. Minimal - ВЫБОР ПО УМОЛЧАНИЮ, поэтому он
-- стоит первым (см. правило порядка в комментарии выше).
local FRAMES = {
    { label = 'Minimal', minimal = true },
    { label = 'Vanilla', minimal = false },
}

--------------------------------------------------------------------------------
-- СБОРКА ПАЛИТРЫ ПРЕСЕТА
--
-- Поля перечислены поимённо, а не перебором таблицы: так видно, что на выходе
-- полный набор, и нечего ловить опечатку в имени поля.
--------------------------------------------------------------------------------

local function Build(style)
    -- Обвязка по умолчанию - значения скина default (skins.lua:152-177).
    local out = {}
    out.BG      = SkinField('default', 'transparentPanelColor', 'AA4A5D6B')
    out.CLOSED  = out.BG
    out.DIVIDER = SkinField('default', 'disabledColor', 'FF47555a')
    out.TITLE   = SkinField('default', 'dialogCaptionColor', 'FFbadbdb')
    out.TOTAL   = out.TITLE
    out.NEUTRAL = out.TITLE
    out.SAFE    = 'ffb7e75f'
    out.WARN    = 'yellow'
    out.BAD     = 'red'
    out.FONT    = 10

    -- VANILLA берёт часть полей из скина фракции. bodyColor игрок видит всегда
    -- (uiutil.lua:298 ставит его из скина безусловно), а цвет шрифта фракции -
    -- только если оставил настройку faction_font_color.
    if style.skin then
        out.NEUTRAL = SkinField('aeon', 'bodyColor', out.NEUTRAL)
        out.DIVIDER = SkinField('aeon', 'disabledColor', out.DIVIDER)
        out.TITLE   = FontColorFor('aeon')
    end

    -- Собственные значения пресета поверх обвязки.
    out.BG      = style.BG      or out.BG
    out.CLOSED  = style.CLOSED  or out.CLOSED
    out.DIVIDER = style.DIVIDER or out.DIVIDER
    out.TITLE   = style.TITLE   or out.TITLE
    out.TOTAL   = style.TOTAL   or out.TOTAL
    out.NEUTRAL = style.NEUTRAL or out.NEUTRAL
    out.SAFE    = style.SAFE    or out.SAFE
    out.WARN    = style.WARN    or out.WARN
    out.BAD     = style.BAD     or out.BAD
    out.FONT    = style.FONT    or out.FONT

    return out
end

--------------------------------------------------------------------------------
-- ПРОФИЛЬ
--
-- Читаем, а не заимствуем UMT: мод обязан работать и без UMT. Отдельного
-- импорта не делаем - тот же ключ, что у rows.lua.
--------------------------------------------------------------------------------

local function Saved()
    local profile = {}
    local ok, res = pcall(function()
        return Prefs.GetFromCurrentProfile(PrefsKey)
    end)
    if not ok then
        LOG('Overflow: settings read error, using defaults: ' .. tostring(res))
        return profile
    end
    if type(res) == 'table' then
        profile = res
    end
    return profile
end

-- Выбор из списка по имени. Неизвестное и отсутствующее значение - первый
-- пункт: молча пропасть из-за правки профиля нельзя.
local function Pick(list, wanted)
    if type(wanted) ~= 'string' then
        return list[1].label
    end
    local many = TableGetn(list)
    for i = 1, many do
        if list[i].label == wanted then
            return list[i].label
        end
    end
    return list[1].label
end

local function ByLabel(list, label)
    local many = TableGetn(list)
    for i = 1, many do
        if list[i].label == label then
            return list[i]
        end
    end
    return list[1]
end

--------------------------------------------------------------------------------
-- МАСШТАБ ШРИФТА
--
-- Ползунок UMT целочисленный (OptionsWindow.lua:267 IntegerSlider), поэтому
-- масштаб хранится в ПРОЦЕНТАХ: 100 - как есть, 150 - в полтора раза больше.
-- Границы - те, что у мода были для своего прежнего масштаба (0.70-2.00).
--------------------------------------------------------------------------------

local FONT_SCALE_MIN = 70
local FONT_SCALE_MAX = 200

-- ПО УМОЛЧАНИЮ 120: это рабочий масштаб игрока, и он должен стоять сразу после
-- установки, без похода в настройки. Сюда же смотрит страница настроек
-- (Options.lua), чтобы ползунок и мод не разошлись в числах.
local FONT_SCALE_DEFAULT = 120

local function FontScaleRead()
    local v = Saved().fontScale
    if type(v) ~= 'number' then
        return FONT_SCALE_DEFAULT
    end
    local n = MathFloor(v + 0.5)
    if n < FONT_SCALE_MIN then return FONT_SCALE_MIN end
    if n > FONT_SCALE_MAX then return FONT_SCALE_MAX end
    return n
end

--------------------------------------------------------------------------------
-- НАРУЖНЫЕ ФУНКЦИИ
--------------------------------------------------------------------------------

function StyleNames()
    local out = {}
    local many = TableGetn(STYLES)
    for i = 1, many do
        out[i] = STYLES[i].label
    end
    return out
end

function StyleCurrent()
    return Pick(STYLES, Saved().style)
end

-- Полная палитра выбранного пресета: цвета ТЕКСТА, фон плоской рамки и
-- базовый размер шрифта.
function StylePalette()
    return Build(ByLabel(STYLES, StyleCurrent()))
end

-- Размер шрифта с учётом масштаба игрока. Округление вниз: дробный кегль
-- движок принимает, но на некоторых машинах даёт разный рендеринг, а
-- предсказуемое целое - нет.
function StyleFontSize()
    local base = StylePalette().FONT
    return MathFloor(base * FontScaleRead() / 100 + 0.5)
end

function FontScale()
    return FontScaleRead()
end

-- Масштаб по умолчанию. Нужен странице настроек: ползунок UMT получает
-- стартовое значение отсюда, а не из числа, записанного в Options.lua.
function FontScaleDefault()
    return FONT_SCALE_DEFAULT
end

-- Только числа: когда включено, из строк убирается весь текст и остаются
-- одни числа. Текст приходит из ui.lua - там и решается, что показать.
function NumbersOnly()
    return Saved().numbersOnly and true or false
end

function FrameNames()
    local out = {}
    local many = TableGetn(FRAMES)
    for i = 1, many do
        out[i] = FRAMES[i].label
    end
    return out
end

function FrameCurrent()
    return Pick(FRAMES, Saved().theme)
end

-- Плоская рамка вместо игровой объёмной.
function FrameMinimal()
    return ByLabel(FRAMES, FrameCurrent()).minimal and true or false
end

-- Мигание выключено по умолчанию: как и в игре, тревога не обязана кричать.
function ThemeBlinkOn()
    return Saved().blink and true or false
end

-- Подпись настройки. Панель сравнивает её с той, на которой построена, и
-- перестраивается при изменении. Сюда входит ВСЁ, что меняет вид при сборке:
-- пресет, рамка, мигание, масштаб шрифта и режим «только числа».
function ThemeSignature()
    -- The FAF plugin for LuaLS reports a global call right after `..` as
    -- undefined. The function is declared above in this file.
    ---@diagnostic disable-next-line: undefined-global
    return StyleCurrent() .. '|' .. FrameCurrent() .. '|' ..
        tostring(ThemeBlinkOn()) .. '|' .. tostring(FontScaleRead()) .. '|' ..
        tostring(NumbersOnly())
end

-- Человеческое описание для лога.
function ThemeTell()
    -- Same false alarm of the FAF plugin as in ThemeSignature.
    ---@diagnostic disable-next-line: undefined-global
    return StyleCurrent() .. ' / ' .. FrameCurrent() ..
        ' / шрифт ' .. tostring(StyleFontSize()) ..
        ' / ' .. (NumbersOnly() and 'только числа' or 'с подписями')
end
