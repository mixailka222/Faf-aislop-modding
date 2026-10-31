# Отладка

Логи, сообщения движка и как их читать.

### Чтение несуществующего глобала вызывает ошибку

На `_G` висит `__index` с `error`, поэтому результат не `nil`, а сообщение `access to nonexistent global variable "X"`. При загрузке модуля такая ошибка отключает модуль, в работающем коде обрывает только текущий вызов.

Источник: fa:lua/system/config.lua#error("access to nonexistent global variable " .. repr(key), 2)

### Отсутствующее поле модуля читается как несуществующий глобал

У таблицы модуля `__index` указывает на `_G`, поэтому `Mod.Missing` падает с тем же сообщением. `if Mod.Missing then` тоже падает. Наличие поля проверяют через `rawget(Mod, 'Missing')`.

Источник: fa:lua/system/import.lua#__index = _G

### Ошибка компиляции модуля не вызывает ошибку `import`

`doscript` пишет `WARNING: SCR_LuaDoFileConcat: Loading "..." failed: ...` и завершается без ошибки. `pcall(import, path)` возвращает `true` и пустой модуль, а виновным в логе выглядит файл, который читает его поле. Отказ файла ищут в логе по `SCR_LuaDoFileConcat`.

Источник: fa:lua/sim/Profiler.lua#this doesn't catch any errors inside `doscript`, only explicit Lua errors

### `Error importing` значит, что файла нет или он упал при выполнении

Настоящая причина записана строкой `WARN` прямо перед этой ошибкой.

Источник: fa:lua/system/import.lua#error("Error importing '" .. name .. "'", 2)

### Ожидание внутри `pcall` обрывает функцию

`WaitSeconds`, `WaitTicks`, `WaitFrames` это `coroutine.yield`, а уступить управление через C-функцию нельзя. `pcall` вернёт `false` с текстом `attempt to yield across metamethod/C-call boundary`, код после ожидания не выполнится, а поток продолжит работу после `pcall`. То же касается `xpcall`, метаметодов и колбэков C-функций.

Источник: lua-lang:src/ldo.c#attempt to yield across metamethod/C-call boundary

### `ForkThread` внутри `pcall` безопасен

Новый поток это отдельная корутина, её ожидания через `pcall` не проходят.

Источник: fa:engine/Core.lua#function ForkThread(callback, ...)

### Ждать можно только в потоке

`CreateUI`, beat-функции и колбэки синхронизации потоками не являются, ожидание запускают через `ForkThread`.

Источник: fa:lua/userInit.lua#WaitFrames = coroutine.yield

### `Expected a game object` означает вызов метода через точку

Компилятор такое не ловит, ошибка возникает в момент вызова.

Наблюдение: строка `Expected a game object. (Did you call with '.' instead of ':'?)` есть в `ForgedAlliance.exe`, в логе она появилась при `control.EnableHitTest(true)`.

### Имена локальных переменных не ограничены

Подходит любое имя, кроме ключевых слов. `local line`, `count`, `name`, `key`, `index`, `value` встречаются в коде игры сотни раз. `local type` и `local next` скрывают встроенные функции только в своей области, как в обычном Lua.

Источник: fa:lua/ui/game/score.lua#local line = {}

### Где лежит лог

