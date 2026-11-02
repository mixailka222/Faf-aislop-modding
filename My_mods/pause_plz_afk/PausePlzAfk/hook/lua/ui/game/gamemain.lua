-- PausePlzAfk - entry point, appended to lua/ui/game/gamemain.lua.
--
-- The game calls CreateUI to build the interface and an error there leaves a black screen.
-- So CreateUI is hooked only after the module has loaded, and the mod runs under pcall.

do
    local okMod, PauseAfkMod = pcall(import, '/mods/PausePlzAfk/modules/pause_afk.lua')

    -- rawget: a plain read of a missing field reaches the strict _G, which raises an error.
    -- rawget needs a table, so the type comes first.
    local OnCreateUI = nil
    if type(PauseAfkMod) == 'table' then
        OnCreateUI = rawget(PauseAfkMod, 'PauseAfkOnCreateUI')
    end

    if not okMod or type(OnCreateUI) ~= 'function' then
        LOG('PausePlzAfk: MODULE FAILED TO LOAD - mod stays disabled. Reason: ' .. tostring(PauseAfkMod))
    else
        local OldCreateUI = CreateUI

        function CreateUI(isReplay)
            -- the game builds its whole interface first
            OldCreateUI(isReplay)
            -- then our mod (even if it fails, the game UI survives)
            if not isReplay then
                local okStart, errStart = pcall(OnCreateUI)
                if not okStart then
                    LOG('PausePlzAfk: OnCreateUI error: ' .. tostring(errStart))
                end
            end
        end

        LOG('PausePlzAfk: hooked CreateUI successfully')
    end
end
