-- Tests of Overflow: row selection, the UMT settings page and the panel layout.
--
-- Run from the tests folder: lua test_overflow_rows.lua. The paths below are relative to
-- it. check.py does that with the Lua of the game, so this code follows its dialect.
--
-- rows.lua: which rows to show, what is written where, how ready-made sets expand and
-- collapse. The body key list must contain eGo and mGo, otherwise the "to allies" rows do
-- not hide when the panel collapses.
--
-- Options.lua (the UMT page): OptionVar:Set keeps the value in memory and does not write
-- the profile; only Save() on closing the window does. A page that read the profile would
-- not see a check box the player has just cleared and would still report success, so the
-- checks go through Set.
--
-- ui.lua: the layout is computed rather than taken from constants, and a mistake looks like
-- a panel overlapping itself. The panel height and the row positions are checked.
--
-- The stubs follow the game sources, not memory. Left is a value object that is both called
-- and assigned through :Set; PostDragger is a game global function; the gamemain stub is
-- declared before ui.lua loads, because import runs when the module loads.

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
function WARN(m) msgs[table.getn(msgs) + 1] = tostring(m) end

Prefs = {}
function Prefs.GetFromCurrentProfile(k) return PROFILE[k] end
function Prefs.SetToCurrentProfile(k, v) PROFILE[k] = v end
-- Game option "faction font colour" for themes.lua. It is off by default, so the stub
-- returns false, not nil: the real Prefs.GetOption returns the default value.
function Prefs.GetOption(k)
    if k == 'faction_font_color' then return false end
    return nil
end

-- Game skins for themes.lua. Only the module loading matters here; the colours themselves
-- are checked in test_overflow_theme.lua, where the skins are described in full.
SKINS = {
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
    uef = {}, aeon = {}, cybran = {}, seraphim = {},
}

function ForkThread(f) f() end
function WaitSeconds(n) end

-- ------------------------------------------------------- UI controls
MADE = {}

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
    c._font = 0
    c._destroyed = false
    c._children = {}
    if type(parent) == 'table' and parent._children then
        table.insert(parent._children, c)
    end
    -- Depth is a value object like Left: it can be READ. The mod raises the title strip
    -- above the content through client.Depth() + 1, and a stub with only Set() would fail
    -- on that call.
    c.Depth = valueProp(function() return c._depth or 0 end,
                        function(v) c._depth = v end)
    function c:SetSolidColor(v) end
    function c:SetTexture(v) end
    -- SetUV is called right after SetTexture only in the Minimal frame. Other frames have
    -- no backing, but the stub has to support everything the game does.
    function c:SetUV(u0, v0, u1, v1) self._uv = { u0, v0, u1, v1 } end
    function c:SetAlpha(v) self._alpha = v end
    function c:SetColor(v) end
    function c:SetDropShadow(v) end
    function c:SetFont(f, s) self._font = s end
    function c:EnableHitTest(v) end
    function c:DisableHitTest(v) end
    -- In the game Hide() and Show() reach every child too: Show() on the window brings back
    -- the rows the mod hid one by one.
    local function SetHiddenTree(ctl, hidden)
        ctl._hidden = hidden
        for _, child in ipairs(ctl._children) do
            SetHiddenTree(child, hidden)
        end
    end
    function c:Hide() SetHiddenTree(self, true) end
    function c:Show() SetHiddenTree(self, false) end
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
function UIUtil.CreateText(parent, text, size, font)
    local c = NewCtrl('Text', parent)
    c._text = text or ''
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
    w.ClientGroup.Left:Set(function() return w.Left() + 5 * pixelScaleFactor end)
    w.ClientGroup.Right:Set(function() return w.Right() - 5 * pixelScaleFactor end)
    w.ClientGroup.Top:Set(function() return w.Top() + 30 * pixelScaleFactor end)
    w.ClientGroup.Bottom:Set(function() return w.Bottom() - 8 * pixelScaleFactor end)
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
    w._closeBtn.Width:Set(function() return 20 * pixelScaleFactor end)
    w._closeBtn.Height:Set(function() return 20 * pixelScaleFactor end)
    w._closeBtn.Left:Set(function() return w.Right() - 30 * pixelScaleFactor end)
    w._closeBtn.Top:Set(function() return w.Top() + 5 * pixelScaleFactor end)

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
function LayoutHelpers.InvScaleNumber(v) return math.ceil(v / pixelScaleFactor) end
-- ScaleNumber exists in the game: the mod uses it to grow a window to its content limit
-- (ApplyMinSize in ui.lua).
function LayoutHelpers.ScaleNumber(v) return math.floor(v * pixelScaleFactor) end

local Dragger = function()
    return { OnMove = nil, OnRelease = nil, Destroy = function() end }
end
-- The dragger is remembered: otherwise the test could not move the panel with a real mouse
-- drag and check the resize and the width.
LAST_DRAG = nil
-- PostDragger is a game GLOBAL function; ui.lua calls it without import.
function PostDragger(frame, key, drag) LAST_DRAG = drag end

FRAME = {
    Left = function() return 0 end,
    Top = function() return 0 end,
    Width = function() return 1920 end,
    Height = function() return 1080 end,
}
function GetFrame(i) return FRAME end
function GetCursor()
    return { SetTexture = function() end, Reset = function() end }
end

-- ------------------------------------------------------- OptionVar.lua
--
-- A copy of the real one from UMT. The key point: Set changes the value IN MEMORY and does
-- NOT write the profile.
local OptionVarMetaTable = {}
OptionVarMetaTable.__index = OptionVarMetaTable
function OptionVarMetaTable:__call() return self._v end
function OptionVarMetaTable:Set(v) self._v = v self:OnChange() end
function OptionVarMetaTable:Bind(fn) self.OnChange = fn self:OnChange() end
function OptionVarMetaTable:Option() return self._o end
function OptionVarMetaTable:Raw() return self end
function OptionVarMetaTable:Reset() end
function OptionVarMetaTable:OnChange() end
function OptionVarMetaTable:OnSave() end
function OptionVarMetaTable:Save()
    local t = PROFILE[self._m] or {}
    t[self._o] = self._v
    PROFILE[self._m] = t
    self:OnSave()
end
function OptionVar(modName, subOpt, default)
    if default == nil then
        error('Attempt to set option ' .. modName .. ':' .. subOpt ..
              ' to nil by default, dont do that!')
    end
    local t = PROFILE[modName] or {}
    local val = t[subOpt]
    if val == nil then
        t[subOpt] = default
        PROFILE[modName] = t
        val = default
    end
    return setmetatable({ _m = modName, _o = subOpt, _v = val },
                        OptionVarMetaTable)
end

-- --------------------------------------------------------------- Options.lua
PAGES = {}
BUILDS = {}

local OptValueMetaTable = {}
function OptValueMetaTable.IsInstance(v)
    return OptValueMetaTable == getmetatable(v)
end

local Option = {}
function Option.Opt(value)
    return setmetatable({ value = value }, OptValueMetaTable)
end
function Option.AddOptions(optName, title, buildTable)
    PAGES[optName] = { title = title }
    BUILDS[optName] = buildTable
end
function Option.Filter(name, optionVar, indent)
    return { type = 'filter', name = name, optionVar = optionVar,
             indent = indent }
end
function Option.Title(name, size, family, color, indent)
    return { type = 'title', name = name, indent = indent }
end
-- Signature of UMT's Options.Strings: (name, items, optionVar, indent).
function Option.Strings(name, items, optionVar, indent)
    return { type = 'strings', name = name, items = items,
             optionVar = optionVar, indent = indent }
end

local function LoadOptions(values, modName, prefix)
    local options = {}
    for optName, defaultValue in pairs(values) do
        local opt = prefix and (prefix .. '.' .. optName) or optName
        if OptValueMetaTable.IsInstance(defaultValue) then
            options[optName] = OptionVar(modName, opt, defaultValue.value)
        elseif type(defaultValue) == 'table' then
            options[optName] = LoadOptions(defaultValue, modName, opt)
        else
            options[optName] = OptionVar(modName, opt, defaultValue)
        end
    end
    return options
end

local OPTIONS_MAIN = nil
local function LoadOptionsFile(mods, key)
    OPTIONS_MAIN()
    return rawget(mods, key) ~= nil
end

local ModsMeta = {
    __newindex = function(self, key, value)
        rawset(self, key, LoadOptions(value, key))
    end,
    __index = function(self, key)
        if LoadOptionsFile(self, key) then return rawget(self, key) end
        error("No options for mod '" .. key .. "'")
    end,
}
Option.Mods = setmetatable({}, ModsMeta)
UMT = { Options = Option }

-- The UMT slider. Integer values, default 1. The caption and the bounds are kept: the
-- settings page check reads them.
function Option.Slider(name, lo, hi, inc, optionVar, indent)
    return { type = 'slider', name = name, optionVar = optionVar,
             min = lo, max = hi, inc = inc, indent = indent or 0 }
