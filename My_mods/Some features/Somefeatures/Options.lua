---@diagnostic disable: undefined-field
-- The LuaLS metadata of ReUI declares `ReUI.Options` as an empty table, so every member of the
-- loaded module is reported as an undefined field. The members exist at runtime.

local OptionValue = ReUI.Options.OptionValue
local ModOptions = ReUI.Options.Mods
local AddOptions = ReUI.Options.Add
local OptionsWindow = ReUI.Options.Window

ModOptions["Somefeatures"] = {
    engineerSelection = OptionValue(true),
    ctrlRightClickMove = OptionValue(true),
    middleClickPriority = OptionValue(true),
}

function Main()
    AddOptions("Some features", function(frame)
        local options = ModOptions["Somefeatures"]
        return OptionsWindow("Some features", function(window)
            window:OptionCheckbox("Shift+Alt selects only engineers, commanders and SACUs", options.engineerSelection)
            window:OptionCheckbox("Ctrl+Right Click moves instead of attacking", options.ctrlRightClickMove)
            window:OptionCheckbox("Middle Click sets target priority to the unit role", options.middleClickPriority)
        end)
    end)
end
