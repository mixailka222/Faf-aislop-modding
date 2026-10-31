# Структура мода

Как игра находит и загружает мод, `mod_info.lua`, `import`, установка.

### Минимальный UI-мод состоит из трёх файлов

`mod_info.lua` описывает мод, `hook/lua/ui/game/gamemain.lua` подключает его к игре, `modules/main.lua` хранит логику. Папка `hook` повторяет структуру каталогов игры.

Источник: fa:lua/MODS.LUA#A mod can also contain a `/hook` folder

### При обновлении мода `uid` меняется, а `name` остаётся

`uid` обозначает конкретную версию, по нему другие моды выбирают нужную. По `name` клиент FAF понимает, какой мод обновлять, поэтому версию в `name` не пишут.

Источник: fa:lua/MODS.LUA#Every new version of a mod should get a new GUID

### `version` это целое число

Дробные значения не поддерживаются, число только растёт.

Источник: fa:lua/MODS.LUA#Decimals are not supported.

### `author` обязателен

Пустое значение показывается как `UNKNOWN`. Длиннее 20 символов имя в игре начинает обрезаться.

Источник: fa:lua/MODS.LUA#Required name(s) of author(s).

### Без `uid` мод получает `uid`, равный имени файла

Формально поле необязательно, но такое значение не гарантирует уникальность, поэтому указывают GUID.

Источник: fa:lua/MODS.LUA#uid = filename, -- default uid to name

### `ui_only = true` делает мод личным

Такой мод меняет только UI-состояние Lua, и другим игрокам он не нужен. При `false` (значение по умолчанию) мод обязателен для всех игроков матча.

Источник: fa:lua/MODS.LUA#Setting to true means this mod will only affect the user interface's Lua state.

### `enabled`, `selectable`, `exclusive`

`enabled = false` запрещает загрузку совсем. `selectable = false` прячет мод из списка, но он загружается по `requires` других модов. `exclusive = true` запрещает любые другие активные моды.

Источник: fa:lua/MODS.LUA#Setting enabled to false causes a mod to never be loaded.

### `requires` не влияет на порядок загрузки

Сортировка читает только `before` и `after`. Текст в `MODS.LUA` про подстановку `requires` вместо `after` кодом сортировки не выполняется. Нужный порядок задают явным `after`.

Источник: fa:lua/MODS.LUA#local after_mods = mod.after

### Без `before` и `after` порядок модов произвольный

На фиксированный порядок рассчитывать нельзя. При цикле в этих списках сортировка отменяется целиком для всех модов, в лог идёт предупреждение.

Источник: fa:lua/MODS.LUA#Mods are applied in an arbitrary order.

### Иконка мода: `.png` или `.jpg`

Клиент FAF не читает `.dds`, а игра понимает оба формата. Без поля используется `/textures/ui/common/dialogs/mod-manager/generic-icon_bmp.dds`.

Источник: fa:lua/MODS.LUA#read `.dds` so please use `.png` or `.jpg`

### Моды включают в менеджере модов лобби

`F10` в игре открывает главное меню, менеджера модов на этой клавише нет.

Источник: fa:lua/ui/lobby/lobby.lua#import("/lua/ui/lobby/modsmanager.lua").CreateDialog

### Папку модов задаёт клиент FAF

Игра берёт `mods` из `custom_vault_path`, который передаёт клиент. Папка `Documents\My Games\Gas Powered Games\Supreme Commander Forged Alliance` используется только как запасной вариант, когда этого пути нет.

Источник: fa:init_faf.lua#LoadVaultContent(custom_vault_path)

### Путь `/mods/<имя>` берётся из имени папки

Каждая папка монтируется как `/mods/<папка>`. Поле `name` на путь не влияет.

Источник: fa:init_faf.lua#MountDirectory(dir .. "/" .. mod, "/mods/" .. mod)

### Экспорт модуля это его глобальные имена

Файл модуля выполняется с таблицей модуля вместо глобального окружения, поэтому `function Start() end` кладёт `Start` в эту таблицу. `import` возвращает саму таблицу, а значение `return` из файла отбрасывается. Так делать нельзя: `return { Start = Start }` не экспортирует ничего.

Источник: fa:lua/system/import.lua#local ok, msg = pcall(doscript, name, module)

### Функция из файла игры не является глобальной

`SetIgnoreSelection`, `CreateUI`, `QuickSave`, `IsNISMode` живут в таблице своего модуля. Запись `local F = SetIgnoreSelection` в другом файле падает при загрузке, нужен `import`.

```lua
local SetIgnoreSelection = import("/lua/ui/game/gamemain.lua").SetIgnoreSelection
```

Источник: fa:lua/keymap/misckeyactions.lua#local SetIgnoreSelection = import("/lua/ui/game/gamemain.lua").SetIgnoreSelection

### Глобальны функции движка и файлов, запущенных через `doscript`

`doscript` без окружения выполняет файл в `_G`. Так появляются `import`, `WaitSeconds`, `AddOnSyncHashedCallback`. Функции движка перечислены в `engine/*.lua`.

Источник: fa:lua/globalInit.lua#doscript '/lua/system/import.lua'

### Циклический импорт безопасен

Таблица модуля регистрируется до выполнения файла, поэтому повторный `import` возвращает её сразу. Модуль может импортировать `gamemain.lua`, из хука которого сам импортирован. Читать при загрузке можно только поля, объявленные выше по файлу.

Источник: fa:lua/system/import.lua#-- add ourselves to prevent loops

### Файл модуля выполняется один раз

Повторный `import` того же пути возвращает готовую таблицу.

Источник: fa:lua/system/import.lua#-- caching: if it exists then we return the previous version

