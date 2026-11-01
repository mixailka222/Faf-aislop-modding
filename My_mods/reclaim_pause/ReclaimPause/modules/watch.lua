-- ReclaimPause - watches the storages and pauses reclaiming engineers.
--
-- While the mass storage is nearly full, reclaim has nowhere to go: the extra goes to
-- allies or burns. The mod pauses the engineers that reclaim and releases them once the
-- player spends mass again. A pause also needs enough energy: reclaim can yield energy, and
-- energy can run out while mass is full.
--
-- A pause keeps the order: EntityBeingReclaimed stays set, only effects and sound stop, and
-- OnUnpaused resumes the same target. Checked in the game for engineers on attack move.
--
-- The game has no call that lists the units, so engineers are found by a hidden selection,
-- only while the mod holds a pause and at most once in rescanSec seconds.
--
-- A scan only adds engineers. Release is decided for each unit from its own order, which
-- costs no selection, so a unit missing from a scan is never released.
--
-- Functions are exported as globals: the game discards what a module returns.

local GameMain = import('/lua/ui/game/gamemain.lua')
local CommandMode = import('/lua/ui/game/commandmode.lua')

local Settings = import('/mods/ReclaimPause/modules/settings.lua')

local PFX = 'ReclaimPause: '
local SCAN_SEC = 1        -- how often the storages and engineers are checked
-- The scan period comes from the setting rescanSec.
local rescanSec = 3

-- Orders the mod manages, by the `type` string of a UI command queue entry.
local MANAGED = {
    Reclaim = true,
    AggressiveMove = true,
    FormAggressiveMove = true,
    Patrol = true,
    FormPatrol = true,
}

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local running = false
local iterNo = 0
local switchIter = 0
local logTick = 0
local rescanIter = 0
local abortIter = 0
local abortCount = 0
local abortLogTick = 0
local engineerCount = 0
local restoreFails = {}    -- restore step -> how many times it failed
local holding = false      -- the mod holds the engineers paused now
local held = {}            -- id -> unit paused by the mod
local heldAt = {}          -- id -> pass on which it was paused
local skipUntil = {}       -- id -> pass until which the unit is left alone
local lowSinceIter = 0     -- pass since which the release condition holds, 0 = it does not
-- Why engineers stayed out of the pause, for the log. A table and not three locals:
-- TickOnce is at the limit of 32 upvalues.
local why = {
    skip = 0,      -- the player released it by hand
    player = 0,    -- already paused, not by the mod
    other = 0,     -- has an order the mod does not manage
}

--------------------------------------------------------------------------------
-- Reading the order
--------------------------------------------------------------------------------

-- Returns the type of the current order and whether the mod manages it. The type also
-- goes to the log, which shows why an engineer was released.
local function FrontKind(unit)
    local ok, queue = pcall(function() return unit:GetCommandQueue() end)
    if not ok or type(queue) ~= 'table' then
        return 'queue-error', false
    end
    local first = queue[1]
    if first == nil then
        return 'empty', false
    end
    return first.type, MANAGED[first.type] == true
end

--------------------------------------------------------------------------------
-- Unit checks. Each goes through pcall: the unit may have died since the last read.
--------------------------------------------------------------------------------

local function IsMine(unit)
    local ok, res = pcall(function() return unit:GetArmy() == GetFocusArmy() end)
    if not ok then
        return false
    end
    return res and true or false
end

local function HasCategory(unit, cat)
    local ok, res = pcall(function() return unit:IsInCategory(cat) end)
    if not ok or not res then
        return false
    end
    return true
end

local function IsAlive(unit)
    local ok, res = pcall(function() return unit:IsDead() end)
    if not ok then
        return false
    end
    return not res
end

-- UserUnit has no IsUnitState, that method belongs to the sim layer. A builder
-- has the unfinished unit in focus. A finished unit in focus means other work,
-- for example reclaiming that unit.
local function IsBuilding(unit)
    local ok, res = pcall(function()
        local focus = unit:GetFocus()
        return focus ~= nil and focus:GetFractionComplete() < 1
    end)
    if not ok then
        LOG(PFX .. 'IsBuilding FAILED: ' .. tostring(res))
        return false
    end
    return res
