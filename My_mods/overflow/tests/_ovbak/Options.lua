-- Overflow - страница настроек для мода "UI mod tools" (UMT). Версия 18.
--
-- ЭТОТ ФАЙЛ ЗАГРУЖАЕТСЯ ТОЛЬКО МОДОМ UMT. Он ищет файл с именем
-- Options.lua в папках модов, помеченных в mod_info.lua флагом __umt, и
-- вызывает у него Main() - mods/umt/modules/Options.lua:361-368. Если UMT нет
-- или выключен, файл просто никто не откроет: мод возьмёт значения из
-- профиля, а если их там нет - покажет все строки.
--
-- ИМЯ ФАЙЛА ИМЕННО Options.lua, с большой буквы: DiskFindFiles ищет по этому
-- имени (Options.lua:363). На Windows сравнение не регистрозависимое, но
-- полагаться на это незачем.
--
-- Пользователь открывает окно через меню игры: "UI mods options".
--
-- ---------------------------------------------------------------------------
-- ЭКСПОРТ И ПОРЯДОК ЗАГРУЗКИ
--
-- Main - ГЛОБАЛЬНАЯ функция, а не запись в return: значение return движок
-- отбрасывает (import.lua:61 и 171). Методичка 3.23.
--
-- ЭТА СТРАНИЦА НЕ ИМПОРТИРУЕТ ui.lua. Она только пишет в профиль, а панель
-- замечает изменение сама, по биту игры. Причина не в экономии, а в
-- неопределённости порядка: неизвестно, UMT ли загрузится раньше интерфейса
-- игры или позже, и импорт ui.lua отсюда в одном из случаев поймал бы ещё не
-- до конца выполненный модуль - ровно тот случай, который описан в 3.23 как
-- стоивший трёх прогонов версий 12-14.
--
-- Побочная выгода: страница не зависит от того, загрузилась ли панель, и её
-- обработчики не могут упасть из-за чужого модуля.
--
-- ---------------------------------------------------------------------------
-- ДВА СПОСОБА ВЫБРАТЬ, И ОНИ НЕ ПРОТИВОРЕЧАТ ДРУГ ДРУГУ
--
--   Выпадающий список «Быстрый выбор» - это ЯВНЫЙ выбор. Щелчок по готовому
--   набору раскладывает его на галочки.
--
--   Галочки - ИСТОЧНИК ПРАВДЫ. Как только игрок снял или поставил галочку
--   вручную, список пересчитывается и показывает тот набор, который
--   получился, либо «Другой набор», если такого нет.
--
-- Поэтому список никогда не расходится с галочками, и панель всегда читает
-- одни и те же числа.
--
-- ---------------------------------------------------------------------------
-- ГЛАВНОЕ ПРАВИЛО, ПОВТОРЁННОЕ ИЗ ОПЫТА (методичка 3.52)
--
-- OptionVar:Set() (OptionVar.lua:24-30) меняет значение ТОЛЬКО В ПАМЯТИ и
-- вызывает OnChange. В профиль попадает исключительно OptionVar:Save(), а его
-- UMT дергает при закрытии окна (OptionsWindow.lua:472-476 и :484-489).
--
-- Значит в момент, когда игрок тронул галочку, профиль ещё старый. Если
-- читать Prefs, мод получит прежнее значение и через минуту после щелчка
-- продолжит показывать старые строки - и так же доложит об этом в лог,
-- создав видимость успеха. Именно это случилось с модом ReclaimPause на игре
-- 2026-10-04.
--
-- Правильно - спросить живое значение у самого OptionVar: он вызывается как
-- функция и отдаёт текущее (OptionVar.lua:18-20). Так же делает работающий
-- мод ASE, ASE/modules/Main.lua:35-37.
--
-- Аргумент колбэка использовать нельзя: Bind вызывает OnChange() вообще без
-- аргументов (OptionVar.lua:73-76), поэтому берём значения из options,
-- которая в замыкании.

