"""
validate_mod.py - проверка модов FAF ДО запуска в игре.

Обычная проверка синтаксиса недостаточна. Мод проходит проверку Python и
компилируется настоящим Lua, а потом всё равно падает в игре. Две причины
повторялись на практике:

  1. Оператор "#" (длина таблицы). В игровом коде FAF его нет ни разу
     (проверено по 1476 файлам), зато table.getn() встречается 470 раз.
     LuaPlus его не поддерживает - парerset спотыкается и ругается на
     СЛЕДУЮЩУЮ строку, а не на ту, где проблема.

  2. Вызов метода через точку вместо двоеточия: obj.Method() вместо
     obj:Method(). Компилятор этого не различает. Игра падает в момент
     вызова с сообщением
     "Expected a game object. (Did you call with '.' instead of ':'?)".

  3. Точка в ключе настроек. Prefs.SetToCurrentProfile("mymod.panelPos")
     записывает ПЛОСКИЙ ключ ["mymod.panelPos"], а Prefs.GetFromCurrentProfile
     читает строку как ПУТЬ ПО ТОЧКАМ и ищет узлы ... -> mymod -> panelPos.
     Узла "mymod" нет, поэтому чтение всегда возвращает nil: настройка
     записывается, но никогда не читается. Панель двигается и каждый раз
     возвращается на место. Ловится только тут - синтаксис корректен.

Проверяет:
  - компилируется ли файл настоящим Lua 5.1 (через lupa/LuaJIT)
  - есть ли оператор "#"
  - нет ли запрещённых имён переменных
  - нет ли точек в ключах Prefs (прямых и через переменную)
  - нет ли вызовов через точку (отдельно, см. methodlint.py)

Установка зависимости (один раз):
    pip install lupa

Использование:
    python validate_mod.py путь-к-mod_info.lua путь-к-какому-то-lua-файлу [...]
"""

import os
import re
import sys

try:
    from lupa import luajit21 as lupa
    IMPL = "LuaJIT 2.1 (синтаксис Lua 5.1)"
except Exception:
    try:
        from lupa import lua51 as lupa
        IMPL = "Lua 5.1"
    except Exception:
        print("НУЖНА БИБЛИОТЕКА lupa:  pip install lupa")
        sys.exit(2)

# Имена, которые нельзя использовать для переменных и функций.
# Это либо зарезервированные слова Lua, либо служебные идентификаторы
# внутри самого Lua/LuaPlus (line, count, source, name, level, step,
# buffer, tag, mode, end, index, value, next, func).
FORBIDDEN = {
    "line", "count", "source", "name", "level", "func", "step",
    "buffer", "tag", "mode", "type", "end", "index", "value",
    "next", "self", "key", "format",
}

LUA_KEYWORDS = {
    "and", "break", "do", "else", "elseif", "end", "false", "for",
    "function", "if", "in", "local", "nil", "not", "or", "repeat",
    "return", "then", "true", "until", "while", "continue",
}

# Оператор длины таблицы. В игровом коде не встречается ни разу.
HASH_RE = re.compile(r"(?:[,(\[{=\s])\s*#[A-Za-z_\[(]")

# Оператор остатка от деления. Тоже не поддерживается движком, и это
# стоило целого прогона: файл не компилировался, мод оставался с пустой
# панелью без внятной причины.
#
#   scan.lua(456): `then' expected near `%'
#
# Проверено: во всех 1477 файлах игры символ % встречается ТОЛЬКО внутри
# комментариев и строковых литералов. Как и #.
#
# Ложные срабатывания исключены:
#   - строковые литералы вычищены заранее (blank_strings);
#   - первый % в строке пропускаем: нечётная длина на нём не нужна;
#   - %s, %d, %.1f и прочие спецификаторы - обычные строки.
PERCENT_RE = re.compile(r"(?<![%'\"])%(?![sdfxqg%'\"])")