`%APPDATA%\Forged Alliance Forever\logs\`: `game_<id>.log` для матчей и `replay_<id>.log` для реплеев. Метка уровня в файле пишется строчными буквами, например `info:`, поэтому поиск ведут без учёта регистра.

Наблюдение: содержимое папки логов на компьютере разработчика.

### Полнота лога текущей сессии

Пока игра открыта, файл текущей партии может быть неполным, а самый свежий по дате файл может относиться к прошлой сессии.

Не подтверждено: нужно открыть лог во время матча и сравнить его с файлом после выхода из игры.

### Архивы `.nx2` открываются обычным zip

Стандартный `zipfile` из Python читает `lua.nx2` и `units.nx2`, проверка целостности проходит. В `lua.nx2` лежит весь игровой Lua.

Наблюдение: `zipfile.ZipFile` и `testzip()` на файлах из `C:\ProgramData\faforever\gamedata`.

### В тестах через `lupa` не работает `for k in t do`

В игре такой цикл штатный, а Lua внутри `lupa` его не знает: `attempt to call a table value`. Для прогона копии файла цикл заменяют на `for k in next, t do`. Код мода менять не нужно.

Источник: fa:lua/UserSync.lua#for k, data in Sync do

### `lupa.table_from` не преобразует вложенные словари

Верхний уровень становится таблицей Lua, вложенный словарь остаётся `userdata`. Вложенные данные собирают литералом Lua через `lua.execute`.

Наблюдение: `lupa` 2.8, `luajit21`, `type(t.a)` вернул `userdata`.

### `table.getn` считает только ключи подряд от 1

На таблице с ключами EntityId он вернёт 0, даже если записи есть. Такие таблицы считают обходом `pairs` или через `table.getsize`.

Источник: lua-lang:src/lib/lauxlib.c#for (n = 1; ; n++) {  /* else must count elements */

### `WaitSeconds` внутри `pcall` не ждёт

`WaitSeconds` использует `coroutine.yield`, а через `pcall` уступить управление нельзя. `pcall` вернёт `false` и `attempt to yield across metamethod/C-call boundary`, а поток пойдёт дальше без ожидания. Цикл с таким ожиданием крутится без пауз.

Источник: lua-lang:src/ldo.c#attempt to yield across metamethod/C-call boundary

### Дефис в шаблоне Lua это ленивый квантификатор

`string.find(s, 'release-in')` не находит текст `release-in`: шаблон читается как `releas`, ноль или больше `e`, затем `in`. Дефис экранируют (`'release%-in'`) или ищут подстроку через `string.find(s, 'release-in', 1, true)`.

Источник: lua-lang:src/lib/lstrlib.c#case '-': {  /* 0 or more repetitions (minimum) */

### Вызов локальной функции до её объявления падает как обращение к глобалу

Локальное имя видно только ниже объявления, выше оно компилируется как глобальное. В файле мода это даёт `access to nonexistent global variable "Имя"`, а не `attempt to call`.

Источник: fa:lua/system/config.lua#error("access to nonexistent global variable " .. repr(key), 2)

### Ошибка `too many upvalues` указывает на место использования

Строка в сообщении относится к обращению функции к 33-й внешней переменной, а не к её объявлению. Файл при этом не компилируется, и `import` заканчивается ошибкой.

Источник: lua-lang:src/lparser.c#luaX_checklimit(fs->ls, f->nups + 1, MAXUPVALUES, "upvalues");

### Как ведёт себя необработанная ошибка в потоке `ForkThread`

Тело долгого цикла кладут в `pcall` и пишут ошибку в лог, а `WaitSeconds` оставляют снаружи. Попадает ли в лог ошибка вне `pcall`, не установлено.

Не подтверждено: нужен опыт в игре, `ForkThread(function() error('x') end)` и поиск строки в логе.

### Строки лога о клавишах показывают шаг поломки

`SetUserKeyMapping` пишет `Keybindings adding key`, а `GetKeyMappings` при незнакомом действии пишет `Keybindings cannot find action`. Так отличают незаписанную привязку от незарегистрированного действия.

Источник: fa:lua/keymap/keymapper.lua#WARN('Keybindings cannot find action "' .. action .. '" for key ' .. key)

### Функции лога глобальные

`LOG`, `WARN` и `SPEW` доступны без импорта. Аннотации всех трёх предупреждают, что они не для рабочего кода.

Источник: fa:engine/Core.lua#--- Prints a debug message to the moholog, this shouldn't be used in production code

### Лог партии в клиенте FAF

Файл `%APPDATA%\Forged Alliance Forever\logs\game_<id>.log`, по одному на партию.

Наблюдение: путь взят из команды запуска игры в файле краша, клиент FAF.

### Лог текущей партии может быть неполным до выхода из игры

Поэтому пока игра открыта, отсутствие строки в файле не доказывает, что код её не писал.

Не подтверждено: нужно сравнить содержимое файла во время партии и после выхода.

### Команда чата /debug-log есть только с ключом /debug

Без ключа запуска `/debug` команда не регистрируется. Она выполняет `WIN_ToggleLogDialog`.

Источник: fa:lua/ui/game/chat/commands/builtin/DebugLog.lua#return HasCommandLineArg('/debug')

### Окно лога привязано к отладочной клавише

В стандартной раскладке это `F9`, в раскладке hotbuild `Ctrl-F9`, действие `debug_toggle_log_window`.

Источник: fa:lua/keymap/defaultKeyMap.lua#= 'debug_toggle_log_window',

### Формат ошибок Lua в логе игры

В логе игры ошибка выглядит как `файл(строка): сообщение near `токен'`. Локальные `lua.exe` и `luac.exe` пишут иначе: `файл:строка: сообщение`.

