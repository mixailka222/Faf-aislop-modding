-- Overflow Testing - entry point, appended to lua/ui/game/gamemain.lua.
--
-- The game calls CreateUI to build the interface and an error there leaves a black screen.
-- So CreateUI is hooked only after the module has loaded, and the mod runs under pcall.

do
    -- The path /mods/NAME comes from the folder name, not from the field name in
    -- mod_info.lua. The case of the mount is not known, so the variants are tried in turn
    -- and the first success wins.
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
            -- the game builds its whole interface first
            OldCreateUI(isReplay)
            -- then the mod: if it fails, the game interface survives
            local ok2, err = pcall(Testing.OnCreateUI)
            if not ok2 then
                LOG('OverflowTesting: OnCreateUI error: ' .. tostring(err))
            end
        end

        LOG('OverflowTesting: hooked CreateUI successfully')
    end
end