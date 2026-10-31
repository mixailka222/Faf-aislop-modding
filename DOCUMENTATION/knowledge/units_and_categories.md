# Юниты и категории

`UserUnit`, категории, выделение, очереди приказов, Blueprint.

### Очередь приказов: в UI тип строкой, в sim числом

В UI `unit:GetCommandQueue()` даёт записи `{ type, ID, position }`, где `type` это строка, например `'Move'`. В sim запись содержит число `commandType` и координаты `x`, `y`, `z`.

Источник: fa:engine/User/UserUnit.lua#---@class UICommandInfo

### Коды приказов sim

`commandType`: `Patrol` 16, `FormPatrol` 18, `Reclaim` 19, `Script` 28, `AggressiveMove` 35, `FormAggressiveMove` 36.

Источник: fa:lua/sim/commands/shared.lua#---| "AggressiveMove"               # 35

### Кнопка атак-мува создаёт Script-пустышку

Кнопка ставит Script-задачу `AttackMove`, а колбэк sim тут же выдаёт настоящий `AggressiveMove` всем юнитам, кроме зданий. В очереди движущегося юнита после этого лежит тип `AggressiveMove`. Задача-пустышка завершается на первом тике.

Источник: fa:lua/SimCallbacks.lua#IssueAggressiveMove(allNonStructures, { x, y, z })

### `LuaParams` виден только при выдаче приказа

Поле приходит в обработчик `OnCommandIssued`. В записи UI-очереди его нет, поэтому `TaskName` по очереди не узнать.

Источник: fa:lua/ui/game/commandmode.lua#if command.LuaParams.TaskName == 'AttackMove' then

### `IsUnitState` есть только у sim-юнита

У `UserUnit` такого метода нет. Состояние `Building` или `Reclaiming` из UI так не прочитать, вызов падает с ошибкой. В UI есть `unit:IsIdle()`.

Источник: fa:engine/Sim/Unit.lua#function Unit:IsUnitState

### Выработка недостроенного здания кодом Lua не определена

`Unit.OnCreate` включает производство всем юнитам сразу, а класс генератора пуст. Строка в `OnStopBeingBuilt` у фабрикатора массы поэтому не доказывает, что до завершения стройки производства нет.

Не подтверждено: нужен замер `GetEconData().energyProduced` у генератора во время постройки.

### `SetPaused` задаёт флаг паузы явно

`SetPaused(units, true)` можно вызывать повторно. Игровая клавиша `pause_unit` вызывает его же с обратным значением `GetIsPaused`. По описанию API пауза останавливает постройку, улучшение и другие задачи, а помощников юнита не затрагивает.

Источник: fa:engine/Sim/Unit.lua#--- Assisting units are unaffected.

### `GetIsPaused` отвечает за группу, `GetIsPausedOfUnit` за один юнит

`GetIsPaused(units)` истинно, если на паузе хотя бы один юнит из списка. `GetIsPausedOfUnit(unit)` есть в движке, игра вызывает его напрямую, без проверки наличия.

Источник: fa:lua/ui/game/orders.lua#if not GetIsPausedOfUnit(silo) then

### Пауза на реклейме сохраняет цель

`OnPaused` выключает только эффекты и звук, `EntityBeingReclaimed` остаётся. Скорость реклейма на паузе равна 0 за счёт патча движка, `OnUnpaused` возвращает эффекты.

Источник: fa:lua/sim/Unit.lua#-- When paused we reclaim at a speed of 0, with thanks to:

### Пауза флагом не останавливает движение и не трогает приказ

Инженер на атак-муве под `SetPaused` продолжает идти к точке, а после снятия паузы продолжает приказ. Очередь у юнита на паузе читается, поэтому пустой ответ `GetCommandQueue()` паузой не объясняется.

Наблюдение: инженеры на атак-муве, ручная пауза и пауза от мода, несколько игр; у 20 инженеров через секунду после паузы очередь вернула `AggressiveMove`.

### `Pause` как приказ и как флаг это разные механизмы

Команда типа 33 `Pause` уходит в очередь приказов и может сработать не сразу, а `SetPaused` действует сразу. Сама игра выдаёт этот приказ только ракетным шахтам и только если они не на паузе.

