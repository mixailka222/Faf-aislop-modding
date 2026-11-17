-- Checks that all three ReUI options are registered and enabled by default.
local Test = import("/mods/ModTest/modules/test.lua")

function Run()
    local modOptions = ReUI.Options.Mods["Somefeatures"]
    Test.Check(modOptions ~= nil, "Somefeatures options are registered")
    if not modOptions then
        return
    end
    Test.Check(modOptions.engineerSelection:Get() == true, "selection option is enabled by default")
    Test.Check(modOptions.ctrlRightClickMove:Get() == true, "Ctrl+RMB option is enabled by default")
    Test.Check(modOptions.middleClickPriority:Get() == true, "MMB priority option is enabled by default")
end
