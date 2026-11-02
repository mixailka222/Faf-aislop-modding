-- Test of the UMT settings page.
--
-- Run from the tests folder: lua test_options_unit.lua. The paths below are relative to it.
-- check.py does that with the Lua of the game, so this code follows its dialect.
--
-- The page code (options.lua) runs against a reproduction of the real UMT API, taken from
-- UMT's Options.lua and OptionVar.lua. Without it no test would execute the page, and an
-- error such as calling Bind on an object that has no such method would show up only in the
-- game, as a black screen.
--
-- The API reproduced here:
--
--   Opt(value)                        takes ONE argument
--   OptValueMetaTable.IsInstance()
--   LoadOptions()
--   Mods.__newindex / __index
--   LoadOptionsFile()
--   OptionVar:Bind(fn)                calls fn IMMEDIATELY
--   OptionVar:Save()
--   AddOptions(option, title, t)
--
-- Also checked, because it is easy to break silently: the slider ranges must not go beyond
-- the SaneInt bounds in settings.lua, otherwise the window and the mod would compute
-- different values.

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

local MOD = '../ReclaimPause/modules/'

do
PROFILE = {}
msgs = {}

function LOG(m) msgs[table.getn(msgs) + 1] = tostring(m) end

-- The mod starts through ForkThread. A stub is enough: the loop is not needed, only the
-- fact that the mod considers itself started.
function ForkThread(f) end

Prefs = {}
function Prefs.GetFromCurrentProfile(k) return PROFILE[k] end
function Prefs.SetToCurrentProfile(k, v) PROFILE[k] = v end

-- ------------------------------------------------------------ OptionVar.lua
local LazyMetaTable = {}
LazyMetaTable.__index = LazyMetaTable
function LazyMetaTable:__call() return self._v end
function LazyMetaTable:Set(v) self._v = v end

local OptionVarMetaTable = {}
OptionVarMetaTable.__index = OptionVarMetaTable
function OptionVarMetaTable:__call() return self._lv() end
function OptionVarMetaTable:Set(v)
  if self._prev == nil then self._prev = self._lv() end
  self._lv:Set(v)
  self:OnChange()
end
function OptionVarMetaTable:Reset()
  if self._prev ~= nil then
    self:Set(self._prev)
    self._prev = nil
  end
end
function OptionVarMetaTable:Bind(fn) self.OnChange = fn self:OnChange() end
function OptionVarMetaTable:Option() return self._o end
function OptionVarMetaTable:Raw() return self._lv end
function OptionVarMetaTable:OnChange() end
function OptionVarMetaTable:OnSave() end
function OptionVarMetaTable:Save()
  local t = PROFILE[self._m] or {}
  t[self._o] = self._lv()
  PROFILE[self._m] = t
  self:OnSave()
  self._prev = nil
end
function OptionVar(modOptionName, subOption, default)
  if default == nil then
    error('Attempt to set option ' .. modOptionName .. ':' .. subOption ..
          ' to nil by default, dont do that!')
  end
  local t = PROFILE[modOptionName] or {}
  local val = t[subOption]
  if val == nil then
    t[subOption] = default
    PROFILE[modOptionName] = t
    val = default
  end
  return setmetatable({ _m = modOptionName, _o = subOption,
                        _lv = setmetatable({ _v = val }, LazyMetaTable) },
    OptionVarMetaTable)
end

-- ---------------------------------------------------------- Options.lua
PAGES = {}
BUILDS = {}

local OptValueMetaTable = {}
function OptValueMetaTable.IsInstance(value)
  return OptValueMetaTable == getmetatable(value)
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
  return { type = 'filter', name = name, optionVar = optionVar, indent = indent }
end
function Option.Title(name, size, family, color, indent)
  return { type = 'title', name = name, indent = indent }
end
function Option.Slider(name, mn, mx, inc, optionVar, indent)
  return { type = 'slider', name = name, mn = mn, mx = mx, inc = inc,
           optionVar = optionVar, indent = indent }
end