end

-- An unreadable unit counts as paused, so that pause orders do not repeat.
local function IsCurrentlyPaused(unit)
    local ok, res = pcall(GetIsPausedOfUnit, unit)
    if not ok then
        LOG(PFX .. 'GetIsPausedOfUnit FAILED: ' .. tostring(res))
        return true
    end
    return res
end

--------------------------------------------------------------------------------
-- Hidden scan of the engineers
--
-- UISelectionByCategory replaces the selection (addToSelection = false) with all engineers,
-- not only those on screen (onScreenOnly = false). The game selects engineers on a hotkey
-- the same way. The selection always returns, even after an error.
--------------------------------------------------------------------------------

-- If the check fails, the selection stays untouched: a missed pass costs one
-- second, a restarted command mode costs the player a build order.
local function PlayerInCommandMode()
    local ok, res = pcall(CommandMode.InCommandMode)
    if not ok then
        LOG(PFX .. 'InCommandMode FAILED: ' .. tostring(res))
        return true
    end
    return res
end

local function CollectEngineers(picked)
    local found = {}
    local n = 0
    for i = 1, table.getn(picked) do
        local unit = picked[i]
        if IsMine(unit) and IsAlive(unit) and not IsBuilding(unit) then
            if HasCategory(unit, 'ENGINEER') and not HasCategory(unit, 'COMMAND') then
                local id = unit:GetEntityId()
                found[id] = unit
                n = n + 1
            end
        end
    end
    return found, n
end

-- One step of giving the selection back. Each step has its own pcall: the next one has to
-- run even if this one failed. Scans and aborts repeat every few seconds, so a lasting
-- failure is logged the first time and then every hundredth.
local function RestoreStep(step, where, fn)
    local ok, err = pcall(fn)
    if ok then
        return
    end
    local n = (restoreFails[step] or 0) + 1
    restoreFails[step] = n
    if n == 1 or math.mod(n, 100) == 0 then
        WARN(PFX .. step .. ' FAILED x' .. tostring(n) .. ' (' .. where .. '): ' .. tostring(err))
    end
end

-- RestoreCommandMode takes no argument: with true it resets issuedOneCommand, and
-- StartCommandMode restarts the mode of the player. Callers skip the scan during a command
-- mode. The restored selection is compared with the saved one, and a mismatch goes to the
-- log.
local function WithAllEngineers(callback)
    local saved = nil
    local beforeN = 0
    local ok, err = pcall(function()
        CommandMode.CacheAndClearCommandMode()
        GameMain.SetIgnoreSelection(true)
        saved = GetSelectedUnits() or {}
        beforeN = table.getn(saved)
        UISelectionByCategory('ENGINEER', false, false, false, false)
        callback(GetSelectedUnits() or {})
    end)
    if saved then
        RestoreStep('SelectUnits', 'scan, ' .. tostring(beforeN) .. ' unit(s)',
                    function() SelectUnits(saved) end)
    end
    RestoreStep('SetIgnoreSelection', 'scan', function() GameMain.SetIgnoreSelection(false) end)
    RestoreStep('RestoreCommandMode', 'scan', function() CommandMode.RestoreCommandMode() end)
    if not ok then
        LOG(PFX .. 'WithAllEngineers FAILED: ' .. tostring(err))
        return false
    end

    local okSel, after = pcall(function() return GetSelectedUnits() or {} end)
    if okSel and beforeN ~= table.getn(after) then
        LOG(PFX .. 'WARNING: selection NOT restored: was ' ..
            tostring(beforeN) .. ' unit(s), now ' .. tostring(table.getn(after)))
    end
    return true
end

local function EnsureEngineers(force)
    if not force and (iterNo - rescanIter) * SCAN_SEC < rescanSec then
        return nil
    end
    -- Before rescanIter changes: the scan has to run on the first pass after
    -- the command mode ends, not rescanSec later.
    if PlayerInCommandMode() then
        return nil
    end
    local box = {}
    local ok = WithAllEngineers(function(picked)
        box.found, box.n = CollectEngineers(picked)
    end)
    rescanIter = iterNo
    if not ok then
        return nil
    end
    return box.found, box.n
