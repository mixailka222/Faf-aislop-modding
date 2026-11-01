-- Overflow - the panel, its rows are chosen in the settings.
--
-- Seven data rows: two independent triples split by thin lines, and the reclaim row.
--   E ally overflow / E to allies / E own production   - energy
--   M ally overflow / M to allies / M own production   - mass
--   reclaim E / M                                      - common row
--
-- The triples are independent: energy and mass overflow can go opposite ways, so each
-- resource takes its colour from its own numbers.
--
-- All numbers come from the game sync (modules/sync.lua). The mod does not touch the
-- selection, the command mode or the hotkey templates.
--
-- Rows can be switched one by one or as a ready-made set in "UI mods options". The list of
-- rows and their titles live in rows.lua, and the position of each row follows from the
-- number of visible rows (ComputeBody).
--
-- The UMT page only writes to the profile. Update() compares the signature of the row set
-- with its own and redoes the layout when it changes, so the page does not depend on the
-- load order of modules. Changing the set recreates nothing: only sizes and visibility
-- change, so dragging, resizing and collapsing keep working.
--
-- ---------------------------------------------------------------------------
-- WINDOW AND SIZE
--
-- The panel is a game Window (lua/maui/window.lua). The class moves and resizes
-- it and keeps its position and size in the profile under L.PANEL_KEY. The mod
-- only reacts: OnResize spreads the rows over the height, ApplyMinSize keeps the
-- window large enough for its text, OnMoveSet returns the height the player chose.
--
-- Nothing is recreated on resize. The window is rebuilt only when the look
-- changes, because colours are set in the constructors of the controls.
--
-- ---------------------------------------------------------------------------
-- STATE LIVES IN TABLE G
--
-- A function can capture at most 32 outer variables, otherwise the whole file
-- fails to compile with "too many upvalues (limit=32)". All panel state is kept
-- in one table, which costs one upvalue.

local UIUtil         = import('/lua/ui/uiutil.lua')
local Bitmap        = import('/lua/maui/bitmap.lua').Bitmap
local Group         = import('/lua/maui/group.lua').Group
local Window        = import('/lua/maui/window.lua').Window
local LayoutHelpers = import('/lua/maui/layouthelpers.lua')
local Prefs         = import('/lua/user/prefs.lua')
local GameMain      = import('/lua/ui/game/gamemain.lua')
local SyncModule    = import('/mods/Overflow/modules/sync.lua')
-- Module fields are read through rawget: a plain read of a missing field reaches the strict
-- _G and fails, while rawget returns nil.
local SyncStart  = rawget(SyncModule, 'Start')
local SyncResult = rawget(SyncModule, 'GetResult')

-- The list of rows and their titles live in rows.lua.
local RowsModule  = import('/mods/Overflow/modules/rows.lua')
local RowsVisible = rawget(RowsModule, 'VisibleRows')
local RowsSign    = rawget(RowsModule, 'RowsSignature')
local RowsTell    = rawget(RowsModule, 'DescribeRows')

-- The look lives in themes.lua.
local ThemesModule = import('/mods/Overflow/modules/themes.lua')
local ThemeColors  = rawget(ThemesModule, 'StylePalette')
local ThemeBlink   = rawget(ThemesModule, 'ThemeBlinkOn')
local ThemeSign    = rawget(ThemesModule, 'ThemeSignature')
local ThemeTellIt  = rawget(ThemesModule, 'ThemeTell')
local ThemeFont    = rawget(ThemesModule, 'StyleFontSize')
local ThemeMinimal = rawget(ThemesModule, 'FrameMinimal')
local ThemeNumbers = rawget(ThemesModule, 'NumbersOnly')

local GetCursor    = GetCursor
local GetFrame     = GetFrame
local StringFormat = string.format
local MathAbs      = math.abs
local MathMax      = math.max
local MathMin      = math.min
local MathFloor    = math.floor
local TableGetn    = table.getn
local LOG          = LOG

--------------------------------------------------------------------------------
-- Load check of the modules
--
-- If sync.lua fails to load, the panel still appears, empty, and LuaPlus blames this file
-- with 'access to nonexistent global variable "GetResult"'. So the modules are checked
-- right after the import.
--------------------------------------------------------------------------------

if type(SyncModule) ~= 'table' or type(SyncResult) ~= 'function' then
    LOG('Overflow: FATAL - sync.lua did not load, panel will be EMPTY. ' ..
        'Look for the real error earlier in this log.')
end

-- Without rows.lua the data still comes and the panel shows all rows.
if type(RowsVisible) ~= 'function' or type(RowsSign) ~= 'function' then
    LOG('Overflow: FATAL - rows.lua did not load, showing all rows. ' ..
        'Look for the real error earlier in this log.')
    RowsVisible = nil
    RowsSign = nil
    RowsTell = nil
end

-- Without themes.lua the panel uses the built-in colours below.
if type(ThemeColors) ~= 'function' or type(ThemeSign) ~= 'function' then
    LOG('Overflow: FATAL - themes.lua did not load, using built-in colours. ' ..
        'Look for the real error earlier in this log.')
    ThemeColors  = nil
    ThemeBlink   = nil
    ThemeSign    = nil
    ThemeTellIt  = nil
    ThemeFont    = nil
    ThemeMinimal = nil
    ThemeNumbers = nil
end

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