Наблюдение: логи FAF с ошибками модов, например `ui.lua(418): too many upvalues (limit=32) near `,'`. Локальный формат проверен запуском `.tools/faf-lua`.

### Необработанная ошибка в CreateUI оставляет чёрный экран

Вызов своего кода из хука `CreateUI` защищают `pcall`, а ошибку пишут в лог.

Наблюдение: партия с модом, в котором ошибка возникала при построении интерфейса.

### pcall возвращает все значения функции

`local ok, a, b = pcall(fn)` даёт оба результата `fn`. Ждать внутри `pcall` нельзя: `coroutine.yield` падает с ошибкой `attempt to yield across metamethod/C-call boundary`.

Наблюдение: проверено запуском в `.tools/faf-lua/lua.exe`.

### Имена в сообщениях Lua стоят в кавычках `` `x' ``

Движок печатает имя между обратным апострофом и прямым: ``attempt to call method `Foo' (a nil value)``. Искать в логе надо именно такой вид, а не `'Foo'`.

Источник: lua-lang:src/ldebug.c#luaG_runerror(L, "attempt to %s %s `%s' (a %s value)",

### `attempt to yield across metamethod/C-call boundary`: ожидание внутри `pcall`

`WaitSeconds` сводится к `coroutine.yield`, а `pcall`, метаметоды, компаратор `table.sort` и колбэк `string.gsub` работают через C-границу, и передать управление через неё нельзя. Внутри `pcall` это приходит как `false` и текст ошибки, а всё после ожидания не выполняется. Ожидание ставят вне `pcall`, и `pcall` оборачивает только работу между ожиданиями.

Источник: lua-lang:src/ldo.c#attempt to yield across metamethod/C-call boundary
Источник: fa:lua/userInit.lua#WaitFrames = coroutine.yield

### `SCR_LuaDoFileConcat: Loading "..." failed`: файл не скомпилировался

В логе это `WARNING: SCR_LuaDoFileConcat: Loading "<файл>" failed: <причина>`, и только здесь видны файл, строка и причина. `import` после этого не бросает ошибку и отдаёт пустой модуль, поэтому следующая ошибка в логе обычно указывает на другой файл. Если мод загрузился, но молчит, эту строку ищут первой.

Источник: fa:lua/sim/Profiler.lua#there's likely a 'WARNING: SCR_LuaDoFileConcat' right above me

### `Expected a game object. (Did you call with '.' instead of ':'?)`

Метод движка получил первым аргументом не объект, обычно из-за точки вместо двоеточия: `control.EnableHitTest(true)`. Рядом в движке лежат `Game object has been destroyed` и `Incorrect type of game object.`: объект уже уничтожен или это объект другого класса.

Наблюдение: все три текста найдены поиском строк в bin/ForgedAlliance.exe, в Lua-исходниках их нет; смысл двух последних выведен из их текста.

### `access to nonexistent global variable "X"`

Прочитано имя, которого нет ни в таблице модуля, ни в `_G`: у `_G` стоит `__index`, вызывающий `error()`. То же сообщение даёт чтение отсутствующего поля модуля (`Mod.Start`), и тогда X это имя поля, а причина часто в другом файле, который не скомпилировался. На верхнем уровне файла такая ошибка прерывает его загрузку.

Источник: fa:lua/system/config.lua#error("access to nonexistent global variable " .. repr(key), 2)

### ``unexpected symbol near `X'``

Парсер встретил токен, с которого не начинается ни выражение, ни оператор. При `#` номер строки указывает на следующую строку: `#` начал комментарий, поэтому `local n = #t` и `local x = 1` под ней дают ошибку ``near `local'`` на второй строке. При `%` после законченного выражения, как в `local b = a % 2`, ошибка стоит на той же строке.

Источник: lua-lang:src/lparser.c#luaX_syntaxerror(ls, "unexpected symbol");

### `` `then' expected near `%' ``

Оператора `%` нет, поэтому в `if a % 2 == 0 then` парсер ждёт `then`, а видит `%`, и ошибка стоит ровно на этой строке. В других местах тот же `%` даёт другой текст: ``<eof> expected near `%'`` после `return a % 2`.

Источник: lua-lang:src/lparser.c#"`%s' expected", luaX_token2str(ls, token)));

### `attempt to index ... (a nil value)`

