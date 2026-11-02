# -*- coding: utf-8 -*-
"""Checks the tests themselves: a test has to go red on broken code.

A test that always passes is worse than no test: it gives confidence for no reason. Here the
mod is broken in many ways (see CASES), and the Lua tests have to catch each one.

The mod and the tests are copied into a temporary folder and every breakage is made in the
copy only, so the real sources are never touched and an interrupted run damages nothing.

The tests run on the game's Lua from .tools/faf-lua, which bootstrap.py builds.
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
sys.path.insert(0, os.path.join(HERE, "..", "..", "..", "DOCUMENTATION", "tools"))
sys.dont_write_bytecode = True
import bootstrap
# Both tests run: some breakages are visible to only one of them. For example, a theme that
# did not reach the panel is missed by the rows test and caught at once by the themes test.
TESTS = ["test_overflow_rows.lua", "test_overflow_theme.lua"]

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

sys.stdout.reconfigure(encoding="utf-8", errors="replace")


def rd(p):
    return io.open(p, encoding="utf-8").read()


def wr(p, t):
    io.open(p, "w", encoding="utf-8", newline="").write(t)


def run_test():
    worst = 0
    chunks = []
    for t in TESTS:
        r = subprocess.run([str(bootstrap.lua_path()), t], cwd=TESTS_DIR,
                           capture_output=True, encoding="utf-8", errors="replace")
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
    print("!! ishodnyy kod uzhe krasnyy, idti besmyslenno")
    for l in out.split("\n"):
        if "[FAIL]" in l:
            print("   " + l[:150])
    sys.exit(1)

CASES = [
    # A missing field is read as "hide" instead of the default value, so after a mod update
    # the panel would disappear for everyone. The compatibility test has to fail.
    ("1: otsutstvuet pole -> schryto, a ne pokazano",
     "rows.lua",
     "            v = DEFAULTS[rowKey]\n        end",
     "            v = false\n        end",
     "без настроек видны строки по умолчанию"),

    # The panel height comes from a constant instead of being computed from the visible
    # rows. The height checks have to fail.
    ("2: raskladka ne schitaetsya po vidimym strokam",
     "ui.lua",
     "        if vis[rowKey] then",
     "        if true then",
     "больше на экране ничего нет"),

    # BODY_KEYS lacks eGo and mGo, so the "to allies" rows are not hidden when the panel
    # collapses. The collapse test has to fail.
    ("3: BAG VERSSII 17 - BODY_KEYS bez eGo i mGo",
     "ui.lua",
     "local BODY_KEYS = { 'eOverflow', 'eGo', 'eOwn', 'divider1',\n"
     "                    'mOverflow', 'mGo', 'mOwn', 'divider2', 'total' }",
     "local BODY_KEYS = { 'eOverflow', 'eOwn', 'divider1',\n"
     "                    'mOverflow', 'mOwn', 'divider2', 'total' }",
     'больше на экране ничего нет'),

    # Values come from the profile instead of the live OptionVar, which keeps the value in
    # memory until the settings window is closed.
    ("4: znacheniya iz profilya, a ne iz OptionVar",
     "Options.lua",
     "            vis[rowKey] = options[rowKey]() and true or false\n"
     "        end\n        return vis\n    end",
     "            vis[rowKey] = PROFILE['Overflow'][rowKey] and true or false\n"
     "        end\n        return vis\n    end",
     "профиль и живое значение OptionVar совпадают"),

    # The page imports ui.lua. The load order is unknown, and in one of the orders such an
    # import would catch a module that has not finished running.
    ("5: stranica importiruet ui.lua (poryadok zagruzki)",
     "Options.lua",
     "    local Rows = import('/mods/Overflow/modules/rows.lua')",
     "    local Rows = import('/mods/Overflow/modules/rows.lua')\n"
     "    import('/mods/Overflow/modules/ui.lua')",
     "страница НЕ импортирует ui.lua"),

    # Case 7: the guard is switched off, so incoming is not zeroed for a full storage. Case
    # 8: the guard is too strict and treats any sample as full.
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

    # ---- appearance breakages ----
    #
    # A faction colour is hard-coded instead of being read from the skin. In the game this
    # looks like a panel of a wrong shade and can be noticed only by eye, so it has its own
    # check.
    ("9: cvet ne chitaetsya iz skina, a zashit",
     "themes.lua",
     "        out.NEUTRAL = SkinField('aeon', 'bodyColor', out.NEUTRAL)",
     "        out.NEUTRAL = 'FFbadbdb'",
     "Vanilla NEUTRAL читается из скина"),

    # ApplyTheme has to run BEFORE the elements are created, because the colour is set right
    # in the constructor. Reordered, the panel silently keeps the old colours for good.
    ("10: tema primenyaetsya POSLE sozdaniya paneli",
     "ui.lua",
     "    ApplyTheme()\n    G.themeSig = ThemeSignatureNow()",
     "    G.themeSig = ThemeSignatureNow()",
     "цвет подписи пресета Minimal должен уйти в панель"),

    # The page builds, but the appearance switch is missing.
    ("11: iz obyavleniya polyu vybrosheno pole theme",
     "Options.lua",
     "        theme     = Opt(looks[1]),\n",
     "",
     "выпадающий список оформления привязан к полю theme"),

    # Moving the window resets the height the player set by resizing. Without the re-apply
    # the panel returns to the content height after the first move.
    ("12: perenos okna sbivaet vysotu igroka",
     "ui.lua",
     "    win.OnMoveSet = function()\n        KeepHeight()\n    end",
     "    win.OnMoveSet = function()\n    end",
     "после переноса высота игрока вернулась, а не осталась сбитой"),

    # The "numbers only" mode is declared but not applied: the captions stay and the check
    # box only pretends to work.
    ("13: rezhim 'tolko chisla' ne deystvuet",
     "ui.lua",
     "local function RowText(caption, amount, unit)\n    if NumbersOnlyOn then",
     "local function RowText(caption, amount, unit)\n    if false then",
     "в режиме чисел подписи строк убраны"),

    # The window pieces are not blanked: with the Minimal frame chosen, the game's
    # volumetric frame stays on top.
    ("14: kuski okna ne pogasheny",
     "ui.lua",
     "piece:SetSolidColor('00000000')",
     "piece:SetSolidColor('ffffffff')",
     "куски окна погашены прозрачным"),

    # Reading a global that does not exist in FAF. Game files write `local MathFloor =
    # math.floor`; there is no global MathFloor, and the game's Lua fails fatally on reading
    # a nonexistent global: the file does not load and the whole mod goes down.
    #
    # The test stubs must not declare MathFloor as a global, otherwise this breakage passes
    # unnoticed.
    #
    # The expected message is not "themes.lua did not load" but the cause: here the file
    # loads (a nonexistent global reads as nil in the test environment) and fails at the
    # first MathFloor call. In the game this happens earlier and harder: the whole file load
    # is aborted.
    ("15: chtenie globala, kotorogo v FAF net",
     "themes.lua",
     "local MathFloor    = math.floor",
     "local MathFloor    = MathFloor",
     "attempt to call a nil value"),

    # The title strip sits above the rows: thirty pixels of emptiness, and the text goes
    # past the bottom frame.
    ("17: polosa zagolovka snova nad strokami",
     "ui.lua",
     "    client.Top:Set(win.Top)",
     "    -- client.Top:Set(win.Top)",
     "строки начинаются от ВЕРХА окна"),

    # The width limit is a fixed number: the panel stops shrinking where the text is still
    # intact, and an empty margin is left on the right.
    ("18: predel shiriny zadano chislom",
     "ui.lua",
     "    if minW < L.MIN_W then minW = L.MIN_W end",
     "    minW = L.MIN_W",
     "предел ШИРИНЫ считается ПО ТЕКСТУ"),

    # The built-in line of the texture is stretched over the whole window: there are two
    # lines, ours and the one inside the texture.
    ("20: vstroennaya liniya tekstury ostanovlena v okne",
     "ui.lua",
     "        piece:SetUV(0, vFrom, 1, vTo)",
     "        piece:SetUV(0, 0, 1, 1)",
     "верхний кусок подложки обрезан по встроенной линии"),

    # The backing is not hidden on collapse: the close button removes the values, but an
    # empty frame stays on the screen.
    ("21: podlozhka ne gasnet pri svorachivanii",
     "ui.lua",
     "        ShowFrameBg(false)",
     "        -- ShowFrameBg(false)",
     "при сворачивании подложка гаснет вместе с окном"),

    # The spreading of rows is switched off: the gaps stay the same and the panel is half
    # empty.
    ("22: stroki ne razezzhayutsya po vysote",
     "ui.lua",
     "            gap = extra / (n - 1)",
     "            gap = 0",
     "нижняя строка встаёт по нижнему полю панели"),

    # The resize handler does not recompute the positions: the window size changes, but the
    # rows stay where they were.
    ("23: resayz ne pereschityvaet stroki",
     "ui.lua",
     "    win.OnResize = function()\n        PlaceRows()\n    end",
     "    win.OnResize = function()\n    end",
     "нижняя строка встаёт по нижнему полю панели"),

    # The height is fitted but the positions are not recomputed: a short row set is spread
    # over the OLD, large height and goes past the panel edge.
    ("24: podgonka vysoty bez vtorogo prohoda",
     "ui.lua",
     "        FitHeight(bodyH)\n"
     "\n"
     "        -- The height changed after the layout, and the row positions depend on it.\n"
     "        PlaceRows()",
     "        FitHeight(bodyH)",
     "после смены набора строк строки остаются ВНУТРИ панели"),

    # The height limit is a fixed number: the window shrinks below the rows and the text
    # goes down past the frame.
    ("19: predel vysoty zadano chislom",
     "ui.lua",
     "    if minH < L.MIN_H then minH = L.MIN_H end",
     "    minH = L.MIN_H",
     "предел ВЫСОТЫ считается по числу строк"),

    # The backing of the Minimal frame is taken from the wrong texture. The panel still
    # works, but the frame looks different. The replacement file
    # filter-ping-panel01_c_bmp.dds exists in the game, so the breakage is plausible.
    #
    # The anchor has two lines, not one line with the path. The path occurs in the file
    # twice: in a comment and in the constant itself. The edit replaces the FIRST
    # occurrence, so a one-line anchor would silently edit the comment while the code stayed
    # intact, and the breakage would go unnoticed.
    ("16: podlozhka ramki iz chuzhoy tekstury",
     "ui.lua",
     "local FRAME_BG_TEXTURE =\n"
     "    '/game/filter-ping-panel/filter-ping-panel02_bmp.dds'",
     "local FRAME_BG_TEXTURE =\n"
     "    '/game/filter-ping-panel/filter-ping-panel01_c_bmp.dds'",
     "подложка рамки Minimal собрана из двух кусков"),
]

# Case 6 is special: it breaks the ABSENCE of a file, not its content, so the file is
# removed instead of edited. It runs after the loop below.
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

# ---- case 6: Main.lua is missing ----
#
# In the game this looks like a working mod with the panel in place but no settings page.
# The chain check catches exactly this.
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
# Case 6 (the missing main.lua) runs as a separate block and is not in CASES, so it is
# counted explicitly: the printed total must not understate the coverage.
TOTAL_CASES = len(CASES) + 1
print("vse %d polomki poymany" % TOTAL_CASES)
