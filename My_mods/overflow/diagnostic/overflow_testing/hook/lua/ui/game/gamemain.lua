-- Overflow Testing - точка входа (хук).
--
-- ВАЖНО: этот файл дописывается в конец lua/ui/game/gamemain.lua, а
-- CreateUI вызывается самой игрой для построения интерфейса. Если здесь
-- возникнет ошибка, игра не сможет построить интерфейс и будет чёрный
-- экран. Поэтому весь код обёрнут в pcall, а перехват CreateUI происходит
-- ТОЛЬКО если модуль удалось загрузить. Любая ошибка -> мод просто
-- выключается, игра работает как обычно.
--
-- Структура файла скопирована из рабочего мода Overflow: там она уже
-- проверена в игре.

do
    ------------------------------------------------------------------
    --  ВАЖНО: путь /mods/ИМЯ берётся из ИМЕНИ ПАПКИ, а не из поля name
    --  в mod_info.lua. Проверено на установленных модах:
    --
    --      папка ACUhighlight      -> name = "Acu highlight"
    --      папка AKA               -> name = "Advanced Key Actions"
    --      папка PxModAlphaV6      -> name = "PxModAlpha"
    --
    --  То есть мод с любым name нормально работает внутри папки с другим
    --  именем. И в логе видно, как клиент это монтирует:
    --      AddSearchPath: '...\mods\overflow', mounted as '/mods/ov...'
    --
    --  Папку пользователь просил назвать overflow_testing, а регистр
    --  привязки нам неизвестен. Поэтому пробуем варианты по очереди.
    --  Первый успешный и есть правильный - запоминаем его.
    ------------------------------------------------------------------
    local CANDIDATES = {
        '/mods/overflow_testing/modules/main.lua',
        '/mods/OverflowTesting/modules/main.lua',
        '/mods/overflowtesting/modules/main.lua',
    }

    local Testing = nil
    local tried = {}

    for _, path in ipairs(CANDIDATES) do
        local ok, mod = pcall(import, path)
        if ok and type(mod) == 'table' and rawget(mod, 'OnCreateUI') ~= nil then
            Testing = mod
            LOG('OverflowTesting: module loaded from ' .. path)
            break
        else
            -- оператор # движком не поддерживается, только table.insert
            table.insert(tried, path .. ' -> ' .. tostring(mod))
        end
    end

    if Testing == nil then
        LOG('OverflowTesting: MODULE FAILED TO LOAD - mod stays disabled.')
        LOG('OverflowTesting: tried:')
        for _, line in ipairs(tried) do
            LOG('OverflowTesting:   ' .. line)
        end
        LOG('OverflowTesting: expected folder name in mods: overflow_testing')
    else
        local OldCreateUI = CreateUI

        function CreateUI(isReplay)
            -- сначала игра строит весь свой интерфейс
            OldCreateUI(isReplay)
            -- потом наш мод (даже если он упадёт - интерфейс игры не пострадает)
            local ok2, err = pcall(Testing.OnCreateUI)
            if not ok2 then
                LOG('OverflowTesting: OnCreateUI error: ' .. tostring(err))
            end
        end

        LOG('OverflowTesting: hooked CreateUI successfully')
    end
end