Поле берут у `nil`: объект не создан или функция вернула пусто. Текст называет, что было `nil`: ``local `a'`` или ``field `x'``, а для upvalue имени нет, и сообщение короче. Искать надо, откуда пришло значение, а не править саму строку.

Источник: lua-lang:src/ldebug.c#luaG_runerror(L, "attempt to %s a %s value", op, t);

### `attempt to call a table value`

Вызвана таблица без `__call`, и у выражения нет имени: например upvalue или результат другого вызова. Если имя известно, текст другой: ``attempt to call field `f' (a table value)``.

Источник: lua-lang:src/ldebug.c#luaG_runerror(L, "attempt to %s a %s value", op, t);

### ``attempt to call method `X' (a nil value)``

У объекта нет такого метода; для поля и глобала вместо `method` стоит `field` или `global`. Типичный случай в интерфейсе: метод симуляции у `UserUnit`, например `AddUnitCallback`, который есть только у `Unit` в sim-слое. Другой случай: `Bind` у результата `Opt()` в UMT.

Источник: fa:lua/sim/Unit.lua#AddUnitCallback = function(self, fn, type)

### ``attempt to call method `X' (a table value)``

Вызвана таблица без `__call`; бывает и ``field `X'``. В тестах на заглушках это обычно `Left` или `Width`: у настоящего контрола там LazyVar, он и вызывается (`c.Left()`), и задаётся (`c.Left:Set(v)`), а таблица с одним `Set` падает.

Источник: fa:lua/lazyvar.lua#__call = function(self)

### `attempt to perform arithmetic on a nil value`

В таком виде, без имени, сообщение выходит для upvalue. Обычно имя есть: ``on local `x'``, ``on field `x'``, а для числового индекса `t[3]` пишется ``field `?'``. Настоящий пример: ``attempt to perform arithmetic on field `huge' (a nil value)``, потому что `math.huge` в игре равен `nil`.

Источник: fa:lua/sim/Projectile.lua#Since `math.huge` does not exist

### `too many upvalues (limit=32)`

Ошибка компиляции, в логе она стоит внутри строки `SCR_LuaDoFileConcat`; полный вид ``<файл>:<строка>: too many upvalues (limit=32) near `end'``. Строка показывает, где парсер встретил 33-е внешнее имя, а не начало функции. Таблица считается одним upvalue, поэтому константы и состояние складывают в таблицы.

Источник: lua-lang:src/llex.c#msg = luaO_pushfstring(ls->L, "too many %s (limit=%d)", msg, limit);

### `Error importing '<путь>'`

`import` бросает это, когда `doscript` файла завершился ошибкой: файла нет или ошибка случилась при выполнении верхнего уровня файла. Настоящая причина напечатана строкой выше через `WARN`. Ошибка компиляции сюда не попадает, её показывает `SCR_LuaDoFileConcat`.

Источник: fa:lua/system/import.lua#error("Error importing '" .. name .. "'", 2)

### `Unable to interrupt path finding`

Это не ошибка движка, а `print` из sim-колбэка `AbortNavigation`, и печатается он только у армии, отдавшей приказ. Причин три: в выделении не осталось своих юнитов, в нём нет `ENGINEER` или `COMMAND`, либо прошлый вызов от этого источника был не больше 5 тиков назад. Значит, вызов проходит не чаще раза в 6 тиков.

Источник: fa:lua/SimCallbacks.lua#if commandSourceGuard and commandSourceGuard + 5 >= gameTick then

### `MODULE FAILED TO LOAD`

Не сообщение движка: эту строку пишут хуки `gamemain.lua` наших модов, когда `import` не удался или нет точки входа. Рядом стоит `Reason:`, а настоящая причина лежит выше в логе, в `SCR_LuaDoFileConcat` или в `WARN` перед `Error importing`.

Наблюдение: строка есть только в hook/lua/ui/game/gamemain.lua модов из My_mods, поиск по references/fa её не находит.

### Пишется ли в лог ошибка внутри потока `ForkThread`

В `bin/ForgedAlliance.exe` есть строки `Error running lua script: %s` и `Error running lua script from destroyed thread: %s`, поэтому утверждать, что поток умирает без следа в логе, нельзя. Цикл в упавшем потоке после ошибки не работает, так что тело цикла всё равно держат под `pcall`.

Не подтверждено: нужен опыт в игре: вызвать `error()` внутри `ForkThread` и прочитать лог.
