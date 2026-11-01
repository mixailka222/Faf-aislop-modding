-- Tests of Overflow: themes and the blinking of the alarm row.
--
-- Run from the tests folder: lua test_overflow_theme.lua. The paths below are relative to
-- it. check.py does that with the Lua of the game, so this code follows its dialect.
--
-- themes.lua: frames and presets, their names and the rule for the default. The defaults
-- themselves are up to the mod, so the tests do not pin them.
--
-- Reading from the game skin: faction themes have to take their values from skins.lua, not
-- from numbers of their own, otherwise a typo in a hex value would silently break a theme
-- and show only in the game.
--
-- The faction_font_color setting: it is OFF by default, and when it is off the game draws
-- text in grey instead of the faction colour. Both sides are checked.
--
-- Robustness: an unknown value in the profile, a missing skin or a missing skin key must
-- never leave a theme without a colour, because a panel with a nil colour is not drawn at
-- all.
--
-- ui.lua: the theme reaches the panel, and changing the theme in the profile rebuilds the
-- panel. The colour is set in the constructor, so a theme applied after the elements are
-- created would leave the panel with the old colour for good.
--
-- Blinking: off by default; when on, the row blinks with a muted colour and stops after a
-- limit.

local function ReadFile(path)
    local file = assert(io.open(path, 'rb'))
    local text = file:read('*a')
    file:close()
    return text
end

-- Every file of a mod runs in its own environment, as in the game.
local function MakeEnv()
    return setmetatable({}, { __index = _G })
end

local function LoadInto(path, env)
    local chunk = assert(loadstring(ReadFile(path), path))
    setfenv(chunk, env)
    return chunk()
end

local function Run(label, block)
    print(label)
    local ok, res = pcall(block)
    if not ok then
        print('  [FAIL] проверка упала: ' .. tostring(res))
        return 1
    end
    return res or 0
end

local MOD = '../Overflow/modules/'

do
PROFILE = {}
msgs = {}

function LOG(m) msgs[table.getn(msgs) + 1] = tostring(m) end

Prefs = {}
function Prefs.GetFromCurrentProfile(k) return PROFILE[k] end
function Prefs.SetToCurrentProfile(k, v) PROFILE[k] = v end

-- Game option "faction font colour". The real Prefs.GetOption returns the default value
-- when the option is absent, so it NEVER returns nil. The stub does the same: with no key
-- set it returns FALLBACK_OPT, not nil.
FACTION_FONT_COLOR = nil
FALLBACK_OPT = false
function Prefs.GetOption(k)
    if k == 'faction_font_color' then
        if FACTION_FONT_COLOR == nil then return FALLBACK_OPT end
        return FACTION_FONT_COLOR
    end
    return nil
end

-- ------------------------------------------------------- GAME SKINS
--
-- A copy of the values from lua/skins/skins.lua: the default palette and the faction
-- sections. The checks run against exactly these numbers.
SKINS_REAL = {
    default = {
        fontColor = 'FFbadbdb',
        bodyColor = 'FF6FAFAF',
        dialogCaptionColor = 'FFbadbdb',
        dialogButtonColor = 'FF69AB4D',
        highlightColor = 'FF7FA8A4',
        disabledColor = 'FF47555a',
        panelColor = 'FF4A5D6B',
        transparentPanelColor = 'AA4A5D6B',
    },
    -- In skins.lua UEF overrides NO colour. But the game copies the whole default chain
    -- into it (table.assimilate), so the UEF table holds the default values, and that is
    -- what the mod sees.
    uef = {
        fontColor = 'FFbadbdb',
        bodyColor = 'FF6FAFAF',
        dialogCaptionColor = 'FFbadbdb',
        dialogButtonColor = 'FF69AB4D',
        highlightColor = 'FF7FA8A4',
        disabledColor = 'FF47555a',
        panelColor = 'FF4A5D6B',
        transparentPanelColor = 'AA4A5D6B',
    },
    aeon = {
        fontColor = 'FFc7e98a',
        bodyColor = 'FF18d006',
        disabledColor = 'FF3b5511',
    },
    cybran = {
        fontColor = 'FFe24f2d',
        bodyColor = 'FFb00101',
        disabledColor = 'FF640505',
    },
    seraphim = {
        fontColor = 'FFffd700',
        bodyColor = 'FF927b00',
        disabledColor = 'FF685f16',
    },
}
SKINS = SKINS_REAL

function ForkThread(f) f() end
function WaitSeconds(n) end

-- ------------------------------------------------------- UI controls
MADE = {}
NEWCOLORS = {}
-- Fill colours are kept apart from text colours. They are different things: redrawing the
-- panel calls SetColor on the captions, while rebuilding it also calls SetSolidColor on the
-- background. Telling "redrawn" from "rebuilt" takes a separate list.
NEWSOLID = {}
-- Textures are kept apart from fills. The backing of the Minimal frame is a Bitmap with
-- SetTexture, and without a separate list "the backing was created with the right texture"
-- cannot be told from "the backing was not created at all".
NEWTEX = {}
-- Texture cropping is kept apart from the texture itself. The backing of the Minimal frame
-- is drawn in two pieces, and the built-in line of the texture between them is SKIPPED
-- through SetUV. Without a separate list "the line was skipped" cannot be told from "the
-- line was stretched over the whole window".
NEWUV = {}

local function valueProp(getter, setter)
    -- Mirrors the game's LazyVar: a value can be a number, be computed by a function, or be
    -- bound to another value object.
    local p = {}
    p._get = getter
    p._set = setter
    p._link = nil
    setmetatable(p, {
        __call = function(self)
            if self._link then return self._link() end
            return self._get()
        end
    })
    function p:Set(v)
        if type(v) == 'function'
            or (type(v) == 'table' and getmetatable(v)) then
            self._link = v
        else
            self._link = nil
            self._set(v)
        end
    end
    return p
