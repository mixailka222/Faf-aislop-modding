# Отладка

Логи, сообщения движка и как их читать.

### `access to nonexistent global variable "X"`

Прочитано имя, которого нет ни в таблице модуля, ни в `_G`: таблица модуля читает через `__index = _G`, а у `_G` стоит `__index`, вызывающий `error()`. Поэтому результат не `nil`: и `X == nil`, и `type(module.X)`, и `if Mod.Name then` падают на отсутствующем имени. То же сообщение даёт чтение отсутствующего поля модуля (`Mod.Start`), и тогда X это имя поля, а причина часто в другом файле, который не скомпилировался. На верхнем уровне файла такая ошибка прерывает его загрузку и отключает модуль, в работающем коде обрывает только текущий вызов. Внутри `pcall` такая ошибка не видна, и проверка вида `pcall(function() return Name() end)` просто молча не срабатывает. Наличие проверяют через `rawget(_G, 'X')` или `rawget(Mod, 'X')`, так делает сама игра. Для модуля сначала проверяют `type(Mod) == 'table'`, потому что `rawget` принимает только таблицу.

Источник: fa:lua/system/config.lua#error("access to nonexistent global variable " .. repr(key), 2)
Источник: fa:lua/system/import.lua#__index = _G
Источник: fa:lua/system/import.lua#__module_metatable = {
Источник: fa:lua/simInit.lua#if rawget(_G, "SetNavigatorPersonalPosMaxDistance") then

### `SCR_LuaDoFileConcat: Loading "..." failed`: файл не скомпилировался

В логе это `WARNING: SCR_LuaDoFileConcat: Loading "<файл>" failed: <причина>`, и только здесь видны файл, строка и причина. `doscript` завершается без ошибки, поэтому `import` её не бросает: `pcall(import, path)` возвращает `true` и пустой модуль. Чтение его поля вне `pcall` падает, и виновным в логе выглядит файл, который читает это поле: следующая ошибка обычно указывает на другой файл. В хуке `gamemain.lua` это ломает загрузку самого `gamemain.lua`, поэтому в хуке точку входа читают только через `rawget`. Если мод загрузился, но молчит, эту строку ищут первой.

Источник: fa:lua/sim/Profiler.lua#this doesn't catch any errors inside `doscript`, only explicit Lua errors
Источник: fa:lua/sim/Profiler.lua#there's likely a 'WARNING: SCR_LuaDoFileConcat' right above me

### `Error importing '<путь>'`

`import` бросает это, когда `doscript` файла завершился ошибкой: файла нет или ошибка случилась при выполнении верхнего уровня файла. Модуль при этом убирается из реестра. Настоящая причина напечатана строкой `WARN` прямо перед этой ошибкой. Ошибка компиляции сюда не попадает, её показывает `SCR_LuaDoFileConcat`.

Источник: fa:lua/system/import.lua#error("Error importing '" .. name .. "'", 2)

### `attempt to yield across metamethod/C-call boundary`: ожидание внутри `pcall`

`WaitSeconds`, `WaitTicks`, `WaitFrames` это `coroutine.yield`, а `pcall`, `xpcall`, метаметоды, компаратор `table.sort`, колбэк `string.gsub` и другие колбэки C-функций работают через C-границу, и передать управление через неё нельзя. Внутри `pcall` это приходит как `false` и текст ошибки: код после ожидания не выполнится, а поток продолжит работу после `pcall` без ожидания. Цикл с таким ожиданием крутится без пауз. Ожидание ставят вне `pcall`, и `pcall` оборачивает только работу между ожиданиями.

Источник: lua-lang:src/ldo.c#attempt to yield across metamethod/C-call boundary
Источник: fa:lua/userInit.lua#WaitFrames = coroutine.yield
Наблюдение: проверено запуском в `.tools/faf-lua/lua.exe`.

### `ForkThread` внутри `pcall` безопасен

Новый поток это отдельная корутина, её ожидания через `pcall` не проходят.

Источник: fa:engine/Core.lua#function ForkThread(callback, ...)

### Ждать можно только в потоке

`CreateUI`, beat-функции и колбэки синхронизации потоками не являются, ожидание запускают через `ForkThread`.

Источник: fa:lua/userInit.lua#WaitFrames = coroutine.yield

### `Expected a game object. (Did you call with '.' instead of ':'?)`

Метод движка получил первым аргументом не объект, обычно из-за точки вместо двоеточия: `control.EnableHitTest(true)`. Компилятор такое не ловит, ошибка возникает в момент вызова. Рядом в движке лежат `Game object has been destroyed` и `Incorrect type of game object.`: объект уже уничтожен или это объект другого класса.

