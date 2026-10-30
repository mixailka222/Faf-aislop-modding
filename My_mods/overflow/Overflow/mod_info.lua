name = "Overflow"
version = 35
copyright = "2026 ExtraMassBlocker"
description = "Shows how much energy you receive from allies through overflow (resource sharing) and how much you give away. Using the 'UI mod tools' mod, you can configure the panel to include additional info, such as mass overflow. Created with AI and may contain errors."
author = "ExtraMassBlocker"
url = ""
-- uid идентифицирует КОНКРЕТНУЮ ВЕРСИЮ мода, а не сам мод, поэтому на каждую
-- новую версию нужен новый uid, а имя остаётся прежним - по имени клиент FAF
-- находит, какой мод обновлять. См. lua/MODS.LUA:41-50 и 69-72.
uid = "9e9cf7ee-e34c-4a4e-af4e-f947a8e3b300"
exclusive = false
ui_only = true
-- флаг "__umt" открывает модуль modules/Options.lua моду "UI mod tools":
-- он ищет этот файл сам (mods/umt/modules/Options.lua:363) и вызывает у
-- него Main(). Без UMT страница настроек не откроется, и мод покажет набор
-- по умолчанию: две строки - перелив энергии союзникам и энергия от нас.
__umt = true
