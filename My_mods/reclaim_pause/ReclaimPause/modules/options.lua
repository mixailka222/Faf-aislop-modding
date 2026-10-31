-- ReclaimPause - страница настроек для мода "UI mod tools" (UMT).
--
-- ЭТОТ ФАЙЛ ЗАГРУЖАЕТСЯ ТОЛЬКО МОДОМ UMT. Он ищет Options.lua в папках
-- модов, помеченных в mod_info.lua флагом __umt, и вызывает Main().
-- Если UMT нет или выключен, файл просто никто не откроет, и мод
-- продолжит работать на значениях по умолчанию.
--
-- Пользователь открывает окно через меню игры: "UI mods options".
--
-- ВАЖНО про модули FAF. У каждого файла мода своё окружение: присваивание
-- "глобального" имени попадает в таблицу модуля, а не в общий _G. Поэтому
-- функции соседнего файла видны только через то, что вернул import().
--
-- ---------------------------------------------------------------------------
-- КАК ЭТО УСТРОЕНО В UMT. Разобрано по mods/umt/modules/Options.lua
-- и Options.lua мода ASE, который работает. Не выдумывать API.
--
-- 1) Объявление настроек - это ПРИСВАИВАНИЕ, а не вызов функции:
--
--        UMT.Options.Mods["ReclaimPause"] = { enabled = Opt(true), ... }
--
--    Присваивание попадает в ModsOptionsMetaTable.__newindex
--    (Options.lua:379-383), который вызывает LoadOptions, а тот создаёт
--    для каждого поля OptionVar (Options.lua:339-358).
--
-- 2) Opt() принимает ОДИН аргумент - значение по умолчанию
--    (Options.lua:400-402). Prefs-ключ подставляет сама LoadOptions.
--
-- 3) Затем поле читается обратно и превращается в OptionVar:
--
--        local options = UMT.Options.Mods["ReclaimPause"]
--
--    В этот момент ключ уже есть в таблице, поэтому __index не
--    срабатывает и повторной загрузки файла не происходит.
--
-- 4) У OptionVar есть метод Bind (OptionVar.lua:73-76). Он НЕ просто
--    запоминает функцию, а СРАЗУ её вызывает. Поэтому весь код ниже
--    обязан быть безопасен при первом запуске - мод ещё может не быть
--    запущен.
--
-- ---------------------------------------------------------------------------
-- ГДЕ ЖИВУТ ЗНАЧЕНИЯ. OptionVar:Save() пишет так
-- (OptionVar.lua:41-47):
--
--        Prefs.GetFromCurrentProfile('ReclaimPause')[optionName] = value
--        Prefs.SetToCurrentProfile('ReclaimPause', modOptionsTable)
--
-- То есть тот же ключ профиля 'ReclaimPause' и те же имена полей, что
-- использует modules/settings.lua. Это НЕ случайность и не конфликт:
-- окно и мод читают одно хранилище, поэтому значение, выставленное
-- ползунком, сразу видно моду. Имена полей в DEFAULTS (settings.lua) и
-- здесь обязаны совпадать - иначе окно и мод разойдутся во мнениях.