end

--------------------------------------------------------------------------------
-- Applying the pause
--------------------------------------------------------------------------------

-- The pause is the SetPaused flag: the order stays and the reclaim stops. The engineer
-- still walks on, AbortMove below stops that. IssueUnitCommand(list, 'Pause') does not fit:
-- it clears the queue, so an attack move is lost, and as a toggle it drifts from
-- GetIsPaused.
local function PauseUnits(list, n)
    if n == 0 then
        return
    end
    local okS, errS = pcall(function() SetPaused(list, true) end)
    if not okS then
        LOG(PFX .. 'SetPaused(true) FAILED: ' .. tostring(errS))
    end
end

local function ResumeUnits(list, n)
    if n == 0 then
        return
    end
    local okS, errS = pcall(function() SetPaused(list, false) end)
    if not okS then
        LOG(PFX .. 'SetPaused(false) FAILED: ' .. tostring(errS))
    end
end

-- The pause flag stops the reclaim but not the movement, so an engineer on attack move
-- would walk on to its target. AbortNavigation stops it and leaves the queue alone.
-- SimCallback with true acts on the current selection, so the units are selected for a
-- moment, as in the scan.
local function AbortMove(list, n)
    if n == 0 then
        return
    end
    if not Settings.ReclaimPauseCfg.abortMove then
        return
    end
    if PlayerInCommandMode() then
        -- Due again at once, or the engineer walks on for another abortSec.
        abortIter = iterNo - Settings.ReclaimPauseCfg.abortSec
        return
    end
    abortIter = iterNo
    local saved = nil
    local beforeN = 0
    local ok, err = pcall(function()
        CommandMode.CacheAndClearCommandMode()
        GameMain.SetIgnoreSelection(true)
        saved = GetSelectedUnits() or {}
        beforeN = table.getn(saved)
        SelectUnits(list)
        SimCallback({ Func = 'AbortNavigation', Args = {} }, true)
    end)
    if saved then
        RestoreStep('SelectUnits', 'abort, ' .. tostring(beforeN) .. ' unit(s)',
                    function() SelectUnits(saved) end)
    end
    RestoreStep('SetIgnoreSelection', 'abort', function() GameMain.SetIgnoreSelection(false) end)
    RestoreStep('RestoreCommandMode', 'abort', function() CommandMode.RestoreCommandMode() end)
    if not ok then
        LOG(PFX .. 'AbortMove FAILED: ' .. tostring(err))
        return
    end
    -- Logged every ten aborts: the log has to show whether aborts happen at all.
    abortCount = abortCount + 1
    abortLogTick = abortLogTick + 1
    if abortLogTick >= 10 then
        abortLogTick = 0
        LOG(PFX .. 'abort issued x' .. tostring(abortCount) ..
            ' last for ' .. tostring(n) .. ' unit(s)')
    end
    local okSel, after = pcall(function() return GetSelectedUnits() or {} end)
    if okSel and beforeN ~= table.getn(after) then
        LOG(PFX .. 'WARNING: selection NOT restored after abort: was ' ..
            tostring(beforeN) .. ', now ' .. tostring(table.getn(after)))
    end
end

-- Seconds the engineer has been held, -1 if unknown.
local function HeldSecs(id)
    local at = heldAt[id]
    if at == nil then
        return -1
    end
    return (iterNo - at) * SCAN_SEC
end

-- An engineer the player released by hand stays out for skipSec seconds. This only covers
-- the case when its order cannot be read.
local function IsSkipped(id)
    local untilNo = skipUntil[id]
    if untilNo == nil then
        return false
    end
    if iterNo >= untilNo then
        skipUntil[id] = nil
        return false
    end
    return true
end

local function HeldCount()
    local n = 0
    for _ in pairs(held) do
        n = n + 1
    end
    return n
end

--------------------------------------------------------------------------------
-- Releasing everyone
--------------------------------------------------------------------------------