end

-- what was imported and when: the settings page must not touch ui.lua
IMPORTED = {}

-- ------------------------------------------------------- The whole UMT chain
--
-- DiskFindFiles returns what would be found on disk. The match is case-insensitive, so the
-- same key is entered with two spellings of the folder: on disk the folder is lower case,
-- while UMT searches by the mod key. This is how the game finds
-- '/mods/ase/modules/options.lua' for the query '/mods/ASE/'.
FOUND_ON_DISK = {
    ['/mods/overflow/|Main.lua']    = { '/mods/overflow/modules/main.lua' },
    ['/mods/overflow/|Options.lua'] = { '/mods/overflow/modules/Options.lua' },
    ['/mods/Overflow/|Options.lua'] = { '/mods/overflow/modules/Options.lua' },
}

function DiskFindFiles(dir, filename)
    local hit = FOUND_ON_DISK[dir .. '|' .. filename]
    if hit then return hit end
    return {}
end

-- UMT:Add, copied verbatim from UMT.
UMT_MODS = {}
function UMT.Add(name) UMT_MODS[name] = true end

-- UMT:Load, copied verbatim from UMT.
function UMT.Load(isReplay)
    for mod in pairs(UMT_MODS) do
        local files = DiskFindFiles('/mods/' .. mod .. '/', 'Main.lua')
        for _, file in pairs(files) do
            LOG('UMT: Loading file ' .. file)
            import(file).Main(isReplay)
        end
    end
end

-- The real sync.lua is needed for the check that incoming is zeroed while the storage is
-- full. It takes these functions as GLOBALS when it loads, so the declarations must exist
-- BEFORE the module loads, otherwise all of them are nil.
TICK = 0
INCOME_E = 0
INCOME_M = 0
function GameTick() return TICK end
function GetSimTicksPerSecond() return 10 end
function GetEconomyTotals()
    return { income = { ENERGY = INCOME_E, MASS = INCOME_M } }
end
function IsAlly(me, armyIdx) return armyIdx ~= me end

-- sync.lua calls GetFocusArmy on EVERY payload. Without this stub sync.lua would collect
-- three errors in a row and remove its own callback, and the test would then fail with
-- "attempt to call global 'SCORE_CB' (a nil value)".
function GetFocusArmy() return 1 end

SCORE_CB = nil
function AddOnSyncHashedCallback(cb, event, id) SCORE_CB = cb end
function RemoveOnSyncHashedCallback(event, id) SCORE_CB = nil end

-- Stub of sync.lua. ui.lua reads its fields through rawget, so it has to be a table with
-- fields, not a set of globals.
SYNCSTUB = {
    started = false,
    Start = function()
        SYNCSTUB.started = true
        return true
    end,
    GetResult = function()
        if SYNC_BROKEN then error('sync is broken') end
        return {
            ok = true,
            incoming = 100, outgoing = 20, own = 200,
            massIncoming = 0, massOutgoing = 30, massOwn = 300,
            reclaim = 5, massReclaim = 6,
        }
    end,
}

function import(p)
    IMPORTED[table.getn(IMPORTED) + 1] = p
    if p == '/lua/user/prefs.lua' then return Prefs end
    if p == '/lua/ui/uiutil.lua' then return UIUtil end
    if p == '/lua/maui/bitmap.lua' then return { Bitmap = Bitmap } end
    if p == '/lua/maui/group.lua' then return { Group = Group } end
    if p == '/lua/maui/layouthelpers.lua' then return LayoutHelpers end
    if p == '/lua/maui/dragger.lua' then return { Dragger = Dragger } end
    if p == '/lua/maui/window.lua' then return { Window = NewWindow } end
    if p == '/lua/ui/game/gamemain.lua' then return GameMainStub end
    if p == '/mods/Overflow/modules/rows.lua' then return MODULES.rows end
    if p == '/mods/Overflow/modules/sync.lua' then return SYNCSTUB end
    if p == '/mods/Overflow/modules/themes.lua' then return MODULES.themes end
    if p == '/lua/skins/skins.lua' then return { skins = SKINS } end
    if p == '/mods/Overflow/modules/ui.lua' then return MODULES.ui end
    -- these two paths come from DiskFindFiles, i.e. from the UMT stub itself
    if p == '/mods/overflow/modules/main.lua' then return MODULES.main end
    if p == '/mods/overflow/modules/Options.lua' then return MODULES.options end
    return {}
end
end

MODULES = {}

-- The gamemain stub MUST exist BEFORE ui.lua loads. ui.lua runs `local GameMain =
-- import('/lua/ui/game/gamemain.lua')` at load time. Declared later, the stub would give
-- nil and OnCreateUI would fail inside pcall: the panel would be created, but the game beat
-- would not be subscribed.
GameMainStub = {
    AddBeatFunction = function(f, throttle, id) BEAT = f end,
    RemoveBeatFunction = function(f, id)
        BEAT_REMOVED = f == BEAT
        BEAT = function() end
    end,
}
BEAT = nil
BEAT_REMOVED = false

local env_rows = MakeEnv()
LoadInto(MOD .. 'rows.lua', env_rows)
MODULES.rows = env_rows
ROWS = env_rows

-- Loaded BEFORE ui.lua and Options.lua: both import themes.lua, and import runs as soon as
-- a module loads. If the themes are not loaded, ui.lua stays with its built-in colours and
-- Options.lua leaves Main() early.
local env_themes = MakeEnv()
LoadInto(MOD .. 'themes.lua', env_themes)
MODULES.themes = env_themes
THEMES = env_themes

local env_ui = MakeEnv()
LoadInto(MOD .. 'ui.lua', env_ui)
MODULES.ui = env_ui
U = env_ui

local env_opt = MakeEnv()
LoadInto(MOD .. 'Options.lua', env_opt)
MODULES.options = env_opt
OPTIONS_MAIN = env_opt.Main

-- the real sync.lua for the test
local env_sync_real = MakeEnv()
LoadInto(MOD .. 'sync.lua', env_sync_real)
SYNC = env_sync_real

-- The shim may be missing: that is then a failure, and the test has to go red with a clear
-- message instead of crashing on opening the file.
local env_main = MakeEnv()
local shim = io.open(MOD .. 'main.lua', 'rb')
if shim then
    shim:close()
    LoadInto(MOD .. 'main.lua', env_main)
end
MODULES.main = env_main