end

-- The last size limit the mod gave the window.
MINSIZE = nil

local function NewCtrl(kind, parent)
    local c = {}
    c._kind = kind
    c._parent = parent
    c._x, c._y, c._w, c._h = 0, 0, 0, 0
    c._hidden = false
    c._text = ''
    c._color = nil
    c._destroyed = false
    -- Depth is a value object like Left: it can be READ. The mod raises the title strip
    -- above the content through client.Depth() + 1, and a stub with only Set() would fail
    -- on that call.
    c.Depth = valueProp(function() return c._depth or 0 end,
                        function(v) c._depth = v end)
    function c:SetSolidColor(v)
        self._color = v
        NEWCOLORS[table.getn(NEWCOLORS) + 1] = v
        NEWSOLID[table.getn(NEWSOLID) + 1] = v
    end
    function c:SetTexture(v)
        self._texture = v
        NEWTEX[table.getn(NEWTEX) + 1] = v
    end
    -- SetUV exists on Bitmap. The stub has to have it: without it the backing would not be
    -- created at all, because the mod calls SetUV right after SetTexture.
    function c:SetUV(u0, v0, u1, v1)
        self._uv = { u0, v0, u1, v1 }
        NEWUV[table.getn(NEWUV) + 1] = { u0, v0, u1, v1 }
    end
    function c:SetAlpha(v) self._alpha = v end
    function c:SetColor(v)
        self._color = v
        NEWCOLORS[table.getn(NEWCOLORS) + 1] = v
    end
    function c:SetDropShadow(v) end
    function c:SetFont(f, s) end
    function c:EnableHitTest(v) end
    function c:DisableHitTest(v) end
    function c:Hide() self._hidden = true end
    function c:Show() self._hidden = false end
    function c:Destroy() self._destroyed = true end
    function c:IsDestroyed() return self._destroyed end
    function c:GetRootFrame() return FRAME end
    function c:SetText(t) self._text = t end
    function c:GetText() return self._text end
    -- GetStringAdvance exists on a text control. The mod measures the width of its longest
    -- line with it. Without it the width limit check would test the stub, not the mod. The
    -- width grows with the string length, as the real one does, so swapping a short caption
    -- for a long one shows.
    function c:GetStringAdvance(s)
        s = s or ''
        return string.len(s) * 6
    end
    function c:Left() return self._x end
    function c:Top() return self._y end
    c.Width = valueProp(function() return c._w end,
                        function(v) c._w = v end)
    c.Height = valueProp(function() return c._h end,
                         function(v) c._h = v end)
    -- Right and Bottom are computed from the neighbouring values, the way ResetLayout binds
    -- them in the game. Reading the _x/_w fields directly does not work: when Left and
    -- Width are set by references (the close button is bound to the right edge of the
    -- window), the fields stay zero and Right would come out zero.
    c.Right = valueProp(function() return c.Left() + c.Width() end,
                       function(v) c._w = v - c.Left() end)
    c.Bottom = valueProp(function() return c.Top() + c.Height() end,
                        function(v) c._h = v - c.Top() end)
    c.Left = valueProp(function() return c._x end,
                       function(v) c._x = v end)
    c.Top = valueProp(function() return c._y end,
                      function(v) c._y = v end)
    MADE[table.getn(MADE) + 1] = c
    return c
end

UIUtil = {}
UIUtil.bodyFont = 'bodyFont'
UIUtil.titleFont = 'titleFont'
function UIUtil.CreateText(parent, text, size, font)
    local c = NewCtrl('Text', parent)
    c._text = text or ''
    c._size = size
    -- The mod writes text through SetText. It is also recorded in a shared list: otherwise
    -- the "numbers only" mode could not be checked on the screen, since each caption has
    -- only its own _text.
    c.SetText = function(self, v)
        self._text = v
        NEWTEXT[table.getn(NEWTEXT) + 1] = v
    end
    return c
end
function UIUtil.GetCursor(name)
    return { SetTexture = function() end, Reset = function() end }
end
-- UIFile resolves a path into the skin folder in the game. The stub returns the path as is:
-- only the call matters, not the resolved file.
function UIUtil.UIFile(filespec) return filespec end

