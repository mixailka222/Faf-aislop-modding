-- The preset of all seven rows at the normal scale: the bottom row stays inside the frame, dragging keeps
-- the height of the window, and the close button and the Overflow button work.
local Test = import("/mods/ModTest/modules/test.lua")
local Panel = import("/mods/ModTestScenarios/support/panel.lua")

local PLAYER_EXTRA_HEIGHT = 10
local ALL_ROWS = "1111111"
local FEW_ROWS_PRESET = "Только E ally overflow"

--- One step of dragging, in the order of the class Window: width and height are taken on the press,
--- the corners are set, then OnMove runs.
local function DragStep(win, dx, dy)
    local width, height = win.Width(), win.Height()
    win.Left:Set(win.Left() + dx)
    win.Top:Set(win.Top() + dy)
    local right, bottom = win.Left() + width, win.Top() + height
    win.Right:Set(right)
    win.Bottom:Set(bottom)
    win:OnMove(win.Left(), win.Top(), false)
end

local function Height(win)
    return win.Bottom() - win.Top()
end

function Run()
    local panel = Panel.State()
    Test.Check(panel ~= nil, "the state of the panel is readable")
    if not panel then
        return
    end
    Panel.WaitForNumbers(panel)
    Panel.ReportFont(panel, "ui_scale 1")
    local win = panel.win

    local function CheckDrag(title)
        local before = Height(win)
        DragStep(win, 10, 10)
        local during = Height(win)
        Test.Step(title .. ": height before the drag " .. tostring(before) .. ", during it " .. tostring(during))
        Test.Check(during == before, title .. ": dragging keeps the height of the window")
        Test.Check(Test.WaitUntil(function() return Height(win) == before end, 3),
            title .. ": the height is the same after the drag")
    end

    Panel.ShowAllRows(panel)
    Panel.CheckRowsInside(panel, "all rows")
    Panel.CheckDividers(panel, "all rows")
    Panel.CheckCloseButton(panel, "all rows")
    CheckDrag("window sized by the mod")
    Panel.CheckCollapse(panel, "all rows")

    -- The player pulled the window a bit higher with few rows, then asked for more rows.
    UMT.Options.Mods["Overflow"].preset:Set(FEW_ROWS_PRESET)
    Test.Check(Test.WaitUntil(function() return panel.rowsSig ~= ALL_ROWS end, 5),
        "the panel took the preset of few rows")
    win.Bottom:Set(win.Bottom() + PLAYER_EXTRA_HEIGHT)
    win:OnResizeSet()
    Test.Step("height chosen by the player: " .. tostring(panel.wantH))
    Panel.ShowAllRows(panel)
    CheckDrag("height chosen by the player")
end
