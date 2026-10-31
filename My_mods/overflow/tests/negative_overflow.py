# -*- coding: utf-8 -*-
"""Проверка самих тестов: тест обязан краснеть на сломанном коде.

Тест, который проходит всегда, хуже отсутствия теста: он даёт уверенность без
основания. Здесь мод ломается разными способами, и каждый обязан быть пойман.

Мод и тесты копируются во временную папку, все поломки делаются только в копии.
Настоящие исходники скрипт не меняет, поэтому прерывание ничего не портит.

Запуск через Python из .tools/venv: тестам нужен lupa.

1) rows.lua: отсутствующее поле читается как «скрыть» вместо значения по
   умолчанию. Должен упасть тест совместимости - тот случай, когда после
   обновления мода панель гаснет у всех.

2) ui.lua: высота панели берётся из константы, а не считается по видимым
   строкам. Должны упасть проверки высоты 38 и 24.

3) ui.lua: возвращён старый баг. Список BODY_KEYS снова без eGo и mGo.
   Должен упасть тест сворачивания. Это самая ценная проверка:
   именно этот баг жил в modе незамеченным.

4) Options.lua: значения берутся из профиля, а не из живого OptionVar.
   Это ровно тот баг, который стоил матча мод ReclaimPause.

5) Options.lua: страница импортирует ui.lua. Порядок загрузки неизвестен,
   и такой импорт в одном из случаев поймал бы не до конца выполненный
   модуль.

6) themes.lua: цвет НЕ читается из скина, а зашит. Опечатка в таком числе
   съела бы тему целиком, и заметить это можно было бы только в игре.

7) ui.lua: тема применяется ПОСЛЕ создания панели. Цвет задаётся в
   конструкторе, поэтому такой порядок оставил бы панель со старым цветом
   навсегда - и молча.

8) Options.lua: из объявления полей выброшено поле theme. Страница собралась
   бы, но переключателя оформления на ней не оказалось бы.
"""
import atexit
import io
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SOURCE_MOD = os.path.abspath(os.path.join(os.path.dirname(HERE), "Overflow"))
# Гоняются ОБА теста: часть поломок видна только одному из них. Например,
# тема не приехала в панель - rows-тест этого не замечает, а тест тем
# замечает сразу.
TESTS = ["test_overflow_rows.py", "test_overflow_theme.py"]

FILES = ["rows.lua", "ui.lua", "Options.lua", "sync.lua", "themes.lua"]

# The tests look for the mod next to their own folder, so the copy keeps that layout.
WORK = tempfile.mkdtemp(prefix="overflow_mutants_")
atexit.register(shutil.rmtree, WORK, ignore_errors=True)
MOD = os.path.join(WORK, "Overflow")
TESTS_DIR = os.path.join(WORK, "tests")
shutil.copytree(SOURCE_MOD, MOD)
os.makedirs(TESTS_DIR)
for t in TESTS:
    shutil.copyfile(os.path.join(HERE, t), os.path.join(TESTS_DIR, t))

ORIGINAL = {}
for f in FILES:
    ORIGINAL[f] = open(os.path.join(MOD, "modules", f), "rb").read()

ENV = dict(os.environ, PYTHONUTF8="1", PYTHONDONTWRITEBYTECODE="1")


def rd(p):
    return io.open(p, encoding="utf-8").read()


def wr(p, t):
    io.open(p, "w", encoding="utf-8", newline="").write(t)


def run_test():
    worst = 0
    chunks = []
    for t in TESTS:
        r = subprocess.run([sys.executable, os.path.join(TESTS_DIR, t)],
                           cwd=TESTS_DIR, env=ENV, capture_output=True,
                           encoding="utf-8", errors="replace")
        if r.returncode != 0:
            worst = r.returncode
        chunks.append((r.stdout or "") + (r.stderr or ""))
    return worst, "\n".join(chunks)


def nfail(out):
    return out.count("[FAIL]")


def restore(fname):
    with open(os.path.join(MOD, "modules", fname), "wb") as fh:
        fh.write(ORIGINAL[fname])


code, out = run_test()
print("ISKHODNO: kod %d, FAIL=%d, OK=%d"
      % (code, nfail(out), out.count("[OK  ]")))
if code != 0:
    print("!! ishodnyy kod uzhe krasnyy, idti besmyslennо".replace(
        "о", "o"))
    for l in out.split("\n"):
        if "[FAIL]" in l:
            print("   " + l[:150])
    sys.exit(1)