-- ------------------------------------------------------- Window class (game)
--
-- The real class is lua/maui/window.lua. The mod uses from it: the constructor,
-- ClientGroup, Left/Top/Right/Bottom/Height as VALUE OBJECTS, Depth:Set, DisableHitTest,
-- SetMinimumResize, Hide, Show, Destroy. It also assigns OnClose and OnResize, which are
-- plain fields here.
local function NewWindow(parent)
    local w = NewCtrl('Window', parent)
    w._x, w._y, w._w, w._h = 8, 80, 340, 160
    w.ClientGroup = NewCtrl('ClientGroup', w)
    -- CLIENT AREA BOUNDS. The Window class insets the client area from the window edges by
    -- the frame and the title strip: 5 left and right, 30 top, 8 bottom. The stub has to
    -- repeat this: without a client area neither the indent of a row under the close button
    -- nor the check that rows start at the top of the window can be computed.
    w.ClientGroup.Left:Set(function() return w.Left() + 5 end)
    w.ClientGroup.Right:Set(function() return w.Right() - 5 end)
    w.ClientGroup.Top:Set(function() return w.Top() + 30 end)
    w.ClientGroup.Bottom:Set(function() return w.Bottom() - 8 end)
    -- The size limit is remembered: otherwise the check "the mod gave the window a limit
    -- based on the content" would test the stub.
    function w:SetMinimumResize(a, b)
        MINSIZE = { a, b }
    end
    function w:DisableHitTest() end
    local function valueProp(getter, setter)
        local p = {}
        p._get = getter
        p._set = setter
        p._link = nil
        setmetatable(p, { __call = function(self)
            if self._link then return self._link() end
            return self._get()
        end })
        function p:Set(v)
            if type(v) == 'function'
                or (type(v) == 'table' and getmetatable(v)) then
                self._link = v
            else
                self._link = nil
                self._set(v)
            end
        end
        return p
    end
    w.Left   = valueProp(function() return w._x end, function(v) w._x = v end)
    w.Top    = valueProp(function() return w._y end, function(v) w._y = v end)
    -- Right and Bottom SET THE SIZE, as in MAUI: Right = Left + Width, Bottom = Top +
    -- Height. The Window class sizes itself this way and does not touch Height at all. A
    -- stub with an empty setter would miss this and let a regression through.
    w.Right  = valueProp(function() return w._x + w._w end,
                         function(v) w._w = v - w._x end)
    w.Bottom = valueProp(function() return w._y + w._h end,
                         function(v) w._h = v - w._y end)
    w.Height = valueProp(function() return w._h end, function(v) w._h = v end)
    -- TITLE STRIP AND CLOSE BUTTON. The Window class always creates them, even when no
    -- title is passed: a 30 px strip and a close button in its top-right corner, 10 from
    -- the right edge and 5 from the top. The mod stretches the strip over the whole window,
    -- and the rows under the button are indented to the right, so the stub has to provide
    -- the strip, the button and the REAL bounds of the button.
    w.TitleGroup = NewCtrl('TitleGroup', w)
    w.TitleGroup._h = 30
    w._closeBtn = NewCtrl('Button', w)
    w._closeBtn.Width:Set(function() return 20 end)
    w._closeBtn.Height:Set(function() return 20 end)
    w._closeBtn.Left:Set(function() return w.Right() - 30 end)
    w._closeBtn.Top:Set(function() return w.Top() + 5 end)

    -- NINE FRAME PIECES. The class creates them in ApplyWindowTextures, and the mod fills
    -- them with a solid colour in the Minimal theme. The stub has to have them, otherwise a
    -- broken theme goes unnoticed.
    for _, part in ipairs({ 'window_tl', 'window_tr', 'window_tm',
                            'window_ml', 'window_m', 'window_mr',
                            'window_bl', 'window_bm', 'window_br' }) do
        w[part] = NewCtrl('Bitmap', w)
        w[part].solid = nil
    end
    w.Width  = valueProp(function() return w._w end, function(v) w._w = v end)
    return w
end

local Bitmap = function(parent) return NewCtrl('Bitmap', parent) end
local Group  = function(parent) return NewCtrl('Group', parent) end

LayoutHelpers = {}
function LayoutHelpers.SetDimensions(c, w, h) c._w = w c._h = h end
-- pixelScaleFactor is the interface scale of the game. The stub uses 1: the multiplication
-- changes nothing, but the call and the order of computations are still checked.
pixelScaleFactor = 1.0

-- There is no global MathFloor in FAF: every game file declares its own alias (`local
-- MathFloor = math.floor`). So the stub does not create the global and takes math.floor at
-- the call site. Declaring MathFloor as a global would hide a read of this nonexistent
-- global, which fails the module load in the game.

-- The anchors repeat layouthelpers.lua: the offset is multiplied by pixelScaleFactor, the
-- result goes through MathFloor, and the anchor is set with SetFunction, so the value
-- recomputes by itself.
function LayoutHelpers.AtLeftIn(c, p, leftOffset)
    if leftOffset and leftOffset ~= 0 then
        c.Left:Set(function() return math.floor(p.Left() + leftOffset * pixelScaleFactor) end)
    else
        c.Left:Set(function() return p.Left() end)
    end
end
function LayoutHelpers.AtTopIn(c, p, topOffset)
    if topOffset and topOffset ~= 0 then
        c.Top:Set(function() return math.floor(p.Top() + topOffset * pixelScaleFactor) end)
    else
        c.Top:Set(function() return p.Top() end)
    end
end
function LayoutHelpers.AtRightIn(c, p, rightOffset)
    if rightOffset and rightOffset ~= 0 then
        c.Right:Set(function() return math.floor(p.Right() - rightOffset * pixelScaleFactor) end)
    else
        c.Right:Set(function() return p.Right() end)
    end
end
function LayoutHelpers.AtLeftTopIn(c, p, x, y)
    LayoutHelpers.AtLeftIn(c, p, x)
    LayoutHelpers.AtTopIn(c, p, y)
end
function LayoutHelpers.AtHorizontalCenterIn(c, p) end
function LayoutHelpers.AtVerticalCenterIn(c, p) end
function LayoutHelpers.FillParent(c, p) end
function LayoutHelpers.InvScaleNumber(v) return v end
-- ScaleNumber exists in the game: the mod uses it to grow a window to its content limit
-- (ApplyMinSize in ui.lua).
function LayoutHelpers.ScaleNumber(v) return math.floor(v * pixelScaleFactor) end

local Dragger = function()
    return { OnMove = nil, OnRelease = nil, Destroy = function() end }
end
function PostDragger(frame, key, drag) end

FRAME = { Width = function() return 1920 end, Height = function() return 1080 end }
function GetFrame(i) return FRAME end
function GetCursor()
    return { SetTexture = function() end, Reset = function() end }
end

GameMainStub = { AddBeatFunction = function(f, throttle, id) BEAT = f end }
BEAT = nil