local f1 = Run("=== 1: rows.lua, выбор строк ===", function()
local fails = 0
local function check(cond, label)
    if cond then
        print('  [OK  ] ' .. label)
    else
        fails = fails + 1
        print('  [FAIL] ' .. label)
    end
end

local BOXES = { 'eOverflow', 'eGo', 'eOwn', 'mOverflow', 'mGo', 'mOwn',
                'total' }

check(ROWS.HowManyRows() == 7, 'строк ровно семь (получено ' ..
      tostring(ROWS.HowManyRows()) .. ')')

local orderOk = true
for i = 1, table.getn(BOXES) do
    if ROWS.RowKeyAt(i) ~= BOXES[i] then orderOk = false end
end
check(orderOk, 'порядок строк совпадает с порядком на панели')

-- Compatibility: there is no profile yet. The panel must show the default set
-- from the mod, otherwise it would disappear after a mod update for everyone
-- who never opened the settings.
PROFILE['Overflow'] = nil
local def = ROWS.RowDefaults()
local vis = ROWS.VisibleRows()
local asDefault = true
local anyOn = false
for i = 1, table.getn(BOXES) do
    if vis[BOXES[i]] ~= def[BOXES[i]] then asDefault = false end
    if def[BOXES[i]] then anyOn = true end
end
check(asDefault, 'без настроек видны строки по умолчанию')
check(anyOn, 'по умолчанию видна хотя бы одна строка')

-- "No field" and "field = false" are DIFFERENT things. The first means "use the default".
PROFILE['Overflow'] = { eOverflow = false }
vis = ROWS.VisibleRows()
check(vis.eOverflow == false, 'явно снятая строка скрыта')
check(vis.eGo == def.eGo and vis.mGo == def.mGo and vis.total == def.total,
      'отсутствующие поля читаются как значение по умолчанию, а не как «скрыть»')

-- A write must not overwrite other fields of the same profile entry: UMT uses it.
PROFILE['Overflow'] = { preset = 'Все строки', eOverflow = true }
vis = {}
for i = 1, table.getn(BOXES) do vis[BOXES[i]] = (BOXES[i] == 'eGo') end
check(ROWS.SaveRows(vis) == true, 'SaveRows сообщил об успехе')
check(PROFILE['Overflow'].preset == 'Все строки',
      'SaveRows не затёр поле preset, принадлежащее UMT')
check(PROFILE['Overflow'].eGo == true and PROFILE['Overflow'].eOverflow == false,
      'SaveRows записал именно переданные флаги')

-- The signature of a set: the panel compares it with its own and re-applies the geometry
-- only when it changes. It has to tell different sets apart.
local sigAll = ROWS.RowsSignature({ eOverflow = true, eGo = true,
    eOwn = true, mOverflow = true, mGo = true, mOwn = true, total = true })
local sigOne = ROWS.RowsSignature({ eOverflow = true, eGo = false,
    eOwn = false, mOverflow = false, mGo = false, mOwn = false, total = false })
check(sigAll ~= sigOne, 'подпись набора различает два разных набора')
check(ROWS.RowsSignature({ eOverflow = true, eGo = true, eOwn = true,
    mOverflow = true, mGo = true, mOwn = true, total = true }) == sigAll,
      'подпись одного и того же набора стабильна')

-- Every ready-made set has to expand and collapse without loss.
local names = ROWS.PresetNames()
local hasAllRows = false
for i = 1, table.getn(names) do
    if names[i] == 'Все строки' then hasAllRows = true end
end
check(hasAllRows, 'в списке есть набор «Все строки»')
local bad = ''
for i = 1, table.getn(names) do
    local label = names[i]
    if label ~= ROWS.PresetOther() then
        local flags = ROWS.PresetByName(label)
        if flags == nil then
            bad = bad .. label .. '(nil) '
        elseif ROWS.PresetFor(flags) ~= label then
            bad = bad .. label .. '(round-trip) '
        end
    end
end
check(bad == '', 'каждый набор разворачивается и сворачивается сам в себя' ..
      (bad == '' and '' or (' НАРУШЕНО: ' .. bad)))

-- The service item is not a set: it must not expand, otherwise a click on it would clear
-- all check boxes.
check(ROWS.PresetByName(ROWS.PresetOther()) == nil,
      'служебный «Другой набор» не разворачивается в набор')

-- An empty set has to match "show nothing", not the service item.
local empty = {}
for i = 1, table.getn(BOXES) do empty[BOXES[i]] = false end
check(ROWS.PresetFor(empty) == 'Ничего не показывать',
      'пустой набор опознан как «Ничего не показывать», а не как служебный')

-- A set that is not in the list has to give nil.
local odd = { eOverflow = true, eGo = true, eOwn = false, mOverflow = false,
              mGo = false, mOwn = true, total = true }
check(ROWS.PresetFor(odd) == nil,
      'нестандартная комбинация не опознана ни за один набор (nil)')

-- RULE: the first set has to equal the default value, otherwise UMT silently rewrites it
-- and saves the result.
local first = ROWS.PresetNames()[1]
local firstFlags = ROWS.PresetByName(first)
local defMatch = true
for i = 1, table.getn(BOXES) do
    if (def[BOXES[i]] and true or false) ~= (firstFlags[BOXES[i]] and true or false) then
        defMatch = false
    end
end
check(defMatch, 'первый набор списка совпадает со значением по умолчанию')

-- Row names for the settings window: each row needs its own, otherwise the check boxes
-- would be unnamed or carry another row's caption.
local noTitle = ''
for i = 1, table.getn(BOXES) do
    local t = ROWS.RowTitleOf(BOXES[i])
    if type(t) ~= 'string' or t == '' then noTitle = noTitle .. BOXES[i] .. ' ' end
end
check(noTitle == '', 'у каждой строки есть название для окна настроек' ..
      (noTitle == '' and '' or (' НЕТ: ' .. noTitle)))

return fails
end)

print('')
local f2 = Run("=== 2: Options.lua, страница настроек ===", function()
local fails = 0
local function check(cond, label)
    if cond then
        print('  [OK  ] ' .. label)
    else
        fails = fails + 1
        print('  [FAIL] ' .. label)
    end
end

local BOXES = { 'eOverflow', 'eGo', 'eOwn', 'mOverflow', 'mGo', 'mOwn',
                'total' }

-- A clean profile. It cannot be cleared through Mods[]: __newindex fires for nil too, and
-- LoadOptions(nil) would fail. Only rawset.
PROFILE['Overflow'] = nil
rawset(UMT.Options.Mods, 'Overflow', nil)
IMPORTED = {}

local okPage, errPage = pcall(OPTIONS_MAIN)
check(okPage, 'Main() страницы отработал без исключения' ..
      (okPage and '' or (': ' .. tostring(errPage))))
if not okPage then return fails end

-- LOAD ORDER. The page must NOT import ui.lua: it is not known whether UMT loads before the
-- game interface or after, and the import could catch a module that has not finished
-- running.
local touchedUi = false
for i = 1, table.getn(IMPORTED) do
    if IMPORTED[i] == '/mods/Overflow/modules/ui.lua' then touchedUi = true end
end
check(not touchedUi, 'страница НЕ импортирует ui.lua (порядок загрузки)')

local opts = UMT.Options.Mods['Overflow']
check(opts ~= nil, 'страница зарегистрирована в UMT.Options.Mods')
check(BUILDS['Overflow'] ~= nil, 'окно создано через AddOptions')

local build = BUILDS['Overflow']
if build == nil then return fails + 1 end

local boxesOk = true
for i = 1, table.getn(BOXES) do
    local v = opts[BOXES[i]]
    if v == nil or type(v.Bind) ~= 'function' then boxesOk = false end
end
check(boxesOk, 'все семь строк - OptionVar с методом Bind')
check(opts.preset ~= nil and type(opts.preset.Bind) == 'function',
      'выпадающий список - OptionVar с методом Bind')

-- Each check box has to be bound to its OWN field, otherwise a click on it would change
-- another one.
local mismatched = ''
local filters = 0
local stringsLine = nil
local themeLine = nil
for i = 1, table.getn(build) do
    local line = build[i]
    if line.type == 'filter' then
        filters = filters + 1
        local nm = line.optionVar:Option()
        if line.optionVar ~= opts[nm] then mismatched = nm .. ' ' end
    elseif line.type == 'strings' then
        -- There are two lists: the theme and the row sets. Both are remembered, otherwise
        -- the theme binding check would pass without looking at anything.
        --
        -- The marker is themeLine, not stringsLine: the first branch is taken before
        -- stringsLine gets anything, so a `stringsLine == nil` test would stay true
        -- forever.
        if themeLine == nil then themeLine = line else stringsLine = line end
    end
end
-- The blink switch is the same Filter type as the row check boxes, so the binding check
-- below covers it too.
check(filters == 9, 'в окне девять галочек: семь строк, мигание и только числа (получено ' ..
      tostring(filters) .. ')')
check(mismatched == '', 'каждая галочка привязана к своему полю' ..
      (mismatched == '' and '' or (': ' .. mismatched)))
-- Check not only equality but WHAT is equal. Otherwise the check passes as nil == nil: drop
-- `theme = Opt(looks[1])` from the field declaration and the page still builds as usual,
-- which is exactly how the player would see it.
check(stringsLine ~= nil and stringsLine.optionVar ~= nil
      and stringsLine.optionVar == opts.preset,
      'выпадающий список привязан к полю preset')
check(themeLine ~= nil and themeLine.optionVar ~= nil
      and opts.theme ~= nil and themeLine.optionVar == opts.theme,
      'выпадающий список оформления привязан к полю theme')
check(stringsLine ~= nil and stringsLine.items ~= nil and
      stringsLine.items[1] == opts.preset(),
      'текущее значение списка есть среди его пунктов - иначе UMT молча ' ..
      'перепишет его первым пунктом и сохранит')
check(opts.preset() == ROWS.PresetNames()[1],
      'значение списка по умолчанию - первый набор')

-- Simulate the player choosing the preset that shows only E ally overflow. Set keeps the
-- value in memory and does NOT write the profile, so if the page reads the profile, the mod
-- sees the old value.
opts.preset:Set('Только E ally overflow')

local prof = PROFILE['Overflow']
check(prof.eOverflow == true, 'после выбора набора видна E ally overflow')
check(prof.eGo == false and prof.eOwn == false and prof.mOverflow == false
      and prof.mGo == false and prof.mOwn == false and prof.total == false,
      'остальные шесть строк сняты, как просил игрок')

-- The mod reads the profile, and the page has to write there what it showed in the check
-- boxes. Any mismatch means the mod sees something other than the player.
local liveMismatch = ''
for i = 1, table.getn(BOXES) do
    if (opts[BOXES[i]]() and true or false) ~= (prof[BOXES[i]] and true or false) then
        liveMismatch = liveMismatch .. BOXES[i] .. ' '
    end
end
check(liveMismatch == '',
      'профиль и живое значение OptionVar совпадают по всем семи строкам' ..
      (liveMismatch == '' and '' or (': расход ' .. liveMismatch)))

-- Now the player sets a check box by hand. The preset list has to stop lying.
opts.mGo:Set(true)
check(opts.preset() == ROWS.PresetOther(),
      'после ручной правки список показывает «Другой набор», а не прежний')
check(PROFILE['Overflow'].mGo == true, 'ручная галочка дошла до профиля')

-- Back to a ready-made set.
opts.preset:Set('Все строки')
local raised = true
for i = 1, table.getn(BOXES) do
    if opts[BOXES[i]]() ~= true then raised = false end
end
check(raised, 'набор «Все строки» поднял обратно все семь галочек')
check(PROFILE['Overflow'].total == true, 'и записал это в профиль')

local joined = table.concat(msgs, ' | ')
check(string.find(joined, 'UMT options page registered') ~= nil,
      'страница отписалась в лог, что зарегистрирована')
check(string.find(joined, 'FAILED') == nil, 'в логе нет ни одной строки FAILED')

return fails
end)

