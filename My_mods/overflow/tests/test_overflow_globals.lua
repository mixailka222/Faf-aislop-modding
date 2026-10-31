-- Overflow - чтение глобалов, которых в ФАФ нет. Проверка.
--
-- ЗАЧЕМ ЭТА ПРОВЕРКА
-- Мод однажды не загрузился в игре: themes.lua содержал `local MathFloor =
-- MathFloor`, а глобала MathFloor в ФАФ не существует. Каждый файл игры
-- объявляет его сам - `local MathFloor = math.floor` (maui/layouthelpers.lua:20,
-- maui/statusbar.lua:3, defaultexplosions.lua:661, forms.lua:30 и другие).
-- LuaPlus на чтение несуществующего глобала падает ФАТАЛЬНО: файл не загружается
-- и рушится весь мод, а не одна его строка.
--
-- ПОЧЕМУ ЭТО НЕ УВИДЕЛИ ТЕСТЫ
-- Заглушки объявляли `MathFloor = math.floor` ГЛОБАЛОМ - то есть сами создавали
-- тот самый глобал, которого в игре нет, и подсовывали его модулю. Мод был
-- зелёным на коде, который в игре обрывает загрузку.
-- Это ровно та ошибка, которую заглушки не должны допускать: заглушка обязана
-- повторять игру, а не подправлять её. Теперь MathFloor в заглушках нет.
--
-- КАК РАБОТАЕТ
-- Каждый .lua мода грузится через loadstring + setfenv в окружение, у которого
-- __index ЗАПИСЫВАЕТ имя искомого глобала и возвращает настоящее значение.
-- Возвращать настоящее значение обязательно: если вернуть nil, чанк не
-- выполнится вообще - не будет даже pcall - и сканер сообщит о первой же
-- отсутствующей стандартной функции вместо интересующей нас.
--
-- setfenv ТОЖЕ ОБЯЗАТЕЛЕН. Без него loadstring компилирует чанк в настоящем
-- _G, учёт имён не срабатывает, и сканер молча рапортует «проблем нет» на
-- любом коде. Такая проверка хуже её отсутствия, потому что снимает проверку
-- с автора.
--
-- ГРАНИЦА. Сканер выполняет только ТЕЛО модуля. Чтения глобалов внутри функций
-- происходят в момент вызова, а функции во время загрузки не вызываются, поэтому
-- такой глобал сканер НЕ увидит. Их находят тесты поведения и LuaLS.
--
-- СПИСОК ГЛОБАЛОВ
-- Ниже только имена, подтверждённые первоисточником: файлы игры в references/fa
-- и стандартная библиотека Lua игры. Если сканер ругается на новое имя - его надо
-- найти в игре и только потом добавлять в список.
--
-- СПИСОК ФАЙЛОВ задан руками: в Lua нет обхода папок. Новый файл мода надо
-- дописать в FILES.
--
-- Запуск из папки tests:  lua test_overflow_globals.lua

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

-- Стандартная библиотека Lua игры.
local KNOWN = {}
for _, name in {
    'assert', 'collectgarbage', 'dofile', 'error', 'getfenv', 'getmetatable', 'ipairs',
    'loadfile', 'loadstring', 'next', 'pairs', 'pcall', 'print', 'rawequal', 'rawget',
    'rawset', 'require', 'setfenv', 'setmetatable', 'tonumber', 'tostring', 'type',
    'unpack', 'xpcall', 'coroutine', 'debug', 'io', 'math', 'os', 'string', 'table',
} do
    KNOWN[name] = true
end

-- Глобалы движка, оболочки и клиента ФАФ. После каждого имени - файл игры,
-- где это имя встречается, чтобы список нельзя было пополнять по памяти.
for _, name in {
    'LOG',                        -- журнал игры
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
    'ForkThread',                 -- потоки клиента
    'WaitSeconds',                -- потоки клиента
    'CreateUI',                   -- lua/ui/game/gamemain.lua, его перехватывает хук
} do
    KNOWN[name] = true
end

-- Минимальные заглушки: ровно те глобалы, которые есть в игре, и НИЧЕГО лишнего.
-- Лишний глобал здесь - это ровно та ошибка, которую эта проверка ищет.
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