Источник: fa:lua/ui/game/orders.lua#IssueUnitCommandToUnit(silo, 'Pause')

### Приказ `Pause` не годится для удержания инженера с атак-мувом

`IssueUnitCommand(units, 'Pause')` останавливает инженера, но атак-мув теряется. Повторная выдача работает как переключатель, поэтому состояние паузы расходится с тем, что ожидает вызывающий код.

Наблюдение: инженеры на атак-муве, сравнение с `SetPaused` в игре; в логе `engineers=9 nowPaused=0` при приказной паузе.

### Неверное имя команды в `IssueUnitCommand` роняет игру

То же относится к `IssueUnitCommandToUnit` и `IssueCommand`. Имя берут из списка `UserUnitCommand`.

Источник: fa:engine/User.lua#---@param command UserUnitCommand # Will crash the game if not a valid command.

### `GetCommandQueue` у завода возвращает очередь точки сбора

У остальных юнитов это очередь приказов. Запись содержит поля `type`, `ID`, `position`.

Источник: fa:engine/User/UserUnit.lua#If the unit has the `FACTORY` category, returns the rally point command queue.

### `AbortNavigation` обрывает путь и не трогает очередь

Колбэк вызывает `navigator:AbortMove()` и `RefocusAssisters()` для юнитов `ENGINEER` и `COMMAND` из выделения. Это штатное действие с горячей клавишей.

Источник: fa:lua/sim/commands/abort-navigation.lua#navigator:AbortMove()

### `AbortNavigation` принимается раз в 6 тактов на игрока

Защита от автоматизации отклоняет вызов, если с прошлого принятого прошло 5 тактов или меньше. Счётчик один на источник команд, а не на юнита, и при 10 тактах в секунду это 0.6 с игрового времени. Отказ печатает `Unable to interrupt path finding`, эта же строка выходит при пустом выделении и при выделении без инженеров. Принятый вызов печатает `Interrupted pathfinding for N unit(s)`.

Источник: fa:lua/SimCallbacks.lua#if commandSourceGuard and commandSourceGuard + 5 >= gameTick then

### Прерванный атак-мув продолжается

Приказ остаётся в очереди, поэтому инженер снова строит путь. Чтобы держать его на месте, обрыв повторяют.

Наблюдение: инженеры на атак-муве под `SetPaused`, один `AbortNavigation` на паузу; инженеры продолжили идти к точке.

### Обрыв пути даёт инженеру на патруле реклейм издалека

Сигнал окончания пути используется разными командами, поэтому у `AbortNavigation` есть побочные эффекты. На атак-муве и патруле инженер начинает реклейм с большего расстояния.

Источник: fa:lua/sim/commands/abort-navigation.lua#For engineers that are on a patrol or an attack move the engineer can start reclaiming from further away

### Дальний реклейм на патруле связан с `GuardScanRadius`

По разбору движка инженер идёт к цели по малому радиусу, а отбрасывает её только по `GuardScanRadius`, и обрыв движения оставляет его между этими границами. Черновик FAForever/fa #7326 отключает обрыв для патрульных инженеров, и с ним приём перестанет работать.

Не подтверждено: в `references` нет кода `CUnitReclaimTask`; нужен реверс движка или замер дальности. Статус PR проверять перед использованием приёма.

### Инженеры на атак-муве и патруле сами бросают реклейм при почти полном хранилище

Игра сообщает об этом только в подсказке загрузки. Числа и проверки уровня хранилища в Lua нет, условие находится в движке.

Источник: fa:lua/ui/help/loadingtips.lua#Engineers on an Attack-Move or Patrol order will stop reclaiming when your storage is nearly full

### Проп отдаёт массу и энергию

Значения берутся из `ReclaimMassMax` и `ReclaimEnergyMax` блюпринта. Что подберёт инженер на атак-муве, заранее неизвестно, поэтому автоматизация реклейма смотрит на оба ресурса.

Источник: fa:lua/sim/Prop.lua#(economy.ReclaimEnergyMax * modifier)