print('')
local f3 = Run("=== 3: ui.lua, раскладка под выбранные строки ===", function()
local fails = 0
local function check(cond, label)
    if cond then
        print('  [OK  ] ' .. label)
    else
        fails = fails + 1
        print('  [FAIL] ' .. label)
    end
end

-- Captions that Render keeps on screen. It is called from Update, i.e. from the game beat.
-- This is how we learn which rows the panel shows.
local CAPTIONS = {
    eOverflow = 'E ally overflow: 100.0 E/s',
    eGo       = 'E to allies: 20.0 E/s',
    eOwn      = 'E own production: 200.0 E/s',
    mOverflow = 'M ally overflow: 0.0 M/s',
    mGo       = 'M to allies: 30.0 M/s',
    mOwn      = 'M own production: 300.0 M/s',
    total     = 'reclaim E 5.0 / M 6.0 /s',
}
local CHROME = { ['Overflow'] = 1, ['x'] = 1, ['-'] = 1, ['+'] = 1,
                 ['100%'] = 1 }

local function shownCaptions()
    local out = {}
    for i = 1, table.getn(MADE) do
        local c = MADE[i]
        if c._kind == 'Text' and not c._hidden and c._text ~= '' then
            out[c._text] = c
        end
    end
    return out
end

-- How many data rows are on screen: data captions minus the header captions.
local function shownData()
    local n = 0
    for txt, _ in pairs(shownCaptions()) do
        if CHROME[txt] == nil then n = n + 1 end
    end
    return n
end

local function shownDividers()
    local n = 0
    for i = 1, table.getn(MADE) do
        local c = MADE[i]
        if c._kind == 'Bitmap' and not c._hidden and c._h == 1 then
            n = n + 1
        end
    end
    return n
end

local function setRows(flags)
    local vis = {}
    for k, v in pairs(flags) do vis[k] = v end
    ROWS.SaveRows(vis)
    if BEAT then BEAT() end
end

-- The layout is checked on the full set, so the test enables all seven rows
-- itself: the default set of the mod is shorter.
PROFILE['Overflow'] = nil
local allRows = {}
for i = 1, ROWS.HowManyRows() do allRows[ROWS.RowKeyAt(i)] = true end
ROWS.SaveRows(allRows)
local okUi, errUi = pcall(U.OnCreateUI)
check(okUi, 'OnCreateUI отработал без исключения' ..
      (okUi and '' or (': ' .. tostring(errUi))))
if not okUi then return fails end
check(SYNCSTUB.started, 'sync.lua получил команду Start')

-- Look for the WINDOW, not a group: the panel is built as a 'Window' container.
local panel = nil
for i = 1, table.getn(MADE) do
    if MADE[i]._kind == 'Window' then panel = MADE[i] end
end
check(panel ~= nil, 'окно создано')

if BEAT then BEAT() end

local t = shownCaptions()
check(t[CAPTIONS.eOverflow] ~= nil, 'на экране строка E ally overflow')
check(t[CAPTIONS.eGo] ~= nil, 'на экране строка E to allies')
check(t[CAPTIONS.total] ~= nil, 'на экране строка реклейма')
check(shownData() == 7, 'на экране все семь строк (строк данных: ' ..
      tostring(shownData()) .. ')')
local hSeven = panel and panel._h or -1
check(hSeven > 0, 'при семи строках высота окна положительная (получено ' ..
      tostring(hSeven) .. ')')
check(shownDividers() == 2, 'при всех строках на месте оба разделителя (' ..
      tostring(shownDividers()) .. ')')

-- The main case: one row is left.
setRows({ eOverflow = true })
t = shownCaptions()
check(t[CAPTIONS.eOverflow] ~= nil, 'при одной строке E ally overflow осталась')
check(shownData() == 1,
      'больше на экране ничего нет (строк данных: ' .. tostring(shownData()) .. ')')
local hOne = panel and panel._h or -1
check(hOne < hSeven,
      'с одной строкой окно должно быть ниже, чем с семью: ' ..
      tostring(hOne) .. ' против ' .. tostring(hSeven))
check(shownDividers() == 0,
      'над одиночной строкой не осталось разделителя (найдено: ' ..
      tostring(shownDividers()) .. ')')

-- Show nothing: the panel is as tall as the header.
setRows({})
check(shownData() == 0,
      'при пустом наборе строк данных на экране нет (строк: ' ..
      tostring(shownData()) .. ')')
local hNone = panel and panel._h or -1
check(hNone <= hOne,
      'при пустом наборе окно должно быть не выше окна с одной строкой: ' ..
      tostring(hNone) .. ' против ' .. tostring(hOne))

-- Back to the full set, then the coordinates.
setRows({ eOverflow = true, eGo = true, eOwn = true, mOverflow = true,
          mGo = true, mOwn = true, total = true })
t = shownCaptions()
local allSeven = true
for k, _ in pairs(CAPTIONS) do
    if t[CAPTIONS[k]] == nil then allSeven = false end
end
check(allSeven, 'после возврата все семь строк на месте')
check(panel._h == hSeven,
      'после возврата всех строк высота окна вернулась (' ..
      tostring(panel._h) .. ' против ' .. tostring(hSeven) .. ')')

-- The row coordinate is taken by CALLING Top(): the layout binds it with a function to the
-- ClientGroup of the window, so the _y field holds nothing.
local function y(cap)
    local c = t[cap]
    if not c then return -1 end
    if c.Top then return c.Top() end
    return c._y
end
local ys = { y(CAPTIONS.eOverflow), y(CAPTIONS.eGo), y(CAPTIONS.eOwn),
             y(CAPTIONS.mOverflow), y(CAPTIONS.mGo), y(CAPTIONS.mOwn),
             y(CAPTIONS.total) }
-- Check the STEP and the ORDER, not absolute coordinates. The rows are bound to the
-- ClientGroup of the window by functions, so their Y depends on the position of the window
-- on the screen and changes with a resize. Only the top-to-bottom order and the step
-- between neighbours stay fixed (L.ROW_STEP = 14).
--
-- The step is checked within a resource: before the divider it is always 14, and after the
-- divider DIV_POST is added, so a step of 18 there is intended.
local ROW_STEP = 14
local coordOk = true
local got = ''
for i = 1, 7 do
    got = got .. ys[i] .. ' '
    -- `i > 1` comes first: `ys[i] <= ys[i-1] and i > 1` would fail on the first element,
    -- because Lua evaluates the operands left to right and reaches the comparison with nil
    -- before the i > 1 test.
    if i > 1 and ys[i] <= ys[i - 1] then coordOk = false end
end
check(coordOk, 'строки идут сверху вниз без наложений (' .. got .. ')')

local stepOk = true
for _, i in pairs({ 1, 2, 4, 5 }) do
    if ys[i + 1] - ys[i] ~= ROW_STEP then stepOk = false end
end
check(stepOk, 'шаг между строками внутри ресурса одинаковый (' ..
      (ys[2] - ys[1]) .. ', ' .. (ys[5] - ys[4]) .. ')')

-- The divider has to stand between the resources and push the second row away.
check(ys[4] - ys[3] > ROW_STEP,
      'разделитель раздвигает второй ресурс (' .. (ys[4] - ys[3]) .. ')')

-- Resize belongs to the Window class, so the checks are that the window is built as
-- expected and handles resize and close. The minimum size, checked further below, keeps a
-- resize from dragging the window down to zero together with its captions.
check(panel ~= nil, 'окно на месте после всех проверок')
check(panel ~= nil and panel.OnResize ~= nil,
      'у окна есть обработчик ресайза')
check(panel ~= nil and panel.OnClose ~= nil,
      'у окна есть обработчик закрытия - он сворачивает панель')

-- HEIGHT SET BY THE PLAYER. Rule: once the player drags the window edge, the height is
-- remembered and the fit to content no longer trims it; moving the window does not change
-- the height.
--
-- The sequence: the player stretches the window, then something knocks the height down, and
-- after a move it has to come back.
if panel ~= nil and panel.OnResizeSet and panel.OnMoveSet then
    panel._h = 250
    panel.OnResizeSet(panel)
    check(panel._h == 250,
          'после ресайза высота игрока запомнена (' .. tostring(panel._h) .. ')')

    -- Simulate what the class does on a move: it resets the height.
    panel._h = 90
    check(panel._h == 90, 'сброс высоты действительно произошёл (проверка замкнута)')

    panel.OnMoveSet(panel)
    check(panel._h == 250,
          'после переноса высота игрока вернулась, а не осталась сбитой (' ..
          tostring(panel._h) .. ')')
end

-- TITLE STRIP, CLOSE BUTTON AND SIZE LIMIT
--
-- 1. The Window class ALWAYS creates an EMPTY 30 px title strip, even when no title is
-- passed. The rows have to start at the top of the window, not below that strip: in a 52 px
-- window thirty pixels would be empty, while three rows need 40, and the text would stick
-- out of the frame.
--
-- 2. The width limit has to follow the text, not be a fixed number such as 200: the panel
-- has to shrink when the text is noticeably shorter than the window.

check(panel.ClientGroup.Top() == panel.Top(),
      'строки начинаются от ВЕРХА окна, а не под пустой полосой заголовка (' ..
      'ClientGroup.Top = ' .. tostring(panel.ClientGroup.Top()) ..
      ', Top окна = ' .. tostring(panel.Top()) .. ')')

check(panel.TitleGroup ~= nil
      and panel.TitleGroup.Height() == panel.Bottom() - panel.Top(),
      'полоса заголовка растянута на всё окно, иначе окно не сдвинуть (' ..
      tostring(panel.TitleGroup and panel.TitleGroup.Height()) .. ')')

-- CLOSE BUTTON. It hangs in the top-right corner of the window and overlaps the UPPER rows:
-- no empty strip separates them. So the row under it is indented to the right more than the
-- lower ones.
local function ctrlFor(text)
    for i = 1, table.getn(MADE) do
        local c = MADE[i]
        if c._kind == 'Text' and c._text == text then return c end
    end
    return nil
end

local function setAllSeven()
    setRows({ eOverflow = true, eGo = true, eOwn = true, mOverflow = true,
              mGo = true, mOwn = true, total = true })
end

setAllSeven()
local topRow = ctrlFor(CAPTIONS.eOverflow)
local lowRow = ctrlFor(CAPTIONS.eOwn)
check(topRow ~= nil and lowRow ~= nil and topRow.Right() < lowRow.Right(),
      'верхняя строка отступает под крестик сильнее нижних (верх ' ..
      tostring(topRow and topRow.Right()) .. ', низ ' ..
      tostring(lowRow and lowRow.Right()) .. ')')

-- SIZE LIMIT. The mod has to tell the window a limit based on the CONTENT: without it the
-- window shrinks to 52 px and the text goes past the frame.
--
-- MINSIZE is reset before each measurement and the ROW SET is changed between them: the
-- limit is computed in LayoutRows when the set changes, so the measurement shows the work
-- of the mod, not a value left from the previous time.
MINSIZE = nil
setRows({ eGo = true })
local one = MINSIZE
MINSIZE = nil
setAllSeven()
local all = MINSIZE
check(all ~= nil and all[1] > 0 and all[2] > 0,
      'мод сообщил окну предел размера (' .. tostring(all and all[1]) ..
      ' x ' .. tostring(all and all[2]) .. ')')

-- Seven rows are 8 + 7*14 - 14 + 4 = 96 px for text plus 8 px of the bottom frame. A limit
-- below 96 would mean the text does not fit.
check(all ~= nil and all[2] >= 96,
      'предел высоты не меньше, чем нужно семи строкам (' ..
      tostring(all and all[2]) .. ')')

check(one ~= nil and all ~= nil and one[2] < all[2],
      'предел ВЫСОТЫ считается по числу строк: с одной строкой он ниже (' ..
      tostring(one and one[2]) .. ' против ' .. tostring(all and all[2]) .. ')')
-- The caption 'E to allies: 20.0 E/s' is SHORTER than 'E own production: 200.0 E/s', so the
-- width limit has to be smaller. A fixed number would not show this: both measurements
-- would be equal.
check(one ~= nil and all ~= nil and one[1] < all[1],
      'предел ШИРИНЫ считается ПО ТЕКСТУ, а не задан числом: с одной ' ..
      'короткой строкой он меньше (' .. tostring(one and one[1]) ..
      ' против ' .. tostring(all and all[1]) .. ')')

-- Back to the full set: the collapse checks follow.
setAllSeven()

-- ROWS SPREAD OVER THE PANEL HEIGHT.
--
-- The taller the panel, the larger the gaps between the rows. The gaps share the REMAINING
-- space equally, so the bottom row always sits exactly on the bottom margin and the top row
-- stays at the top edge.
--
-- The check follows the Window class: the new size is set first, then OnResize is called.
--
-- The height is set as a NUMBER, not through the fit: by this point G.wantH has already
-- been set by the move check above, and the "natural" height is not natural here. With a
-- number the layout is predictable.
setAllSeven()
local row1 = ctrlFor(CAPTIONS.eOverflow)
local rowN = ctrlFor(CAPTIONS.total)

-- The divider is found by its PARENT, not by height: the frame pieces of the window are
-- Bitmaps too, and Height alone does not tell them from the divider.
local div1 = nil
for i = 1, table.getn(MADE) do
    local c = MADE[i]
    if c._kind == 'Bitmap' and c._parent == panel.ClientGroup then
        if div1 == nil or c.Top() < div1.Top() then div1 = c end
    end
end

check(row1 ~= nil and rowN ~= nil,
      'строки нашлись для проверки растяжения')

if row1 ~= nil and rowN ~= nil then
    -- BOTTOM MARGIN. The mod has its own number (PAD_BOTTOM); the test repeats it so that
    -- the check is about the distribution, not about itself.
    local PAD_BOTTOM = 4

    local function bottomRow()
        return rowN.Top() + 14
    end

    local function byBottom()
        return panel.ClientGroup.Bottom() - PAD_BOTTOM
    end

    local function measure(h)
        panel._h = h
        panel.OnResize(panel)
        return row1.Top(), rowN.Top()
    end

    local r1a, rNa = measure(300)
    local d1a = -1
    if div1 ~= nil then d1a = div1.Top() end

    check(r1a == panel.ClientGroup.Top() + 8,
          'верхняя строка остаётся у верхнего края панели (' ..
          tostring(r1a) .. ' при крае ' .. tostring(panel.ClientGroup.Top()) .. ')')
    check(math.abs(bottomRow() - byBottom()) <= 1,
          'нижняя строка встаёт по нижнему полю панели (низ строки ' ..
          tostring(bottomRow()) .. ', поле ' .. tostring(byBottom()) .. ')')

    -- Stretch further: the gaps have to grow and the bottom of the row has to land on the
    -- margin again. This tells a distribution from "shift the whole block down".
    local r1b, rNb = measure(400)
    local d1b = -1
    if div1 ~= nil then d1b = div1.Top() end

    check(r1b == r1a,
          'верхняя строка не съезжает и на большей высоте (' ..
          tostring(r1a) .. ' -> ' .. tostring(r1b) .. ')')
    check(rNb > rNa,
          'нижняя строка уезжает вниз вместе с растяжением панели (' ..
          tostring(rNa) .. ' -> ' .. tostring(rNb) .. ')')
    check(math.abs(bottomRow() - byBottom()) <= 1,
          'и на большей высоте низ строки ложится по нижнему полю (' ..
          tostring(bottomRow()) .. ' против ' .. tostring(byBottom()) .. ')')
    check(div1 ~= nil and d1b > d1a,
          'разделитель едет вместе со строками (' ..
          tostring(d1a) .. ' -> ' .. tostring(d1b) .. ')')

    -- And back: the previous height has to give the previous layout, otherwise the panel
    -- "remembers" the stretch after the player has returned it.
    local r1c, rNc = measure(300)
    check(r1c == r1a and rNc == rNa,
          'при возврате прежней высоты раскладка возвращается (' ..
          tostring(rNc) .. ' против ' .. tostring(rNa) .. ')')

    -- CHANGING THE ROW SET ALSO CHANGES THE PANEL HEIGHT, and does it AFTER the layout
    -- (FitHeight is called from ApplyLayout below). The positions depend on the height, so
    -- they have to be recomputed after the fit too: without a second pass a short set would
    -- be spread over the old, large height and the rows would go past the panel edge.
    setRows({ eOwn = true, mOverflow = true })
    local pair2 = ctrlFor(CAPTIONS.mOverflow)
    check(pair2 ~= nil,
          'вторая строка пары нашлась для проверки подгонки высоты')
    if pair2 ~= nil then
        check(pair2.Top() + 14 <= panel.ClientGroup.Bottom(),
              'после смены набора строк строки остаются ВНУТРИ панели (низ ' ..
              'строки ' .. tostring(pair2.Top() + 14) .. ', низ окна ' ..
              tostring(panel.ClientGroup.Bottom()) .. ')')
    end
    setAllSeven()
end

-- COLLAPSING. BODY_KEYS has to contain eGo and mGo: otherwise the "to allies" rows do not
-- get Hide() and hang under the collapsed header, because a Group in the game does not clip
-- its children.
--
-- There is no "-" button: collapsing is closing the window, as with the minimap. So the
-- check is on the RESULT: the panel hides and comes back, and the rows are taken off the
-- screen.
if panel ~= nil and panel.OnClose then
    local hiddenBefore = panel._hidden
    panel.OnClose(panel)
    check(panel._hidden == true,
          'после закрытия окно спрятано, а не просто сжато')
    check(shownData() == 0,
          'в свёрнутом виде строк данных на экране нет (их ' ..
          tostring(shownData()) .. ')')

    -- Return: as with the minimap, the panel is reopened by the "Overflow" button.
    local reopen = nil
    for i = 1, table.getn(MADE) do
        if MADE[i]._kind == 'Bitmap' and MADE[i]._parent ~= panel
            and MADE[i]._parent ~= panel.ClientGroup then
            reopen = MADE[i]
        end
    end
    check(reopen ~= nil, 'кнопка возврата панели создана вне окна')
    if reopen ~= nil then
        reopen.HandleEvent(reopen, { Type = 'ButtonRelease' })
        check(panel._hidden == false,
              'после возврата окно снова показано (было скрыто: ' ..
              tostring(hiddenBefore) .. ')')
        check(shownData() == 7,
              'после возврата все семь строк на месте (' ..
              tostring(shownData()) .. ')')

        -- The default set: five rows and both dividers are hidden one by one, and Show()
        -- on the window would bring them back. The set also changes while collapsed.
        setRows({ eOverflow = true, eGo = true })
        panel.OnClose(panel)
        setRows({ eOverflow = true, eGo = true, eOwn = true })
        check(shownData() == 0 and shownDividers() == 0,
              'смена набора в свёрнутом виде ничего не показывает (строк ' ..
              tostring(shownData()) .. ', разделителей ' .. tostring(shownDividers()) .. ')')
        reopen.HandleEvent(reopen, { Type = 'ButtonRelease' })
        check(shownData() == 3 and shownDividers() == 0,
              'после возврата видны только три включённые строки (строк ' ..
              tostring(shownData()) .. ', разделителей ' .. tostring(shownDividers()) .. ')')
        setAllSeven()
    end
end

local joined = table.concat(msgs, ' | ')
check(string.find(joined, 'FAILED') == nil, 'в логе нет ни одной строки FAILED')

return fails
end)

