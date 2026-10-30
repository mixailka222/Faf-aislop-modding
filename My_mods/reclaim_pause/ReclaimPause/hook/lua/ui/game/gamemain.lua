-- ReclaimPause - точка входа (хук).
--
-- ВАЖНО: этот файл дописывается в конец lua/ui/game/gamemain.lua, и функция
-- CreateUI вызывается самой игрой для построения интерфейса. Если здесь
-- возникнет ошибка, игра не сможет построить интерфейс и будет чёрный экран.
-- Поэтому весь код обёрнут в pcall, а перехват CreateUI происходит ТОЛЬКО если
-- модуль успешно загрузился. Любая ошибка -> мод просто выключается.
--
-- settings.lua грузится первым: watch.lua читает из него ReclaimPauseCfg
-- и функции ReclaimPauseLoadSettings/ReclaimPauseSettingsLine.

do
    local okSettings, Settings = pcall(import, '/mods/ReclaimPause/modules/settings.lua')

    if not okSettings then
        LOG('ReclaimPause: SETTINGS FAILED TO LOAD - mod stays disabled. Reason: ' .. tostring(Settings))
    else
        local ok, ReclaimPause = pcall(import, '/mods/ReclaimPause/modules/watch.lua')

        -- Проверка экспорта через rawget, а не обычным обращением к полю.
        -- Обычное обращение при отсутствующем поле уходит в __index таблицы
        -- модуля (lua/system/import.lua:24-26, __index = _G), а на _G висит
        -- метаметод, вызывающий error() (lua/system/config.lua:56-61).
        -- В этом коде путь был недостижим из-за короткого замыкания or, но
        -- при будущем переименовании экспорта стал бы фатальным.
        -- Порядок важен: rawget требует таблицу, поэтому сначала type.
        local OnCreateUI = nil
        if type(ReclaimPause) == 'table' then
            OnCreateUI = rawget(ReclaimPause, 'ReclaimPauseOnCreateUI')
        end

        if not ok or type(ReclaimPause) ~= 'table'
            or type(OnCreateUI) ~= 'function' then
            LOG('ReclaimPause: MODULE FAILED TO LOAD - mod stays disabled. Reason: ' .. tostring(ReclaimPause))
        else
            local OldCreateUI = CreateUI

            function CreateUI(isReplay)
                -- сначала игра строит весь свой интерфейс
                OldCreateUI(isReplay)
                -- потом наш мод (даже если он упадёт - интерфейс игры не пострадает)
                local ok2, err = pcall(OnCreateUI)
                if not ok2 then
                    LOG('ReclaimPause: OnCreateUI error: ' .. tostring(err))
                end
            end

            LOG('ReclaimPause: hooked CreateUI successfully')
        end
    end
end