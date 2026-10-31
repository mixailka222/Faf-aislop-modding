-- Overflow - панель интерфейса, строки выбираются настройкой.
--
-- СЕМЬ СТРОК ДАННЫХ, две независимые тройки, разделённые тонкой линией, и
-- строка реклейма:
--   E ally overflow / E to allies / E own production   - энергия
--   M ally overflow / M to allies / M own production   - масса
--   reclaim E / M                                          - общая строка
--
-- Тройки НЕЗАВИСИМЫ: перелив энергии и перелив массы могут быть
-- противоположными, поэтому цвет каждого ресурса считается по своим числам.
--
-- ВСЕ числа приходят из modules/sync.lua - из синхронизации игры. Обход
-- армии и подмена выделения удалены: они были нужны только для строки
-- "own production", а теперь и она считается формулой. Поэтому мод больше
-- не трогает выделение, режим приказов и шаблоны хоткея.
--
-- ---------------------------------------------------------------------------
-- КАКИЕ СТРОКИ ПОКАЗЫВАТЬ РЕШАЕТ НАСТРОЙКА
--
-- Все семь строк можно включать и выключать по одной через "UI mods options"
-- и одним щелчком выбрать готовый набор - вплоть до одной строки
-- "E ally overflow". Определение строк и их названия лежат в rows.lua,
-- оттуда же берёт их страница настроек.
--
-- Из-за этого высота панели и положение строк БОЛЬШЕ НЕ ЗАДАНЫ ЧИСЛАМИ.
-- Раньше здесь стояло девять жёстких Y, и они годились только когда видны
-- все строки. Теперь координата каждой строки считается от числа ВИДИМЫХ
-- строк, см. ComputeBody.
--
-- Настройку применяет НЕ страница, а сама панель: страница UMT только пишет
-- в профиль, а Update() сравнивает подпись набора строк со своей и
-- перекладывает геометрию, когда набор изменился. Так страница не зависит
-- от порядка загрузки модулей - а он неизвестен.
--
-- НИЧЕГО НЕ ПЕРЕСОЗДАЁТСЯ при смене набора. Меняются только размеры и
-- видимость, поэтому перетаскивание, ресайз, сворачивание и закрытие
-- продолжают работать.
--
-- ---------------------------------------------------------------------------
-- WINDOW AND SIZE
--
-- The panel is a game Window (lua/maui/window.lua). The class moves and resizes
-- it and keeps its position and size in the profile under L.PANEL_KEY. The mod
-- only reacts: OnResize spreads the rows over the height, ApplyMinSize keeps the
-- window large enough for its text, OnMoveSet returns the height the player chose.
--
-- Nothing is recreated on resize. The window is rebuilt only when the look
-- changes, because colours are set in the constructors of the controls.
--
-- ---------------------------------------------------------------------------
-- STATE LIVES IN TABLE G
--
-- A function can capture at most 32 outer variables, otherwise the whole file
-- fails to compile with "too many upvalues (limit=32)". All panel state is kept
-- in one table, which costs one upvalue.

local UIUtil         = import('/lua/ui/uiutil.lua')
local Bitmap        = import('/lua/maui/bitmap.lua').Bitmap
local Group         = import('/lua/maui/group.lua').Group
local Window        = import('/lua/maui/window.lua').Window
local LayoutHelpers = import('/lua/maui/layouthelpers.lua')
local Prefs         = import('/lua/user/prefs.lua')
local GameMain      = import('/lua/ui/game/gamemain.lua')
local SyncModule    = import('/mods/Overflow/modules/sync.lua')
-- Поля модуля читаем ЧЕРЕЗ rawget, а не прямо.
--
-- У таблицы модуля есть __index, уходящий в _G, а на _G висит
-- метаметод из config.lua:56-61, который ОШИБКОЙ падает на любом
-- несуществующем глобале. Поэтому обычная проверка наличия поля
-- вида Mod.Start сама по себе роняет загрузку модуля, если поля
-- нет. rawget обходит __index и просто вернёт nil.
local SyncStart  = rawget(SyncModule, 'Start')
local SyncResult = rawget(SyncModule, 'GetResult')

-- Список строк живёт в rows.lua, там же названия для окна настроек. Правила
-- чтения те же самые: поля берём через rawget, иначе проверка наличия поля
-- сама роняет загрузку модуля.
local RowsModule  = import('/mods/Overflow/modules/rows.lua')
local RowsVisible = rawget(RowsModule, 'VisibleRows')
local RowsSign    = rawget(RowsModule, 'RowsSignature')
local RowsTell    = rawget(RowsModule, 'DescribeRows')

-- Оформление живёт в themes.lua: там же список названий для окна настроек.
-- Правила чтения те же самые - через rawget.
local ThemesModule = import('/mods/Overflow/modules/themes.lua')
local ThemeColors  = rawget(ThemesModule, 'StylePalette')
local ThemeBlink   = rawget(ThemesModule, 'ThemeBlinkOn')
local ThemeSign    = rawget(ThemesModule, 'ThemeSignature')
local ThemeTellIt  = rawget(ThemesModule, 'ThemeTell')
local ThemeFont    = rawget(ThemesModule, 'StyleFontSize')
local ThemeMinimal = rawget(ThemesModule, 'FrameMinimal')
local ThemeNumbers = rawget(ThemesModule, 'NumbersOnly')

local GetCursor    = GetCursor
local GetFrame     = GetFrame
local StringFormat = string.format
local MathAbs      = math.abs
local MathMax      = math.max
local MathMin      = math.min
local MathFloor    = math.floor
local TableGetn    = table.getn
local LOG          = LOG

--------------------------------------------------------------------------------
-- ДИАГНОСТИКА ЗАГРУЗКИ МОДУЛЯ ДАННЫХ
--
-- Если sync.lua не компилируется или падает при загрузке, панель всё равно
-- создастся - и будет пустой. Причём сообщение об ошибке вводит в заблуждение:
-- LuaPlus пишет 'access to nonexistent global variable "GetResult"' и
-- указывает строку В ЭТОМ файле, хотя виноват sync.lua.
--
-- Реальный случай: scan.lua:456 использовал оператор %, который движок не
-- поддерживает. Файл не загрузился, мод показал пустую панель, и по логу
-- казалось, что проблема в ui.lua.
--
-- Поэтому проверяем модуль сразу после импорта и говорим прямо.
--------------------------------------------------------------------------------

if type(SyncModule) ~= 'table' or type(SyncResult) ~= 'function' then
    LOG('Overflow: FATAL - sync.lua did not load, panel will be EMPTY. ' ..
        'Look for the real error earlier in this log.')
end

-- rows.lua отвечает только за то, какие строки показывать. Если он не
-- загрузился, данные всё равно идут, но панель покажет все строки молча -
-- поэтому говорим об этом прямо.
if type(RowsVisible) ~= 'function' or type(RowsSign) ~= 'function' then
    LOG('Overflow: FATAL - rows.lua did not load, showing all rows. ' ..
        'Look for the real error earlier in this log.')
    RowsVisible = nil
    RowsSign = nil
    RowsTell = nil
end

-- themes.lua отвечает только за цвета. Если он не загрузился, панель
-- покажется со встроенными ниже цветами - то есть ровно так, как выглядела
-- до появления тем. Молча менять оформление на другое нельзя.
if type(ThemeColors) ~= 'function' or type(ThemeSign) ~= 'function' then
    LOG('Overflow: FATAL - themes.lua did not load, using built-in colours. ' ..
        'Look for the real error earlier in this log.')
    ThemeColors  = nil
    ThemeBlink   = nil
    ThemeSign    = nil
    ThemeTellIt  = nil
    ThemeFont    = nil
    ThemeMinimal = nil
    ThemeNumbers = nil
end

--------------------------------------------------------------------------------
-- ТАБЛИЦЫ КОНСТАНТ
--------------------------------------------------------------------------------

-- Размеры строк внутри окна. Размер шрифта ФИКСИРОВАН: своя раскладка с
-- масштабом ушла вместе с самодельной рамкой. Теперь размер окна меняет
-- ресайз, а шрифт остаётся прежним при любом размере панели.
local L = {
    -- Ширина и высота по умолчанию. Высота рассчитана на все семь строк
    -- плюс заголовок окна в 30 пикселей и рамку вокруг.
    DEFAULT_W = 340,
    DEFAULT_H = 160,

    -- ОТСТУП ТЕКСТА ОТ БОРДЕРА. Задача игрока: сделать заметно больше.
    -- 10 пикселей - это примерно ширина одного знака при кегле 11,
    -- то есть текст перестаёт липнуть к рамке, но ещё не отрывается.
    PAD      = 10,
    PAD_TOP  = 8,

    -- ШАГ строки 14 пикселей: при шрифте 11-12 этого хватает, иначе семь
    -- строк не влезают в окно.
    ROW_STEP   = 14,
    ROW_H      = 14,

    DIV_PRE    = 0,           -- зазор перед разделителем
    DIV_POST   = 4,           -- зазор после разделителя
    DIV_H      = 1,           -- толщина линии-разделителя
    PAD_BOTTOM = 4,           -- поле под последней строкой

    -- ПОЛ РАЗМЕРА. Это именно ПОЛ, а не предел: настоящий предел мод
    -- считает по содержимому (см. ApplyMinSize) и берёт большее из двух.
    --
    -- Было 200 по ширине - жёсткое число. Панель не сжималась дальше, хотя
    -- текст был заметно короче окна, и пустое поле справа оставалось всегда.
    --
    -- НИЖЕ 92 ПО ШИРИНЕ ВСЁ РАВНО НЕ ОПУСТИТЬСЯ: сам класс Window не даёт
    -- окну стать уже суммы крестика и двух угловых кусков рамки
    -- (window.lua:310: _title.Width() + _closeBtn.Width() + 2*window_tl.Width()).
    -- У куска mini-map_brd_ul.dds ширина 36 px, то есть один углы забирают 72.
    --
    -- НИЖЕ 52 ПО ВЫСОТЕ - ТОЖЕ: класс не даёт окну стать ниже суммы верхнего
    -- и нижнего кусков рамки, 36 + 12 = 48 px (window.lua:320).
    MIN_W = 100,
    MIN_H = 52,

    -- РАМКА ОКНА. Класс забирает её из окна сам (window.lua:100-101:
    -- _borderSize = 5 по бокам, _cornerSize = 8 снизу). Числа нужны здесь,
    -- чтобы посчитать, сколько площади остаётся тексту.
    CLIENT_PAD_X = 5,
    FRAME_BOTTOM = 8,

    -- ОТСТУП ТЕКСТА ОТ ПРАВОГО БОРДЕРА. Вдвое больше левого (PAD): при самом
    -- подходящем размере текст упирался в рамку - жалоба игрока. Число входит
    -- и в ширину предельного размера, поэтому окно шире текста ровно на него.
    RIGHT_PAD = 20,

    -- ОДИН РАЗМЕР НА ВСЕ СТРОКИ. Раньше первая строка была размером 12,
    -- остальные 11 - и крупный шрифт давал другую метрику глифа, из-за чего
    -- первая строка выглядела сдвинутой вправо. Замер показал, что левые
    -- края у строк ОДИНАКОВЫ (L=476 и L=476), то есть дело было в шрифте.
    -- Размер шрифта фиксированный и одинаковый для всех строк.
    FONT       = 11,

    DEFAULT_LEFT = 8,
    DEFAULT_TOP  = 80,

    -- Ключ профиля для окна. Класс Window сам пишет в него положение и
    -- размер (window.lua:527-545). Точек в имени быть НЕ должно:
    -- GetFromCurrentProfile читает строку как путь по точкам.
    --
    -- Старый ключ 'OverflowPanelPos' в профиле остаётся и больше не читается.
    -- Формат у него другой, и класс на старом формате упал бы на
    -- арифметике с nil (window.lua:467-468).
    PANEL_KEY = 'OverflowPanel',

    -- Ключ профиля для свёрнутого состояния.
    COLLAPSE_KEY = 'OverflowCollapsed',

    -- порог тревоги: доля перелива от своей добычи, выше которой
    -- считаем опасной. 20% - уже заметная зависимость от союзника.
    WARN_RATIO = 0.2,
}

