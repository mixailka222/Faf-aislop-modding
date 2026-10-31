# -*- coding: utf-8 -*-
"""Проверка: новые проверки сброса краснеют на сломанном коде.

Поломки повторяют реальные ошибки, одна из которых уже была допущена
при написании кода (запись options.x(v) вместо options.x:Set(v)).

Мод и тест копируются во временную папку, поломки делаются только в копии.
Настоящие исходники скрипт не меняет, поэтому прерывание ничего не портит.

Тест выполняет Lua игры из .tools/faf-lua, его собирает bootstrap.py.
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

SET_BLOCK = u"""        options.enabled:Raw():Set(cfg.enabled)
        options.highMass:Raw():Set(cfg.highMass)
        options.lowMass:Raw():Set(cfg.lowMass)
        options.energyMin:Raw():Set(cfg.energyMin)
        options.minSec:Raw():Set(cfg.minSec)
        options.releaseHoldSec:Raw():Set(cfg.releaseHoldSec)
        options.rescanSec:Raw():Set(cfg.rescanSec)
        options.startGrace:Raw():Set(cfg.startGrace)
        options.abortMove:Raw():Set(cfg.abortMove)
        options.abortSec:Raw():Set(cfg.abortSec)
        options.skipSec:Raw():Set(cfg.skipSec)
"""

CALL_BLOCK = u"""        options.enabled(cfg.enabled)
        options.highMass(cfg.highMass)
        options.lowMass(cfg.lowMass)
        options.energyMin(cfg.energyMin)
        options.minSec(cfg.minSec)
        options.releaseHoldSec(cfg.releaseHoldSec)
        options.rescanSec(cfg.rescanSec)
        options.startGrace(cfg.startGrace)
        options.abortMove(cfg.abortMove)
        options.abortSec(cfg.abortSec)
        options.skipSec(cfg.skipSec)
"""

STUCK = u"""            writing = false
"""

CLEAR = u"""            options.resetFlag:Set(false)
"""

BROKEN = [
    (u"1. запись ползунков вызовом вместо Raw():Set",
     SET_BLOCK, CALL_BLOCK),

    (u"2. галочка не снимает себя",
     CLEAR, u""),

    (u"3. сброс не пишет значения в ползунки",
     SET_BLOCK, u""),

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