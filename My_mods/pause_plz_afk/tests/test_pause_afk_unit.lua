-- Unit test of the PausePlzAfk mod (modules/pause_afk.lua + hook gamemain.lua).
--
-- Run from the tests folder: lua test_pause_afk_unit.lua. The paths below are relative to
-- it. check.py does that with the Lua of the game, so this code follows its dialect.
--
-- Every file of a mod in FAF has its own environment: assigning a "global" name puts it
-- into the module table, not into the shared _G. The test reproduces this: each file runs
-- in a separate table with __index = _G.
--
-- Covered: an AFK player gets the pause and two messages; an active player is left alone;
-- an empty selection ends silently; someone else's pause is not duplicated, but the
-- messages still go out; an order in the middle of the check cancels the trigger; a dead
-- unit counts as busy (no pause); the hook does not break CreateUI and, on a broken import,
-- switches itself off and logs FAILED TO LOAD.

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

local MOD = '../PausePlzAfk/'

do
MSGS = {}
CHAT = {}
SEL = nil
TICKS = 100
PAUSED = false
PAUSE_REQ = 0
HOOK_ORIG_CALLED = 0

function LOG(m) MSGS[table.getn(MSGS) + 1] = tostring(m) end

-- Time: every wait advances the ticks (10 ticks per second).
function WaitSeconds(x) TICKS = TICKS + (x or 0) * 10 end
function GameTick() return TICKS end
function ForkThread(f) f() return {} end

function GetSelectedUnits() return SEL end

function SessionIsPaused() return PAUSED end
function SessionRequestPause() PAUSE_REQ = PAUSE_REQ + 1 PAUSED = true end
function SessionSendChatMessage(m) CHAT[table.getn(CHAT) + 1] = m end

function MakeUnit(idleSeq)
  local u = {}
  u.calls = 0
  u.idleSeq = idleSeq or { true }
  function u.IsIdle(self)
    self.calls = self.calls + 1
    local v = self.idleSeq[self.calls]
    if v == 'dead' then error('unit gone', 2) end
    if v == nil then v = self.idleSeq[table.getn(self.idleSeq)] end
    return v
  end
  return u
end

function Reset()
  MSGS = {}
  CHAT = {}
  SEL = nil
  TICKS = 100
  PAUSED = false
  PAUSE_REQ = 0
  STORE = {}
end
end

STORE = {}
Prefs = {}
function Prefs.GetFromCurrentProfile(k) return STORE[k] end
function Prefs.SetToCurrentProfile(k, v) STORE[k] = v end

SETT = nil
function import(p)
  if p == '/mods/PausePlzAfk/modules/settings.lua' then return SETT end
  if p == '/lua/user/prefs.lua' then return Prefs end
  return {}
end

-- The settings in isolation, as in the engine. pause_afk.lua picks them up through import.
local env_sett = MakeEnv()
LoadInto(MOD .. 'modules/settings.lua', env_sett)
SETT = env_sett

-- The mod module in isolation, as in the engine.
local env_mod = MakeEnv()
LoadInto(MOD .. 'modules/pause_afk.lua', env_mod)
MODT = env_mod

