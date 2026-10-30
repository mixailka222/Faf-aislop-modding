# -*- coding: utf-8 -*-
# Юнит-тест мода ReclaimPause (settings.lua + watch.lua).
#
# ВАЖНО про окружение. У каждого файла мода в FAF своё окружение: присваивание
# "глобального" имени попадает в таблицу модуля, а НЕ в общий _G. Тест обязан
# это воспроизводить, иначе пропустит ошибку, из-за которой версия 3 не
# стартовала в игре: settings.lua грузился, а watch.lua не видел его функций.
# Поэтому каждый файл выполняется в отдельной таблице с __index = _G,
# а import() возвращает именно её.
#
# Проверяем: гистерезис, правило энергии в обе стороны, минимальный интервал,
# освобождение при смене приказа, уважение к ручному снятию паузы, отказ
# трогать строителей/командиров/чужих/мёртвых, распознавание всех форм
# приказа, применение настроек на ходу, и два требования безопасности:
#   - выделение возвращается;
#   - обход НЕ имеет права снимать паузу с живого инженера (баг версии 2).

import io, os, sys
from lupa import luajit21 as lupa

HERE = os.path.dirname(os.path.abspath(__file__))
BASE = os.path.join(os.path.dirname(HERE), "ReclaimPause", "modules")
settings_src = io.open(BASE + r"\settings.lua", encoding="utf-8").read()
watch_src = io.open(BASE + r"\watch.lua", encoding="utf-8").read()

lua = lupa.LuaRuntime(unpack_returned_tuples=True)

