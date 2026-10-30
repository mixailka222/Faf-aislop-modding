"""Проверка предела upvalue (32) - ловушка, из-за которой рухнул Overflow v3.

ПРОБЛЕМА
--------
LuaPlus разрешает функции захватывать не больше 32 переменных из внешней
области видимости. При превышении он НЕ выдаёт обычную ошибку времени
выполнения, а ОТКАЗЫВАЕТСЯ КОМПИЛИРОВАТЬ ФАЙЛ ЦЕЛИКОМ:

    ui.lua(418): too many upvalues (limit=32) near `,'

Обычный Lua и LuaJIT этот предел не проверяют - у них лимит 60. Поэтому
validate_mod.py на этапе компиляции не видит ничего, а в игре файл молча
не грузится. Дальше падает весь интерфейс: игровой gamemain.lua, к
которому дописан хук мода, не импортируется, и игра уходит в краш.

ЧТО ДЕЛАЕТ ЭТОТ СКРИПТ
----------------------
Для каждой функции файла считает, сколько имён верхнего уровня (модуля)
она использует. Это и есть кандидаты в upvalue.

Эвристика, не точный анализ:
  * поля вида obj.Field не считаются переменными;
  * локальные переменные и параметры внутри функции исключены;
  * тело функции ищется по отступу закрывающего `end`.

Погрешность есть, поэтому приоритет - не пропустить реальное превышение.
Порог тревоги ниже предела движка.

Использование:
    python upvaluecheck.py файл.lua [файл.lua ...]
"""
import re
import sys

UPVALUE_LIMIT = 32     # жёсткий предел LuaPlus
UPVALUE_WARN = 26      # с этого числа предупреждаем


def strip_strings_and_comments(src):
    """Убрать содержимое строк и комментарии, чтобы имена внутри них не считались кодом."""
    out = []
    i = 0
    n = len(src)
    while i < n:
        c = src[i]
        # многострочный комментарий --[[ ... ]] - без этой обработки его
        # содержимое попадало в код и портило подсчёт
        if src[i:i + 4] == '--[[':
            j = src.find(']]', i + 4)
            if j == -1:
                break
            out.append('\n' * src.count('\n', i, j))
            i = j + 2
            continue
        # комментарий до конца строки
        if c == '-' and src[i:i + 2] == '--':
            j = src.find('\n', i)
            if j == -1:
                break
            out.append('\n')
            i = j + 1
            continue
        if c in "\"'":
            quote = c
            out.append(' ')
            i += 1
            while i < n:
                if src[i] == '\\':
                    i += 2
                    continue
                if src[i] == quote:
                    i += 1
                    break
                if src[i] == '\n':
                    out.append('\n')
                i += 1
            continue
        out.append(c)
        i += 1
    return ''.join(out)


# Ключевые слова не могут быть именами переменных. Без этого фильтра
# `local function Foo()` читалось как «объявлена переменная function»,
# и ключевое слово попадало в список upvalue.
KEYWORDS = {
    "and", "break", "do", "else", "elseif", "end", "false", "for", "function",
    "if", "in", "local", "nil", "not", "or", "repeat", "return", "then",
    "true", "until", "while",
}


def module_locals(code):
    """Имена, объявленные на верхнем уровне файла - кандидаты в upvalue."""
    names = set()
    # local X = ... , local function X, и голое local X (через запятую)
    for m in re.finditer(r"\blocal\s+([A-Za-z_]\w*)\s*(?:=|\(|,|$)", code, re.M):
        if m.group(1) not in KEYWORDS:
            names.add(m.group(1))
    for m in re.finditer(r"\blocal\s+function\s+([A-Za-z_]\w*)", code):
        names.add(m.group(1))
    # продолжения: local A, B = 1, 2
    for m in re.finditer(r"\blocal\s+([A-Za-z_]\w*\s*(?:,\s*[A-Za-z_]\w*\s*)*)", code):
        for part in m.group(1).split(','):
            part = part.strip()
            if re.fullmatch(r"[A-Za-z_]\w*", part) and part not in KEYWORDS:
                names.add(part)
    # глобальные функции файла тоже захватываются
    for m in re.finditer(r"^\s*function\s+([A-Za-z_]\w*)\s*\(", code, re.M):
        names.add(m.group(1))
    return names