SYNCSTUB = {
    started = false,
    Start = function() SYNCSTUB.started = true return true end,
    GetResult = function()
        return {
            ok = true,
            incoming = 100, outgoing = 20, own = 200,
            massIncoming = 0, massOutgoing = 30, massOwn = 300,
            reclaim = 5, massReclaim = 6,
        }
    end,
}

function import(p)
    if p == '/lua/user/prefs.lua' then return Prefs end
    if p == '/lua/skins/skins.lua' then return { skins = SKINS } end
    if p == '/lua/ui/uiutil.lua' then return UIUtil end
    if p == '/lua/maui/bitmap.lua' then return { Bitmap = Bitmap } end
    if p == '/lua/maui/group.lua' then return { Group = Group } end
    if p == '/lua/maui/layouthelpers.lua' then return LayoutHelpers end
    if p == '/lua/maui/dragger.lua' then return { Dragger = Dragger } end
    if p == '/lua/maui/window.lua' then return { Window = NewWindow } end
    if p == '/lua/ui/game/gamemain.lua' then return GameMainStub end
    if p == '/mods/Overflow/modules/rows.lua' then return MODULES.rows end
    if p == '/mods/Overflow/modules/themes.lua' then return MODULES.themes end
    if p == '/mods/Overflow/modules/sync.lua' then return SYNCSTUB end
    return {}
end

-- ------------------------------------------------------- helpers
function alltext() return table.concat(msgs, ' | ') end
NEWTEXT = {}
function resetlog() msgs = {} NEWTEXT = {} NEWUV = {} end

-- The # operator is not supported by the engine; the table length is taken with table.getn.
TableGetn = table.getn

function PickTheme(name)
    local t = PROFILE['Overflow']
    if type(t) ~= 'table' then t = {} end
    t.theme = name
    PROFILE['Overflow'] = t
end
function PickBlink(on)
    local t = PROFILE['Overflow']
    if type(t) ~= 'table' then t = {} end
    t.blink = on and true or false
    PROFILE['Overflow'] = t
end

-- Choices in the profile. The preset and the frame have their own keys: style and theme.
function PickStyle(name)
    local t = PROFILE['Overflow']
    if type(t) ~= 'table' then t = {} end
    t.style = name
    PROFILE['Overflow'] = t
end
function PickFrame(name)
    local t = PROFILE['Overflow']
    if type(t) ~= 'table' then t = {} end
    t.theme = name
    PROFILE['Overflow'] = t
end
function PickFontScale(v)
    local t = PROFILE['Overflow']
    if type(t) ~= 'table' then t = {} end
    t.fontScale = v
    PROFILE['Overflow'] = t
end
function PickNumbers(on)
    local t = PROFILE['Overflow']
    if type(t) ~= 'table' then t = {} end
    t.numbersOnly = on and true or false
    PROFILE['Overflow'] = t
end

-- AN EMPTY PROFILE MEANS THE WHOLE PROFILE IS EMPTY, not only the 'Overflow' key.
--
-- The panel keeps its collapsed state under its OWN top-level key (COLLAPSE_KEY =
-- 'OverflowCollapsed' in ui.lua) and reads it back when it builds the window. If only one
-- key were cleared, the collapsed state would survive ClearProfile: the next U.OnCreateUI()
-- would raise the panel already collapsed, Render would not be called, and the captions
-- would not return to the screen.
function ClearProfile() PROFILE = {} end

FIELDS = { 'BG', 'CLOSED', 'DIVIDER', 'TITLE', 'TOTAL', 'NEUTRAL',
           'SAFE', 'WARN', 'BAD' }
function Complete(pal)
    if type(pal) ~= 'table' then return false end
    for i = 1, TableGetn(FIELDS) do
        local f = FIELDS[i]
        if type(pal[f]) ~= 'string' or pal[f] == '' then return false end
    end
    return true
end
function InList(list, value)
    for i = 1, TableGetn(list) do
        if list[i] == value then return true end
    end
    return false
end
end

MODULES = {}

local env_theme = MakeEnv()
LoadInto(MOD .. 'themes.lua', env_theme)
MODULES.themes = env_theme
-- A separate global: the check blocks see the module only through it.
T = env_theme

local env_rows = MakeEnv()
LoadInto(MOD .. 'rows.lua', env_rows)
MODULES.rows = env_rows
ROWS = env_rows

-- ui.lua loads last: it pulls themes.lua and rows.lua through import, and without them the
-- log gets FATAL.
local env_ui = MakeEnv()
LoadInto(MOD .. 'ui.lua', env_ui)
MODULES.ui = env_ui
U = env_ui

local f1 = Run("=== 1. СОСТАВ: ДВА ВЫБОРА ===", function()
local fails = 0
local function check(cond, text)
    if cond then return end
    fails = fails + 1
    print('  [FAIL] ' .. text)
end

-- Player profiles store these names, so they must not change. The default is
-- up to the mod, so the rule is checked instead of a name: the default is the
-- first item, otherwise UMT silently replaces it with items[1].
ClearProfile()
local frames = T.FrameNames()
check(TableGetn(frames) == 2,
      'рамок ровно две (получено ' .. tostring(TableGetn(frames)) .. ')')
check(InList(frames, 'Vanilla'), 'рамка Vanilla есть в списке')
check(InList(frames, 'Minimal'), 'рамка Minimal есть в списке')
check(T.FrameCurrent() == frames[1],
      'рамка по умолчанию - первый пункт списка, а не ' ..
      tostring(T.FrameCurrent()))

ClearProfile()
local styles = T.StyleNames()
check(TableGetn(styles) == 2,
      'пресетов ровно два (получено ' .. tostring(TableGetn(styles)) .. ')')
check(InList(styles, 'Vanilla'), 'пресет Vanilla есть в списке')
check(InList(styles, 'Minimal'), 'пресет Minimal есть в списке')
check(T.StyleCurrent() == styles[1],
      'пресет по умолчанию - первый пункт списка, а не ' ..
      tostring(T.StyleCurrent()))

-- THERE ARE NO FACTION THEMES. The frame is taken from the skin folder anyway, so the lists
-- must have no separate item for a faction.
local joined = frames[1] .. frames[2] .. styles[1] .. styles[2]
for _, gone in ipairs({ 'AEON', 'UEF', 'Cybran', 'Seraphim', 'SSB', 'Тихая',
                        'Неон' }) do
    check(string.find(joined, gone, 1, true) == nil,
          'фракционная тема ' .. gone .. ' убрана из списков')
end
return fails
end)