STUBS = r'''
msgs = {}
STORE = {}
WORLD = {}
SEL = {}
SCAN_CALLS = 0
PAUSED = {}
MASSPCT = 0.5
ENERGYPCT = 1.0
MAXM = 1000.0
THREAD = nil
HIDE_QUEUE_WHEN_PAUSED = false
MODULES = {}

Prefs = {}
function Prefs.GetFromCurrentProfile(k) return STORE[k] end
function Prefs.SetToCurrentProfile(k, v) STORE[k] = v end

GameMain = {}
function GameMain.SetIgnoreSelection(v) IGNORE_SEL = v end

CommandMode = {}
function CommandMode.CacheAndClearCommandMode() CMDMODE_CACHED = true end
function CommandMode.RestoreCommandMode(v) CMDMODE_CACHED = false end

-- import() возвращает таблицу модуля. Так же ведёт себя движок.
function import(p)
  if MODULES['settings'] and p == '/mods/ReclaimPause/modules/settings.lua' then
    return MODULES['settings']
  end
  if p == '/lua/user/prefs.lua' then return Prefs end
  if p == '/lua/ui/game/gamemain.lua' then return GameMain end
  if p == '/lua/ui/game/commandmode.lua' then return CommandMode end
  return {}
end

function LOG(m) msgs[#msgs + 1] = tostring(m) end

function GetFocusArmy() return 1 end

-- Счётчик реклейма САМОЙ ИГРЫ. В игре это econData.reclaimed из
-- ui/game/economy.lua:382, из него работает колонка "реклейм" в панели
-- ресурсов. RECLAIMED - накопительное значение, прирост за секунду и
-- есть текущая добыча реклеймом.
RECLAIMED = 0
function GetEconomyTotals()
  return { stored = { MASS = MASSPCT * MAXM, ENERGY = ENERGYPCT * MAXM },
           maxStorage = { MASS = MAXM, ENERGY = MAXM },
           reclaimed = { MASS = RECLAIMED, ENERGY = RECLAIMED } }
end
function AddReclaimed(d) RECLAIMED = RECLAIMED + (d or 0) end

function GetSelectedUnits() return SEL end
function SelectUnits(list) SEL = list or {} end

function UISelectionByCategory(cat, addToSel, onScreen, toggle, isReset)
  SCAN_CALLS = SCAN_CALLS + 1
  local out = {}
  local n = 0
  if cat == 'ENGINEER' then
    for i = 1, #WORLD do
      local u = WORLD[i]
      if u.cats['ENGINEER'] then
        n = n + 1
        out[n] = u
      end
    end
  end
  SEL = out
end

ABORTED = {}
function SimCallback(cb, applyToSelection)
  if cb and cb.Func == 'AbortNavigation' and applyToSelection then
    local list = GetSelectedUnits() or {}
    for i = 1, #list do ABORTED[#ABORTED + 1] = list[i].id end
  end
end

function SetPaused(list, paused)
  for i = 1, #list do
    PAUSED[list[i].id] = paused
  end
end

function GetIsPaused(list)
  return PAUSED[list[1].id] == true
end

-- Одиночные варианты движка. Их наличие в реальной сборке НЕ подтверждено,
-- поэтому мод обязан читать их через pcall. Здесь они есть, и рядом есть
-- отдельный сценарий, где их нет.
-- Одиночная функция движка. Её наличие в сборке НЕ подтверждено, поэтому
-- мод обязан читать её через pcall. Тут она ЕСТЬ; сценарии убирают её
-- целиком (GetIsPausedOfUnit = nil) или заменяют на бросающую.
REAL_OF_UNIT = nil
function GetIsPausedOfUnit(unit)
  return PAUSED[unit.id] == true
end
REAL_OF_UNIT = GetIsPausedOfUnit
function SetOfUnitMode(mode)
  -- 'yes' = обычная, 'nil' = функции нет вовсе, 'throw' = есть, но бросает
  if mode == 'nil' then
    GetIsPausedOfUnit = nil
  elseif mode == 'throw' then
    GetIsPausedOfUnit = function() error('boom', 2) end
  else
    GetIsPausedOfUnit = REAL_OF_UNIT
  end
end

-- Имитация Sync.Reclaim. Реальную публикацию делает sim/Prop.lua:384-392,
-- а живое падение массы - sim/Prop.lua:181 в OnDamage.
-- mode 'drop' = масса падает у n пропов, 'same' = не падает,
-- 'dead' = запись стала false, как это делает CleanupUILabel (Prop.lua:400).
-- Канал недоступен: таблицы нет. Прибор обязан сказать sync=n/a, а не
-- показать props=0, потому что это разные вещи.
function SyncBreak()
  Sync.Reclaim = nil
end

function PropMode(mode, n)
  local r = {}
  if mode == 'dead' then
    r[1] = false
    r[2] = { mass = 400, position = { 0, 0, 0 } }
  else
    local base = 500
    if mode == 'fall' then
      -- Масса падает на каждом вызове: тогда КАЖДЫЙ замер прибора видит
      -- падение. Иначе падение видно только один раз, и в периодическую
      -- строку оно может не попасть.
      PROPBASE = (PROPBASE or base) - 10
      base = PROPBASE
    end
    for i = 1, (n or 3) do
      r[i] = { mass = base - i, position = { 0, 0, 0 } }
    end
  end
  Sync.Reclaim = r
end

-- Отпустить реклейм так, как это делает движок: вызывает колбэки
-- OnStopReclaim у юнитов. target=nil означает "остов доеден".
function FireReclaimStop(units, target)
  for _, u in ipairs(units) do
    local lst = (u.cbs or {})['OnStopReclaim']
    if lst then
      for _, fn in ipairs(lst) do fn(u, target) end
    end
  end
end

function ForkThread(f) THREAD = f end
function WaitSeconds(x) error('__LOOPSTOP__', 0) end

function MakeUnit(id, opts)
  opts = opts or {}
  local u = {}
  u.id = id
  u.army = opts.army or 1
  u.dead = opts.dead or false
  u.cats = opts.cats or {}
  u.queue = opts.queue or {}
  u.building = opts.building or false
  u.cbs = {}
  function u:GetArmy() return self.army end
  function u:IsDead() return self.dead end
  function u:IsInCategory(c) return self.cats[c] == true end
  -- IsUnitState в игре из слоя интерфейса НЕдоступен (проверено:
  -- recl=0/0 при 120 инженерах). Заглушка отвечает только на
  -- 'Building' - это нужно проверке зданий. На 'Reclaiming' ответа нет,
  -- и код не должен на него опираться.
  u.reclaiming = opts.reclaiming or false
  function u:SetReclaiming(v) self.reclaiming = v end
  function u:IsUnitState(s) return s == 'Building' and self.building or false end
  -- Шаг в одну сторону: mod меряет пройденное расстояние.
  function u:Walk(dx, dz)
    self.pos = { self.pos[1] + (dx or 0), self.pos[2], self.pos[3] + (dz or 0) }
  end
  function u:GetCommandQueue()
    -- Воспроизводим реальное поведение движка: у юнита на паузе очередь
    -- читается пустой, хотя приказ на месте.
    if HIDE_QUEUE_WHEN_PAUSED and PAUSED[self.id] then return {} end
    return self.queue
  end
  function u:GetEntityId() return self.id end
  -- sim/Unit.lua:4171. Bez etogo metoda pcall v mode poglotil by otkaz
  -- i kolbek nikogda ne podnyalsya by - a imenno eto i nado proverit.
  function u:AddUnitCallback(fn, kind)
    self.cbs[kind] = self.cbs[kind] or {}
    table.insert(self.cbs[kind], fn)
  end
  u.pos = opts.pos or { 0, 0, 0 }
  function u:GetPosition() return self.pos end
  function u:SetPos(x, z) self.pos = { x, 0, z } end
  return u
end

CRASHES = 0
function RunOnce()
  if THREAD == nil then return false end
  local ok, err = pcall(THREAD)
  if not ok and not string.find(tostring(err), '__LOOPSTOP__', 1, true) then
    msgs[#msgs + 1] = 'UNEXPECTED: ' .. tostring(err)
    CRASHES = CRASHES + 1
    return false
  end
  return true
end

function Reset(mass, energy)
  WATCH.ReclaimPauseStop()
  STORE = {}
  MASSPCT = mass or 0.5
  ENERGYPCT = energy or 1.0
  MAXM = 1000.0
  WORLD = {}
  SEL = {}
  PAUSED = {}
  ABORTED = {}
  SCAN_CALLS = 0
  HIDE_QUEUE_WHEN_PAUSED = false
  -- Sync.Reclaim публикует {mass=...} из sim/Prop.lua:390. Падение массы
  -- пропа между замерами означает, что реклейм идёт прямо сейчас.
  Sync = { Reclaim = {} }
  PROPBASE = nil
  RECLAIMED = 0
  -- Наличие GetIsPausedOfUnit здесь НЕ задаётся: иначе проба успевает
  -- пройти внутри ReclaimPauseStart и закэшировать положительный ответ.
  -- Сценарии, которым это нужно, ставят режим ДО вызова Reset.
  CRASHES = 0
  msgs = {}
  THREAD = nil
  WATCH.ReclaimPauseStart()
  -- ВАЖНО: настройки задаются ПОСЛЕ старта, потому что
  -- ReclaimPauseStart() перечитывает их из профиля и затирает ручные.
  SET.ReclaimPauseCfg.startGrace = 0
  SET.ReclaimPauseCfg.rescanSec = 3
  SET.ReclaimPauseCfg.skipSec = 3
  SET.ReclaimPauseCfg.abortSec = 2
  SET.ReclaimPauseCfg.abortMove = true
  SET.ReclaimPauseCfg.releaseHoldSec = 0
  SET.ReclaimPauseCfg.probeSec = 0
end

function SetHideQueue(v) HIDE_QUEUE_WHEN_PAUSED = v end

function Forget(u)
  for i = 1, #WORLD do
    if WORLD[i] == u then table.remove(WORLD, i) return end
  end
end
'''