local total = Run("", function()
fails = 0
function check(cond, what)
  if not cond then fails = fails + 1 print('  [FAIL] ' .. what) end
end

-- AFK: the unit has no orders for 10 ticks -> pause and two messages to everyone.
print('=== 1: AFK fires pause and two chat messages ===')
Reset()
SEL = { MakeUnit({ true }) }
MODT.PauseAfkOnCreateUI()
check(PAUSE_REQ == 1, 'пауза запрошена ровно один раз')
check(table.getn(CHAT) == 2, 'отправлено два сообщения в чат')
check(CHAT[1].text == 'plz hold pause im afk', 'текст первого сообщения верный')
check(CHAT[1].to == 'all' and CHAT[1].Chat == true, 'первое сообщение помечено всем')
check(string.find(CHAT[2].text, 'Pause Plz AFK') ~= nil, 'второе сообщение - подпись мода')

print('=== 2: busy player left alone ===')
Reset()
SEL = { MakeUnit({ false }) }
MODT.PauseAfkOnCreateUI()
check(PAUSE_REQ == 0, 'пауза не запрошена')
check(table.getn(CHAT) == 0, 'в чат ничего не отправлено')

print('=== 3: empty selection exits silently ===')
Reset()
SEL = nil
MODT.PauseAfkOnCreateUI()
check(PAUSE_REQ == 0, 'пауза не запрошена')
check(table.getn(CHAT) == 0, 'в чат ничего не отправлено')

-- Someone else's pause is already set: the request is not duplicated, the messages still go
-- out.
print('=== 4: existing pause is not duplicated ===')
Reset()
PAUSED = true
SEL = { MakeUnit({ true }) }
MODT.PauseAfkOnCreateUI()
check(PAUSE_REQ == 0, 'повторный запрос паузы не сделан')
check(table.getn(CHAT) == 2, 'объяснение в чат всё равно отправлено')

-- An order in the middle of the check: the first samples are idle, then busy -> cancel.
print('=== 5: order mid-check cancels ===')
Reset()
SEL = { MakeUnit({ true, true, true, false }) }
MODT.PauseAfkOnCreateUI()
check(PAUSE_REQ == 0, 'пауза не запрошена')
check(table.getn(CHAT) == 0, 'в чат ничего не отправлено')

-- The unit dies in the middle of the check (IsIdle throws) -> counts as busy.
print('=== 6: dead unit counts as busy ===')
Reset()
SEL = { MakeUnit({ true, 'dead' }) }
MODT.PauseAfkOnCreateUI()
check(PAUSE_REQ == 0, 'пауза не запрошена')
check(table.getn(CHAT) == 0, 'в чат ничего не отправлено')

print('=== 7: one busy unit of many is enough ===')
Reset()
SEL = { MakeUnit({ true }), MakeUnit({ false }) }
MODT.PauseAfkOnCreateUI()
check(PAUSE_REQ == 0, 'пауза не запрошена')
check(table.getn(CHAT) == 0, 'в чат ничего не отправлено')

return fails
end)

total = total + Run("", function()
fails = 0
print('=== 10: custom profile text is sent ===')
Reset()
STORE['PausePlzAfk'] = { msgText = 'hold on, brb' }
SEL = { MakeUnit({ true }) }
MODT.PauseAfkOnCreateUI()
check(PAUSE_REQ == 1, 'пауза запрошена')
check(table.getn(CHAT) == 2, 'два сообщения отправлены')
check(CHAT[1].text == 'hold on, brb', 'в чат ушёл текст из профиля')

print('=== 11: blank text falls back to default ===')
Reset()
STORE['PausePlzAfk'] = { msgText = '   ' }
SEL = { MakeUnit({ true }) }
MODT.PauseAfkOnCreateUI()
check(CHAT[1].text == 'plz hold pause im afk', 'пустой текст заменён умолчанием')

print('=== 12: non-string falls back to default ===')
Reset()
STORE['PausePlzAfk'] = { msgText = 42 }
SEL = { MakeUnit({ true }) }
MODT.PauseAfkOnCreateUI()
check(CHAT[1].text == 'plz hold pause im afk', 'число вместо строки заменено умолчанием')

print('=== 13: long text is cut to chat limit ===')
Reset()
STORE['PausePlzAfk'] = { msgText = string.rep('x', 300) }
SEL = { MakeUnit({ true }) }
MODT.PauseAfkOnCreateUI()
check(string.len(CHAT[1].text) <= 200, 'текст не длиннее 200')

-- "\208\176" is the Cyrillic "а", two bytes in UTF-8.
local RU = '\208\176'

-- 101 letters are 202 bytes: the cut falls between two letters, 100 whole letters remain.
print('=== 13a: cut between two-byte letters keeps them whole ===')
check(SETT.PauseAfkSaneMsg(string.rep(RU, 101)) == string.rep(RU, 100), 'осталось 100 целых букв')

-- "x" shifts the letters by one byte, so byte 200 is the first byte of a letter: the
-- split letter is dropped, 99 remain.
print('=== 13b: cut inside a two-byte letter drops it ===')
check(SETT.PauseAfkSaneMsg('x' .. string.rep(RU, 150)) == 'x' .. string.rep(RU, 99),
    'разрезанная буква удалена целиком')

print('=== 14: missing profile falls back to default ===')
Reset()
SEL = { MakeUnit({ true }) }
MODT.PauseAfkOnCreateUI()
check(CHAT[1].text == 'plz hold pause im afk', 'без профиля отправлено умолчание')

return fails
end)

-- The UMT page with a fake UMT: registration, a field of 200 characters, and an edit
-- through the window is written to the profile and seen by the mod.
UMT = { Options = { Mods = {} } }
function UMT.Options.Opt(v)
  local box = { val = v }
  setmetatable(box, { __call = function(self) return self.val end })
  function box.Set(self, v) self.val = v end
  function box.Bind(self, fn) BOUNDFN = fn end
  return box
