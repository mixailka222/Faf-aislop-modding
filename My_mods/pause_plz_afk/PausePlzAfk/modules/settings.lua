-- PausePlzAfk - message text settings.
--
-- Stored in the player profile under the key 'PausePlzAfk'. The UMT options
-- page (modules/options.lua) uses the same key and field names, so the
-- window and the mod read the same value.
--
-- The mod works without the 'UI mod tools' mod: if UMT is missing, this file
-- is still read at fire time and supplies the defaults.

local Prefs = import('/lua/user/prefs.lua')

local PREFS_KEY = 'PausePlzAfk'
local MSG_LIMIT = 200

local DEFAULTS = {
    msgText = 'plz hold pause im afk',
}

-- Current values. Read from here and from options.lua.
PauseAfkCfg = {
    msgText = DEFAULTS.msgText,
}

---Clean one message: non-string or blank becomes the default, longer than
-- the chat limit is cut. Cutting is byte-based, so a character split by the
-- cut is dropped whole (else the chat gets broken bytes). Single source for
-- both the mod and the options page.
function PauseAfkSaneMsg(val)
    if type(val) ~= 'string' then
        return DEFAULTS.msgText
    end
    if string.find(val, '%S') == nil then
        return DEFAULTS.msgText
    end
    if string.len(val) > MSG_LIMIT then
        -- A UTF-8 continuation byte (128..191) right after the cut means the cut
        -- splits a character: step back to its first byte and cut before it.
        local cut = MSG_LIMIT
        while cut > 0 do
            local nextByte = string.byte(val, cut + 1)
            if nextByte < 128 or nextByte >= 192 then
                break
            end
            cut = cut - 1
        end
        val = string.sub(val, 1, cut)
        if val == '' then
            return DEFAULTS.msgText
        end
    end
    return val
end

---Reread settings from the profile. Call it at fire time, not at load:
-- the player may have edited the text after the match interface was built.
function PauseAfkLoadSettings()
    local ok, saved = pcall(function() return Prefs.GetFromCurrentProfile(PREFS_KEY) end)
    if ok and type(saved) == 'table' then
        PauseAfkCfg.msgText = PauseAfkSaneMsg(saved.msgText)
    else
        PauseAfkCfg.msgText = DEFAULTS.msgText
    end
end

---Write current values to the profile.
function PauseAfkSaveSettings()
    local ok, err = pcall(function()
        Prefs.SetToCurrentProfile(PREFS_KEY, {
            msgText = PauseAfkCfg.msgText,
        })
    end)
    if not ok then
        LOG('PausePlzAfk: SaveSettings FAILED: ' .. tostring(err))
    end
end

---Defaults are needed by the UMT options page.
function PauseAfkDefaults()
    return DEFAULTS
end

---Short line for the log. The message itself can be anything, tostring only.
function PauseAfkSettingsLine()
    return 'msgText=' .. tostring(PauseAfkCfg.msgText)
end
