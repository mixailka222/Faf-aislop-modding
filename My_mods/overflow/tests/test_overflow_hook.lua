-- Tests of the Overflow entry point, hook/lua/ui/game/gamemain.lua.
--
-- The hook runs while the game builds its interface: an error outside pcall here
-- leaves the player without an interface.
--
-- Run from the tests folder: lua test_overflow_hook.lua

local function ReadFile(path)
    local file = assert(io.open(path, 'rb'))
    local text = file:read('*a')
    file:close()
    return text
end

local hookSource = ReadFile('../Overflow/hook/lua/ui/game/gamemain.lua')

local fails = 0

local function check(cond, label)
    if cond then
        print('  [OK  ] ' .. label)
    else
        fails = fails + 1
        print('  [FAIL] ' .. label)
    end
end

local msgs = {}

local function Said(text)
    return string.find(table.concat(msgs, ' | '), text, 1, true) ~= nil
end

-- When a module fails to compile, doscript ends without an error and import returns
-- an empty module. Reading a missing field reaches the strict _G of the game and fails.
local function BrokenModule()
    return setmetatable({}, { __index = function(_, key)
        error('access to nonexistent global variable ' .. tostring(key), 2)
    end })
end

-- A fresh gamemain.lua with the hook appended to it, as the game does.
local function LoadHook(module)
    msgs = {}
    local env = setmetatable({}, { __index = _G })
    env.built = 0
    env.CreateUI = function(isReplay) env.built = env.built + 1 end
    env.LOG = function(m) table.insert(msgs, tostring(m)) end
    env.import = function(path) return module end
    local chunk = assert(loadstring(hookSource))
    setfenv(chunk, env)
    local ok, err = pcall(chunk)
    if not ok then
        print('  hook failed: ' .. tostring(err))
    end
    return ok, env
end

print('=== 1: ui.lua did not compile ===')
local ok, env = LoadHook(BrokenModule())
check(ok, 'the hook survives a broken module')
env.CreateUI(false)
check(env.built == 1, 'the game still builds its interface')
check(Said('MODULE FAILED TO LOAD'), 'the failure is in the log')

print('=== 2: ui.lua loaded ===')
local called = 0
ok, env = LoadHook({ OnCreateUI = function() called = called + 1 end })
check(ok, 'the hook loads with a working module')
env.CreateUI(false)
check(env.built == 1, 'the game builds its interface')
check(called == 1, 'the mod starts after the game interface')

print('=== 3: the mod fails while starting ===')
ok, env = LoadHook({ OnCreateUI = function() error('boom') end })
check(ok, 'the hook loads with a failing entry point')
env.CreateUI(false)
check(env.built == 1, 'the game builds its interface')
check(Said('OnCreateUI error'), 'the error is in the log')

print('')
if fails > 0 then
    print('failed checks: ' .. tostring(fails))
    os.exit(1)
end
print('all checks passed')
