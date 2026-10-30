"""
methodlint.py - ищет вызовы методов через точку вместо двоеточия.

Ошибка obj.Method() вместо obj:Method() не является синтаксической.
Lua-компилятор не различает точку и двоеточие, поэтому validate_mod.py
её не видит. Игра падает в момент вызова:

    Expected a game object. (Did you call with '.' instead of ':'?)

ВАЖНО: инструмент даёт ложные срабатывания. Геттеры свойств в FAF
вызываются ЧЕРЕЗ ТОЧКУ, и это правильно:

    panel.Left()        -- правильно, геттер
    panel.Width()       -- правильно, геттер
    panel.Left:Set(100) -- правильно, установка свойства
    control:EnableHitTest(true)  -- правильно, действие
    label:SetText('x')           -- правильно, действие

Так вызывает сама игра, например lua/ui/game/massfabs.lua:214
    self.Left:Set(... self._parent.Right() - self.Width())

Правило:
    - свойство-геттер   -> через точку
    - установка свойства-> точка + :Set
    - действие над объектом -> через двоеточие

Все совпадения этого инструмента нужно проверить глазами по правилу выше.

Использование:
    python methodlint.py путь-к-файлу.lua [другие-файлы.lua]
"""

import re
import sys

# Таблицы и модули - обращение через точку корректно.
# Дополняйте список по мере изучения новых импортов.
KNOWN_TABLES = {
    "UIUtil", "LayoutHelpers", "Prefs", "GameMain", "Selection",
    "TableInsert", "TableConcat", "StringFormat", "MathAbs",
    "MathMax", "MathMin", "MathFloor", "MathCeil", "MathRound",
    "LOG", "WARN", "SPEW", "TRACE",
    "GetCursor", "GetFrame", "GetSelectedUnits", "GetFocusArmy",
    "GameTick", "UISelectionByCategory", "SelectUnits", "PostDragger",
    "Dragger", "Bitmap", "Group", "Button", "Checkbox", "Text",
    "StatusBar", "TableEmpty", "TableGetN", "MathRandom",
}

# obj.Method( где obj - строчная буква (переменная или параметр),
# а Method начинается с заглавной (метод объекта).
METHOD_CALL = re.compile(r"(?<![\w:.])([a-z_]\w*)\.([A-Z]\w*)\s*\(")

# Геттеры свойств maui - через точку это ПРАВИЛЬНО, их надо исключать.
PROPERTY_GETTERS = {
    "Left", "Right", "Top", "Bottom", "Width", "Height",
    "Depth", "Alpha", "Scroll", "ItemHeight",
}


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
    return out_lines


def main():
    files = sys.argv[1:]
    if not files:
        print(__doc__)
        return

    for path in files:
        src = open(path, encoding="utf-8").read()
        src = re.sub(r"--\[\[.*?\]\]", " ", src, flags=re.S)
        lines = strip_comments(src)

        suspicious = []
        for n, line in enumerate(lines, 1):
            for m in METHOD_CALL.finditer(line):
                obj, meth = m.group(1), m.group(2)
                if obj in KNOWN_TABLES:
                    continue
                if meth in PROPERTY_GETTERS:
                    continue          # геттер - точка правильна
                suspicious.append((n, obj, meth, line.strip()[:92]))

        print("Проверено: %s" % path)
        if not suspicious:
            print("    подозрительных вызовов не найдено")
        else:
            print("    ПРОВЕРИТЬ ВРУЧНУЮ %d мест:" % len(suspicious))
            for n, obj, meth, line in suspicious:
                print("      строка %-5d %s.%s(...)" % (n, obj, meth))
                print("                   %s" % line)
        print()


main()
