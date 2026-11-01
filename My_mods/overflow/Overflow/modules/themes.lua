-- Overflow - look of the panel: style, frame, blinking.
--
-- A separate file for the same reason as rows.lua: the settings page needs the names
-- without importing the panel.
--
-- A style (StyleNames) sets the font size and the colours of the text, a frame (FrameNames)
-- sets the window itself. Each has two variants, Minimal by default and Vanilla.
--
-- Vanilla takes size 10, the size of the small numbers on the game resource panel, and its
-- colours from the game skin, so the mod follows FAF if the skin changes. SAFE, WARN and
-- BAD come from the game resource panel in both styles. The game passes colour names such
-- as 'red' to Text:SetColor, and the labels here are the same Text.
--
-- The three colours mean the same in every style: green - no overflow, yellow - allies
-- overflow to you, red - you depend on it too much. A style changes the shade, not the list
-- of states. States and the threshold live in ui.lua (StatusColor).
--
-- The option faction_font_color is off by default, and the game then draws
-- skins.default.fontColor instead of the faction colour. FontColorFor repeats that check.
-- Prefs.GetOption returns the default of a missing option, so it cannot be nil.
--
-- Nothing here touches UMT, for the same reason as in rows.lua. The profile key 'Overflow'
-- has no dots and is shared with rows.lua and UMT.
--
-- Names of styles and frames must not change: UMT replaces a saved value it cannot find in
-- a list with the first item and saves it.

local Prefs        = import('/lua/user/prefs.lua')
local LOG          = LOG
-- FAF has no global MathFloor, and reading a missing global stops the whole file from
-- loading.
local MathFloor    = math.floor
local TableGetn    = table.getn

local PrefsKey = 'Overflow'

-- Without the game skins the numbers given below stay in place.
local Skins = nil
do
    local okSkins, resSkins = pcall(function()
        return import('/lua/skins/skins.lua').skins
    end)
    if okSkins and type(resSkins) == 'table' then
        Skins = resSkins
    else
        LOG('Overflow: skins.lua did not load, Vanilla style will use ' ..
            'fallback colours')
    end
end


-- A skin field as a string, fallback for anything else: a panel without its colours is
-- better than transparent text.
local function SkinField(skinName, fieldName, fallback)
    if Skins == nil then
        return fallback
    end
    local sk = Skins[skinName]
    if type(sk) ~= 'table' then
        return fallback
    end
    local got = sk[fieldName]
    if type(got) ~= 'string' or got == '' then
        return fallback
    end
    return got
end

-- Font colour of a faction, with the same check as in the game.
local function FontColorFor(skinName)
    local plain = SkinField('default', 'fontColor', 'FFbadbdb')
    local okOpt, resOpt = pcall(function()
        return Prefs.GetOption('faction_font_color')
    end)
    if okOpt and resOpt then
        return SkinField(skinName, 'fontColor', plain)
    end
    return plain
end

--------------------------------------------------------------------------------
-- Lists. The first item is the default: UMT falls back to items[1].
--------------------------------------------------------------------------------

-- Styles: font and text colours.
local STYLES = {
    -- The default style. Field names are upper case, as Build reads them.
    { label = 'Minimal',
      FONT = 11,
      DIVIDER = 'FF405060',
      TITLE   = 'FF8FD0FF',
      SAFE    = 'FF5CE07A',
      WARN    = 'FFFFD24A',
      BAD     = 'FFEF5350',
      NEUTRAL = 'FF8A96A3',
      TOTAL   = 'FFFFD24A',
      CLOSED  = 'FF1E2A34' },

    -- As in the game: size 10 is what it uses for its small numbers.
    { label = 'Vanilla',
      FONT = 10,
      skin = true },
}

-- Styles have no BG: the window colour belongs to the frame setting (ui.lua,
-- ApplyFrameBackground). BG stays in the palette as the default for CLOSED, the colour of
-- the reopen button.

-- Frames: how the window looks. Minimal is the default, so it comes first.
local FRAMES = {
    { label = 'Minimal', minimal = true },
    { label = 'Vanilla', minimal = false },
}

--------------------------------------------------------------------------------
-- Palette of a style. The fields are listed by name to show that the set is complete.
--------------------------------------------------------------------------------

