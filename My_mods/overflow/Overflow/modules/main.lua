-- Overflow - вход для мода "UI mod tools" (UMT). Версия 19.
--
-- ---------------------------------------------------------------------------
-- ЗАЧЕМ ЭТОТ ФАЙЛ. БЕЗ НЕГО СТРАНИЦА НАСТРОЕК НЕ ПОЯВЛЯЕТСЯ ВООБЩЕ
--
-- UMT не сканирует моды сам. Он делает ровно это
-- (mods/umt/modules/Mods.lua:5-12):
--
--     function Load(isReplay)
--         for mod in mods do
--             local files = DiskFindFiles("/mods/" .. mod .. "/", 'Main.lua')
--             for _, file in files do
--                 LOG("UMT: Loading file " .. file)
--                 import(file).Main(isReplay)
--             end
--         end
--     end
--
-- Список mods наполняет UML ("UI mod library") по флагу __umt в mod_info.
-- То есть UMT зовёт Main ТОЛЬКО у того мода, у которого есть файл Main.lua.
--
-- Дальше важно, что именно делает наш Main. Страницу настроек создаёт
-- modules/Options.lua, но UMT сам его не ищет. Он ищет Options.lua только
-- внутри LoadOptionsFile, а ту попадает из __index на
-- UMT.Options.Mods[<имя мода>] (Options.lua:378-390):
--
--     __index = function(self, key)
--         if LoadOptionsFile(self, key) then return rawget(self, key) end
--         ErrorF("No options for mod '%s'", key)
--     end
--
-- То есть Options.lua грузится ТОЛЬКО когда кто-то ПРОЧТЁТ
-- UMT.Options.Mods["Overflow"]. Прочтение и есть наша работа здесь.
--
-- ПРОВЕРЕНО В ИГРЕ 2026-10-05. Мод был в списке активных, панель работала,
-- но в логе стояло:
--
--     UMT: Loading file /mods/umt/modules/main.lua
--     UMT: Loading file /mods/ase/modules/main.lua
--     Loading options of mod 'ASE'
--
-- и ни слова про Overflow. ASE - единственный мод с Main.lua, поэтому до
-- наших опций очередь просто не дошла.
--
-- ---------------------------------------------------------------------------
-- ИМЯ ФАЙЛА. Ищется 'Main.lua'; сравнение регистронезависимое, поэтому
-- main.lua тоже подойдёт - у ASE он с маленькой буквы и находится. Имя
-- 'Options.lua' в той же строке ищется точно так же, и наш Options.lua
-- написан с большой буквы - так надёжнее.
--
-- РЕГИСТР ПАПКИ. DiskFindFiles получает имя папки от UML, и в логе видно
-- `UML: added overflow` - то есть строчными. Совпадение регистронезависимое,
-- поэтому DiskFindFiles("/mods/Overflow/", ...) находит папку overflow.
--
-- ---------------------------------------------------------------------------
-- ГЛАВНОЕ ПРАВИЛО: Main здесь НИЧЕГО НЕ ДЕЛАЕТ САМ
--
-- Он только читает UMT.Options.Mods["Overflow"], чтобы UMT загрузил
-- Options.lua. Он НЕ импортирует ui.lua: порядок загрузки UMT относительно
-- интерфейса игры неизвестен, а импорт панели отсюда в одном из случаев
-- поймал бы ещё не до конца выполненный модуль - ровно случай, описанный в
-- методичке 3.23 как стоивший трёх проговонов версий 12-14.
--
-- ---------------------------------------------------------------------------
-- ПОЧЕМУ ВСЁ ПОД pcall
--
-- UMT зовёт Main БЕЗ защиты (Mods.lua:9), и мы находимся внутри его
-- обработчика на PostCreateUI. Ошибка здесь свалила бы CreateGameInterface и
-- не дала открыть игровой интерфейс. Поэтому тело под pcall, а причина
-- ошибки пишется в лог прямо.
--
-- ВНИМАНИЕ, та же ловушка, что в ReclaimPause: внутри pcall нельзя
-- запускать WaitSeconds - pcall это C-функция, и передать управление
-- корутине через неё нельзя. Здесь ожиданий и не предполагалось.

function Main(isReplay)
    if not UMT or not UMT.Options or not UMT.Options.Mods then
        LOG('Overflow: UMT not available, options page skipped')
        return
    end

    -- ВОТ ЭТО ЧТЕНИЕ И ЕСТЬ ВСЯ РАБОТА ФАЙЛА. Оно заставляет UMT найти
    -- /mods/Overflow/modules/Options.lua и вызвать у него Main(), а тот
    -- объявит поля и зарегистрирует страницу через AddOptions.
    --
    -- UMT:LoadOptionsFile ищет Options.lua по всему дереву папки мода, так
    -- что modules/Options.lua подходит.
    local ok, err = pcall(function()
        return UMT.Options.Mods["Overflow"]
    end)

    if not ok then
        LOG('Overflow: UMT options FAILED: ' .. tostring(err))
        return
    end

    -- UMT вернул nil, если Options.lua не нашёлся или не отработал.
    -- Молчать об этом нельзя: игрок не найдёт своей страницы и будет
    -- искать причину не там.
    if err == nil then
        LOG('Overflow: FAILED - UMT did not find modules/Options.lua')
    else
        LOG('Overflow: UMT options page requested, 7 rows')
    end
end