-- РАМКА ИЗ ТЕКСТУР МИНИКАРТЫ.
--
-- Тот же набор, что у миникарты (minimap.lua:97-108). Класс Window принимает
-- такую таблицу последним аргументом и подставляет её вместо своей
-- (window.lua:160-162), поэтому рамка и подложка окна получаются игровыми.
--
-- ЦВЕТ ФРАКЦИИ ЗДЕСЬ НЕ УКАЗЫВАЕТСЯ, и это не упущение: UIFile ведёт в
-- папку скина, поэтому на AEON приедет зелёная рамка, на Cybran бордовая, на
-- UEF голубая. Своих чисел здесь нет и быть не должно.
local function WindowBrd()
    -- Таблица собирается поимённо, а не литералом в return: литерал return в
    -- файле мода выглядит для validate_mod.py как попытка экспорта через
    -- return, а экспорт через return не работает.
    local brd = {}
    brd.tl = UIUtil.UIFile('/game/mini-map-brd/mini-map_brd_ul.dds')
    brd.tr = UIUtil.UIFile('/game/mini-map-brd/mini-map_brd_ur.dds')
    brd.tm = UIUtil.UIFile('/game/mini-map-brd/mini-map_brd_horz_um.dds')
    brd.ml = UIUtil.UIFile('/game/mini-map-brd/mini-map_brd_vert_l.dds')
    brd.m  = UIUtil.UIFile('/game/mini-map-brd/mini-map_brd_m.dds')
    brd.mr = UIUtil.UIFile('/game/mini-map-brd/mini-map_brd_vert_r.dds')
    brd.bl = UIUtil.UIFile('/game/mini-map-brd/mini-map_brd_ll.dds')
    brd.bm = UIUtil.UIFile('/game/mini-map-brd/mini-map_brd_lm.dds')
    brd.br = UIUtil.UIFile('/game/mini-map-brd/mini-map_brd_lr.dds')

    -- ЦВЕТ ЗАХВАТНЫХ ПОЛОС. Класс Window заливает им восемь полос ресайза и
    -- показывает их при наведении на край (window.lua:167-174 и :351). В игре
    -- там стоит 'ff415055', и на рамке своей яркости это читается как серое
    -- пятно поверх текстуры - рамка будто гаснет.
    --
    -- Ставим полностью прозрачный: полосы остаются кликабельными (альфа у
    -- них 0, а клик по невидимому работает - ровно так же у самой игры, см.
    -- комментарий в window.lua:108), курсор при наведении меняется, но серая
    -- подложка поверх рамки не появляется.
    brd.borderColor = '00000000'
    return brd
end

local C = {
    -- BG больше НЕ красит рамку. Он остался только как цвет кнопки
    -- возврата по умолчанию. Рамку красит её собственная подложка,
    -- см. ApplyFrameBackground ниже.
    BG      = 'E6101418',
    DIVIDER = 'FF405060',
    TITLE   = 'FF8FD0FF',
    SAFE    = 'FF5CE07A',
    WARN    = 'FFFFD24A',
    BAD     = 'FFEF5350',
    NEUTRAL = 'FF8A96A3',
    TOTAL   = 'FFFFD24A',
    CLOSED  = 'FF1E2A34',
}


--------------------------------------------------------------------------------
-- ПРИМЕНЕНИЕ ТЕМЫ
--
-- Таблица C - это ТЕКУЩАЯ тема, а не константа. Значения приходят из
-- themes.lua и раскладываются поимённо, поэтому все 25 мест, где читается
-- C.*, продолжают работать без единой правки.
--
-- Таблица намеренно не заменяется целиком на новую: тогда пришлось бы менять
-- ссылку C в двадцати пяти местах. Перезаписываем поля - ссылка та же.
--
-- Присваивание идёт через `or C.*`: если themes.lua вернёт неполную тему,
-- останутся прежние значения, а не nil. Панель с nil-цветом не рисуется
-- вообще, это худший из возможных исходов.
--------------------------------------------------------------------------------

local function ApplyTheme()
    if not ThemeColors then
        return false
    end

    local ok, pal = pcall(ThemeColors)
    if not ok or type(pal) ~= 'table' then
        LOG('Overflow: theme FAILED, keeping previous colours: ' ..
            tostring(pal))
        return false
    end

    C.BG      = pal.BG      or C.BG
    C.CLOSED  = pal.CLOSED  or C.CLOSED
    C.DIVIDER = pal.DIVIDER or C.DIVIDER
    C.TITLE   = pal.TITLE   or C.TITLE
    C.TOTAL   = pal.TOTAL   or C.TOTAL
    C.NEUTRAL = pal.NEUTRAL or C.NEUTRAL
    C.SAFE    = pal.SAFE    or C.SAFE
    C.WARN    = pal.WARN    or C.WARN
    C.BAD     = pal.BAD     or C.BAD

    return true
end

-- Подпись оформления, на которой сейчас построена панель. Update() сравнивает
-- её с текущей и перестраивает панель при изменении - тем же приёмом, что и
-- для строк.
local function ThemeSignatureNow()
    if not ThemeSign then
        return nil
    end
    local ok, sig = pcall(ThemeSign)
    if not ok then
        return nil
    end
    return sig
end

--------------------------------------------------------------------------------
-- КАКИЕ СТРОКИ И КАК ОНИ ИДУТ
--
-- Порядок и названия строк живут в rows.lua: оттуда же берёт их страница
-- настроек, чтобы окно и панель не разошлись в том, как строка называется.
-- Здесь только ПОРЯДОК и разделители - это уже часть раскладки, а не
-- содержания.
--
-- ПОРЯДОК ОБЯЗАТЕЛ и обязан совпадать с порядком в rows.lua. Расхождение
-- даст панель, где галка «M to allies» прячет строку «E to allies».
--
-- РАЗДЕЛИТЕЛЬ рисуется только если НАД НИМ есть хоть одна видимая строка.
-- Без этого правила при выборе одной строки снизу осталась бы тонкая линия
-- над пустотой.
--
-- Эти таблицы объявлены ДО ApplyLayout не по вкусу, а по необходимости:
-- ApplyLayout захватывает их как upvalue, и если объявить их ниже, то внутри
-- функции они разрешатся как ГЛОБАЛЬНЫЕ переменные, а чтение несуществующей
-- глобальной переменной в этом движке фатально.
--------------------------------------------------------------------------------

local ROW_ORDER   = { 'eOverflow', 'eGo', 'eOwn', 'mOverflow', 'mGo',
                      'mOwn', 'total' }

-- какой разделитель перед какой строкой
local ROW_DIVIDER = { mOverflow = 'divider1', total = 'divider2' }

-- размер шрифта каждой строки. Строки перелива крупнее: их читают чаще.
local ROW_FONT = {
    eOverflow = 12,
    eGo       = 11,
    eOwn      = 11,
    mOverflow = 12,
    mGo       = 11,
    mOwn      = 11,
    total     = 11,
}

-- ВСЁ, что относится к телу панели и должно прятаться вместе с ним.
-- Порядок здесь не важен: сначала прячем всё это, потом показываем нужное.
--
-- ВАЖНО: список должен содержать ВСЕ строки данных. Раньше здесь не хватало
-- eGo и mGo, и сворачивание оставляло их висеть под шапкой: Hide() до них не
-- доходил, а панель сжималась до L.HEADER. Group детей не обрезает -
-- lua/maui/group.lua знает только InternalCreateGroup, обрезание есть лишь
-- у текста (lua/maui/text.lua:44, SetClipToWidth), и мод его не использует.
local BODY_KEYS = { 'eOverflow', 'eGo', 'eOwn', 'divider1',
                    'mOverflow', 'mGo', 'mOwn', 'divider2', 'total' }

