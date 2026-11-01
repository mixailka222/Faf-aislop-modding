-- Overflow - entry point for the "UI mod tools" (UMT) mod.
--
-- UMT calls Main() of every Main.lua (the file name match ignores case) in the mods flagged
-- with __umt, and it loads modules/Options.lua only when the field
-- UMT.Options.Mods["Overflow"] is read. Without this file the settings page never appears.
--
-- Reading that field is all Main does. It does not import ui.lua: the load order of UMT and
-- the game interface is unknown, and the import could meet a module that is still loading.
--
-- UMT calls Main without pcall, and an error here would stop CreateGameInterface. So the
-- read goes through pcall and a failure goes to the log.

function Main(isReplay)
    if not UMT or not UMT.Options or not UMT.Options.Mods then
        LOG('Overflow: UMT not available, options page skipped')
        return
    end

    -- This read makes UMT find modules/Options.lua and call its Main(). UMT searches the
    -- whole folder of the mod.
    local ok, err = pcall(function()
        return UMT.Options.Mods["Overflow"]
    end)

    if not ok then
        LOG('Overflow: UMT options FAILED: ' .. tostring(err))
        return
    end

    -- nil means Options.lua was not found or failed, and the player gets no page.
    if err == nil then
        LOG('Overflow: FAILED - UMT did not find modules/Options.lua')
    else
        LOG('Overflow: UMT options page requested, 7 rows')
    end
end