Наблюдение: строка `Expected a game object. (Did you call with '.' instead of ':'?)` есть в `ForgedAlliance.exe`, в логе она появилась при `control.EnableHitTest(true)`.
Наблюдение: все три текста найдены поиском строк в bin/ForgedAlliance.exe, в Lua-исходниках их нет; смысл двух последних выведен из их текста.

### Имена локальных переменных не ограничены

Подходит любое имя, кроме ключевых слов. `local line`, `count`, `name`, `key`, `index`, `value` встречаются в коде игры сотни раз. `local type` и `local next` скрывают встроенные функции только в своей области, как в обычном Lua.

Источник: fa:lua/ui/game/score.lua#local line = {}

### Где лежит лог

`%APPDATA%\Forged Alliance Forever\logs\`: `game_<id>.log` для матчей, по одному на партию, и `replay_<id>.log` для реплеев. Метка уровня в файле пишется строчными буквами, например `info:`, поэтому поиск ведут без учёта регистра.

Наблюдение: содержимое папки логов на компьютере разработчика.
Наблюдение: путь взят из команды запуска игры в файле краша, клиент FAF.

### Лог пишется на диск по ходу матча

Файл отстаёт от игры на секунды, поэтому его можно читать, не закрывая игру. Самый свежий по дате файл может относиться к прошлой сессии.

Наблюдение: процесс игры завершён извне на 150-й секунде запуска, последней строкой файла осталась `Session time: 00:02:27`.

### Архивы `.nx2` открываются обычным zip

Стандартный `zipfile` из Python читает `lua.nx2` и `units.nx2`, проверка целостности проходит. В `lua.nx2` лежит весь игровой Lua.

Наблюдение: `zipfile.ZipFile` и `testzip()` на файлах из `C:\ProgramData\faforever\gamedata`.

### `table.getn` считает только ключи подряд от 1

На таблице с ключами EntityId он вернёт 0, даже если записи есть. Такие таблицы считают обходом `pairs` или через `table.getsize`.

Источник: lua-lang:src/lib/lauxlib.c#for (n = 1; ; n++) {  /* else must count elements */

### Дефис в шаблоне Lua это ленивый квантификатор

`string.find(s, 'release-in')` не находит текст `release-in`: шаблон читается как `releas`, ноль или больше `e`, затем `in`. Дефис экранируют (`'release%-in'`) или ищут подстроку через `string.find(s, 'release-in', 1, true)`.

Источник: lua-lang:src/lib/lstrlib.c#case '-': {  /* 0 or more repetitions (minimum) */

### Вызов локальной функции до её объявления падает как обращение к глобалу

Локальное имя видно только ниже объявления, выше оно компилируется как глобальное. В файле мода это даёт `access to nonexistent global variable "Имя"`, а не `attempt to call`.

Источник: fa:lua/system/config.lua#error("access to nonexistent global variable " .. repr(key), 2)

### `too many upvalues (limit=32)`

Ошибка компиляции: файл не компилируется, в логе она стоит внутри строки `SCR_LuaDoFileConcat`. Текст ошибки: ``too many upvalues (limit=32) near `end'``, расположение указано в формате лога игры или `luac`, см. «Формат ошибок Lua в логе игры». Строка относится к обращению функции к 33-й внешней переменной, где её встретил парсер, а не к её объявлению и не к началу функции. Таблица считается одним upvalue, поэтому константы и состояние складывают в таблицы.

Источник: lua-lang:src/lparser.c#luaX_checklimit(fs->ls, f->nups + 1, MAXUPVALUES, "upvalues");
Источник: lua-lang:src/llex.c#msg = luaO_pushfstring(ls->L, "too many %s (limit=%d)", msg, limit);

### Ошибка внутри `ForkThread` попадает в лог

Вне `pcall` поток обрывается, а в логе появляется `warning: Error running lua script: <файл>(<строка>): <текст>` и стек. Цикл в упавшем потоке после ошибки не работает, поэтому тело долгого цикла всё равно кладут в `pcall`, а `WaitSeconds` оставляют снаружи.

Наблюдение: `ForkThread(function() error('x') end)` в интерфейсе матча, строка и стек прочитаны в логе.

### LuaLS: ложное `undefined-global` на вызове сразу после `..`

Плагин FAF для LuaLS может считать необъявленным глобал файла, если он вызван сразу после оператора `..`. Такой вызов работает в игре. Замечание подавляется строкой `---@diagnostic disable-next-line: undefined-global` с причиной рядом.

Наблюдение: в `My_mods/overflow/Overflow/modules/themes.lua` функция `FrameCurrent` объявлена в этом же файле. LuaLS принимал вызов `ByLabel(FRAMES, FrameCurrent())`, но отмечал `'|' .. FrameCurrent()`.

### Строки лога о клавишах показывают шаг поломки

