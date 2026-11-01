-- ReclaimPause - settings of the mod.
--
-- Stored in the player profile under the key "ReclaimPause". The settings page
-- (modules/options.lua) uses the same key and field names, so the window and the mod read
-- the same values.
--
-- Without the "UI mod tools" mod the defaults apply, and only a key assigned by the player
-- toggles the mod.

local Prefs = import('/lua/user/prefs.lua')

local PFX = 'ReclaimPause: '
local PREFS_KEY = 'ReclaimPause'

local DEFAULTS = {
    enabled   = true,   -- the mod is on
    highMass  = 70,     -- pause at this mass fill. Below 76.5%: there the game stops reclaim of
                         -- attack-moving engineers itself and they walk on
    lowMass   = 65,     -- release at this mass fill
    energyMin = 70,     -- pause only with at least this energy fill
    minSec    = 3,      -- seconds between switches, at least
    releaseHoldSec = 3, -- seconds the release condition has to hold, 0 = at once. At a spend rate of
                         -- 3 points a second, 10 would overshoot by almost 30 points
    rescanSec = 3,      -- how often the list of engineers is rebuilt
    startGrace = 15,    -- no scan in the first N seconds of a match: the player needs the selection
    abortMove = true,   -- abort the path, so that the engineer stands still
    abortSec = 1,       -- how often the abort repeats while the pause holds
    skipSec = 3,        -- seconds to leave alone an engineer the player released by hand, only
                         -- matters when its order cannot be read
}

-- Текущие значения. Читаются из этого файла и из options.lua.
ReclaimPauseCfg = {
    enabled   = DEFAULTS.enabled,
    highMass  = DEFAULTS.highMass,
    lowMass   = DEFAULTS.lowMass,
    energyMin = DEFAULTS.energyMin,
    minSec    = DEFAULTS.minSec,
    releaseHoldSec = DEFAULTS.releaseHoldSec,
    rescanSec = DEFAULTS.rescanSec,
    startGrace = DEFAULTS.startGrace,
    abortMove = DEFAULTS.abortMove,
    abortSec = DEFAULTS.abortSec,
    skipSec = DEFAULTS.skipSec,
}

-- Set by the UMT page. Without UMT it stays nil and there is nothing to update.
local windowPush = nil

-- Limits for numbers. They cover a damaged profile and values from the window.
local function SaneInt(val, def, lo, hi)
    if type(val) ~= 'number' then
        return def
    end
    local n = math.floor(val)
    if n < lo then
        return lo
    end
    if n > hi then
        return hi
    end
    return n
end

local function SaneBool(val, def)
    if val == nil then
        return def
    end
    if val then
        return true
    end
    return false
end

---Copy the values into ReclaimPauseCfg within their limits. The profile and the page both
---pass here: an old profile can hold a value the sliders no longer reach.
---@param values table
function ReclaimPauseApplyValues(values)
    ReclaimPauseCfg.enabled   = SaneBool(values.enabled, DEFAULTS.enabled)
    ReclaimPauseCfg.highMass  = SaneInt(values.highMass, DEFAULTS.highMass, 50, 100)
    ReclaimPauseCfg.lowMass   = SaneInt(values.lowMass, DEFAULTS.lowMass, 0, 100)
    ReclaimPauseCfg.energyMin = SaneInt(values.energyMin, DEFAULTS.energyMin, 0, 100)
    ReclaimPauseCfg.minSec    = SaneInt(values.minSec, DEFAULTS.minSec, 0, 120)
    ReclaimPauseCfg.releaseHoldSec =
        SaneInt(values.releaseHoldSec, DEFAULTS.releaseHoldSec, 0, 300)
    ReclaimPauseCfg.rescanSec = SaneInt(values.rescanSec, DEFAULTS.rescanSec, 1, 60)
    -- At 5 the first pass can still meet the game selecting the commander, and his selection is lost.
    ReclaimPauseCfg.startGrace = SaneInt(values.startGrace, DEFAULTS.startGrace, 10, 300)
    ReclaimPauseCfg.abortMove = SaneBool(values.abortMove, DEFAULTS.abortMove)
    ReclaimPauseCfg.abortSec = SaneInt(values.abortSec, DEFAULTS.abortSec, 1, 30)
    ReclaimPauseCfg.skipSec = SaneInt(values.skipSec, DEFAULTS.skipSec, 0, 60)
    -- The release threshold above the pause threshold would keep the mod switching.
    if ReclaimPauseCfg.lowMass > ReclaimPauseCfg.highMass then
        ReclaimPauseCfg.lowMass = ReclaimPauseCfg.highMass
    end
end