def find_yield_in_pcall(code):
    """Строки с WaitSeconds, оказавшиеся ВНУТРИ pcall(function() ... end).

    Ищем только форму pcall(function ...) / xpcall(function ...): у неё
    есть тело и закрывающий end.

    Форма pcall(имя, аргументы) блоком НЕ является - это обычный вызов
    без end. Раньше чекер считал и его открывающим, из-за чего счётчик
    глубины рассинхронизировался и проверка «залипала» до конца файла:
    любое WaitSeconds дальше по файлу помечалось, даже если оно было в
    обычной функции, запущенной через ForkThread в отдельной корутине
    (то есть совершенно безопасно). Наблюдалось на modules/main.lua
    диагностического мода OverflowTesting.

    Пока глубина блока pcall больше нуля, любое упоминание WaitSeconds
    считается нарушением.

    Возвращает список кортежей (номер строки, текст).
    """
    lines = code.split("\n")
    result = []

    # Открывает блок только pcall( function ... - именно анонимная функция.
    OPENS_BLOCK = re.compile(r"\b(?:x?pcall)\s*\(\s*function\b")

    depth = 0
    inside = False
    for i, line in enumerate(lines):
        stripped = line.strip()
        opened = len(OPENS_BLOCK.findall(stripped))

        if inside:
            depth += opened
            # открывающие конструкторы, требующие закрывающего end
            if re.search(r"\b(do|then)\b\s*$", stripped):
                depth += 1
            elif re.search(r"\bfunction\b", stripped):
                depth += 1
            if re.search(r"\bWaitSeconds\b", stripped):
                result.append((i + 1, stripped[:80]))
            # закрывающие end
            ends = len(re.findall(r"\bend\b", stripped))
            depth -= ends
            if depth <= 0:
                inside = False
                depth = 0
        elif opened:
            inside = True
            depth = 1
            # Одиночный pcall(function() ... end) закрывается на той же
            # строке. Раньше её "end" не считался, и глубина съезжала на
            # единицу до конца файла: любое последующее WaitSeconds
            # помечалось, хотя никакого pcall вокруг него не было.
            # Наблюдалось на modules/watch.lua мода ReclaimPause.
            depth -= len(re.findall(r"\bend\b", stripped))
            if depth <= 0:
                inside = False
                depth = 0
            # если WaitSeconds на той же строке, что и pcall - тоже плохо
            if re.search(r"\bWaitSeconds\b", stripped):
                result.append((i + 1, stripped[:80]))

    return result

# Вызовы настроек профиля. Ключ с точкой пишется плоским ключом, а читается
# как путь по точкам -> чтение всегда nil. Подробно в documentation.md 11.1.
PREFS_FUNCS = "SetToCurrentProfile|GetFromCurrentProfile|GetFieldFromCurrentProfile"
PREFS_CALL_RE = re.compile(r"\b(?:%s)\s*\(\s*([^,()]+)" % PREFS_FUNCS)
# Простое присваивание строковой константы: local KEY = 'abc'
STRING_ASSIGN_RE = re.compile(r"\blocal\s+([A-Za-z_]\w*)\s*=\s*(['\"])([^'\"]*)\2")


def collect_string_assigns(code):
    """Имя переменной -> строковое значение. Нужно, чтобы поймать ключ,
    переданный не литералом, а переменной: local KEY = 'a.b'."""
    return {m.group(1): m.group(3) for m in STRING_ASSIGN_RE.finditer(code)}


def check_prefs_keys(code):
    """Возвращает список (строка, ключ) для ключей настроек с точками."""
    assigns = collect_string_assigns(code)
    found = []
    for i, line in enumerate(code.split("\n"), 1):
        for m in PREFS_CALL_RE.finditer(line):
            arg = m.group(1).strip()
            # аргумент-строка
            lit = re.match(r"^(['\"])([^'\"]*)\1$", arg)
            if lit:
                key = lit.group(2)
            else:
                # аргумент-переменная: ищем её значение среди констант
                key = assigns.get(arg)
                if key is None:
                    continue
            if "." in key:
                found.append((i, key))
    return found


def strip_comments(src):
    out_lines = []
    for ln in src.split("\n"):
        buf, i, quote = [], 0, None
        while i < len(ln):
            c = ln[i]
            if quote:
                buf.append(c)
                if c == "\\":
                    if i + 1 < len(ln):
                        buf.append(ln[i + 1])
                        i += 2
                        continue
                elif c == quote:
                    quote = None
                i += 1
                continue
            if c in "\"'":
                quote = c
                buf.append(c)
                i += 1
                continue
            if ln[i:i + 2] == "--":
                break
            buf.append(c)
            i += 1
        out_lines.append("".join(buf))
    return "\n".join(out_lines)


# ---------------------------------------------------------------------------
# НЕСУЩЕСТВУЮЩИЕ ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ
# ---------------------------------------------------------------------------
#
# В LuaPlus чтение несуществующей глобальной переменной - ФАТАЛЬНАЯ ошибка,
# а не nil. Компиляцией это не ловится.
#
# Реальный случай: в функции StartResize параметр переименовали из keyCode
# в event, а в вызове PostDragger осталось keyCode. Ошибка фатальная, но
# проявлялась ТОЛЬКО при клике мышью, то есть только в игре. Ни одна из
# проверок того времени её не увидела.

