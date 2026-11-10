-- stand: profile options = { ui_scale = 1.5 }

-- At ui_scale 1.5 the rows stay inside the frame, the close button stays off the top row and the Overflow
-- button comes up where the panel was.
local Test = import("/mods/ModTest/modules/test.lua")
local Panel = import("/mods/ModTestScenarios/support/panel.lua")

function Run()
    local panel = Panel.State()
    Test.Check(panel ~= nil, "the state of the panel is readable")
    if not panel then
        return
    end
    Test.Check(import("/lua/maui/layouthelpers.lua").GetPixelScaleFactor() == 1.5, "the match runs at ui_scale 1.5")
    Panel.WaitForNumbers(panel)
    Panel.ReportFont(panel, "ui_scale 1.5")
    Panel.CheckRowsInside(panel, "two rows")
    Panel.CheckCloseButton(panel, "two rows")
    Panel.ShowAllRows(panel)
    Panel.CheckRowsInside(panel, "all rows")
    Panel.CheckCloseButton(panel, "all rows")
    Test.Shot("before_collapse")
    Panel.CheckCollapse(panel, "all rows")
    Test.Shot("after_reopen")

    panel.win.Left:Set(panel.win.Left() + 200)
    panel.win.Right:Set(panel.win.Right() + 200)
    panel.win.Top:Set(panel.win.Top() + 100)
    panel.win.Bottom:Set(panel.win.Bottom() + 100)
    Panel.CheckCollapse(panel, "moved panel")
end