local f2 = Run("=== 2. ПАЛИТРА ПОЛНА У ЛЮБОГО ПРЕСЕТА ===", function()
local fails = 0
local function check(cond, text)
    if cond then return end
    fails = fails + 1
    print('  [FAIL] ' .. text)
end

-- A panel with a nil colour is not drawn at all, so the set of fields has to be complete
-- for any choice.
local styleList = { 'Vanilla', 'Minimal' }
for i = 1, TableGetn(styleList) do
    ClearProfile()
    PickStyle(styleList[i])
    local pal = T.StylePalette()
    check(Complete(pal),
          'пресет ' .. styleList[i] .. ' вернул полный набор полей')
end

-- BOTH PRESETS HAVE A FONT SIZE, NEITHER SETS THE FRAME COLOURS. The frame paints itself
-- with its own backing and the preset knows nothing about the frame. Were BG in the preset,
-- the choice "Minimal frame + Vanilla preset" would paint the window with the game's
-- transparent panel AA4A5D6B (skins.lua). So BG of Minimal is the same as the game's.
ClearProfile()
PickStyle('Minimal')
local minPal = T.StylePalette()
check(minPal.BG == 'AA4A5D6B',
      'пресет Minimal больше не задаёт цвет рамки (BG = ' ..
      tostring(minPal.BG) .. ')')
check(minPal.FONT == 11, 'у пресета Minimal кегль 11, а не nil (' ..
      tostring(minPal.FONT) .. ')')
return fails
end)

local f3 = Run("=== 3. СМЫСЛ ЦВЕТОВ ОДИНАКОВ У ОБОИХ ПРЕСЕТОВ ===", function()
local fails = 0
local function check(cond, text)
    if cond then return end
    fails = fails + 1
    print('  [FAIL] ' .. text)
end

-- The player reads the colours as: green is no overflow, yellow is allies overflowing to
-- you, red is you depend on overflow. So the list of states has to be the same and only the
-- shade may differ.
--
-- What can be checked here: both presets have all three states and all three are NON-EMPTY
-- strings. The meaning of the shade is set in StatusColor in ui.lua and is checked in the
-- panel test.
local want = { 'SAFE', 'WARN', 'BAD' }
for i = 1, TableGetn(want) do
    local field = want[i]
    ClearProfile()
    PickStyle('Vanilla')
    local v = T.StylePalette()[field]
    ClearProfile()
    PickStyle('Minimal')
    local m = T.StylePalette()[field]
    check(type(v) == 'string' and v ~= '' and type(m) == 'string' and m ~= '',
          'состояние ' .. field .. ' есть у обоих пресетов (Vanilla ' ..
          tostring(v) .. ', Minimal ' .. tostring(m) .. ')')
end

-- The state colours of the VANILLA PRESET are the game's, without exceptions.
ClearProfile()
PickStyle('Vanilla')
local van = T.StylePalette()
check(van.SAFE == 'ffb7e75f',
      'Vanilla SAFE - игровой ffb7e75f (economy_mini.lua:12), а не ' ..
      tostring(van.SAFE))
check(van.WARN == 'yellow',
      'Vanilla WARN - игровое имя цвета yellow (economy.lua:262), а не ' ..
      tostring(van.WARN))
check(van.BAD == 'red',
      'Vanilla BAD - игровое имя цвета red (economy.lua:264), а не ' ..
      tostring(van.BAD))
return fails
end)

local f4 = Run("=== 4. ПРЕСЕТ VANILLA ЧИТАЕТ СКИНА ИГРЫ ===", function()
local fails = 0
local function check(cond, text)
    if cond then return end
    fails = fails + 1
    print('  [FAIL] ' .. text)
end

-- A typo in a number is impossible: the values come from the skin, and if FAF changes the
-- skin, the mod follows.
ClearProfile()
FACTION_FONT_COLOR = true
PickStyle('Vanilla')
local v = T.StylePalette()
check(v.NEUTRAL == 'FF18d006',
      'Vanilla NEUTRAL читается из скина (bodyColor FF18d006), а не ' ..
      tostring(v.NEUTRAL))
check(v.DIVIDER == 'FF3b5511',
      'Vanilla DIVIDER читается из скина (disabledColor FF3b5511), а не ' ..
      tostring(v.DIVIDER))

-- The background of the flat frame comes from the same skin.
check(v.BG == 'AA4A5D6B',
      'Vanilla BG - прозрачная панель игры AA4A5D6B, а не ' .. tostring(v.BG))

-- The MINIMAL PRESET ignores the skin colours: it is ours and uses its own numbers.
ClearProfile()
PickStyle('Minimal')
local m = T.StylePalette()
check(m.NEUTRAL == 'FF8A96A3',
      'Minimal NEUTRAL свой, а не игровой (FF8A96A3 против ' ..
      tostring(m.NEUTRAL) .. ')')

FACTION_FONT_COLOR = nil
return fails
end)