KNOWN_GLOBALS = {
    # Lua
    "assert", "collectgarbage", "dofile", "error", "getfenv", "getmetatable",
    "ipairs", "loadfile", "loadstring", "next", "pairs", "pcall", "print",
    "rawequal", "rawget", "rawset", "require", "select", "setfenv",
    "setmetatable", "tonumber", "tostring", "type", "unpack", "xpcall",
    "bit", "coroutine", "debug", "io", "math", "os", "package", "string",
    "table", "_G", "self",
    # движок FAF
    "LOG", "import", "AddBeatFunction", "RemoveBeatFunction", "PostDragger",
    "GetFrame", "GetCursor", "GetFocusArmy", "GameTick", "GetEconomyTotals",
    "GetSimTicksPerSecond", "GetSelectedUnits", "UISelectionByCategory",
    "WaitSeconds", "ForkThread", "GetTime", "GetCommandTime", "IsReplay",
    "GetArmyStats", "GetPlayerName", "Script", "Selection",
    # Проверены по исходникам игры, а не выдуманы:
    #   IsAlly                     - sim/score.lua:298, ui/game/score.lua:197
    #   GetGameTimeSeconds         - sim/score.lua:154, ui/game/score.lua:62
    #   AddOnSyncHashedCallback    - UserSync.lua:39
    #   RemoveOnSyncHashedCallback - UserSync.lua:47
    #   AddOnSyncCallback          - UserSync.lua:24
    "IsAlly", "GetGameTimeSeconds", "AddOnSyncHashedCallback",
    "RemoveOnSyncHashedCallback", "AddOnSyncCallback", "RemoveOnSyncCallback",
}

DECL_NOISE = {
    "local", "function", "end", "if", "then", "else", "elseif", "for", "while",
    "do", "return", "break", "repeat", "until", "and", "or", "not", "nil",
    "true", "false", "in", "self",
}


def blank_strings(src):
    """Заменить содержимое строк пробелами, сохранив переводы строк."""
    out = []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c == "-" and src[i:i + 4] == "--[[":
            j = src.find("]]", i + 4)
            if j == -1:
                break
            out.append(" " * (j + 2 - i))
            i = j + 2
            continue
        if c == "-" and src[i:i + 2] == "--":
            j = src.find("\n", i)
            if j == -1:
                break
            out.append(" " * (j - i))
            i = j
            continue
        if c in "\"'":
            quote = c
            j = i + 1
            while j < n:
                if src[j] == "\\":
                    j += 2
                    continue
                if src[j] == quote:
                    j += 1
                    break
                if src[j] == "\n":
                    break
                j += 1
            out.append(" " * (j - i))
            i = j
            continue
        out.append(c)
        i += 1
    return "".join(out)


def find_module_export_return(path, code):
    """Модуль ФАФ не должен возвращать таблицу - он экспортирует глобалами.

    import.lua:61 выполняет файл через doscript с таблицей модуля как
    ОКРУЖЕНИЕМ, а import.lua:171 возвращает именно эту таблицу. Значение
    return из файла молча отбрасывается.

    То есть "return { Start = ... }" даёт модуль, у которого НОЛЬ полей.
    Обращение Mod.Start уходит в __index таблицы модуля, оттуда в _G, где
    висит метаметод из config.lua:56-61, и он падает ошибкой:
        access to nonexistent global variable "Start"

    Проверено на игровом модуле /lua/system/utils.lua: 1146 строк, ни одного
    return {...}, экспорт только через function Xxx() end.

    Файлы вне папки modules не проверяем: там return может быть законен.
    """
    if "modules" not in path.replace("/", os.sep).replace("\\", os.sep):
        return []
    hits = []
    for i, line in enumerate(code.split("\n")):
        if re.match(r"^\s*return\s*\{", line):
            hits.append((i + 1, line.strip()[:70]))
    return hits