-- Sizes inside the window. The font stays the same at any window size.
local L = {
    -- Default size: all seven rows plus the 30 px title and the frame.
    DEFAULT_W = 340,
    DEFAULT_H = 160,

    -- Text margin from the border, about one character at size 11.
    PAD      = 10,
    PAD_TOP  = 8,

    -- Row step: at font size 11-12 this fits seven rows into the window.
    ROW_STEP   = 14,
    ROW_H      = 14,

    DIV_PRE    = 0,           -- gap before a divider
    DIV_POST   = 4,           -- gap after a divider
    DIV_H      = 1,           -- divider thickness
    PAD_BOTTOM = 4,           -- margin below the last row

    -- Floor of the size. The real limit comes from the content (ApplyMinSize), and the
    -- larger of the two applies. The Window class keeps the window at least 92 px wide, the
    -- close button plus two 36 px corner pieces, and 48 px high, the 36 + 12 px frame
    -- pieces.
    MIN_W = 100,
    MIN_H = 52,

    -- Window frame, which the class takes from the window: 5 px at the sides, 8 px at the
    -- bottom. Needed to compute the room left for the text.
    CLIENT_PAD_X = 5,
    FRAME_BOTTOM = 8,

    -- Right margin, twice the left one: at the smallest size the text would touch the
    -- frame. It is part of the width limit, so the window is wider than the text by this
    -- much.
    RIGHT_PAD = 20,

    -- Default font size, used when themes.lua gives none.
    FONT       = 11,

    DEFAULT_LEFT = 8,
    DEFAULT_TOP  = 80,

    -- Profile key of the window: the class stores its position and size there. No dots:
    -- GetFromCurrentProfile reads the string as a path.
    PANEL_KEY = 'OverflowPanel',

    -- Profile key of the collapsed state.
    COLLAPSE_KEY = 'OverflowCollapsed',

    -- Alarm threshold: share of overflow in own production. 20% is already a visible
    -- dependence on an ally.
    WARN_RATIO = 0.2,
}

-- Frame made of the minimap textures. The Window class takes this table as its last
-- argument. UIFile resolves into the skin folder, so the frame takes the faction colour by
-- itself.
local function WindowBrd()
    local brd = {}
    brd.tl = UIUtil.UIFile('/game/mini-map-brd/mini-map_brd_ul.dds')
    brd.tr = UIUtil.UIFile('/game/mini-map-brd/mini-map_brd_ur.dds')
    brd.tm = UIUtil.UIFile('/game/mini-map-brd/mini-map_brd_horz_um.dds')
    brd.ml = UIUtil.UIFile('/game/mini-map-brd/mini-map_brd_vert_l.dds')
    brd.m  = UIUtil.UIFile('/game/mini-map-brd/mini-map_brd_m.dds')
    brd.mr = UIUtil.UIFile('/game/mini-map-brd/mini-map_brd_vert_r.dds')
    brd.bl = UIUtil.UIFile('/game/mini-map-brd/mini-map_brd_ll.dds')
    brd.bm = UIUtil.UIFile('/game/mini-map-brd/mini-map_brd_lm.dds')
    brd.br = UIUtil.UIFile('/game/mini-map-brd/mini-map_brd_lr.dds')

    -- Colour of the grab strips the class shows when the mouse is over a window edge. The
    -- game value 'ff415055' reads as a grey patch over this frame. Transparent strips stay
    -- clickable and the cursor still changes.
    brd.borderColor = '00000000'
    return brd
end

local C = {
    -- BG does not paint the frame, it is only the default of the reopen button colour.
    BG      = 'E6101418',
    DIVIDER = 'FF405060',
    TITLE   = 'FF8FD0FF',
    SAFE    = 'FF5CE07A',
    WARN    = 'FFFFD24A',
    BAD     = 'FFEF5350',
    NEUTRAL = 'FF8A96A3',
    TOTAL   = 'FFFFD24A',
    CLOSED  = 'FF1E2A34',
}

--------------------------------------------------------------------------------
-- Applying the theme
--
-- C holds the current theme, its fields are overwritten in place. `or C.*` keeps the
-- previous value if a theme is incomplete: a panel with a nil colour is not drawn at all.
--------------------------------------------------------------------------------

local function ApplyTheme()
    if not ThemeColors then
        return false
    end

    local ok, pal = pcall(ThemeColors)
    if not ok or type(pal) ~= 'table' then
        LOG('Overflow: theme FAILED, keeping previous colours: ' ..
            tostring(pal))
        return false
    end

    C.BG      = pal.BG      or C.BG
    C.CLOSED  = pal.CLOSED  or C.CLOSED
    C.DIVIDER = pal.DIVIDER or C.DIVIDER
    C.TITLE   = pal.TITLE   or C.TITLE
    C.TOTAL   = pal.TOTAL   or C.TOTAL
    C.NEUTRAL = pal.NEUTRAL or C.NEUTRAL
    C.SAFE    = pal.SAFE    or C.SAFE
    C.WARN    = pal.WARN    or C.WARN
    C.BAD     = pal.BAD     or C.BAD

    return true
end

-- Signature of the current look. Update() rebuilds the panel when it changes.
local function ThemeSignatureNow()
    if not ThemeSign then
        return nil
    end
    local ok, sig = pcall(ThemeSign)
    if not ok then
        return nil
    end
    return sig
end

--------------------------------------------------------------------------------
-- Rows and their order
--
-- Keys and titles live in rows.lua, only the order and the dividers are here. ROW_ORDER has
-- to match rows.lua, or the check box "M to allies" would hide the row "E to allies". A
-- divider is drawn only if a visible row is above it.
--
-- These tables are declared before ApplyLayout because it captures them as upvalues:
-- further down they would resolve as globals, and reading a missing global fails.
--------------------------------------------------------------------------------

local ROW_ORDER   = { 'eOverflow', 'eGo', 'eOwn', 'mOverflow', 'mGo',
                      'mOwn', 'total' }

-- which divider goes before which row
local ROW_DIVIDER = { mOverflow = 'divider1', total = 'divider2' }

-- размер шрифта каждой строки. Строки перелива крупнее: их читают чаще.
local ROW_FONT = {
    eOverflow = 12,
    eGo       = 11,
    eOwn      = 11,
    mOverflow = 12,
    mGo       = 11,
    mOwn      = 11,
    total     = 11,
}