-- КЛЮЧИ ПРОФИЛЯ ВАЖНЫ: в них НЕ должно быть точек.
-- SetToCurrentProfile создаёт ОДИН ключ с точкой внутри имени, а
-- GetFromCurrentProfile читает строку как ПУТЬ ПО ТОЧКАМ и ищет узлы
-- <профиль> -> 'Overflow' -> 'panelPos'. Узла 'Overflow' нет, поэтому
-- чтение всегда возвращает nil.
--
-- Ключи объявлены в L: L.PANEL_KEY ведёт окно класса Window (положение и
-- размер), L.COLLAPSE_KEY - свёрнутое состояние. Старый ключ
-- 'OverflowPanelPos' больше не читается и в коде не упоминается.

--------------------------------------------------------------------------------
-- СОСТОЯНИЕ - всё в одной таблице, см. предупреждение выше
--------------------------------------------------------------------------------

local G = {
    ---@type Window?
    win       = nil,        -- окно игры (класс Window)
    reopenButton = nil,     -- кнопка, возвращающая свёрнутую панель
    labels    = {},
    collapsed = false,
    beatErrors = 0,         -- ошибок Update подряд

    -- Подпись набора строк, под который сейчас собрана панель. Update()
    -- сравнивает её с текущей и перекладывает раскладку при изменении -
    -- тем же приёмом, что и для оформления.
    rowsSig   = nil,
    themeSig  = nil,

    -- Мигание тревожной строки. blinkWanted - что выбрал игрок, blinkOn -
    -- текущая фаза, blinkRun - сколько раз строка уже мигала.
    --
    -- Флаги разведены намеренно: если бы при выключенной галочке мы просто
    -- не трогали blinkOn, он всё равно переключался бы на чётное число, и
    -- строка загоралась бы приглушённым цветом.
    blinkWanted = false,
    blinkRun  = 0,
    blinkOn   = false,

    -- ВЫСОТА, КОТОРУЮ ИГРОК ПОДОБРАЛ САМ. Заполняется только когда игрок
    -- потянул окно за край. После этого его выбор главный: подгонка под
    -- содержимое может только ДОРАСТИТЬ до окна, но никогда не срезает его.
    wantH     = nil,

    -- Подложка рамки Minimal: СПИСОК из двух Bitmap с текстурой игры под
    -- окном. Два, а не один, потому что встроенную линию текстуры нужно
    -- пропустить - см. FRAME_LINE_TOP. Живут не в окне, а в GetFrame(0),
    -- поэтому и при пересборке окна, и при сворачивании их надо гасить
    -- вручную - см. ApplyFrameBackground и ShowFrameBg.
    frameBg   = nil,

    -- Набор видимых строк, снятый в LayoutRows. ApplyMinSize спрашивает его
    -- отсюда, чтобы не читать профиль второй раз на каждый проход.
    visSet    = nil,

    -- Последняя раскладка тела: список строк с их ЕСТЕСТВЕННЫМИ координатами,
    -- их число и естественная высота тела. Нужна PlaceRows, чтобы пересчитать
    -- позиции при протяжке окна за край, не собирая раскладку заново.
    bodyItems = nil,
    bodyCount = 0,
    bodyH     = 0,
}

