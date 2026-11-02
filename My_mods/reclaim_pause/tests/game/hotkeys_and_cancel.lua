-- A hotkey changes the settings past the open UMT window. Cancel undoes what the player moved in the
-- window, but it must not bring back a value the hotkey has replaced.
local Test = import("/mods/ModTest/modules/test.lua")
local Prefs = import("/lua/user/prefs.lua")

local KEPT = 85
local MOVED = 90

local function Saved(field)
    return Prefs.GetFromCurrentProfile("ReclaimPause")[field]
end

function Run()
    WaitSeconds(2)
    local actions = import("/lua/keymap/keyactions.lua").keyActions
    local reset = actions.reclaimpause_defaults
    local toggle = actions.reclaimpause_toggle
    Test.Check(reset and toggle, "the hotkey actions of the mod exist")
    if not (reset and toggle) then
        return
    end

    local Settings = import("/mods/ReclaimPause/modules/settings.lua")
    local OptionsWindow = import("/mods/UMT/modules/OptionsWindow.lua").OptionsWindow
    local Options = UMT.Options
    local options = Options.Mods["ReclaimPause"]
    local default = Settings.ReclaimPauseDefaults().highMass

    -- A key press runs the text of its action, and so does this.
    local function Press(action)
        ConExecute(action.action)
        WaitSeconds(0.5)
    end

    -- The page of the mod lives inside UMT, this window is built by the same class from its OptionVars.
    local function MoveSliderInWindow()
        options.highMass:Set(KEPT)
        options.highMass:Save()
        local window = OptionsWindow(GetFrame(0), "ReclaimPause", "ModTest", {
            Options.Filter("enabled", options.enabled, 16),
            Options.Slider("highMass", 50, 100, 1, options.highMass, 16),
        })
        options.highMass:Set(MOVED)
        return window
    end

    local window = MoveSliderInWindow()
    Press(reset)
    Test.Check(options.highMass() == default, "the reset key reaches the open window")
    window:OnClose()
    Test.Check(Settings.ReclaimPauseCfg.highMass == default, "Cancel keeps the reset value in the mod")
    Test.Check(options.highMass() == default, "Cancel keeps the reset value in the window")
    Test.Check(Saved("highMass") == default, "Cancel keeps the reset value in the profile")

    window = MoveSliderInWindow()
    Press(toggle)
    Test.Check(options.enabled() == false, "the toggle key reaches the open window")
    window:OnClose()
    Test.Check(Settings.ReclaimPauseCfg.highMass == KEPT, "Cancel undoes the slider after the toggle key")
    Test.Check(Saved("highMass") == KEPT, "the profile has the value from before the slider move")
    Test.Check(Settings.ReclaimPauseCfg.enabled == false, "Cancel keeps the mod switched off")
    Test.Check(Saved("enabled") == false, "the profile keeps the mod switched off")
    Press(toggle)
end
