# Юниты и категории

`UserUnit`, категории, выделение, очереди приказов, Blueprint.

### Очередь приказов: в UI тип строкой, в sim числом

В UI `unit:GetCommandQueue()` возвращает список записей `{ type, ID, position }`, текущий приказ стоит первым, а `type` это строка, например `'Move'` или `'Script'`. У юнита с категорией `FACTORY` вместо очереди приказов приходит очередь точки сбора. В sim запись содержит число `commandType` и координаты `x`, `y`, `z`.

Источник: fa:engine/User/UserUnit.lua#---@class UICommandInfo
Источник: fa:engine/User/UserUnit.lua#Returns a table of commands. If the unit has the `FACTORY` category, returns the rally point command queue.

### Коды приказов sim

`commandType`: `Patrol` 16, `FormPatrol` 18, `Reclaim` 19, `Script` 28, `AggressiveMove` 35, `FormAggressiveMove` 36.

Источник: fa:lua/sim/commands/shared.lua#---| "AggressiveMove"               # 35

### Атак-мув с кнопки это `Script` с `TaskName = 'AttackMove'`

Кнопка отдаёт команду типа `Script` с параметрами `TaskName` и `AbilityName`, а `commandmode.lua` превращает её в `SimCallback` с `Func = "AttackMove"`. Колбэк sim тут же выдаёт настоящий `AggressiveMove` всем юнитам, кроме зданий, поэтому в очереди движущегося юнита после этого лежит тип `AggressiveMove`. Сам класс задачи в `lua/sim/tasks/AttackMove.lua` пустой, задача-пустышка завершается на первом тике.

Источник: fa:lua/ui/game/commandmode.lua#if command.LuaParams.TaskName == 'AttackMove' then
Источник: fa:lua/SimCallbacks.lua#IssueAggressiveMove(allNonStructures, { x, y, z })

### `LuaParams` виден только при выдаче приказа

Поле приходит в обработчик `OnCommandIssued`. В записи UI-очереди его нет, поэтому `TaskName` по очереди не узнать.

Источник: fa:lua/ui/game/commandmode.lua#if command.LuaParams.TaskName == 'AttackMove' then

### `UserUnit` и `Unit` это разные объекты

В интерфейсе юнит это `UserUnit`: у него нет `IsUnitState`, `AddUnitCallback`, `GetNavigator` и других методов симуляции. Вызов такого метода из интерфейса падает с `attempt to call method`, а под `pcall` выглядит как обычный `false`, и проверка состояния всегда ложна. Поэтому состояние `Building` или `Reclaiming` из UI так не прочитать, в UI есть `unit:IsIdle()` и `unit:GetFocus()`. Команду в sim-слой передают через `SimCallback`.

Источник: fa:engine/Sim/Unit.lua#function Unit:IsUnitState(stateName)

### Что строит инженер, из UI видно через `GetFocus`

`unit:GetFocus()` возвращает юнит, на котором сосредоточен инженер, или `nil`. Так игра сравнивает, строят ли два инженера одно и то же. Недостроенный юнит отличается по `GetFractionComplete() < 1`.

Источник: fa:lua/ui/game/commandmode.lua#if targetFocus and targetFocus == engineer:GetFocus() then

Не подтверждено: что возвращает `GetFocus` инженеру на реклейме обломка. Sim-слой делает цель реклейма фокусом, но обломок не юнит, поэтому ожидается `nil`. Нужен опыт в игре.

### Выработка недостроенного здания кодом Lua не определена

`Unit.OnCreate` включает производство всем юнитам сразу, а класс генератора пуст. Строка в `OnStopBeingBuilt` у фабрикатора массы поэтому не доказывает, что до завершения стройки производства нет.

Не подтверждено: нужен замер `GetEconData().energyProduced` у генератора во время постройки.

### `SetPaused` задаёт флаг паузы явно

`SetPaused(units, true)` можно вызывать повторно. Игровая клавиша `pause_unit` вызывает его же с обратным значением `GetIsPaused`. По описанию API пауза останавливает постройку, улучшение и другие задачи, а помощников юнита не затрагивает.

Источник: fa:engine/Sim/Unit.lua#--- Assisting units are unaffected.

### `GetIsPaused` отвечает за группу, `GetIsPausedOfUnit` за один юнит

