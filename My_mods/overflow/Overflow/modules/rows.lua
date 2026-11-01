-- Overflow - which rows of the panel are shown.
--
-- A separate file because the panel (ui.lua) and the UMT settings page (Options.lua) both
-- need the list of rows, and the page must not import the panel: the load order of UMT and
-- the game interface is unknown, so the import could meet a module that is still loading.
-- The page writes to the profile and the panel notices the change on its beat.
--
-- Functions are exported as globals: the game discards what a module returns. ui.lua reads
-- them through rawget.
--
-- Values live under the profile key 'Overflow', the same key OptionVar:Save() uses, so the
-- window and the mod share them. Without UMT the keys are absent and VisibleRows() returns
-- the defaults. This file must not touch UMT: without it, reading the missing global would
-- kill the whole mod.
--
-- The key has no dots: GetFromCurrentProfile reads the string as a path.
--
-- The profile stores which rows are visible, not which are hidden: an absent field has to
-- mean "as by default", or an update of the mod would blank the panel of everyone who never
-- opened the settings.

local Prefs        = import('/lua/user/prefs.lua')
local LOG          = LOG
local TableGetn    = table.getn
local TableConcat  = table.concat
local StringFormat = string.format

local PREFS_KEY = 'Overflow'


-- The order of the rows on the panel. ROW_ORDER in ui.lua has to match it.
local ROWS = { 'eOverflow', 'eGo', 'eOwn', 'mOverflow', 'mGo', 'mOwn', 'total' }

-- Titles for the settings window, one for each key of ROWS.
local TITLES = {
    eOverflow = 'E ally overflow - сколько энергии дают союзники',
    eGo       = 'E to allies - сколько энергии отдаём мы',
    eOwn      = 'E own production - своя выработка энергии',
    mOverflow = 'M ally overflow - сколько массы дают союзники',
    mGo       = 'M to allies - сколько массы отдаём мы',
    mOwn      = 'M own production - своя выработка массы',
    total     = 'reclaim E / M - скорость реклейма',
}

-- Two rows are visible by default. This set has to match PRESETS[1]: UMT replaces a value
-- it cannot find in a list with the first item and saves it.
local DEFAULTS = {
    eOverflow = true,
    eGo       = true,
    eOwn      = false,
    mOverflow = false,
    mGo       = false,
    mOwn      = false,
    total     = false,
}

--------------------------------------------------------------------------------
-- Ready-made sets, so that keeping one row does not take six clicks.
--
-- The first item matches DEFAULTS, see above. The last item is not a set but the state
-- shown for a combination that is not listed: it has no flags, so PresetByName returns nil
-- and choosing it changes nothing.
--------------------------------------------------------------------------------

local PRESETS = {
    { label = 'E ally overflow + E to allies',
      flags = { eOverflow = true, eGo = true } },
    { label = 'Все строки',
      flags = { eOverflow = true, eGo = true, eOwn = true,
                mOverflow = true, mGo = true, mOwn = true, total = true } },
    { label = 'Только E ally overflow',
      flags = { eOverflow = true } },
    { label = 'Только перелив союзников',
      flags = { eOverflow = true, mOverflow = true } },
    { label = 'Только энергия',
      flags = { eOverflow = true, eGo = true, eOwn = true } },
    { label = 'Только масса',
      flags = { mOverflow = true, mGo = true, mOwn = true } },
    { label = 'Ничего не показывать',
      flags = {} },
    { label = 'Другой набор',
      flags = nil },
}

function HowManyRows()
    return TableGetn(ROWS)
end

-- Row key by number, from 1.
function RowKeyAt(i)
    return ROWS[i]
end

-- Row title for the settings window.
function RowTitleOf(rowKey)
    return TITLES[rowKey]
end

-- A copy, so that the caller cannot damage the definition.
function RowDefaults()
    local out = {}
    for i = 1, TableGetn(ROWS) do
        local rowKey = ROWS[i]
        out[rowKey] = DEFAULTS[rowKey]
    end
    return out
