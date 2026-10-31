# Хуки

Как работают файлы `hook/` и перехват функций игры.

### Хук дописывается в конец игрового файла

Файл из `hook/` не заменяет игровой. Он склеивается с ним и выполняется как одно целое, в окружении этого файла, поэтому хук видит `local` оригинального файла: хук ReUI читает `ignoreSelection`, объявленную в `gamemain.lua` как `local`. Хуки всех модов дописываются друг за другом.

Источник: fa:lua/MODS.LUA#it defines a hook of the same name; if so, the file is concatenated to the end of the script before
Источник: ui-libs:mods/ReUI/hook/lua/ui/game/gamemain.lua#return ignoreSelection or import('/lua/ui/game/selection.lua').IsHidden()

### Код хука оборачивают в `do ... end`

Иначе его локальные переменные окажутся видны хукам, которые дописаны после него.

Источник: fa:lua/MODS.LUA#introduce new scope to gaurentee our local variables

### Хук функции вызывает прежнюю версию

Функцию оригинала заменяют обычным объявлением. Прежнюю версию нужно сохранить в локальной переменной и вызвать, иначе теряется исходное поведение и изменения других модов.

```lua
do
    local oldFn = Fn
    function Fn(arg)
        oldFn(arg)
        -- своя работа
    end
end
```

Источник: fa:lua/MODS.LUA#-- preserve original behavior or another mod's changes

### Хук метода класса создаёт производный класс

```lua
do
    local oldCls = Cls
    local oldMethod = oldCls.Method
    Cls = Class(oldCls) {
        Method = function(self, arg)
            oldMethod(self, arg)
        end,
    }
end
```

Источник: fa:lua/MODS.LUA#local oldMethod = oldCls.Method

### Безопасный хук `CreateUI`

Экспорт читается через `rawget` до установки хука. Этот вид переживает опечатку в пути, ошибку при выполнении модуля и ошибку компиляции.

```lua
do
    local ok, Mod = pcall(import, '/mods/MyMod/modules/main.lua')
    local OnCreateUI = type(Mod) == 'table' and rawget(Mod, 'OnCreateUI')
    if not ok or type(OnCreateUI) ~= 'function' then
        LOG('MyMod: NOT LOADED - ' .. tostring(Mod))
    else
        local OldCreateUI = CreateUI
        function CreateUI(isReplay)
            OldCreateUI(isReplay)
            local ok2, err = pcall(OnCreateUI)
            if not ok2 then LOG('MyMod: ' .. tostring(err)) end
        end
    end
end
```

Источник: fa:lua/ui/game/gamemain.lua#function CreateUI(isReplay)

### Ошибка в хуке ломает игровой файл

Хук стал частью игрового файла, поэтому необработанная ошибка в нём обрывает загрузку этого файла целиком.

Наблюдение: ошибка верхнего уровня в хуке `gamemain.lua` и ошибка внутри `CreateUI`: вместо карты чёрный экран с отдельными элементами интерфейса.

### `pcall(Mod.Field)` не защищает чтение поля

Аргумент вычисляется до входа в `pcall`. Отсутствующее поле модуля вызывает ошибку снаружи `pcall`, в месте вызова. Поле достают через `rawget` заранее.

Источник: fa:lua/system/config.lua#error("access to nonexistent global variable " .. repr(key), 2)

### Номера строк в ошибке относятся к склеенному файлу

Номер равен сумме строк игрового файла, предыдущих хуков и строки внутри своего хука. Порядок хуков виден в логе по строкам `Hooked <файл> with <хук>`.

Источник: fa:lua/MODS.LUA#it defines a hook of the same name; if so, the file is concatenated to the end of the script before
Наблюдение: трассировка `gamemain.lua(1884)` при 1248 строках в игровом файле и 13 хуках на него. Суммирование строк сошлось с реальным местом ошибки.

### Хук выполняется при загрузке файла, а `CreateUI` позже

Код хука вне функций выполняется при загрузке игрового файла, когда интерфейс ещё не построен. Чтобы увидеть панели игры и других модов, работу откладывают в перехват `CreateUI`.

Источник: fa:lua/ui/game/gamemain.lua#function CreateUI(isReplay)

### `userInit.lua` выполняется в каждой игровой сессии

Файл запускается в свежем Lua-состоянии при старте сессии, а не при запуске клиента.