### Остов даёт энергию только при ненулевом `Wreckage.EnergyMult`

Без этого поля множитель равен 0. Блюпринтов юнитов в `references` нет, поэтому энергия с конкретных остовов, например электростанций, не проверена.

Источник: fa:lua/sim/Unit.lua#energy = energy * (bp.Wreckage.EnergyMult or 0)

### Координаты индексируются числами 1, 2, 3

X лежит в `[1]`, Y в `[2]`, Z в `[3]`. Пару значений сохраняют именованными полями `{ x = p[1], z = p[3] }`, потому что `{ p[1], p[3] }` кладёт Z в индекс 2.

Источник: fa:lua/sim/Prop.lua#local terrainAltitude = GetTerrainHeight(self.CachePosition[1], self.CachePosition[3])

### UserUnit отдаёт данные объекта на стороне UI

Основное: `GetEconData()`, `GetFocus()` (объект или `nil`), `GetStat(name, default)` (таблица `{Value = число}`), `GetFractionComplete()`, а также `GetWorkProgress()`, `GetShieldRatio()`, `GetFuelRatio()` от 0 до 1.

Источник: fa:engine/User/UserUnit.lua#function UserUnit:GetEconData()

### GetArmy у UserUnit считает армии с 1

Игра вычитает единицу, когда ей нужен индекс с нуля.

Источник: fa:lua/keymap/selectedinfo.lua#info.armyIndex = unit:GetArmy() - 1

### EconData содержит шесть вещественных полей

`energyProduced`, `energyRequested`, `energyConsumed`, `massProduced`, `massRequested`, `massConsumed`. Дробными значения стали благодаря патчам движка.

Источник: fa:engine/User/UserUnit.lua#-- Thanks to the following engine patches this contains floats instead of ints:

### energyProduced отражает бонус соседства

Панель под выделенным юнитом показывает это значение, поэтому видны числа с учётом соседей.

Источник: fa:lua/ui/game/unitview.lua#-- This allows us to show adjacency-affected values better.

### Учёт паузы и улучшений в energyProduced не установлен

Источник показывает только соседство.

Не подтверждено: нужно сравнить `GetEconData().energyProduced` в игре на юните с паузой и на командире с улучшением.

### Образец чтения всех данных юнита

`GetUnitRolloverInfo(unit, skipFocus)` копирует экономику, здоровье, щит, цепочку `focus`, счётчик убийств и данные силосов.

Источник: fa:lua/keymap/selectedinfo.lua#function GetUnitRolloverInfo(unit, skipFocus)

### ID юнитов в нижнем регистре

`BlueprintId` строится из имени файла через `lower`, и игра ищет по такому ключу результат `GetUnitId()`: `__blueprints[target:GetUnitId()]`. Пример `"UAL0305"` в аннотации движка не отражает этого.

Источник: fa:lua/system/Blueprints.lua#gsub(lower(bp.Source), "^.*/([^/]+)_[a-z]+%.bp$", "%1")

### В UI нет функции «все мои юниты»

Готовые списки есть только частичные: `GetSelectedUnits`, `GetIdleEngineers`, `GetIdleFactories`, `GetArmyAvatars`. Отдельный объект достаётся через `GetUnitById(id)`. Полный список собирают скрытым выделением.

Источник: fa:engine/User.lua#function GetIdleEngineers()

### Скрытое выделение целиком

`SetIgnoreSelection` это функция `gamemain.lua`, а не глобальная. `CacheAndClearCommandMode` и `RestoreCommandMode` сохраняют режим приказов игрока. `GetSelectedUnits()` при пустом выделении даёт `nil`.

```lua
CommandMode.CacheAndClearCommandMode()
GameMain.SetIgnoreSelection(true)
local old = GetSelectedUnits()
UISelectionByCategory('ALLUNITS', false, false, false, false)
local units = GetSelectedUnits() or {}
SelectUnits(old)
GameMain.SetIgnoreSelection(false)
CommandMode.RestoreCommandMode(true)
```

Источник: ui-libs:mods/UMT/modules/units.lua#CommandMode.CacheAndClearCommandMode()