local function Build(style)
    -- The base comes from the skin `default`.
    local out = {}
    out.BG      = SkinField('default', 'transparentPanelColor', 'AA4A5D6B')
    out.CLOSED  = out.BG
    out.DIVIDER = SkinField('default', 'disabledColor', 'FF47555a')
    out.TITLE   = SkinField('default', 'dialogCaptionColor', 'FFbadbdb')
    out.TOTAL   = out.TITLE
    out.NEUTRAL = out.TITLE
    out.SAFE    = 'ffb7e75f'
    out.WARN    = 'yellow'
    out.BAD     = 'red'
    out.FONT    = 10

    -- Vanilla takes part of the fields from a faction skin: bodyColor always, the font
    -- colour only with the option faction_font_color.
    if style.skin then
        out.NEUTRAL = SkinField('aeon', 'bodyColor', out.NEUTRAL)
        out.DIVIDER = SkinField('aeon', 'disabledColor', out.DIVIDER)
        out.TITLE   = FontColorFor('aeon')
    end

    -- The values of the style go over the base.
    out.BG      = style.BG      or out.BG
    out.CLOSED  = style.CLOSED  or out.CLOSED
    out.DIVIDER = style.DIVIDER or out.DIVIDER
    out.TITLE   = style.TITLE   or out.TITLE
    out.TOTAL   = style.TOTAL   or out.TOTAL
    out.NEUTRAL = style.NEUTRAL or out.NEUTRAL
    out.SAFE    = style.SAFE    or out.SAFE
    out.WARN    = style.WARN    or out.WARN
    out.BAD     = style.BAD     or out.BAD
    out.FONT    = style.FONT    or out.FONT

    return out
end

--------------------------------------------------------------------------------
-- Profile, read directly: the mod has to work without UMT.
--------------------------------------------------------------------------------

local function Saved()
    local profile = {}
    local ok, res = pcall(function()
        return Prefs.GetFromCurrentProfile(PrefsKey)
    end)
    if not ok then
        LOG('Overflow: settings read error, using defaults: ' .. tostring(res))
        return profile
    end
    if type(res) == 'table' then
        profile = res
    end
    return profile
end

-- Item of a list by name. An unknown or absent value gives the first item.
local function Pick(list, wanted)
    if type(wanted) ~= 'string' then
        return list[1].label
    end
    local many = TableGetn(list)
    for i = 1, many do
        if list[i].label == wanted then
            return list[i].label
        end
    end
    return list[1].label
end

local function ByLabel(list, label)
    local many = TableGetn(list)
    for i = 1, many do
        if list[i].label == label then
            return list[i]
        end
    end
    return list[1]
end

--------------------------------------------------------------------------------
-- Font scale. The UMT slider is integer, so the scale is stored in percent: 100 is as is,
-- 150 is one and a half.
--------------------------------------------------------------------------------

local FONT_SCALE_MIN = 70
local FONT_SCALE_MAX = 200

-- The default scale. The settings page reads it from here, so the slider and the mod agree.
local FONT_SCALE_DEFAULT = 120

local function FontScaleRead()
    local v = Saved().fontScale
    if type(v) ~= 'number' then
        return FONT_SCALE_DEFAULT
    end
    local n = MathFloor(v + 0.5)
    if n < FONT_SCALE_MIN then return FONT_SCALE_MIN end
    if n > FONT_SCALE_MAX then return FONT_SCALE_MAX end
    return n
end


function StyleNames()
    local out = {}
    local many = TableGetn(STYLES)
    for i = 1, many do
        out[i] = STYLES[i].label
    end
    return out
end

function StyleCurrent()
    return Pick(STYLES, Saved().style)
end

-- Full palette of the selected style: text colours and the base font size.
function StylePalette()
    return Build(ByLabel(STYLES, StyleCurrent()))
end

-- Font size with the scale of the player, as an integer.
function StyleFontSize()
    local base = StylePalette().FONT
    return MathFloor(base * FontScaleRead() / 100 + 0.5)
end

function FontScale()
    return FontScaleRead()
end

-- Default scale for the slider of the settings page.
function FontScaleDefault()
    return FONT_SCALE_DEFAULT
end

-- Numbers only: the rows lose their text. ui.lua decides what to show.
function NumbersOnly()
    return Saved().numbersOnly and true or false
end

function FrameNames()
    local out = {}
    local many = TableGetn(FRAMES)
    for i = 1, many do
        out[i] = FRAMES[i].label
    end
    return out
end

function FrameCurrent()
    return Pick(FRAMES, Saved().theme)
end

-- Flat frame instead of the game window frame.
function FrameMinimal()
    return ByLabel(FRAMES, FrameCurrent()).minimal and true or false
end

-- Blinking is off by default.
function ThemeBlinkOn()
    return Saved().blink and true or false
end

-- Signature of the settings. The panel rebuilds when it changes, so it holds everything
-- that changes the look at build time.
function ThemeSignature()
    -- The FAF plugin for LuaLS reports a global call right after `..` as
    -- undefined. The function is declared above in this file.
    ---@diagnostic disable-next-line: undefined-global
    return StyleCurrent() .. '|' .. FrameCurrent() .. '|' ..
        tostring(ThemeBlinkOn()) .. '|' .. tostring(FontScaleRead()) .. '|' ..
        tostring(NumbersOnly())
end

-- Description for the log.
function ThemeTell()
    -- Same false alarm of the FAF plugin as in ThemeSignature.
    ---@diagnostic disable-next-line: undefined-global
    return StyleCurrent() .. ' / ' .. FrameCurrent() ..
        ' / шрифт ' .. tostring(StyleFontSize()) ..
        ' / ' .. (NumbersOnly() and 'только числа' or 'с подписями')
end