local function ReleaseAll(reason)
    local list = {}
    local n = 0
    for _, unit in pairs(held) do
        if IsCurrentlyPaused(unit) then
            list[n + 1] = unit
            n = n + 1
        end
    end
    ResumeUnits(list, n)
    local wasN = HeldCount()
    held = {}
    skipUntil = {}
    if wasN > 0 then
        LOG(PFX .. 'released ' .. tostring(wasN) .. ' engineer(s): ' .. tostring(reason))
    end
end

--------------------------------------------------------------------------------
-- Reading the storages
--------------------------------------------------------------------------------

local function FillOf(econ, res)
    if type(econ.maxStorage) ~= 'table' or type(econ.stored) ~= 'table' then
        return nil
    end
    local mx = econ.maxStorage[res]
    local st = econ.stored[res]
    if type(mx) ~= 'number' or type(st) ~= 'number' or mx <= 0 then
        return nil
    end
    return st / mx
end

--------------------------------------------------------------------------------
-- Main step
--------------------------------------------------------------------------------

-- What keeps the mod from pausing now, for the log.
local function Explain(cfg, massFill, energyFill)
    if not cfg.enabled then
        return 'MOD-DISABLED'
    end
    if massFill < cfg.highMass / 100 then
        return 'WAIT-MASS ' .. string.format('%.0f', massFill * 100) .. '%' ..
            ' (need ' .. string.format('%.0f', cfg.highMass) .. '%)'
    end
    if energyFill < cfg.energyMin / 100 then
        -- Both numbers matter: mass can be well above its threshold while energy delays the
        -- pause.
        return 'WAIT-ENERGY ' .. string.format('%.0f', energyFill * 100) .. '%' ..
            ' (need ' .. string.format('%.0f', cfg.energyMin) .. '%)' ..
            ', mass ' .. string.format('%.0f', massFill * 100) .. '%' ..
            ' of ' .. string.format('%.0f', cfg.highMass) .. '% - mass OK'
    end
    return 'THRESHOLDS-OK'
end

-- Why the mod still holds: the condition is not met, or the release time has not passed.
local function ExplainHold(cfg, massFill, holdSec)
    if not holding then
        return 'not-holding'
    end
    if massFill > cfg.lowMass / 100 then
        return 'mass-above-low'
    end
    local left = cfg.releaseHoldSec - holdSec
    if left < 0 then
        left = 0
    end
    return 'release-in ' .. tostring(math.floor(left)) .. 's'
end

---Manual check on a key assigned by the player: shows what the mod sees right now and why
---it did not act, without waiting minutes for the threshold.
function ReclaimPauseForceCheck()
    Settings.ReclaimPauseLoadSettings()
    local cfg = Settings.ReclaimPauseCfg

    local okE, econ = pcall(function() return GetEconomyTotals() end)
    if not okE or type(econ) ~= 'table' then
        LOG(PFX .. 'CHECK: economy unavailable')
        return
    end
    local massFill = FillOf(econ, 'MASS') or 0
    local energyFill = FillOf(econ, 'ENERGY') or 1

    local got, n = EnsureEngineers(true)

    LOG(PFX .. 'CHECK mass=' .. string.format('%.1f', massFill * 100) .. '%' ..
        ' energy=' .. string.format('%.1f', energyFill * 100) .. '%' ..
        ' needMass=' .. tostring(cfg.highMass) ..
        ' needEnergy=' .. tostring(cfg.energyMin) ..
        ' engineersFound=' .. (got and tostring(n) or '?') ..
        ' held=' .. tostring(HeldCount()) ..
        ' verdict=' .. Explain(cfg, massFill, energyFill) ..
        ' | ' .. Settings.ReclaimPauseSettingsLine())
end