`SetUserKeyMapping` пишет `Keybindings adding key`, а `GetKeyMappings` при незнакомом действии пишет `Keybindings cannot find action`. Так отличают незаписанную привязку от незарегистрированного действия.

Источник: fa:lua/keymap/keymapper.lua#WARN('Keybindings cannot find action "' .. action .. '" for key ' .. key)

### Функции лога глобальные

`LOG`, `WARN` и `SPEW` доступны без импорта. Аннотации всех трёх предупреждают, что они не для рабочего кода.

Источник: fa:engine/Core.lua#--- Prints a debug message to the moholog, this shouldn't be used in production code

### Команда чата /debug-log есть только с ключом /debug

Без ключа запуска `/debug` команда не регистрируется. Она выполняет `WIN_ToggleLogDialog`.

Источник: fa:lua/ui/game/chat/commands/builtin/DebugLog.lua#return HasCommandLineArg('/debug')

### Окно лога привязано к отладочной клавише

В стандартной раскладке это `F9`, в раскладке hotbuild `Ctrl-F9`, действие `debug_toggle_log_window`.

Источник: fa:lua/keymap/defaultKeyMap.lua#= 'debug_toggle_log_window',

### Формат ошибок Lua в логе игры

В логе игры ошибка выглядит как `файл(строка): сообщение near `токен'`. Локальные `lua.exe` и `luac.exe` пишут иначе: `файл:строка: сообщение`.

Наблюдение: логи FAF с ошибками модов, например `ui.lua(418): too many upvalues (limit=32) near `,'`. Локальный формат проверен запуском `.tools/faf-lua`.

### pcall возвращает все значения функции

`local ok, a, b = pcall(fn)` даёт оба результата `fn`.

Наблюдение: проверено запуском в `.tools/faf-lua/lua.exe`.

### Имена в сообщениях Lua стоят в кавычках `` `x' ``

Движок печатает имя между обратным апострофом и прямым: ``attempt to call method `Foo' (a nil value)``. Искать в логе надо именно такой вид, а не `'Foo'`.

Источник: lua-lang:src/ldebug.c#luaG_runerror(L, "attempt to %s %s `%s' (a %s value)",

### ``unexpected symbol near `X'``

Парсер встретил токен, с которого не начинается ни выражение, ни оператор. При `#` номер строки указывает на следующую строку: `#` начал комментарий, поэтому `local n = #t` и `local x = 1` под ней дают ошибку ``near `local'`` на второй строке. При `%` после законченного выражения, как в `local b = a % 2`, ошибка стоит на той же строке.

Источник: lua-lang:src/lparser.c#luaX_syntaxerror(ls, "unexpected symbol");

### `` `then' expected near `%' ``

Оператора `%` нет, поэтому в `if a % 2 == 0 then` парсер ждёт `then`, а видит `%`, и ошибка стоит ровно на этой строке. В других местах тот же `%` даёт другой текст: ``<eof> expected near `%'`` после `return a % 2`.

Источник: lua-lang:src/lparser.c#"`%s' expected", luaX_token2str(ls, token)));

### `attempt to index ... (a nil value)` пишет только локальный Lua