-- Verbatim from UMT's Options.lua, including IsInstance instead of type().
local function LoadOptions(values, modName, prefix)
  local options = {}
  for optName, defaultValue in pairs(values) do
    local opt = prefix and (prefix .. "." .. optName) or optName
    if OptValueMetaTable.IsInstance(defaultValue) then
      options[optName] = OptionVar(modName, opt, defaultValue.value)
    elseif type(defaultValue) == "table" then
      options[optName] = LoadOptions(defaultValue, modName, opt)
    else
      options[optName] = OptionVar(modName, opt, defaultValue)
    end
  end
  return options
end

-- LoadOptionsFile is simplified here: instead of searching the disk it just calls our Main.
-- UMT works the same way: the file is found, Main is called.
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
  end
}
Option.Mods = setmetatable({}, ModsMeta)

UMT = { Options = Option }

function import(p)
  if p == '/mods/ReclaimPause/modules/settings.lua' then return MODULES.settings end
  if p == '/mods/ReclaimPause/modules/watch.lua' then return MODULES.watch end
  -- prefs has to be the real stub: settings.lua calls Prefs.SetToCurrentProfile, and with
  -- an empty {} that call would fail inside pcall.
  if p == '/lua/user/prefs.lua' then return Prefs end
  return {}
end
end

MODULES = {}

local env_s = MakeEnv()
LoadInto(MOD .. 'settings.lua', env_s)
MODULES.settings = env_s
local env_w = MakeEnv()
LoadInto(MOD .. 'watch.lua', env_w)
MODULES.watch = env_w
WATCH = env_w
SET = env_s

-- the settings page loads into its own environment, as the engine does
local env_o = MakeEnv()
LoadInto(MOD .. 'options.lua', env_o)
OPTIONS_MAIN = env_o.Main

local env_m = MakeEnv()
LoadInto(MOD .. 'main.lua', env_m)
SHIM = env_m.Main

-- The mod is started. In the game CreateUI has already run by the time the settings page
-- loads, so Bind calls Refresh on a live mod, and that is what is checked.
WATCH.ReclaimPauseStart()

-- The order in the game: UMT first calls Main of every mod with the __umt flag, then builds
-- the interface. The Main of the shim READS our field, which is the reason options.lua runs
-- at all.
print('=== 1: страница настроек UMT ===')
local okMain, errMain = pcall(env_m.Main, false)
if okMain then
    print('  [OK  ] modules/main.lua отработал без исключения')
else
    print('  [FAIL] modules/main.lua упал: ' .. tostring(errMain))
    os.exit(1)
end