### Регистр в пути `import` не важен

`import` приводит путь к нижнему регистру.

Источник: fa:lua/system/import.lua#name = name:lower()

### Путь без `/` в начале считается от текущего файла

`import('mods/x.lua')` ищет файл рядом с импортирующим модулем, а не в `/mods/`. Пути к модам начинают с `/mods/`.

Источник: fa:lua/system/import.lua#name2 = FileCollapsePath(name .. '/../' .. name2)

### Каждый файл мода выполняется в своей таблице модуля

`import` создаёт таблицу и выполняет файл с ней как с окружением, поэтому присваивание «глобального» имени остаётся в этой таблице. Соседний файл его не видит и обращается к нему только через то, что вернул `import()`. Тест, повторяющий это поведение, выполняет каждый файл в отдельной таблице с `__index = _G`.

Источник: fa:lua/system/import.lua#local ok, msg = pcall(doscript, name, module)

### Импортированный модуль живёт в `__modules`

Таблица модуля остаётся в реестре, и повторный `import` возвращает её же. Сборщик мусора её не забирает, даже если вызывающий код не хранит ссылку.

Источник: fa:lua/system/import.lua#__modules = {}

### `import` сам загружает ещё не загруженный файл

Порядок импорта между файлами обычно неважен. Ошибка при выполнении файла даёт `Error importing '...'` и убирает модуль из реестра. Неполную таблицу можно получить только при циклическом импорте и от `lazyimport`.

Источник: fa:lua/system/import.lua#-- add ourselves to prevent loops

### Обращение к отсутствующему имени бросает ошибку

Таблица модуля читает через `__index = _G`, а у `_G` есть `__index`, вызывающий `error`. Поэтому и `X == nil`, и `type(module.X)` падают на отсутствующем имени, а не дают `nil`. Наличие проверяют через `rawget(_G, 'X')` или `rawget(module, 'X')`, так делает сама игра.

Источник: fa:lua/simInit.lua#if rawget(_G, "SetNavigatorPersonalPosMaxDistance") then

### `iscallable` проверяет вызываемость надёжнее `type`

Игра считает вызываемым `function`, `cfunction` и таблицу с `__call`. Сравнение `type(f) == 'function'` покрывает только первый случай.

Источник: fa:lua/system/config.lua#if tt == 'function' or tt == 'cfunction' then

### Файлы .bp подхватываются только у sim-модов

Регистрировать их и класть в `/hook` не нужно. ID берётся из поля `BlueprintId`, а у юнита без него из имени файла без суффикса `_unit.bp`.

Источник: fa:lua/MODS.LUA#If an active sim mod has any .bp files, they will be automatically run during blueprint loading

### Merge меняет блюпринт частично

С `Merge = true` заменяются только указанные поля, включая вложенные таблицы. Поле удаляют значением `"__nil"`, категории меняют через `AddCategories` и `DelCategories`, оружие через `ModWeapon`.

Источник: fa:lua/MODS.LUA#replace the one currently there unless the `Merge = true` flag is set in the blueprint.

### ModBlueprints меняет блюпринты кодом

Для массовых правок есть `SetModBlueprintFunction` в файле `.bp` и старый хук `ModBlueprints` в `/lua/system/Blueprints.lua`.

Источник: fa:lua/MODS.LUA#The newer method is using the function `SetModBlueprintFunction`, which you can call from a `.bp`

### `return` модуля отбрасывается

`import` выполняет файл через `doscript` и возвращает свою таблицу модуля, а не результат файла. Экспорт делается только объявлениями верхнего уровня: `function Start() end`. Файл с `return { Start = Start }` отдаёт модуль без этих полей, если функции объявлены как `local`.

Источник: fa:lua/system/import.lua#local ok, msg = pcall(doscript, name, module)

### У каждого файла своё окружение

Глобальное присваивание в файле мода попадает в таблицу этого модуля, а не в `_G`. Соседний файл видит такое имя только через `import(...)`, а прямое обращение к нему даёт `access to nonexistent global variable`.

Источник: fa:lua/system/import.lua#-- set up an environment for the new module

### Отсутствующее поле модуля это ошибка, а не `nil`

`__index` таблицы модуля ведёт в `_G`, а у `_G` стоит `__index` с `error()`. Поэтому проверка `if Mod.Name then` сама падает, а проверять надо через `rawget(Mod, "Name")`. Сначала `type(Mod) == "table"`, потому что `rawget` принимает только таблицу.

Источник: fa:lua/system/import.lua#__module_metatable = {

### `pcall(import, path)` не ловит ошибку компиляции

При синтаксической ошибке `doscript` только пишет `WARNING` в лог, `pcall` возвращает `true`, а модуль остаётся пустым. Чтение его поля вне `pcall` падает, и в хуке `gamemain.lua` это ломает загрузку самого `gamemain.lua`. В хуке точку входа читают только через `rawget`.

Источник: fa:lua/sim/Profiler.lua#this doesn't catch any errors inside `doscript`

### Циклический `import` отдаёт недозагруженный модуль

`import` кладёт таблицу модуля в кэш до выполнения файла. Если при загрузке файла A выполняется `import` файла A, вернётся та же таблица с ещё не созданными функциями, а чтение такой функции падает.

Источник: fa:lua/system/import.lua#-- add ourselves to prevent loops

### `import` кэширует модуль по пути в нижнем регистре

Повторный `import` возвращает ту же таблицу, поэтому состояние модуля общее для всех файлов, которые его импортировали. Код верхнего уровня выполняется один раз.

Источник: fa:lua/system/import.lua#name = name:lower()
