-- Тест страницы настроек UMT.
--
-- ПОЧЕМУ ТЕСТ НУЖЕН. Мод однажды упал в игре чёрным экраном: options.lua
-- вызвал метод Bind у объекта, у которого такого метода нет. Код страницы
-- не исполнялся НИ ОДНИМ тестом - про ошибку узнали только в игре.
--
-- Этот тест воспроизводит настоящий API UMT по исходникам
-- mods/umt/modules/Options.lua и mods/umt/modules/OptionVar.lua, без
-- выдумок:
--
--   Opt(value)                        Options.lua:400-402, ОДИН аргумент
--   OptValueMetaTable.IsInstance()    Options.lua:335-337
--   LoadOptions()                     Options.lua:339-358
--   Mods.__newindex / __index         Options.lua:378-396
--   LoadOptionsFile()                 Options.lua:361-376
--   OptionVar:Bind(fn)                OptionVar.lua:73-76, вызывает СРАЗУ
--   OptionVar:Save()                  OptionVar.lua:41-47
--   AddOptions(option, title, t)      Options.lua:317-319
--
-- Заодно проверяется вещь, которую легко сломать молча: диапазоны ползунков
-- не должны выходить за границы SaneInt в settings.lua, иначе окно и мод
-- станут считать разные значения.

-- Run from the tests folder: the paths below are relative to it. check.py does
-- that with the Lua of the game, so this code follows its dialect.
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

-- Мод запускается через ForkThread. Здесь достаточно заглушки: цикл нам
-- не нужен, нужен только факт, что мод считает себя запущенным.
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

-- Дословно по Options.lua:339-358, включая IsInstance вместо type()
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

-- LoadOptionsFile у нас упрощён: вместо поиска по диску он просто зовёт
-- наш Main. Именно так и работает UMT: файл нашёлся, Main вызван.
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
  -- prefs обязан возвращаться настоящим: settings.lua делает
  -- Prefs.SetToCurrentProfile, и при заглушке {} он падает в pcall.
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

-- страница настроек грузится в собственное окружение, как это делает движок
local env_o = MakeEnv()
LoadInto(MOD .. 'options.lua', env_o)
OPTIONS_MAIN = env_o.Main

local env_m = MakeEnv()
LoadInto(MOD .. 'main.lua', env_m)
SHIM = env_m.Main

-- Мод запущен. В игре к моменту загрузки страницы настроек CreateUI уже
-- отработал, поэтому Bind вызывает Refresh на живом моде - это и проверяем.
WATCH.ReclaimPauseStart()

-- Настоящий порядок в игре: сначала UMT зовёт Main каждого мода с флагом
-- __umt, потом строит интерфейс. Main шима ЧИТАЕТ наше поле - это и есть
-- причина, по которой options.lua вообще выполняется.
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

-- Страница должна использовать ИМЕННО OptionVar, а не сырые Opt().
-- Раньше здесь стояло options.highMass = Opt(...): тип табличный, метода
-- Bind нет - ровно та ошибка, что роняла игру.
local build = BUILDS['ReclaimPause']
if build == nil then
  -- AddOptions не вызвали или упали на нём. В игре это и есть чёрный
  -- экран, поэтому дальше идти бессмысленно - падаем с внятным текстом.
  check(false, 'AddOptions не отработал: окно не собрано, в игре это чёрный экран')
  return fails
end
local uses = 0
for i = 1, table.getn(build) do
  local r = build[i].optionVar
  if r ~= nil and type(r.Bind) == 'function' then uses = uses + 1 end
end
check(uses >= 12, 'в окне ' .. tostring(uses) .. ' полей, и все на OptionVar')

