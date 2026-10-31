-- Overflow - точка входа (хук).
--
-- ВАЖНО: этот файл дописывается в конец lua/ui/game/gamemain.lua, и функция
-- CreateUI вызывается самой игрой для построения интерфейса. Если здесь
-- возникнет ошибка, игра не сможет построить интерфейс и будет чёрный экран.
-- Поэтому весь код обёрнут в pcall, а перехват CreateUI происходит ТОЛЬКО если
-- модуль успешно загрузился. Любая ошибка -> мод просто выключается.

do
    local ok, Overflow = pcall(import, '/mods/Overflow/modules/ui.lua')

    -- rawget: a module that failed to compile is empty, and a plain read of a
    -- missing field reaches the strict _G of the game, which raises an error.
    local OnCreateUI = nil
    if ok and type(Overflow) == 'table' then
        OnCreateUI = rawget(Overflow, 'OnCreateUI')
    end

    if type(OnCreateUI) ~= 'function' then
        LOG('Overflow: MODULE FAILED TO LOAD - mod stays disabled. Reason: ' .. tostring(Overflow))
    else
        local OldCreateUI = CreateUI

        function CreateUI(isReplay)
            -- сначала игра строит весь свой интерфейс
            OldCreateUI(isReplay)
            -- потом наш мод (даже если он упадёт - интерфейс игры не пострадает)
            local ok2, err = pcall(OnCreateUI)
            if not ok2 then
                LOG('Overflow: OnCreateUI error: ' .. tostring(err))
            end
        end

        LOG('Overflow: hooked CreateUI successfully')
    end
end