local f5 = Run("=== 5. НАСТРОЙКА faction_font_color ===", function()
local fails = 0
local function check(cond, text)
    if cond then return end
    fails = fails + 1
    print('  [FAIL] ' .. text)
end

-- The option is off by default, and then the game draws text with the grey
-- skins.default.fontColor. The mod repeats this.
ClearProfile()
FACTION_FONT_COLOR = false
PickStyle('Vanilla')
local grey = T.StylePalette()
check(grey.TITLE == 'FFbadbdb',
      'при выключенной настройке заголовок серый, как в игре (FFbadbdb), а не ' ..
      tostring(grey.TITLE))

FACTION_FONT_COLOR = true
ClearProfile()
PickStyle('Vanilla')
local colour = T.StylePalette()
check(colour.TITLE == 'FFc7e98a',
      'при включённой настройке цвет шрифта фракции доезжает до панели, а не ' ..
      tostring(colour.TITLE))

-- Ordinary text does NOT depend on the option: the game sets bodyColor from the skin
-- unconditionally.
check(colour.NEUTRAL == grey.NEUTRAL,
      'цвет обычного текста не зависит от faction_font_color')

FACTION_FONT_COLOR = nil
return fails
end)

local f6 = Run("=== 6. МАСШТАБ ШРИФТА ===", function()
local fails = 0
local function check(cond, text)
    if cond then return end
    fails = fails + 1
    print('  [FAIL] ' .. text)
end

-- The UMT slider is integer, so the scale is in percent.
ClearProfile()
check(T.FontScale() == T.FontScaleDefault(),
      'без настроек масштаб равен значению по умолчанию из мода, а не ' ..
      tostring(T.FontScale()))
check(T.FontScaleDefault() >= 70 and T.FontScaleDefault() <= 200,
      'масштаб по умолчанию лежит в границах ползунка, а не ' ..
      tostring(T.FontScaleDefault()))

ClearProfile()
PickFontScale(100)
PickStyle('Vanilla')
check(T.StyleFontSize() == 10,
      'при 100 процентах кегль равен базовому (10), а не ' ..
      tostring(T.StyleFontSize()))

ClearProfile()
PickFontScale(150)
PickStyle('Vanilla')
check(T.StyleFontSize() == 15,
      'при 150 процентах кегль 15, а не ' .. tostring(T.StyleFontSize()))

ClearProfile()
PickFontScale(150)
PickStyle('Minimal')
check(T.StyleFontSize() == 17,
      'пресет масштабируется от СВОЕГО базового кегля (11 -> 17), а не ' ..
      tostring(T.StyleFontSize()))

-- Bounds. Outside them the mod behaves as at the bound instead of failing.
ClearProfile()
PickFontScale(5)
check(T.FontScale() == 70, 'слишком маленький масштаб поднимается до 70')
ClearProfile()
PickFontScale(9999)
check(T.FontScale() == 200, 'слишком большой масштаб опускается до 200')

-- Garbage in the profile must not break the panel.
ClearProfile()
PickFontScale('не число')
check(T.FontScale() == T.FontScaleDefault(),
      'нечисловой масштаб трактуется как значение по умолчанию')
return fails
end)

local f7 = Run("=== 7. РАМКА И РЕЖИМ «ТОЛЬКО ЧИСЛА» ===", function()
local fails = 0
local function check(cond, text)
    if cond then return end
    fails = fails + 1
    print('  [FAIL] ' .. text)
end

ClearProfile()
PickFrame('Minimal')
check(T.FrameCurrent() == 'Minimal', 'рамка Minimal выбирается')
check(T.FrameMinimal() == true, 'рамка Minimal помечена как плоская')
PickFrame('Vanilla')
check(T.FrameMinimal() == false, 'рамка Vanilla помечена как игровая')

-- An unknown value gives the default frame: it must not silently disappear.
ClearProfile()
PickFrame('не существует')
check(T.FrameCurrent() == T.FrameNames()[1],
      'неизвестная рамка откатывается к рамке по умолчанию')

ClearProfile()
check(T.NumbersOnly() == false, 'режим «только числа» выключен по умолчанию')
ClearProfile()
PickNumbers(true)
check(T.NumbersOnly() == true, 'режим «только числа» читается из профиля')
return fails
end)

local f8 = Run("=== 8. ПОДПИСЬ И МИГАНИЕ ===", function()
local fails = 0
local function check(cond, text)
    if cond then return end
    fails = fails + 1
    print('  [FAIL] ' .. text)
end

-- The signature decides whether to rebuild the panel. Everything that changes the look at
-- build time has to be part of it, otherwise a changed setting would not be picked up.
--
-- All settings are given explicitly and exactly one differs from the base set, so the check
-- does not depend on the defaults.
local function Sig(over)
    ClearProfile()
    PickStyle(over.style or 'Minimal')
    PickFrame(over.frame or 'Minimal')
    PickFontScale(over.scale or 100)
    PickNumbers(over.numbers)
    PickBlink(over.blink)
    return T.ThemeSignature()
end
local base = Sig({})
check(Sig({ style = 'Vanilla' }) ~= base,
      'подпись обязана меняться при смене пресета')
check(Sig({ frame = 'Vanilla' }) ~= base,
      'подпись обязана меняться при смене рамки')
check(Sig({ scale = 150 }) ~= base,
      'подпись обязана меняться при смене масштаба шрифта')
check(Sig({ numbers = true }) ~= base,
      'подпись обязана меняться при включении «только числа»')
check(Sig({ blink = true }) ~= base, 'подпись обязана меняться при мигании')

ClearProfile()
PickBlink(true)
check(T.ThemeBlinkOn() == true, 'мигание читается из профиля')
ClearProfile()
check(T.ThemeBlinkOn() == false, 'мигание выключено по умолчанию')

-- The description has to be readable, not a concatenation of fields.
ClearProfile()
PickStyle('Minimal')
local tell = T.ThemeTell()
check(string.find(tell, 'Minimal', 1, true) ~= nil,
      'в описании видно имя пресета, а не ' .. tell)
check(string.find(tell, T.ThemeSignature(), 1, true) == nil,
      'описание не выдаёт сырую подпись: ' .. tell)
return fails
end)