### SetIgnoreSelection и Selection.Hidden одинаково глушат OnSelectionChanged

Обе проверки стоят в начале функции, поэтому `ObserveSelection` и хуки ниже них не срабатывают. Разница в режиме приказов: `SetIgnoreSelection` блокирует `EndCommandMode`, а `Hidden` запоминает режим и перезапускает его.

Источник: fa:lua/ui/game/gamemain.lua#if import("/lua/ui/game/selection.lua").IsHidden() then

### Selection.Hidden не защищён от ошибок

`Hidden` вызывает функцию без `pcall`. Ошибка внутри оставит `hidden_select = true`, и `OnSelectionChanged` перестанет работать до конца партии.

Источник: fa:lua/ui/game/selection.lua#hidden_select = true

### Внутри OnSelectionChanged GetSelectedUnits даёт nil

Это верно, когда функцию вызывает движок. Сканировать армию внутри этого обработчика нельзя.

Источник: fa:lua/ui/game/gamemain.lua#`GetSelectedUnits` always results in `nil` within this function.

### Скан армии привязан к армии в фокусе

При смене `GetFocusArmy()` кэш сбрасывают, а при значении -1 (наблюдатель) скан не делают.

Источник: ui-libs:mods/UMT/modules/units.lua#if army ~= -1 and currentTick - 10 >= prevCache then

### Пустой результат скана не означает «юнитов нет»

Такой замер отбрасывают и оставляют прошлый результат. Причина пустого ответа не установлена.

Наблюдение: партия с UI-сканом `UISelectionByCategory` и `GetSelectedUnits`, пустой список в момент достройки здания.

### Параметры UISelectionByCategory

Порядок: `expression`, `addToCurSel`, `inViewFrustum`, `nearestToMouse`, `mustBeIdle`.

Источник: fa:engine/User.lua#function UISelectionByCategory(expression, addToCurSel, inViewFrustum, nearestToMouse, mustBeIdle)

### В выражении выбора пробел и звёздочка значат пересечение

Игра пишет и `"RESEARCH UEF"`, и `"FACTORY * AIR"`.

Источник: fa:lua/keymap/misckeyactions.lua#local categoryFilter = "FACTORY * " .. factoryType

### Плюс в выражении UISelectionByCategory неоднозначен

Игра вызывает `UISelectionByCategory("AIR + MOBILE", ...)`, а затем отсеивает только транспорт. По такому коду нельзя понять, означает ли `+` объединение.

Не подтверждено: нужен запуск в игре со сравнением результата для `"AIR + MOBILE"` и `"AIR MOBILE"`.

### Консольная команда UI_SelectByCategory принимает флаги и запятую

Флаги идут перед категориями: `+nearest`, `+idle`, `+inview`, `+goto`, `+excludeengineers`. Запятая разделяет альтернативы. Результат читают сразу: `ConExecute(...)`, затем `GetSelectedUnits()`.

Источник: fa:lua/keymap/keyactions.lua#UI_SelectByCategory INTELLIGENCE STRUCTURE RADAR, INTELLIGENCE STRUCTURE OMNI

### Операции над категориями

`*` пересечение, `+` объединение, `-` разность. Работают с объектами `categories.X`.

Источник: fa:engine/Core/EntityCategory.lua#--- Return the intersection between two categories

### Способы проверить категорию

`unit:IsInCategory('NAME')` принимает строку. `EntityCategoryContains(cat, unit)` и `EntityCategoryFilterDown(cat, units)` принимают объект категории. `EntityCategoryGetUnitList(cat)` возвращает ID блюпринтов.

Источник: fa:engine/Core.lua#function EntityCategoryGetUnitList(category)

### Полный список категорий лежит в аннотации движка

Комментарии к именам объясняют смысл части категорий.

Источник: fa:engine/Core/Categories.lua#HYDROCARBON = categoryValue

### Автоматические поля блюпринта

Игра заполняет `CategoriesHash`, `TechCategory`, `LayerCategory`, `FactionCategory`. В `CategoriesHash` лежит ещё и сам `BlueprintId`.

Источник: fa:lua/system/Blueprints.lua#bp.FactionCategory = string.upper(bp.General.FactionName or 'Unknown')