CASES = [
    ("1: otsutstvuet pole -> schryto, a ne pokazano",
     "rows.lua",
     "            v = DEFAULTS[rowKey]\n        end",
     "            v = false\n        end",
     "без настроек видны строки по умолчанию"),

    ("2: raskladka ne schitaetsya po vidimym strokam",
     "ui.lua",
     "        if vis[rowKey] then",
     "        if true then",
     "больше на экране ничего нет"),

    ("3: BAG VERSSII 17 - BODY_KEYS bez eGo i mGo",
     "ui.lua",
     "local BODY_KEYS = { 'eOverflow', 'eGo', 'eOwn', 'divider1',\n"
     "                    'mOverflow', 'mGo', 'mOwn', 'divider2', 'total' }",
     "local BODY_KEYS = { 'eOverflow', 'eOwn', 'divider1',\n"
     "                    'mOverflow', 'mOwn', 'divider2', 'total' }",
     'больше на экране ничего нет'),

    ("4: znacheniya iz profilya, a ne iz OptionVar",
     "Options.lua",
     "            vis[rowKey] = options[rowKey]() and true or false\n"
     "        end\n        return vis\n    end",
     "            vis[rowKey] = PROFILE['Overflow'][rowKey] and true or false\n"
     "        end\n        return vis\n    end",
     "профиль и живое значение OptionVar совпадают"),

    ("5: stranica importiruet ui.lua (poryadok zagruzki)",
     "Options.lua",
     "    local Rows = import('/mods/Overflow/modules/rows.lua')",
     "    local Rows = import('/mods/Overflow/modules/rows.lua')\n"
     "    import('/mods/Overflow/modules/ui.lua')",
     "страница НЕ импортирует ui.lua"),

    ("7: zapret vyklyuchen - polnoe hranilishche, a vhodyashchiy ne nul",
     "sync.lua",
     "    local peggedE = maxHeadE ~= nil and maxHeadE <= 0",
     "    local peggedE = false",
     "входящий обнулён запретом"),

    ("8: zapret slishkom strogij - lyuboy otschet schitaetsya polnym",
     "sync.lua",
     "    local peggedE = maxHeadE ~= nil and maxHeadE <= 0",
     "    local peggedE = maxHeadE ~= nil",
     "входящий остался"),

    # ---- поломки оформления ----
    #
    # Проверка 6: цвет фракции зашит вместо чтения из скина. В игре такая
    # ошибка выглядит как «панель не того оттенка», и заметить её можно
    # только глазами - поэтому она и проверяется отдельно.
    ("9: cvet ne chitaetsya iz skina, a zashit",
     "themes.lua",
     "        out.NEUTRAL = SkinField('aeon', 'bodyColor', out.NEUTRAL)",
     "        out.NEUTRAL = 'FFbadbdb'",
     "Vanilla NEUTRAL читается из скина"),

    # Проверка 7: самое дорогое место. ApplyTheme обязан вызываться ДО
    # создания элементов, потому что цвет задаётся прямо в конструкторе.
    # Переставим - и панель молча останется в старых цветах навсегда.
    ("10: tema primenyaetsya POSLE sozdaniya paneli",
     "ui.lua",
     "    ApplyTheme()\n    G.themeSig = ThemeSignatureNow()",
     "    G.themeSig = ThemeSignatureNow()",
     "цвет подписи пресета Minimal должен уйти в панель"),

    # Проверка 8: страница собралась, а переключателя оформления нет.
    ("11: iz obyavleniya polyu vybrosheno pole theme",
     "Options.lua",
     "        theme     = Opt(looks[1]),\n",
     "",
     "выпадающий список оформления привязан к полю theme"),

    # Перенос окна сбрасывает высоту, которую игрок подобрал ресайзом.
    # Убираем перевыставку - и панель после первого же смещения сама
    # возвращается к высоте содержимого. Именно это и было в игре.
    ("12: perenos okna sbivaet vysotu igroka",
     "ui.lua",
     "    win.OnMoveSet = function()\n        KeepHeight()\n    end",
     "    win.OnMoveSet = function()\n    end",
     "после переноса высота игрока вернулась, а не осталась сбитой"),

    # Режим «только числа» объявлен, но не применяется: подписи остаются,
    # и галочка в настройках делает вид, что работает.
    ("13: rezhim 'tolko chisla' ne deystvuet",
     "ui.lua",
     "local function RowText(caption, amount, unit)\n    if NumbersOnlyOn then",
     "local function RowText(caption, amount, unit)\n    if false then",
     "в режиме чисел подписи строк убраны"),

    # Плоская рамка объявлена, но куски окна не заливаются: игрок выбрал
    # Minimal и получил игровое окно.
    # Куски окна НЕ погашены: игрок выбрал Minimal, а сверху осталась
    # игровая объёмная рамка - ровно тот вид, который игрок просил убрать.
    ("14: kuski okna ne pogasheny",
     "ui.lua",
     "piece:SetSolidColor('00000000')",
     "piece:SetSolidColor('ffffffff')",
     "куски окна погашены прозрачным"),

    # Чтение глобала, которого в ФАФ нет. Именно так мод уже не грузился:
    # в themes.lua стояло `local MathFloor = MathFloor`. Глобала
    # MathFloor в ФАФ нет - каждый файл игры пишет `local MathFloor =
    # math.floor` (maui/layouthelpers.lua:20 и другие), а LuaPlus падает на
    # чтении несуществующего глобала ФАТАЛЬНО: файл не грузится и рушится
    # весь мод.
    #
    # Ошибка прошла мимо тестов только потому, что заглушки САМИ объявляли
    # MathFloor глобалом. Теперь они этого не делают, и поломка обязана
    # ломать тесты, если её снова внесут по незнанию.
    #
    # Ожидаемое сообщение - не «themes.lua did not load», а причина: файл
    # грузится (nil из несуществующего глобала - это nil, а не ошибка), и
    # падает первым же вызовом MathFloor. В игре то же самое происходит
    # раньше и жёстче: LuaPlus обрывает загрузку файла целиком.
    ("15: chtenie globala, kotorogo v FAF net",
     "themes.lua",
     "local MathFloor    = math.floor",
     "local MathFloor    = MathFloor",
     "attempt to call upvalue 'MathFloor'"),

    # Подложка рамки Minimal взята не с той текстуры. Сломается ровно так же,
    # как в игре: панель останется рабочей, но рамка будет чужой - от панели
    # фильтра, а не от Selection Cost UI. Настоящий файл
    # filter-ping-panel01_c_bmp.dds в игре есть, то есть поломка
    # правдоподобна, а не выдумана.
    #
    # ЯКОРЬ ДВУСТРОЧНЫЙ, а не одна строка с путём. Путь встречается в файле
    # дважды: в комментарии, где цитируется чужой мод, и в самой константе.
    # Правка заменяет ПЕРВОЕ вхождение, поэтому однострочный якорь молча
    # правил бы комментарий, а код остался бы целым - и поломка прошла бы
    # незамеченной.
    # Полоса заголовка снова над строками: игрок увидит тридцать пикселей
    # пустоты, а текст вылезет за нижнюю рамку.
    ("17: polosa zagolovka snova nad strokami",
     "ui.lua",
     "    client.Top:Set(win.Top)",
     "    -- client.Top:Set(win.Top)",
     "строки начинаются от ВЕРХА окна"),

    # Предел ширины снова жёсткое число: панель перестаёт сжиматься там, где
    # текст ещё цел, и справа остаётся пустое поле.
    ("18: predel shiriny zadano chislom",
     "ui.lua",
     "    if minW < L.MIN_W then minW = L.MIN_W end",
     "    minW = L.MIN_W",
     "предел ШИРИНЫ считается ПО ТЕКСТУ"),

    # Предел высоты снова жёсткое число: окно сжимается ниже строк, и текст
    # уезжает вниз за рамку.
    # Встроенную линию текстуры снова тянут на всё окно: у игрока опять
    # окажутся две линии - наша и та, что внутри текстуры.
    ("20: vstroennaya liniya tekstury ostanovlena v okne",
     "ui.lua",
     "        piece:SetUV(0, vFrom, 1, vTo)",
     "        piece:SetUV(0, 0, 1, 1)",
     "верхний кусок подложки обрезан по встроенной линии"),

    # Подложка снова не гаснет при сворачивании: крестик уберёт значения, а
    # пустая рамка останется висеть на экране.
    ("21: podlozhka ne gasnet pri svorachivanii",
     "ui.lua",
     "        ShowFrameBg(false)",
     "        -- ShowFrameBg(false)",
     "при сворачивании подложка гаснет вместе с окном"),

    # Разъезжание отключено: промежутки остаются прежними, и панель снова
    # выходит наполовину пустой - ровно то, на что жаловался игрок.
    ("22: stroki ne razezzhayutsya po vysote",
     "ui.lua",
     "            gap = extra / (n - 1)",
     "            gap = 0",
     "нижняя строка встаёт по нижнему полю панели"),

    # Обработчик протяжки не пересчитывает позиции: размер окна меняется, а
    # строки остаются на прежних местах.
    ("23: resayz ne pereschityvaet stroki",
     "ui.lua",
     "    win.OnResize = function()\n        PlaceRows()\n    end",
     "    win.OnResize = function()\n    end",
     "нижняя строка встаёт по нижнему полю панели"),

    # Высота подгоняется, а позиции не пересчитываются: короткий набор строк
    # разъезжается по ПРЕЖНЕЙ, большой высоте и уезжает за край панели.
    ("24: podgonka vysoty bez vtorogo prohoda",
     "ui.lua",
     "        FitHeight(bodyH)\n"
     "\n"
     "        -- ВЫСОТА ОКНА МЕНЯЕТСЯ ЗДЕСЬ, ПОСЛЕ РАСКЛАДКИ, а позиции строк от неё\n"
     "        -- зависят (см. PlaceRows). Без второго прохода строки остались бы\n"
     "        -- расставлены по ПРЕЖНЕЙ высоте: смена набора строк меняет и высоту\n"
     "        -- панели, и новый, короткий набор разъехался бы по старой, большой.\n"
     "        PlaceRows()",
     "        FitHeight(bodyH)",
     "после смены набора строк строки остаются ВНУТРИ панели"),

    ("19: predel vysoty zadano chislom",
     "ui.lua",
     "    if minH < L.MIN_H then minH = L.MIN_H end",
     "    minH = L.MIN_H",
     "предел ВЫСОТЫ считается по числу строк"),

    ("16: podlozhka ramki iz chuzhoy tekstury",
     "ui.lua",
     "local FRAME_BG_TEXTURE =\n"
     "    '/game/filter-ping-panel/filter-ping-panel02_bmp.dds'",
     "local FRAME_BG_TEXTURE =\n"
     "    '/game/filter-ping-panel/filter-ping-panel01_c_bmp.dds'",
     "подложка рамки Minimal собрана из двух кусков"),
]

