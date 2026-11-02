# Настройки

`Prefs`, профили и страницы настроек.

### Ключ с точкой в `SetToCurrentProfile` потом не читается

`SetToCurrentProfile` пишет `fieldName` как один плоский ключ таблицы, а `GetFromCurrentProfile` собирает из него путь для `GetPreference` и разбирает его по уровням. Запись `'mymod.pos'` создаёт плоский ключ, а чтение ищет узел `mymod` и возвращает `nil`. Имя поля профиля пишут без точек.

```lua
Prefs.SetToCurrentProfile('MyMod', { panelX = 10 })
local saved = Prefs.GetFromCurrentProfile('MyMod')
```

Источник: fa:lua/user/prefs.lua#profile.profiles[profile.current][fieldName] = data
Источник: fa:lua/user/prefs.lua#return GetPreference('profile.profiles.' .. current .. '.' .. fieldName)

### Чтение с точкой это штатный доступ к вложенному полю

`GetFromCurrentProfile` читает вложенное поле по точкам, и для настоящей вложенности это работает: `GetFromCurrentProfile('options.repeatbuild')` читает поле `repeatbuild` таблицы `options`. Игра делает так постоянно.

Источник: fa:lua/ui/game/gamemain.lua#Prefs.GetFromCurrentProfile('options.repeatbuild')
Источник: fa:lua/user/prefs.lua#return GetPreference('profile.profiles.' .. current .. '.' .. fieldName)

### `SetPreference` с точками пишет вложенно

В отличие от `SetToCurrentProfile`, движковая функция сама разбирает путь.

Источник: fa:lua/ui/dialogs/profile.lua#SetPreference("profile.current", row + 1)

### Точки в ключах внутри сохраняемой таблицы безопасны

Такие ключи сохраняются как есть и читаются обычным индексом таблицы.

Наблюдение: `Game.prefs` содержит в профиле таблицу мода с ключами вида `['title.font.quality']`.

### Настройки попадают на диск при выходе из игры

До этого они живут в памяти. `SavePreferences()` вызывать не нужно. Если игра упала, несохранённые изменения теряются.

Источник: fa:engine/User.lua#--- Updates a value in the preference file. Updating the preference file on disk is delayed until the application exits.

### `GetPreference` возвращает глубокую копию

Вызов дорогой, на каждом тике его не делают. Изменение копии в настройки не попадает. `SetToCurrentProfile` при каждом вызове читает и пишет всю таблицу `profile`, поэтому на каждое движение мыши его не вызывают, сохраняют при отпускании.

Источник: fa:engine/User.lua#The value retrieved is a deep copy of what resides in the actual

### Без текущего профиля запись тихо пропадает

`SetToCurrentProfile` ничего не делает и не сообщает об ошибке, поэтому `pcall` этого не поймает. `GetFromCurrentProfile` возвращает `nil`.

Источник: fa:lua/user/prefs.lua#if profile.profiles[profile.current] then
Источник: fa:lua/user/prefs.lua#if profile.current then

### `:Set` внутри обработчика снова вызывает `OnChange`

Запись N полей из обработчика `Bind` даёт N вложенных вызовов. От этого защищаются флагом, который обязательно снимают после записи.

Источник: ui-libs:mods/UMT/modules/OptionVar.lua#self._lv:Set(value)

### Окно UMT сохраняет все OptionVar своей страницы

`SaveOptions` обходит `_optionVars`, куда попадает каждая строка с `optionVar`. Служебное поле тоже окажется в профиле.

Источник: ui-libs:mods/UMT/modules/OptionsWindow.lua#self._optionVars[option] = data.optionVar

### Значение по умолчанию не может быть `nil`

`Create` бросает ошибку только на `nil`, поэтому `Opt(false)` допустим.

Источник: ui-libs:mods/UMT/modules/OptionVar.lua#if default == nil then

### Вместо таблицы элементов можно передать функцию

`AddOptions(имя, заголовок, fn)` работает: при открытии страницы UMT вызывает `fn(parent:GetRootFrame())` и считает результат окном страницы. Так можно сделать своё окно, например с кнопкой.

Источник: ui-libs:mods/UMT/modules/Options.lua#if iscallable(self.data[2]) then

### Позицию панели хранят в базовых единицах

При чтении её снова умножит `LayoutHelpers.AtLeftTopIn`, поэтому панель стоит верно при любом `ui_scale`.

```lua
Prefs.SetToCurrentProfile('MyPanelPos', { left = LayoutHelpers.InvScaleNumber(self.Left()) })
```

Источник: fa:lua/ui/game/massfabs.lua#left = LayoutHelpers.InvScaleNumber(self.Left())

### Класс Window хранит координаты и размер в разных единицах