local fails = Run("=== 2: поля и окно ===", function()
local fails = 0
local function check(cond, label)
  if cond then
    print('  [OK  ] ' .. label)
  else
    fails = fails + 1
    print('  [FAIL] ' .. label)
  end
end

local joined = table.concat(msgs, ' | ')

check(UMT.Options.Mods['ReclaimPause'] ~= nil,
      'страница зарегистрирована в UMT.Options.Mods')
check(BUILDS['ReclaimPause'] ~= nil, 'окно создано через AddOptions')

local expected = {
  'enabled', 'highMass', 'lowMass', 'energyMin', 'minSec',
  'releaseHoldSec', 'rescanSec', 'startGrace',
  'abortMove', 'abortSec', 'skipSec', 'resetFlag',
}
local opts = UMT.Options.Mods['ReclaimPause']
for i = 1, table.getn(expected) do
  local k = expected[i]
  local okv, v = pcall(function() return opts[k] end)
  check(okv and v ~= nil and type(v.Bind) == 'function',
        'поле ' .. k .. ' - OptionVar с методом Bind')
end

-- The page has to use OptionVar, not a raw Opt(): an Opt value is a plain table without a
-- Bind method, which is the error that crashed the game.
local build = BUILDS['ReclaimPause']
if build == nil then
  -- AddOptions was not called or failed. In the game this is a black screen, so going
  -- further makes no sense: fail with a clear message.
  check(false, 'AddOptions не отработал: окно не собрано, в игре это чёрный экран')
  return fails
end
local uses = 0
for i = 1, table.getn(build) do
  local r = build[i].optionVar
  if r ~= nil and type(r.Bind) == 'function' then uses = uses + 1 end
end
check(uses >= 12, 'в окне ' .. tostring(uses) .. ' полей, и все на OptionVar')

-- RANGES. A slider wider than SaneInt in settings.lua makes the window and the mod compute
-- different values, and it happens silently.
local sane = {
  highMass = { 50, 100 }, lowMass = { 0, 100 }, energyMin = { 0, 100 },
  minSec = { 0, 120 }, releaseHoldSec = { 0, 300 },
  rescanSec = { 1, 60 }, startGrace = { 10, 300 }, abortSec = { 1, 30 },
  skipSec = { 0, 60 },
}
local badRange = ''
for i = 1, table.getn(build) do
  local line = build[i]
  if line.type == 'slider' and line.optionVar ~= nil then
    local nm = line.optionVar:Option()
    if sane[nm] ~= nil then
      if line.mn < sane[nm][1] or line.mx > sane[nm][2] then
        badRange = badRange .. nm .. '[' .. tostring(line.mn) .. '..' ..
            tostring(line.mx) .. '] '
      end
    end
  end
end
check(badRange == '', 'диапазоны ползунков в пределах SaneInt' ..
      (badRange == '' and '' or (' НАРУШЕНО: ' .. badRange)))

-- A slider shows only multiples of its step, so a default between two steps
-- would be displayed as another number.
local defaults = SET.ReclaimPauseDefaults()
local offStep = ''
for i = 1, table.getn(build) do
  local line = build[i]
  if line.type == 'slider' and line.optionVar ~= nil then
    local nm = line.optionVar:Option()
    local steps = (defaults[nm] - line.mn) / line.inc
    if steps ~= math.floor(steps) then offStep = offStep .. nm .. ' ' end
  end
end
check(offStep == '', 'значение по умолчанию попадает на шаг ползунка' ..
      (offStep == '' and '' or (' НАРУШЕНО: ' .. offStep)))

-- MAIN POINT. Simulate the player moving the sliders: OptionVar:Set keeps the value in
-- memory and does NOT write the profile, exactly like the real one. If the mod reads the
-- profile, it sees the old value.
local opts = UMT.Options.Mods['ReclaimPause']
opts.highMass:Set(70)
opts.lowMass:Set(65)

check(SET.ReclaimPauseCfg.highMass == 70,
      'ползунок highMass=70 дошёл до мода, профиль не мешал (было ' ..
      tostring(SET.ReclaimPauseCfg.highMass) .. ')')
check(SET.ReclaimPauseCfg.lowMass == 65,
      'ползунок lowMass=65 дошёл до мода (было ' ..
      tostring(SET.ReclaimPauseCfg.lowMass) .. ')')

-- the values have to reach the profile too, otherwise the next match starts the mod with
-- the old numbers again
local prof = PROFILE['ReclaimPause']
check(type(prof) == 'table' and prof.highMass == 70 and prof.lowMass == 65,
      'живые значения записаны в профиль для следующего матча')

-- the safeguard for lowMass > highMass
opts.highMass:Set(60)
opts.lowMass:Set(90)
check(SET.ReclaimPauseCfg.lowMass <= SET.ReclaimPauseCfg.highMass,
      'lowMass > highMax опущен до highMass, мод не залипнет')

-- A value saved before the minimum was raised is lifted to the minimum.
PROFILE['ReclaimPause'].startGrace = 0
SET.ReclaimPauseLoadSettings()
check(SET.ReclaimPauseCfg.startGrace == 10,
      'сохранённый startGrace=0 поднят до минимума (было ' ..
      tostring(SET.ReclaimPauseCfg.startGrace) .. ')')
PROFILE['ReclaimPause'].startGrace = 15
PROFILE['ReclaimPause'].skipSec = 300
SET.ReclaimPauseLoadSettings()
check(SET.ReclaimPauseCfg.skipSec == 60,
      'сохранённый skipSec=300 опущен до максимума ползунка (было ' ..
      tostring(SET.ReclaimPauseCfg.skipSec) .. ')')
PROFILE['ReclaimPause'].skipSec = 3
SET.ReclaimPauseLoadSettings()

-- The OptionVars read the same old profile, and the page copies them into the mod on every change.
opts.startGrace:Raw():Set(0)
opts.skipSec:Raw():Set(300)
opts.minSec:Set(4)
check(SET.ReclaimPauseCfg.startGrace == 10,
      'старый startGrace=0 из окна не обходит минимум (было ' ..
      tostring(SET.ReclaimPauseCfg.startGrace) .. ')')
check(SET.ReclaimPauseCfg.skipSec == 60,
      'старый skipSec=300 из окна не обходит максимум (было ' ..
      tostring(SET.ReclaimPauseCfg.skipSec) .. ')')
check(PROFILE['ReclaimPause'].startGrace == 10 and PROFILE['ReclaimPause'].skipSec == 60,
      'в профиль попали значения в пределах (startGrace=' ..
      tostring(PROFILE['ReclaimPause'].startGrace) ..
      ', skipSec=' .. tostring(PROFILE['ReclaimPause'].skipSec) .. ')')
opts.startGrace:Raw():Set(15)
opts.skipSec:Raw():Set(3)
opts.minSec:Set(3)

-- put it back, so that the next checks start from a known value
opts.highMass:Set(90)
opts.lowMass:Set(80)

-- Bind calls fn IMMEDIATELY. So Refresh must have run and brought the settings to a
-- consistent state.
local cfg = SET.ReclaimPauseCfg
check(cfg ~= nil and cfg.releaseHoldSec ~= nil,
      'Refresh из окна применил настройки: releaseHoldSec=' ..
      tostring(cfg and cfg.releaseHoldSec))
check(string.find(joined, 'UMT options page registered') ~= nil,
      'мод отписался в лог, что страница зарегистрирована')
check(string.find(joined, 'FAILED') == nil,
      'в логе нет ни одной строки FAILED')

print('')
print('=== СБРОС НАСТРОЕК ГАЛОЧКОЙ В ОКНЕ ===')
-- UMT has no buttons: its options window knows only eight element types, and a button is
-- not among them. So the reset is a check box that clears itself after the reset.

-- Set values that are not in DEFAULTS, so that they are visible in the profile.
opts.highMass:Set(100)
opts.lowMass:Set(99)
opts.minSec:Set(9)

-- The check box cleared itself: reopening the window must not silently reset the settings
-- again.
opts.resetFlag:Set(true)
check(SET.ReclaimPauseCfg.highMass == 70,
      'галочка сбросила мод к умолчаниям: highMass 70 вместо ' ..
      tostring(SET.ReclaimPauseCfg.highMass))
check(SET.ReclaimPauseCfg.lowMass == 65,
      'lowMass сброшен в 65 (было 99), получено ' ..
      tostring(SET.ReclaimPauseCfg.lowMass))
check(opts.resetFlag() == false,
      'галочка сняла себя сама, второй тихий сброс при запуске не будет')

-- MAIN POINT OF THIS TEST. The sliders in the window have to show the defaults. Writing
-- options.x(value) instead of options.x:Set(value) only READS the value and discards the
-- argument: the reset would pass while the player sees the old 100/99 in the window.
check(opts.highMass() == 70,
      'ползунок в окне показывает 70, а не старое 100 (получено ' ..
      tostring(opts.highMass()) .. ')')
check(opts.lowMass() == 65,
      'ползунок снятия показывает 65, а не 99 (получено ' ..
      tostring(opts.lowMass()) .. ')')
check(opts.minSec() == SET.ReclaimPauseDefaults().minSec,
      'ползунок интервала вернулся к значению по умолчанию (получено ' ..
      tostring(opts.minSec()) .. ')')

-- The writing flag must not stay stuck: after a reset the slider has to control the setting
-- again.
opts.highMass:Set(88)
check(SET.ReclaimPauseCfg.highMass == 88,
      'после сброса мод снова живой: ползунок снова влияет на настройку (получено ' ..
      tostring(SET.ReclaimPauseCfg.highMass) .. ')')

-- The log has a line about the reset: the check box really worked and did not act idle.
local after = table.concat(msgs, ' | ')
check(string.find(after, 'RESET FROM PAGE') ~= nil,
      'в лог попала строка RESET FROM PAGE')

print('')
print('=== СБРОС И ПЕРЕКЛЮЧЕНИЕ ГОРЯЧЕЙ КЛАВИШЕЙ ===')
-- Hotkeys change the settings past the page. Any slider move makes the page read
-- all its OptionVars, so they must already hold the new values.
opts.highMass:Set(95)
SET.ReclaimPauseResetDefaults()
check(opts.highMass() == SET.ReclaimPauseDefaults().highMass,
      'сброс клавишей дошёл до ползунка (получено ' .. tostring(opts.highMass()) .. ')')
opts.minSec:Set(7)
check(SET.ReclaimPauseCfg.highMass == SET.ReclaimPauseDefaults().highMass,
      'движение другого ползунка не вернуло порог после сброса клавишей (получено ' ..
      tostring(SET.ReclaimPauseCfg.highMass) .. ')')

WATCH.ReclaimPauseToggle()
check(opts.enabled() == false, 'выключение клавишей дошло до галочки в окне')
opts.minSec:Set(8)
check(SET.ReclaimPauseCfg.enabled == false,
      'движение ползунка не включило мод обратно')
WATCH.ReclaimPauseToggle()
check(opts.enabled() == true, 'включение клавишей дошло до галочки в окне')

opts.highMass:Set(91)
check(SET.ReclaimPauseCfg.highMass == 91,
      'после клавиш ползунок снова управляет настройкой')

print('')
print('=== CANCEL В ОКНЕ НЕ ОТМЕНЯЕТ ГОРЯЧИЕ КЛАВИШИ ===')
-- OK in the UMT window calls Save on every OptionVar, Cancel calls Reset.
local function Window(method)
  for i = 1, table.getn(expected) do
    local var = opts[expected[i]]
    var[method](var)
  end
end
Window('Save')

SET.ReclaimPauseResetDefaults()
Window('Reset')
check(SET.ReclaimPauseCfg.highMass == SET.ReclaimPauseDefaults().highMass,
      'Cancel не вернул порог после сброса клавишей (получено ' ..
      tostring(SET.ReclaimPauseCfg.highMass) .. ')')

WATCH.ReclaimPauseToggle()
Window('Reset')
check(SET.ReclaimPauseCfg.enabled == false,
      'Cancel не включил мод обратно после выключения клавишей')
WATCH.ReclaimPauseToggle()

-- A slider moved before the key has already remembered the value Cancel returns to.
opts.highMass:Set(85)
Window('Save')
opts.highMass:Set(91)
SET.ReclaimPauseResetDefaults()
Window('Reset')
check(SET.ReclaimPauseCfg.highMass == SET.ReclaimPauseDefaults().highMass,
      'Cancel не вернул порог, сдвинутый до сброса клавишей (получено ' ..
      tostring(SET.ReclaimPauseCfg.highMass) .. ')')

-- The toggle key changes one setting, so Cancel still undoes a slider move.
opts.highMass:Set(85)
Window('Save')
opts.highMass:Set(91)
WATCH.ReclaimPauseToggle()
Window('Reset')
check(SET.ReclaimPauseCfg.highMass == 85,
      'клавиша включения не мешает Cancel откатить ползунок (получено ' ..
      tostring(SET.ReclaimPauseCfg.highMass) .. ')')
WATCH.ReclaimPauseToggle()

return fails
end)

print('')
print('=== ИТОГ ===')
local total = fails
if total > 0 then
    print('провалено проверок: ' .. tostring(total))
    os.exit(1)
end
print('все проверки пройдены')