---Reread the settings from the profile.
function ReclaimPauseLoadSettings()
    local ok, saved = pcall(function() return Prefs.GetFromCurrentProfile(PREFS_KEY) end)
    if ok and type(saved) == 'table' then
        ReclaimPauseApplyValues(saved)
    else
        ReclaimPauseCfg.enabled   = DEFAULTS.enabled
        ReclaimPauseCfg.highMass  = DEFAULTS.highMass
        ReclaimPauseCfg.lowMass   = DEFAULTS.lowMass
        ReclaimPauseCfg.energyMin = DEFAULTS.energyMin
        ReclaimPauseCfg.minSec    = DEFAULTS.minSec
        ReclaimPauseCfg.releaseHoldSec = DEFAULTS.releaseHoldSec
        ReclaimPauseCfg.rescanSec = DEFAULTS.rescanSec
        ReclaimPauseCfg.startGrace = DEFAULTS.startGrace
        ReclaimPauseCfg.abortMove = DEFAULTS.abortMove
        ReclaimPauseCfg.abortSec = DEFAULTS.abortSec
        ReclaimPauseCfg.skipSec = DEFAULTS.skipSec
    end
end

---Reset the settings to their defaults. Called by a key assigned by the player and by the
---reset check box: UMT has no button element.
function ReclaimPauseResetDefaults()
    ReclaimPauseCfg.enabled   = DEFAULTS.enabled
    ReclaimPauseCfg.highMass  = DEFAULTS.highMass
    ReclaimPauseCfg.lowMass   = DEFAULTS.lowMass
    ReclaimPauseCfg.energyMin = DEFAULTS.energyMin
    ReclaimPauseCfg.minSec    = DEFAULTS.minSec
    ReclaimPauseCfg.releaseHoldSec = DEFAULTS.releaseHoldSec
    ReclaimPauseCfg.rescanSec = DEFAULTS.rescanSec
    ReclaimPauseCfg.startGrace = DEFAULTS.startGrace
    ReclaimPauseCfg.abortMove = DEFAULTS.abortMove
    ReclaimPauseCfg.abortSec  = DEFAULTS.abortSec
    ReclaimPauseCfg.skipSec   = DEFAULTS.skipSec
    ReclaimPauseSaveSettings()
    ReclaimPausePushToWindow()
    LOG(PFX .. 'settings reset to defaults: mass=' ..
        tostring(DEFAULTS.lowMass) .. '..' .. tostring(DEFAULTS.highMass) ..
        ' energyMin=' .. tostring(DEFAULTS.energyMin))
    return ReclaimPauseSettingsLine()
end

---The UMT page passes a function that copies ReclaimPauseCfg into its OptionVars.
function ReclaimPauseBindWindow(fn)
    windowPush = fn
end

---Hotkeys change the settings past the page. The page must get the new values:
---its next slider move reads all OptionVars and would write the old ones back.
---@param name? string the only setting that changed, nil means all of them
function ReclaimPausePushToWindow(name)
    if windowPush == nil then
        return
    end
    local ok, err = pcall(windowPush, name)
    if not ok then
        LOG(PFX .. 'PushToWindow FAILED: ' .. tostring(err))
    end
end

---Write the current values to the profile.
function ReclaimPauseSaveSettings()
    local ok, err = pcall(function()
        Prefs.SetToCurrentProfile(PREFS_KEY, {
            enabled   = ReclaimPauseCfg.enabled,
            highMass  = ReclaimPauseCfg.highMass,
            lowMass   = ReclaimPauseCfg.lowMass,
            energyMin = ReclaimPauseCfg.energyMin,
            minSec    = ReclaimPauseCfg.minSec,
            releaseHoldSec = ReclaimPauseCfg.releaseHoldSec,
            rescanSec = ReclaimPauseCfg.rescanSec,
            startGrace = ReclaimPauseCfg.startGrace,
            abortMove = ReclaimPauseCfg.abortMove,
            abortSec = ReclaimPauseCfg.abortSec,
            skipSec = ReclaimPauseCfg.skipSec,
        })
    end)
    if not ok then
        LOG(PFX .. 'SaveSettings FAILED: ' .. tostring(err))
    end
end

---The profile key is needed by the UMT page.
function ReclaimPausePrefsKey()
    return PREFS_KEY
end

---The settings page needs the defaults.
function ReclaimPauseDefaults()
    return DEFAULTS
end

---Short line for the log.
function ReclaimPauseSettingsLine()
    return 'enabled=' .. tostring(ReclaimPauseCfg.enabled) ..
        ' mass=' .. tostring(ReclaimPauseCfg.lowMass) .. '..' ..
        tostring(ReclaimPauseCfg.highMass) ..
        ' energyMin=' .. tostring(ReclaimPauseCfg.energyMin) ..
        ' minSec=' .. tostring(ReclaimPauseCfg.minSec) ..
        ' holdSec=' .. tostring(ReclaimPauseCfg.releaseHoldSec) ..
        ' rescanSec=' .. tostring(ReclaimPauseCfg.rescanSec) ..
        ' startGrace=' .. tostring(ReclaimPauseCfg.startGrace) ..
        ' abortMove=' .. tostring(ReclaimPauseCfg.abortMove)
end