print('')
local f4 = Run("=== 4: модули отдают всё, что мод вызывает ===", function()
local fails = 0
local function check(cond, label)
    if cond then
        print('  [OK  ] ' .. label)
    else
        fails = fails + 1
        print('  [FAIL] ' .. label)
    end
end

-- If a function of a module is renamed and a call is forgotten, the access gives nil: the
-- loop `for i = 1, nil` runs zero times, the table stays empty, and the page fails later,
-- on Opt(nil).
local NEEDS = {
  ROWS = { 'HowManyRows', 'RowKeyAt', 'RowTitleOf', 'RowDefaults',
           'PresetNames', 'PresetFor', 'PresetOther', 'PresetByName',
           'VisibleRows', 'SaveRows', 'RowsSignature', 'DescribeRows' },
  SYNCSTUB = { 'Start', 'GetResult' },
}
local absent = ''
for modName, fns in pairs(NEEDS) do
    local mod = modName == 'ROWS' and ROWS or SYNCSTUB
    for i = 1, table.getn(fns) do
        if type(mod[fns[i]]) ~= 'function' then
            absent = absent .. modName .. '.' .. fns[i] .. ' '
        end
    end
end
check(absent == '', 'у модулей есть все функции, которые мод вызывает' ..
      (absent == '' and '' or (' НЕТ: ' .. absent)))

-- The engine discards the value of return, so exports go through globals.
check(U.ReapplyRows == nil,
      'ui.lua никуда не экспортирует ReapplyRows: применение делает сам Update')

return fails
end)

