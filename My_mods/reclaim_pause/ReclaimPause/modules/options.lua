-- ReclaimPause - settings page for the "UI mod tools" (UMT) mod.
--
-- Only UMT loads this file: it looks for options.lua in the mods flagged with __umt in
-- mod_info.lua and calls Main(). Without UMT the mod works on its defaults. The player
-- opens the window from the game menu: "UI mods options".
--
-- OptionVar:Save() writes to the profile key 'ReclaimPause' under the field names used
-- here, the same key and names as in settings.lua. The names here and in DEFAULTS have to
-- match, or the window and the mod would read different values.

function Main()
    local Options = UMT.Options
    local Opt = Options.Opt
    local PFX = 'ReclaimPause: '

    local Settings = import('/mods/ReclaimPause/modules/settings.lua')
    local Watch = import('/mods/ReclaimPause/modules/watch.lua')

    local def = Settings.ReclaimPauseDefaults()

    -- The assignment, not a call, creates an OptionVar for each field. Opt() takes only the
    -- default, UMT supplies the prefs key.
    Options.Mods["ReclaimPause"] = {
        enabled        = Opt(def.enabled),
        highMass       = Opt(def.highMass),
        lowMass        = Opt(def.lowMass),
        energyMin      = Opt(def.energyMin),
        minSec         = Opt(def.minSec),
        releaseHoldSec = Opt(def.releaseHoldSec),
        rescanSec      = Opt(def.rescanSec),
        startGrace     = Opt(def.startGrace),
        abortMove      = Opt(def.abortMove),
        abortSec       = Opt(def.abortSec),
        skipSec        = Opt(def.skipSec),
        -- Not a setting but a button that clears itself. UMT saves every OptionVar of the
        -- window, so the profile always holds resetFlag = false and no reset repeats at the
        -- start.
        resetFlag      = Opt(false),
    }

    local options = Options.Mods["ReclaimPause"]

    -- The live value comes from the OptionVar, called as a function, and not from
    -- ReclaimPauseLoadSettings(): OptionVar:Set() changes it in memory only, and UMT calls
    -- OptionVar:Save() when the window closes. Right after a slider moves the profile still
    -- holds the old value.
    -- Set on resetFlag calls OnChange, which is this same Refresh. The flag stops
    -- that nested call while the reset takes the check mark off.
    local writing = false

    -- Raw(), not Set: Set would remember the old value for Cancel and call Refresh.
    -- Save forgets the value remembered when a slider moved before the key press,
    -- otherwise Cancel would bring it back. The profile already has the new value.
    -- A key that changes one setting names it, so Cancel still undoes the others.
    local function PushToWindow(name)
        for field, value in Settings.ReclaimPauseCfg do
            if name == nil or name == field then
                options[field]:Raw():Set(value)
                options[field]:Save()
            end
        end
    end

    local function Refresh()
        if writing then return end

        local cfg = Settings.ReclaimPauseCfg

        -- The reset goes first: the lines below would overwrite it with the old values.
        -- ReclaimPauseResetDefaults calls PushToWindow, which writes the sliders.
        if options.resetFlag() then
            writing = true
            options.resetFlag:Set(false)
            Settings.ReclaimPauseResetDefaults()
            cfg = Settings.ReclaimPauseCfg
            writing = false
            LOG(PFX .. 'RESET FROM PAGE: ' .. Settings.ReclaimPauseSettingsLine())
        end

        cfg.enabled        = options.enabled() and true or false
        cfg.highMass       = options.highMass()
        cfg.lowMass        = options.lowMass()
        cfg.energyMin      = options.energyMin()
        cfg.minSec         = options.minSec()
        cfg.releaseHoldSec = options.releaseHoldSec()
        cfg.rescanSec      = options.rescanSec()
        cfg.startGrace     = options.startGrace()
        cfg.abortMove      = options.abortMove() and true or false
        cfg.abortSec       = options.abortSec()
        cfg.skipSec        = options.skipSec()
        Settings.ReclaimPauseApplyValues(cfg)
        -- Saved at once, so that the profile, the window and the mod see the same values.
        Settings.ReclaimPauseSaveSettings()
        Watch.ReclaimPauseApplySettings()
        LOG(PFX .. 'settings from window: ' .. Settings.ReclaimPauseSettingsLine())
    end

    options.enabled:Bind(Refresh)
    options.highMass:Bind(Refresh)
    options.lowMass:Bind(Refresh)
    options.energyMin:Bind(Refresh)
    options.minSec:Bind(Refresh)
    options.releaseHoldSec:Bind(Refresh)
    options.rescanSec:Bind(Refresh)
    options.startGrace:Bind(Refresh)
    options.abortMove:Bind(Refresh)
    options.abortSec:Bind(Refresh)
    options.skipSec:Bind(Refresh)
    options.resetFlag:Bind(Refresh)
    Settings.ReclaimPauseBindWindow(PushToWindow)

    -- The sliders stay within the limits of ReclaimPauseApplyValues, otherwise the window
    -- and the mod would hold different values. UMT shows the second argument in its list,
    -- and the name of the mod is the only thing that identifies it there.
    Options.AddOptions("ReclaimPause", "ReclaimPause", {
        Options.Filter("Мод включён", options.enabled),
        Options.Title("Пороги по массе", 14, nil, nil, 16),
        Options.Slider("Ставить на паузу от заполнения, %", 50, 100, 1, options.highMass, 16),
        Options.Slider("Снимать паузу от заполнения, %", 0, 100, 1, options.lowMass, 16),
        Options.Title("Энергия", 14, nil, nil, 16),
        Options.Slider("Ставить на паузу, только если энергии не меньше, %",
            0, 100, 1, options.energyMin, 16),
        Options.Title("Поведение", 14, nil, nil, 16),
        Options.Slider("Минимум секунд между переключениями", 0, 30, 1, options.minSec, 16),
        Options.Slider("Держать условие снятия N секунд (0 = сразу)",
            0, 60, 1, options.releaseHoldSec, 16),
        Options.Slider("Как часто искать инженеров, секунд", 1, 30, 1, options.rescanSec, 16),
        Options.Slider("Первые N секунд матча не трогать выделение", 10, 60, 5, options.startGrace, 16),
        Options.Filter("Останавливать на месте (обрыв маршрута)", options.abortMove, 16),
        Options.Slider("Повторять обрыв каждые N секунд", 1, 15, 1, options.abortSec, 16),
        Options.Slider("Не трогать N секунд после ручного снятия", 0, 60, 1, options.skipSec, 16),
        Options.Title("Сброс", 14, nil, nil, 16),
        -- A check box instead of a button: UMT has no button element. UMT draws the check
        -- mark once, when the window is created, so the mark disappears from the screen
        -- only after the window reopens. The value and the reset itself apply at once.
        Options.Filter("Сбросить все настройки к значениям по умолчанию",
            options.resetFlag, 16),
    })

    LOG(PFX .. 'UMT options page registered')
end