-- Everything in the panel body. LayoutRows hides what is switched off, so the list needs
-- every row.
local BODY_KEYS = { 'eOverflow', 'eGo', 'eOwn', 'divider1',
                    'mOverflow', 'mGo', 'mOwn', 'divider2', 'total' }

--------------------------------------------------------------------------------
-- State, all of it in one table: see the header
--------------------------------------------------------------------------------

local G = {
    ---@type Window?
    win       = nil,        -- game window (class Window)
    reopenButton = nil,     -- button that brings a collapsed panel back
    labels    = {},
    collapsed = false,
    beatErrors = 0,         -- Update errors in a row

    -- Signature of the row set the panel is built for, see Update().
    rowsSig   = nil,
    themeSig  = nil,

    -- Blinking of the alarm row. blinkWanted is the choice of the player, blinkOn the
    -- current phase, blinkRun the number of blinks so far. They are kept apart: with
    -- blinking off, blinkOn alone would still flip and the row would light up dimmed.
    blinkWanted = false,
    blinkRun  = 0,
    blinkOn   = false,

    -- Height the player chose by dragging the edge. From then on fitting to the content can
    -- only grow the window, never cut it.
    wantH     = nil,

    -- Background of the Minimal frame: two Bitmaps, because the line built into the texture
    -- has to be skipped, see FRAME_LINE_TOP. They live in GetFrame(0), not in the window,
    -- so a rebuild and a collapse handle them by hand.
    frameBg   = nil,

    -- Visible rows taken in LayoutRows, so that ApplyMinSize does not read the profile
    -- again.
    visSet    = nil,

    -- Last layout of the body: items with natural coordinates, their count and the natural
    -- height. PlaceRows needs them on a resize.
    bodyItems = nil,
    bodyCount = 0,
    bodyH     = 0,
}

--------------------------------------------------------------------------------
-- Background of the Minimal frame
--
-- The frame is a game texture, filter-ping-panel02_bmp.dds, 180x72: the first 4 px are
-- transparent, then a thin outline and a black field with alpha 54. A flat fill cannot give
-- this: the nine window pieces are 12-36 px thick. So in Minimal the pieces are blanked and
-- a Bitmap draws the background. The texture stretches over the window, so its outline
-- grows with it.
--
-- The texture has its own dividing line at row 35 of 72, across the full width, the same in
-- all four skins. Stretched over the window it would hang in the empty middle, so the
-- background is two pieces cut by SetUV that skip it: rows 0-34 and 36-71. The seam is at
-- the middle of the window, where the field is even, and does not show.
--
-- window_* are fields of the class, so blanking goes under pcall with a log line: if the
-- class renames them, the panel keeps the game frame.
--------------------------------------------------------------------------------
local WINDOW_PARTS = {
    'window_tl', 'window_tr', 'window_tm',
    'window_ml', 'window_m',  'window_mr',
    'window_bl', 'window_bm', 'window_br',
}

-- UIFile resolves into the skin folder, so the background follows the faction.
local FRAME_BG_TEXTURE =
    '/game/filter-ping-panel/filter-ping-panel02_bmp.dds'

-- Position of the built-in line as a share of the texture height: SetUV works in shares.
-- Measured on the unpacked file in all four skins.
local FRAME_LINE_TOP    = 35 / 72
local FRAME_LINE_BOTTOM = 36 / 72

--------------------------------------------------------------------------------
-- The background lives in GetFrame(0), not in the window, so collapsing hides it
-- separately.
--------------------------------------------------------------------------------
local function ShowFrameBg(show)
    if not G.frameBg then return end
    for i = 1, TableGetn(G.frameBg) do
        if show then
            G.frameBg[i]:Show()
        else
            G.frameBg[i]:Hide()
        end
    end
end

local function ApplyFrameBackground(win)
    -- The old background hangs on GetFrame(0) and does not die with the window.
    if G.frameBg then
        for i = 1, TableGetn(G.frameBg) do
            G.frameBg[i]:Destroy()
        end
        G.frameBg = nil
    end

    if not ThemeMinimal then
        return
    end
    local okMin, wantMin = pcall(ThemeMinimal)
    if not okMin or not wantMin then
        return
    end

    local ok, miss = pcall(function()
        for i = 1, TableGetn(WINDOW_PARTS) do
            local piece = win[WINDOW_PARTS[i]]
            if not piece then
                return WINDOW_PARTS[i]
            end
            piece:SetSolidColor('00000000')
        end
        return nil
    end)
    if not ok then
        LOG('Overflow: minimal frame FAILED: ' .. tostring(miss))
    elseif miss then
        LOG('Overflow: minimal frame incomplete, no field ' .. miss)
    end

    -- Middle of the window, where the pieces meet. It comes from the window, not from
    -- ClientGroup: the background covers the whole frame.
    local function midY()
        return win.Top() + (win.Bottom() - win.Top()) / 2
    end

    local function MakePiece(vFrom, vTo)
        local piece = Bitmap(GetFrame(0))
        -- One below the window, which is always at depth 20 (CreatePanel).
        piece.Depth:Set(19)
        -- SetUV cuts the assigned texture, so it follows SetTexture.
        piece:SetTexture(UIUtil.UIFile(FRAME_BG_TEXTURE))
        piece:SetUV(0, vFrom, 1, vTo)
        piece:DisableHitTest()
        -- The player resizes the window, so the sides are functions and not numbers.
        piece.Left:Set(function() return win.Left() end)
        piece.Width:Set(function() return win.Right() - win.Left() end)
        return piece
    end

    local okBg, errBg = pcall(function()
        local top = MakePiece(0, FRAME_LINE_TOP)
        top.Top:Set(function() return win.Top() end)
        top.Height:Set(function() return midY() - win.Top() end)

        local bot = MakePiece(FRAME_LINE_BOTTOM, 1)
        bot.Top:Set(midY)
        bot.Height:Set(function() return win.Bottom() - midY() end)

        G.frameBg = {}
        G.frameBg[1] = top
        G.frameBg[2] = bot
    end)
    if not okBg then
        -- Without the background the game frame shows, and the panel keeps working.
        LOG('Overflow: minimal frame background FAILED: ' .. tostring(errBg))
    end
