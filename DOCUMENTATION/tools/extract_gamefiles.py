"""
extract_gamefiles.py - распаковка игровых файлов FAF для исследования.

Зачем: игровые файлы лежат в C:\\ProgramData\\faforever\\gamedata\\*.nx2
внутри zip-архивов с нестандартными локальными заголовками. Обычный unzip
их не читает. Этот скрипт читает центральный каталог (имена там открытые)
и распаковывает содержимое.

Это ПЕРВИЧНЫЙ источник. Он важнее репозитория GitHub, потому что показывает
именно тот код, который реально работает у игрока.

Использование:
    python extract_gamefiles.py <путь-к-архиву.nx2> <папка-назначения> [фильтр]

Пример - распаковать весь игровой Lua-код:
    python extract_gamefiles.py "C:\\ProgramData\\faforever\\gamedata\\lua.nx2" .\\gamefiles .lua

Требуется Python 3.8+. Сторонних библиотек не нужно.
"""

import struct
import sys
import os
import zlib


def read_entries(path):
    """Возвращает список (имя, метод_сжатия, размер_сжатого, размер_исходного,
    смещение_локального_заголовка, crc32) из центрального каталога zip."""
    f = open(path, "rb")
    size = os.path.getsize(path)

    tail_start = max(0, size - 66000)
    f.seek(tail_start)
    tail = f.read()
    idx = tail.rfind(b"PK\x05\x06")
    if idx < 0:
        raise SystemExit("EOCD не найден - это не zip-архив: " + path)
    _, _, _, _, ntot, cdsize, cdoff, _ = struct.unpack_from("<IHHHHIIH", tail, idx)

    f.seek(cdoff)
    cd = f.read(cdsize)
    off = 0
    for _ in range(ntot):
        if cd[off:off + 4] != b"PK\x01\x02":
            break
        (sig, vmade, vneed, flags, comp, t, d, crc, csize, usize,
         fnlen, exlen, comlen, dstart, iattr, eattr, lho) = struct.unpack_from(
            "<IHHHHHHIIIHHHHHII", cd, off)
        name = cd[off + 46:off + 46 + fnlen].decode("utf-8", "replace")
        off += 46 + fnlen + exlen + comlen
        yield name, comp, csize, usize, lho, crc
    f.close()


def data_start(f, lho):
    """Смещение начала данных файла = начало локального заголовка + его длина.
    У .nx2/.scd локальный заголовок короче стандартного, поэтому длину
    вычисляем по месту, а не по константе."""
    f.seek(lho)
    lh = f.read(30)
    fnlen, exlen = struct.unpack_from("<HH", lh, 26)
    return lho + 30 + fnlen + exlen


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return
    archive, outdir = sys.argv[1], sys.argv[2]
    pats = sys.argv[3:]

    f = open(archive, "rb")
    ok = skip = 0
    try:
        for name, comp, csize, usize, lho, crc in read_entries(archive):
            if pats and not any(p.lower() in name.lower() for p in pats):
                continue
            if name.endswith("/"):
                continue
            f.seek(data_start(f, lho))
            blob = f.read(csize)
            if comp == 0:
                data = blob
            elif comp == 8:
                try:
                    data = zlib.decompressobj(-15).decompress(blob)
                except zlib.error as e:
                    print("DECOMP FAIL", name, e)
                    skip += 1
                    continue
            else:
                skip += 1
                continue
            if usize and len(data) != usize:
                print("SIZE MISMATCH", name, len(data), usize)
                skip += 1
                continue
            if crc and zlib.crc32(data) & 0xffffffff != crc:
                print("CRC MISMATCH", name)
                skip += 1
                continue
            dest = os.path.join(outdir, name.replace("/", os.sep))
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            with open(dest, "wb") as out:
                out.write(data)
            ok += 1
    finally:
        f.close()
    print("распаковано %d, пропущено %d -> %s" % (ok, skip, outdir))


main()