`GetIsPaused(list)` истинно, если на паузе хотя бы один юнит из списка. `GetIsPausedOfUnit(unit)` и `SetPausedOfUnit(unit, pause)` это функции из `userInit.lua`: они кладут юнита в одну общую таблицу, поэтому мусора не создают. Игра вызывает `GetIsPausedOfUnit` напрямую, без проверки наличия.

Источник: fa:lua/ui/game/orders.lua#if not GetIsPausedOfUnit(silo) then
Источник: fa:lua/userInit.lua#_G.GetIsPausedOfUnit = function(unit)

### Пауза не отменяет реклейм

`OnPaused` в sim-слое выключает только эффекты и звук, поле `EntityBeingReclaimed` не обнуляется. Скорость реклейма на паузе равна 0 за счёт патча движка. `OnUnpaused` запускает эффекты для той же цели.

Источник: fa:lua/sim/Unit.lua#-- When paused we reclaim at a speed of 0, with thanks to:

### Пауза флагом не останавливает движение и не трогает приказ

Инженер на атак-муве под `SetPaused` перестаёт реклеймить, но идёт к точке дальше, там встаёт и приказ не теряет: после снятия паузы он продолжает приказ. Очередь у юнита на паузе читается, поэтому пустой ответ `GetCommandQueue()` паузой не объясняется.

Наблюдение: инженеры на атак-муве, ручная пауза и пауза от мода, несколько игр; у 20 инженеров через секунду после паузы очередь вернула `AggressiveMove`.
Наблюдение: инженеры на атак-муве в матче, флаг `SetPaused(units, true)`, сдвиг координат из лога ReclaimPause и ручная проверка в игре.

### `Pause` как приказ и как флаг это разные механизмы

Команда типа 33 `Pause` уходит в очередь приказов и может сработать не сразу, а `SetPaused` действует сразу. Сама игра выдаёт этот приказ только ракетным шахтам и только если они не на паузе. `IssueUnitCommand(units, 'Pause')` останавливает инженера, но снимает приказ атак-мув. Повторная выдача работает как переключатель, поэтому состояние паузы расходится с `GetIsPaused` и с тем, что ожидает вызывающий код. Для паузы без потери приказа используют `SetPaused`.

Источник: fa:lua/ui/game/orders.lua#IssueUnitCommandToUnit(silo, 'Pause')
Наблюдение: инженеры на атак-муве, сравнение с `SetPaused` в игре; в логе `engineers=9 nowPaused=0` при приказной паузе.
Наблюдение: инженер на атак-муве в матче, сравнение команды и флага вручную и по логу ReclaimPause.

### Неверное имя команды в `IssueUnitCommand` роняет игру

То же относится к `IssueUnitCommandToUnit` и `IssueCommand`. Имя берут из списка `UserUnitCommand`.

Источник: fa:engine/User.lua#---@param command UserUnitCommand # Will crash the game if not a valid command.

### `AbortNavigation` обрывает путь и не трогает очередь

Колбэк вызывает `navigator:AbortMove()` и `RefocusAssisters()` для юнитов `ENGINEER` и `COMMAND` из выделения. Это штатное действие с горячей клавишей.

Источник: fa:lua/sim/commands/abort-navigation.lua#navigator:AbortMove()

### `AbortNavigation` принимается раз в 6 тактов на игрока

Защита от автоматизации отклоняет вызов, если с прошлого принятого прошло 5 тактов или меньше. Счётчик один на источник команд, а не на юнита, и при 10 тактах в секунду это 0.6 с игрового времени. Отказ печатает `Unable to interrupt path finding`.

Источник: fa:lua/SimCallbacks.lua#if commandSourceGuard and commandSourceGuard + 5 >= gameTick then

### Прерванный атак-мув продолжается

Приказ остаётся в очереди, поэтому инженер снова строит путь. Чтобы держать его на месте, обрыв повторяют.

Наблюдение: инженеры на атак-муве под `SetPaused`, один `AbortNavigation` на паузу; инженеры продолжили идти к точке.

### `IssuePatrol` с одной точкой работает как движение

Дойдя до точки, юнит останавливается, и его очередь приказов пустеет. Чтобы юнит патрулировал, нужны два вызова с разными точками: тогда `GetCommandQueue()` держит две записи с `type = 'Patrol'`.

Наблюдение: инженер `uel0105` в матче; после одного вызова очередь опустела к 127-му тику, после двух вызовов записей оставалось две, в том числе после снятия паузы.

