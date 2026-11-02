-- Overflow - entry point, appended to lua/ui/game/gamemain.lua.
--
-- The game calls CreateUI to build the interface and an error there leaves a black screen.
-- So CreateUI is hooked only after the module has loaded, and the mod runs under pcall.

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
            -- the game builds its whole interface first
            OldCreateUI(isReplay)
            -- then the mod: if it fails, the game interface survives
            local ok2, err = pcall(OnCreateUI)
            if not ok2 then
                LOG('Overflow: OnCreateUI error: ' .. tostring(err))
            end
        end

        LOG('Overflow: hooked CreateUI successfully')
    end
end