local f9 = Run("=== 9. УСТОЙЧИВОСТЬ К ПРОФИЛЮ И СКИНАМ ===", function()
local fails = 0
local function check(cond, text)
    if cond then return end
    fails = fails + 1
    print('  [FAIL] ' .. text)
end

-- An empty profile: everything has to take its default instead of failing.
ClearProfile()
check(T.StyleCurrent() == T.StyleNames()[1],
      'пустой профиль даёт пресет по умолчанию')
check(T.FrameCurrent() == T.FrameNames()[1],
      'пустой профиль даёт рамку по умолчанию')
check(T.FontScale() == T.FontScaleDefault(),
      'пустой профиль даёт масштаб по умолчанию')
check(Complete(T.StylePalette()), 'пустой профиль даёт полную палитру')

-- Garbage values in the profile.
local t = PROFILE['Overflow']
PROFILE['Overflow'] = { style = 42, theme = {}, fontScale = {}, blink = 'да' }
check(T.StyleCurrent() == T.StyleNames()[1],
      'нестрочный пресет откатывается к пресету по умолчанию')
check(T.FrameCurrent() == T.FrameNames()[1],
      'нестрочная рамка откатывается к рамке по умолчанию')
check(T.FontScale() == T.FontScaleDefault(),
      'нестрочный масштаб откатывается к масштабу по умолчанию')
check(T.ThemeBlinkOn() == true, 'любая непустая строка считается включённой')
PROFILE['Overflow'] = nil

-- WITHOUT skins.lua. The module has to survive and return a full set: a panel without the
-- skin colours is better than a panel with transparent text.
ClearProfile()
local vanillaNoSkin = T.StylePalette()
check(Complete(vanillaNoSkin),
      'без скина палитра Vanilla остаётся полной')
check(vanillaNoSkin.NEUTRAL ~= nil and vanillaNoSkin.NEUTRAL ~= '',
      'без скина обычный текст не прозрачный')
return fails
end)

