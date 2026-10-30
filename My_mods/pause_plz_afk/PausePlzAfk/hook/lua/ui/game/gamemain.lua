-- PausePlzAfk - entry point (hook).
--
-- This file is appended to lua/ui/game/gamemain.lua, and CreateUI is called
-- by the game itself to build the interface. If this errors, the game gets
-- a black screen. So the module loads via pcall, CreateUI is hooked ONLY on
-- success, and any error just disables the mod with a LOG line.

do
    local okMod, PauseAfkMod = pcall(import, '/mods/PausePlzAfk/modules/pause_afk.lua')

    -- Read the export via rawget, not a plain field access. A plain access
    -- on a missing field falls through the module __index (lua/system/
    -- import.lua:24-26, __index = _G), and _G carries a metatable that calls
    -- error() (lua/system/config.lua:56-61). Check type first: rawget needs
    -- a table.
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