-- Split from TickOnce to stay under the limit of 32 upvalues per function: exceeding it
-- stops the whole file from compiling. The verdict is always logged, so the state shows
-- without the hotkey.
local function PeriodicLog(cfg, massFill, energyFill, holdSec)
    logTick = logTick + 1
    -- More often near the threshold: that is where the mod races the game, which stops
    -- reclaim by itself.
    local logEvery = 15
    if massFill >= cfg.lowMass / 100 then
        logEvery = 5
    end
    if logTick < logEvery then
        return
    end
    logTick = 0
    LOG(PFX .. 'mass=' .. string.format('%.1f', massFill * 100) .. '%' ..
        ' energy=' .. string.format('%.1f', energyFill * 100) .. '%' ..
        ' engineers=' .. (engineerCount >= 0 and tostring(engineerCount) or '?') ..
        ' held=' .. tostring(HeldCount()) ..
        ' verdict=' .. Explain(cfg, massFill, energyFill) ..
        ' hold=' .. ExplainHold(cfg, massFill, holdSec) ..
        ' why=skip:' .. tostring(why.skip) ..
        ' player:' .. tostring(why.player) ..
        ' other:' .. tostring(why.other) ..
        ' | ' .. Settings.ReclaimPauseSettingsLine())
end

local function TickOnce()
    local okE, econ = pcall(function() return GetEconomyTotals() end)
    if not okE or type(econ) ~= 'table' then
        return
    end
    local massFill = FillOf(econ, 'MASS')
    if not massFill then
        return
    end
    local energyFill = FillOf(econ, 'ENERGY') or 1

    iterNo = iterNo + 1
    local cfg = Settings.ReclaimPauseCfg
    rescanSec = cfg.rescanSec

    -- Hysteresis over two thresholds. A release also needs the condition to hold for
    -- releaseHoldSec seconds: a short dip below lowMass changes nothing, and engineers do
    -- not flicker at the border.
    local holdSec = 0
    local want = holding
    if holding then
        if massFill <= cfg.lowMass / 100 then
            if lowSinceIter == 0 then
                lowSinceIter = iterNo
            end
            holdSec = (iterNo - lowSinceIter) * SCAN_SEC
            if holdSec >= cfg.releaseHoldSec then
                want = false
            end
        else
            lowSinceIter = 0
            holdSec = 0
        end
    else
        lowSinceIter = 0
        if massFill >= cfg.highMass / 100 then
            want = true
        end
    end

    -- A pause needs enough energy, otherwise the mod would keep engineers from collecting
    -- it. The check is symmetric: if energy drops while paused, the engineers are released.
    local energyOk = energyFill >= cfg.energyMin / 100
    if want and not energyOk then
        want = false
    end

    -- no switch sooner than minSec
    local sinceSec = (iterNo - switchIter) * SCAN_SEC
    if want ~= holding and sinceSec < cfg.minSec then
        want = holding
    end

    if not cfg.enabled then
        want = false
    end

    why.skip = 0
    why.player = 0
    why.other = 0

    -- The switch is recorded before the scan: after a switch the scan has to run at once.
    local changed = (want ~= holding)
    if changed then
        holding = want
        if not holding then
            lowSinceIter = 0
        end
        switchIter = iterNo
        rescanIter = iterNo - rescanSec
    end

    local fresh = nil
    local foundN = -1
    local graceLeft = cfg.startGrace - iterNo * SCAN_SEC
    -- The scan touches the selection (WithAllEngineers), so it runs only while the
    -- pause is active.
    if want and graceLeft <= 0 then
        local got, n = EnsureEngineers()
        if got then
            fresh = got
            foundN = n
            engineerCount = n
        end
    else
        -- No scan: -1 means "not searched" and is logged as "?", because zero and no data
        -- differ.
        engineerCount = -1
    end

    local release = {}
    local releaseN = 0
    local topause = {}
    local pauseN = 0

    if not want then
        -- Release everyone held. No scan is needed for that.
        for id, unit in pairs(held) do
            if IsCurrentlyPaused(unit) then
                release[releaseN + 1] = unit
                releaseN = releaseN + 1
            end
            LOG(PFX .. 'unit ' .. tostring(id) .. ' release, held ' ..
                tostring(HeldSecs(id)) .. 's')
            held[id] = nil
            heldAt[id] = nil
            skipUntil[id] = nil
        end
    else
        -- 1. Known engineers are checked directly, without the selection.
        for id, unit in pairs(held) do
            if not IsAlive(unit) then
                held[id] = nil
                heldAt[id] = nil
            else
                local kind, managed = FrontKind(unit)
                local actuallyPaused = IsCurrentlyPaused(unit)
                if managed then
                    if actuallyPaused then
                        held[id] = unit
                        -- The first two checks after the pause log the order as it is,
                        -- which shows whether it is lost or only unreadable.
                        if HeldSecs(id) <= 1 then
                            LOG(PFX .. 'unit ' .. tostring(id) ..
                                ' check after pause +' .. tostring(HeldSecs(id)) ..
                                's, order=' .. tostring(kind))
                        end
                    else
                        -- The player unpaused it, but the order is still ours and the
                        -- storage is full, so the pause returns. Leaving it alone would let
                        -- it finish the reclaim, reach the target and lose the order. To
                        -- keep the mod out, the player turns it off.
                        topause[pauseN + 1] = unit
                        pauseN = pauseN + 1
                        held[id] = unit
                        heldAt[id] = iterNo
                        LOG(PFX .. 'unit ' .. tostring(id) ..
                            ' manual unpause, but order=' .. tostring(kind) ..
                            ' - pause returned')
                    end
                elseif kind == 'empty' or kind == 'queue-error' then
                    -- An empty or unreadable queue does not prove that the order is done:
                    -- an engineer cannot reach its target within a second. A paused unit
                    -- stays held.
                    if actuallyPaused then
                        held[id] = unit
                        if HeldSecs(id) <= 1 then
                            LOG(PFX .. 'unit ' .. tostring(id) ..
                                ' check after pause +' .. tostring(HeldSecs(id)) ..
                                's, order=' .. tostring(kind))
                        end
                    else
                        skipUntil[id] = iterNo + cfg.skipSec
                        held[id] = nil
                        heldAt[id] = nil
                    end
                else
                    -- A specific foreign order (Guard, Build, Attack) is a reliable read:
                    -- release it.
                    local secs = HeldSecs(id)
                    if actuallyPaused then
                        release[releaseN + 1] = unit
                        releaseN = releaseN + 1
                    end
                    held[id] = nil
                    heldAt[id] = nil
                    LOG(PFX .. 'unit ' .. tostring(id) ..
                        ' released, current order=' .. tostring(kind) ..
                        ', held ' .. tostring(secs) .. 's')
                end
            end
        end

        -- 2. New candidates come only from a fresh scan.
        if fresh then
            for id, unit in pairs(fresh) do
                -- An engineer without a managed order has nothing worth pausing, and one
                -- already paused may be the doing of the player.
                local alreadyPaused = IsCurrentlyPaused(unit)
                local kind, managed = FrontKind(unit)
                if held[id] == nil then
                    if IsSkipped(id) then
                        why.skip = why.skip + 1
                    elseif alreadyPaused then
                        why.player = why.player + 1
                    elseif not managed then
                        why.other = why.other + 1
                    else
                        topause[pauseN + 1] = unit
                        pauseN = pauseN + 1
                        held[id] = unit
                        heldAt[id] = iterNo
                        LOG(PFX .. 'unit ' .. tostring(id) ..
                            ' PAUSE issued, order=' .. tostring(kind))
                    end
                end
            end
        end
    end

    if releaseN > 0 then
        ResumeUnits(release, releaseN)
    end
    if pauseN > 0 then
        PauseUnits(topause, pauseN)
        AbortMove(topause, pauseN)
    elseif cfg.abortMove and holding then
        -- An abort works once: an interrupted attack move finds its path again. So while
        -- the storage is full it repeats every abortSec seconds, or the engineer reaches
        -- its target.
        if (iterNo - abortIter) * SCAN_SEC >= cfg.abortSec then
            local alist = {}
            local an = 0
            for _id, aunit in pairs(held) do
                if IsCurrentlyPaused(aunit) then
                    an = an + 1
                    alist[an] = aunit
                end
            end
            if an > 0 then
                AbortMove(alist, an)
            end
        end
    end

    if changed then
        local what = 'RELEASED'
        if want then
            what = 'PAUSED'
        end
        LOG(PFX .. what .. ' mass=' .. string.format('%.1f', massFill * 100) .. '%' ..
            ' energy=' .. string.format('%.1f', energyFill * 100) .. '%' ..
            ' verdict=' .. Explain(cfg, massFill, energyFill) ..
            ' hold=' .. ExplainHold(cfg, massFill, holdSec) ..
            ' engineers=' .. (foundN >= 0 and tostring(foundN) or '?') ..
            ' nowPaused=' .. tostring(pauseN) ..
            ' nowReleased=' .. tostring(releaseN))
    end

    PeriodicLog(cfg, massFill, energyFill, holdSec)
