# -*- coding: utf-8 -*-
u"""Сообщение движка в логе -> раздел методички, где оно разбирается.

Источник истины -- сам documentation.md. Раздел попадает в таблицу только
если сообщение реально встречается в его тексте: в backticks или внутри
блока кода. Ничего не выдумывается и ни откуда не копируется.

Подписи сообщений заданы здесь списком, а не берутся из найденной строки:
чтобы одна и та же ошибка не дала пять строк вида 'Start', 'ResetCounters',
'X'. Правило одно - сообщение, которое здесь есть, обязано где-то встречаться.

Запуск:  python tools\\msgindex.py             напечатать таблицу
         python tools\\msgindex.py --check     FAIL, если таблица в файле
                                              разошлась с текстом
         python tools\\msgindex.py --write     пересобрать таблицу в файле
"""
import io, os, re, sys

# (регулярка в тексте методички, подпись в таблице)
MESSAGES = [
    (r"attempt to yield across", u"attempt to yield across metamethod/C-call boundary"),
    (r"SCR_LuaDoFileConcat", u"SCR_LuaDoFileConcat ... failed"),
    (r"Expected a game object", u"Expected a game object. (Did you call with '.' instead of ':'?)"),
    (r"access to nonexistent global variable", u'access to nonexistent global variable "X"'),
    (r"unexpected symbol near", u"unexpected symbol near 'X'"),
    (r"then' expected near", u"`then' expected near `%'"),
    (r"attempt to index .*\(a nil value\)", u"attempt to index ... (a nil value)"),
    (r"attempt to call a table value", u"attempt to call a table value"),
    (r"attempt to call (?:method|field) '[^']*' \(a nil value\)",
     u"attempt to call method 'ИМЯ' (a nil value)"),
    (r"attempt to call (?:method|field) '[^']*' \(a table value\)",
     u"attempt to call method 'ИМЯ' (a table value)"),
    (r"attempt to perform arithmetic on a nil value", u"attempt to perform arithmetic on a nil value"),
    (r"too many upvalues", u"too many upvalues (limit=32)"),
    (r"Error importing", u"Error importing '/mods/...'"),
    (r"Unable to interrupt path finding", u"Unable to interrupt path finding"),
    (r"MODULE FAILED TO LOAD", u"MODULE FAILED TO LOAD"),
]

TABLE_HEAD = u"| Сообщение в логе | Где разбирается |"
TABLE_SEP = u"| --- | --- |"


def numkey(n):
    return [int(x) for x in re.findall(r"\d+", n)]


def collect(doc):
    found = {}
    cur = None
    inblock = False
    for l in doc.split("\n"):
        if re.match(r"^#{2,4}\s", l):
            # заголовок без номера ("Источники") обнуляет раздел: иначе его
            # сообщения припишутся к последнему нумерованному
            m = re.match(r"^#{3,4}\s+(\d+(?:\.\d+)*[a-z]?)\.", l)
            cur = m.group(1) if m else None
            continue
        if not cur:
            continue
        if cur == "3.7" and l.startswith("|"):
            continue              # таблицы самого раздела не служат источником
        if l.lstrip().startswith("```"):
            inblock = not inblock
            continue
        # кандидаты: текст в backticks; внутри блока кода -- вся строка,
        # потому что живые цитаты из лога там кавычками не выделены
        cand = [l] if inblock else re.findall(r"`([^`\n]+)`", l)
        hay = u"\n".join(cand)
        for rx, label in MESSAGES:
            if re.search(rx, hay):
                found.setdefault(label, set()).add(cur)
    return found


def build(found):
    rows = sorted(found.items(),
                  key=lambda kv: (numkey(sorted(kv[1], key=numkey)[0]), kv[0]))
    out = [TABLE_HEAD, TABLE_SEP]
    for msg, nums in rows:
        out.append(u"| `%s` | %s |" % (msg.replace("|", "\\|"),
                                      ", ".join(sorted(nums, key=numkey))))
    return u"\n".join(out)


def table_span(text):
    """Границы сгенерированной таблицы: шапка плюс все следующие строки '|'.

    Считать по одной строке нельзя: если найти только первую строку данных,
    старый хвост таблицы останется на месте и получится дубль.
    """
    lines = text.split("\n")
    start = None
    for i, l in enumerate(lines):
        if l.strip() == TABLE_HEAD:
            start = i
            break
    if start is None:
        return None, None, lines
    end = start + 1
    while end < len(lines) and lines[end].startswith("|"):
        end += 1
    return start, end, lines


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    doc = os.path.normpath(os.path.join(here, "..", "documentation.md"))
    for a in sys.argv[1:]:
        if not a.startswith("-"):
            doc = a
    text = io.open(doc, encoding="utf-8").read()
    table = build(collect(text))
    rows = table.split("\n")

    if "--write" in sys.argv:
        start, end, lines = table_span(text)
        if start is None:
            print("FAIL: table not found in %s -- insert it manually once" % doc)
            return 1
        lines[start:end] = rows
        io.open(doc, "w", encoding="utf-8", newline="\n").write(u"\n".join(lines))
        print("OK: table rewritten (%d messages)" % (len(rows) - 2))
        return 0

    if "--check" in sys.argv:
        start, end, _ = table_span(text)
        if start is None:
            print("FAIL: table not found")
            return 1
        have = u"\n".join(text.split("\n")[start:end])
        if have == table:
            print("OK: table matches the text (%d messages)" % (len(rows) - 2))
            return 0
        print("FAIL: table has drifted from the text -- run with --write")
        print(have)
        return 1
    print(table)
    return 0


if __name__ == "__main__":
    sys.exit(main())