# -*- coding: utf-8 -*-
"""Тест страницы настроек UMT.

ПОЧЕМУ ТЕСТ НУЖЕН. Версия 15 упала в игре чёрным экраном: options.lua
вызвал метод Bind у объекта, у которого такого метода нет. Код страницы
не исполнялся НИ ОДНИМ тестом - про ошибку узнали только в игре.

Этот тест воспроизводит настоящий API UMT по исходникам
mods/umt/modules/Options.lua и mods/umt/modules/OptionVar.lua, без
выдумок:

  Opt(value)                        Options.lua:400-402, ОДИН аргумент
  OptValueMetaTable.IsInstance()    Options.lua:335-337
  LoadOptions()                     Options.lua:339-358
  Mods.__newindex / __index         Options.lua:378-396
  LoadOptionsFile()                 Options.lua:361-376
  OptionVar:Bind(fn)                OptionVar.lua:73-76, вызывает СРАЗУ
  OptionVar:Save()                  OptionVar.lua:41-47
  AddOptions(option, title, t)      Options.lua:317-319

Заодно проверяется вещь, которую легко сломать молча: диапазоны ползунков
не должны выходить за границы SaneInt в settings.lua, иначе окно и мод
станут считать разные значения.
"""
import io
import os
import sys

from lupa import luajit21 as lupa

HERE = os.path.dirname(os.path.abspath(__file__))
MOD = os.path.join(os.path.dirname(HERE), "ReclaimPause")


def rd(p):
    return io.open(p, encoding="utf-8").read()


settings_src = rd(MOD + r"\modules\settings.lua")
watch_src = rd(MOD + r"\modules\watch.lua")
main_src = rd(MOD + r"\modules\main.lua")
options_src = rd(MOD + r"\modules\options.lua")

lua = lupa.LuaRuntime(unpack_returned_tuples=True)
make_env = lua.eval("function() local t = {} setmetatable(t, {__index = _G}) return t end")
loader = lua.eval("""function(src, env)
  local f, err = loadstring(src)
  if not f then error(err) end
  setfenv(f, env)
  return f()
end""")

# --------------------------------------------------------------- окружение
STUBS = r'''
PROFILE = {}
msgs = {}

function LOG(m) msgs[#msgs + 1] = tostring(m) end

-- Мод запускается через ForkThread. Здесь достаточно заглушки: цикл нам
-- не нужен, нужен только факт, что мод считает себя запущенным.
function ForkThread(f) end

Prefs = {}
function Prefs.GetFromCurrentProfile(k) return PROFILE[k] end
function Prefs.SetToCurrentProfile(k, v) PROFILE[k] = v end

-- ------------------------------------------------------------ OptionVar.lua
local OptionVarMetaTable = {}
OptionVarMetaTable.__index = OptionVarMetaTable
function OptionVarMetaTable:__call() return self._v end
function OptionVarMetaTable:Set(v) self._v = v self:OnChange() end
function OptionVarMetaTable:Bind(fn) self.OnChange = fn self:OnChange() end
function OptionVarMetaTable:Option() return self._o end
function OptionVarMetaTable:Raw() return self end
function OptionVarMetaTable:OnChange() end
function OptionVarMetaTable:OnSave() end
function OptionVarMetaTable:Save()
  local t = PROFILE[self._m] or {}
  t[self._o] = self._v
  PROFILE[self._m] = t
  self:OnSave()
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
  return setmetatable({ _m = modOptionName, _o = subOption, _v = val },
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
'''

lua.execute(STUBS)
G = lua.globals()
G['MODULES'] = lua.eval('{}')

env_s = make_env()
loader(settings_src, env_s)
G['MODULES']['settings'] = env_s
env_w = make_env()
loader(watch_src, env_w)
G['MODULES']['watch'] = env_w
G['WATCH'] = env_w
G['SET'] = env_s

# страница настроек грузится в собственное окружение, как это делает движок
env_o = make_env()
loader(options_src, env_o)
G['OPTIONS_MAIN'] = env_o['Main']

env_m = make_env()
loader(main_src, env_m)
G['SHIM'] = env_m['Main']

# Мод запущен. В игре к моменту загрузки страницы настроек CreateUI уже
# отработал, поэтому Bind вызывает Refresh на живом моде - это и проверяем.
G['WATCH']['ReclaimPauseStart']()

# Настоящий порядок в игре: сначала UMT зовёт Main каждого мода с флагом
# __umt, потом строит интерфейс. Main шима ЧИТАЕТ наше поле - это и есть
# причина, по которой options.lua вообще выполняется.
print("=== 1: страница настроек UMT ===")
try:
    env_m['Main'](False)
    print("  [OK  ] modules/main.lua отработал без исключения")
except Exception as e:
    print("  [FAIL] modules/main.lua упал: " + str(e))
    sys.exit(1)

CHECK = r'''
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
  'releaseHoldSec', 'probeSec', 'rescanSec', 'startGrace',
  'abortMove', 'abortSec', 'skipSec', 'resetFlag',
}
local opts = UMT.Options.Mods['ReclaimPause']
for i = 1, #expected do
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
for i = 1, #build do
  local r = build[i].optionVar
  if r ~= nil and type(r.Bind) == 'function' then uses = uses + 1 end
end
check(uses >= 13, 'в окне ' .. tostring(uses) .. ' полей, и все на OptionVar')

-- ДИАПАЗОНЫ. Ползунок шире, чем SaneInt в settings.lua, - окно и мод
-- будут считать разные значения, и это молча.
local sane = {
  highMass = { 50, 100 }, lowMass = { 0, 100 }, energyMin = { 0, 100 },
  minSec = { 0, 120 }, releaseHoldSec = { 0, 300 }, probeSec = { 0, 60 },
  rescanSec = { 1, 60 }, startGrace = { 0, 300 }, abortSec = { 1, 30 },
  skipSec = { 0, 600 },
}
local badRange = ''
for i = 1, #build do
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
check(cfg ~= nil and cfg.releaseHoldSec ~= nil and cfg.probeSec ~= nil,
      'Refresh из окна применил настройки: releaseHoldSec=' ..
      tostring(cfg and cfg.releaseHoldSec) .. ' probeSec=' ..
      tostring(cfg and cfg.probeSec))
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
opts.probeSec:Set(0)

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
check(opts.probeSec() == 5,
      'прибор вернулся к 5 секундам, а не остался выключенным (получено ' ..
      tostring(opts.probeSec()) .. ')')

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

return fails
'''

try:
    fails = lua.execute(CHECK) or 0
except Exception as e:
    print("  [FAIL] проверка упала: " + str(e))
    fails = 1

print("")
print("=== ИТОГ ===")
if fails:
    print("провалено проверок: %d" % fails)
    sys.exit(1)
print("все проверки пройдены")
