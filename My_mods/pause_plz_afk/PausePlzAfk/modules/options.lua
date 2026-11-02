-- PausePlzAfk - options page for the 'UI mod tools' (UMT) mod. UMT calls Main() when the
-- field UMT.Options.Mods['PausePlzAfk'] is read. Without UMT nobody opens this file and the
-- mod works on the profile defaults.
--
-- The player opens the window from the game menu: 'UI mods options'.
--
-- OptionVar:Set() changes the value in memory only, the profile gets it from
-- OptionVar:Save() when the window closes. So the live value is read from the OptionVar
-- itself and saved at once: the profile, the window and the mod see the same text.

function Main()
    local Options = UMT.Options
    local Opt = Options.Opt
    local PFX = 'PausePlzAfk: '

    local Settings = import('/mods/PausePlzAfk/modules/settings.lua')

    local def = Settings.PauseAfkDefaults()

    -- The assignment, not a call, creates the OptionVars. Opt() takes only the default.
    Options.Mods['PausePlzAfk'] = {
        msgText = Opt(def.msgText),
    }

    local options = Options.Mods['PausePlzAfk']

    local function Refresh()
        local cfg = Settings.PauseAfkCfg
        cfg.msgText = Settings.PauseAfkSaneMsg(options.msgText())
        Settings.PauseAfkSaveSettings()
        LOG(PFX .. 'settings from window: ' .. Settings.PauseAfkSettingsLine())
    end

    -- Bind calls Refresh at once, so it has to work before the match mod has started.
    options.msgText:Bind(Refresh)

    -- 200 is the chat text limit. UMT shows the second argument in its list, and the name
    -- of the mod is the only thing that identifies it there.
    Options.AddOptions('PausePlzAfk', 'PausePlzAfk', {
        Options.TextEdit('AFK chat message', options.msgText, 200),
    })

    LOG(PFX .. 'UMT options page registered')
end
