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

`import` создаёт таблицу модуля и выполняет файл через `doscript` с ней как с окружением вместо глобального. Поэтому глобальное присваивание и объявление верхнего уровня `function Start() end` кладут имя в эту таблицу, а не в `_G`, и экспорт делается только так. `import` возвращает саму таблицу, а значение `return` из файла отбрасывается: файл с `return { Start = Start }` отдаёт модуль без этих полей, если функции объявлены как `local`. Соседний файл видит такое имя только через `import(...)`, а прямое обращение к нему даёт `access to nonexistent global variable`. Тест, повторяющий это поведение, выполняет каждый файл в отдельной таблице с `__index = _G`.

Источник: fa:lua/system/import.lua#local ok, msg = pcall(doscript, name, module)
Источник: fa:lua/system/import.lua#-- set up an environment for the new module

### Функция из файла игры не является глобальной

`SetIgnoreSelection`, `CreateUI`, `QuickSave`, `IsNISMode` живут в таблице своего модуля. Запись `local F = SetIgnoreSelection` в другом файле падает при загрузке, нужен `import`.

```lua
local SetIgnoreSelection = import("/lua/ui/game/gamemain.lua").SetIgnoreSelection
```

Источник: fa:lua/keymap/misckeyactions.lua#local SetIgnoreSelection = import("/lua/ui/game/gamemain.lua").SetIgnoreSelection

### Глобальны функции движка и файлов, запущенных через `doscript`

`doscript` без окружения выполняет файл в `_G`. Так появляются `import`, `WaitSeconds`, `AddOnSyncHashedCallback`. Функции движка перечислены в `engine/*.lua`.

Источник: fa:lua/globalInit.lua#doscript '/lua/system/import.lua'

### Циклический `import` безопасен, но отдаёт недозагруженный модуль

`import` сам загружает ещё не загруженный файл, поэтому порядок импорта между файлами обычно неважен. Таблицу модуля он кладёт в кэш до выполнения файла, поэтому повторный `import` возвращает её сразу: модуль может импортировать `gamemain.lua`, из хука которого сам импортирован. Если при загрузке файла A выполняется `import` файла A, вернётся та же таблица с ещё не созданными функциями, а чтение такой функции падает, поэтому при загрузке читать можно только поля, объявленные выше по файлу. Неполную таблицу можно получить только при циклическом импорте и от `lazyimport`.

Источник: fa:lua/system/import.lua#-- add ourselves to prevent loops

### `import` кэширует модуль по пути в нижнем регистре

`import` приводит путь к нижнему регистру, поэтому регистр в пути не важен. Таблица модуля остаётся в реестре `__modules`, и повторный `import` того же пути возвращает её же. Поэтому код верхнего уровня выполняется один раз, а состояние модуля общее для всех файлов, которые его импортировали. Сборщик мусора таблицу не забирает, даже если вызывающий код не хранит ссылку.

Источник: fa:lua/system/import.lua#name = name:lower()
Источник: fa:lua/system/import.lua#-- caching: if it exists then we return the previous version
Источник: fa:lua/system/import.lua#__modules = {}

### Путь без `/` в начале считается от текущего файла

`import('mods/x.lua')` ищет файл рядом с импортирующим модулем, а не в `/mods/`. Пути к модам начинают с `/mods/`.

Источник: fa:lua/system/import.lua#name2 = FileCollapsePath(name .. '/../' .. name2)

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
