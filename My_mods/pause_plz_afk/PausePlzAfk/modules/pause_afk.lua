-- PausePlzAfk - auto-pause when the player missed the match start.
-- Based on PPA by 4z0t.
--
-- How it works: 5 seconds after the interface is built, look at the current
-- selection (the game selects the ACU itself around 2.5s in). If every
-- selected unit sits without orders for 10 sim ticks (~1s), the player is
-- considered AFK: request a pause and tell everyone in chat. Fires once.
--
-- Fixes vs the original: the message text lives in the player profile
-- (modules/settings.lua, editable from the UMT options window) instead of a
-- wrongly-pathed Message.lua that was never read; all selected units
-- are checked, not just the first; the wait for a selection has a timeout
-- instead of looping forever; chat goes to everyone (single-argument call).

local PauseAfkMsgText = 'plz hold pause im afk'
local PauseAfkMsgTag = '<<message sent with "Pause Plz AFK" mod>>'

local PauseAfkWaitStart = 5
local PauseAfkWaitPick = 60
local PauseAfkRounds = 10
local PauseAfkTickTries = 20

-- Forward declaration: PauseAfkMain calls it, the body sits at the file end.
-- Without this, the name resolves to a global (nil) at compile time.
local PauseAfkReadMsg

function PauseAfkOnCreateUI()
    ForkThread(PauseAfkMain)
end

function PauseAfkMain()
    WaitSeconds(PauseAfkWaitStart)

    -- Wait for a selection to appear (with a timeout, not forever).
    local picked = nil
    local spent = 0
    while spent < PauseAfkWaitPick do
        local okPick, sel = pcall(function() return GetSelectedUnits() end)
        if okPick and sel ~= nil and sel[1] ~= nil then
            picked = sel
            break
        end
        WaitSeconds(0.5)
        spent = spent + 0.5
    end
    if picked == nil then
        LOG('PausePlzAfk: no selection found, staying idle')
        return
    end

    -- 10 checks, one sim tick apart. Any busy unit means the player is here.
    local round = 1
    while round <= PauseAfkRounds do
        local okPick, sel = pcall(function() return GetSelectedUnits() end)
        if okPick and sel ~= nil and sel[1] ~= nil then
            picked = sel
        end
        if PauseAfkAnyBusy(picked) then
            return
        end
        PauseAfkWaitTick()
        round = round + 1
    end

    -- Everyone idle: pause (unless someone already did) and explain in chat.
    -- The text is read fresh here, not at load: the player may have edited
    -- it in the UMT window after the interface was built.
    local msgText = PauseAfkReadMsg()

    local okPaused, paused = pcall(function() return SessionIsPaused() end)
    if okPaused and paused then
        LOG('PausePlzAfk: game already paused, skip pause request')
    else
        local okReq = pcall(function() SessionRequestPause() end)
        if not okReq then
            LOG('PausePlzAfk: SessionRequestPause failed')
        end
    end

    local okOne = pcall(function()
        SessionSendChatMessage({ to = 'all', Chat = true, text = msgText })
    end)
    if not okOne then
        LOG('PausePlzAfk: first chat message failed')
    end

    WaitSeconds(1)

    local okTwo = pcall(function()
        SessionSendChatMessage({ to = 'all', Chat = true, text = PauseAfkMsgTag })
    end)
    if not okTwo then
        LOG('PausePlzAfk: second chat message failed')
    end
end

-- True if at least one unit in the list has orders (or its state is
-- unknown, e.g. it died mid-check: unknown counts as busy so we never
-- pause on a guess).
function PauseAfkAnyBusy(picked)
    local slot = 1
    while picked[slot] ~= nil do
        local holder = picked[slot]
        local okIdle, idle = pcall(holder.IsIdle, holder)
        if not okIdle or not idle then
            return true
        end
        slot = slot + 1
    end
    return false
end

-- Wait for one sim tick, with a wall-clock cap: if the game is already
-- paused by someone else, GameTick() stops growing and a bare
-- 'while GameTick() < tickEnd' would hang forever.
function PauseAfkWaitTick()
    local tickEnd = GameTick() + 1
    local tries = 0
    while tries < PauseAfkTickTries and GameTick() < tickEnd do
        WaitSeconds(0.1)
        tries = tries + 1
    end
end

-- Message text for the chat: fresh from the profile, default on any failure
-- (no settings file, broken profile, no Prefs). Never errors out: every
-- read goes through pcall or rawget.
PauseAfkReadMsg = function()
    local okMod, Settings = pcall(import, '/mods/PausePlzAfk/modules/settings.lua')
    if okMod and type(Settings) == 'table' then
        local LoadSettings = rawget(Settings, 'PauseAfkLoadSettings')
        if type(LoadSettings) == 'function' then
            pcall(LoadSettings)
        end
        local cfg = rawget(Settings, 'PauseAfkCfg')
        if type(cfg) == 'table' then
            local seen = rawget(cfg, 'msgText')
            if type(seen) == 'string' and seen ~= '' then
                return seen
            end
        end
    end
    return PauseAfkMsgText
end
