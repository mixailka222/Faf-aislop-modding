-- The player assigns the three actions during a match. The key window is open and its OK step runs, only
-- the clicks in the window are replaced by the call they end in. The keys are then pressed for real.
local Test = import("/mods/ModTest/modules/test.lua")
local KeyMapper = import("/lua/keymap/keymapper.lua")
local Keybindings = import("/lua/ui/dialogs/keybindings.lua")

local PATROL_ENGINEER = "uel0105"
local TOGGLE_KEY = "K"
local CHECK_KEY = "L"
local RESET_KEY = "J"
local COMBINATION = "Ctrl-Alt-R"
local KEY_SECONDS = 8

function Run()
    local Settings = import("/mods/ReclaimPause/modules/settings.lua")
    local Watch = import("/mods/ReclaimPause/modules/watch.lua")
    Settings.ReclaimPauseCfg.startGrace = 0
    local watched = Test.WatchLog(Watch)
    local settingsLines = Test.WatchLog(Settings)

    WaitSeconds(2)
    Test.Spawn(PATROL_ENGINEER, 6, 6, { { 30, 30 }, { -10, 30 } })
    WaitSeconds(2)
    local engineer = Test.FindById(Test.UnitsOfCategory("ENGINEER"), PATROL_ENGINEER)
    Test.Check(engineer, "the engineer exists")
    if not engineer then
        return
    end
    Test.Check(Test.WaitUntil(function() return GetIsPausedOfUnit(engineer) end, 10), "the engineer is paused")

    local KEYS = {
        reclaimpause_toggle = TOGGLE_KEY,
        reclaimpause_check = CHECK_KEY,
        reclaimpause_defaults = RESET_KEY,
    }
    Keybindings.CreateUI()
    local listed = {}
    for _, line in Test.Upvalue(Keybindings.CreateUI, "FormatData")() do
        if line.type == "entry" and line.category == "reclaimpause" then
            listed[line.action] = line.text
        end
    end
    for action in KEYS do
        Test.Step("in the key window: " .. tostring(listed[action]))
        Test.Check(listed[action] ~= nil, "the key window lists " .. action)
    end

    for action, key in KEYS do
        KeyMapper.SetUserKeyMapping(key, nil, action)
    end
    local Confirm = Test.Upvalue(Keybindings.CreateUI, "ConfirmNewKeyMap")
    Test.Check(Confirm ~= nil, "the OK step of the key window is readable")
    Confirm()
    Keybindings.CloseUI()
    for action, key in KEYS do
        Test.Check(KeyMapper.GetCurrentKeyBinding(action) == key, "the key is saved: " .. key)
    end

    local function Press(key, lines, text)
        Test.PressKey(key)
        Test.Check(Test.WaitUntil(function() return Test.Logged(lines, text) end, KEY_SECONDS), "the log has: " .. text)
    end

    Test.ForgetLog(watched)
    Press(TOGGLE_KEY, watched, "toggled, enabled=false")
    Test.Check(Test.WaitUntil(function() return not GetIsPausedOfUnit(engineer) end, 3), "the pause is released")
    Press(TOGGLE_KEY, watched, "toggled, enabled=true")

    Test.ForgetLog(watched)
    Press(CHECK_KEY, watched, "CHECK ")
    Test.Check(Test.Logged(watched, "verdict="), "the line has verdict=")

    Press(RESET_KEY, settingsLines, "settings reset to defaults")

    KeyMapper.SetUserKeyMapping(COMBINATION, TOGGLE_KEY, "reclaimpause_toggle")
    Confirm()
    Test.ForgetLog(watched)
    Press(COMBINATION, watched, "toggled, enabled=false")
end