end

--------------------------------------------------------------------------------
-- Visible rows. Without rows.lua everything is shown: an empty set would look like a broken
-- mod.
--------------------------------------------------------------------------------

local function VisibleSet()
    if RowsVisible then
        return RowsVisible()
    end
    local out = {}
    out.eOverflow = true
    out.eGo       = true
    out.eOwn      = true
    out.mOverflow = true
    out.mGo       = true
    out.mOwn      = true
    out.total     = true
    return out
end


local function Num(v)
    if v == nil then return '0' end
    if v >= 1000 then return StringFormat('%.0f', v) end
    return StringFormat('%.1f', v)
end


local function MakeLabel(parent, textSize, color)
    local label = UIUtil.CreateText(parent, '', textSize, UIUtil.bodyFont)
    label:SetColor(color)
    label:SetDropShadow(true)
    label:DisableHitTest(true)
    return label
end

local function MakeDivider(parent)
    local bar = Bitmap(parent)
    bar.Depth:Set(20)
    bar:SetSolidColor(C.DIVIDER)
    bar:DisableHitTest(true)
    return bar
end

--------------------------------------------------------------------------------
-- Layout of the body by visible rows
--
-- Returns the items to show (with Y from the top of the window and a divider flag), their
-- count and the pixels the body needs.
--------------------------------------------------------------------------------

local function ComputeBody(vis)
    local items = {}
    local howMany = 0
    local y = L.PAD_TOP
    local anyAbove = false

    for i = 1, TableGetn(ROW_ORDER) do
        local rowKey = ROW_ORDER[i]
        if vis[rowKey] then
            local div = ROW_DIVIDER[rowKey]
            if div and anyAbove then
                howMany = howMany + 1
                items[howMany] = { id = div, divider = true, y = y + L.DIV_PRE }
                y = y + L.DIV_PRE + L.DIV_POST
            end
            howMany = howMany + 1
            items[howMany] = { id = rowKey, divider = false, y = y }
            y = y + L.ROW_STEP
            anyAbove = true
        end
    end

    local bodyH = 0
    if howMany > 0 then
        -- y has already moved one step past the last row: its top is y minus
        -- the step, and the window has to hold the whole row below that top.
        bodyH = (y - L.ROW_STEP) + L.ROW_H + L.PAD_BOTTOM
    end

    return items, howMany, bodyH
end

--------------------------------------------------------------------------------
-- Right inset of a row
--
-- The close button hangs in the top right corner and the rows pass under it: there is no
-- empty title strip (CreatePanel). Only a row that crosses the button steps aside, and the
-- inset comes from the real button position, which differs between skins.
--------------------------------------------------------------------------------
local function RowRightInset(top)
    -- The Window constructor sets _closeBtn, but the class annotations do not
    -- declare it.
    ---@diagnostic disable-next-line: undefined-field
    if not G.win or not G.win._closeBtn then return L.RIGHT_PAD end
    local ok, inset = pcall(function()
        local client = G.win.ClientGroup
        ---@diagnostic disable-next-line: undefined-field
        local btn = G.win._closeBtn
        -- The window is in screen pixels, the rows in own units: see ApplyMinSize.
        local btnTop = LayoutHelpers.InvScaleNumber(btn.Top() - client.Top())
        local btnBottom = LayoutHelpers.InvScaleNumber(btn.Bottom() - client.Top())
        if top >= btnBottom or (top + L.ROW_H) <= btnTop then
            return L.RIGHT_PAD
        end
        local over = LayoutHelpers.InvScaleNumber(client.Right() - btn.Left()) + L.RIGHT_PAD
        if over > L.RIGHT_PAD then return over end
        return L.RIGHT_PAD
    end)
    if ok and type(inset) == 'number' then return inset end
    return L.RIGHT_PAD
end

--------------------------------------------------------------------------------
-- Width of a row in pixels, measured because letters differ in width. Under pcall: without
-- GetStringAdvance the width is 0 and the limit stays L.MIN_W.
--------------------------------------------------------------------------------
local function RowTextWidth(ctl)
    if not ctl then return 0 end
    local ok, w = pcall(function()
        return ctl:GetStringAdvance(ctl:GetText())
    end)
    if ok and type(w) == 'number' and w > 0 then return w end
    return 0
end

--------------------------------------------------------------------------------
-- Size limit of the window by content
--
-- The Window class knows nothing about the content. So the width comes from the longest
-- visible row with its margins and the height from the number of visible rows plus the
-- bottom frame: the window cannot shrink below its text.
--------------------------------------------------------------------------------
local function ApplyMinSize()
    if not G.win then return end
    local vis = G.visSet
    if not vis then return end
    local items, howMany, bodyH = ComputeBody(vis)

    local widest = 0
    for i = 1, howMany do
        local it = items[i]
        if not it.divider then
            -- RowTextWidth gives screen pixels, while SetMinimumResize multiplies its
            -- numbers by the interface scale. So the width goes to own units, otherwise at
            -- scale 2 the window would be twice as wide as needed.
            local need = LayoutHelpers.InvScaleNumber(
                RowTextWidth(G.labels[it.id])) + L.PAD
                + RowRightInset(it.y)
            if need > widest then widest = need end
        end
    end

    local minW = widest + L.CLIENT_PAD_X * 2
    if minW < L.MIN_W then minW = L.MIN_W end

    local minH = bodyH + L.FRAME_BOTTOM
    if minH < L.MIN_H then minH = L.MIN_H end

    -- The only call into the class here, it must not break the drawing pass.
    pcall(function()
        G.win:SetMinimumResize(minW, minH)
    end)

    -- SetMinimumResize limits only the drag of the player. An already smaller window (more
    -- rows, a larger font) has to grow by itself, and only up to the limit: otherwise a
    -- window the player stretched would jump back on every pass. The limit is in own units
    -- and the window sides in screen pixels, hence ScaleNumber.
    pcall(function()
        local wantW = LayoutHelpers.ScaleNumber(minW)
        local wantH = LayoutHelpers.ScaleNumber(minH)
        if G.win.Right() - G.win.Left() < wantW then
            G.win.Right:Set(G.win.Left() + wantW)
        end
        if G.win.Bottom() - G.win.Top() < wantH then
            G.win.Bottom:Set(G.win.Top() + wantH)
        end
    end)