# Шестой случай особый: ломается не содержимое файла, а его ОТСУТСТВИЕ.
# Именно так это и выглядело в игре - моду нет, мод работает, страницы нет.
# Поэтому здесь файл удаляется, а не правится.
SHIM = os.path.join(MOD, "modules", "main.lua")

bad = 0
for label, fname, old, new, expect in CASES:
    restore(fname)
    path = os.path.join(MOD, "modules", fname)
    t = rd(path)
    if old not in t:
        print("%-44s NE NAIDENO MESTO PODMENU" % label)
        bad += 1
        continue
    wr(path, t.replace(old, new, 1))

    code, out = run_test()
    caught = (code != 0) and (expect in out) and ("[FAIL]" in out)
    if not caught:
        bad += 1
    print("")
    print("%-44s kod %d, FAIL=%d  %s"
          % (label, code, nfail(out), "POIMAL" if caught else "!!! NE POIMAL"))
    for l in out.split("\n"):
        if "[FAIL]" in l:
            print("     " + l[:150])

    restore(fname)

# ---- случай 6: файла Main.lua просто нет ----
#
# Ломается не содержимое файла, а его ОТСУТСТВИЕ. Именно так это и выглядело
# в игре: моду нет, мод работает, панель на месте, а страницы настроек нет.
# Ровно этот случай проверка цепочки и ловит.
os.remove(SHIM)
code, out = run_test()
caught = (code != 0) and ("страница зарегистрирована" in out) \
    and ("[FAIL]" in out)
if not caught:
    bad += 1
print("")
print("%-44s kod %d, FAIL=%d  %s"
      % ("6: NET FAILA modules/main.lua (shim)", code, nfail(out),
         "POIMAL" if caught else "!!! NE POIMAL"))
for l in out.split("\n"):
    if "[FAIL]" in l:
        print("     " + l[:150])
shutil.copyfile(os.path.join(SOURCE_MOD, "modules", "main.lua"), SHIM)

code, out = run_test()
print("")
print("POSLE VOSSTANOVLENIYA: kod %d, FAIL=%d, OK=%d"
      % (code, nfail(out), out.count("[OK  ]")))
if code != 0:
    bad += 1

print("")
if bad:
    print("!!! ne vse polomki poymany (%d)" % bad)
    sys.exit(1)
# Случай 6 (отсутствие файла main.lua) реализован отдельным блоком и не
# входит в CASES. Считаем явно: занижать покрытие в выводе нельзя, ради
# этого скрипт и делается.
TOTAL_CASES = len(CASES) + 1
print("vse %d polomki poymany" % TOTAL_CASES)