### Справочник полей блюпринта

Типы и значения допустимых полей описаны в `engine/Core/Blueprints/UnitBlueprint.lua`, общие поля сущностей в `EntityBlueprint.lua`.

Источник: fa:engine/Core/Blueprints/UnitBlueprint.lua#---@class UnitBlueprintEconomy

### General.Icon это тип фона

Значения: `air`, `amph`, `land`, `sea`. Это не файл иконки юнита.

Источник: fa:engine/Core/Blueprints/UnitBlueprint.lua#---@alias IconBackgroundType "air" | "amph" | "land" | "sea"

### Смысл AdjacentStructureEnergyMod и AdjacentEnergyProductionMod не установлен

Поля есть в аннотации без описания. Игровой Lua читает их только в `lua/tests/DumpProperties.lua`.

Не подтверждено: нужны значения в `units/` и проверка влияния на бонус соседства.

### Фактическая выработка равна паспортной, умноженной на множитель соседства

Значения из блюпринта надо читать при запуске: другой мод может их изменить.

Источник: fa:lua/sim/Unit.lua#self:SetProductionPerSecondEnergy((bpEcon.ProductionPerSecondEnergy or 0) * (self.EnergyProdAdjMod or 1))

### Бонусы соседства генераторов отрицательные

Они снижают потребление соседей. Выработку энергии повышает только `T1EnergyStorage`, выработку массы только `T1MassStorage`. Значения по размерам SIZE4..SIZE20 лежат в таблице `adj`.

Источник: fa:lua/sim/AdjacencyBuffs.lua#EnergyProduction=   {0.25, 0.125, 0.083334, 0.0625, 0.05},

### Гидрокарбонная станция использует бонусы T2-генератора

Источник: fa:lua/sim/AdjacencyBuffs.lua#adj.Hydrocarbon = adj.T2PowerGenerator

### ID энергетических зданий

T1 `xxb1101`, гидро `xxb1102`, T2 `xxb1201`, T3 `xxb1301`. Префиксы фракций: `ueb` UEF, `uab` Aeon, `urb` Cybran, `xsb` Seraphim.

Источник: fa:lua/BuildingTemplates.lua#'T1HydroCarbon',

### Выработка генераторов 20, 100, 500 и 2500 энергии в секунду

Порядок: T1, гидро, T2, T3.

Не подтверждено: нужны файлы `units/*/*_unit.bp`. В коде лучше читать `bp.Economy.ProductionPerSecondEnergy`.

### У гидро есть категория TECH1

Фильтр `ENERGYPRODUCTION TECH1` тогда захватывает и гидро, поэтому `HYDROCARBON` проверяют первым.

Не подтверждено: нужен файл `units/UEB1102/UEB1102_unit.bp`.

### В интерфейсе нет функции «все юниты армии»

Есть `GetSelectedUnits()`, `GetIdleEngineers()`, `GetIdleFactories()` и `GetUnitById(id)`. Полный список получают скрытым выделением через `UISelectionByCategory(expression, addToCurSel, inViewFrustum, nearestToMouse, mustBeIdle)` и `GetSelectedUnits()`.

Источник: fa:engine/User.lua#function UISelectionByCategory(expression, addToCurSel, inViewFrustum, nearestToMouse, mustBeIdle)

### `UserUnit` и `Unit` это разные объекты

В интерфейсе юнит это `UserUnit`: у него нет `IsUnitState`, `AddUnitCallback`, `GetNavigator` и других методов симуляции. Вызов такого метода падает, а под `pcall` выглядит как обычный `false`. Команду в sim-слой передают через `SimCallback`.

Источник: fa:engine/Sim/Unit.lua#function Unit:IsUnitState(stateName)

### Очередь приказов в интерфейсе

`unit:GetCommandQueue()` возвращает список с полями `ID`, `type`, `position`, текущий приказ стоит первым, а `type` это строка, например `'Script'`. У юнита с категорией `FACTORY` вместо очереди приходит очередь точки сбора.

Источник: fa:engine/User/UserUnit.lua#Returns a table of commands. If the unit has the `FACTORY` category, returns the rally point command queue.