local f10 = Run("=== 10. ui.lua: ОФОРМЛЕНИЕ ДОЕЗЖАЕТ ДО ПАНЕЛИ ===", function()
local fails = 0
local function check(cond, text)
    if cond then return end
    fails = fails + 1
    print('  [FAIL] ' .. text)
end

-- The panel reads the palette when it is built, and the colours have to reach the captions.
--
-- The colour is taken from the GAME skin, not from the Minimal palette. The built-in
-- colours of ui.lua equal the Minimal palette, so a check for FF8FD0FF would pass even if
-- ApplyTheme were NOT called: the test would be green on a broken panel. That is why
-- Vanilla and FF18d006 are used here: that colour is not in the built-in palette.
ClearProfile()
PickStyle('Vanilla')
resetlog()
NEWCOLORS = {}
U.OnCreateUI()
local seen = {}
for i = 1, table.getn(NEWCOLORS) do seen[NEWCOLORS[i]] = true end
check(seen['FF18d006'] == true,
      'цвет подписи пресета Minimal должен уйти в панель')
check(string.find(alltext(), 'window created', 1, true) ~= nil,
      'панель собралась')
check(string.find(alltext(), 'Vanilla', 1, true) ~= nil,
      'в логе должно быть видно имя пресета')

-- "NUMBERS ONLY" MODE: a row keeps one number, without a caption and without a unit.
-- Checked on the text that actually reached the screen.
ClearProfile()
PickNumbers(true)
NEWTEXT = {}
U.OnCreateUI()
BEAT()
local joined = ''
for i = 1, table.getn(NEWTEXT) do joined = joined .. '|' .. tostring(NEWTEXT[i]) end
check(string.find(joined, 'ally overflow', 1, true) == nil,
      'в режиме чисел подписи строк убраны: ' .. joined)
check(string.find(joined, '|0.0', 1, true) ~= nil,
      'в режиме чисел остались сами числа: ' .. joined)

-- MINIMAL FRAME BACKING. In Minimal the frame is not a window but a plain Bitmap with a
-- game texture. So the mod BLANKS all nine window pieces with a transparent colour and
-- draws the background with a separate Bitmap.
--
-- Checked: the number of blanked pieces, their colour, and that the backing is created with
-- the right texture at all. A count alone is not enough: nine fills can be made in a wrong
-- colour, and the panel would keep the game frame.
ClearProfile()
PickFrame('Minimal')
NEWSOLID = {}
NEWTEX = {}
NEWUV = {}
-- A mark in the shared list of controls: the backing is looked up only among the controls
-- created by THIS pass, otherwise pieces from earlier window builds would be counted.
local mark = table.getn(MADE)
U.OnCreateUI()
check(TableGetn(NEWSOLID) >= 9,
      'рамка Minimal: погашены девять кусков окна (заливок ' ..
      tostring(TableGetn(NEWSOLID)) .. ')')
local cleared = 0
for i = 1, TableGetn(NEWSOLID) do
    if NEWSOLID[i] == '00000000' then cleared = cleared + 1 end
end
check(cleared >= 9,
      'рамка Minimal: куски окна погашены прозрачным, а не залиты цветом (' ..
      tostring(cleared) .. ')')

-- THE BACKING IS TWO PIECES, NOT ONE.
--
-- The panel texture has its OWN divider line in the middle: y=35 of 72, full width
-- (measured on the unpacked file, the same in all four skins). Stretched over the whole
-- window, the line ends up in empty space and our own divider stands next to it, giving TWO
-- lines.
--
-- So the background is drawn with two Bitmaps and the built-in line between them is SKIPPED
-- through SetUV: the top piece takes texture rows 0..34, the bottom one 36..71. This is
-- what is checked, not just "a backing exists".
local pieces = {}
for i = mark + 1, table.getn(MADE) do
    local c = MADE[i]
    if c._texture ~= nil
        and string.find(tostring(c._texture),
                        'filter-ping-panel02_bmp.dds', 1, true) ~= nil then
        pieces[table.getn(pieces) + 1] = c
    end
end
check(table.getn(pieces) == 2,
      'подложка рамки Minimal собрана из двух кусков, а не из одного (' ..
      tostring(table.getn(pieces)) .. ')')

local LINE_TOP = 35 / 72
local LINE_BOTTOM = 36 / 72
local topPiece, botPiece = nil, nil
for i = 1, table.getn(pieces) do
    local uv = pieces[i]._uv
    if uv ~= nil and uv[4] <= LINE_TOP + 0.001 then topPiece = pieces[i] end
    if uv ~= nil and uv[2] >= LINE_BOTTOM - 0.001 then botPiece = pieces[i] end
end
check(topPiece ~= nil,
      'верхний кусок подложки обрезан по встроенной линии, а не тянет её на ' ..
      'всё окно (v1 = ' .. tostring(topPiece and topPiece._uv[4]) .. ')')
check(botPiece ~= nil,
      'нижний кусок подложки начинается после встроенной линии (v0 = ' ..
      tostring(botPiece and botPiece._uv[2]) .. ')')
check(topPiece ~= nil and botPiece ~= nil
      and topPiece._uv[1] == 0 and topPiece._uv[2] == 0
      and botPiece._uv[3] == 1 and botPiece._uv[4] == 1,
      'два куска вместе накрывают всю текстуру, без дыр по краям')

-- COLLAPSING REMOVES THE BACKING.
--
-- The backing hangs off GetFrame(0), not off the window, so G.win:Hide() does not touch it
-- and the mod has to hide it itself. Otherwise the close button would remove only the
-- values and an empty frame would stay on the screen.
local panel = nil
for i = mark + 1, table.getn(MADE) do
    if MADE[i]._kind == 'Window' then panel = MADE[i] end
end
check(panel ~= nil and panel.OnClose ~= nil,
      'окно нашлось для проверки сворачивания')
if panel ~= nil and panel.OnClose ~= nil then
    panel.OnClose(panel)
    local gone = 0
    for i = 1, table.getn(pieces) do
        if pieces[i]._hidden then gone = gone + 1 end
    end
    check(gone == table.getn(pieces) and table.getn(pieces) > 0,
          'при сворачивании подложка гаснет вместе с окном (погашено ' ..
          tostring(gone) .. ' из ' .. tostring(table.getn(pieces)) .. ')')
end

ClearProfile()
PickFrame('Vanilla')
NEWSOLID = {}
NEWTEX = {}
NEWUV = {}
U.OnCreateUI()
check(TableGetn(NEWSOLID) < 9,
      'в игровой рамке куски окна остаются текстурами (заливок ' ..
      tostring(TableGetn(NEWSOLID)) .. ')')
check(TableGetn(NEWTEX) == 0,
      'в игровой рамке подложка не создаётся (текстур ' ..
      tostring(TableGetn(NEWTEX)) .. ')')
check(TableGetn(NEWUV) == 0,
      'в игровой рамке текстура не режется (обрезок ' ..
      tostring(TableGetn(NEWUV)) .. ')')

-- And without this mode the captions are in place: otherwise the check box does nothing.
ClearProfile()
NEWTEXT = {}
U.OnCreateUI()
BEAT()
joined = ''
for i = 1, table.getn(NEWTEXT) do joined = joined .. '|' .. tostring(NEWTEXT[i]) end
check(string.find(joined, 'ally overflow', 1, true) ~= nil,
      'без режима чисел подписи вернулись')
return fails
end)

print('')
local noSkinOk, noSkinErr = pcall(function()
    -- The skin is removed BEFORE the module loads: themes.lua takes the skin table once, at
    -- import.
    SKINS = nil
    resetlog()
    local env_noskin = MakeEnv()
    LoadInto(MOD .. 'themes.lua', env_noskin)
    T = env_noskin
    if string.find(alltext(), 'skins.lua did not load', 1, true) == nil then
        print('  [FAIL] о пропаже скинов не сказано в лог')
        f10 = f10 + 1
    else
        print('  пропажа скинов замечена и сказана в лог')
    end
    PROFILE['Overflow'] = { theme = 'AEON' }
    NEWCOLORS = {}
    if not Complete(T.StylePalette()) then
        print('  [FAIL] без skins.lua палитра должна остаться полной')
        f10 = f10 + 1
    else
        print('  без skins.lua палитра осталась полной')
    end
end)
if not noSkinOk then
    print('  [FAIL] модуль не пережил пропажу скинов: ' .. tostring(noSkinErr))
    f10 = 1
end

print('')
print('=== ИТОГ ===')
local total = f1 + f2 + f3 + f4 + f5 + f6 + f7 + f8 + f9 + f10
if total > 0 then
    print('провалено проверок: ' .. tostring(total))
    os.exit(1)
end
print('все проверки пройдены')
