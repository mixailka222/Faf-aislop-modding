-- PausePlzAfk - entry point for the 'UI mod tools' (UMT) mod.
--
-- THIS FILE IS REQUIRED, though it does nothing by itself. Mechanics:
--
-- 1. UMT lists mods flagged with __umt in mod_info.lua.
-- 2. Then it looks for Main.lua in the mod folder and calls its Main()
--    (umt/modules/Mods.lua:4-12).
-- 3. The options page lives in a separate options.lua, and UMT loads it
--    ONLY when someone READS the field UMT.Options.Mods['PausePlzAfk'].
--
-- A closed loop: without main.lua nobody reads the field, without reading
-- the field options.lua never loads, without options.lua the page never
-- appears. (Same trap ReclaimPause documents in its modules/main.lua.)
--
-- WHY pcall. UMT calls Main UNPROTECTED (Mods.lua:9, no pcall around
-- import(file).Main(isReplay)). Any error here escapes outward and kills
-- CreateGameInterface - a black screen. Settings are an optional nicety
-- and must not be able to kill the game, so the read is wrapped in pcall
-- and failures only go to LOG: the mod works, the page is missing, and the
-- player learns it from the log instead of a black screen.

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
