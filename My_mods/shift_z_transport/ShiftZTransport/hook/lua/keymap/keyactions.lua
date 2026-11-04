--  shift_z_transport: context-sensitive Shift+Z for transports and factories.
--  This file is appended to the game's /lua/keymap/keyactions.lua
--  by the FAF hook system, so it runs while the key action table is being built.
--
--  Only the code behind the existing action is replaced. The key binding itself is not
--  touched: Shift+Z stays 'shift_spreadattack' in defaultKeyMap/hotbuildKeyMap and in
--  the user's profile.
--
--  The whole decision lives in this file and is published as a global, so pressing the
--  key never imports a module of this mod. An import at press time can fail (for example
--  when ReUI has not preloaded the mod yet) and then the key would silently do nothing.

local function OptionIsOn()
    local reui = rawget(_G, "ReUI")
    if not reui then
        return true
    end

    local options = rawget(reui, "Options")
    if not options then
        return true
    end

    local mods = rawget(options, "Mods")
    if not mods then
        return true
    end

    -- Indexing an unknown mod raises an error, so it has to stay inside pcall.
    local ok, opts = pcall(function() return mods["ShiftZTransport"] end)
    if not ok or not opts then
        return true
    end

    local opt = rawget(opts, "enabled")
    if not opt then
        return true
    end

    local read, flag = pcall(function() return opt:Get() end)
    if not read then
        return true
    end

    return flag ~= false
end

local function OnlyTransports(selection)
    local total = table.getn(selection)
    if total == 0 then
        return false
    end

    local transports = EntityCategoryFilterDown(categories.TRANSPORTATION, selection)
    return table.getn(transports) == total
end

local function OnlyFactories(selection)
    local total = table.getn(selection)
    if total == 0 then
        return false
    end

    local factories = EntityCategoryFilterDown(
        categories.FACTORY + categories.EXTERNALFACTORY, selection)
    return table.getn(factories) == total
end

rawset(_G, "ShiftZTransportSpreadMove", function()
    if OptionIsOn() then
        local selection = GetSelectedUnits()
        if selection then
            if OnlyTransports(selection) then
                ConExecute("StartCommandMode order RULEUCC_Transport")
                return
            end

            if OnlyFactories(selection) then
                import("/lua/keymap/misckeyactions.lua").ToggleRepeatBuild()
                return
            end
        end
    end

    import("/lua/ui/game/hotkeys/distribute-queue.lua").DistributeOrders(true)
end)

local target = keyActions['shift_spreadattack']
if target then
    target.action = "UI_Lua ShiftZTransportSpreadMove()"
else
    WARN("[shift_z_transport] key action 'shift_spreadattack' is missing; mod does nothing")
end