--------------------------------------------------------------------------------
-- РАМКА MINIMAL: ПОДЛОЖКА ИЗ ТЕКСТУРЫ ИГРЫ
--
-- Задача игрока - рамка «максимально минималистичная, как панели мода
-- Selection Cost UI». Разобрал тот мод, панель у него сделана так
-- (mods/Selection Cost UI/hook/lua/ui/game/gamemain.lua:47-49):
--
--     statsFrame = Bitmap(GUI.bg)
--     statsFrame:SetTexture(UIUtil.UIFile(
--         '/game/filter-ping-panel/filter-ping-panel02_bmp.dds'))
--     LayoutHelpers.SetDimensions(statsFrame, 110, 45)
--
-- То есть это НЕ окно, а обычный Bitmap с одной игровой текстурой: размер
-- задан руками и никогда не меняется. Панели слева на скриншоте игрока -
-- она и есть.
--
-- Текстуру я распаковал из textures.scd и посмотрел, а не взял по названию:
-- textures/ui/aeon/game/filter-ping-panel/filter-ping-panel02_bmp.dds, 180x72.
-- Первые 4 px по краям прозрачны, дальше идёт тонкий зелёный контур
-- (#6BAA4A при прозрачности 229), а поле - чёрное с прозрачностью 54 из 255.
-- «Слегка прозрачная подложка» в игре уже есть, значит свои числа не нужны.
--
-- ЧТО БЫЛО СЛОМАНО. Заливка брала цвет из ПРЕСЕТА оформления, а не из
-- настройки «Рамка окна». При рамке Minimal и пресете Vanilla она брала
-- прозрачную панель игры AA4A5D6B (skins.lua:172) - то самое серое пятно,
-- о котором сообщил игрок. Цвет вдобавок зависел от карты под панелью: на
-- тёмной карте выходило почти чёрное, на светло-серой - серое.
--
-- ПОЧЕМУ ПЛОСКАЯ ЗАЛИВКА НЕ ГОДИТСЯ. Девять кусков window_tl ... window_br у
-- игры разной толщины: угол mini-map_brd_ul.dds 36x36, край
-- mini-map_brd_horz_um.dds 12x36, бок mini-map_brd_vert_l.dds 16x12. Ровным
-- цветом из них получается широкая полоса 12-16 px, а тонкого контура в 2 px
-- не выйдет никак. Поэтому в Minimal куски окна гасятся, а фон рисует
-- отдельный Bitmap с текстурой.
--
-- ЧЕСТ О РАСТЯЖЕНИИ. Текстура тянется на всё окно, а не плиткуется, поэтому
-- тонкий контур у неё растягивается вместе с окном: на панели вдвое шире
-- исходной контур станет вдвое толще. Это осознанный размен - ровно так же
-- сделано у Selection Cost UI, просто там окно никогда не меняет размер.
--
-- ВСТРОЕННАЯ ЛИНИЯ ТЕКСТУРЫ - ВТОРАЯ НАХОДКА.
--
-- Кроме контура, в текстуре есть СВОЯ линия-разделитель на середине: y=35 из
-- 72, во всю ширину, #6BAA4A при прозрачности 251. Замер по распакованному
-- файлу, и он одинаков у всех четырёх скинов: 180x72, доля 0.486.
--
-- Selection Cost UI берёт эту текстуру в размере 110x45 и получает линию ровно
-- между своими двумя строками - она линию и использует, отдельной не рисует
-- (gamemain.lua:47-49, 55-73: там только четыре подписи и ничего больше).
--
-- Мы же тянем текстуру на всё окно, поэтому её линия уезжает на СЕРЕДИНУ окна
-- и оказывается там, где никакой границы нет: у игрока две строки стоят
-- сверху, а линия висит в пустоте ниже них, рядом с нашим разделителем. Игрок
-- описал это так: «есть строка-разделитель, но что она разделяет, если
-- значения и окно живут разными жизнями». Линий выходило две.
--
-- Поэтому фон рисуется ДВУМЯ кусками, а встроенная линия между ними
-- ПРОПУСКАЕТСЯ: верхний кусок берёт строки 0..34 текстуры, нижний 36..71.
-- Режем через SetUV (maui/bitmap.lua:4) - так же поступает игра в
-- ui/game/statusbar.lua:46-83.
--
-- Боковые линии текстуры при этом остаются целыми: они идут по всей высоте
-- файла, а по ширине куски не режутся вовсе. Шов приходится на середину окна
-- и ничем не виден: поле текстуры там ровное.
--
-- ПОЛЕ window_* - НЕ ПОДЧЁРКНУТОЕ, в отличие от _resizeGroup, и создаётся
-- в ApplyWindowTextures при каждой сборке окна, то есть всегда есть. Но это
-- всё же устройство класса, поэтому гашение идёт под pcall с записью в лог:
-- если класс когда-нибудь переименует поле, панель останется рабочей, просто
-- покажет игровую рамку.
--------------------------------------------------------------------------------
local WINDOW_PARTS = {
    'window_tl', 'window_tr', 'window_tm',
    'window_ml', 'window_m',  'window_mr',
    'window_bl', 'window_bm', 'window_br',
}

-- Путь идёт через UIFile, а тот ведёт в папку скина (uiutil.lua:423-443), так
-- что подложка меняет вид вместе с фракцией - ровно как в игре и как у
-- Selection Cost UI.
local FRAME_BG_TEXTURE =
    '/game/filter-ping-panel/filter-ping-panel02_bmp.dds'

-- Где в текстуре её встроенная линия, в долях высоты файла.
--
-- Доли, а не доли пикселя, потому что SetUV работает в долях. Числа сняты с
-- распакованного файла (180x72, линия на строке 35) и потому не зависят от
-- размера окна. Проверено у всех четырёх скинов: файл один и тот же 180x72,
-- линия на той же строке 35.
local FRAME_LINE_TOP    = 35 / 72
local FRAME_LINE_BOTTOM = 36 / 72

--------------------------------------------------------------------------------
-- ПОКАЗ И СПРЯТЫВАНИЕ ПОДЛОЖКИ
--
-- Подложка живёт в GetFrame(0), а НЕ в окне, и вместе с окном не исчезает.
-- Поэтому сворачивание обязано гасить её отдельно: без этого крестик убирал
-- только значения, а пустая рамка оставалась висеть на экране - ровно то, о
-- чём сообщил игрок.
--------------------------------------------------------------------------------
local function ShowFrameBg(show)
    if not G.frameBg then return end
    for i = 1, TableGetn(G.frameBg) do
        if show then
            G.frameBg[i]:Show()
        else
            G.frameBg[i]:Hide()
        end
    end
end

local function ApplyFrameBackground(win)
    -- Прежняя подложка подвешена к GetFrame(0), а не к окну, и вместе с окном
    -- не умирает. Без этой строки она осталась бы висеть на экране после
    -- возврата на игровую рамку.
    if G.frameBg then
        for i = 1, TableGetn(G.frameBg) do
            G.frameBg[i]:Destroy()
        end
        G.frameBg = nil
    end

    if not ThemeMinimal then
        return
    end
    local okMin, wantMin = pcall(ThemeMinimal)
    if not okMin or not wantMin then
        return
    end

    local ok, miss = pcall(function()
        for i = 1, TableGetn(WINDOW_PARTS) do
            local piece = win[WINDOW_PARTS[i]]
            if not piece then
                return WINDOW_PARTS[i]
            end
            piece:SetSolidColor('00000000')
        end
        return nil
    end)
    if not ok then
        LOG('Overflow: minimal frame FAILED: ' .. tostring(miss))
    elseif miss then
        LOG('Overflow: minimal frame incomplete, no field ' .. miss)
    end

    -- СЕРЕДИНА ОКНА. По ней сходятся два куска подложки, и ровно по ней
    -- текстура разрезана. Считается от границ окна, а не от ClientGroup:
    -- подложка рисует рамку целиком, включая поля, которых у клиентской
    -- области нет.
    local function midY()
        return win.Top() + (win.Bottom() - win.Top()) / 2
    end

    -- Один кусок подложки: общая часть у обоих.
    local function MakePiece(vFrom, vTo)
        local piece = Bitmap(GetFrame(0))
        -- Глубина на единицу меньше окна. Окно всегда на 20 (см. CreatePanel),
        -- и класс Window свою глубину сам не меняет, поэтому здесь число, а не
        -- функция от win.Depth().
        piece.Depth:Set(19)
        -- SetUV идёт СТРОГО после SetTexture: он режет уже назначенную
        -- текстуру, а не задаёт её.
        piece:SetTexture(UIUtil.UIFile(FRAME_BG_TEXTURE))
        piece:SetUV(0, vFrom, 1, vTo)
        piece:DisableHitTest()
        -- Размер окна меняется: игрок тянет за край. Поэтому все четыре
        -- стороны заданы функциями, а не числами, - иначе подложка осталась
        -- бы прежнего размера.
        piece.Left:Set(function() return win.Left() end)
        piece.Width:Set(function() return win.Right() - win.Left() end)
        return piece
    end

    local okBg, errBg = pcall(function()
        local top = MakePiece(0, FRAME_LINE_TOP)
        top.Top:Set(function() return win.Top() end)
        top.Height:Set(function() return midY() - win.Top() end)

        local bot = MakePiece(FRAME_LINE_BOTTOM, 1)
        bot.Top:Set(midY)
        bot.Height:Set(function() return win.Bottom() - midY() end)

        G.frameBg = {}
        G.frameBg[1] = top
        G.frameBg[2] = bot
    end)
    if not okBg then
        -- Панель обязана остаться рабочей: без подложки будет видна игровая
        -- рамка, и это лучше падения всей перерисовки.
        LOG('Overflow: minimal frame background FAILED: ' .. tostring(errBg))
    end
end

--------------------------------------------------------------------------------
-- ВИДИМЫЕ СТРОКИ
--
-- Читаем из rows.lua. Если тот не загрузился, показываем всё: молча сменить
-- набор на пустой нельзя, игрок решил бы, что мод сломался.
--------------------------------------------------------------------------------

local function VisibleSet()
    if RowsVisible then
        return RowsVisible()
    end
    -- rows.lua не загрузился: показываем всё. Таблица собирается поимённо,
    -- а не литералом в return: литерал return в файле мода выглядит для
    -- validate_mod.py как попытка экспорта через return, а экспорт через
    -- return не работает.
    local out = {}
    out.eOverflow = true
    out.eGo       = true
    out.eOwn      = true
    out.mOverflow = true
    out.mGo       = true
    out.mOwn      = true
    out.total     = true
    return out
end

--------------------------------------------------------------------------------
-- ФОРМАТИРОВАНИЕ ЧИСЕЛ
--------------------------------------------------------------------------------

local function Num(v)
    if v == nil then return '0' end
    if v >= 1000 then return StringFormat('%.0f', v) end
    return StringFormat('%.1f', v)
end

--------------------------------------------------------------------------------
-- ЭЛЕМЕНТЫ
--
-- Размер шрифта фиксирован: раньше он домножался на масштаб панели, теперь
-- масштаба нет. Чтобы текст стал крупнее, нужен размер в настройках мода, а не
-- движок окна.
--------------------------------------------------------------------------------

local function MakeLabel(parent, textSize, color)
    local label = UIUtil.CreateText(parent, '', textSize, UIUtil.bodyFont)
    label:SetColor(color)
    label:SetDropShadow(true)
    label:DisableHitTest(true)
    return label
end

local function MakeDivider(parent)
    local bar = Bitmap(parent)
    bar.Depth:Set(20)
    bar:SetSolidColor(C.DIVIDER)
    bar:DisableHitTest(true)
    return bar
end

--------------------------------------------------------------------------------
-- РАСКЛАДКА ТЕЛА ПО ВИДИМЫМ СТРОКАМ
--
-- Возвращает список того, что показывать (с координатой Y ОТНОСИТЕЛЬНО ВЕРХА
-- окна и признаком «это разделитель»), сколько этого всего, и сколько
-- пикселей нужно телу.
--
-- Считается ОТ ЧИЛА ВИДИМЫХ СТРОК, поэтому окно с одной строкой в семь раз
-- ниже окна со всеми, и пустоты под последней строкой не остаётся.
--
-- Второе значение возвращается отдельным счётчиком, потому что оператор #
-- движком не поддерживается.
--------------------------------------------------------------------------------

local function ComputeBody(vis)
    local items = {}
    local howMany = 0
    local y = L.PAD_TOP
    local anyAbove = false

    for i = 1, TableGetn(ROW_ORDER) do
        local rowKey = ROW_ORDER[i]
        if vis[rowKey] then
            local div = ROW_DIVIDER[rowKey]
            if div and anyAbove then
                howMany = howMany + 1
                items[howMany] = { id = div, divider = true, y = y + L.DIV_PRE }
                y = y + L.DIV_PRE + L.DIV_POST
            end
            howMany = howMany + 1
            items[howMany] = { id = rowKey, divider = false, y = y }
            y = y + L.ROW_STEP
            anyAbove = true
        end
    end

    local bodyH = 0
    if howMany > 0 then
        -- y уже уехал на шаг ПОСЛЕДНЕЙ строки, поэтому её низ - это y
        -- минус шаг.
        bodyH = (y - L.ROW_STEP) + L.PAD_BOTTOM
    end

    return items, howMany, bodyH
end

--------------------------------------------------------------------------------
-- ОТСТУП СТРОКИ СПРАВА
--
-- Крестик закрытия висит в правом верхнем углу окна (window.lua:246-251), а
-- пустой полосы заголовка над строками больше нет (см. CreatePanel). Значит
-- верхние строки проходят прямо под крестиком.
--
-- Отступает ТОЛЬКО та строка, которая с крестиком пересекается. Отступить
-- всем значило бы держать пустое поле справа у каждой строки, а задача игрока
-- - как раз убрать пустоту. Ниже крестика строка идёт во всю ширину.
--
-- Считаем от РЕАЛЬНОГО положения кнопки, а не от числа: в другом скине
-- крестик другого размера.
--------------------------------------------------------------------------------
local function RowRightInset(top)
    -- The Window constructor sets _closeBtn, but the class annotations do not
    -- declare it.
    ---@diagnostic disable-next-line: undefined-field
    if not G.win or not G.win._closeBtn then return L.RIGHT_PAD end
    local ok, inset = pcall(function()
        local client = G.win.ClientGroup
        ---@diagnostic disable-next-line: undefined-field
        local btn = G.win._closeBtn
        local btnTop = btn.Top() - client.Top()
        local btnBottom = btn.Bottom() - client.Top()
        if top >= btnBottom or (top + L.ROW_H) <= btnTop then
            return L.RIGHT_PAD
        end
        local over = client.Right() - btn.Left() + L.RIGHT_PAD
        if over > L.RIGHT_PAD then return over end
        return L.RIGHT_PAD
    end)
    if ok and type(inset) == 'number' then return inset end
    return L.RIGHT_PAD
end

--------------------------------------------------------------------------------
-- ШИРИНА СТРОКИ В ПИКСЕЛЯХ
--
-- МЕРЯЕМ, А НЕ СЧИТАЕМ ПО ЗНАКАМ. У букв разная ширина, и прикидка "длина
-- строки на среднюю ширину глифа" на подписях вроде 'E ally overflow'
-- промахивается. Штатная функция контрола GetStringAdvance (maui/text.lua,
-- так же меряют в uiutil.lua:1054 и ui/dialogs/createunit.lua:2120) даёт
-- настоящую ширину строки в пикселях.
--
-- ПОД pcall. Если функция когда-нибудь исчезнет, панель обязана остаться
-- рабочей: ширина выйдет нулевой, предел станет прежним - L.MIN_W.
--------------------------------------------------------------------------------
local function RowTextWidth(ctl)
    if not ctl then return 0 end
    local ok, w = pcall(function()
        return ctl:GetStringAdvance(ctl:GetText())
    end)
    if ok and type(w) == 'number' and w > 0 then return w end
    return 0
end

--------------------------------------------------------------------------------
-- ПРЕДЕЛ РАЗМЕРА ОКНА ПО СОДЕРЖИМОМУ
--
-- Класс Window о содержимом не знает и не даёт окну стать меньше суммы кусков
-- рамки (window.lua:310, :320). Всё остальное - на нас: без этого окно
-- сжималось до 52 px, а текст уезжал за рамку.
--
-- ШИРИНА - по САМОЙ ДЛИННОЙ видимой строке плюс её отступы. Поэтому окно
-- не сжать уже, чем нужно строке, и текст никогда не обрежется; и наоборот,
-- пустого поля справа у окна не остаётся.
--
-- ВЫСОТА - по числу видимых строк плюс нижняя рамка. Поэтому окно не сжать
-- ниже, чем нужно строкам, и текст не вылезет вниз.
--------------------------------------------------------------------------------
local function ApplyMinSize()
    if not G.win then return end
    local vis = G.visSet
    if not vis then return end
    local items, howMany, bodyH = ComputeBody(vis)

    local widest = 0
    for i = 1, howMany do
        local it = items[i]
        if not it.divider then
            -- RowTextWidth даёт ЭКРАННЫЕ пиксели - так его и применяет сама
            -- игра (uiutil.lua:1054 сравнивает им ширину контрола). А предел
            -- размера считается в СВОИХ единицах: SetMinimumResize умножает
            -- число на масштаб интерфейса (window.lua:571-573). Поэтому
            -- ширина текста приводится к своим, иначе на масштабе 2 окно
            -- вышло бы вдвое шире нужного.
            local need = LayoutHelpers.InvScaleNumber(
                RowTextWidth(G.labels[it.id])) + L.PAD
                + RowRightInset(it.y)
            if need > widest then widest = need end
        end
    end

    local minW = widest + L.CLIENT_PAD_X * 2
    if minW < L.MIN_W then minW = L.MIN_W end

    local minH = bodyH + L.FRAME_BOTTOM
    if minH < L.MIN_H then minH = L.MIN_H end

    -- Под pcall: это единственный вызов в класс отсюда, и уронить им весь
    -- проход отрисовки нельзя.
    pcall(function()
        G.win:SetMinimumResize(minW, minH)
    end)

    -- ПОДРАСТИ, ЕСЛИ СОДЕРЖИМОЕ УЖЕ НЕ ВЛЕЗАЕТ.
    --
    -- SetMinimumResize ограничивает только ПРОТЯЖКУ игрока: окно, которое уже
    -- стало меньше, оно не двигает. А стать меньше оно может - если включили
    -- больше строк или подняли масштаб шрифта, текст становится шире. Тогда
    -- текст выходит за рамку: ровно это игрок и увидел на скриншотах. Поэтому
    -- окно доращивается само.
    --
    -- Растёт ТОЛЬКО до предела и только когда не хватает: если размер уже
    -- больше, не трогаем ни строки - иначе растянутое игроком окно дёргалось
    -- бы назад на каждом проходе.
    --
    -- Через ScaleNumber, потому что предел считается в своих единицах, а
    -- Left/Right окна - в экранных: SetMinimumResize делает то же самое
    -- внутри себя (window.lua:571-573).
    pcall(function()
        local wantW = LayoutHelpers.ScaleNumber(minW)
        local wantH = LayoutHelpers.ScaleNumber(minH)
        if G.win.Right() - G.win.Left() < wantW then
            G.win.Right:Set(G.win.Left() + wantW)
        end
        if G.win.Bottom() - G.win.Top() < wantH then
            G.win.Bottom:Set(G.win.Top() + wantH)
        end
    end)
end

--------------------------------------------------------------------------------
-- РАССТАНОВКА СТРОК ПО ОКНУ
--
-- Отдельно от LayoutRows, потому что зовётся ещё и при протяжке окна за край:
-- набор строк тогда не меняется, меняется только высота панели.
--
-- СТРОКИ РАЗЪЕЗЖАЮТСЯ ПО ВЫСОТЕ. Промежутки между строками растут, пока
-- тело не заполнит панель. Панель ровно по содержимому - промежутков нет
-- вовсе; игрок растянул панель выше - они появляются и делят пустоту поровну.
-- Игрок выбрал именно это поведение.
--
-- Кегль при этом НЕ растёт: строка - подпись фиксированного размера, и
-- увеличивать сам текст нечем (размер берётся у MakeLabel при сборке окна).
-- Растут только промежутки.
--
-- ПОЧЕМУ ПРОМЕЖУТКИ, А НЕ УМНОЖЕНИЕ КООРДИНАТ. Первая редакция умножала
-- координату строки на коэффициент растяжения. Это неверно: высота строки при
-- этом не меняется, поэтому нижняя строка уезжала за край панели - проверка
-- «строки остаются внутри панели» это и поймала. Промежутки же считаются от
-- ОСТАТКА места, поэтому нижняя строка всегда встаёт ровно по нижнему полю.
--------------------------------------------------------------------------------
local function PlaceRows()
    if not G.win or not G.bodyItems then return end
    local client = G.win.ClientGroup

    -- СКОЛЬКО МЕСТА ДОСТАЁТСЯ ПРОМЕЖУТКАМ.
    --
    -- Сколько места есть - читаем у клиентской области, а сколько занимает
    -- само содержимое - знаем из ComputeBody. Числа эти в РАЗНЫХ единицах:
    -- клиентская высота в экранных пикселях, наши - в своих, и при масштабе
    -- интерфейса 2 они различаются вдвое. Поэтому приводим экранные к своим
    -- через InvScaleNumber (layouthelpers.lua:64; тот же приём для позиции окна
    -- взят из massfabs.lua:228-238, см. шапку файла).
    --
    -- Содержимое занимает от PAD_TOP до низа ПОСЛЕДНЕЙ СТРОКИ. Низ последней
    -- строки - это её верх плюс ROW_H, а верх последней строки в bodyH уже
    -- учтён вместе с PAD_BOTTOM (ComputeBody). Отсюда span.
    local gap = 0
    local n = G.bodyCount
    if n > 1 then
        local room = LayoutHelpers.InvScaleNumber(client.Bottom() - client.Top())
        local span = (G.bodyH - L.PAD_BOTTOM - L.PAD_TOP) + L.ROW_H
        local extra = room - L.PAD_TOP - L.PAD_BOTTOM - span
        if extra > 0 then
            gap = extra / (n - 1)
        end
    end

    for i = 1, n do
        local it = G.bodyItems[i]
        local ctl = G.labels[it.id]
        if ctl then
            -- К естественной координате добавляется по одному промежутку за
            -- каждый элемент ПЕРЕД этим. Первая строка остаётся на своём
            -- PAD_TOP, последняя встаёт ровно по нижнему полю. При пустой
            -- панели (gap = 0) выходит ровно прежняя раскладка.
            local top = it.y + (i - 1) * gap
            if it.divider then
                -- РАЗДЕЛИТЕЛЮ НУЖЕН И Top. Без него у контрола заданы
                -- только Height, Left и Right, круг движка не замкнут, и
                -- чтение Top() уходит в переполнение стека
                -- (control.lua:31-42; в логе это предупреждение LazyVar).
                ctl.Height:Set(L.DIV_H)
                LayoutHelpers.AtLeftIn(ctl, client, 0)
                LayoutHelpers.AtRightIn(ctl, client, 0)
                LayoutHelpers.AtTopIn(ctl, client, top)
            else
                ctl.Height:Set(L.ROW_H)
                LayoutHelpers.AtLeftTopIn(ctl, client, L.PAD, top)
                -- Отступ справа считаем по РАСТЯНУТОЙ координате: крестик
                -- закрытия висит на неподвижном верхнем углу, а строка при
                -- растяжении уезжает вниз и уходит из-под него.
                LayoutHelpers.AtRightIn(ctl, client, RowRightInset(top))
            end
        end
    end
end

--------------------------------------------------------------------------------
-- СБОРКА РАСКЛАДКИ
--
-- Здесь решается, ЧТО показывать и в каком порядке, а где это стоит -
-- в PlaceRows. Так сделано потому, что при протяжке окна меняется только
-- второе.
--------------------------------------------------------------------------------

local function LayoutRows()
    if not G.win then return 0 end

    local client = G.win.ClientGroup
    -- Набор видимых строк запоминаем: его же спрашивает ApplyMinSize, а ей
    -- незачем читать профиль второй раз на каждый проход.
    local vis = VisibleSet()
    G.visSet = vis
    local items, howMany, bodyH = ComputeBody(vis)

    -- СПИСОК ТОГО, ЧТО ОСТАЛОСЬ НА ЭКРАНЕ. Сначала собираем его целиком,
    -- и только потом прячем всё остальное: снимать галочку с последней строки
    -- нельзя, пока не станет ясно, что больше не нужно показывать ничего.
    local want = {}
    for i = 1, howMany do
        want[items[i].id] = true
    end

    -- ПРЯЧЕТ ТЕ, ЧТО ВЫКЛЮЧЕНО. Раньше это делала старая раскладка; после
    -- перехода на окно класс о выключенных строках не знает ничего, и без
    -- этого цикла они остались бы на экране со старым текстом.
    local many = TableGetn(BODY_KEYS)
    for i = 1, many do
        local ctl = G.labels[BODY_KEYS[i]]
        if ctl then
            if want[BODY_KEYS[i]] then
                ctl:Show()
            else
                ctl:Hide()
            end
        end
    end

    -- Раскладку запоминаем: при протяжке окна за край набор строк не
    -- меняется, и пересобрать её заново не нужно - хватит PlaceRows.
    --
    -- ШТАТНЫЕ ПОМОЩНИКИ ИГРЫ, а не привязка руками. Разница не
    -- косметическая: AtLeftIn/AtTopIn делают MathFloor и умножают отступ на
    -- pixelScaleFactor (layouthelpers.lua:384-420), а наша привязка не делала
    -- ни того, ни другого. Плюс задаются сразу ОБЕ грани, поэтому ширину
    -- подписи не считает сам Text.
    G.bodyItems = items
    G.bodyCount = howMany
    G.bodyH = bodyH
    PlaceRows()

    -- Предел размера ставим ЗДЕСЬ, а не только на проходе отрисовки: набор
    -- строк меняется редко, но после него окно должно упереться в новый
    -- предел сразу, а не через секунду до ближайшего beat.
    ApplyMinSize()

    return howMany
end

--------------------------------------------------------------------------------
-- ВЫСОТА ОКНА ПО СОДЕРЖИМОМУ
--
-- Высота ставится ТОЛЬКО при создании окна и при смене набора строк. Ни
-- ресайз, ни перетаскивание её не трогают - иначе размер, подогнанный
-- игроком, возвращался бы к высоте содержимого при первом же движении мыши.
--
-- Ширину мод не трогает вовсе: её подбирает игрок.
--
-- ЧТО ИМЕННО ЗАБИРАЕТ ОКНО ПОД РАМКУ. Пустой полосы заголовка над строками нет
-- (см. CreatePanel), поэтому сверху не отнимается ничего, а снизу остаётся
-- нижний кусок рамки - 8 px (window.lua:129, _cornerSize).
--------------------------------------------------------------------------------

-- ВЫСОТУ ОКНА КЛАССА Window ЗАДАЁТ Bottom, А НЕ Height.
--
-- window.lua НИ РАЗУ не выставляет Height: он задаёт Left, Top, Right и
-- Bottom (window.lua:469-511), а Height выводится из Bottom и Top
-- (control.lua:41). Если написать Height:Set(n), у окна останутся ОБА
-- значения - и Height, и Bottom, - и Height перестанет следовать за Bottom.
--
-- Именно это и подтвердил лог: после Height:Set(82) пятнадцать событий
-- ресайза подряд показали высоту 82 - высоту содержимого, а не ту, которую
-- игрок вытянул. Окно выглядело выше, а Height() врало.
--
-- Поэтому высота ставится через Bottom - ровно так, как это делает сам класс.
local function SetWindowHeight(want)
    G.win.Bottom:Set(G.win.Top() + want)
end

local function FitHeight(bodyH)
    if not G.win then return end
    local want = bodyH + L.FRAME_BOTTOM
    if want < L.MIN_H then want = L.MIN_H end
    -- ВЫБОР ИГРОКА ГЛАВНЫЙ. Если он уже тянул окно за край, его высоту мы не
    -- режем: окно может только дорасти, если строк перестало хватать.
    if G.wantH and G.wantH > want then want = G.wantH end
    SetWindowHeight(want)
end

-- ВЕРНУТЬ ВЫСОТУ, ПОДОБРАННУЮ ИГРОКОМ.
--
-- Класс при переносе перезаписывает Right и Bottom значениями, снятыми на
-- ButtonPress (window.lua:394-402). По собственным расчётам класса размер
-- должен сохраниться, и в большинстве окон он и сохраняется - но проверить
-- это без запуска в игре нельзя. Поэтому после каждого шага переноса мы
-- перевыставляем высоту сами: это стоит одну строку и не зависит от того,
-- что именно её сбило.
local function KeepHeight()
    if G.wantH and G.win then
        SetWindowHeight(G.wantH)
    end
end

-- refitHeight передаётся отдельно от раскладки намеренно: раскладка двигает
-- строки, а размер окна трогает не она.
local function ApplyLayout(refitHeight)
    if not G.win then return end
    local vis = VisibleSet()
    local _, howMany, bodyH = ComputeBody(vis)
    LayoutRows()
    if refitHeight then
        FitHeight(bodyH)

        -- ВЫСОТА ОКНА МЕНЯЕТСЯ ЗДЕСЬ, ПОСЛЕ РАСКЛАДКИ, а позиции строк от неё
        -- зависят (см. PlaceRows). Без второго прохода строки остались бы
        -- расставлены по ПРЕЖНЕЙ высоте: смена набора строк меняет и высоту
        -- панели, и новый, короткий набор разъехался бы по старой, большой.
        PlaceRows()
    end
    if howMany == 0 then
        LOG('Overflow: no visible rows, window shrunk to the frame')
    end
end

--------------------------------------------------------------------------------
-- СВЁРТЫВАНИЕ
--
-- Сделано ровно как у миникарты: её кнопка закрытия вызывает
-- ToggleMinimap(), которая прячет окно и пишет состояние в профиль
-- (minimap.lua:85-91 и :196-213). Свободное перетаскивание и сворачивание
-- в игре уживаются - нельзя двигать только прибитые к краю панели.
--
-- Отличие от миникарты одно: там окно возвращает горячая клавиша и панель
-- multifunction, у нас - собственная кнопка, которая и была в моде всегда.
--------------------------------------------------------------------------------

local function CollapseKeyRead()
    local ok, v = pcall(function()
        return Prefs.GetFromCurrentProfile(L.COLLAPSE_KEY)
    end)
    if not ok then
        return false
    end
    return v and true or false
end

local function CollapseKeyWrite(collapsed)
    local ok, err = pcall(function()
        Prefs.SetToCurrentProfile(L.COLLAPSE_KEY, collapsed and true or false)
    end)
    if not ok then
        LOG('Overflow: collapse state FAILED: ' .. tostring(err))
    end
end

local function SetCollapsed(collapsed)
    if not G.win then return end
    G.collapsed = collapsed and true or false

    if collapsed then
        G.win:Hide()
        -- ПОДЛОЖКА ГАСНЕТ ОТДЕЛЬНО. Она висит в GetFrame(0), а не в окне, и
        -- G.win:Hide() её не трогает. Без этой строки крестик убирал только
        -- значения, а пустая рамка оставалась на экране.
        ShowFrameBg(false)
        if G.reopenButton then
            -- Чтение геометрии идёт под pcall по той же причине, что и в
            -- диагностике: геометрия контрола в движке круговая
            -- (control.lua:31-42). Окно класса ею заведено целиком, но если
            -- чтение всё же не удастся, панель обязана просто не найти своё
            -- место, а не упасть вместе со всей перерисовкой.
            pcall(function()
                LayoutHelpers.AtLeftTopIn(G.reopenButton, GetFrame(0),
                                          G.win.Left(), G.win.Top())
            end)
            G.reopenButton:Show()
        end
        CollapseKeyWrite(true)
        return
    end

    if G.reopenButton then
        G.reopenButton:Hide()
    end
    G.win:Show()
    ShowFrameBg(true)
    CollapseKeyWrite(false)
end

local NumbersOnlyOn = false

local function ReloadNumbersOnly()
    NumbersOnlyOn = false
    if not ThemeNumbers then
        return
    end
    local ok, res = pcall(ThemeNumbers)
    if ok and res then
        NumbersOnlyOn = true
    end
end

-- Подпись строки. В обычном режиме - как была: «E ally overflow: 1.2 E/s».
-- В режиме чисел - только «1.2».
local function RowText(caption, amount, unit)
    if NumbersOnlyOn then
        return Num(amount)
    end
    return StringFormat('%s: %s %s/s', caption, Num(amount), unit)
end

--------------------------------------------------------------------------------
-- СОЗДАНИЕ ОКНА
--------------------------------------------------------------------------------

CreatePanel = function()
    if G.win then
        pcall(function() G.win:Destroy() end)
        G.win = nil
    end
    if G.reopenButton then
        pcall(function() G.reopenButton:Destroy() end)
        G.reopenButton = nil
    end

    -- Таблица подписей пересоздаётся: в G.labels лежат все элементы, которыми
    -- управляет раскладка.
    G.labels = {}
    G.rowsSig = nil
    G.themeSig = nil

    -- ОФОРМЛЕНИЕ ПРИМЕНЯЕТСЯ ПЕРВЫМ ДЕЛОМ, до создания любых элементов: фон
    -- и подписи берут цвета из C прямо в конструкторе, и если тема придёт
    -- позже, они останутся со старыми цветами.
    ApplyTheme()
    G.themeSig = ThemeSignatureNow()
    G.blinkRun = 0
    G.blinkOn = false
    G.blinkWanted = false
    if ThemeBlink then
        local okBlink, resBlink = pcall(ThemeBlink)
        if okBlink and resBlink then
            G.blinkWanted = true
        end
    end

    local frame = GetFrame(0)

    -- Класс Window сам берёт из профиля положение и размер, сам их пишет и
    -- сам не даёт окну уехать за экран после смены разрешения
    -- (window.lua:461-513 и :527-545). Позиция и размер по умолчанию нужны
    -- только для первого запуска.
    -- НАЗВАНИЯ В ОКНЕ НЕТ: задача игрока - убрать его как лишнее. Передаём
    -- nil вместо строки. Заголовок при этом остаётся: он и есть зона
    -- перетаскивания (window.lua:387), и без него окно нельзя было бы двигать.
    local win = Window(frame, nil, nil, false, false, false, false,
                       L.PANEL_KEY,
                       { Left = L.DEFAULT_LEFT, Top = L.DEFAULT_TOP,
                         Right = L.DEFAULT_LEFT + L.DEFAULT_W,
                         Bottom = L.DEFAULT_TOP + L.DEFAULT_H },
                       WindowBrd())
    G.win = win
    win.Depth:Set(20)
    ApplyFrameBackground(win)
    win:SetMinimumResize(L.MIN_W, L.MIN_H)
    win:DisableHitTest()

    -- РЕСАЙЗ И ПЕРЕТАСКИВАНИЕ у класса свои, но СТРОКИ РАЗЪЕЗЖАЮТСЯ ПО
    -- ВЫСОТЕ (см. PlaceRows), поэтому протяжку за край пропустить нельзя:
    -- без пересчёта позиции останутся от прежней высоты.
    --
    -- Класс зовёт OnResize УЖЕ ПОСЛЕ того, как задал новый размер
    -- (window.lua:324-326: сначала Set, потом OnResize), поэтому высоту внутри
    -- читать можно.
    --
    -- LayoutRows целиком здесь не нужен и вреден: он перечитывает профиль и
    -- правит видимость строк, а при протяжке не меняется ни то, ни другое.
    win.OnResize = function()
        PlaceRows()
    end

    -- ИГРОК ПОДОБРАЛ ВЫСОТУ САМ. Запоминаем её один раз - с этого момента
    -- подгонка под содержимое её не срезает, а может только дорастить окно.
    -- Класс зовёт OnResizeSet по отпусканию протяжки (window.lua:337).
    win.OnResizeSet = function()
        -- Читаем через Bottom и Top, а не через Height(): Height у окна класса
        -- выводится, и после первой же записи в него перестаёт быть верным.
        G.wantH = win.Bottom() - win.Top()
        LOG('Overflow: player height ' .. tostring(G.wantH))
    end

    -- ПЕРЕНОС НЕ ДОЛЖЕН МЕНЯТЬ РАЗМЕР. По расчётам самого класса он и не
    -- меняется: ширина и высота снимаются на ButtonPress и возвращаются на
    -- каждом шаге (window.lua:394-402). Но проверить это без запуска в игре
    -- нельзя, а цена ошибки - панель, которую сбросило при первом же
    -- смещении. Поэтому после каждого шага переноса высоту перевыставляем.
    win.OnMove = function()
        KeepHeight()
    end
    win.OnMoveSet = function()
        KeepHeight()
    end

    -- Кнопка закрытия сворачивает панель. Ровно как у миникарты.
    win.OnClose = function()
        SetCollapsed(true)
    end

    local client = win.ClientGroup

    -- ПУСТОЙ ПОЛОСЫ ЗАГОЛОВКА БОЛЬШЕ НЕТ.
    --
    -- Класс Window заводит полосу высотой 30 px ВСЕГДА (window.lua:219-226) -
    -- даже когда название не передано, - и внутри неё остаётся один крестик.
    -- Строки же начинались НИЖЕ неё (window.lua:288). На окне в 52 px это
    -- значило тридцать пикселей пустоты, а трём строкам нужно 40: в остатке
    -- они не помещались и вылезали за рамку.
    --
    -- Строки начинаем от самого верха окна: ClientGroup.Top перестаёт
    -- следовать за низом полосы и держится за верх окна.
    client.Top:Set(win.Top)

    -- Полосу растягиваем на всё окно и поднимаем над содержимым. Она
    -- ПРОЗРАЧНАЯ и нужна ровно для одного: за неё окно таскают
    -- (window.lua:387-408 - перетаскивание висит ТОЛЬКО на ней). Не растянуть
    -- её нельзя: на полосе в 30 px окно сдвигалось бы только за верхнюю
    -- тридцатипиксельную кромку.
    --
    -- Крестик закрытия лежит ВНУТРИ полосы и потому остаётся выше неё - клик
    -- по нему по-прежнему закрывает панель, а не тащит окно.
    win.TitleGroup.Height:Set(function() return win.Bottom() - win.Top() end)
    win.TitleGroup.Depth:Set(function() return client.Depth() + 1 end)

    -- КЕГЛЬ БЕРЁТСЯ ИЗ ПРЕСЕТА и умножается на масштаб игрока
    -- (themes.lua: StyleFontSize). Если themes.lua не загрузился, остаётся
    -- L.FONT - панель обязана показывать хоть что-то в любом случае.
    local fontSize = L.FONT
    if ThemeFont then
        local okFont, resFont = pcall(ThemeFont)
        if okFont and type(resFont) == 'number' and resFont > 0 then
            fontSize = resFont
        end
    end

    -- строки данных
    G.labels.eOverflow = MakeLabel(client, fontSize, C.NEUTRAL)
    G.labels.eGo       = MakeLabel(client, fontSize, C.NEUTRAL)
    G.labels.eOwn      = MakeLabel(client, fontSize, C.NEUTRAL)
    G.labels.divider1  = MakeDivider(client)
    G.labels.mOverflow = MakeLabel(client, fontSize, C.NEUTRAL)
    G.labels.mGo       = MakeLabel(client, fontSize, C.NEUTRAL)
    G.labels.mOwn      = MakeLabel(client, fontSize, C.NEUTRAL)
    G.labels.divider2  = MakeDivider(client)
    G.labels.total     = MakeLabel(client, fontSize, C.TOTAL)

    ReloadNumbersOnly()

    -- вся геометрия ставится одним вызовом; true - подогнать высоту окна
    ApplyLayout(true)


    -- кнопка, возвращающая свёрнутую панель
    G.reopenButton = Bitmap(frame)
    G.reopenButton.Depth:Set(21)
    G.reopenButton:SetSolidColor(C.CLOSED)
    G.reopenButton:EnableHitTest(true)
    LayoutHelpers.SetDimensions(G.reopenButton, 120, 20)
    pcall(function()
        LayoutHelpers.AtLeftTopIn(G.reopenButton, frame, win.Left(), win.Top())
    end)
    G.reopenButton.HandleEvent = function(self, event)
        if event.Type == 'ButtonRelease' then
            SetCollapsed(false)
            return true
        end
        return false
    end
    local rbLabel = UIUtil.CreateText(G.reopenButton, 'Overflow',
                                      fontSize, UIUtil.bodyFont)
    rbLabel:SetColor(C.TITLE)
    rbLabel:SetDropShadow(true)
    rbLabel:DisableHitTest(true)
    LayoutHelpers.AtLeftTopIn(rbLabel, G.reopenButton, 6, 2)
    G.reopenButton:Hide()

    -- Свёрнутое состояние переносится между матчами: ровно так ведёт себя
    -- миникарта со своим 'stratview' (minimap.lua:20).
    G.collapsed = false
    if CollapseKeyRead() then
        SetCollapsed(true)
    end

    local themeSay = 'built-in colours'
    if ThemeTellIt then
        local okTell, resTell = pcall(ThemeTellIt)
        if okTell and resTell then
            themeSay = resTell
        end
    end
    LOG('Overflow: window created, theme ' .. themeSay ..
        ', collapsed=' .. tostring(G.collapsed))

    -- РАЗМЕРЫ СТРОК В ЛОГ - ОДИН РАЗ, ПРИ СОЗДАНИИ ОКНА.
    --
    -- НЕ НАДО УДИВЛЯТЬСЯ, ЧТО ЗДЕСЬ pcall. В движке геометрия контрола
    -- КРУГОВАЯ: Left, Top, Right, Bottom, Width и Height связаны друг с другом
    -- по умолчанию (control.lua:31-42, там же комментарий: разорвать круг
    -- можно, только задав ЧЕТЫРЕ из них). Поэтому читать геометрию не
    -- всякого контрола безопасно: на неполном круге рекурсия уходит в
    -- переполнение стека.
    --
    -- Именно так панель уже ломалась: дамп читал геометрию строки,
    -- падал, и CreatePanel не доходил до SyncStart - значения пропадали,
    -- а строки оставались. Поломка была в ДИАГНОСТИКЕ, а не в раскладке.
    --
    -- Отсюда правило: диагностика не имеет права ронять то, что она
    -- измеряет. Цена ошибки здесь - одна строка '?', а не пустая панель.
    pcall(function()
        local many = TableGetn(BODY_KEYS)
        for i = 1, many do
            local rowId = BODY_KEYS[i]
            local ctl = G.labels[rowId]
            if ctl and not ctl._hidden then
                -- Каждая строка читается СВОИМ pcall: иначе одна неудачная
                -- строка съедает все следующие, и в логе остаётся половина
                -- картины - именно так и вышло в прошлый раз.
                local okRead, l, tp, w, h = pcall(function()
                    return ctl.Left(), ctl.Top(), ctl.Width(), ctl.Height()
                end)
                if okRead then
                    LOG('Overflow: row ' .. rowId ..
                        ' L=' .. tostring(l) .. ' T=' .. tostring(tp) ..
                        ' W=' .. tostring(w) .. ' H=' .. tostring(h))
                else
                    LOG('Overflow: row ' .. rowId .. ' geometry unreadable')
                end
            end
        end
        LOG('Overflow: window L=' .. tostring(win.Left()) ..
            ' T=' .. tostring(win.Top()) ..
            ' W=' .. tostring(win.Width()) ..
            ' H=' .. tostring(win.Bottom() - win.Top()))
    end)
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- ВЫБОР ЦВЕТА ПО СОСТОЯНИЮ
--
-- СМЫСЛ ЦВЕТА: хорошо - когда мы НЕ зависим от союзников.
--
--   зелёный  перелив = 0, мы держимся на своём
--   жёлтый   перелив > 0, но не больше порога от своей добычи
--   красный  перелив больше порога
--
-- Порядок проверок ВАЖЕН. Первой идёт проверка на ноль: если перелива
-- нет, а своя добыча тоже 0, то условие shown <= 0.2 * own выполнилось бы
-- (0 <= 0) и мы ошибочно показали бы жёлтый вместо зелёного.
--
-- ---------------------------------------------------------------------------
-- МИГАНИЕ
--
-- Взрядно у игры: тревожное число мигает серым по белому -
-- ff404040 <-> ffffffff (economy.lua:276-281). Не красным мигающим: игра
-- дёргает глаз не тревожным цветом, а контрастом со своим же фоном.
--
-- Точно так же и здесь. BlinkDim - приглушённый цвет, во вторую фазу строка
-- показывает обычный C.BAD. Все строки мигают ВМЕСТЕ, одним флагом G.blinkOn:
-- так же сделано у игры, где blinkyFlag один на всё число (economy.lua:276).
--
-- BlinkLimit повторяет приём игры: после ста срабатываний мигание
-- прекращается само (economy.lua:254,271-272). Без этого панель мигала бы
-- все двадцать минут матча и в итоге раздражала бы.
--------------------------------------------------------------------------------

local BlinkDim   = 'ff404040'
local BlinkLimit = 100

local function StatusColor(shown, own)
    local col
    if shown <= 0 then
        col = C.SAFE
    elseif shown <= L.WARN_RATIO * own then
        col = C.WARN
    else
        col = C.BAD
        -- Мигание - только по запросу игрока и только на тревожном состоянии.
        --
        -- Счётчик отсчётывает ВЫЗОВЫ, а не секунды: статус считается для
        -- энергии и для массы отдельно, поэтому за один проход набегает два.
        -- Порядок величины тот же, что у игры, - там счётчик растёт на каждом
        -- обновлении (economy.lua:254,271-272).
        if G.blinkOn then
            G.blinkRun = G.blinkRun + 1
            if G.blinkRun > BlinkLimit then
                G.blinkOn = false
            end
        end
    end
    if G.blinkOn and col == C.BAD then
        return BlinkDim
    end
    return col
end

-- Красит и подписывает тройку строк одного ресурса: сколько пришло от
-- союзников, сколько мы отдали, сколько произвели сами.
--
-- Цвет ВСЕХ трёх строк ресурса одинаковый и считается по старому правилу -
-- по доле входящего перелива в собственной добыче. То есть "зелёный" до сих
-- пор означает "живём своим", а жёлтый и красный - "зависим от союзника".
--
-- Про исходящий перелив отдельного цвета пока НЕ вводим: непонятно, что
-- для него хорошо. Отдали много - это плохо? Или нормально, если отдаём
-- в пустоту, а не союзнику? Решать пользователю, а не молча угадывать.
-- Если понадобится другой цвет - менять здесь одну строку SetColor.
local function SetTriple(overLabel, goLabel, ownLabel, overText, goText,
                         ownText, incoming, outgoing, own, unit)
    local color = StatusColor(incoming, own)
    overLabel:SetColor(color)
    goLabel:SetColor(color)
    ownLabel:SetColor(color)
    overLabel:SetText(RowText(overText, incoming, unit))
    goLabel:SetText(RowText(goText, outgoing, unit))
    ownLabel:SetText(RowText(ownText, own, unit))
end

--------------------------------------------------------------------------------
-- ОТРИСОВКА
--------------------------------------------------------------------------------

local function Render(d)
    -- Энергия и масса считаются ОТДЕЛЬНО: перелив энергии и перелив
    -- массы могут быть противоположными. Один общий цвет закрасил бы
    -- и здоровую строку по другому ресурсу.
    SetTriple(G.labels.eOverflow, G.labels.eGo, G.labels.eOwn,
              'E ally overflow', 'E to allies', 'E own production',
              d.incoming, d.outgoing, d.own, 'E')

    SetTriple(G.labels.mOverflow, G.labels.mGo, G.labels.mOwn,
              'M ally overflow', 'M to allies', 'M own production',
              d.massIncoming, d.massOutgoing, d.massOwn, 'M')

    -- Нижняя строка ВСЕГДА про реклейм, независимо от того, есть он
    -- или нет. Постоянная строка не даёт панели менять вид ежесекундно.
    if NumbersOnlyOn then
        G.labels.total:SetText(Num(d.reclaim) .. ' / ' .. Num(d.massReclaim))
    else
        G.labels.total:SetText(StringFormat('reclaim E %s / M %s /s',
            Num(d.reclaim), Num(d.massReclaim)))
    end
end

--------------------------------------------------------------------------------
-- ОБНОВЛЕНИЕ
--------------------------------------------------------------------------------

local function Update()
    -- Данные приходят из sync.lua через колбэк синхронизации. Здесь мы
    -- только забираем ГОТОВЫЙ результат и рисуем. Никакой арифметики,
    -- никакого обхода армии, никакого ожидания здесь быть не может -
    -- функция вызывается из beat, а не из синхронизации.
    local d = SyncResult()

    if G.win == nil then return end

    -- ОФОРМЛЕНИЕ. Тот же приём, что и для строк: страница настроек только
    -- пишет в профиль, панель замечает изменение здесь.
    --
    -- В отличие от строк здесь ПЕРЕСОБИРАЕМ окно, а не перекладываем
    -- раскладку. Причина - цвет: он задан в конструкторе элементов
    -- (CreatePanel -> SetColor), и перекладкой его не сменить.
    --
    -- Пересборка под pcall: мы внутри beat, и ошибка здесь уронила бы всю
    -- перерисовку вместе с панелью.
    if ThemeSign then
        local sig = ThemeSignatureNow()
        if sig ~= nil and sig ~= G.themeSig then
            -- ПРИЧИНУ ПЕРЕСБОРКИ ПИШЕМ В ЛОГ. Окно создаётся заново, и
            -- высота, которую игрок подобрал ресайзом, при этом теряется:
            -- новое окно встаёт по содержимому. Если в логе видно
            -- 'theme REBUILD' без смены темы игроком - значит пересборка
            -- идёт сама, и это отдельная поломка.
            LOG('Overflow: theme REBUILD ' .. tostring(G.themeSig) ..
                ' -> ' .. tostring(sig))
            local okRebuild, errRebuild = pcall(CreatePanel)
            if okRebuild then
                LOG('Overflow: theme applied: ' .. ThemeTellIt())
            else
                LOG('Overflow: theme rebuild FAILED: ' .. tostring(errRebuild))
            end
            return
        end
    end

    -- ФАЗА МИГАНИЯ переключается здесь, один раз на проход, а не внутри
    -- StatusColor: та зовётся дважды за проход (энергия и масса), и мигание
    -- дёргалось бы четыре раза вместо двух.
    if G.blinkWanted and G.blinkRun <= BlinkLimit then
        G.blinkOn = not G.blinkOn
    end

    -- НАСТРОЙКА СТРОК. Страница настроек UMT только пишет в профиль, и
    -- панель замечает изменение здесь. Так страница не зависит от порядка
    -- загрузки модулей, а её обработчики не могут упасть из-за чужого файла.
    --
    -- Сравниваем ПОДПИСЬ НАБОРА, а не перекладываем геометрию каждый бит:
    -- перерисовка ежесекундно дёргала бы панель без причины.
    if RowsVisible then
        local vis = RowsVisible()
        local sig = RowsSign(vis)
        if sig ~= G.rowsSig then
            G.rowsSig = sig
            ApplyLayout(true)
            LOG('Overflow: rows applied: ' .. RowsTell(vis))
        end
    end

    if d == nil then return end

    -- режим наблюдателя: своей армии нет, показывать нечего
    if d.observer then
        if not G.collapsed then
            G.labels.eOverflow:SetColor(C.NEUTRAL)
            G.labels.mOverflow:SetColor(C.NEUTRAL)
            G.labels.eGo:SetColor(C.NEUTRAL)
            G.labels.mGo:SetColor(C.NEUTRAL)
            G.labels.eOverflow:SetText('E ally overflow: n/a')
            G.labels.eGo:SetText('E to allies: n/a')
            G.labels.eOwn:SetText('E own production: n/a')
            G.labels.mOverflow:SetText('M ally overflow: n/a')
            G.labels.mGo:SetText('M to allies: n/a')
            G.labels.mOwn:SetText('M own production: n/a')
            if NumbersOnlyOn then
                G.labels.total:SetText('-')
            else
                G.labels.total:SetText('observer mode')
            end
        end
        ApplyMinSize()
        return
    end

    if not d.ok then return end
    if not G.collapsed then
        Render(d)
    end

    -- Предел размера пересчитываем на каждом проходе: числа в строках меняются
    -- каждую секунду, а с ними меняется и ширина самой длинной строки.
    ApplyMinSize()
end

local BEAT_ERROR_LIMIT = 3

-- The game calls beat functions without pcall, so an error would repeat on every
-- beat and stop the functions registered after this one.
local function SafeUpdate()
    local ok, err = pcall(Update)
    if ok then
        G.beatErrors = 0
        return
    end
    G.beatErrors = G.beatErrors + 1
    LOG('Overflow: Update FAILED (' .. tostring(G.beatErrors) .. '/' ..
        tostring(BEAT_ERROR_LIMIT) .. '): ' .. tostring(err))
    if G.beatErrors >= BEAT_ERROR_LIMIT then
        pcall(GameMain.RemoveBeatFunction, SafeUpdate, 'Overflow')
        LOG('Overflow: too many errors, panel stopped updating')
    end
end

--------------------------------------------------------------------------------
-- ВХОД
--------------------------------------------------------------------------------

function OnCreateUI()
    ForkThread(function()
        WaitSeconds(1)

        ------------------------------------------------------------------
        -- ВАЖНО: WaitSeconds НЕЛЬЗЯ ЗАПУСКАТЬ ВНУТРИ pcall
        --
        -- pcall - это C-функция, а WaitSeconds передаёт управление
        -- корутине. Через C-границу передать управление нельзя, и
        -- LuaPlus роняет всё с ошибкой:
        --
        --   attempt to yield across metamethod/C-call boundary
        --
        -- Наблюдалось в игре: панель создалась, а данных в ней не
        -- появилось никогда - упало на ожидании, beat-функция не
        -- зарегистрировалась. Симптом выглядит как "мод грузится, но
        -- молчит", и вводит в заблуждение: виноват вроде бы рендеринг.
        --
        -- Правило: pcall - только для СИНХРОННОЙ работы. Любое ожидание
        -- (WaitSeconds, ожидание в цикле) - строками выше.
        ------------------------------------------------------------------

        -- интерфейс игры уже построен, но даём секунду на завершение
        local ok, err = pcall(function()
            CreatePanel()
        end)
        if not ok then
            LOG('Overflow: init FAILED: ' .. tostring(err))
            return
        end

        ------------------------------------------------------------------
        -- Ожидания стартового окна больше нет.
        --
        -- В версиях 8-10 приходилось ждать GameTick() > 50: мод подменял
        -- выделение, а игра в это время гоняет выделение командира
        -- (gamemain.lua:143-151) и сбивалась. Обход армии удалён, выделение
        -- мы теперь не трогаем вообще - и сталкиваться больше не с чем.
        --
        -- Первые тики матча отбрасывает сам sync.lua: в них симулятор не
        -- инициализирован и обе армии показывают одинаковые числа.
        ------------------------------------------------------------------
        if type(SyncStart) ~= 'function' then
            LOG('Overflow: FATAL - sync.lua exported no Start. Panel stays empty.')
            return
        end
        local ok2, err2 = pcall(SyncStart)
        if not ok2 then
            LOG('Overflow: sync start FAILED: ' .. tostring(err2))
            return
        end

        -- beat теперь нужен ТОЛЬКО чтобы перерисовывать панель. Данные
        -- приходят примерно раз в 2 с, поэтому throttle = true достаточно.
        local ok3, err3 = pcall(function()
            GameMain.AddBeatFunction(SafeUpdate, true, 'Overflow')
        end)
        if not ok3 then
            LOG('Overflow: beat FAILED: ' .. tostring(err3))
        end
    end)
end

-- ЭКСПОРТ: функций выше достаточно.
--
-- "return { OnCreateUI = OnCreateUI }" здесь НЕ НУЖНО и было бы мёртвым
-- кодом: модуль ФАФ отбрасывает значение return (import.lua:61,171),
-- экспорт идёт через глобалы. Хук читает Overflow.OnCreateUI - и находит
-- именно глобал, объявленный как "function OnCreateUI()".
--
-- По той же причине в sync.lua нельзя писать "return { Start = ... }":
-- модуль отдаст ноль полей, и обращение Mod.Start уйдёт в _G, где висит
-- метаметод config.lua:56-61 и падает ошибкой.