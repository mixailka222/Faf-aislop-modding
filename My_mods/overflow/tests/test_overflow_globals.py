# -*- coding: utf-8 -*-
u"""Overflow - чтение глобалов, которых в ФАФ нет. Проверка.

ЗАЧЕМ ЭТА ПРОВЕРКА
Мод однажды не загрузился в игре: themes.lua содержал `local MathFloor =
MathFloor`, а глобала MathFloor в ФАФ не существует. Каждый файл игры
объявляет его сам - `local MathFloor = math.floor` (maui/layouthelpers.lua:20,
maui/statusbar.lua:3, defaultexplosions.lua:661, forms.lua:30 и другие).
LuaPlus на чтение несуществующего глобала падает ФАТАЛЬНО: файл не загружается
и рушится весь мод, а не одна его строка.

ПОЧЕМУ ЭТО НЕ УВИДЕЛИ ТЕСТЫ
Заглушки объявляли `MathFloor = math.floor` ГЛОБАЛОМ - то есть сами создавали
тот самый глобал, которого в игре нет, и подсовывали его модулю. Мод был
зелёным на коде, который в игре обрывает загрузку.
Это ровно та ошибка, которую заглушки не должны допускать: заглушка обязана
повторять игру, а не подправлять её. Теперь MathFloor в заглушках нет.

КАК РАБОТАЕТ
Каждый .lua мода грузится через loadstring + setfenv в окружение, у которого
__index ЗАПИСЫВАЕТ имя искомого глобала и возвращает настоящее значение.
Возвращать настоящее значение обязательно: если вернуть nil, чанк не
выполнится вообще - не будет даже pcall - и сканер сообщит о первой же
отсутствующей стандартной функции вместо интересующей нас.

setfenv ТОЖЕ ОБЯЗАТЕЛЕН. Без него loadstring компилирует чанк в настоящем
_G, учёт имён не срабатывает, и сканер молча рапортует «проблем нет» на
любом коде. Такая проверка хуже её отсутствия, потому что снимает проверку
с автора.

ГРАНИЦА, И КОГДА ЕЁ ПРОВЕРИЛИ. Сканер выполняет только ТЕЛО модуля. Чтения
глобалов внутри функций происходят в момент вызова, а функции во время
загрузки не вызываются, поэтому такой глобал сканер НЕ увидит.

Проверено на себе: подмена `if G.frameBg then` на `if Gg.frameBg then`
(тот самый класс ошибки) дала «чтение глобалов чистое», код 0. Ошибку нашли
тесты поведения - панель просто не собралась.

Поэтому сканер ловит ровно то, что ловит: глобалы на верхнем уровне
(`local MathFloor = MathFloor` - типичный случай, именно он и был). Остальное
остаётся на тестах поведения, и это нормальное разделение работы, а не
недостаток. Приписывать сканеру то, чего он не делает, нельзя: проверка,
которая обещает больше, чем делает, вреднее отсутствующей.

СПИСОК ГЛОБАЛОВ
Ниже только имена, подтверждённые первоисточником: файлы распакованной игры
в references/fa
и уже много версий работающие моды проекта. Непроверенных имён в списке нет.
Если сканер ругается на новое имя - его надо найти в игре и только потом
добавлять в список.

ЗАПУСК
    python tests\\test_overflow_globals.py
Код возврата 0 - чисто, 1 - есть неизвестные глобалы.
"""
from __future__ import print_function

import io
import os
import sys

from lupa import luajit21 as lupa

HERE = os.path.dirname(os.path.abspath(__file__))
MOD = os.path.abspath(os.path.join(HERE, os.pardir, "Overflow"))

# --------------------------------------------------------------------------
# Глобалы, которые в ФАФ ЕСТЬ.
# --------------------------------------------------------------------------

# Стандартная библиотека Lua 5.1 плюс расширения LuaJIT.
STDLIB = set(u"""
abs assert collectgarbage dofile error getfenv getmetatable ipairs loadstring
next pairs pcall print rawequal rawget rawset require select setfenv
setmetatable tonumber tostring type unpack xpcall coroutine debug io math
os package string table load arg
""".split())

