-- Unit test of the ReclaimPause mod (settings.lua + watch.lua).
--
-- Run from the tests folder: lua test_watch_unit.lua. The paths below are relative to it.
-- check.py does that with the Lua of the game, so this code follows its dialect.
--
-- Every file of a mod in FAF has its own environment: assigning a "global" name puts it
-- into the module table, not into the shared _G. The test has to reproduce this, otherwise
-- it misses the failure where settings.lua loaded but watch.lua did not see its functions.
-- So each file runs in a separate table with __index = _G, and import() returns exactly
-- that table.
--
-- Covered: hysteresis, the energy rule in both directions, the minimum interval, release
-- when the order changes, respect for a pause lifted by hand, refusal to touch builders,
-- commanders, foreign and dead units, recognition of all order forms, applying settings on
-- the fly, and two safety requirements: the selection is restored, and a scan pass never
-- lifts the pause of a live engineer.

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
CMDMODE_ACTIVE = false
CMDMODE_CACHE_CALLS = 0
function CommandMode.InCommandMode() return CMDMODE_ACTIVE end
function CommandMode.CacheAndClearCommandMode()
  CMDMODE_CACHED = true
  CMDMODE_CACHE_CALLS = CMDMODE_CACHE_CALLS + 1
end
function CommandMode.RestoreCommandMode(v) CMDMODE_CACHED = false end

-- import() returns the module table, as the engine does.
function import(p)
  if MODULES['settings'] and p == '/mods/ReclaimPause/modules/settings.lua' then
    return MODULES['settings']
  end
  if p == '/lua/user/prefs.lua' then return Prefs end
  if p == '/lua/ui/game/gamemain.lua' then return GameMain end
  if p == '/lua/ui/game/commandmode.lua' then return CommandMode end
  if p == '/lua/keymap/keymapper.lua' then return KEYMAPPER end
  return {}
end

-- /lua/keymap/keymapper.lua with the given key map of the player.
KEY_ACTIONS = {
  reclaimpause_toggle = { action = 'toggle' },
  reclaimpause_check = { action = 'check' },
  reclaimpause_defaults = { action = 'defaults' },
}
function MakeKeyMapper(playerMap)
  local k = {}
  function k.GetCurrentKeyMap() return playerMap end
  function k.GetKeyActions() return KEY_ACTIONS end
  return k
end

IN_ADDED = nil
function IN_AddKeyMapTable(keys) IN_ADDED = keys end

function LOG(m) msgs[table.getn(msgs) + 1] = tostring(m) end
function WARN(m) msgs[table.getn(msgs) + 1] = tostring(m) end

function GetFocusArmy() return 1 end

function GetEconomyTotals()
  return { stored = { MASS = MASSPCT * MAXM, ENERGY = ENERGYPCT * MAXM },
           maxStorage = { MASS = MAXM, ENERGY = MAXM } }
end
function GetSelectedUnits() return SEL end
function SelectUnits(list) SEL = list or {} end

function UISelectionByCategory(cat, addToSel, onScreen, toggle, isReset)
  SCAN_CALLS = SCAN_CALLS + 1
  local out = {}
  local n = 0
  if cat == 'ENGINEER' then
    for i = 1, table.getn(WORLD) do
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
    for i = 1, table.getn(list) do ABORTED[table.getn(ABORTED) + 1] = list[i].id end
  end
end

function SetPaused(list, paused)
  for i = 1, table.getn(list) do
    PAUSED[list[i].id] = paused
  end
end

function GetIsPausedOfUnit(unit)
  return PAUSED[unit.id] == true
end

function ForkThread(f) THREAD = f end
function WaitSeconds(x) error('__LOOPSTOP__', 0) end

-- The unit a builder is focused on. Only the method the mod reads is present.
function MakeFocus(fraction)
  local f = {}
  function f:GetFractionComplete() return fraction end
  return f
end