В игре чтение поля у `nil` ошибки не даёт и возвращает `nil`, см. `dialect.md`. Эту строку выводит `.tools/faf-lua/lua.exe`, и там искать надо, откуда пришло значение. В игре пустое значение проявляется позже и в другом месте: ``attempt to call method `X'``, ``attempt to perform arithmetic`` или ``Attempt to set attribute 'x' on nil``.

Источник: lua-lang:src/ldebug.c#luaG_runerror(L, "attempt to %s a %s value", op, t);
Наблюдение: поиск по папке логов FAF на компьютере разработчика эту строку не нашёл, замер чтения описан в `dialect.md`.

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

### `Unable to interrupt path finding`

Это не ошибка движка, а `print` из sim-колбэка `AbortNavigation`, и печатается он только у армии, отдавшей приказ. Причин три: в выделении не осталось своих юнитов, в нём нет `ENGINEER` или `COMMAND`, либо прошлый вызов от этого источника был не больше 5 тиков назад. Принятый вызов печатает `Interrupted pathfinding for N unit(s)`.

Источник: fa:lua/SimCallbacks.lua#if commandSourceGuard and commandSourceGuard + 5 >= gameTick then

### `MODULE FAILED TO LOAD`

Не сообщение движка: эту строку пишут хуки `gamemain.lua` наших модов, когда `import` не удался или нет точки входа. Рядом стоит `Reason:`, а настоящая причина лежит выше в логе, в `SCR_LuaDoFileConcat` или в `WARN` перед `Error importing`.

Наблюдение: строка есть только в hook/lua/ui/game/gamemain.lua модов из My_mods, поиск по references/fa её не находит.

### Матч запускается из командной строки

`ForgedAlliance.exe /map SCMP_009` сразу начинает матч, без клиента FAF и лобби. Без `/noAi` остальные армии занимает ИИ. Фракцию задаёт `/faction`: `/seed` её не фиксирует. Размер окна задаёт `/windowed 1024 768`. Режим победы по умолчанию `sandbox`.

Источник: fa:lua/SinglePlayerLaunch.lua#Called by the engine using the `/map <mapPath>` launch arg
Источник: fa:lua/SinglePlayerLaunch.lua#if not HasCommandLineArg("/noAi") then
Источник: https://wiki.faforever.com/en/Development/Game-Development/Command-Line-Switches
Наблюдение: запуск с этими ключами; при одном `/seed 1` командиры в разных запусках были разных фракций.

### `/init` принимает файл вне папки `bin`

Подходит абсолютный путь. Движок ставит `InitFileDir` на папку этого файла, а штатный init ищет от неё `fa_path.lua` и `gamedata`. Поэтому свой init сначала возвращает значение, затем выполняет штатный файл и дописывает моды в `path`:

```lua
InitFileDir = 'C:/ProgramData/FAForever/bin'
dofile(InitFileDir .. '/init.lua')
table.insert(path, { dir = '<путь к моду>', mountpoint = '/mods/имя' })
```

Так мод подключается из своей папки, без копирования в игру или в хранилище модов.

Источник: fa:init_faf.lua#dofile(InitFileDir .. '/../fa_path.lua')
Наблюдение: запуск с таким init из временной папки, в логе `DISK: AddSearchPath` с папкой мода и `Hooked` с его хуками.

### `/prefs` считает путь от папки настроек игры

Значение приклеивается к `%LOCALAPPDATA%\Gas Powered Games\Supreme Commander Forged Alliance\`. С абсолютным путём игра пишет `Unable to open preference file` и работает на пустых настройках, поэтому моды из файла не включаются. Работает относительный путь вида `..\..\Temp\папка\Game.prefs`. Файл только с таблицей `active_mods` игра считает устаревшим: переименовывает его в `Game.prefs.bad` и создаёт настройки по умолчанию. Достаточно добавить `profile` с одним профилем и `version = { major = 1 }`. Основной `Game.prefs` при этом не меняется.

Источник: https://wiki.faforever.com/en/Development/Game-Development/Command-Line-Switches
Наблюдение: запуски с абсолютным путём, с файлом из одной `active_mods` и с таким файлом; время изменения основного `Game.prefs` осталось прежним.

### `Blueprints.lua` читает настройки мимо `/prefs`

Он сам открывает `/preferences/Game.prefs`, а штатный init монтирует туда папку настроек игрока. Поэтому при `/prefs` с другим файлом `PreGameData` всё равно берётся из настроек игрока: список иконок модов приходит оттуда, и без этих модов лог получает `Unable to load icons from mod`. Чтобы отделить запуск от настроек игрока, в своём init меняют `dir` у записи `path` с `mountpoint = '/preferences'`.

Источник: fa:lua/system/Blueprints.lua#local file = DiskFindFiles("/preferences", "Game.prefs")[1]
Наблюдение: запуск с временным `/prefs` дал эти строки в логе, после замены `dir` они исчезли.

### Матч через `/map` сохраняет реплей

Файл `LastGame.SCFAReplay` ложится в `Documents\My Games\Gas Powered Games\Supreme Commander Forged Alliance\replays\<профиль>\`. Папка создаётся, если её не было.

Источник: fa:lua/SinglePlayerLaunch.lua#sessionInfo.createReplay = true
Наблюдение: строка `Saving replay to` в логе запуска и файл на этом пути.

### Время в матче через `/map` идёт неравномерно

`WaitSeconds` в интерфейсе не равен десяти тикам симуляции на секунду, и отношение меняется по ходу матча. Сценарий, которому важен порядок событий, считает сами события: проверка «за 3 секунды» здесь случайно проходила на сломанном коде.

Наблюдение: за `WaitSeconds(10)` прошло 167 тиков, а 16 проходов цикла мода с `WaitSeconds(1)` заняли 213 тиков.

### `SimLua` отвергается в матче через `/map`

`SessionGetScenarioInfo().Options.CheatsEnabled` там равно `'true'`, но `ConExecute('SimLua ...')` не выполняется, а в логе появляется `<игрок> is trying to cheat!`. Действия в sim в таком матче делают своим обработчиком: мод с `ui_only = false` хукает `/lua/SimCallbacks.lua`, а обработчик вызывают через `SimCallback`.

Источник: fa:lua/SinglePlayerLaunch.lua#CheatsEnabled = 'true',
Наблюдение: запуск с `SimLua`, затем с таким модом: обработчик создал юнитов и выдал им приказы.