# Глобалы движка, оболочки и клиента ФАФ. После каждого имени - файл игры,
# где это имя встречается, чтобы список нельзя было пополнять по памяти.
GAME = set(u"""
LOG                       # журнал игры
import                    # lua/import.lua:106
Prefs                     # lua/user/prefs.lua
UIUtil                    # lua/ui/uiutil.lua
Bitmap                    # lua/maui/bitmap.lua
Group                     # lua/maui/group.lua
Dragger                   # lua/maui/dragger.lua
Window                    # lua/maui/window.lua
LayoutHelpers             # lua/maui/layouthelpers.lua
GameMain                  # lua/ui/game/gamemain.lua
GameTick                  # lua/userInit.lua:74 (local GameTick = GameTick)
IsAlly                    # lua/shield.lua:52 (local IsAlly = IsAlly)
GetGameTick               # lua/shield.lua:55
AddOnSyncHashedCallback   # lua/UserSync.lua:39
RemoveOnSyncHashedCallback  # lua/UserSync.lua:47
GetEconomyTotals          # lua/ui/game/economy.lua:377
GetSimTicksPerSecond      # lua/ui/game/economy.lua:378
GetFocusArmy              # lua/AI/aibrain.lua:297
GetCursor                 # lua/ui/uiutil.lua:518
GetFrame                  # lua/debug/uidebug.lua:67
ForkThread                # потоки клиента
WaitSeconds               # потоки клиента
MODULES                   # экспорт модулей мода
""".split())

# Имена, которые читает сам стенд, а не мод.
SERVICE = set(u"_G env seen __makeenv".split())

# Строки-комментарии после имени глобала: имя остаётся, хвост отбрасывается.
GAME = set(x.split()[0] for x in GAME)

KNOWN = STDLIB | GAME

lua = lupa.LuaRuntime(unpack_returned_tuples=True)

lua.execute(u"""
function __makeenv(seen)
    local t = {}
    return setmetatable(t, { __index = function(_, k)
        seen[k] = true
        return _G[k]
    end })
end
""")

seen = lua.eval("{}")
env = lua.eval(u"function(s) return __makeenv(s) end")(seen)

# Минимальные заглушки: ровно те глобалы, которые есть в игре, и НИЧЕГО лишнего.
# Лишний глобал здесь - это ровно та ошибка, которую эта проверка ищет.
lua.execute(u"""
import = function(p) return {} end
LOG = function(m) end
toast = function(m) end
""")

loader = lua.eval(
    u"function(s, e) local f, err = loadstring(s) "
    u"if not f then return { ok = false, err = err } end "
    u"setfenv(f, e) "
    u"local ok, e2 = pcall(f) "
    u"return { ok = ok, err = e2 } end")

bad = 0
checked = 0

for root, dirs, files in os.walk(MOD):
    for fn in sorted(files):
        if not fn.endswith(u".lua"):
            continue
        path = os.path.join(root, fn)
        rel = os.path.relpath(path, MOD)
        checked += 1
        src = io.open(path, encoding="utf-8").read()
        for k in list(seen.keys()):
            del seen[k]
        res = loader(src, env)
        if not res["ok"]:
            bad += 1
            print(u"  [FAIL] %s не выполнился: %s" % (rel, res["err"]))
            continue
        unknown = []
        for k in seen.keys():
            k = str(k)
            if k not in KNOWN and k not in SERVICE:
                unknown.append(k)
        if unknown:
            bad += 1
            print(u"  [FAIL] %s читает глобалы, которых нет в ФАФ:" % rel)
            for k in sorted(unknown):
                print(u"         " + k)

print(u"")
print(u"=== ИТОГ ===")
print(u"файлов проверено: %d" % checked)
if bad:
    print(u"провалено проверок: %d" % bad)
    sys.exit(1)
print(u"чтение глобалов чистое")