end

--------------------------------------------------------------------------------
-- Placing the rows in the window
--
-- Separate from LayoutRows because a resize calls it too, and the set of rows does not
-- change then. Rows spread over the height: the gaps grow until the body fills the panel,
-- the font does not grow. The gaps come from the remaining room, so the last row always
-- lands on the bottom margin.
--------------------------------------------------------------------------------
local function PlaceRows()
    if not G.win or not G.bodyItems then return end
    local client = G.win.ClientGroup

    -- The room is read from the client area in screen pixels and converted to own units to
    -- compare it with bodyH: at interface scale 2 they differ twice.
    -- The content runs from PAD_TOP to the bottom of the last row, bodyH holds
    -- that span together with both margins (ComputeBody).
    local gap = 0
    local n = G.bodyCount
    if n > 1 then
        local room = LayoutHelpers.InvScaleNumber(client.Bottom() - client.Top())
        local extra = room - G.bodyH
        if extra > 0 then
            gap = extra / (n - 1)
        end
    end

    for i = 1, n do
        local it = G.bodyItems[i]
        local ctl = G.labels[it.id]
        if ctl then
            -- One gap for each item above. The first row stays on PAD_TOP, the last lands
            -- on the bottom margin.
            local top = it.y + (i - 1) * gap
            if it.divider then
                -- A divider needs Top too: with only Height, Left and Right set, reading
                -- Top() overflows the stack, because control geometry is circular.
                -- ScaleNumber rounds down: at ui_scale 0.8 one pixel becomes zero.
                ctl.Height:Set(MathMax(1, LayoutHelpers.ScaleNumber(L.DIV_H)))
                LayoutHelpers.AtLeftIn(ctl, client, 0)
                LayoutHelpers.AtRightIn(ctl, client, 0)
                LayoutHelpers.AtTopIn(ctl, client, top)
            else
                ctl.Height:Set(LayoutHelpers.ScaleNumber(L.ROW_H))
                LayoutHelpers.AtLeftTopIn(ctl, client, L.PAD, top)
                -- The inset uses the stretched coordinate: the close button stays in the
                -- corner, and a row moves out from under it.
                LayoutHelpers.AtRightIn(ctl, client, RowRightInset(top))
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Building the layout. This decides what is shown and in which order, PlaceRows decides
-- where, because a resize changes only the latter.
--------------------------------------------------------------------------------

local function LayoutRows()
    if not G.win then return 0 end

    local client = G.win.ClientGroup
    -- Kept for ApplyMinSize, so that it does not read the profile again.
    local vis = VisibleSet()
    G.visSet = vis
    local items, howMany, bodyH = ComputeBody(vis)

    -- What stays on the screen.
    local want = {}
    for i = 1, howMany do
        want[items[i].id] = true
    end

    -- Hide what is switched off: the class knows nothing about the rows.
    local many = TableGetn(BODY_KEYS)
    for i = 1, many do
        local ctl = G.labels[BODY_KEYS[i]]
        if ctl then
            if want[BODY_KEYS[i]] then
                ctl:Show()
            else
                ctl:Hide()
            end
        end
    end

    -- Remembered: a resize only needs PlaceRows.
    G.bodyItems = items
    G.bodyCount = howMany
    G.bodyH = bodyH
    PlaceRows()

    -- The limit is set here too: after a change of the set the window has to meet it at
    -- once, not on the next beat.
    ApplyMinSize()

    return howMany
end

--------------------------------------------------------------------------------
-- Window height by content
--
-- It is set only when the window is created and when the set of rows changes. Otherwise the
-- size the player chose would go back on the first mouse move. The width belongs to the
-- player. The title strip takes nothing (CreatePanel), the bottom frame takes 8 px.
--------------------------------------------------------------------------------

-- The height of a Window is set through Bottom: the class sets Left, Top, Right and Bottom,
-- and Height follows from them. After Height:Set() the control keeps both values and Height
-- stops following Bottom.
local function SetWindowHeight(want)
    G.win.Bottom:Set(G.win.Top() + want)
end

local function FitHeight(bodyH)
    if not G.win then return end
    local want = bodyH + L.FRAME_BOTTOM
    if want < L.MIN_H then want = L.MIN_H end
    -- The height of the window and G.wantH are in screen pixels.
    want = LayoutHelpers.ScaleNumber(want)
    -- The choice of the player wins: the height is not cut, the window can only grow.
    if G.wantH and G.wantH > want then want = G.wantH end
    SetWindowHeight(want)
end

-- On a move the class overwrites Right and Bottom with values taken at ButtonPress, so the
-- height is set again after each step.
-- The rows may have outgrown the height the player chose, so the height comes
-- from FitHeight and not from G.wantH alone.
local function KeepHeight()
    if G.wantH then
        FitHeight(G.bodyH)
    end
end