SCENARIOS = r'''
local ENGINEER  = { ENGINEER = true }
local CMD       = { ENGINEER = true, COMMAND = true }
local AM        = { { CommandType = 'AggressiveMove' } }
local AM_SCRIPT = { { CommandType = 'Script', LuaParams = { TaskName = 'AttackMove' } } }
local RECLAIM_N = { { CommandType = 19 } }
local PATROL    = { { CommandType = 'Patrol' } }
local ATTACK    = { { CommandType = 'Attack', Target = { Type = 'Unit' } } }
local BUILDQ    = { { CommandType = 'Build' } }

local fails = 0
local function check(cond, label)
  if cond then
    print('  [OK  ] ' .. label)
  else
    fails = fails + 1
    print('  [FAIL] ' .. label)
    -- ПОСЛЕДНИЕ ЗАПИСИ ЛОГА. Без них провал бесполезен: приходится
    -- гадать, что мод делал. Три хвоста показывают причину сразу.
    local n = table.getn(msgs)
    local from = n - 2
    if from < 1 then from = 1 end
    for i = from, n do
      print('         log[' .. tostring(i) .. ']: ' .. tostring(msgs[i]))
    end
  end
end

local function isPaused(id) return PAUSED[id] == true end
local function eng(id, queue, extra)
  local o = { cats = ENGINEER, queue = queue }
  if extra then for k, v in pairs(extra) do o[k] = v end end
  return MakeUnit(id, o)
end
local function add(u) WORLD[#WORLD + 1] = u return u end

print('')
print('=== 0: ОКРУЖЕНИЕ МОДУЛЯ (именно тут ломалась версия 3) ===')
check(rawget(_G, 'ReclaimPauseCfg') == nil,
      'ReclaimPauseCfg НЕ является общим глобалом - окружение модуля воспроизведено')
check(type(SET.ReclaimPauseCfg) == 'table', 'settings виден через таблицу модуля')
check(type(WATCH.ReclaimPauseStart) == 'function', 'watch виден через таблицу модуля')

print('')
print('=== 1: масса полна, энергии хватает -> пауза сразу ===')
Reset(0.95, 1.0)
add(eng(100, AM))
RunOnce()
check(isPaused(100), 'инженер на атак-мув поставлен на паузу при массе 95%')

print('')
print('=== 2: между порогами остаётся на паузе (нет дребезга) ===')
MASSPCT = 0.85
RunOnce(); RunOnce(); RunOnce()
check(isPaused(100), 'при массе 85% инженер остался на паузе')

print('')
print('=== 3: расход массы -> пауза снята ===')
-- Пороги после измерения порога игры: 65..70 (было 80..90).
-- Снятие теперь только при 65% и ниже.
MASSPCT = 0.60
for _ = 1, 6 do RunOnce() end
check(not isPaused(100),
      'при массе 60% (ниже lowMass=65) пауза снята')

print('')
print('=== 4: чаще заданного интервала переключаться нельзя ===')
Reset(0.95, 1.0)
add(eng(100, AM))
RunOnce()
check(isPaused(100), 'поставили на паузу на первом же проходе')
-- minSec после правки равен 3 (было 5), поэтому и ждать три секунды.
MASSPCT = 0.10
RunOnce(); RunOnce()
check(isPaused(100), 'через 2 с (меньше minSec=3) пауза ещё держится')
RunOnce()
check(not isPaused(100), 'на 3-й секунде пауза снята')

print('')
print('=== 5: смена приказа -> освобождение ===')
Reset(0.95, 1.0)
local u5 = add(eng(100, AM))
RunOnce()
check(isPaused(100), 'поставили на паузу')
u5.queue = BUILDQ
RunOnce()
check(not isPaused(100), 'приказ сменился - пауза снята сама')

print('')
print('=== 6: полное хранилище - мод держит даже после ручного снятия ===')
Reset(0.95, 1.0)
add(eng(100, AM))
RunOnce()
check(isPaused(100), 'поставили на паузу')
PAUSED[100] = false                 -- игрок снял паузу руками
RunOnce()
check(isPaused(100),
      'мод вернул паузу: приказ на месте, хранилище полно')
for _ = 1, 3 do RunOnce() end
check(isPaused(100), 'и дальше держит: хранилище не опустело, отпускать не за что')

-- а отпускает мод по делу - когда хранилище действительно опустело
Reset(0.95, 1.0)
add(eng(104, AM))
RunOnce()
check(isPaused(104), 'поставили на паузу при полном хранилище')
MASSPCT = 0.30
for _ = 1, 20 do RunOnce() end
check(not isPaused(104), 'при пустом хранилище инженер отпущен')

print('')
print('=== 7: строителей и командиров не трогаем ===')
Reset(0.95, 1.0)
add(MakeUnit(200, { cats = ENGINEER, queue = AM, building = true }))
add(MakeUnit(201, { cats = CMD, queue = AM }))
RunOnce()
check(not isPaused(200), 'инженер со статусом Building не тронут')
check(not isPaused(201), 'командир не тронут')

print('')
print('=== 8: чужие и мёртвые не тронуты ===')
Reset(0.95, 1.0)
add(MakeUnit(300, { cats = ENGINEER, queue = AM, army = 2 }))
add(MakeUnit(301, { cats = ENGINEER, queue = AM, dead = true }))
RunOnce()
check(not isPaused(300), 'инженер чужой армии не тронут')
check(not isPaused(301), 'мёртвый инженер не тронут')

print('')
print('=== 9: распознаются все формы приказа ===')
Reset(0.95, 1.0)
add(eng(401, AM))
add(eng(402, AM_SCRIPT))
add(eng(403, RECLAIM_N))
add(eng(404, PATROL))
add(eng(405, ATTACK))
RunOnce()
check(isPaused(401), 'AggressiveMove (строка)')
check(isPaused(402), 'Script + TaskName=AttackMove')
check(isPaused(403), 'Reclaim (число 19)')
check(isPaused(404), 'Patrol (строка)')
check(not isPaused(405), 'обычная атака по юниту - не наш случай')

print('')
print('=== 10: выключение мода отпускает инженеров ===')
Reset(0.95, 1.0)
add(eng(100, AM))
RunOnce()
check(isPaused(100), 'поставили на паузу')
WATCH.ReclaimPauseToggle()
check(not isPaused(100), 'после выключения инженер отпущен')
MASSPCT = 0.50
RunOnce(); RunOnce()
check(not isPaused(100), 'выключенный мод не паузит заново')
WATCH.ReclaimPauseToggle()
MASSPCT = 0.95
RunOnce()
check(isPaused(100), 'после включения снова работает')

print('')
print('=== 11: юнит умер на паузе -> мод восстанавливается ===')
Reset(0.95, 1.0)
local u11 = add(eng(100, AM))
RunOnce()
u11.dead = true
for _ = 1, 7 do RunOnce() end
add(eng(101, AM))
for _ = 1, 6 do RunOnce() end
check(isPaused(101), 'после смерти первого новый инженер взят под управление')

print('')
print('=== 12: нулевая вместимость не роняет мод ===')
Reset(0.95, 1.0)
add(eng(100, AM))
RunOnce()
MAXM = 0
RunOnce()
MAXM = 1000
check(true, 'деление на ноль пережито')

print('')
print('=== 13: инженер БЕЗ приказа модом не трогается (pauseIdle удалён) ===')
Reset(0.95, 1.0)
add(eng(100, {}))
RunOnce()
check(not isPaused(100),
      'простаивающий инженер без приказа НЕ ставится на паузу')

Reset(0.95, 1.0)
add(eng(101, AM))
RunOnce()
check(isPaused(101),
      'инженер с НАШИМ приказом (атак-мув) ставится на паузу')

print('')
print('=== 14: БЕЗОПАСНОСТЬ - выделение возвращается ===')
Reset(0.95, 1.0)
add(eng(100, AM))
local marker = add(MakeUnit(999, { cats = ENGINEER, queue = {} }))
SEL = { marker }
RunOnce()
check(table.getn(SEL) == 1 and SEL[1].id == 999,
      'после скрытого обхода выделение игрока восстановлено')
check(IGNORE_SEL == false, 'SetIgnoreSelection вернулся в false')

print('')
print('=== 15: БЕЗОПАСНОСТЬ - при пустом хранилище выделение не трогаем ===')
Reset(0.20, 1.0)
add(eng(100, AM))
local marker2 = add(MakeUnit(998, { cats = ENGINEER, queue = {} }))
SEL = { marker2 }
for _ = 1, 30 do RunOnce() end
check(SCAN_CALLS == 0, 'за 30 секунд при массе 20% обход не делался ни разу')
check(table.getn(SEL) == 1 and SEL[1].id == 998, 'выделение не тронуто')

print('')
print('=== 16: ЭНЕРГИЯ - масса полна, энергии мало -> паузы нет ===')
Reset(0.95, 0.20)
add(eng(100, AM))
for _ = 1, 10 do RunOnce() end
check(not isPaused(100), 'при энергии 20% инженер работает, хотя масса полна')

print('')
print('=== 17: ЭНЕРГИЯ - энергия упала на паузе -> отпускаем ===')
Reset(0.95, 1.0)
add(eng(100, AM))
RunOnce()
check(isPaused(100), 'сначала поставили на паузу')
ENERGYPCT = 0.10
for _ = 1, 8 do RunOnce() end
check(not isPaused(100), 'энергия упала до 10% - инженер отпущен')

print('')
print('=== 18: РЕГРЕСС - обход не имеет права снимать паузу ===')
Reset(0.95, 1.0)
local u18 = add(eng(100, AM))
RunOnce()
check(isPaused(100), 'поставили на паузу')
Forget(u18)
for _ = 1, 12 do RunOnce() end
check(isPaused(100), 'инженер, не попавший в обход, остался на паузе (баг v2)')

print('')
print('=== 19: настройки применяются на ходу ===')
Reset(0.95, 1.0)
add(eng(100, AM))
SET.ReclaimPauseCfg.highMass = 99
SET.ReclaimPauseCfg.energyMin = 0
SET.ReclaimPauseCfg.minSec = 0
WATCH.ReclaimPauseApplySettings()
for _ = 1, 4 do RunOnce() end
check(not isPaused(100), 'при пороге 99% и массе 95% паузы нет')
MASSPCT = 0.995
RunOnce()
check(isPaused(100), 'при массе 99.5% пауза включилась с новым порогом')

print('')
print('=== 20: РЕГРЕСС - очередь на паузе читается пустой ===')
Reset(0.95, 1.0)
SetHideQueue(true)
add(eng(100, AM))
RunOnce()
check(isPaused(100), 'инженер поставлен на паузу')
for _ = 1, 15 do RunOnce() end
check(isPaused(100), 'инженер с пустой очередью на паузе остался на паузе')
SetHideQueue(false)
MASSPCT = 0.60
for _ = 1, 6 do RunOnce() end
check(not isPaused(100),
      'при падении массы до 60% (ниже lowMass=65) всё же отпущен')

print('')
print('=== 21: ФЛАГОВАЯ ПАУЗА держится и не переключается ===')
Reset(0.95, 1.0)
add(eng(100, AM))
RunOnce()
check(isPaused(100), 'инженер поставлен на паузу')
for _ = 1, 20 do RunOnce() end
check(isPaused(100), 'через 20 проходов пауза держится (идемпотентность флага)')
MASSPCT = 0.60
for _ = 1, 6 do RunOnce() end
check(not isPaused(100),
      'при падении массы до 60% отпущен')
for _ = 1, 6 do RunOnce() end
-- При 60% с порогами 65..70 мод уже НЕ ставит паузу: 60 < highMass=70.
check(not isPaused(100),
      'повторно не паузится: 60% ниже highMass=70')

print('')
print('=== 22: приказ сохранён - приказ не перевыдаётся ===')
Reset(0.95, 1.0)
local u22 = add(eng(100, AM))
RunOnce()
check(isPaused(100), 'поставили на паузу')
check(u22.queue[1] ~= nil, 'очередь инженера не тронута модом')
check(u22.queue[1].CommandType == 'AggressiveMove',
      'приказ атак-мув на месте после паузы')
MASSPCT = 0.70
for _ = 1, 6 do RunOnce() end
check(u22.queue[1] ~= nil and u22.queue[1].CommandType == 'AggressiveMove',
      'приказ атак-мув цел и после снятия паузы')

print('')
print('=== 23: юнит на паузе игроком мод не трогает ===')
Reset(0.95, 1.0)
add(eng(100, AM))
PAUSED[100] = true
RunOnce()
check(isPaused(100), 'осталась на паузе')
for _ = 1, 5 do RunOnce() end
check(isPaused(100), 'мод не снял и не переставил паузу игрока')

print('')
print('=== 24: РУЧНАЯ ПРОВЕРКА (ReclaimPauseForceCheck) ===')
Reset(0.65, 1.0)
add(eng(100, AM))
WATCH.ReclaimPauseForceCheck()
local joined = table.concat(msgs, ' | ')
check(string.find(joined, 'verdict=WAIT%-MASS') ~= nil,
      'при массе 65% и пороге 70% вердикт WAIT-MASS')
check(string.find(joined, 'engineersFound=1') ~= nil,
      'проверка видит инженера на атак-мув')
check(string.find(joined, 'needMass=70') ~= nil,
      'в лог попал требуемый порог 70%')

print('')
print('=== 25: РУЧНАЯ ПРОВЕРКА при достигнутых порогах ===')
MASSPCT = 0.95
msgs = {}
WATCH.ReclaimPauseForceCheck()
local joined2 = table.concat(msgs, ' | ')
check(string.find(joined2, 'verdict=THRESHOLDS%-OK') ~= nil,
      'при массе 95% вердикт THRESHOLDS-OK')

print('')
print('=== 26: РУЧНАЯ ПРОВЕРКА при выключенном моде ===')
WATCH.ReclaimPauseToggle()
msgs = {}
WATCH.ReclaimPauseForceCheck()
local joined3 = table.concat(msgs, ' | ')
check(string.find(joined3, 'verdict=MOD%-DISABLED') ~= nil,
      'выключенный мод сообщает об этом сам')
WATCH.ReclaimPauseToggle()

print('')
print('=== 27: РУЧНАЯ ПРОВЕРКА при нехватке энергии ===')
Reset(0.95, 0.20)
add(eng(100, AM))
msgs = {}
WATCH.ReclaimPauseForceCheck()
local joined4 = table.concat(msgs, ' | ')
check(string.find(joined4, 'verdict=WAIT%-ENERGY') ~= nil,
      'при энергии 20% вердикт WAIT-ENERGY')

print('')
print('=== 28: ОБРЫВ МАРШРУТА ===')
Reset(0.95, 1.0)
add(eng(100, AM))
RunOnce()
check(isPaused(100), 'инженер поставлен на паузу')
check(table.getn(ABORTED) == 1 and ABORTED[1] == 100,
      'маршрут инженера оборван (AbortNavigation вызван на него)')
check(table.getn(SEL) == 0, 'выделение после обрыва чистое')

print('')
print('=== 29: обрыв маршрута отключается настройкой ===')
Reset(0.95, 1.0)
SET.ReclaimPauseCfg.abortMove = false
add(eng(100, AM))
RunOnce()
check(isPaused(100), 'пауза есть')
check(table.getn(ABORTED) == 0, 'маршрут НЕ рвётся при abortMove=false')
SET.ReclaimPauseCfg.abortMove = true

print('')
print('=== 30: обрыв маршрута не трогает очередь ===')
Reset(0.95, 1.0)
local u30 = add(eng(100, AM))
RunOnce()
check(u30.queue[1] ~= nil and u30.queue[1].CommandType == 'AggressiveMove',
      'приказ атак-мув цел после паузы и обрыва маршрута')

print('')
print('=== 31: выделение игрока цело при обрыве ===')
Reset(0.95, 1.0)
local u31 = add(eng(100, AM))
local mk = add(MakeUnit(997, { cats = ENGINEER, queue = {} }))
SEL = { mk }
RunOnce()
check(table.getn(SEL) == 1 and SEL[1].id == 997,
      'выделение игрока восстановлено после обрыва маршрута')

print('')
print('=== 32: ручное снятие при НАЛИЧИИ приказа - пауза возвращается ===')
Reset(0.95, 1.0)
add(eng(100, AM))
RunOnce()
check(isPaused(100), 'поставили на паузу')
PAUSED[100] = false                 -- игрок снял паузу, но приказ оставил
RunOnce()
check(isPaused(100),
      'приказ на месте - мод вернул паузу, а не ушёл в игнорирование')
local j32 = table.concat(msgs, ' | ')
check(string.find(j32, 'pause returned') ~= nil,
      'в логе сказано, что пауза возвращена, а не проигнорирована')

-- а если приказ сняли - инженер просто отпускается и не мучается
Reset(0.95, 1.0)
local u32 = add(eng(103, AM))
RunOnce()
check(isPaused(103), 'поставили на паузу')
PAUSED[103] = false
u32.queue = {}                     -- игрок снял паузу И приказ
RunOnce()
check(not isPaused(103), 'без приказа мод отпускает и не возвращает паузу')
for _ = 1, 6 do RunOnce() end
check(not isPaused(103),
      'и через много секунд мод не цепляется: приказа нет - делать нечего')

print('')
print('=== 33: ТАЙМЕР УДЕРЖАНИЯ (releaseHoldSec) ===')
Reset(0.95, 1.0)
SET.ReclaimPauseCfg.releaseHoldSec = 30
add(eng(100, AM))
RunOnce()
check(isPaused(100), 'поставили на паузу при массе 95%')

MASSPCT = 0.50
local releasedAt = 0
for n = 1, 45 do
  RunOnce()
  if not isPaused(100) then releasedAt = n break end
end
-- Срок 30 секунд при шаге цикла в 1 секунду: отпустить раньше 29 нельзя
-- (условие должно ПРОДЕРЖАТЬСЯ), позже 31 - уже сбилась счётка проходов.
check(releasedAt >= 29 and releasedAt <= 31,
      'условие держалось все 30 секунд, отпуск на проходе ' .. tostring(releasedAt))
local j33 = table.concat(msgs, ' | ')
check(string.find(j33, 'hold=release%-in') ~= nil,
      'в логе видно, сколько секунд осталось ждать (hold=release-in)')

print('')
print('=== 34: условие снятия должно ДЕРЖАТЬСЯ, а не моргать ===')
Reset(0.95, 1.0)
SET.ReclaimPauseCfg.releaseHoldSec = 10
add(eng(101, AM))
RunOnce()
check(isPaused(101), 'поставили на паузу')
MASSPCT = 0.50
for _ = 1, 4 do RunOnce() end     -- условие выполнено 4 секунды
MASSPCT = 0.95                    -- провал был коротким
RunOnce()
check(isPaused(101), 'короткий провал НЕ отпустил инженера')
MASSPCT = 0.50
local blink = 0
for _ = 1, 30 do
  RunOnce()
  if not isPaused(101) then blink = blink + 1 break end
end
check(blink > 0, 'устойчивое низкое хранилище отпустило')

print('')
print('=== 35: releaseHoldSec = 0 отпускает заметно раньше ===')
Reset(0.95, 1.0)
SET.ReclaimPauseCfg.releaseHoldSec = 0
add(eng(102, AM))
RunOnce()
check(isPaused(102), 'поставили на паузу')
MASSPCT = 0.50
local fast = 0
for n = 1, 20 do
  RunOnce()
  if not isPaused(102) then fast = n break end
end
-- Единственный ограничитель - debounce minSec (5 секунд).
check(fast > 0 and fast <= 6,
      'без удержания отпуск на проходе ' .. tostring(fast) ..
      ' - упёрлось только в minSec, а не в releaseHoldSec')

print('')
print('=== 36: ПРИБОР - координаты удерживаемых юнитов ===')
Reset(0.95, 1.0)
SET.ReclaimPauseCfg.probeSec = 5
SET.ReclaimPauseCfg.releaseHoldSec = 0
local u36 = add(eng(103, AM))
u36:SetPos(100, 100)
RunOnce()
for _ = 1, 20 do RunOnce() end     -- достаточно, чтобы периодическая строка вышла
local j36 = table.concat(msgs, ' | ')
check(string.find(j36, 'posMoved=') ~= nil, 'в логе есть поле posMoved')
check(string.find(j36, 'posShift=') ~= nil, 'в логе есть поле posShift')
check(string.find(j36, 'posMoved=0/1') ~= nil,
      'юнит стоял на месте - сдвигов ноль (posMoved=0/1)')

-- теперь он "едет": на каждом интервале замера смещается на 40 единиц
local movedSeen = ''
for _ = 1, 20 do
  u36:SetPos(100 + 40 * (SCAN_N or 0), 100)
  SCAN_N = (SCAN_N or 0) + 1
  RunOnce()
end
movedSeen = table.concat(msgs, ' | ')
check(string.find(movedSeen, 'posMoved=1/1') ~= nil,
      'южет сдвинулся - видно posMoved=1/1 и ненулевой posShift')
SCAN_N = nil

print('')
print('=== 37: прибор выключен - позиции не меряются ===')
Reset(0.95, 1.0)
SET.ReclaimPauseCfg.posProbeSec = 0
add(eng(104, AM))
for _ = 1, 20 do RunOnce() end
check(string.find(table.concat(msgs, ' | '), 'pos=off') ~= nil,
      'при probeSec=0 в логе стоит pos=off, а не вводящее в заблуждение 0/0')

print('')
print('=== 38: GetIsPausedOfUnit, а если его нет в сборке движка ===')
SetOfUnitMode('yes')
Reset(0.95, 1.0)
add(eng(105, AM))
RunOnce()
check(isPaused(105), 'с одиночной функцией пауза ставится')
check(string.find(table.concat(msgs, ' | '), 'GetIsPausedOfUnit available') ~= nil,
      'мод при старте сообщил, что одиночная функция доступна')

SetOfUnitMode('nil')          -- движок такой функции не знает ВОВСЕ
Reset(0.95, 1.0)
add(eng(106, AM))
RunOnce()
check(isPaused(106), 'БЕЗ одиночной функции мод всё равно работает (откат)')
check(string.find(table.concat(msgs, ' | '), 'NOT available') ~= nil,
      'мод сообщил, что одиночной функции нет, и ушёл на общий путь')

-- и теперь убеждаемся, что мод НЕ падает, когда функция есть, но кидает
SetOfUnitMode('throw')        -- функция есть, но бросает при вызове
Reset(0.95, 1.0)
add(eng(107, AM))
RunOnce()
check(isPaused(107), 'функция есть, но бросает - мод не падает, откат сработал')
SetOfUnitMode('yes')

print('')
print('=== 39: ПРИЗНАК АКТИВНОГО РЕКЛЕЙМА по Sync.Reclaim ===')
Reset(0.95, 1.0)
SET.ReclaimPauseCfg.probeSec = 1
SET.ReclaimPauseCfg.releaseHoldSec = 0
add(eng(110, AM))
RunOnce()
-- периодическая строка печатается раз в 15 проходов, поэтому проходов
-- заведомо больше
for _ = 1, 20 do PropMode('same'); RunOnce() end   -- масса не падает
local jA = table.concat(msgs, ' | ')
check(string.find(jA, 'recl=0') ~= nil,
      'масса пропов не падает - recl=0, то есть реклейма нет')

for _ = 1, 20 do PropMode('fall', 3); RunOnce() end -- масса падает у трёх
local jB = table.concat(msgs, ' | ')
check(string.find(jB, 'recl=3') ~= nil,
      'масса падает у трёх пропов - recl=3, реклейм идёт')

-- props и left: сколько вообще осталось подобрать. Именно эти два числа
-- отличают "игра остановила реклейм" от "подбирать нечего".
check(string.find(jB, 'props=3') ~= nil,
      'в пробе props=3 - три пропа доступны для реклейма')
check(string.find(jB, 'sync=ok') ~= nil, 'канал Sync.Reclaim доступен (sync=ok)')
check(string.find(jB, 'raw=3') ~= nil,
      'raw=3 совпадает с числом записей - канал не пуст и не обрезан')
local atLeft = string.find(jB, 'left=', 1, true)
check(atLeft ~= nil, 'в пробе есть left= - сколько массы осталось')
if atLeft ~= nil then
  local leftVal = string.match(string.sub(jB, atLeft + 5), '^(%d+)') or '0'
  check(tonumber(leftVal) > 0,
        'left= больше нуля: ' .. leftVal .. ' массы ещё на пропах')
end

-- CleanupUILabel ставит запись в false и ОБНУЛЯЕТ mass (Prop.lua:396-403).
-- Прибор обязан это пережить, а не упасть на попытке взять .mass
for _ = 1, 20 do PropMode('dead'); RunOnce() end
check(CRASHES == 0, 'запись false от CleanupUILabel не уронила прибор')

print('')
print('=== 39a: проп доступен, но его не берут (props>0, recl=0) ===')
Reset(0.95, 1.0)
SET.ReclaimPauseCfg.probeSec = 1
add(eng(114, AM))
RunOnce()
for _ = 1, 20 do PropMode('same', 7); RunOnce() end
local jS = table.concat(msgs, ' | ')
check(string.find(jS, 'props=7') ~= nil, 'доступно 7 пропов')
check(string.find(jS, 'recl=0') ~= nil,
      'но никто их не берёт: recl=0 при props=7 - это остановка игры')

print('')
print('=== 39b: канал Sync.Reclaim недоступен - прибор это признаёт ===')
Reset(0.95, 1.0)
SET.ReclaimPauseCfg.probeSec = 1
add(eng(115, AM))
RunOnce()
for _ = 1, 20 do SyncBreak(); RunOnce() end
local jN = table.concat(msgs, ' | ')
check(string.find(jN, 'sync=n/a') ~= nil,
      'при отсутствии таблицы прибор пишет sync=n/a, а не props=0')
check(string.find(jN, 'props=?') ~= nil,
      'и все поля прибора помечены вопросом, а не выдуманным нулём')

print('')
print('=== 39c: движение инженеров меряется и без активной паузы ===')
-- Пока инженер реклеймит, он стоит. Когда игра прекращает реклейм,
-- инженер на атак-муве идёт к точке. Значит доля движущихся -
-- это признак, по которому ищем порог.
Reset(0.60, 1.0)
SET.ReclaimPauseCfg.probeSec = 1
SET.ReclaimPauseCfg.highMass = 100     -- мод не должен брать никого
SET.ReclaimPauseCfg.lowMass = 99
u125 = eng(125, AM)
add(u125)
RunOnce()
for _ = 1, 20 do RunOnce() end
local jQ = table.concat(msgs, ' | ')
check(string.find(jQ, 'held=0') ~= nil, 'мод никого не держит: хранилище 60%')
check(string.find(jQ, 'mov=0/1') ~= nil,
      'инженер найден и замерен: mov=0/1 - стоит на месте')
-- st накапливается по одному за проход, поэтому сравниваем ОК с ПОПЫТКАМИ,
-- а не конкретные числа.
local stA, stB = string.match(jQ, 'st=(%d+)/(%d+)')
check(stA ~= nil and stA == stB and tonumber(stB) > 0,
      'счётчик IsUnitState растёт и ошибок нет: st=' .. tostring(stA) ..
      '/' .. tostring(stB))

print('')
print('=== 39d: движущийся инженер считается ===')
-- Строка состояния печатается раз в 15 проходов, поэтому двигаться
-- надо КАЖДЫЙ проход: иначе сдвиг успеет исчезнуть до следующей строки.
for _ = 1, 20 do u125:Walk(1, 0); RunOnce() end
local jW = table.concat(msgs, ' | ')
check(string.find(jW, 'mov=1/1') ~= nil,
      'инженер идёт - прибор пишет mov=1/1')
check(string.find(jW, 'far=1') ~= nil,
      'и far=1 - максимальный пройденный путь виден в логе')

print('')
print('=== 39d2: стоящий после движущегося = 0 ===')
for _ = 1, 20 do RunOnce() end
local jX = table.concat(msgs, ' | ')
check(string.find(jX, 'mov=0/1') ~= nil,
      'когда инженер стоит, доля движущихся снова 0: mov=0/1')

print('')
print('=== 39d3: мелкий сдвиг не считается движением ===')
Reset(0.60, 1.0)
SET.ReclaimPauseCfg.probeSec = 1
SET.ReclaimPauseCfg.highMass = 100
SET.ReclaimPauseCfg.lowMass = 99
u128 = eng(128, AM)
add(u128)
RunOnce()
for _ = 1, 20 do u128:Walk(0.2, 0); RunOnce() end
local jY = table.concat(msgs, ' | ')
check(string.find(jY, 'mov=0/1') ~= nil,
      'сдвиг 0.2 ниже порога 0.5 - движением не считается')

print('')
print('=== 39e: скорость реклейма из счётчика игры ===')
-- Прямой признак "реклеймят ли сейчас". Источник - счётчик самой игры
-- econ.reclaimed (ui/game/economy.lua:382), а не наш прибор.
Reset(0.60, 1.0)
SET.ReclaimPauseCfg.probeSec = 1
SET.ReclaimPauseCfg.highMass = 100
SET.ReclaimPauseCfg.lowMass = 99
u129 = eng(129, AM)
add(u129)
RunOnce()
for _ = 1, 20 do AddReclaimed(10); RunOnce() end   -- идёт реклейм
local jZ = table.concat(msgs, ' | ')
check(string.find(jZ, 'rec=10') ~= nil,
      'счётчик растёт на 10 за проход - прибор пишет rec=10')

for _ = 1, 20 do RunOnce() end                      -- реклейм прекратился
local jZ2 = table.concat(msgs, ' | ')
check(string.find(jZ2, 'rec=0') ~= nil,
      'счётчик замер - прибор пишет rec=0')

-- Возобновление: счётчик снова растёт
for _ = 1, 20 do AddReclaimed(7); RunOnce() end
local jZ3 = table.concat(msgs, ' | ')
check(string.find(jZ3, 'rec=7') ~= nil,
      'после возобновления rec снова ненулевой: rec=7')

print('')
print('=== 39f: компактная строка замера идёт раз в probeSec ===')
-- Главная строка состояния идёт раз в 15 проходов (logEvery), и при
-- высоком lowMass никогда не учащается. Между такими замерами масса
-- уезжает на треть, и момент остановки реклейма пропадает. Компактная
-- строка REC печатается каждый probeSec секунд.
Reset(0.60, 1.0)
SET.ReclaimPauseCfg.probeSec = 1
SET.ReclaimPauseCfg.highMass = 100
SET.ReclaimPauseCfg.lowMass = 99
u130 = eng(130, AM)
add(u130)
RunOnce()
for _ = 1, 6 do AddReclaimed(12); RunOnce() end
local jC = table.concat(msgs, ' | ')
local cnt = 0
for _ in string.gmatch(jC, 'ReclaimPause: REC ') do cnt = cnt + 1 end
check(cnt >= 5, 'строк REC за 6 проходов с probeSec=1: ' .. tostring(cnt))
check(string.find(jC, 'rec=12') ~= nil,
      'в компактной строке есть скорость реклейма')
check(string.find(jC, 'mov=0/1') ~= nil,
      'и доля движущихся инженеров')

print('')
print('=== 40: прибор выключен - видно pos=off и recl=? ===')
Reset(0.95, 1.0)
SET.ReclaimPauseCfg.probeSec = 0
add(eng(111, AM))
for _ = 1, 20 do RunOnce() end
local jC = table.concat(msgs, ' | ')
check(string.find(jC, 'pos=off') ~= nil, 'при выключенном приборе стоит pos=off')
check(string.find(jC, 'recl=?') ~= nil,
      'при выключенном приборе recl помечен вопросом, а не нулём')
check(string.find(jC, 'props=?') ~= nil and string.find(jC, 'left=?') ~= nil,
      'при выключенном приборе props и left тоже помечены вопросом')

print('')
print('=== 41: РАЗБОР "почему инженера не взяли" ===')
Reset(0.95, 1.0)
SET.ReclaimPauseCfg.probeSec = 0
add(eng(112, AM))                              -- наш приказ, берём
add(MakeUnit(113, { cats = ENGINEER, queue = AM }))
PAUSED[113] = true                             -- игрок поставил паузу руками
add(MakeUnit(114, { cats = ENGINEER, queue = { { CommandType = 'Guard' } } }))
RunOnce()
check(isPaused(112), 'инженер с нашим приказом взят под паузу')
check(not isPaused(114), 'инженер с чужим приказом (Guard) не тронут')
for _ = 1, 20 do RunOnce() end
local jD = table.concat(msgs, ' | ')
check(string.find(jD, 'why=skip:') ~= nil, 'в логе есть разбор причин why=')
check(string.find(jD, 'player:') ~= nil, 'отдельно считаются те, кто уже на паузе игрока')
check(string.find(jD, 'other:') ~= nil, 'отдельно считаются те, у кого приказ не наш')

print('')
print('=== 42: ГЛАВНОЕ - падение в цикле должно быть замечено ===')
check(CRASHES == 0,
      'за весь прогон ни одного падения в основном цикле (' .. tostring(CRASHES) .. ')')
local joined5 = table.concat(msgs, ' | ')
check(string.find(joined5, 'CRASH') == nil,
      'в логе теста нет ни одной строки CRASH')

return fails + CRASHES
'''

# --- создаём отдельное окружение на каждый файл мода, как это делает движок
make_env = lua.eval("function() local t = {} setmetatable(t, {__index = _G}) return t end")
loader = lua.eval("""function(src, env)
  local f, err = loadstring(src)
  if not f then error(err) end
  setfenv(f, env)
  return f()
end""")

lua.execute(STUBS)
lua.globals()['MODULES'] = lua.eval("{}")
lua.globals()['SET'] = lua.eval("{}")
lua.globals()['WATCH'] = lua.eval("{}")

# порядок как в игре: settings грузится раньше watch
env_settings = make_env()
loader(settings_src, env_settings)
lua.globals().MODULES['settings'] = env_settings
lua.globals().SET = env_settings

env_watch = make_env()
loader(watch_src, env_watch)
lua.globals().WATCH = env_watch

fails = lua.execute(SCENARIOS) or 0

print("")
print("=== ИТОГ ===")
if fails:
    print("провалено проверок: %d" % fails)
    sys.exit(1)
print("все проверки пройдены")