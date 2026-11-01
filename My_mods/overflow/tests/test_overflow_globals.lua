-- Overflow - scans every mod file for reads of globals that do not exist in FAF.
--
-- Reading a nonexistent global is a fatal error in the game's Lua: the file does not load
-- and the whole mod goes down with it, not one line. Game files declare their own aliases
-- (`local MathFloor = math.floor`); there is no global MathFloor.
--
-- Each mod .lua is loaded with loadstring and setfenv into an environment whose __index
-- records the name and returns the real value. The real value is required: with nil the
-- chunk would stop at the first missing standard function instead of reaching the one we
-- look for. setfenv is required too: without it loadstring compiles the chunk in the real
-- _G, no names are recorded, and the scan reports no problems for any code.
--
-- Limit: only the module body runs. A global read inside a function happens when the
-- function is called, and nothing is called while loading, so the scan does not see it.
-- Behaviour tests and LuaLS cover those.
--
-- KNOWN lists only names confirmed in the game's own Lua files or its standard library. A
-- name the scan rejects has to be found in the game before it is added.
--
-- FILES is written by hand because Lua cannot walk folders: a new mod file has to be added
-- there.
--
-- Run from the tests folder: lua test_overflow_globals.lua

local MOD = '../Overflow/'

local FILES = {
    'mod_info.lua',
    'hook/lua/ui/game/gamemain.lua',
    'modules/Options.lua',
    'modules/main.lua',
    'modules/rows.lua',
    'modules/sync.lua',
    'modules/themes.lua',
    'modules/ui.lua',
}

-- Standard library of the game's Lua.
local KNOWN = {}
for _, name in {
    'assert', 'collectgarbage', 'dofile', 'error', 'getfenv', 'getmetatable', 'ipairs',
    'loadfile', 'loadstring', 'next', 'pairs', 'pcall', 'print', 'rawequal', 'rawget',
    'rawset', 'require', 'setfenv', 'setmetatable', 'tonumber', 'tostring', 'type',
    'unpack', 'xpcall', 'coroutine', 'debug', 'io', 'math', 'os', 'string', 'table',
} do
    KNOWN[name] = true
end

-- Globals of the engine, shell and FAF client. Each name is followed by a game file where
-- it occurs, so the list is not extended from memory.
for _, name in {
    'LOG',                        -- game log
    'import',                     -- lua/system/import.lua
    'GameTick',                   -- lua/userInit.lua
    'IsAlly',                     -- lua/shield.lua
    'AddOnSyncHashedCallback',    -- lua/UserSync.lua
    'RemoveOnSyncHashedCallback', -- lua/UserSync.lua
    'GetEconomyTotals',           -- lua/ui/game/economy.lua
    'GetSimTicksPerSecond',       -- lua/ui/game/economy.lua
    'GetFocusArmy',               -- lua/AI/aibrain.lua
    'GetCursor',                  -- lua/ui/uiutil.lua
    'GetFrame',                   -- lua/debug/uidebug.lua
    'ForkThread',                 -- client threads
    'WaitSeconds',                -- client threads
    'CreateUI',                   -- lua/ui/game/gamemain.lua, hooked by the mod
} do
    KNOWN[name] = true
end

-- Minimal stubs: only globals that exist in the game. An extra global here would hide
-- exactly the error this scan looks for.
import = function(p) return {} end
LOG = function(m) end

local bad = 0

for _, name in ipairs(FILES) do
    local file = assert(io.open(MOD .. name, 'rb'))
    local source = file:read('*a')
    file:close()

    local seen = {}
    local env = setmetatable({}, { __index = function(_, key)
        seen[key] = true
        return _G[key]
    end })
    local chunk = assert(loadstring(source, name))
    setfenv(chunk, env)
    local ok, err = pcall(chunk)
    if not ok then
        bad = bad + 1
        print('  [FAIL] ' .. name .. ' не выполнился: ' .. tostring(err))
    else
        local unknown = {}
        for key in pairs(seen) do
            if not KNOWN[key] then
                table.insert(unknown, key)
            end
        end
        if table.getn(unknown) > 0 then
            bad = bad + 1
            table.sort(unknown)
            print('  [FAIL] ' .. name .. ' читает глобалы, которых нет в ФАФ: ' ..
                  table.concat(unknown, ', '))
        end
    end
end

print('')
print('=== ИТОГ ===')
print('файлов проверено: ' .. tostring(table.getn(FILES)))
if bad > 0 then
    print('провалено проверок: ' .. tostring(bad))
    os.exit(1)
end
print('чтение глобалов чистое')
