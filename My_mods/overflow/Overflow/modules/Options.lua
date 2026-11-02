-- Overflow - settings page for the "UI mod tools" (UMT) mod.
--
-- Only UMT loads this file: it finds Options.lua by name in the mods flagged with __umt and
-- calls Main(). Without UMT the mod reads the profile, and without values there it shows
-- the default rows. The player opens the window from the game menu: "UI mods options".
--
-- Main is a global function: the game discards what a module returns.
--
-- The page does not import ui.lua: the load order of UMT and the game interface is unknown,
-- and the import could meet a module that is still loading. It only writes to the profile,
-- and the panel notices the change on its beat.
--
-- The list of ready-made sets is an explicit choice: a click expands the set into check
-- boxes. The check boxes are the source of truth: after a change by hand the list shows the
-- matching set, or the "other set" item.
--
-- OptionVar:Set() changes the value in memory only, and UMT calls OptionVar:Save() when the
-- window closes. While the window is open the profile is stale, so the live value is read
-- from the OptionVar, called as a function. Bind calls the handler without arguments, so
-- the values come from `options` in the closure.

function Main()
    local Options = UMT.Options
    local Opt = Options.Opt
    local PFX = 'Overflow: '

    local Rows = import('/mods/Overflow/modules/rows.lua')

    -- rawget: a plain read of a missing module field reaches the strict _G and fails.
    local RowHowMany = rawget(Rows, 'HowManyRows')
    local RowIdAt    = rawget(Rows, 'RowKeyAt')
    local RowTitle   = rawget(Rows, 'RowTitleOf')
    local RowDefault = rawget(Rows, 'RowDefaults')
    local PresetList = rawget(Rows, 'PresetNames')
    local PresetPick = rawget(Rows, 'PresetFor')
    local PresetRest = rawget(Rows, 'PresetOther')
    local PresetOpen = rawget(Rows, 'PresetByName')
    local RowSave    = rawget(Rows, 'SaveRows')
    local RowTell    = rawget(Rows, 'DescribeRows')

    if type(RowHowMany) ~= 'function' or type(RowSave) ~= 'function'
        or type(PresetList) ~= 'function' then
        LOG(PFX .. 'FATAL - rows.lua did not load, settings page will show ' ..
            'defaults only. Look for the real error earlier in this log.')
        return
    end

    -- Without themes.lua the page is skipped: half of its settings would do nothing.
    local Themes = import('/mods/Overflow/modules/themes.lua')
    local ThemeNames = rawget(Themes, 'FrameNames')
    local StyleNames = rawget(Themes, 'StyleNames')
    local ScaleDefault = rawget(Themes, 'FontScaleDefault')

    if type(ThemeNames) ~= 'function' or type(StyleNames) ~= 'function'
        or type(ScaleDefault) ~= 'function' then
        LOG(PFX .. 'FATAL - themes.lua did not load, settings page skipped. ' ..
            'Look for the real error earlier in this log.')
        return
    end

    local defaults = RowDefault()
    local items = PresetList()
    -- The first item of each list is the default: UMT falls back to items[1].
    local looks = ThemeNames()
    local styles = StyleNames()

    -- The UMT slider is integer, so the font scale is in percent.
    local FONT_SCALE_MIN = 70
    local FONT_SCALE_MAX = 200
    local FONT_SCALE_STEP = 5

    -- The assignment, not a call, creates an OptionVar for each field, and UMT supplies the
    -- prefs key. The first set matches the default rows.
    Options.Mods["Overflow"] = {
        preset    = Opt(items[1]),
        eOverflow = Opt(defaults.eOverflow),
        eGo       = Opt(defaults.eGo),
        eOwn      = Opt(defaults.eOwn),
        mOverflow = Opt(defaults.mOverflow),
        mGo       = Opt(defaults.mGo),
        mOwn      = Opt(defaults.mOwn),
        total     = Opt(defaults.total),
        theme     = Opt(looks[1]),
        style     = Opt(styles[1]),
        fontScale = Opt(ScaleDefault()),
        numbersOnly = Opt(false),
        blink     = Opt(false),
    }

    local options = Options.Mods["Overflow"]

    -- Re-entry guard: a click on the list sets every check box, and each Set calls
    -- OnChange. Without the guard the check box handler would overwrite the set just
    -- chosen.
    local busy = false

    -- Live values of all check boxes.
    local function ReadBoxes()
        local vis = {}
        for i = 1, RowHowMany() do
            local rowKey = RowIdAt(i)
            vis[rowKey] = options[rowKey]() and true or false
        end
        return vis
    end

    -- Saves and logs. The panel picks the change up by itself.
    local function Apply(vis, fromPreset)
        RowSave(vis)
        LOG(PFX .. 'rows: ' .. RowTell(vis) ..
            ' | from list: ' .. tostring(fromPreset))
    end

    -- A check box was clicked: the list follows, so that it shows what is on the screen.
    local function OnBoxChange()
        if busy then return end
        busy = true
        local ok, vis = pcall(function()
            local box = ReadBoxes()
            -- Without a match the list shows the "other set" item. busy stops the OnChange
            -- of preset.
            local match = PresetPick(box)
            options.preset:Set(match or PresetRest())
            return box
        end)
        busy = false
        if not ok then
            LOG(PFX .. 'options refresh FAILED: ' .. tostring(vis))
            return
        end
        Apply(vis, false)
    end

    -- The list was clicked: the set goes to the check boxes. busy stops their handlers, and
    -- the profile is written here from the live values.
    local function OnPresetChange()
        if busy then return end
        busy = true
        local ok, vis = pcall(function()
            local flags = PresetOpen(options.preset())
            if flags then
                for i = 1, RowHowMany() do
                    local rowKey = RowIdAt(i)
                    options[rowKey]:Set(flags[rowKey])
                end
            end
            return ReadBoxes()
        end)
        busy = false
        if not ok then
            LOG(PFX .. 'preset FAILED: ' .. tostring(vis))
            return
        end
        Apply(vis, true)
    end

    for i = 1, RowHowMany() do
        options[RowIdAt(i)]:Bind(OnBoxChange)
    end
    options.preset:Bind(OnPresetChange)

    Options.AddOptions("Overflow", "Overflow: оформление и строки", {
        Options.Strings("Рамка окна", looks, options.theme, 0),
        Options.Strings("Пресет: шрифт и цвета", styles, options.style, 0),
        Options.Slider("Масштаб шрифта, %", FONT_SCALE_MIN, FONT_SCALE_MAX,
                       FONT_SCALE_STEP, options.fontScale, 0),
        Options.Filter("Только числа, без подписей", options.numbersOnly, 16),
        Options.Filter("Мигать при тревоге", options.blink, 16),
        Options.Title("Какие строки показывать", 14, nil, nil, 24),
        Options.Strings("Быстрый выбор", items, options.preset, 0),
        Options.Title("Или поставь галочки вручную", 14, nil, nil, 16),
        Options.Filter(RowTitle('eOverflow'), options.eOverflow, 16),
        Options.Filter(RowTitle('eGo'), options.eGo, 16),
        Options.Filter(RowTitle('eOwn'), options.eOwn, 16),
        Options.Filter(RowTitle('mOverflow'), options.mOverflow, 16),
        Options.Filter(RowTitle('mGo'), options.mGo, 16),
        Options.Filter(RowTitle('mOwn'), options.mOwn, 16),
        Options.Filter(RowTitle('total'), options.total, 16),
    })

    LOG(PFX .. 'UMT options page registered, frame + style + scale + ' ..
        'numbers + blink + ' .. RowHowMany() .. ' rows')
end
