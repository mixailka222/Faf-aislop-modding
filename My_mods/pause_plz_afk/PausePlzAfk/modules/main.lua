-- PausePlzAfk - entry point for the 'UI mod tools' (UMT) mod.
--
-- UMT calls Main() of the mods flagged with __umt in mod_info.lua, and it loads options.lua
-- only when the field UMT.Options.Mods['PausePlzAfk'] is read. Reading that field is all
-- this file does.
--
-- UMT calls Main without pcall, and an error here would stop CreateGameInterface and leave
-- a black screen. So the read goes through pcall and a failure only reaches the log.

function Main(isReplay)
    if not UMT or not UMT.Options or not UMT.Options.Mods then
        LOG('PausePlzAfk: UMT not available, options page skipped')
        return
    end

    -- Reading this one field makes UMT find and run options.lua.
    local ok, seen = pcall(function() return UMT.Options.Mods['PausePlzAfk'] end)
    if not ok then
        LOG('PausePlzAfk: UMT options FAILED: ' .. tostring(seen))
        return
    end
    if seen == nil then
        LOG('PausePlzAfk: UMT did not register our options page')
    end
end
