# Юнит-тест настоящего sync.lua на ЗАДАННЫХ числах, где ответ известен заранее.
#
# Лог игры больше не подходит: предыдущий файл с диагностикой заменён.
# Зато тут всё детерминировано - ожидания выведены из формулы руками.
#
# Сценарии (окно 2 с, значит делим на 2, чтобы получить /с):
#
#  A. у союзника есть место, наше хранилище полное
#     ME:   dIn=40  dOut=0  dExc=0  dSt=0   -> исходящий 40/2 = 20/с
#     ALLY: dIn=40  dOut=0  dExc=0  dSt=40  -> союзник отдал 0
#     входящий = 0, своё = 40/2 - 0 = 20/с
#
#  B. оба хранилища полные, излишек уходит в пустоту
#     ME:   dIn=40  dOut=0  dExc=40 dSt=0   -> исходящий 0, всё сгорело
#     входящий = 0, своё = 20/с
#
#  C. мы тратим, союзник делится с нами
#     ME:   dIn=72  dOut=140 dExc=0  dSt=0   -> исходящий 0 (переполнение)
#     ALLY: dIn=40  dOut=8  dExc=0  dSt=0   -> союзник отдал 32/2 = 16/с
#     входящий = 16/с, своё = 36 - 16 = 20/с
import io, os, sys
from lupa import luajit21 as lupa

HERE = os.path.dirname(os.path.abspath(__file__))
SYNC = os.path.abspath(os.path.join(os.path.dirname(HERE),
                                   "Overflow", "modules", "sync.lua"))
src = io.open(SYNC, encoding="utf-8").read()
# единственная правка формы обхода, см. раздел 3.21 методички
src = src.replace("for armyIdx in scoreData do", "for armyIdx in next, scoreData do")

lua = lupa.LuaRuntime(unpack_returned_tuples=True)
g = lua.globals()
msgs = []
def _L(m):
    msgs.append(str(m)); return True
TICK = lua.table_from([0]); FOCUS = lua.table_from([1]); CB = lua.table_from([None])
g["TICK"] = TICK; g["FOCUS"] = FOCUS; g["CB"] = CB; g["LOG"] = _L
g["GameTick"] = lua.eval("function() return TICK[1] end")
g["GetFocusArmy"] = lua.eval("function() return FOCUS[1] end")
g["GetSimTicksPerSecond"] = lua.eval("function() return 10 end")
g["IsAlly"] = lua.eval("function(a, b) return (a == 1 and b == 2) end")
g["AddOnSyncHashedCallback"] = lua.eval("function(cb, cat, id) CB[1] = cb end")
g["RemoveOnSyncHashedCallback"] = lua.eval("function(cat, id) CB[1] = nil end")
g["import"] = lua.eval("function(p) return {} end")
# Движок отдаёт income ЗА ТИК. Мод умножает на simFreq (10).
# Ставим 2.0 -> 20/с, как командир.
g["GetEconomyTotals"] = lua.eval("""function()
  return { income = { ENERGY = 2.0, MASS = 0.1 },
           reclaimed = { ENERGY = 0.0, MASS = 0.0 },
           stored = { ENERGY = 4000.0, MASS = 650.0 },
           maxStorage = { ENERGY = 4000.0, MASS = 650.0 },
           lastUseActual = { ENERGY = 0.0, MASS = 0.0 } }
end""")

ret = lua.execute(src)
# В ФАФ значение return ОТБРАСЫВАЕТСЯ: экспорт идёт через глобалы,
# потому что doscript выполняет файл с таблицей модуля как окружением
# (import.lua:61). Поэтому и здесь проверяем глобалы, а не результат execute.
print("значение return модуля:", "None - так и должно быть" if ret is None else ret)
assert ret is None, "модуль не должен ничего возвращать: экспорт через глобалы"
_ltype = lua.eval("function(x) return type(x) end")
for need in ("Start", "GetResult"):
    got = _ltype(g[need])
    assert got == "function", "экспорт %s отсутствует (type=%s)" % (need, got)
print("экспорт на месте: Start, GetResult")

start = g["Start"]
getres = g["GetResult"]
start()
cb = CB[1]
if cb is None:
    print("НЕТ КОЛБЭКА")
    sys.exit(1)

def payload(me_ein, me_eout, me_eexc, me_est, me_emin, me_mout, me_mexc, me_mstore,
            al_ein, al_eout, al_eexc, al_est):
    return lua.execute("""return {
      [1]={resources={
        energyin={total=%s,reclaimed=0.0}, energyout={total=%s,excess=%s},
        massin={total=%s,reclaimed=0.0}, massout={total=%s,excess=%s},
        storage={storedEnergy=%s,storedMass=%s}}},
      [2]={resources={
        energyin={total=%s,reclaimed=0.0}, energyout={total=%s,excess=%s},
        massin={total=0.0,reclaimed=0.0}, massout={total=0.0,excess=0.0},
        storage={storedEnergy=%s,storedMass=0.0}}}
    }""" % (me_ein, me_eout, me_eexc, me_emin, me_mout, me_mexc, me_est, me_mstore,
            al_ein, al_eout, al_eexc, al_est))

def feed(tick, p):
    TICK[1] = tick
    FOCUS[1] = 1
    cb(p)
    r = getres()
    if r is None:
        return None
    return {k: r[k] for k in ("incoming", "outgoing", "own", "massOutgoing",
                              "elapsed")}