function Main()
    local Options = UMT.Options
    local Opt = Options.Opt
    local PFX = 'ReclaimPause: '

    local Settings = import('/mods/ReclaimPause/modules/settings.lua')
    local Watch = import('/mods/ReclaimPause/modules/watch.lua')

    local def = Settings.ReclaimPauseDefaults()

    -- ШАГ 1: объявление. Именно присваивание создаёт OptionVar.
    Options.Mods["ReclaimPause"] = {
        enabled        = Opt(def.enabled),
        highMass       = Opt(def.highMass),
        lowMass        = Opt(def.lowMass),
        energyMin      = Opt(def.energyMin),
        minSec         = Opt(def.minSec),
        releaseHoldSec = Opt(def.releaseHoldSec),
        rescanSec      = Opt(def.rescanSec),
        startGrace     = Opt(def.startGrace),
        abortMove      = Opt(def.abortMove),
        abortSec       = Opt(def.abortSec),
        skipSec        = Opt(def.skipSec),
        -- СБРОС НАСТРОЕК. Это не настройка, а кнопка с автоснятием.
        -- UMT сохраняет все OptionVar'ы окна (OptionsWindow.lua:473),
        -- поэтому поле попадёт в профиль как resetFlag=false. Это
        -- безвредно и в профиле всегда false: сам факт сброса там
        -- не хранится, повторного тихого сброса при запуске не будет.
        resetFlag      = Opt(false),
    }

    -- ШАГ 2: забираем созданные OptionVar.
    local options = Options.Mods["ReclaimPause"]

    -- ШАГ 3: реакция на изменение.
    --
    -- ВАЖНО, почему здесь НЕ берётся ReclaimPauseLoadSettings().
    --
    -- OptionVar:Set() (OptionVar.lua:24-30) меняет значение только в
    -- памяти и вызывает OnChange. В профиль попадает исключительно
    -- OptionVar:Save(), а его UMT дергает при закрытии окна
    -- (OptionsWindow.lua:472-476 и :484-489).
    --
    -- Значит в момент, когда игрок тронул ползунок, профиль ещё старый.
    -- Если читать Prefs, мод получит прежнее значение и через минуту после
    -- перетаскивания продолжит работать по старому порогу - и так же
    -- доложит об этом в лог, создав видимость успеха. Ровно это и случилось
    -- на игре 2026-10-04: игрок поставил 70, мод отработал на 85.
    --
    -- Правильно - спросить живое значение у самого OptionVar: он
    -- вызывается как функция и отдаёт текущее (OptionVar.lua:18-20).
    -- Так же делает ASE, ASE/modules/Main.lua:35-37.
    --
    -- Аргумент нам не нужен и может быть чем угодно, поэтому читаем из
    -- options, которая в замыкании.
    -- Флаг на время записи в ползунки. Set зовёт OnChange, а это тот
    -- же Refresh, поэтому без флага сброс дал бы 12 вложенных
    -- вызовов, 12 лишних сохранений профиля и 12 лишних строк в логе.
    local writing = false

    -- Raw(), not Set: OptionVar:Set remembers the old value, and Cancel in the
    -- UMT window would bring it back. The new value is already in the profile,
    -- so nothing here has to call OnChange.
    local function PushToWindow()
        local cfg = Settings.ReclaimPauseCfg
        options.enabled:Raw():Set(cfg.enabled)
        options.highMass:Raw():Set(cfg.highMass)
        options.lowMass:Raw():Set(cfg.lowMass)
        options.energyMin:Raw():Set(cfg.energyMin)
        options.minSec:Raw():Set(cfg.minSec)
        options.releaseHoldSec:Raw():Set(cfg.releaseHoldSec)
        options.rescanSec:Raw():Set(cfg.rescanSec)
        options.startGrace:Raw():Set(cfg.startGrace)
        options.abortMove:Raw():Set(cfg.abortMove)
        options.abortSec:Raw():Set(cfg.abortSec)
        options.skipSec:Raw():Set(cfg.skipSec)
    end

    local function Refresh()
        if writing then return end

        local cfg = Settings.ReclaimPauseCfg

        -- СБРОС К УМОЛЧАНИЯМ. Идёт ПЕРВЫМ: если поставить его ниже,
        -- строки после присвоят cfg старые значения и затрут сброс.
        -- Значения в ползунки пишет PushToWindow через ReclaimPauseBindWindow.
        if options.resetFlag() then
            writing = true
            options.resetFlag:Set(false)
            Settings.ReclaimPauseResetDefaults()
            cfg = Settings.ReclaimPauseCfg
            writing = false
            LOG(PFX .. 'RESET FROM PAGE: ' .. Settings.ReclaimPauseSettingsLine())
        end

        cfg.enabled        = options.enabled() and true or false
        cfg.highMass       = options.highMass()
        cfg.lowMass        = options.lowMass()
        cfg.energyMin      = options.energyMin()
        cfg.minSec         = options.minSec()
        cfg.releaseHoldSec = options.releaseHoldSec()
        cfg.rescanSec      = options.rescanSec()
        cfg.startGrace     = options.startGrace()
        cfg.abortMove      = options.abortMove() and true or false
        cfg.abortSec       = options.abortSec()
        cfg.skipSec        = options.skipSec()
        -- тот же предохранитель, что и в settings.lua: иначе мод залипнет
        if cfg.lowMass > cfg.highMass then
            cfg.lowMass = cfg.highMass
        end
        -- пишем сразу, чтобы профиль, окно и мод видели одно и то же
        Settings.ReclaimPauseSaveSettings()
        Watch.ReclaimPauseApplySettings()
        LOG(PFX .. 'settings from window: ' .. Settings.ReclaimPauseSettingsLine())
    end

    options.enabled:Bind(Refresh)
    options.highMass:Bind(Refresh)
    options.lowMass:Bind(Refresh)
    options.energyMin:Bind(Refresh)
    options.minSec:Bind(Refresh)
    options.releaseHoldSec:Bind(Refresh)
    options.rescanSec:Bind(Refresh)
    options.startGrace:Bind(Refresh)
    options.abortMove:Bind(Refresh)
    options.abortSec:Bind(Refresh)
    options.skipSec:Bind(Refresh)
    options.resetFlag:Bind(Refresh)
    Settings.ReclaimPauseBindWindow(PushToWindow)

    -- ШАГ 4: описание окна. Ползунки не выходят за границы SaneInt
    -- в settings.lua, иначе окно и мод станут считать разные значения.
    -- Второй аргумент - строка, которую игрок видит в списке UMT
    -- (Options.lua:31-33 кладёт её в globalOptions[option][1]). Держим
    -- её равной имени мода: в списке это единственное, что мод называет.
    Options.AddOptions("ReclaimPause", "ReclaimPause", {
        Options.Filter("Мод включён", options.enabled),
        Options.Title("Пороги по массе", 14, nil, nil, 16),
        Options.Slider("Ставить на паузу от заполнения, %", 50, 100, 1, options.highMass, 16),
        Options.Slider("Снимать паузу от заполнения, %", 0, 100, 1, options.lowMass, 16),
        Options.Title("Энергия", 14, nil, nil, 16),
        Options.Slider("Ставить на паузу, только если энергии не меньше, %",
            0, 100, 1, options.energyMin, 16),
        Options.Title("Поведение", 14, nil, nil, 16),
        Options.Slider("Минимум секунд между переключениями", 0, 30, 1, options.minSec, 16),
        Options.Slider("Держать условие снятия N секунд (0 = сразу)",
            0, 60, 1, options.releaseHoldSec, 16),
        Options.Slider("Как часто искать инженеров, секунд", 1, 30, 1, options.rescanSec, 16),
        Options.Slider("Первые N секунд матча не трогать выделение", 0, 60, 5, options.startGrace, 16),
        Options.Filter("Останавливать на месте (обрыв маршрута)", options.abortMove, 16),
        Options.Slider("Повторять обрыв каждые N секунд", 1, 15, 1, options.abortSec, 16),
        Options.Slider("Не трогать N секунд после ручного снятия", 0, 60, 1, options.skipSec, 16),
        Options.Title("Сброс", 14, nil, nil, 16),
        -- Галочка вместо кнопки: UMT не умеет рисовать кнопки.
        -- OptionsWindow.lua:238-412 знает всего восемь типов
        -- элементов, кнопки среди них нет, а документированный в
        -- Options.lua:316 вариант "table|fun(frame):Control" не
        -- реализован: OptionsWindow.lua:188 перебирает buildTable
        -- как таблицу, и функция бы там упала.
        --
        -- Ставишь галочку - мод сбрасывает все ползунки к умолчаниям.
        --
        -- Про снятие галочки. Значение снимается сразу, но РИСУНОК
        -- галочки обновляется не сразу: OptionsWindow.lua:247 задаёт
        -- вид галочки один раз при создании окна и больше за
        -- значением не следит. Поэтому после сброса окно лучше
        -- закрыть и открыть заново - галочка будет уже снята, а
        -- ползунки покажут умолчания. Пока окно не переоткрыто,
        -- значение в профиле уже правильное, то есть на игру сброс
        -- подействовал сразу.
        Options.Filter("Сбросить все настройки к значениям по умолчанию",
            options.resetFlag, 16),
    })

    LOG(PFX .. 'UMT options page registered')
end