### Атак-мув с кнопки это `Script` с `TaskName = 'AttackMove'`

Кнопка отдаёт команду типа `Script` с параметрами `TaskName` и `AbilityName`, а `commandmode.lua` превращает её в `SimCallback` с `Func = "AttackMove"`. Сам класс задачи в `lua/sim/tasks/AttackMove.lua` пустой.

Источник: fa:lua/ui/game/commandmode.lua#if command.LuaParams.TaskName == 'AttackMove' then

### `GetEconData()` даёт экономику одного юнита

Поля: `energyConsumed`, `energyProduced`, `energyRequested`, `massConsumed`, `massProduced`, `massRequested`. Значения дробные благодаря патчам движка.

Источник: fa:engine/User/UserUnit.lua#---@class EconData

### `GetFocusArmy()` равен `-1` у наблюдателя

Иначе это номер армии, на которой стоит фокус. Код, которому нужна своя армия, проверяет этот случай отдельно.

Источник: fa:engine/Core.lua#The current army number that the player has focused, or `-1` for none (i.e. observer)

### Пауза не отменяет реклейм

`OnPaused` в sim-слое останавливает только эффекты и звук, поле `EntityBeingReclaimed` не обнуляется, а реклейм на паузе идёт со скоростью 0. `OnUnpaused` запускает эффекты для той же цели.

Источник: fa:lua/sim/Unit.lua#-- When paused we reclaim at a speed of 0, with thanks to:

### `SetPaused` не останавливает движение

Инженер на атак-муве с флагом паузы перестаёт реклеймить, но идёт к точке дальше, там встаёт и приказ не теряет.

Наблюдение: инженеры на атак-муве в матче, флаг `SetPaused(units, true)`, сдвиг координат из лога ReclaimPause и ручная проверка в игре.

### Команда `'Pause'` это не то же, что `SetPaused`

`IssueUnitCommand(units, 'Pause')` снимала с инженера приказ атак-мув, а состояние паузы после неё расходилось с `GetIsPaused`. Для паузы без потери приказа используют `SetPaused`.

Наблюдение: инженер на атак-муве в матче, сравнение команды и флага вручную и по логу ReclaimPause.

### `GetIsPaused`, `GetIsPausedOfUnit`, `SetPausedOfUnit`

`GetIsPaused(list)` отвечает, стоит ли на паузе хотя бы один юнит списка. `GetIsPausedOfUnit(unit)` и `SetPausedOfUnit(unit, pause)` это функции из `userInit.lua`: они кладут юнита в одну общую таблицу, поэтому мусора не создают.

Источник: fa:lua/userInit.lua#_G.GetIsPausedOfUnit = function(unit)

### На паузе апгрейд не стартует

Игра снимает паузу, ждёт 5 тиков, выдаёт апгрейд, снова ждёт 5 тиков и ставит паузу обратно. Этот приём не требует приказов и перехвата режима команд.

Источник: fa:lua/ui/game/commandmode.lua#-- paused units do not start upgrades

### Инженеры на атак-муве и патруле сами перестают реклеймить

Об этом сказано в подсказке загрузки игры: при почти полном хранилище реклейм прекращается. Числа там нет, и в Lua-файлах игры порог не найден, поэтому его считают условием движка.

Источник: fa:lua/ui/help/loadingtips.lua#Engineers on an Attack-Move or Patrol order will stop reclaiming when your storage is nearly full

### Порог остановки реклейма около 76.5% массы

Скорость реклейма упала со 140 до 10 массы в секунду между заполнением 76.4% и 76.6% и больше не восстановилась, а доля идущих инженеров выросла. Зависимость от скорости наполнения и от запаса энергии не проверялась.

Наблюдение: один замер, 137 инженеров, шаг 1 с, энергия 100%, скорость из накопительного `GetEconomyTotals().reclaimed`.

### `GetResourceSharing()` не даёт объём перелива

В аннотациях функция возвращает `boolean`, а в Lua игры она не вызывается. Что именно она значит, не проверялось.

Источник: fa:engine/User.lua#function GetResourceSharing()