# Окно теперь 50 тиков, и дельты КОПЯТСЯ. Значит каждый payload добавляет
# своё, а публикация происходит раз в 50 тиков. Подаём много шагов и смотрим
# результат после каждой публикации.

TICK_PER_STEP = 18          # так приходят payload в игре
WINDOW = 50                 # WINDOW_TICKS в sync.lua
PROD_E = 20                 # 2.0/тик * 10 = 20/с
PROD_M = 1

def feed(tick, p):
    TICK[1] = tick
    FOCUS[1] = 1
    cb(p)
    r = getres()
    if r is None:
        return None
    return {k: r[k] for k in ("incoming", "outgoing", "own", "massOutgoing",
                              "elapsed")}

def series(nSteps, meFn, alFn):
    """Прогоняет nSteps payload подряд, возвращает все публикации.

    СБРОС ОБЯЗАТЕЛЕН: счётчики модуля переживают сценарий, а следующий
    начинается с меньших тиков, и разности выходят отрицательными.
    """
    g["ResetCounters"]()
    out = []
    tick = 60
    for i in range(nSteps):
        tick = tick + TICK_PER_STEP
        r = feed(tick, payload(*(meFn(i) + alFn(i))))
        if r is not None:
            out.append(r)
    return out

def mkME(i, eout, eexc, estore, mout, mstore, mexc):
    return (4000 + PROD_E * ((i + 1) * TICK_PER_STEP) / 10.0,
            eout, eexc, estore,
            650 + PROD_M * ((i + 1) * TICK_PER_STEP) / 10.0,
            mout, mexc, mstore)

def mkAL(i, ein, eout, estore):
    return (ein, eout, 0.0, estore)

# A: у союзника есть место. Наш излишек (dSt=0, dExc=0) уходит к нему,
#    у союзника растёт запас.
def aME(i):
    return mkME(i, 0, 0, 4000, 0, 650, 0)
def aAL(i):
    return mkAL(i, 4000 + PROD_E * ((i + 1) * TICK_PER_STEP) / 10.0, 0,
               PROD_E * ((i + 1) * TICK_PER_STEP) / 10.0)

# B: оба полные, наш излишек сгорает (dExc повторяет dIn)
def bME(i):
    dIn = PROD_E * TICK_PER_STEP / 10.0
    return mkME(i, 0, 4000 + dIn * (i + 1), 4000, 0, 650, 650 + PROD_M * TICK_PER_STEP / 10.0 * (i + 1))
def bAL(i):
    return mkAL(i, 4000 + PROD_E * ((i + 1) * TICK_PER_STEP) / 10.0, 0,
               PROD_E * ((i + 1) * TICK_PER_STEP) / 10.0)

# C: союзник делится с нами: его излишек 20-8=12/с -> к нам
def cME(i):
    dIn = PROD_E * TICK_PER_STEP / 10.0
    return mkME(i, 140 * TICK_PER_STEP / 10.0 * (i + 1), 4000 + dIn * (i + 1),
                4000, 0, 650, 0)
def cAL(i):
    # запас ПОСТОЯННЫЙ: союзник полон и расти не может.
    # Тогда исходящий союзника = (36 - 14.4 - 0 - 0) / 1.8 = 12/с
    return mkAL(i, 4000 + PROD_E * ((i + 1) * TICK_PER_STEP) / 10.0,
               8 * TICK_PER_STEP / 10.0 * (i + 1),
               0.0)

pubA = series(8, aME, aAL)
pubB = series(8, bME, bAL)
pubC = series(8, cME, cAL)

a = pubA[-1] if pubA else None
b = pubB[-1] if pubB else None
c = pubC[-1] if pubC else None
print("публикаций: A=%d B=%d C=%d" % (len(pubA), len(pubB), len(pubC)))

fails = []
def check(name, got, want, tol=0.01):
    ok = got is not None and abs(got - want) <= tol
    print("  [%s] %-34s получено %-8s ожидалось %s"
          % ("OK  " if ok else "FAIL", name,
             "None" if got is None else "%.2f" % got, want))
    if not ok:
        fails.append(name)

print()
print("=== Сценарий A: место у союзника есть ===")
check("исходящий, /с", a and a["outgoing"], 20)
check("входящий, /с", a and a["incoming"], 0)
check("своё, /с", a and a["own"], 20)

print()
print("=== Сценарий B: место НИ У КОГО НЕТ, излишек сгорает ===")
check("исходящий, /с", b and b["outgoing"], 0)
check("входящий, /с", b and b["incoming"], 0)
check("своё, /с", b and b["own"], 20)

print()
print("=== Сценарий C: союзник отдаёт 12/с ===")
check("входящий, /с", c and c["incoming"], 12)
check("исходящий, /с", c and c["outgoing"], 0)
check("своё, /с = income(20) - входящий(12)", c and c["own"], 8)

print()
print("=== МАССА: сценарий A ===")
check("исходящий M, /с", a and a["massOutgoing"], 1)

print()
errs = [m for m in msgs if "ERROR" in str(m) or "FAILED" in str(m)]
print("ошибок модуля: %d" % len(errs))
for m in errs[:5]:
    print("  ", m)
print()
print("ИТОГ: %s" % ("все проверки пройдены" if not fails and not errs
                    else "провалено: " + ", ".join(fails)))