end

--------------------------------------------------------------------------------
-- Loop. WaitSeconds cannot run inside pcall: a coroutine cannot yield through a C function.
--------------------------------------------------------------------------------

local function Loop()
    while running do
        -- An error would end this thread: the game logs it, but the mod stays
        -- stopped until the next match. Under pcall the loop goes on.
        local ok, err = pcall(TickOnce)
        if not ok then
            LOG(PFX .. 'CRASH in TickOnce: ' .. tostring(err))
        end
        WaitSeconds(SCAN_SEC)
    end
end

--------------------------------------------------------------------------------
-- Entry points
--------------------------------------------------------------------------------

---Apply changed settings on the fly. Called by the settings page.
function ReclaimPauseApplySettings()
    if not running then
        return
    end
    if Settings.ReclaimPauseCfg.enabled then
        switchIter = iterNo - Settings.ReclaimPauseCfg.minSec
        return
    end
    ReleaseAll('mod disabled')
    holding = false
end

function ReclaimPauseStart()
    if running then
        return
    end
    Settings.ReclaimPauseLoadSettings()
    running = true
    iterNo = 0
    -- The last switch counts as long ago, otherwise the first one would wait for minSec.
    switchIter = -(Settings.ReclaimPauseCfg.minSec)
    rescanIter = 0 - Settings.ReclaimPauseCfg.rescanSec
    logTick = 0
    engineerCount = 0
    holding = false
    held = {}
    heldAt = {}
    skipUntil = {}
    lowSinceIter = 0
    why.skip = 0
    why.player = 0
    why.other = 0
    LOG(PFX .. 'started, ' .. Settings.ReclaimPauseSettingsLine())
    ForkThread(Loop)
