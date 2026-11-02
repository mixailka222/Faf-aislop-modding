# -*- coding: utf-8 -*-
"""Checks the reset checks of test_options_unit.lua: they have to go red on broken code.

The breakages repeat realistic mistakes, such as writing options.x(v) instead of
options.x:Set(v).

The mod and the test are copied into a temporary folder and the breakages are made in the
copy only, so the real sources are never touched and an interrupted run damages nothing.

The test runs on the game's Lua from .tools/faf-lua, which bootstrap.py builds.
"""
import atexit
import io
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "..", "DOCUMENTATION", "tools"))
sys.dont_write_bytecode = True
import bootstrap

# The test looks for the mod next to its own folder, so the copy keeps that layout.
WORK = tempfile.mkdtemp(prefix="reclaim_mutants_")
atexit.register(shutil.rmtree, WORK, ignore_errors=True)
shutil.copytree(os.path.join(os.path.dirname(HERE), "ReclaimPause"),
                os.path.join(WORK, "ReclaimPause"))
os.makedirs(os.path.join(WORK, "tests"))
TEST = "test_options_unit.lua"
shutil.copyfile(os.path.join(HERE, TEST), os.path.join(WORK, "tests", TEST))
OPT = os.path.join(WORK, "ReclaimPause", "modules", "options.lua")

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ORIG = io.open(OPT, encoding="utf-8").read()

SET_LINE = u"""                options[field]:Raw():Set(value)
"""

CALL_LINE = u"""                options[field](value)
"""

SAVE_LINE = u"""                options[field]:Save()
"""

FILTER = u"            if name == nil or name == field then"

STUCK = u"""            writing = false
"""

CLEAR = u"""            options.resetFlag:Set(false)
"""

BROKEN = [
    (u"1. запись ползунков вызовом вместо Raw():Set",
     SET_LINE, CALL_LINE),

    (u"2. галочка не снимает себя",
     CLEAR, u""),

    (u"3. сброс не пишет значения в ползунки",
     SET_LINE, u""),

    (u"4. сброс стоит ПОСЛЕ присвоения ползунков (затирается)",
     u"""        if options.resetFlag() then
            writing = true
            options.resetFlag:Set(false)
            Settings.ReclaimPauseResetDefaults()
            cfg = Settings.ReclaimPauseCfg
""",
     u"""        if false then
            writing = true
            options.resetFlag:Set(false)
            Settings.ReclaimPauseResetDefaults()
            cfg = Settings.ReclaimPauseCfg
"""),

    (u"5. флаг writing залипает: Refresh выключен навсегда",
     STUCK, u""),

    (u"6. сброса нет вообще",
     u"        if options.resetFlag() then", u"        if false then"),

    (u"7. Cancel возвращает ползунок, сдвинутый до клавиши сброса",
     SAVE_LINE, u""),

    (u"8. клавиша включения лишает Cancel отката ползунков",
     FILTER, u"            if true then"),
]

results = []
for title, old, new in BROKEN:
    if ORIG.count(old) != 1:
        print(u"  ОШИБКА ПОДСТАНОВКИ (%s): вхождений %d" % (title, ORIG.count(old)))
        results.append((title, False))
        continue
    io.open(OPT, "w", encoding="utf-8", newline="").write(ORIG.replace(old, new))
    p = subprocess.run([str(bootstrap.lua_path()), TEST], cwd=os.path.join(WORK, "tests"),
                       capture_output=True)
    out = p.stdout.decode("utf-8", "replace") + p.stderr.decode("utf-8", "replace")
    fails = out.count("[FAIL]")
    name = [l for l in out.split("\n") if "[FAIL]" in l][:2]
    ok = fails > 0 or p.returncode != 0
    results.append((title, ok))
    print(u"  %s  %-52s FAIL=%d" % (u"ПОЙМАЛ " if ok else u"ПРОПУСТИЛ",
                                    title, fails))
    for n in name:
        print(u"           " + n.strip())

missed = [title for title, caught in results if not caught]
if missed:
    print(u"не пойманы: " + u"; ".join(missed))
    sys.exit(1)