def check_undefined_globals(code):
    """Имена, которые нигде не объявлены и не входят в список известных.

    Эвристика: собираем ВСЕ объявления по файлу (local, function,
    параметры, переменные цикла) и ищем идентификаторы вне набора.
    Области видимости не разбираются, поэтому возможны ложные срабатывания -
    особенно на вложенных функциях. Потому это ПРЕДУПРЕЖДЕНИЕ, не ошибка.
    """
    declared = set()

    for m in re.finditer(r"\blocal\s+([A-Za-z_]\w*(?:\s*,\s*[A-Za-z_]\w*)*)", code):
        for part in m.group(1).split(','):
            part = part.strip()
            if part:
                declared.add(part)
    for m in re.finditer(r"\bfunction\s+([A-Za-z_][\w.:]*)", code):
        declared.add(m.group(1).split('.')[-1])
    for m in re.finditer(r"function\s*[^\(]*\(([^)]*)\)", code, re.S):
        for part in m.group(1).split(','):
            part = part.strip().split('=')[0].strip()
            if re.fullmatch(r"[A-Za-z_]\w*", part):
                declared.add(part)
    for m in re.finditer(r"\bfor\s+([A-Za-z_]\w*(?:\s*,\s*[A-Za-z_]\w*)*)\s+in\b", code):
        for part in m.group(1).split(','):
            part = part.strip()
            if part:
                declared.add(part)

    declared |= DECL_NOISE | KNOWN_GLOBALS

    # Ключи таблиц: income = 0, BAD = 'x', author = "..." - это ПОЛЯ,
    # а не переменные. Без их учёта валидатор заваливается шумом на
    # каждой таблице. Сравнения != и ~= исключены знаком перед '='.
    for m in re.finditer(r"(?<![\w.:])([A-Za-z_]\w*)\s*(?<![=!<>])=(?!=)", code):
        declared.add(m.group(1))

    # содержимое строк ВЫЧИЩАЕМ: иначе в результат попадают куски
    # путей вроде '/lua/maui/dragger.lua'. strip_comments строки только
    # защищает от комментариев, но не удаляет их текст.
    code = blank_strings(code)

    used = set()
    # Ищем идентификаторы, которым НЕ предшествует точка или двоеточие.
    # Так obj.Method не считается переменной (Method - это поле), но
    # сам obj - считается, даже если дальше идёт двоеточие: `obj:Method()`
    # это обращение к переменной obj, а не к полю.
    for m in re.finditer(r"(?<![\w.:])([A-Za-z_]\w*)", code):
        used.add(m.group(1))

    return sorted(n for n in used - declared)