local function ApplyLayout(refitHeight)
    if not G.win then return end
    local vis = VisibleSet()
    local _, howMany, bodyH = ComputeBody(vis)
    LayoutRows()
    if refitHeight then
        FitHeight(bodyH)

        -- The height changed after the layout, and the row positions depend on it.
        PlaceRows()
    end
    if howMany == 0 then
        LOG('Overflow: no visible rows, window shrunk to the frame')
    end
end

--------------------------------------------------------------------------------
-- Collapsing works like the minimap: the close button hides the window and the state goes
-- to the profile. The panel returns through its own button.
--------------------------------------------------------------------------------

local function CollapseKeyRead()
    local ok, v = pcall(function()
        return Prefs.GetFromCurrentProfile(L.COLLAPSE_KEY)
    end)
    if not ok then
        return false
    end
    return v and true or false
end

local function CollapseKeyWrite(collapsed)
    local ok, err = pcall(function()
        Prefs.SetToCurrentProfile(L.COLLAPSE_KEY, collapsed and true or false)
    end)
    if not ok then
        LOG('Overflow: collapse state FAILED: ' .. tostring(err))
    end
end

local function SetCollapsed(collapsed)
    if not G.win then return end
    G.collapsed = collapsed and true or false

    if collapsed then
        G.win:Hide()
        -- The background lives in GetFrame(0), and G.win:Hide() does not reach it.
        ShowFrameBg(false)
        if G.reopenButton then
            -- Under pcall because control geometry is circular: if the read fails, the
            -- button stays where it is and the drawing pass survives.
            pcall(function()
                LayoutHelpers.AtLeftTopIn(G.reopenButton, GetFrame(0),
                                          LayoutHelpers.InvScaleNumber(G.win.Left()),
                                          LayoutHelpers.InvScaleNumber(G.win.Top()))
            end)
            G.reopenButton:Show()
        end
        CollapseKeyWrite(true)
        return
    end

    if G.reopenButton then
        G.reopenButton:Hide()
    end
    G.win:Show()
    ShowFrameBg(true)
    CollapseKeyWrite(false)
end

local NumbersOnlyOn = false

local function ReloadNumbersOnly()
    NumbersOnlyOn = false
    if not ThemeNumbers then
        return
    end
    local ok, res = pcall(ThemeNumbers)
    if ok and res then
        NumbersOnlyOn = true
    end
end

-- Text of a row: "E ally overflow: 1.2 E/s", or just "1.2" with numbers only.
local function RowText(caption, amount, unit)
    if NumbersOnlyOn then
        return Num(amount)
    end
    return StringFormat('%s: %s %s/s', caption, Num(amount), unit)
end

--------------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------------

