-- PausePlzAfk - options page for the 'UI mod tools' (UMT) mod.
--
-- THIS FILE IS LOADED ONLY BY UMT. It looks for options.lua in folders of
-- mods flagged with __umt in mod_info.lua and calls Main(). If UMT is
-- missing or off, nobody opens this file and the mod keeps working on the
-- profile defaults.
--
-- The player opens the window from the game menu: 'UI mods options'.

-- How this works in UMT (from mods/umt/modules/Options.lua and the working
-- EUT mod - no invented API):
--
-- 1) Declaring settings is an ASSIGNMENT, not a call:
--
--        UMT.Options.Mods['PausePlzAfk'] = { msgText = Opt('...') }
--
--    The assignment hits ModsOptionsMetaTable.__newindex, which calls
--    LoadOptions, and that wraps each field in an OptionVar.
--
-- 2) Opt() takes ONE argument - the default. UMT supplies the prefs key.
--
-- 3) OptionVar:Set() changes the value in memory only; the profile gets it
--    via OptionVar:Save(), which UMT calls when the window closes. So the
--    moment the player edits the field, the profile is still old: read the
--    live value from the OptionVar itself (call it as a function), and save
--    at once so profile, window and mod see the same thing.
--
-- 4) OptionVar:Bind calls the function IMMEDIATELY, so Refresh must be safe
--    on first run - the match mod may not be started yet.

function Main()
    local Options = UMT.Options
    local Opt = Options.Opt
    local PFX = 'PausePlzAfk: '

    local Settings = import('/mods/PausePlzAfk/modules/settings.lua')

    local def = Settings.PauseAfkDefaults()

    -- STEP 1: declaration. The assignment itself creates the OptionVar.
    Options.Mods['PausePlzAfk'] = {
        msgText = Opt(def.msgText),
    }

    -- STEP 2: take back the created OptionVar.
    local options = Options.Mods['PausePlzAfk']

    -- STEP 3: react to change. Read the live OptionVar value (not Prefs),
    -- clean it through the same single source as the mod, save at once.
    local function Refresh()
        local cfg = Settings.PauseAfkCfg
        cfg.msgText = Settings.PauseAfkSaneMsg(options.msgText())
        Settings.PauseAfkSaveSettings()
        LOG(PFX .. 'settings from window: ' .. Settings.PauseAfkSettingsLine())
    end

    options.msgText:Bind(Refresh)

    -- STEP 4: window layout. 200 = the chat text limit (ChatPayload.lua:40).
    -- The second argument is the line the player sees in the UMT list
    -- (Options.lua:31-33 stores it in globalOptions[option][1]). Keep it
    -- equal to the mod name: it is the only thing identifying the mod there.
    Options.AddOptions('PausePlzAfk', 'PausePlzAfk', {
        Options.TextEdit('AFK chat message', options.msgText, 200),
    })

    LOG(PFX .. 'UMT options page registered')
end
