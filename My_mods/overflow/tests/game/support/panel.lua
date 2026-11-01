-- What the scenarios of the panel share. The controls are read from the state table of ui.lua, their
-- positions are screen pixels.
local Test = import("/mods/ModTest/modules/test.lua")

local ROW_ORDER = { "eOverflow", "eGo", "eOwn", "mOverflow", "mGo", "mOwn", "total" }
local DIVIDER_BELOW = { eOwn = "divider1", mOwn = "divider2" }
local ALL_ROWS = "1111111"
local ALL_ROWS_PRESET = "Все строки"

function State()
    return Test.Upvalue(import("/mods/Overflow/modules/ui.lua").CreatePanel, "G")
end

--- The rows have text only after the first numbers came.
function WaitForNumbers(panel)
    local Sync = import("/mods/Overflow/modules/sync.lua")
    Test.Check(Test.WaitUntil(function() return panel.win ~= nil and Sync.GetResult() ~= nil end, 30),
        "the first numbers came")
    Test.WaitUntil(function() return (panel.labels.eOverflow:GetText() or "") ~= "" end, 5)
end

function ShowAllRows(panel)
    UMT.Options.Mods["Overflow"].preset:Set(ALL_ROWS_PRESET)
    Test.Check(Test.WaitUntil(function() return panel.rowsSig == ALL_ROWS end, 5),
        "the panel took the preset of all rows")
    Test.WaitUntil(function() return (panel.labels.total:GetText() or "") ~= "" end, 10)
end

local function TextRight(label)
    return label.Left() + label:GetStringAdvance(label:GetText())
end

local function TextBottom(label)
    return label.Top() + label.FontAscent() + label.FontDescent()
end

--- Logs the numbers of every visible row and checks that its text stays inside the frame. A row counts
--- by the text it shows, because the box of a row is wider than its text.
function CheckRowsInside(panel, title)
    local win = panel.win
    Test.Step(title .. ": window L=" .. tostring(win.Left()) .. " T=" .. tostring(win.Top()) ..
        " R=" .. tostring(win.Right()) .. " B=" .. tostring(win.Bottom()))
    local previous
    for _, row in ROW_ORDER do
        local label = panel.labels[row]
        if not label:IsHidden() then
            Test.Step(title .. ": " .. row .. " '" .. tostring(label:GetText()) .. "' L=" .. tostring(label.Left()) ..
                " T=" .. tostring(label.Top()) .. " textR=" .. tostring(TextRight(label)) ..
                " textB=" .. tostring(TextBottom(label)) .. " box B=" .. tostring(label.Bottom()))
            Test.Check(label.Left() >= win.Left() and TextRight(label) <= win.Right(),
                title .. ": " .. row .. " fits the width")
            Test.Check(label.Top() >= win.Top() and TextBottom(label) <= win.Bottom(),
                title .. ": " .. row .. " fits the height")
            if previous then
                Test.Check(previous.Top() < label.Top(), title .. ": " .. row .. " stands below the row above")
            end
            previous = label
        end
    end
end

--- The close button lives in the top right corner, the top row must not run under it.
function CheckCloseButton(panel, title)
    local button = panel.win._closeBtn
    local top = panel.labels.eOverflow
    Test.Step(title .. ": close button L=" .. tostring(button.Left()) .. " T=" .. tostring(button.Top()) ..
        " B=" .. tostring(button.Bottom()) .. ", top row textR=" .. tostring(TextRight(top)))
    local apart = TextRight(top) <= button.Left() or TextBottom(top) <= button.Top() or top.Top() >= button.Bottom()
    Test.Check(apart, title .. ": the close button does not cover the top row")
end

--- Dividers are thin, so a scale below 1 could round them away.
function CheckDividers(panel, title)
    for row, name in DIVIDER_BELOW do
        local divider = panel.labels[name]
        local above = panel.labels[row]
        Test.Step(title .. ": " .. name .. " T=" .. tostring(divider.Top()) .. " H=" .. tostring(divider.Height()) ..
            " L=" .. tostring(divider.Left()) .. " R=" .. tostring(divider.Right()) ..
            ", row above T=" .. tostring(above.Top()))
        Test.Check(not divider:IsHidden(), title .. ": " .. name .. " is shown")
        Test.Check(divider.Height() >= 1, title .. ": " .. name .. " is at least one pixel high")
        Test.Check(divider.Right() > divider.Left(), title .. ": " .. name .. " has a width")
        Test.Check(divider.Top() > above.Top() and divider.Top() < panel.win.Bottom(),
            title .. ": " .. name .. " stands below its row")
    end
end

--- Reports the size of the font. The size of a row comes from the options of the mod and from ui_scale.
function ReportFont(panel, title)
    local label = panel.labels.eOverflow
    Test.Step(title .. ": ui_scale " .. tostring(import("/lua/maui/layouthelpers.lua").GetPixelScaleFactor()) ..
        ", font size " .. tostring(label._font._pointsize()) ..
        ", font height " .. tostring(label.FontAscent() + label.FontDescent()) ..
        ", width of the sample " .. tostring(label:GetStringAdvance("E ally overflow: 0.0 E/s")))
end

--- The button that brings the panel back appears where the panel was. The button of the window and the
--- press on the panel button are what the game calls on a click.
function CheckCollapse(panel, title)
    local win = panel.win
    local left, top = win.Left(), win.Top()
    win._closeBtn:OnClick()
    Test.Check(win:IsHidden(), title .. ": the close button hides the panel")
    Test.Check(not panel.reopenButton:IsHidden(), title .. ": the Overflow button is shown")
    for _, piece in panel.frameBg or {} do
        Test.Check(piece:IsHidden(), title .. ": the frame is hidden with the panel")
    end
    Test.Step(title .. ": panel at " .. tostring(left) .. "," .. tostring(top) .. ", button at " ..
        tostring(panel.reopenButton.Left()) .. "," .. tostring(panel.reopenButton.Top()))
    Test.Check(math.abs(panel.reopenButton.Left() - left) <= 1 and math.abs(panel.reopenButton.Top() - top) <= 1,
        title .. ": the Overflow button stands where the panel was")
    panel.reopenButton:HandleEvent({ Type = "ButtonRelease" })
    Test.Check(not win:IsHidden(), title .. ": a click brings the panel back")
    Test.Check(panel.reopenButton:IsHidden(), title .. ": the Overflow button is gone")
    for _, piece in panel.frameBg or {} do
        Test.Check(not piece:IsHidden(), title .. ": the frame is back")
    end
end