def main():
    files = sys.argv[1:]
    if not files:
        print(__doc__)
        return

    lua = lupa.LuaRuntime()
    loadstring = lua.eval("loadstring")

    print("Проверка. Интерпретатор: %s" % IMPL)
    print("Файлов: %d" % len(files))
    print()

    problems = 0
    for path in files:
        if not os.path.exists(path):
            print("  %-50s ФАЙЛ НЕ НАЙДЕН" % path)
            problems += 1
            continue

        src = open(path, encoding="utf-8").read()

        # BOM. Символ U+FEFF в начале файла - это не комментарий, а
        # невидимый символ. Парсер Lua на нём может споткнуться.
        #
        # Откуда берётся: PowerShell 5.1 команда
        #   Set-Content -Encoding UTF8
        # пишет BOM автоматически. Именно так в мод попал BOM - и никто
        # этого не заметил, потому что и LuaJIT, и движок его терпят.
        # Терпят - не значит надо оставлять.
        has_bom = src.startswith("﻿")
        if has_bom:
            src = src[1:]

        # 1. компиляция
        res = loadstring(src, "@" + path)
        if isinstance(res, tuple):
            chunk, err = res[0], res[1]
        else:
            chunk, err = res, None
        compiles = chunk is not None

        code = strip_comments(re.sub(r"--\[\[.*?\]\]", " ", src, flags=re.S))
        code = re.sub(r"--.*", "", code)

        # 2. оператор #
        hashes = [(i + 1, l.strip()[:80])
                  for i, l in enumerate(code.split("\n")) if HASH_RE.search(l)]

        # 2b. оператор %. Проверяем по коду с ВЫЧИЩЕННЫМИ строками,
        # иначе '%.1f' и '%d' приняли бы его за арифметику.
        code_nostr = blank_strings(code)
        percents = [(i + 1, l.strip()[:80])
                    for i, l in enumerate(code_nostr.split("\n"))
                    if PERCENT_RE.search(l)]

        # 2c. WaitSeconds внутри pcall. pcall - это C-функция, а WaitSeconds
        # передаёт управление корутине. Через C-границу управление передать
        # нельзя, и LuaPlus роняет всё:
        #
        #   attempt to yield across metamethod/C-call boundary
        #
        # Симптом вводит в заблуждение: панель создаётся, а данных в ней
        # не появляется никогда. Видно "мод загрузился, но молчит".
        yields_in_pcall = find_yield_in_pcall(code_nostr)
        export_returns = find_module_export_return(path, code)

        # 3. запрещённые имена
        decls = set(re.findall(r"\blocal\s+([A-Za-z_]\w*)", code))
        decls |= set(re.findall(r"\bfunction\s+([A-Za-z_]\w*)", code))
        bad = sorted(d for d in decls if d.lower() in FORBIDDEN)

        # 4. точки в ключах настроек
        prefs_bad = check_prefs_keys(code)

        # 5. несуществующие глобальные переменные (предупреждение)
        unknown = check_undefined_globals(code)

        status = ("OK" if compiles and not hashes and not percents and not bad
                  and not prefs_bad and not has_bom and not yields_in_pcall
                  and not export_returns
                  else "ПРОБЛЕМЫ")
        print("  %-50s %s" % (os.path.basename(path), status))

        if export_returns:
            print("      return {...} в модуле - экспорт НЕ работает (см. 3.23):")
            for n, t in export_returns[:5]:
                print("         строка %-5d %s" % (n, t))
            print("      Модуль ФАФ экспортирует глобалами: function Start() end")
            print("      и ничего не возвращает. Значение return отбрасывается,")
            print("      поэтому модуль отдаёт ноль полей. См. import.lua:61,171")
            problems += 1

        if yields_in_pcall:
            print("      WaitSeconds внутри pcall - ФАТАЛЬНО (см. 3.2):")
            for n, t in yields_in_pcall[:5]:
                print("         строка %-5d %s" % (n, t))
            print("      pcall - C-функция, передать через неё управление")
            print("      корутине нельзя. Вынесите WaitSeconds наружу.")
            problems += 1

        if has_bom:
            print("      BOM в начале файла (U+FEFF). Lua-парсер может "
                  "споткнуться.")
            print("      Источник обычно: PowerShell 5.1 "
                  "Set-Content -Encoding UTF8")
            print("      Убрать: перезаписать файл в UTF-8 БЕЗ BOM, "
                  "например python:")
            print("        python -c \"import io,sys;p=sys.argv[1];"
                  "b=open(p,'rb').read();"
                  "open(p,'wb').write(b[3:] if b[:3]==b'\\xef\\xbb\\xbf' else b)\" <файл>")
            problems += 1
        if not compiles:
            print("      компиляция: %s" % err)
            problems += 1
        if hashes:
            print("      оператор '#' (НЕ поддерживается движком!), строки:")
            for n, t in hashes[:5]:
                print("         строка %-5d %s" % (n, t))
            problems += 1
        if percents:
            print("      оператор '%' (НЕ поддерживается движком!), строки:")
            for n, t in percents[:5]:
                print("         строка %-5d %s" % (n, t))
            print("      Замените на сравнение или ключевой флаг, см. 3.3.")
            problems += 1
        if bad:
            print("      запрещённые имена переменных: %s" % ", ".join(bad))
            problems += 1
        if prefs_bad:
            print("      ТОЧКА В КЛЮЧЕ НАСТРОЕК - запись сработает, чтение всегда nil:")
            for n, key in prefs_bad[:5]:
                print("         строка %-5d ключ '%s'" % (n, key))
            print("      Ключ должен быть без точек: 'mymodPanelPos', не 'mymod.panelPos'.")
            print("      Подробно: documentation.md, раздел 11.1")
            problems += 1
        if unknown:
            # НЕ считаем проблемой: области видимости не разбираются,
            # возможны ложные срабатывания. Но в LuaPlus такое имя -
            # фатальная ошибка, поэтому предупреждаем.
            print("      ВНИМАНИЕ: имена, не найденные среди объявлений:")
            print("        %s" % ", ".join(unknown[:12]))
            print("      Если это не глобальные функции движка - будет ФАТАЛЬНО:")
            print("      'access to nonexistent global variable'. См. раздел 3.6")

    print()
    print("Проверить вызовы через точку:  python methodlint.py <файл.lua>")
    print("Проверить пути импорта:        python importcheck.py <папка мода>")
    print()
    print("ИТОГ:", "всё чисто" if problems == 0 else "%d проблем" % problems)
    print("Помни: это проверка до запуска. Первый запуск в игре - главная проверка.")


main()
