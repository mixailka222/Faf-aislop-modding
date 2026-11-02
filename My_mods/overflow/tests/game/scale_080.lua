-- stand: profile options = { ui_scale = 0.8 }

-- At ui_scale 0.8 one pixel of a divider rounds down to zero unless the mod keeps it.
local Test = import("/mods/ModTest/modules/test.lua")
local Panel = import("/mods/ModTestScenarios/support/panel.lua")

function Run()
    local panel = Panel.State()
    Test.Check(panel ~= nil, "the state of the panel is readable")
    if not panel then
        return
    end
    Test.Check(import("/lua/maui/layouthelpers.lua").GetPixelScaleFactor() == 0.8, "the match runs at ui_scale 0.8")
    Panel.WaitForNumbers(panel)
    Panel.ReportFont(panel, "ui_scale 0.8")
    Panel.ShowAllRows(panel)
    Panel.CheckDividers(panel, "ui_scale 0.8")
    Panel.CheckRowsInside(panel, "ui_scale 0.8")
end
