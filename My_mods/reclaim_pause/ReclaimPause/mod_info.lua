name = "Reclaim Pause"
version = 36
copyright = "2026 ExtraMassBlocker"
description = "Puts your reclaiming engineers on hold when your mass storage is nearly full (70% by default) and releases them again when you start spending mass (65%). Engineers keep their orders, so on release they carry on from where they stopped. Using the 'UI mod tools' mod, you can change every threshold. Created with AI and may contain errors."
author = "ExtraMassBlocker, Puffskein"
url = ""
-- uid идентифицирует КОНКРЕТНУЮ ВЕРСИЮ мода, а не сам мод, поэтому на каждую
-- новую версию нужен новый uid, а имя остаётся прежним - по имени клиент FAF
-- находит, какой мод обновлять. См. lua/MODS.LUA:41-50 и 69-72.
uid = "22cf9e27-281f-4409-9d26-ce1fc6259b14"
exclusive = false
ui_only = true
-- Флаг для мода "UI mod tools": он сам подхватит modules/options.lua.
-- Без UMT мод работает как обычно, просто на значениях по умолчанию.
__umt = true