### Обрыв пути даёт инженеру на патруле реклейм издалека

Сигнал окончания пути используется разными командами, поэтому у `AbortNavigation` есть побочные эффекты. На атак-муве и патруле инженер начинает реклейм с большего расстояния.

Источник: fa:lua/sim/commands/abort-navigation.lua#For engineers that are on a patrol or an attack move the engineer can start reclaiming from further away

### Дальний реклейм на патруле связан с `GuardScanRadius`

По разбору движка инженер идёт к цели по малому радиусу, а отбрасывает её только по `GuardScanRadius`, и обрыв движения оставляет его между этими границами. Черновик FAForever/fa #7326 отключает обрыв для патрульных инженеров, и с ним приём перестанет работать.

Не подтверждено: в `references` нет кода `CUnitReclaimTask`; нужен реверс движка или замер дальности. Статус PR проверять перед использованием приёма.

### Инженеры на атак-муве и патруле сами бросают реклейм при почти полном хранилище

Игра сообщает об этом только в подсказке загрузки. Числа там нет, и в Lua-файлах игры порог и проверка уровня хранилища не найдены, поэтому его считают условием движка.

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

Глобальной функции `GetUnits()` нет, она есть в чужих библиотеках как обёртка над скрытым выделением, и функция из чужого мода перестаёт работать, если игрок этот мод отключил. Готовые списки есть только частичные: `GetSelectedUnits()`, `GetIdleEngineers()`, `GetIdleFactories()`, `GetArmyAvatars()`, `GetValidAttackingUnits()`. Отдельный объект достаётся через `GetUnitById(id)`. Полный список собирают скрытой подменой выделения: внутри неё вызывают `UISelectionByCategory('ALLUNITS', false, false, false, false)` и читают `GetSelectedUnits() or {}`, потому что при пустом выделении `GetSelectedUnits()` даёт `nil`.

Источник: fa:engine/User.lua#function GetIdleEngineers()
Источник: fa:engine/User.lua#function UISelectionByCategory(expression, addToCurSel, inViewFrustum, nearestToMouse, mustBeIdle)
Источник: ui-libs:mods/UMT/modules/units.lua#UISelectionByCategory("ALLUNITS", false, false, false, false)

### Внутри OnSelectionChanged GetSelectedUnits даёт nil

Это верно, когда функцию вызывает движок. Сканировать армию внутри этого обработчика нельзя.

Источник: fa:lua/ui/game/gamemain.lua#`GetSelectedUnits` always results in `nil` within this function.

### Скан армии привязан к армии в фокусе

При смене `GetFocusArmy()` кэш сбрасывают, а при значении -1 (наблюдатель) скан не делают.

Источник: ui-libs:mods/UMT/modules/units.lua#if army ~= -1 and currentTick - 10 >= prevCache then

### Пустой результат скана не означает «юнитов нет»

Результат `UISelectionByCategory` + `GetSelectedUnits` бывает пустым, и это неудачный замер: его отбрасывают и оставляют прошлый результат. Причина пустого ответа не установлена.

Наблюдение: партия с UI-сканом `UISelectionByCategory` и `GetSelectedUnits`, пустой список в момент достройки здания.
Наблюдение: достройка здания при обходе армии: список пуст, при этом доход читается верно. Точная причина не установлена.

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

### `GetFocusArmy()` равен `-1` у наблюдателя

Иначе это номер армии, на которой стоит фокус. Код, которому нужна своя армия, проверяет этот случай отдельно.

Источник: fa:engine/Core.lua#The current army number that the player has focused, or `-1` for none (i.e. observer)

### На паузе апгрейд не стартует

Игра снимает паузу, ждёт 5 тиков, выдаёт апгрейд, снова ждёт 5 тиков и ставит паузу обратно. Этот приём не требует приказов и перехвата режима команд.

Источник: fa:lua/ui/game/commandmode.lua#-- paused units do not start upgrades

### Порог остановки реклейма около 76.5% массы

Скорость реклейма упала со 140 до 10 массы в секунду между заполнением 76.4% и 76.6% и больше не восстановилась, а доля идущих инженеров выросла. Зависимость от скорости наполнения и от запаса энергии не проверялась.

Наблюдение: один замер, 137 инженеров, шаг 1 с, энергия 100%, скорость из накопительного `GetEconomyTotals().reclaimed`.