print('')
local f5 = Run("=== 5: цепочка UMT, от Add до появления страницы ===", function()
local fails = 0
local function check(cond, label)
    if cond then
        print('  [OK  ] ' .. label)
    else
        fails = fails + 1
        print('  [FAIL] ' .. label)
    end
end

-- The order in the game: UML finds the mod by the __umt flag and tells UMT to Add it, then
-- UMT looks for Main.lua in the mod folder and calls its Main. Without Main.lua the queue
-- never reaches our options.
UMT.Add('overflow')

local nBefore = table.getn(msgs)
UMT.Load(nil)
local loaded = table.concat(msgs, ' | ')
local nAfter = table.getn(msgs)

check(string.find(loaded, 'UMT: Loading file /mods/overflow/modules/main.lua') ~= nil,
      'UMT нашёл наш Main.lua в папке мода')
check(string.find(loaded, 'Loading options file') ~= nil
      or string.find(loaded, 'loading option') ~= nil
      or string.find(loaded, 'UMT options page') ~= nil,
      'наш Main дошёл до чтения UMT.Options.Mods и.options грузятся')

-- The main check: the page is REGISTERED. Everything else is detail.
check(BUILDS['Overflow'] ~= nil,
      'страница зарегистрирована: AddOptions отработал без ошибки')
check(BUILDS['Overflow'] ~= nil and table.getn(BUILDS['Overflow']) == 15,
      'в странице 15 строк: рамка, пресет, масштаб, два переключателя, два ' ..
      'заголовка, список наборов и семь галочек (получено ' ..
      tostring(BUILDS['Overflow'] and table.getn(BUILDS['Overflow']) or 0) .. ')')

-- SCALE SLIDER. The bounds have to match themes.lua, otherwise the slider would give a
-- value that the mod then clamps to its own bounds, and the slider position would not match
-- how the panel behaves.
local sliderFound = nil
if BUILDS['Overflow'] then
    for i = 1, table.getn(BUILDS['Overflow']) do
        local row = BUILDS['Overflow'][i]
        if row.type == 'slider' then sliderFound = row end
    end
end
check(sliderFound ~= nil, 'на странице есть ползунок масштаба шрифта')
check(sliderFound ~= nil and sliderFound.min == 70 and sliderFound.max == 200,
      'границы ползунка 70-200 совпадают с границами модуля оформления')
check(sliderFound ~= nil and sliderFound.inc == 5,
      'шаг ползунка 5 процентов')

-- The shim has to be safe without UMT too: the page must not crash the game when the UMT
-- mod is absent.
local savedUMT = UMT
UMT = nil
local okNoUmt = pcall(MODULES.main.Main, nil)
UMT = savedUMT
check(okNoUmt, 'шим не падает, когда UMT нет')

-- A failed registration has to be logged: staying silent would send the player looking for
-- the cause in the wrong place.
check(string.find(loaded, 'FAILED') == nil,
      'в логе загрузки цепочки нет ни одной строки FAILED')

return fails
end)

