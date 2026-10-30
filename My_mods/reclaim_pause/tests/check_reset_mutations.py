# -*- coding: utf-8 -*-
"""Проверка: новые проверки сброса краснеют на сломанном коде.

Поломки повторяют реальные ошибки, одна из которых уже была допущена
при написании кода (запись options.x(v) вместо options.x:Set(v)).
"""
import io
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TEST = os.path.join(HERE, "test_options_unit.py")
OPT = os.path.join(os.path.dirname(HERE), "ReclaimPause", "modules", "options.lua")

ORIG = io.open(OPT, encoding="utf-8").read()

SET_BLOCK = u"""            options.enabled:Set(cfg.enabled)
            options.highMass:Set(cfg.highMass)
            options.lowMass:Set(cfg.lowMass)
            options.energyMin:Set(cfg.energyMin)
            options.minSec:Set(cfg.minSec)
            options.releaseHoldSec:Set(cfg.releaseHoldSec)
            options.probeSec:Set(cfg.probeSec)
            options.rescanSec:Set(cfg.rescanSec)
            options.startGrace:Set(cfg.startGrace)
            options.abortMove:Set(cfg.abortMove)
            options.abortSec:Set(cfg.abortSec)
            options.skipSec:Set(cfg.skipSec)
"""

CALL_BLOCK = u"""            options.enabled(cfg.enabled)
            options.highMass(cfg.highMass)
            options.lowMass(cfg.lowMass)
            options.energyMin(cfg.energyMin)
            options.minSec(cfg.minSec)
            options.releaseHoldSec(cfg.releaseHoldSec)
            options.probeSec(cfg.probeSec)
            options.rescanSec(cfg.rescanSec)
            options.startGrace(cfg.startGrace)
            options.abortMove(cfg.abortMove)
            options.abortSec(cfg.abortSec)
            options.skipSec(cfg.skipSec)
"""

GUARD = u"""        if writing then return end

"""

CLEAR = u"""            options.resetFlag:Set(false)
"""

BROKEN = [
    (u"1. запись ползунков вызовом вместо :Set",
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
     GUARD, u""),

    (u"6. сброса нет вообще",
     u"        if options.resetFlag() then", u"        if false then"),
]

results = []
for title, old, new in BROKEN:
    if ORIG.count(old) != 1:
        print(u"  ОШИБКА ПОДСТАНОВКИ (%s): вхождений %d" % (title, ORIG.count(old)))
        results.append((title, 999, 0, u"podstanovka ne srabotala"))
        continue
    io.open(OPT, "w", encoding="utf-8", newline="").write(ORIG.replace(old, new))
    p = subprocess.run([sys.executable, TEST], capture_output=True)
    out = p.stdout.decode("utf-8", "replace") + p.stderr.decode("utf-8", "replace")
    fails = out.count("[FAIL]")
    oks = out.count("[OK  ]")
    name = [l for l in out.split("\n") if "[FAIL]" in l][:2]
    ok = fails > 0 or p.returncode != 0
    results.append((title, fails, oks, u"; ".join(x.strip() for x in name)))
    print(u"  %s  %-52s FAIL=%d" % (u"ПОЙМАЛ " if ok else u"ПРОПУСТИЛ",
                                    title, fails))
    for n in name:
        print(u"           " + n.strip())

io.open(OPT, "w", encoding="utf-8", newline="").write(ORIG)
print("")
print(u"исходный код восстановлен")

bad = [r for r in results if r[1] == 0 and r[3] == u"podstanovka ne srabotala"]
if bad:
    sys.exit(1)