-- ДИАПАЗОНЫ. Ползунок шире, чем SaneInt в settings.lua, - окно и мод
-- будут считать разные значения, и это молча.
local sane = {
  highMass = { 50, 100 }, lowMass = { 0, 100 }, energyMin = { 0, 100 },
  minSec = { 0, 120 }, releaseHoldSec = { 0, 300 },
  rescanSec = { 1, 60 }, startGrace = { 0, 300 }, abortSec = { 1, 30 },
  skipSec = { 0, 600 },
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

-- ГЛАВНОЕ. Имитируем работу игрока с ползунками: OptionVar:Set держит
-- значение в памяти и НЕ пишет в профиль - ровно как настоящий
-- (OptionVar.lua:24-30). Если мод читает профиль, он увидит старое.
local opts = UMT.Options.Mods['ReclaimPause']
opts.highMass:Set(70)
opts.lowMass:Set(65)

check(SET.ReclaimPauseCfg.highMass == 70,
      'ползунок highMass=70 дошёл до мода, профиль не мешал (было ' ..
      tostring(SET.ReclaimPauseCfg.highMass) .. ')')
check(SET.ReclaimPauseCfg.lowMass == 65,
      'ползунок lowMass=65 дошёл до мода (было ' ..
      tostring(SET.ReclaimPauseCfg.lowMass) .. ')')

-- значения обязаны попасть и в профиль: иначе в следующем матче мод
-- снова стартует со старых чисел
local prof = PROFILE['ReclaimPause']
check(type(prof) == 'table' and prof.highMass == 70 and prof.lowMass == 65,
      'живые значения записаны в профиль для следующего матча')

-- предохранитель от залипания при lowMass > highMass
opts.highMass:Set(60)
opts.lowMass:Set(90)
check(SET.ReclaimPauseCfg.lowMass <= SET.ReclaimPauseCfg.highMass,
      'lowMass > highMax опущен до highMass, мод не залипнет')

-- возвращаем как было, чтобы следующие проверки считались от известного
opts.highMass:Set(90)
opts.lowMass:Set(80)

-- Bind вызывается СРАЗУ (OptionVar.lua:75). Значит Refresh обязан был
-- отработать и привести настройки в согласованное состояние.
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
-- Кнопки UMT не умеет: OptionsWindow.lua:238-412 знает всего восемь
-- типов элементов, кнопки среди них нет. Поэтому сброс сделан
-- галочкой, которая после сброса снимает себя сама.

-- Ставим значения, которых нет в DEFAULTS: их видно в профиле.
opts.highMass:Set(100)
opts.lowMass:Set(99)
opts.minSec:Set(9)

-- Галочка снята с себя сама: повторное открытие окна не должно
-- молча сбросить настройки ещё раз.
opts.resetFlag:Set(true)
check(SET.ReclaimPauseCfg.highMass == 70,
      'галочка сбросила мод к умолчаниям: highMass 70 вместо ' ..
      tostring(SET.ReclaimPauseCfg.highMass))
check(SET.ReclaimPauseCfg.lowMass == 65,
      'lowMass сброшен в 65 (было 99), получено ' ..
      tostring(SET.ReclaimPauseCfg.lowMass))
check(opts.resetFlag() == false,
      'галочка сняла себя сама, второй тихий сброс при запуске не будет')

-- ГЛАВНОЕ ДЛЯ ЭТОГО ТЕСТА. Ползунки в окне обязаны показывать
-- умолчания. Если писать options.x(значение) вместо
-- options.x:Set(значение), то по OptionVar.lua:18-20 вызов только
-- ЧИТАЕТ значение и аргумент выбрасывает: сброс пройдёт, а игрок
-- увидит в окне старые 100/99 - ровно тот симптом, с которым
-- пришли к нам.
check(opts.highMass() == 70,
      'ползунок в окне показывает 70, а не старое 100 (получено ' ..
      tostring(opts.highMass()) .. ')')
check(opts.lowMass() == 65,
      'ползунок снятия показывает 65, а не 99 (получено ' ..
      tostring(opts.lowMass()) .. ')')
check(opts.minSec() == SET.ReclaimPauseDefaults().minSec,
      'ползунок интервала вернулся к значению по умолчанию (получено ' ..
      tostring(opts.minSec()) .. ')')

-- Флаг writing не должен залипнуть: после сброса ползунок снова
-- обязан управлять настройкой.
opts.highMass:Set(88)
check(SET.ReclaimPauseCfg.highMass == 88,
      'после сброса мод снова живой: ползунок снова влияет на настройку (получено ' ..
      tostring(SET.ReclaimPauseCfg.highMass) .. ')')

-- В лог попала строка о сбросе - видно, что галочка реально
-- сработала, а не подействовала вхолостую.
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