print('')
local f6 = Run("=== 6: запрет на входящий при полном хранилище ===", function()
local fails = 0
local function check(cond, label)
    if cond then
        print('  [OK  ] ' .. label)
    else
        fails = fails + 1
        print('  [FAIL] ' .. label)
    end
end

-- One Sync.Score sample for an army. The field order follows sim/score.lua.
local function Army(ein, eout, eexc, estore, emax,
                   emin, mout, mexc, mstore, mmax)
    return { resources = {
        energyin  = { total = ein, reclaimed = 0 },
        energyout = { total = eout, excess = eexc },
        massin    = { total = emin, reclaimed = 0 },
        massout   = { total = mout, excess = mexc },
        storage   = { storedEnergy = estore, maxEnergy = emax,
                      storedMass = mstore, maxMass = mmax },
    } }
end

local function Feed(myBase, myLater, allyBase, allyLater)
    -- Resetting the error counter before each scenario is REQUIRED. Otherwise the errors of
    -- the previous scenario accumulate, exceed NERR_LIMIT = 3, and sync.lua removes its
    -- callback, so the scenario fails for a reason unrelated to the one under test.
    SYNC.ResetCounters()
    local before = table.concat(msgs, ' | ')
    check(string.find(before, 'ERROR') == nil,
          'sync.lua не оставил ошибок от прошлого сценария')
    msgs = {}
    TICK = 100
    SCORE_CB({ [1] = myBase, [2] = allyBase })
    TICK = 200
    SCORE_CB({ [1] = myLater, [2] = allyLater })
    return SYNC.GetResult()
end

-- Start() first, then the check: the callback must not exist before it.
IMPORTED = {}
SYNC.Start()
check(SCORE_CB ~= nil, 'Start() зарегистрировал колбэк Sync.Score')
local reimported = false
for i = 1, table.getn(IMPORTED) do
    if IMPORTED[i] == '/lua/UserSync.lua' then reimported = true end
end
check(not reimported, 'UserSync.lua не выполняется второй раз')

-- SCENARIO A. My storage sits at the ceiling for the whole window, the ally gives.
--
--   me: storage 1000 of 1000, produced 100, spent nothing
--   ally: produced 100, storage 0 of 2000, spent nothing
--
-- Without the guard the mod would show incoming 10/s and outgoing 10/s at once. Incoming is
-- physically impossible: there is nowhere to put it.
local rA = Feed(
    Army(0, 0, 0, 1000, 1000, 0, 0, 0, 500, 500),
    Army(100, 0, 0, 1000, 1000, 0, 0, 0, 500, 500),
    Army(0, 0, 0, 0, 2000, 0, 0, 0, 0, 2000),
    Army(100, 0, 0, 0, 2000, 0, 0, 0, 0, 2000))

check(rA ~= nil and rA.ok == true, 'окно опубликовано, сценарий A')
if rA ~= nil then
    check(rA.outgoing > 0,
          'исходящий ненулевой, как и должно быть при полном запасе (' ..
          tostring(rA.outgoing) .. ')')
    check(rA.incoming == 0,
          'входящий обнулён запретом: принимать некуда (было бы 10.0)')
    check(string.find(table.concat(msgs, ' | '), 'GUARD E') ~= nil,
          'в лог записана строка GUARD E с сырыми числами')
    check(string.find(table.concat(msgs, ' | '), 'полный: true') ~= nil,
          'в лог записано, что запас признан полным')
end

-- SCENARIO B. I have room: 500 of 1000. The guard does not apply.
local rB = Feed(
    Army(0, 0, 0, 500, 1000, 0, 0, 0, 500, 500),
    Army(100, 0, 0, 500, 1000, 0, 0, 0, 500, 500),
    Army(0, 0, 0, 0, 2000, 0, 0, 0, 0, 2000),
    Army(100, 0, 0, 0, 2000, 0, 0, 0, 0, 2000))

check(rB ~= nil and rB.ok == true, 'окно опубликовано, сценарий B')
if rB ~= nil then
    check(rB.incoming > 0,
          'входящий остался: место было, запрет не тронул (' ..
          tostring(rB.incoming) .. ')')
    check(string.find(table.concat(msgs, ' | '), 'GUARD') == nil,
          'GUARD не сработал там, где не должен')
end

-- SCENARIO C. The ceiling GREW in the middle of the window: at the start there was no room,
-- at the end the ceiling is 2000 with 1000 stored, i.e. room appeared.
--
-- A crude check such as "minimum stored >= minimum ceiling" would be wrong here: it would
-- call the storage full and zero a real overflow.
local rC = Feed(
    Army(0, 0, 0, 1000, 1000, 0, 0, 0, 500, 500),
    Army(100, 0, 0, 1000, 2000, 0, 0, 0, 500, 500),
    Army(0, 0, 0, 0, 2000, 0, 0, 0, 0, 2000),
    Army(100, 0, 0, 0, 2000, 0, 0, 0, 0, 2000))

check(rC ~= nil and rC.ok == true, 'окно опубликовано, сценарий C')
if rC ~= nil then
    check(rC.incoming > 0,
          'выросший потолок НЕ считается полным: место было, входящий остался (' ..
          tostring(rC.incoming) .. ')')
    check(string.find(table.concat(msgs, ' | '), 'GUARD') == nil,
          'на растущем потолке GUARD не сработал')
end

-- SCENARIO D. The MASS storage sits at the ceiling for the whole window, the ally gives.
-- There is nowhere to put it, so incoming has to be zeroed.
local rD = Feed(
    Army(0, 0, 0, 500, 1000, 0, 0, 0, 500, 500),
    Army(100, 0, 0, 500, 1000, 100, 0, 0, 500, 500),
    Army(0, 0, 0, 0, 2000, 0, 0, 0, 0, 2000),
    Army(100, 0, 0, 0, 2000, 100, 0, 0, 0, 2000))

check(rD ~= nil and rD.ok == true, 'окно опубликовано, сценарий D')
if rD ~= nil then
    check(rD.massIncoming == 0,
          'входящая масса обнулена: хранилище массы полно (' ..
          tostring(rD.massIncoming) .. ')')
    check(string.find(table.concat(msgs, ' | '), 'GUARD M') ~= nil,
          'в лог записана строка GUARD M с сырыми числами')
end

-- SCENARIO E. The total mass income over the match is much larger than the capacity, but
-- the storage has room. Free space is computed from the stored amount, not from income.
local rE = Feed(
    Army(0, 0, 0, 500, 1000, 5000, 0, 0, 100, 500),
    Army(100, 0, 0, 500, 1000, 5100, 0, 0, 100, 500),
    Army(0, 0, 0, 0, 2000, 0, 0, 0, 0, 2000),
    Army(100, 0, 0, 0, 2000, 100, 0, 0, 0, 2000))

check(rE ~= nil and rE.ok == true, 'окно опубликовано, сценарий E')
if rE ~= nil then
    check(rE.massIncoming > 0,
          'входящая масса осталась: место в хранилище было (' ..
          tostring(rE.massIncoming) .. ')')
    check(string.find(table.concat(msgs, ' | '), 'GUARD') == nil,
          'при свободном месте GUARD не сработал')
end

-- SCENARIO F. The engine income includes reclaim, and "own production" counts it as its
-- own, although the reclaim row also shows it separately. Window 10 s: income 50 and 30 per
-- second, reclaim 20 and 10 per second.
INCOME_E = 5
INCOME_M = 3
local function Reclaimed(army, recE, recM)
    army.resources.energyin.reclaimed = recE
    army.resources.massin.reclaimed = recM
    return army
end
local rF = Feed(
    Reclaimed(Army(0, 0, 0, 500, 1000, 0, 0, 0, 100, 500), 0, 0),
    Reclaimed(Army(500, 500, 0, 500, 1000, 300, 300, 0, 100, 500), 200, 100),
    Army(0, 0, 0, 0, 2000, 0, 0, 0, 0, 2000),
    Army(0, 0, 0, 0, 2000, 0, 0, 0, 0, 2000))
INCOME_E = 0
INCOME_M = 0

check(rF ~= nil and rF.ok == true, 'окно опубликовано, сценарий F')
if rF ~= nil then
    check(rF.reclaim == 20 and rF.massReclaim == 10,
          'реклейм считается по своим счётчикам (' .. tostring(rF.reclaim) ..
          ', ' .. tostring(rF.massReclaim) .. ')')
    check(rF.own == 50, 'своя энергия вместе с реклеймом (' ..
          tostring(rF.own) .. ')')
    check(rF.massOwn == 30, 'своя масса вместе с реклеймом (' ..
          tostring(rF.massOwn) .. ')')
end

check(string.find(table.concat(msgs, ' | '), 'ERROR') == nil,
      'sync.lua не сыпал ошибок ни в одном сценарии')

return fails
end)

print('')
local f7 = Run("=== 7: ошибка в Update не уходит в цикл игры ===", function()
local fails = 0
local function check(cond, label)
    if cond then
        print('  [OK  ] ' .. label)
    else
        fails = fails + 1
        print('  [FAIL] ' .. label)
    end
end

msgs = {}
SYNC_BROKEN = true
check(pcall(BEAT), 'первая ошибка Update поймана внутри мода')
check(not BEAT_REMOVED, 'после одной ошибки панель продолжает работать')

SYNC_BROKEN = false
check(pcall(BEAT), 'без ошибки Update работает как обычно')

SYNC_BROKEN = true
for _ = 1, 10 do pcall(BEAT) end
SYNC_BROKEN = false

local told = 0
for _ in string.gfind(table.concat(msgs, ' | '), 'Update FAILED') do
    told = told + 1
end
check(told == 4, 'в лог попали только ошибки до предела (' .. tostring(told) .. ')')
check(BEAT_REMOVED, 'после трёх ошибок подряд функция бита снята')
return fails
end)

-- A fresh ui.lua: the first one remembers the height the checks above set by hand.
local env_ui_scaled = MakeEnv()
LoadInto(MOD .. 'ui.lua', env_ui_scaled)
U_SCALED = env_ui_scaled

