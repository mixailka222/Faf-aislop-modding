-- uid идентифицирует КОНКРЕТНУЮ ВЕРСИЮ мода, а не сам мод, поэтому на каждую
-- новую версию нужен новый uid, а имя остаётся прежним - по имени клиент FAF
-- находит, какой мод обновлять. См. lua/MODS.LUA:41-50 и 69-72.
name = "OverflowTesting"
version = 3
uid = "c51f9d24-8a63-4e17-b0f9-6d3a27e8c154"
description = "Diagnostic mod. Writes raw synchronized economy data for your army and your allies to the log once per sync, and nothing else. No panel, no computed overflow, no unit scanning. Used to establish whether the game syncs ally income, expense, stored and max stored resources, and what the 'excess' counter means. Read the game log to use it."
author = "ExtraMassBlocker"
copyright = "2026 ExtraMassBlocker"
url = ""
exclusive = false
ui_only = true