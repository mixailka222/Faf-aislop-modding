"""Проверка: все ли локальные пути import('/mods/...') существуют в папке мода."""
import os, re, sys

root = os.path.abspath(sys.argv[1])
modname = os.path.basename(root)          # имя папки мода
prefix = "/mods/%s/" % modname
bad = 0
total = 0
for dp, dn, fn in os.walk(root):
    for f in fn:
        if not f.endswith(".lua"):
            continue
        p = os.path.join(dp, f)
        src = open(p, encoding="utf-8").read()
        for m in re.finditer(r"import\(\s*'(/mods/[^']+)'", src):
            rel = m.group(1)
            if not rel.startswith(prefix):
                print("  ЧУЖОЙ %-46s (%s)" % (rel, f))
                continue
            local = rel[len(prefix):].replace("/", os.sep)
            exists = os.path.exists(os.path.join(root, local))
            total += 1
            print("  %s  %-46s (%s)" % ("OK  " if exists else "НЕТ ", rel, f))
            if not exists:
                bad += 1
print()
print("локальных импортов: %d, битых: %d" % (total, bad))