end
function UMT.Options.TextEdit(name, ov, lim)
  PAGEFIELD = { name = name, ov = ov, lim = lim }
  return PAGEFIELD
end
function UMT.Options.AddOptions(tab, title, items)
  PAGETAB = tab
  PAGETITLE = title
  PAGEITEMS = items
end

local env_opt = MakeEnv()
LoadInto(MOD .. 'modules/options.lua', env_opt)
OPTENV = env_opt
total = total + Run("", function()
fails = 0
function check(cond, what)
  if not cond then fails = fails + 1 print('  [FAIL] ' .. what) end
end

print('=== 15: UMT page registers and edits the text ===')
Reset()
OPTENV.Main()
check(PAGETAB == 'PausePlzAfk', 'страница зарегистрирована под именем мода')
check(PAGEFIELD.lim == 200, 'поле ввода ограничено 200 символами')
UMT.Options.Mods['PausePlzAfk'].msgText:Set('window text')
BOUNDFN()
check(SETT.PauseAfkCfg.msgText == 'window text', 'правка из окна видна моду')
check(STORE['PausePlzAfk'].msgText == 'window text', 'правка из окна записана в профиль')
SEL = { MakeUnit({ true }) }
MODT.PauseAfkOnCreateUI()
check(CHAT[1].text == 'window text', 'мод отправил текст из окна')

return fails
end)

-- The UMT entry point: Main() must read the settings field, and that read makes the real
-- UMT load options.lua with the page.
local env_main = MakeEnv()
LoadInto(MOD .. 'modules/main.lua', env_main)
MAINT = env_main
total = total + Run("", function()
fails = 0
print('=== 16: UMT entry reads our options field ===')
ACCESSED = nil
UMT = { Options = { Mods = {} } }
setmetatable(UMT.Options.Mods, { __index = function(self, k) ACCESSED = k return nil end })
MAINT.Main(false)
check(ACCESSED == 'PausePlzAfk', 'Main прочитал поле настроек (это грузит страницу)')
return fails
end)

-- The hook in its own environment: its own import (returns the module) and its own
-- CreateUI.
local HOOK = MOD .. 'hook/lua/ui/game/gamemain.lua'
HOOK_ORIG_CALLED = 0
local hook_env = MakeEnv()
hook_env.import = function(p)
    if p == '/mods/PausePlzAfk/modules/pause_afk.lua' then return MODT end
    error('unexpected import: ' .. tostring(p))
end
hook_env.CreateUI = function(isReplay) HOOK_ORIG_CALLED = HOOK_ORIG_CALLED + 1 end
LoadInto(HOOK, hook_env)
HOOKT = hook_env
total = total + Run("", function()
fails = 0
function check(cond, what)
  if not cond then fails = fails + 1 print('  [FAIL] ' .. what) end
end

-- The hook wraps CreateUI: the original is called and the mod starts, except in a replay.
print('=== 8: hook chains CreateUI ===')
Reset()
SEL = { MakeUnit({ false }) }
HOOKT.CreateUI(false)
check(HOOK_ORIG_CALLED == 1, 'оригинальный CreateUI вызван')
check(PAUSE_REQ == 0 and table.getn(CHAT) == 0, 'активный игрок не тронут через хук')

print('=== 9: replay does nothing ===')
Reset()
SEL = { MakeUnit({ true }) }
HOOKT.CreateUI(true)
check(PAUSE_REQ == 0 and table.getn(CHAT) == 0, 'в повторе паузы и сообщений нет')

return fails
end)

-- A broken import: the hook has to switch itself off, not crash the interface.
local bad_env = MakeEnv()
bad_env.import = function(p) error('no such file') end
bad_env.CreateUI = function(isReplay) HOOK_ORIG_CALLED = HOOK_ORIG_CALLED + 1 end
LoadInto(HOOK, bad_env)
HOOK_ORIG_CALLED = 0
bad_env.CreateUI(false)
if HOOK_ORIG_CALLED ~= 1 then
    print('  [FAIL] при битом импорте оригинальный CreateUI обязан работать')
    total = total + 1
end
if string.find(table.concat(MSGS, ' | '), 'FAILED TO LOAD', 1, true) == nil then
    print('  [FAIL] при битом импорте в логе обязана быть строка FAILED TO LOAD')
    total = total + 1
end

print('')
print('=== ИТОГ ===')
if total > 0 then
    print('провалено проверок: ' .. tostring(total))
    os.exit(1)
end
print('все проверки пройдены')