end

function ReclaimPauseStop()
    if not running then
        return
    end
    running = false
    ReleaseAll('mod stopped')
    holding = false
    LOG(PFX .. 'stopped')
end

function ReclaimPauseToggle()
    if Settings.ReclaimPauseCfg.enabled then
        Settings.ReclaimPauseCfg.enabled = false
        ReleaseAll('toggled off')
        holding = false
    else
        Settings.ReclaimPauseCfg.enabled = true
    end
    Settings.ReclaimPauseSaveSettings()
    Settings.ReclaimPausePushToWindow('enabled')
    switchIter = iterNo - Settings.ReclaimPauseCfg.minSec
    LOG(PFX .. 'toggled, ' .. Settings.ReclaimPauseSettingsLine())
end

-- The lobby builds the key map of a match, but UI mods join the game only inside
-- the session, so the lobby does not know the actions of this mod and drops the
-- keys the player assigned to them. They are installed here instead.
local function InstallKeys()
    local KeyMapper = import('/lua/keymap/keymapper.lua')
    local actions = KeyMapper.GetKeyActions()
    local keys = {}
    local n = 0
    for key, action in pairs(KeyMapper.GetCurrentKeyMap()) do
        if string.sub(action, 1, 13) == 'reclaimpause_' then
            keys[key] = actions[action]
            n = n + 1
        end
    end
    if n > 0 then
        IN_AddKeyMapTable(keys)
    end
    LOG(PFX .. 'hotkeys installed: ' .. tostring(n))
end

function ReclaimPauseOnCreateUI()
    ReclaimPauseStart()
    local ok, err = pcall(InstallKeys)
    if not ok then
        LOG(PFX .. 'hotkeys FAILED: ' .. tostring(err))
    end
end