print('')
local f8 = Run("=== 8: масштаб интерфейса ===", function()
local fails = 0
local function check(cond, label)
    if cond then
        print('  [OK  ] ' .. label)
    else
        fails = fails + 1
        print('  [FAIL] ' .. label)
    end
end

local mark = 0

local function Build(scale)
    pixelScaleFactor = scale
    PROFILE = {}
    local allRows = {}
    for i = 1, ROWS.HowManyRows() do allRows[ROWS.RowKeyAt(i)] = true end
    ROWS.SaveRows(allRows)
    mark = table.getn(MADE)
    U_SCALED.OnCreateUI()
    BEAT()
    for i = mark + 1, table.getn(MADE) do
        if MADE[i]._kind == 'Window' then return MADE[i] end
    end
end

local function Row(text)
    for i = mark + 1, table.getn(MADE) do
        if MADE[i]._kind == 'Text' and MADE[i]._text == text then return MADE[i] end
    end
end

local plain = Build(1.0)
local plainHeight = plain.Bottom() - plain.Top()
local plainLast = Row('reclaim E 5.0 / M 6.0 /s')
local plainOffset = plainLast.Top() - plain.Top()
local plainMargin = plain.ClientGroup.Bottom() - (plainLast.Top() + plainLast.Height())

local win = Build(2.0)
local height = win.Bottom() - win.Top()
check(math.abs(height - 2 * plainHeight) <= 1,
      'высота окна растёт вместе с масштабом (' .. tostring(height) ..
      ' против ' .. tostring(plainHeight) .. ')')

local first = Row('E ally overflow: 100.0 E/s')
local third = Row('E own production: 200.0 E/s')
local last = Row('reclaim E 5.0 / M 6.0 /s')
check(first ~= nil and first.Height() == 28,
      'высота строки растёт вместе с масштабом (' ..
      tostring(first and first.Height()) .. ')')
check(last ~= nil and math.abs((last.Top() - win.Top()) - 2 * plainOffset) <= 1,
      'нижняя строка стоит там же относительно окна (' ..
      tostring(last and last.Top() - win.Top()) .. ' против ' ..
      tostring(plainOffset) .. ')')
check(last ~= nil and math.abs((win.ClientGroup.Bottom() - (last.Top() + last.Height()))
      - 2 * plainMargin) <= 1,
      'поле под нижней строкой масштабируется вместе с окном')

local right = win.ClientGroup.Right()
check(first ~= nil and first.Right() == win._closeBtn.Left() - 40,
      'строка под крестиком отступает от него на RIGHT_PAD в экранных пикселях (' ..
      tostring(first and first.Right()) .. ' при крестике ' ..
      tostring(win._closeBtn.Left()) .. ')')
check(third ~= nil and third.Right() == right - 40,
      'строка ниже крестика идёт во всю ширину (' ..
      tostring(third and third.Right()) .. ' при крае ' .. tostring(right) .. ')')

win.OnClose(win)
local reopen = nil
for i = mark + 1, table.getn(MADE) do
    if MADE[i].HandleEvent ~= nil then reopen = MADE[i] end
end
check(reopen ~= nil and math.abs(reopen.Left() - win.Left()) <= 1
      and math.abs(reopen.Top() - win.Top()) <= 1,
      'кнопка возврата появляется на месте панели (' ..
      tostring(reopen and reopen.Left()) .. ', ' .. tostring(reopen and reopen.Top()) ..
      ' при окне ' .. tostring(win.Left()) .. ', ' .. tostring(win.Top()) .. ')')

-- The smallest scale of the game: one pixel scaled by 0.8 floors to zero.
local small = Build(0.8)
local thinnest = nil
for i = mark + 1, table.getn(MADE) do
    local c = MADE[i]
    if c._kind == 'Bitmap' and c._parent == small.ClientGroup then
        if thinnest == nil or c.Height() < thinnest then thinnest = c.Height() end
    end
end
check(thinnest ~= nil and thinnest >= 1,
      'разделитель не исчезает при масштабе 80% (высота ' .. tostring(thinnest) .. ')')

pixelScaleFactor = 1.0
return fails
end)

-- A fresh ui.lua: the line about the growth of the window is written once per load.
local env_ui_guards = MakeEnv()
LoadInto(MOD .. 'ui.lua', env_ui_guards)
U_GUARDS = env_ui_guards

print('')
local f9 = Run("=== 9: сбой под pcall виден в логе, панель его переживает ===", function()
local fails = 0
local function check(cond, label)
    if cond then
        print('  [OK  ] ' .. label)
    else
        fails = fails + 1
        print('  [FAIL] ' .. label)
    end
end

local function Told(text)
    local n = 0
    for i = 1, table.getn(msgs) do
        if string.find(msgs[i], text, 1, true) then n = n + 1 end
    end
    return n
end

local function NewestWindow()
    local found = nil
    for i = 1, table.getn(MADE) do
        if MADE[i]._kind == 'Window' then found = MADE[i] end
    end
    return found
end

msgs = {}
PROFILE = {}
local allRows = {}
for i = 1, ROWS.HowManyRows() do allRows[ROWS.RowKeyAt(i)] = true end
ROWS.SaveRows(allRows)
U_GUARDS.OnCreateUI()
BEAT()
check(Told('FAILED') == 0, 'без сбоев строк FAILED нет')
local win = NewestWindow()
local reopen = nil
for i = 1, table.getn(MADE) do
    if MADE[i].HandleEvent ~= nil then reopen = MADE[i] end
end

-- ApplyMinSize runs on every beat.
msgs = {}
local readRight = win.Right._get
win.Right._get = function() error('growth boom') end
for _ = 1, 5 do BEAT() end
win.Right._get = readRight
check(Told('window growth FAILED, limit') == 1, 'сбой роста окна в логе один раз за 5 проходов')
check(Told('growth boom') == 1, 'в строке лога есть текст ошибки')
check(Told('Update FAILED') == 0, 'сбой роста окна не останавливает обновление панели')

msgs = {}
local readLeft = win.Left._get
win.Left._get = function() error('move boom') end
win.OnClose(win)
win.Left._get = readLeft
check(Told('reopen button move FAILED') == 1 and Told('move boom') == 1, 'сбой сдвига кнопки в логе')
check(reopen._hidden == false, 'кнопка возврата всё равно показана: панель можно вернуть')
reopen.HandleEvent(reopen, { Type = 'ButtonRelease' })

-- One rebuild of the panel meets every other failure: a change of the look triggers it.
msgs = {}
win.Destroy = function() error('window boom') end
reopen.Destroy = function() error('button boom') end
local plainReadKey = Prefs.GetFromCurrentProfile
Prefs.GetFromCurrentProfile = function(k)
    if k == 'OverflowCollapsed' then error('key boom') end
    return plainReadKey(k)
end
-- The reopen button is the only control placed right in the frame. The new window exists
-- by then, and only the size dump reads its Width.
local plainPlace = LayoutHelpers.AtLeftTopIn
LayoutHelpers.AtLeftTopIn = function(c, p, x, y)
    if p == FRAME then
        NewestWindow().Width = function() error('dump boom') end
        error('place boom')
    end
    plainPlace(c, p, x, y)
end
PROFILE['Overflow'].blink = true
BEAT()
LayoutHelpers.AtLeftTopIn = plainPlace
Prefs.GetFromCurrentProfile = plainReadKey

check(Told('old window Destroy FAILED') == 1 and Told('window boom') == 1, 'сбой Destroy окна в логе')
check(Told('old reopen button Destroy FAILED') == 1 and Told('button boom') == 1,
      'сбой Destroy кнопки в логе')
check(Told('reopen button placement FAILED') == 1 and Told('place boom') == 1,
      'сбой размещения кнопки в логе')
check(Told('collapse state read FAILED, key OverflowCollapsed') == 1 and Told('key boom') == 1,
      'сбой чтения свёрнутости в логе с ключом')
check(Told('window geometry dump FAILED') == 1 and Told('dump boom') == 1,
      'сбой вывода размеров в логе')
check(Told('theme rebuild FAILED') == 0, 'пересборка панели дошла до конца')
check(NewestWindow() ~= win, 'панель собрана заново')

-- A rebuild of a collapsed panel, with the collapse state unreadable: the new panel opens,
-- so its rows have to be shown.
local rebuilt = NewestWindow()
rebuilt.OnClose(rebuilt)
Prefs.GetFromCurrentProfile = function(k)
    if k == 'OverflowCollapsed' then error('key boom') end
    return plainReadKey(k)
end
PROFILE['Overflow'].blink = false
BEAT()
Prefs.GetFromCurrentProfile = plainReadKey
local shownRows = 0
for _, c in ipairs(NewestWindow().ClientGroup._children) do
    if c._kind == 'Text' and not c._hidden then shownRows = shownRows + 1 end
end
check(NewestWindow() ~= rebuilt and not NewestWindow()._hidden and shownRows > 0,
      'свёрнутая панель после пересборки открыта со строками (строк ' .. tostring(shownRows) .. ')')
return fails
end)

print('')

print('')
print('=== ИТОГ ===')
local total = f1 + f2 + f3 + f4 + f5 + f6 + f7 + f8 + f9
if total > 0 then
    print('провалено проверок: ' .. tostring(total))
    os.exit(1)
end
print('все проверки пройдены')