def function_bodies(code):
    """Итерация (имя, номер строки, отступ, тело) по функциям верхнего уровня вложенности."""
    lines = code.split('\n')
    out = []
    i = 0
    while i < len(lines):
        line = lines[i]
        m = (re.match(r"(\s*)local\s+function\s+([A-Za-z_]\w*)\s*\(", line)
             or re.match(r"(\s*)function\s+([A-Za-z_]\w*)\s*\(", line))
        if not m:
            i += 1
            continue
        indent, fname = len(m.group(1)), m.group(2)
        body = []
        j = i
        closed = False
        while j < len(lines):
            cur = lines[j]
            cur_indent = len(cur) - len(cur.lstrip())
            if j > i and cur.strip() == 'end' and cur_indent == indent:
                closed = True
                break
            body.append(cur)
            j += 1
        if not closed:
            i += 1
            continue
        out.append((fname, i + 1, indent, '\n'.join(body)))
        i = j + 1
    return out


IDENT = re.compile(r"\b([A-Za-z_]\w*)\b")


def analyze(path):
    raw = open(path, encoding='utf-8').read()
    code = strip_strings_and_comments(raw)
    mod = module_locals(code)

    rows = []
    for fname, ln, indent, body in function_bodies(code):
        inner = set()
        # объявленные внутри функции - не upvalue.
        # ВАЖНО: `local a, b, c = ...` объявляет ВСЕ три имени, поэтому
        # перечисляем все, а не только первое. Иначе вторые и третьи имена
        # ошибочно попадают в upvalue и счёт завышается.
        for m in re.finditer(
                r"\blocal\s+([A-Za-z_]\w*(?:\s*,\s*[A-Za-z_]\w*)*)\s*(?:=|\(|,|$)",
                body, re.M):
            for part in m.group(1).split(','):
                part = part.strip()
                if re.fullmatch(r"[A-Za-z_]\w*", part):
                    inner.add(part)

        for pat in (r"\bfor\s+([A-Za-z_]\w*)\s*(?:,|in|=)",
                    r"function\s+([A-Za-z_]\w*)"):
            inner |= set(re.findall(pat, body))
        for pm in re.finditer(r"function\s*[A-Za-z_.:]*\s*\(([^)]*)\)", body):
            for part in pm.group(1).split(','):
                part = part.strip()
                if part:
                    inner.add(re.split(r"[\s=]", part)[0])

        used = set(IDENT.findall(body))
        # obj.Field -> Field не переменная
        used -= set(re.findall(r"\.([A-Za-z_]\w*)", body))
        # ключи вида t['x'] уже вычищены удалением строк
        # исключаем имена, объявленные внутри
        outer = sorted(n for n in (used & mod) if n not in inner)
        rows.append((fname, ln, len(outer), outer))

    return rows


def main():
    files = sys.argv[1:]
    if not files:
        print(__doc__)
        return 2

    problems = 0
    for path in files:
        print("\n=== %s ===" % path)
        rows = analyze(path)
        if not rows:
            print("  функций верхнего уровня не найдено")
            continue

        rows_sorted = sorted(rows, key=lambda r: -r[2])
        worst = rows_sorted[0][2] if rows_sorted else 0
        print("  функций: %d, худшая: %d upvalue из %d"
              % (len(rows), worst, UPVALUE_LIMIT))

        for fname, ln, count, names in rows_sorted[:8]:
            if count < UPVALUE_WARN:
                break
            flag = "ПЕРЕПОЛНЕНИЕ" if count > UPVALUE_LIMIT else "близко к пределу"
            print("    %-22s строка %-5d %2d upvalue  %s"
                  % (fname, ln, count, flag))
            # показываем списком, чтобы легко было проверить глазами
            for chunk in (names[i:i + 8] for i in range(0, len(names), 8)):
                print("        " + ", ".join(chunk))

        over = [r for r in rows if r[2] > UPVALUE_LIMIT]
        near = [r for r in rows if UPVALUE_WARN < r[2] <= UPVALUE_LIMIT]

        if over:
            problems += len(over)
            print("  ПРОБЛЕМА: %d функций с превышением предела движка" % len(over))
            print("  Файл НЕ ЗАГРУЗИТСЯ в игре. Сгруппируй константы в таблицы:")
            print("  вместо 14 отдельных local сделай local L = { ... } и пиши L.WIDTH.")
        elif near:
            print("  ВНИМАНИЕ: %d функций близко к пределу (%d)"
                  % (len(near), UPVALUE_LIMIT))

    print()
    if problems:
        print("ИТОГ: %d функций с превышением предела upvalue" % problems)
    else:
        print("ИТОГ: превышений нет")
    return 1 if problems else 0


sys.exit(main())