function Main()
    local Options = UMT.Options
    local Opt = Options.Opt
    local PFX = 'Overflow: '
    -- Оператор # движком не поддерживается, длина таблицы - только
    -- через table.getn (методичка 3.3). Объявляем здесь явно: неявное
    -- обращение к глобалу, которого нет, роняет загрузку модуля (3.6).
    local TableGetn = table.getn

    local Rows = import('/mods/Overflow/modules/rows.lua')

    -- Поля rows.lua берём через rawget: у таблицы модуля __index уходит в
    -- _G, а на _G висит метаметод, падающий ошибкой на несуществующем
    -- глобале. Проверка наличия поля сама по себе тогда роняет загрузку.
    local RowHowMany = rawget(Rows, 'HowManyRows')
    local RowIdAt    = rawget(Rows, 'RowKeyAt')
    local RowTitle   = rawget(Rows, 'RowTitleOf')
    local RowDefault = rawget(Rows, 'RowDefaults')
    local PresetList = rawget(Rows, 'PresetNames')
    local PresetPick = rawget(Rows, 'PresetFor')
    local PresetRest = rawget(Rows, 'PresetOther')
    local PresetOpen = rawget(Rows, 'PresetByName')
    local RowSave    = rawget(Rows, 'SaveRows')
    local RowTell    = rawget(Rows, 'DescribeRows')

    if type(RowHowMany) ~= 'function' or type(RowSave) ~= 'function'
        or type(PresetList) ~= 'function' then
        LOG(PFX .. 'FATAL - rows.lua did not load, settings page will show ' ..
            'defaults only. Look for the real error earlier in this log.')
        return
    end

    -- Оформление живёт в themes.lua, там же и названия тем. Если модуль не
    -- загрузился, страницу настроек не показываем вовсе: список настроек
    -- оказался бы наполовину неправдой, и это хуже, чем её отсутствие.
    local Themes = import('/mods/Overflow/modules/themes.lua')
    local ThemeNames = rawget(Themes, 'FrameNames')
    local StyleNames = rawget(Themes, 'StyleNames')
    local ScaleDefault = rawget(Themes, 'FontScaleDefault')

    if type(ThemeNames) ~= 'function' or type(StyleNames) ~= 'function'
        or type(ScaleDefault) ~= 'function' then
        LOG(PFX .. 'FATAL - themes.lua did not load, settings page skipped. ' ..
            'Look for the real error earlier in this log.')
        return
    end

    local BOXES = { 'eOverflow', 'eGo', 'eOwn', 'mOverflow', 'mGo',
                    'mOwn', 'total' }
    local defaults = RowDefault()
    local items = PresetList()
    -- ПЕРВЫЙ элемент каждого списка - вариант по умолчанию: UMT ставит
    -- items[1], если сохранённого значения в списке нет
    -- (StringSelector.lua:31-35). Задача игрока: и рамка, и пресет по
    -- умолчанию Vanilla.
    local looks = ThemeNames()
    local styles = StyleNames()

    -- МАСШТАБ ШРИФТА В ПРОЦЕНТАХ. Ползунок UMT целочисленный
    -- (OptionsWindow.lua:267 IntegerSlider), поэтому дробных значений он не
    -- умеет. Границы - прежние границы масштаба мода, 0.70 и 2.00.
    local FONT_SCALE_MIN = 70
    local FONT_SCALE_MAX = 200
    local FONT_SCALE_STEP = 5

    -- ШАГ 1: объявление. Именно ПРИСВАИВАНИЕ в Mods["Overflow"] создаёт
    -- OptionVar для каждого поля (Options.lua:379-383 -> :339-358). Prefs-ключ
    -- подставляет сама LoadOptions - писать его не нужно.
    --
    -- Значение выпадающего списка - items[1], а не отдельная строка: UMT
    -- ставит items[1], если текущее значение не найдено в списке
    -- (StringSelector.lua:31-35). Первый набор совпадает со значением по
    -- умолчанию, поэтому расхождения не будет.
    Options.Mods["Overflow"] = {
        preset    = Opt(items[1]),
        eOverflow = Opt(defaults.eOverflow),
        eGo       = Opt(defaults.eGo),
        eOwn      = Opt(defaults.eOwn),
        mOverflow = Opt(defaults.mOverflow),
        mGo       = Opt(defaults.mGo),
        mOwn      = Opt(defaults.mOwn),
        total     = Opt(defaults.total),
        theme     = Opt(looks[1]),
        style     = Opt(styles[1]),
        fontScale = Opt(ScaleDefault()),
        numbersOnly = Opt(false),
        blink     = Opt(false),
    }

    -- ШАГ 2: забираем созданные OptionVar.
    local options = Options.Mods["Overflow"]

    -- ЗАЩИТА ОТ ПОВТОРНОГО ВХОДА.
    --
    -- Щелчок по выпадающему списку раскладывает набор на галочки, и каждая
    -- галочка вызывает Set, а значит OnChange. Без этой защиты обработчик
    -- галочки успевает переписать только что выбранный набор - и список тут
    -- же показал бы не то, что игрок выбрал.
    local busy = false

    -- Живые значения всех галочек в одну таблицу.
    local function ReadBoxes()
        local vis = {}
        for i = 1, RowHowMany() do
            local rowKey = RowIdAt(i)
            vis[rowKey] = options[rowKey]() and true or false
        end
        return vis
    end

    -- Записать и сказать в лог. Панель подхватит изменение сама.
    local function Apply(vis, fromPreset)
        RowSave(vis)
        LOG(PFX .. 'rows: ' .. RowTell(vis) ..
            ' | from list: ' .. tostring(fromPreset))
    end

    -- ШАГ 3: щелчок по галочке.
    --
    -- Список пересчитывается здесь же, иначе он остался бы старым и
    -- показывал не то, что на экране.
    local function OnBoxChange()
        if busy then return end
        busy = true
        local ok, vis = pcall(function()
            local box = ReadBoxes()
            -- Совпал набор - пишем его название. Не совпал ни один - пишем
            -- служебное «Другой набор», иначе список продолжал бы показывать
            -- прежний набор при уже других галочках.
            --
            -- Set вызывает OnChange у preset, но busy=true, поэтому
            -- повторного входа не будет.
            local match = PresetPick(box)
            options.preset:Set(match or PresetRest())
            return box
        end)
        busy = false
        if not ok then
            LOG(PFX .. 'options refresh FAILED: ' .. tostring(vis))
            return
        end
        Apply(vis, false)
    end

    -- ШАГ 4: щелчок по выпадающему списку.
    --
    -- Набор раскладывается на галочки через Set, и каждая из них дёргает
    -- OnBoxChange. busy=true держит все эти вызовы от работы; запись в
    -- профиль делаем сами, из уже прочитанных живых значений.
    local function OnPresetChange()
        if busy then return end
        busy = true
        local ok, vis = pcall(function()
            local flags = PresetOpen(options.preset())
            if flags then
                for i = 1, RowHowMany() do
                    local rowKey = RowIdAt(i)
                    options[rowKey]:Set(flags[rowKey])
                end
            end
            return ReadBoxes()
        end)
        busy = false
        if not ok then
            LOG(PFX .. 'preset FAILED: ' .. tostring(vis))
            return
        end
        Apply(vis, true)
    end

    for i = 1, TableGetn(BOXES) do
        options[BOXES[i]]:Bind(OnBoxChange)
    end
    options.preset:Bind(OnPresetChange)

    -- ШАГ 5: описание окна.
    Options.AddOptions("Overflow", "Overflow: оформление и строки", {
        Options.Strings("Рамка окна", looks, options.theme, 0),
        Options.Strings("Пресет: шрифт и цвета", styles, options.style, 0),
        Options.Slider("Масштаб шрифта, %", FONT_SCALE_MIN, FONT_SCALE_MAX,
                       FONT_SCALE_STEP, options.fontScale, 0),
        Options.Filter("Только числа, без подписей", options.numbersOnly, 16),
        Options.Filter("Мигать при тревоге", options.blink, 16),
        Options.Title("Какие строки показывать", 14, nil, nil, 24),
        Options.Strings("Быстрый выбор", items, options.preset, 0),
        Options.Title("Или поставь галочки вручную", 14, nil, nil, 16),
        Options.Filter(RowTitle('eOverflow'), options.eOverflow, 16),
        Options.Filter(RowTitle('eGo'), options.eGo, 16),
        Options.Filter(RowTitle('eOwn'), options.eOwn, 16),
        Options.Filter(RowTitle('mOverflow'), options.mOverflow, 16),
        Options.Filter(RowTitle('mGo'), options.mGo, 16),
        Options.Filter(RowTitle('mOwn'), options.mOwn, 16),
        Options.Filter(RowTitle('total'), options.total, 16),
    })

    LOG(PFX .. 'UMT options page registered, frame + style + scale + ' ..
        'numbers + blink + ' .. RowHowMany() .. ' rows')
end
