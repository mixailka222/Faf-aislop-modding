-- ReclaimPause - entry point, appended to lua/ui/game/gamemain.lua.
--
-- The game calls CreateUI to build the interface and an error there leaves a black screen.
-- So CreateUI is hooked only after the module has loaded, and the mod runs under pcall.
--
-- settings.lua loads first: watch.lua reads ReclaimPauseCfg and its functions.

do
    local okSettings, Settings = pcall(import, '/mods/ReclaimPause/modules/settings.lua')

    if not okSettings then
        LOG('ReclaimPause: SETTINGS FAILED TO LOAD - mod stays disabled. Reason: ' .. tostring(Settings))
    else
        local ok, ReclaimPause = pcall(import, '/mods/ReclaimPause/modules/watch.lua')

        -- rawget: a plain read of a missing field reaches the strict _G, which raises an
        -- error. rawget needs a table, so the type comes first.
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
                -- the game builds its whole interface first
                OldCreateUI(isReplay)
                -- then the mod: if it fails, the game interface survives
                local ok2, err = pcall(OnCreateUI)
                if not ok2 then
                    LOG('ReclaimPause: OnCreateUI error: ' .. tostring(err))
                end
            end

            LOG('ReclaimPause: hooked CreateUI successfully')
        end
    end
end