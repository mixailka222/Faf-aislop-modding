-- ReclaimPause - настройки мода.
--
-- Хранятся в профиле игрока под ключом "ReclaimPause". Теми же ключами
-- пользуется страница настроек (modules/options.lua), поэтому окно и мод
-- читают одно и то же значение и не расходятся во мнениях.
--
-- Мод работает и без мода "UI mod tools": если UMT нет, берутся значения
-- по умолчанию, а переключить мод можно только клавишей, назначенной игроком.

local Prefs = import('/lua/user/prefs.lua')

local PFX = 'ReclaimPause: '
local PREFS_KEY = 'ReclaimPause'

-- Значения по умолчанию. Те же, что выбраны при разработке.
local DEFAULTS = {
    enabled   = true,   -- мод работает
    highMass  = 70,     -- ставим на паузу, когда масса заполнена не меньше
                         -- ИЗМЕРЕНО 2026-10-10: игра сама прекращает
                         -- реклейм у инженеров на атак-муве около 76.5%.
                         -- Ставим порог НИЖЕ этого, иначе мод сработает
                         -- поздно: игра уже отпустит инженеров и они
                         -- разойдутся к точке атак-мува.
    lowMass   = 65,     -- снимаем паузу, когда масса заполнена не больше
    energyMin = 70,     -- паузу разрешаем, только если энергии не меньше
    minSec    = 3,      -- между переключениями не меньше стольких секунд
    releaseHoldSec = 3, -- столько секунд условие снятия должно держаться
                         -- подряд; 0 = отпускать сразу, как раньше.
                         -- 3 секунды вместо 10: при скорости расхода
                         -- около 3 процентных пунктов в секунду ожидание
                         -- в 10 секунд давало перелёт почти в 30 пунктов,
                         -- и мод отпускал инженеров сильно ниже порога.
    rescanSec = 3,      -- как часто пересобирать список инженеров
    startGrace = 15,    -- в первые N секунд матча обход не делается
    abortMove = true,   -- обрывать маршрут, чтобы инженер стоял на месте
    abortSec = 1,       -- как часто повторять обрыв маршрута, пока держим
    skipSec = 3,        -- сколько секунд НЕ трогать того, кого сняли
                         -- вручную. Игнорирование нужно только когда
                         -- приказ прочитать нельзя: у юнита без паузы
                         -- очередь читается, и пустая она честно.
                         -- Было 60 - это была дыра, инженер успевал
                         -- уехать к точке атак-мува и потерять приказ.
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

-- Приведение к допустимому виду. Нужно и на случай испорченного профиля,
-- и на случай absurdных значений из окна настроек.
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

---Перечитать настройки из профиля.
function ReclaimPauseLoadSettings()
    local ok, saved = pcall(function() return Prefs.GetFromCurrentProfile(PREFS_KEY) end)
    if ok and type(saved) == 'table' then
        ReclaimPauseCfg.enabled   = SaneBool(saved.enabled, DEFAULTS.enabled)
        ReclaimPauseCfg.highMass  = SaneInt(saved.highMass, DEFAULTS.highMass, 50, 100)
        ReclaimPauseCfg.lowMass   = SaneInt(saved.lowMass, DEFAULTS.lowMass, 0, 100)
        ReclaimPauseCfg.energyMin = SaneInt(saved.energyMin, DEFAULTS.energyMin, 0, 100)
        ReclaimPauseCfg.minSec    = SaneInt(saved.minSec, DEFAULTS.minSec, 0, 120)
        ReclaimPauseCfg.releaseHoldSec =
            SaneInt(saved.releaseHoldSec, DEFAULTS.releaseHoldSec, 0, 300)
        ReclaimPauseCfg.rescanSec = SaneInt(saved.rescanSec, DEFAULTS.rescanSec, 1, 60)
        -- Below 5 the first pass meets the game selecting the commander, and his selection is lost.
        ReclaimPauseCfg.startGrace = SaneInt(saved.startGrace, DEFAULTS.startGrace, 5, 300)
        ReclaimPauseCfg.abortMove = SaneBool(saved.abortMove, DEFAULTS.abortMove)
        ReclaimPauseCfg.abortSec = SaneInt(saved.abortSec, DEFAULTS.abortSec, 1, 30)
        ReclaimPauseCfg.skipSec = SaneInt(saved.skipSec, DEFAULTS.skipSec, 0, 600)
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
    -- порог снятия не может быть выше порога паузы, иначе мод залипнет
    if ReclaimPauseCfg.lowMass > ReclaimPauseCfg.highMass then
        ReclaimPauseCfg.lowMass = ReclaimPauseCfg.highMass
    end
end

---Сбросить настройки к значениям по умолчанию.
--
-- Вызывается клавишей, назначенной игроком, и галочкой сброса. Кнопки в окне UMT
-- сделать нельзя: мод UMT умеет только восемь типов элементов
-- (OptionsWindow.lua:238-412) и не содержит кнопки, а документированный
-- в Options.lua:316 вариант "table|fun(frame:Frame):Control" не
-- реализован - OptionsWindow.lua:188 перебирает buildTable как
-- таблицу.
--
-- Числа НЕ дублируются: берутся из DEFAULTS. Иначе правка
-- умолчаний когда-нибудь разъехалась бы со сбросом.
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

---Записать текущие значения в профиль.
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

---Ключ профиля нужен и странице настроек UMT.
function ReclaimPausePrefsKey()
    return PREFS_KEY
end

---Значения по умолчанию нужны странице настроек.
function ReclaimPauseDefaults()
    return DEFAULTS
end

---Короткая строка для лога.
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