CreatePanel = function()
    if G.win then
        pcall(function() G.win:Destroy() end)
        G.win = nil
    end
    if G.reopenButton then
        pcall(function() G.reopenButton:Destroy() end)
        G.reopenButton = nil
    end

    -- G.labels holds the controls the layout manages, they are recreated.
    G.labels = {}
    G.rowsSig = nil
    G.themeSig = nil

    -- The theme comes first: controls take their colours from C in the constructor.
    ApplyTheme()
    G.themeSig = ThemeSignatureNow()
    G.blinkRun = 0
    G.blinkOn = false
    G.blinkWanted = false
    if ThemeBlink then
        local okBlink, resBlink = pcall(ThemeBlink)
        if okBlink and resBlink then
            G.blinkWanted = true
        end
    end

    local frame = GetFrame(0)

    -- The class reads and writes the position and size in the profile and keeps the window
    -- on the screen, the defaults are only for the first start. The title is nil on
    -- purpose, the title group stays: it is the drag area.
    local win = Window(frame, nil, nil, false, false, false, false,
                       L.PANEL_KEY,
                       { Left = L.DEFAULT_LEFT, Top = L.DEFAULT_TOP,
                         Right = L.DEFAULT_LEFT + L.DEFAULT_W,
                         Bottom = L.DEFAULT_TOP + L.DEFAULT_H },
                       WindowBrd())
    G.win = win
    win.Depth:Set(20)
    ApplyFrameBackground(win)
    win:SetMinimumResize(L.MIN_W, L.MIN_H)
    win:DisableHitTest()

    -- Rows spread over the height (PlaceRows), so dragging an edge has to place them again.
    -- The class calls OnResize after it has set the new size. LayoutRows is not needed: it
    -- rereads the profile and the visibility, and neither changes here.
    win.OnResize = function()
        PlaceRows()
    end

    -- The player chose the height: fitting to the content no longer cuts it. The class
    -- calls OnResizeSet when the drag ends.
    win.OnResizeSet = function()
        -- Bottom and Top, because Height is derived: see SetWindowHeight.
        G.wantH = win.Bottom() - win.Top()
        LOG('Overflow: player height ' .. tostring(G.wantH))
    end

    -- A move must not change the size, see KeepHeight.
    win.OnMove = function()
        KeepHeight()
    end
    win.OnMoveSet = function()
        KeepHeight()
    end

    -- The close button collapses the panel, as on the minimap.
    win.OnClose = function()
        SetCollapsed(true)
    end

    local client = win.ClientGroup

    -- The class always reserves a 30 px title strip, even without a title, and puts the
    -- client area below it. In a 52 px window that leaves no room, so the rows start from
    -- the top of the window.
    client.Top:Set(win.Top)

    -- The strip is transparent and dragging hangs only on it, so it stretches over the
    -- whole window above the content. The close button lies inside it and stays above it,
    -- so a click on the button still closes the panel.
    win.TitleGroup.Height:Set(function() return win.Bottom() - win.Top() end)
    win.TitleGroup.Depth:Set(function() return client.Depth() + 1 end)

    -- The font size comes from the style and the scale of the player. Without themes.lua
    -- L.FONT stays.
    local fontSize = L.FONT
    if ThemeFont then
        local okFont, resFont = pcall(ThemeFont)
        if okFont and type(resFont) == 'number' and resFont > 0 then
            fontSize = resFont
        end
    end

    -- data rows
    G.labels.eOverflow = MakeLabel(client, fontSize, C.NEUTRAL)
    G.labels.eGo       = MakeLabel(client, fontSize, C.NEUTRAL)
    G.labels.eOwn      = MakeLabel(client, fontSize, C.NEUTRAL)
    G.labels.divider1  = MakeDivider(client)
    G.labels.mOverflow = MakeLabel(client, fontSize, C.NEUTRAL)
    G.labels.mGo       = MakeLabel(client, fontSize, C.NEUTRAL)
    G.labels.mOwn      = MakeLabel(client, fontSize, C.NEUTRAL)
    G.labels.divider2  = MakeDivider(client)
    G.labels.total     = MakeLabel(client, fontSize, C.TOTAL)

    ReloadNumbersOnly()

    -- all geometry in one call, true fits the height
    ApplyLayout(true)

    -- button that brings a collapsed panel back
    G.reopenButton = Bitmap(frame)
    G.reopenButton.Depth:Set(21)
    G.reopenButton:SetSolidColor(C.CLOSED)
    G.reopenButton:EnableHitTest(true)
    LayoutHelpers.SetDimensions(G.reopenButton, 120, 20)
    pcall(function()
        LayoutHelpers.AtLeftTopIn(G.reopenButton, frame,
                                  LayoutHelpers.InvScaleNumber(win.Left()),
                                  LayoutHelpers.InvScaleNumber(win.Top()))
    end)
    G.reopenButton.HandleEvent = function(self, event)
        if event.Type == 'ButtonRelease' then
            SetCollapsed(false)
            return true
        end
        return false
    end
    local rbLabel = UIUtil.CreateText(G.reopenButton, 'Overflow',
                                      fontSize, UIUtil.bodyFont)
    rbLabel:SetColor(C.TITLE)
    rbLabel:SetDropShadow(true)
    rbLabel:DisableHitTest(true)
    LayoutHelpers.AtLeftTopIn(rbLabel, G.reopenButton, 6, 2)
    G.reopenButton:Hide()

    -- The collapsed state carries over between matches, as on the minimap.
    G.collapsed = false
    if CollapseKeyRead() then
        SetCollapsed(true)
    end

    local themeSay = 'built-in colours'
    if ThemeTellIt then
        local okTell, resTell = pcall(ThemeTellIt)
        if okTell and resTell then
            themeSay = resTell
        end
    end
    LOG('Overflow: window created, theme ' .. themeSay ..
        ', collapsed=' .. tostring(G.collapsed))

    -- Row sizes go to the log once. Under pcall: Left, Top, Right, Bottom, Width and Height
    -- depend on each other by default, and reading an incomplete control overflows the
    -- stack. Diagnostics must not break what they measure.
    pcall(function()
        local many = TableGetn(BODY_KEYS)
        for i = 1, many do
            local rowId = BODY_KEYS[i]
            local ctl = G.labels[rowId]
            if ctl and not ctl._hidden then
                -- Each row has its own pcall, so that one bad row does not eat the rest.
                local okRead, l, tp, w, h = pcall(function()
                    return ctl.Left(), ctl.Top(), ctl.Width(), ctl.Height()
                end)
                if okRead then
                    LOG('Overflow: row ' .. rowId ..
                        ' L=' .. tostring(l) .. ' T=' .. tostring(tp) ..
                        ' W=' .. tostring(w) .. ' H=' .. tostring(h))
                else
                    LOG('Overflow: row ' .. rowId .. ' geometry unreadable')
                end
            end
        end
        LOG('Overflow: window L=' .. tostring(win.Left()) ..
            ' T=' .. tostring(win.Top()) ..
            ' W=' .. tostring(win.Width()) ..
            ' H=' .. tostring(win.Bottom() - win.Top()))
    end)
end

--------------------------------------------------------------------------------
-- Colour by state. Good means independent of allies.
--
--   green   overflow = 0
--   yellow  overflow > 0, not above the threshold of own production
--   red     overflow above the threshold
--
-- The zero check comes first: with no overflow and no own production, shown <= 0.2 * own
-- holds (0 <= 0) and would give yellow instead of green.
--
-- Blinking follows the game resource panel: a dark grey phase against the normal colour,
-- one flag for all rows, and it stops by itself after BlinkLimit calls, or the panel would
-- blink through the whole match.
--------------------------------------------------------------------------------

local BlinkDim   = 'ff404040'
local BlinkLimit = 100

local function StatusColor(shown, own)
    local col
    if shown <= 0 then
        col = C.SAFE
    elseif shown <= L.WARN_RATIO * own then
        col = C.WARN
    else
        col = C.BAD
        -- Blinks only on request and only in the alarm state. The counter counts calls, not
        -- seconds: energy and mass add two per pass.
        if G.blinkOn then
            G.blinkRun = G.blinkRun + 1
            if G.blinkRun > BlinkLimit then
                G.blinkOn = false
            end
        end
    end
    if G.blinkOn and col == C.BAD then
        return BlinkDim
    end
    return col
end

-- Colours and fills the three rows of a resource: what came from allies, what we gave, what
-- we produced. All three take their colour from the share of incoming overflow in own
-- production.
local function SetTriple(overLabel, goLabel, ownLabel, overText, goText,
                         ownText, incoming, outgoing, own, unit)
    local color = StatusColor(incoming, own)
    overLabel:SetColor(color)
    goLabel:SetColor(color)
    ownLabel:SetColor(color)
    overLabel:SetText(RowText(overText, incoming, unit))
    goLabel:SetText(RowText(goText, outgoing, unit))
    ownLabel:SetText(RowText(ownText, own, unit))
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

