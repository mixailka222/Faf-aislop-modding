-- The real page of the mod, opened the way the list of UMT opens it. A key changes the settings past the
-- page, so the next slider move must not write old values back and Cancel must not undo the key.
local Test = import("/mods/ModTest/modules/test.lua")
local Prefs = import("/lua/user/prefs.lua")

local SKIP_SLIDER = "Не трогать N секунд после ручного снятия"
local TITLE = "ReclaimPause"

local function Saved(field)
    return Prefs.GetFromCurrentProfile("ReclaimPause")[field]
end

function Run()
    WaitSeconds(2)
    local Settings = import("/mods/ReclaimPause/modules/settings.lua")
    local Watch = import("/mods/ReclaimPause/modules/watch.lua")
    local OptionsWindow = import("/mods/UMT/modules/OptionsWindow.lua").OptionsWindow
    local Options = UMT.Options
    local options = Options.Mods["ReclaimPause"]
    local actions = import("/lua/keymap/keyactions.lua").keyActions
    local pages = Test.Upvalue(Options.AddOptions, "globalOptions")
    local page = pages and pages[TITLE]
    Test.Check(page ~= nil, "the page of the mod is registered")
    if not page then
        return
    end
    local windowLines = Test.WatchLog(import("/mods/ReclaimPause/modules/options.lua"))

    local function OpenWindow(entries)
        return OptionsWindow(GetFrame(0), page[1], TITLE, entries or page[2])
    end

    local function Press(action)
        ConExecute(action.action)
        WaitSeconds(0.5)
    end

    -- Threshold 90 is saved, the reset key comes, then a slider moves in a window opened after the key.
    options.highMass:Set(90)
    options.highMass:Save()
    Test.Check(Settings.ReclaimPauseCfg.highMass == 90, "the threshold is 90")
    Press(actions.reclaimpause_defaults)
    local window = OpenWindow()
    Test.ForgetLog(windowLines)
    window:SetOption("minSec", 5)
    Test.Step("after the slider: " .. Settings.ReclaimPauseSettingsLine())
    Test.Check(Test.Logged(windowLines, "settings from window"), "the slider writes settings from window")
    Test.Check(Test.Logged(windowLines, "mass=65..70"), "the line has mass=65..70")
    Test.Check(Settings.ReclaimPauseCfg.highMass == 70, "the threshold stayed at the default")
    window:OnClose(true)

    -- The mod is switched off by the key before the window opens, Cancel must keep that.
    Press(actions.reclaimpause_toggle)
    Test.Check(Settings.ReclaimPauseCfg.enabled == false, "the key switched the mod off")
    window = OpenWindow()
    window:OnClose()
    Test.Check(Settings.ReclaimPauseCfg.enabled == false, "Cancel keeps the mod switched off")
    Test.Check(options.enabled() == false, "Cancel keeps the mod switched off in the window")
    Test.Check(Saved("enabled") == false, "the profile keeps the mod switched off")
    Press(actions.reclaimpause_toggle)
    Test.Check(Settings.ReclaimPauseCfg.enabled == true, "the key switches the mod on again")

    local entry
    for _, candidate in page[2] do
        if candidate.name == SKIP_SLIDER then
            entry = candidate
        end
    end
    Test.Check(entry ~= nil, "the page has the slider")
    if not entry then
        return
    end
    Press(actions.reclaimpause_defaults)
    window = OpenWindow({ entry })
    local shown = window._previous
    Test.Step("slider: value text '" .. tostring(shown.value:GetText()) .. "', position " ..
        tostring(shown.slider:GetValue()) .. ", step " .. tostring(entry.inc))
    Test.Check(tonumber(shown.value:GetText()) == 3, "the slider shows 3")
    Test.Check(shown.slider:GetValue() == 3, "the handle of the slider stands on 3")
    window:OnClose()
end