Источник: fa:lua/SessionInit.lua#doscript '/lua/userInit.lua'

### Хук `ui_only`-мода на `userInit.lua` может не сработать

`SessionInit.lua` выполняет `userInit.lua` раньше, чем добавляет UI-моды в `__active_mods`.

Не подтверждено: нужен лог игры с `ui_only`-модом, который хукает `/lua/userInit.lua`, и строка `Hooked` для него.

### Верхнеуровневый `return` в файле хука опасен

После склейки за `return` идёт код следующего хука, а компилятор требует, чтобы `return` был последним в блоке: `<eof> expected near ...`. Ошибка отключит весь игровой файл.

Не подтверждено: нужен запуск игры с двумя хуками на один файл, где первый заканчивается на `return`.

### BOM в начале обычного файла не мешает

Компилятор пропускает BOM при чтении файла. В поставке игры с BOM начинаются `lua/armordefinition.lua`, `lua/ui/game/taunt.lua` и ещё три файла.

Источник: lua-lang:HISTORY#skip BOM and unix style # comments when reading files

### BOM в файле хука опасен

Пропускается только BOM в самом начале. Посреди текста тот же компилятор выдаёт `unexpected symbol near`, а файл хука оказывается в середине склейки. `luac` по отдельному файлу этого не покажет.

Не подтверждено: нужен запуск игры с хуком, сохранённым с BOM.

### Хук `defaultKeyMap.lua` действует не всегда

`GetCurrentKeyMap` берёт `GetUserKeyMap() or GetDefaultKeyMap()`, поэтому своя карта игрока целиком заменяет карту по умолчанию: это замена, а не слияние. Первая правка клавиши копирует текущую карту в `UserKeyMap` целиком, поэтому клавиши мода, подключённого позже, туда не попадают. Файл карты по умолчанию выбирает `GetDefaultKeyMapName` по настройке `UserKeyMapName`: при другом пресете читается другой файл со своей таблицей `defaultKeyMap`, и хук файла `defaultKeyMap.lua` к нему не относится. Надёжный путь: действие из `keyActions` остаётся, а клавишу игрок назначает в меню вручную.

Источник: fa:lua/keymap/keymapper.lua#return GetUserKeyMap() or GetDefaultKeyMap()
Источник: fa:lua/keymap/keymapper.lua#return Prefs.GetFromCurrentProfile("UserKeyMapName") or "/lua/keymap/defaultkeymap.lua"

### Клавиша действия из мода может не дойти до партии

Лобби строит карту клавиш партии до старта сессии, а UI-моды попадают в `__active_mods` только в `SessionInit.lua`. Действия из хука `keyactions.lua` лобби поэтому не знает, и привязанная к ним клавиша в партию не попадает. Мод ставит такую клавишу сам при создании интерфейса через `IN_AddKeyMapTable`. ReUI.Actions решает это иначе: записывает действия в `UserKeyActions`.

Источник: fa:lua/ui/lobby/lobby.lua#IN_AddKeyMapTable(import("/lua/keymap/keymapper.lua").GetKeyMappings(
Источник: fa:lua/SessionInit.lua#table.insert(__active_mods, m)
Источник: ui-libs:mods/ReUI/Actions/Actions.lua#SetUserKeyAction(

Не подтверждено: что хуки UI-модов не действуют в лобби. Вывод сделан по коду, нужен лог партии со строкой `Keybindings cannot find action`.

### Клавиша `pause_unit` зависит от раскладки

`Z` в `defaultKeyMap.lua`, `Tab` в `alternativeKeyMap.lua` и `hotbuildKeyMap.lua`.

Источник: fa:lua/keymap/alternativeKeyMap.lua#['Tab']                 = 'pause_unit',

### Ошибка в `CreateUI` прерывает создание интерфейса

`CreateGameInterface` вызывает `CreateUI(isReplay)` без `pcall`, поэтому необработанная ошибка в хуке прерывает его, код после вызова не выполняется, и остаётся чёрный экран. В хуке сначала зовут оригинал, затем свой код под `pcall` с записью ошибки в лог, а `CreateUI` заменяют только если модуль мода загрузился.

Источник: fa:lua/ui/game/gamemain.lua#provider.CreateGameInterface = function(self, inIsReplay)
Наблюдение: партия с модом, в котором ошибка возникала при построении интерфейса.