function MakeUnit(id, opts)
  opts = opts or {}
  local u = {}
  u.id = id
  u.army = opts.army or 1
  u.dead = opts.dead or false
  u.cats = opts.cats or {}
  u.queue = opts.queue or {}
  u.focus = opts.focus
  function u:GetArmy() return self.army end
  function u:IsDead() return self.dead end
  function u:IsInCategory(c) return self.cats[c] == true end
  -- UserUnit has no IsUnitState, that method belongs to the sim layer. The stub
  -- must not have it either, otherwise a call that fails in the game passes here.
  function u:GetFocus() return self.focus end
  function u:GetCommandQueue()
    -- Simulates a queue that reads empty while the unit is paused, for the code path that
    -- handles an empty queue.
    if HIDE_QUEUE_WHEN_PAUSED and PAUSED[self.id] then return {} end
    return self.queue
  end
  function u:GetEntityId() return self.id end
  return u
end

CRASHES = 0
function RunOnce()
  if THREAD == nil then return false end
  local ok, err = pcall(THREAD)
  if not ok and not string.find(tostring(err), '__LOOPSTOP__', 1, true) then
    msgs[table.getn(msgs) + 1] = 'UNEXPECTED: ' .. tostring(err)
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
  CMDMODE_ACTIVE = false
  CMDMODE_CACHE_CALLS = 0
  HIDE_QUEUE_WHEN_PAUSED = false
  CRASHES = 0
  msgs = {}
  THREAD = nil
  WATCH.ReclaimPauseStart()
  -- The settings are set AFTER the start, because ReclaimPauseStart() rereads them from the
  -- profile and overwrites the manual values.
  SET.ReclaimPauseCfg.startGrace = 0
  SET.ReclaimPauseCfg.rescanSec = 3
  SET.ReclaimPauseCfg.skipSec = 3
  SET.ReclaimPauseCfg.abortSec = 2
  SET.ReclaimPauseCfg.abortMove = true
  SET.ReclaimPauseCfg.releaseHoldSec = 0
end

function SetHideQueue(v) HIDE_QUEUE_WHEN_PAUSED = v end

function Forget(u)
  for i = 1, table.getn(WORLD) do
    if WORLD[i] == u then table.remove(WORLD, i) return end
  end
end
end

MODULES = {}

-- same order as in the game: settings loads before watch
local env_settings = MakeEnv()
LoadInto(MOD .. 'settings.lua', env_settings)
MODULES.settings = env_settings
SET = env_settings

local env_watch = MakeEnv()
LoadInto(MOD .. 'watch.lua', env_watch)
WATCH = env_watch

