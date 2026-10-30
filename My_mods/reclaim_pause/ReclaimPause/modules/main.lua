-- ReclaimPause - точка входа для мода "UI mod tools" (UMT).
--
-- ФАЙЛ ОБЯЗАТЕЛЕН, хотя сам по себе ничего не делает. Механика такая:
--
-- 1. UMT находит моды с флагом __umt в mod_info.lua и добавляет их в
--    свой список (в логе видно "UML: added reclaimpause").
-- 2. Затем UMT ищет в папке мода файл Main.lua и вызывает его Main().
-- 3. Страница настроек лежит в отдельном файле options.lua, и UMT
--    загружает его ТОЛЬКО при ЧТЕНИИ поля UMT.Options.Mods["ReclaimPause"].
--    Поле читает тот, кто обращается к настройкам.
--
-- Получается замкнутый круг: без Main.lua никто не читает поле, без чтения
-- поля не грузится options.lua, без options.lua страница не появляется.
--
-- У modов, у которых всё работает (ASE), Main.lua существует и первым же
-- делом читает своё поле.
--
-- Вызов Main происходит в момент построения интерфейса, раньше нашего
-- собственного хука CreateUI, поэтому здесь НЕЛЬЗЯ запускать логику:
-- настройки ещё не загружены. Только регистрация страницы.
--
-- ---------------------------------------------------------------------------
-- ПОЧЕМУ ЗДЕСЬ pcall. UMT вызывает Main БЕЗЗАЩИТНО:
--
--     mods/umt/modules/Mods.lua:9
--         import(file).Main(isReplay)
--
-- Никакого pcall вокруг. Любая ошибка в нашей странице настроек уходит
-- наружу и роняет CreateGameInterface - то есть ЧЁРНЫЙ ЭКРАН.
--
-- Именно так и случилось в версии 15: options.lua обратился к методу,
-- которого в UMT нет, и игра не запустилась. Настройки - необязательная
-- удобная штука, и они не имеют права ронять игру.
--
-- Поэтому всё тело под pcall, а ошибка печатается в лог: мод работает,
-- страница не появляется, игрок об этом узнаёт из лога, а не из чёрного
-- экрана.
--
-- ЧТО ИМЕННО ЛОМАЛОСЬ. В версии 15 страница выглядела так:
--
--     local enabled = Opt(prefKey, 'enabled', def.enabled)
--     enabled:Bind(Refresh)
--
-- Это выдуманный API. Настоящий Opt() (Options.lua:400-402) принимает
-- ОДИН аргумент, а Bind есть не у результата Opt(), а у OptionVar,
-- создаваемого только ПРИСВАИВАНИЕМ UMT.Options.Mods["Имя"] = {...}.
-- Разбор правильного устройства - в шапке modules/options.lua.
--
-- Настоящая сигнатура вызова ошибки: "attempt to call method `Bind' (a nil
-- value)". Method - значит объект есть, а метода на нём нет: именно
-- случай setmetatable({value=...}, OptValueMetaTable), где в
-- OptValueMetaTable метода Bind не существует.

function Main(isReplay)
    if not UMT or not UMT.Options or not UMT.Options.Mods then
        LOG('ReclaimPause: UMT not available, options page skipped')
        return
    end

    -- Одно чтение этого поля заставляет UMT найти и выполнить options.lua.
    local ok, err = pcall(function() return UMT.Options.Mods["ReclaimPause"] end)
    if not ok then
        LOG('ReclaimPause: UMT options FAILED: ' .. tostring(err))
        return
    end
    if err == nil then
        LOG('ReclaimPause: UMT did not register our options page')
    end
end