local function Render(d)
    -- Energy and mass apart: their overflow can go opposite ways, and one colour would
    -- paint the healthy row too.
    SetTriple(G.labels.eOverflow, G.labels.eGo, G.labels.eOwn,
              'E ally overflow', 'E to allies', 'E own production',
              d.incoming, d.outgoing, d.own, 'E')

    SetTriple(G.labels.mOverflow, G.labels.mGo, G.labels.mOwn,
              'M ally overflow', 'M to allies', 'M own production',
              d.massIncoming, d.massOutgoing, d.massOwn, 'M')

    -- The bottom row is always about reclaim, so the panel keeps its look.
    if NumbersOnlyOn then
        G.labels.total:SetText(Num(d.reclaim) .. ' / ' .. Num(d.massReclaim))
    else
        G.labels.total:SetText(StringFormat('reclaim E %s / M %s /s',
            Num(d.reclaim), Num(d.massReclaim)))
    end
end

--------------------------------------------------------------------------------
-- Update
--------------------------------------------------------------------------------

local function Update()
    -- sync.lua computes everything, this function only takes the result and draws.
    local d = SyncResult()

    if G.win == nil then return end

    -- The settings page writes to the profile, and the panel notices here. Unlike rows, the
    -- look needs a rebuild: colours are set in the constructors of the controls. Under
    -- pcall, because this runs inside a beat.
    if ThemeSign then
        local sig = ThemeSignatureNow()
        if sig ~= nil and sig ~= G.themeSig then
            -- The reason goes to the log: a rebuild loses the height the player chose, and
            -- a rebuild without a change of theme means a bug.
            LOG('Overflow: theme REBUILD ' .. tostring(G.themeSig) ..
                ' -> ' .. tostring(sig))
            local okRebuild, errRebuild = pcall(CreatePanel)
            if okRebuild then
                LOG('Overflow: theme applied: ' .. ThemeTellIt())
            else
                LOG('Overflow: theme rebuild FAILED: ' .. tostring(errRebuild))
            end
            return
        end
    end

    -- The blink phase flips here, once per pass: StatusColor runs twice per pass.
    if G.blinkWanted and G.blinkRun <= BlinkLimit then
        G.blinkOn = not G.blinkOn
    end

    -- The same for the rows: the signature is compared instead of moving the geometry every
    -- beat.
    if RowsVisible then
        local vis = RowsVisible()
        local sig = RowsSign(vis)
        if sig ~= G.rowsSig then
            G.rowsSig = sig
            ApplyLayout(true)
            LOG('Overflow: rows applied: ' .. RowsTell(vis))
        end
    end

    if d == nil then return end

    -- observer: no army of its own, nothing to show
    if d.observer then
        if not G.collapsed then
            G.labels.eOverflow:SetColor(C.NEUTRAL)
            G.labels.mOverflow:SetColor(C.NEUTRAL)
            G.labels.eGo:SetColor(C.NEUTRAL)
            G.labels.mGo:SetColor(C.NEUTRAL)
            G.labels.eOverflow:SetText('E ally overflow: n/a')
            G.labels.eGo:SetText('E to allies: n/a')
            G.labels.eOwn:SetText('E own production: n/a')
            G.labels.mOverflow:SetText('M ally overflow: n/a')
            G.labels.mGo:SetText('M to allies: n/a')
            G.labels.mOwn:SetText('M own production: n/a')
            if NumbersOnlyOn then
                G.labels.total:SetText('-')
            else
                G.labels.total:SetText('observer mode')
            end
        end
        ApplyMinSize()
        return
    end

    if not d.ok then return end
    if not G.collapsed then
        Render(d)
    end

    -- The limit is recalculated on each pass: new numbers change the width of the longest
    -- row.
    ApplyMinSize()
end

local BEAT_ERROR_LIMIT = 3

-- The game calls beat functions without pcall, so an error would repeat on every
-- beat and stop the functions registered after this one.
local function SafeUpdate()
    local ok, err = pcall(Update)
    if ok then
        G.beatErrors = 0
        return
    end
    G.beatErrors = G.beatErrors + 1
    LOG('Overflow: Update FAILED (' .. tostring(G.beatErrors) .. '/' ..
        tostring(BEAT_ERROR_LIMIT) .. '): ' .. tostring(err))
    if G.beatErrors >= BEAT_ERROR_LIMIT then
        pcall(GameMain.RemoveBeatFunction, SafeUpdate, 'Overflow')
        LOG('Overflow: too many errors, panel stopped updating')
    end
end

--------------------------------------------------------------------------------
-- Entry point
--------------------------------------------------------------------------------

function OnCreateUI()
    ForkThread(function()
        WaitSeconds(1)

        -- The wait stays outside pcall: WaitSeconds cannot yield through a C function. The
        -- interface is built already, the second lets it finish.
        local ok, err = pcall(function()
            CreatePanel()
        end)
        if not ok then
            LOG('Overflow: init FAILED: ' .. tostring(err))
            return
        end

        -- sync.lua itself drops the first ticks of a match: the sim is not ready then and
        -- both armies show equal numbers.
        if type(SyncStart) ~= 'function' then
            LOG('Overflow: FATAL - sync.lua exported no Start. Panel stays empty.')
            return
        end
        local ok2, err2 = pcall(SyncStart)
        if not ok2 then
            LOG('Overflow: sync start FAILED: ' .. tostring(err2))
            return
        end

        -- The beat only redraws the panel. Data comes about every 2 s, so the throttled
        -- beat is enough.
        local ok3, err3 = pcall(function()
            GameMain.AddBeatFunction(SafeUpdate, true, 'Overflow')
        end)
        if not ok3 then
            LOG('Overflow: beat FAILED: ' .. tostring(err3))
        end
    end)
end