`top`, `left`, `right`, `bottom` записаны в экранных пикселях, `width` и `height` в базовых единицах. При чтении окно ограничивается рамкой родителя.

Источник: fa:lua/maui/window.lua#width = LayoutHelpers.InvScaleNumber(self.Width()),

### Где лежит Game.prefs

Папка `%LOCALAPPDATA%\Gas Powered Games\Supreme Commander Forged Alliance\` монтируется как `/preferences`.

Источник: fa:init_faf.lua#MountDirectory(SHGetFolderPath('LOCAL_APPDATA') .. 'Gas Powered Games/Supreme Commander Forged Alliance', '/preferences')

### Game.prefs это Lua-скрипт

Игра сама выполняет его через `doscript`. По наличию ключа в файле видно, сработала ли запись.

Источник: fa:lua/system/Blueprints.lua#doscript(file, data)

### UMT подхватывает мод только с `__umt` и `ui_only`

В `mod_info.lua` нужны оба поля: `__umt = true` и `ui_only = true`. Имя для дальнейшего поиска берётся из папки мода, а в логе появляется `UML: added <папка>`.

Источник: ui-libs:mods/UMT/hook/lua/ui/game/gamemain.lua#| UMT.LuaQ.where(function(v) return v.__umt and v.ui_only end)

### UMT вызывает `Main` только у мода с файлом `Main.lua`

После `CreateUI` игры UMT ищет `Main.lua` в папке мода со всеми подпапками и зовёт `import(file).Main(isReplay)` без `pcall`. Ошибка там уходит в построение интерфейса, прерывает `CreateGameInterface` и даёт чёрный экран при входе в матч, поэтому тело `Main` держат под `pcall` и пишут ошибку в лог. Без этого файла мод работает, лог чистый, а страницы настроек нет.

Источник: ui-libs:mods/UMT/modules/Mods.lua#local files = DiskFindFiles("/mods/" .. mod .. "/", 'Main.lua')
Источник: ui-libs:mods/UMT/modules/Mods.lua#import(file).Main(isReplay)
Источник: ui-libs:mods/UMT/hook/lua/ui/game/gamemain.lua#UMT.Mods.Load(isReplay)

### Поиск `Main.lua` и `Options.lua` не зависит от регистра

UMT находит и `modules/main.lua`, а пути в логе идут строчными, например `/mods/ase/modules/main.lua`.

Наблюдение: строка `UMT: Loading file /mods/ase/modules/main.lua` в логе матча с модами UMT и ASE.

### `Options.lua` грузится только при чтении `UMT.Options.Mods["Имя"]`

Чтение отсутствующего ключа срабатывает через `__index`: если полей ещё нет, UMT ищет `Options.lua` в папке `/mods/Имя/` и вызывает его `Main()`. Если страница не появилась, `__index` бросает ошибку `No options for mod`, а `nil` не возвращается никогда. Обычно это чтение делает `Main.lua`, но объявить страницу можно и прямо в нём.

Источник: ui-libs:mods/UMT/modules/Options.lua#local function LoadOptionsFile(modsOptions, modName)
Источник: ui-libs:mods/UMT/modules/Options.lua#ErrorF("No options for mod '%s'", key)

### Настройки UMT объявляются присваиванием

`UMT.Options.Mods["Имя"] = { поле = Opt(значение) }` создаёт `OptionVar` на каждое поле. `Opt` принимает один аргумент и только помечает значение по умолчанию, методов у него нет. `Bind` есть только у `OptionVar`, поэтому объект читают обратно из `UMT.Options.Mods["Имя"]`. Окно описывается вызовом `AddOptions(option, title, buildTable)`.

Источник: ui-libs:mods/UMT/modules/Options.lua#function Opt(value)

### Методы `OptionVar`

`opt()` читает живое значение. `__call` не принимает аргументов, поэтому `opt(5)` молча вернёт текущее значение и ничего не запишет. `opt:Set(v)` меняет значение в памяти и вызывает `OnChange`, `opt:Save()` пишет в профиль, `opt:Reset()` откатывает. `opt:Bind(fn)` запоминает `fn` как `OnChange` и тут же вызывает `self:OnChange()`, поэтому первый аргумент `fn` это сам `OptionVar`, а код в функции должен работать ещё до старта мода.

Источник: ui-libs:mods/UMT/modules/OptionVar.lua#function OptionVarMetaTable:Bind(fn)
Источник: ui-libs:mods/UMT/modules/OptionVar.lua#function OptionVarMetaTable:__call()
Источник: ui-libs:mods/UMT/modules/OptionVar.lua#---@param fn fun(opt: OptionVar)

### Профиль обновляется только по кнопке OK

`:Set` меняет значение только в памяти. В профиль пишет `:Save()`, а окно вызывает его только по кнопке OK, у всех `OptionVar` окна. Cancel и закрытие откатывают значения через `Reset`, и `OnChange` срабатывает снова. Пока окно открыто, в профиле старые значения, поэтому мод должен читать живое значение `opt()`, а не `Prefs`.

Источник: ui-libs:mods/UMT/modules/OptionsWindow.lua#SaveOptions = function(self)
Источник: ui-libs:mods/UMT/modules/OptionsWindow.lua#self:OnClose(true)

### Значение из `OptionVar:Set` откатывает кнопка Cancel

`Set` запоминает прежнее значение, а Cancel зовёт `Reset` у всех полей страницы, даже если значение менялось не из окна. Мод, который меняет настройку мимо окна, например по хоткею, пишет через `option:Raw():Set(value)`: прежнее значение тогда не запоминается и `OnChange` не вызывается. Если поле уже двигали в окне, запомненное значение остаётся, и Cancel вернёт его. Стирает его `option:Save()`, заодно записывая текущее значение в профиль.

Источник: ui-libs:mods/UMT/modules/OptionVar.lua#self._prev = self._lv()
Источник: ui-libs:mods/UMT/modules/OptionVar.lua#self:Set(self._prev)
Источник: ui-libs:mods/UMT/modules/OptionVar.lua#self._prev = nil

### `OptionVar` читает профиль один раз при создании

Значение берётся при создании, и там же значение по умолчанию записывается в профиль. Запись в `Prefs` в обход `OptionVar` окно не увидит, а старое значение из `OptionVar` вернётся в профиль при следующем `:Save()`, поэтому кнопка OK её затрёт. Если мод меняет значения окна из своего кода, он пишет в `OptionVar` через `option:Raw():Set(value)`, а не только в `Prefs`.

Источник: ui-libs:mods/UMT/modules/OptionVar.lua#local val = modOptionsTable and modOptionsTable[subOption]

### Ключ профиля UMT это имя из `Mods["Имя"]`

`OptionVar` хранит все поля мода одной таблицей в профиле под этим именем: `:Save()` пишет `Prefs[имя мода][поле]`. Поэтому мод может читать те же значения через `Prefs.GetFromCurrentProfile("Имя")`. Ключ и имена полей при этом должны совпадать с объявленными в UMT, а в имени не должно быть точек.

Источник: ui-libs:mods/UMT/modules/OptionVar.lua#local modOptionsTable = Prefs.GetFromCurrentProfile(self._m)

### Элементы окна UMT

Типов восемь: `filter`, `color`, `slider`, `colorslider`, `strings`, `edit`, `title`, `splitter`, а `column` переключает колонку. Кнопки нет. Окно открывается пунктом меню `UI mods options`.

Источник: ui-libs:mods/UMT/modules/OptionsWindow.lua#if data.type == "filter" then
Источник: ui-libs:mods/UMT/modules/Options.lua#---@field type  "splitter"|"title"|"color"|"slider"|"filter"|"edit"|"colorslider"|"strings"|"column"
Источник: ui-libs:mods/UMT/hook/lua/ui/game/tabs.lua#label = 'UI mods options',

### Галочка окна UMT не следит за значением

Вид галочки задаётся один раз при создании окна. Если код поменял значение через `:Set`, значение уже новое, но картинка обновится только при новом открытии окна.

Источник: ui-libs:mods/UMT/modules/OptionsWindow.lua#group.check:SetCheck(self:GetOption(option), true)

### Значение выпадающего списка UMT должно быть в списке

При создании списка UMT ищет текущее значение в `items`. Если его там нет, он ставит `items[1]` и сразу вызывает `Save`. Значение по умолчанию не обязано быть первым пунктом, оно обязано быть среди пунктов.

Источник: ui-libs:mods/UMT/modules/Views/StringSelector.lua#optionVar:Set(items[1])

### Ползунок UMT округляет вниз до шага

`IntegerSlider` приводит значение к `math.floor(value / шаг) * шаг`. Значение 3 при шаге 15 окно покажет как 0, поэтому значение по умолчанию должно быть кратно шагу.

Источник: fa:lua/maui/slider.lua#value = math.floor(value / self._indentValue) * self._indentValue

### Строки лога для диагностики UMT

`UML: added <папка>` значит, что мод попал в список. `UMT: Loading file <путь>` значит, что найден `Main.lua`. `Loading options of mod '<имя>'` значит, что кто-то прочитал `UMT.Options.Mods`. Первая отсутствующая строка показывает, на каком шаге цепочка оборвалась.

Источник: ui-libs:mods/UMT/modules/Options.lua#LogF("Loading options of mod '%s'", modName)