end

-- Set names in the order of PRESETS.
function PresetNames()
    local out = {}
    for i = 1, TableGetn(PRESETS) do
        out[i] = PRESETS[i].label
    end
    return out
end


-- Which rows to show. An absent key reads as the default: see the header.
function VisibleRows()
    local saved = nil
    local ok, res = pcall(function()
        return Prefs.GetFromCurrentProfile(PREFS_KEY)
    end)
    if ok then
        saved = res
    else
        LOG('Overflow: rows read error, showing defaults: ' .. tostring(res))
    end

    local out = {}
    for i = 1, TableGetn(ROWS) do
        local rowKey = ROWS[i]
        local v
        if type(saved) == 'table' then
            v = saved[rowKey]
        end
        if v == nil then
            v = DEFAULTS[rowKey]
        end
        out[rowKey] = v and true or false
    end
    return out
end

-- Writes the rows to the profile. The table is read and written back because UMT keeps its
-- own fields under the same key.
function SaveRows(vis)
    local ok, err = pcall(function()
        local profile = Prefs.GetFromCurrentProfile(PREFS_KEY)
        if type(profile) ~= 'table' then
            profile = {}
        end
        for i = 1, TableGetn(ROWS) do
            local rowKey = ROWS[i]
            profile[rowKey] = vis[rowKey] and true or false
        end
        Prefs.SetToCurrentProfile(PREFS_KEY, profile)
    end)
    if not ok then
        LOG('Overflow: rows Save FAILED: ' .. tostring(err))
        return false
    end
    return true
end


-- Name of the set equal to vis, or nil. All rows are compared, including those the set does
-- not mention.
function PresetFor(vis)
    for i = 1, TableGetn(PRESETS) do
        local preset = PRESETS[i]
        -- the last item is not a set
        if preset.flags ~= nil then
            local same = true
            for j = 1, TableGetn(ROWS) do
                local rowKey = ROWS[j]
                local want = preset.flags[rowKey]
                if want == nil then
                    want = false
                end
                if (vis[rowKey] and true or false) ~= want then
                    same = false
                    break
                end
            end
            if same then
                return preset.label
            end
        end
    end
    return nil
end

-- Label of the state with no matching set, for a combination made by hand.
function PresetOther()
    return PRESETS[TableGetn(PRESETS)].label
end

-- Expands a set name into flags. nil for an unknown name and for the last item.
function PresetByName(label)
    for i = 1, TableGetn(PRESETS) do
        if PRESETS[i].label == label then
            -- the last item has nothing to expand
            if PRESETS[i].flags == nil then
                return nil
            end
            local out = {}
            for j = 1, TableGetn(ROWS) do
                local rowKey = ROWS[j]
                local want = PRESETS[i].flags[rowKey]
                out[rowKey] = want and true or false
            end
            return out
        end
    end
    return nil
end


-- Signature of the visible rows, one '1' or '0' per row. The panel redoes the layout only
-- when it changes. A string, because tables compare by reference.
function RowsSignature(vis)
    local parts = {}
    for i = 1, TableGetn(ROWS) do
        local rowKey = ROWS[i]
        if vis[rowKey] then
            parts[i] = '1'
        else
            parts[i] = '0'
        end
    end
    return TableConcat(parts)
end

-- Short line for the log: which rows are visible.
function DescribeRows(vis)
    local parts = {}
    local howMany = 0
    for i = 1, TableGetn(ROWS) do
        local rowKey = ROWS[i]
        if vis[rowKey] then
            howMany = howMany + 1
            parts[howMany] = rowKey
        end
    end
    if howMany == 0 then
        return 'none'
    end
    return StringFormat('%d/%d [%s]', howMany, TableGetn(ROWS),
        TableConcat(parts, ' '))
end