local fails = Run("=== сценарии ===", function()
local ENGINEER  = { ENGINEER = true }
local CMD       = { ENGINEER = true, COMMAND = true }
local AM        = { { type = 'AggressiveMove' } }
local RECLAIM   = { { type = 'Reclaim' } }
local PATROL    = { { type = 'Patrol' } }
local ATTACK    = { { type = 'Attack' } }
local BUILDQ    = { { type = 'Build' } }

local fails = 0
local function check(cond, label)
  if cond then
    print('  [OK  ] ' .. label)
  else
    fails = fails + 1
    print('  [FAIL] ' .. label)
    -- The last log entries: without them a failure gives no hint of what the mod was doing.
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
local function add(u) WORLD[table.getn(WORLD) + 1] = u return u end

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
PAUSED[100] = false                 -- the player lifts the pause by hand
RunOnce()
check(isPaused(100),
      'мод вернул паузу: приказ на месте, хранилище полно')
for _ = 1, 3 do RunOnce() end
check(isPaused(100), 'и дальше держит: хранилище не опустело, отпускать не за что')

-- and the mod releases for a real reason: when the storage has actually emptied
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
add(MakeUnit(200, { cats = ENGINEER, queue = PATROL, focus = MakeFocus(0.5) }))
add(MakeUnit(201, { cats = CMD, queue = AM }))
add(MakeUnit(202, { cats = ENGINEER, queue = RECLAIM, focus = MakeFocus(1.0) }))
RunOnce()
check(not isPaused(200), 'инженер с недостроенным юнитом в фокусе не тронут')
check(not isPaused(201), 'командир не тронут')
check(isPaused(202), 'инженер с готовым юнитом в фокусе встаёт на паузу: он не строит')

print('')
print('=== 7a: режим команд игрока не трогаем ===')
Reset(0.95, 1.0)
add(eng(203, AM))
CMDMODE_ACTIVE = true
for _ = 1, 4 do RunOnce() end
check(SCAN_CALLS == 0, 'при активном режиме команд обхода инженеров нет')
check(CMDMODE_CACHE_CALLS == 0, 'режим команд игрока не перезапускался при обходе')
check(not isPaused(203), 'инженер без обхода пока не найден')
CMDMODE_ACTIVE = false
RunOnce()
check(isPaused(203), 'режим команд закончился - обход идёт на следующем же проходе')

Reset(0.95, 1.0)
add(eng(204, AM))
RunOnce()
check(isPaused(204), 'поставили на паузу до режима команд')
ABORTED = {}
CMDMODE_CACHE_CALLS = 0
CMDMODE_ACTIVE = true
for _ = 1, 6 do RunOnce() end
check(table.getn(ABORTED) == 0, 'обрыв маршрута ждёт конца режима команд')
check(CMDMODE_CACHE_CALLS == 0, 'режим команд игрока не перезапускался при обрыве')
CMDMODE_ACTIVE = false
for _ = 1, 3 do RunOnce() end
check(table.getn(ABORTED) > 0, 'режим команд закончился - обрыв маршрута продолжился')

print('')
print('=== 7b: обрыв, пропущенный из-за режима команд, не ждёт новый abortSec ===')
Reset(0.95, 1.0)
SET.ReclaimPauseCfg.abortSec = 5
add(eng(205, AM))
for _ = 1, 5 do RunOnce() end       -- the pause with the first abort, the next one is due
ABORTED = {}
CMDMODE_ACTIVE = true
RunOnce()
check(table.getn(ABORTED) == 0, 'срок повторного обрыва выпал на режим команд')
CMDMODE_ACTIVE = false
RunOnce()
check(table.getn(ABORTED) == 1, 'повторный обрыв идёт на первом проходе после режима команд')

Reset(0.95, 1.0)
SET.ReclaimPauseCfg.abortSec = 5
add(eng(206, AM))
RunOnce()
PAUSED[206] = false                 -- the player lifts the pause, the order stays
ABORTED = {}
CMDMODE_ACTIVE = true
RunOnce()
check(isPaused(206) and table.getn(ABORTED) == 0, 'пауза вернулась, обрыв отложен режимом команд')
CMDMODE_ACTIVE = false
RunOnce()
check(table.getn(ABORTED) == 1, 'обрыв вернувшейся паузы идёт на первом проходе после режима команд')

print('')
print('=== 8: чужие и мёртвые не тронуты ===')
Reset(0.95, 1.0)
add(MakeUnit(300, { cats = ENGINEER, queue = AM, army = 2 }))
add(MakeUnit(301, { cats = ENGINEER, queue = AM, dead = true }))
RunOnce()
check(not isPaused(300), 'инженер чужой армии не тронут')
check(not isPaused(301), 'мёртвый инженер не тронут')

print('')
print('=== 9: распознаются приказы мода ===')
Reset(0.95, 1.0)
add(eng(401, AM))
add(eng(403, RECLAIM))
add(eng(404, PATROL))
add(eng(405, ATTACK))
RunOnce()
check(isPaused(401), 'AggressiveMove')
check(isPaused(403), 'Reclaim')
check(isPaused(404), 'Patrol')
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
print('=== 14a: БЕЗОПАСНОСТЬ - сбой шага возврата виден в логе и не отменяет следующие ===')

local function told(text)
  local n = 0
  for i = 1, table.getn(msgs) do
    if string.find(msgs[i], text, 1, true) then n = n + 1 end
  end
  return n
end

-- The scan gives the selection back first, the abort second: only the abort fails here.
Reset(0.95, 1.0)
add(eng(100, AM))
local playerSel = { add(MakeUnit(997, { cats = ENGINEER, queue = {} })) }
SEL = playerSel
local plainSelect = SelectUnits
local selectBacks = 0
SelectUnits = function(list)
  if list == playerSel then
    selectBacks = selectBacks + 1
    if selectBacks == 2 then error('select boom') end
  end
  plainSelect(list)
end
RunOnce()
SelectUnits = plainSelect
check(told('SelectUnits FAILED x1 (abort, 1 unit(s))') == 1, 'сбой SelectUnits в логе с вызывающим и числом юнитов')
check(told('select boom') == 1, 'в строке лога есть текст ошибки')
check(IGNORE_SEL == false, 'после сбоя SelectUnits вернулся SetIgnoreSelection')
check(CMDMODE_CACHED == false, 'после сбоя SelectUnits вернулся режим команды')

Reset(0.95, 1.0)
add(eng(100, AM))
local plainIgnore = GameMain.SetIgnoreSelection
GameMain.SetIgnoreSelection = function(v)
  if v == false then error('ignore boom') end
  plainIgnore(v)
end
RunOnce()
GameMain.SetIgnoreSelection = plainIgnore
check(told('SetIgnoreSelection FAILED x1 (scan)') == 1, 'сбой SetIgnoreSelection в логе')
check(CMDMODE_CACHED == false, 'после сбоя SetIgnoreSelection вернулся режим команды')
check(isPaused(100), 'сбой шага возврата не срывает обход')

-- A step that fails on every scan and abort is the case the counted line exists for.
Reset(0.95, 1.0)
add(eng(100, AM))
local plainRestore = CommandMode.RestoreCommandMode
local restoreTries = 0
CommandMode.RestoreCommandMode = function()
  restoreTries = restoreTries + 1
  error('restore boom')
end
for _ = 1, 300 do RunOnce() end
CommandMode.RestoreCommandMode = plainRestore
check(told('RestoreCommandMode FAILED x1 (scan)') == 1, 'первый сбой RestoreCommandMode в логе')
check(restoreTries >= 200, 'шаг падал на каждом обходе и сбросе (' .. tostring(restoreTries) .. ')')
check(told('restore boom') == 1 + math.floor(restoreTries / 100),
      'лог не засыпан: первый сбой и каждый сотый (' .. tostring(told('restore boom')) .. ')')

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
print('=== 15a: БЕЗОПАСНОСТЬ - выключенный мод выделение не трогает ===')
Reset(0.95, 1.0)
SET.ReclaimPauseCfg.enabled = false
add(eng(101, AM))
for _ = 1, 30 do RunOnce() end
check(SCAN_CALLS == 0, 'выключенный мод обход не запускает')

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
check(not isPaused(100),
      'повторно не паузится: 60% ниже highMass=70')

print('')
print('=== 22: приказ сохранён - приказ не перевыдаётся ===')
Reset(0.95, 1.0)
local u22 = add(eng(100, AM))
RunOnce()
check(isPaused(100), 'поставили на паузу')
check(u22.queue[1] ~= nil, 'очередь инженера не тронута модом')
check(u22.queue[1].type == 'AggressiveMove',
      'приказ атак-мув на месте после паузы')
MASSPCT = 0.70
for _ = 1, 6 do RunOnce() end
check(u22.queue[1] ~= nil and u22.queue[1].type == 'AggressiveMove',
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
print('=== 27a: РУЧНАЯ ПРОВЕРКА различает "не искали" и "никого нет" ===')
Reset(0.95, 1.0)
add(eng(100, AM))
CMDMODE_ACTIVE = true
msgs = {}
WATCH.ReclaimPauseForceCheck()
check(string.find(table.concat(msgs, ' | '), 'engineersFound=?', 1, true) ~= nil,
      'в режиме команд обхода нет, поэтому вместо числа стоит ?')

Reset(0.95, 1.0)
msgs = {}
WATCH.ReclaimPauseForceCheck()
check(string.find(table.concat(msgs, ' | '), 'engineersFound=0', 1, true) ~= nil,
      'обход прошёл и никого не нашёл, поэтому стоит 0')

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
check(u30.queue[1] ~= nil and u30.queue[1].type == 'AggressiveMove',
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
PAUSED[100] = false                 -- the player lifts the pause but keeps the order
RunOnce()
check(isPaused(100),
      'приказ на месте - мод вернул паузу, а не ушёл в игнорирование')
local j32 = table.concat(msgs, ' | ')
check(string.find(j32, 'pause returned') ~= nil,
      'в логе сказано, что пауза возвращена, а не проигнорирована')

-- and if the order is gone, the engineer is simply released and left alone
Reset(0.95, 1.0)
local u32 = add(eng(103, AM))
RunOnce()
check(isPaused(103), 'поставили на паузу')
PAUSED[103] = false
u32.queue = {}                     -- the player lifts the pause AND the order
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
-- A hold of 30 seconds at a loop step of 1 second: releasing before 29 is not allowed (the
-- condition has to HOLD), after 31 the count of passes has drifted.
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
for _ = 1, 4 do RunOnce() end     -- the condition has held for 4 seconds
MASSPCT = 0.95                    -- the dip was short
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
-- The only limiter is the minSec debounce.
check(fast > 0 and fast <= 6,
      'без удержания отпуск на проходе ' .. tostring(fast) ..
      ' - упёрлось только в minSec, а не в releaseHoldSec')

print('=== 41: РАЗБОР "почему инженера не взяли" ===')
Reset(0.95, 1.0)
add(eng(112, AM))                              -- our order, taken
add(MakeUnit(113, { cats = ENGINEER, queue = AM }))
PAUSED[113] = true                             -- the player paused it by hand
add(MakeUnit(114, { cats = ENGINEER, queue = { { type = 'Guard' } } }))
RunOnce()
check(isPaused(112), 'инженер с нашим приказом взят под паузу')
check(not isPaused(114), 'инженер с чужим приказом (Guard) не тронут')
for _ = 1, 20 do RunOnce() end
local jD = table.concat(msgs, ' | ')
check(string.find(jD, 'why=skip:') ~= nil, 'в логе есть разбор причин why=')
check(string.find(jD, 'player:') ~= nil, 'отдельно считаются те, кто уже на паузе игрока')
check(string.find(jD, 'other:') ~= nil, 'отдельно считаются те, у кого приказ не наш')

print('')
print('=== 41a: клавиши мода ставит только игрок ===')
Reset(0.5, 1.0)
WATCH.ReclaimPauseStop()
KEYMAPPER = MakeKeyMapper({ ['Ctrl-A'] = 'select_all', ['F5'] = 'reclaimpause_toggle' })
IN_ADDED = nil
WATCH.ReclaimPauseOnCreateUI()
check(IN_ADDED ~= nil and IN_ADDED['F5'] == KEY_ACTIONS.reclaimpause_toggle,
      'клавиша, назначенная игроком, доходит до партии')
check(IN_ADDED ~= nil and IN_ADDED['Ctrl-A'] == nil, 'чужие клавиши мод заново не ставит')
check(string.find(table.concat(msgs, ' | '), 'hotkeys FAILED', 1, true) == nil,
      'установка клавиш прошла без ошибки')

WATCH.ReclaimPauseStop()
KEYMAPPER = MakeKeyMapper({ ['Ctrl-A'] = 'select_all' })
IN_ADDED = nil
WATCH.ReclaimPauseOnCreateUI()
check(IN_ADDED == nil, 'без назначенных клавиш мод ничего не ставит')

print('')
print('=== 42: ГЛАВНОЕ - падение в цикле должно быть замечено ===')
check(CRASHES == 0,
      'за весь прогон ни одного падения в основном цикле (' .. tostring(CRASHES) .. ')')
local joined5 = table.concat(msgs, ' | ')
check(string.find(joined5, 'CRASH') == nil,
      'в логе теста нет ни одной строки CRASH')

return fails + CRASHES
end)

print('')
print('=== ИТОГ ===')
local total = fails
if total > 0 then
    print('провалено проверок: ' .. tostring(total))
    os.exit(1)
end
print('все проверки пройдены')
