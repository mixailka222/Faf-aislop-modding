# Связь sim и UI

Как сторона симуляции и интерфейс обмениваются данными.

### Что видно в `Sync.Score`

Наблюдатель и реплей получают все армии. Игрок получает полные данные своей армии и союзников: для союзников копируется вся таблица. У остальных армий остаётся только `{ general = {} }`, поэтому экономика врага в UI недоступна, а у побеждённых `Defeated = true`.

Источник: fa:lua/sim/score.lua#if (myArmyIndex == index) or (alliesScore and IsAlly(myArmyIndex, index)) then

### `Sync.Score` приходит примерно раз в 2 с, а не каждый бит

`ScoreThread` собирает очки всех армий за `scoreInterval = 2` секунды: интервал делится на число армий, и один проход идёт по всем армиям. Только потом поток записывает `Sync.Score`, и колбэк на `'Score'` срабатывает лишь на такой записи.

Источник: fa:lua/sim/score.lua#scoreInterval = 2

### `AddOnSyncHashedCallback(cb, cat, id)`

Данные из `Sync` ловят этим колбэком, а не опросом по таймеру: поток с `WaitSeconds` видит только таблицу последней синхронизации и пропускает всё, что было между замерами, а `AddOnSyncHashedCallback(cb, 'Reclaim', 'ИмяМода')` получает каждое обновление. Колбэк вызывается внутри `OnSync` с `Sync[cat]` и только в тот момент, когда этот ключ пришёл, раньше, чем игра разбирает остальные поля. `id` должен быть уникальным, иначе заменит чужой колбэк. Вызов идёт без `pcall`: ошибка прерывает `OnSync` на этом бите, поэтому тело колбэка оборачивают в `pcall` сами.

Источник: fa:lua/UserSync.lua#function AddOnSyncHashedCallback(cb, cat, id)
Источник: fa:lua/UserSync.lua#callback(data)

### `UserSync.lua` загружен через `doscript`

`SessionInit.lua` выполняет его через `doscript`, поэтому `AddOnSyncCallback`, `AddOnSyncHashedCallback`, `OnSync` и `Sync` это настоящие глобалы и доступны без импорта. `import('/lua/UserSync.lua')` не нужен и не создаёт глобалы: он запустил бы вторую копию файла в таблице модуля, со своей пустой таблицей колбэков, и колбэки из этой копии движок вызывать не будет.

Источник: fa:lua/SessionInit.lua#doscript '/lua/UserSync.lua'

### `currentScores` нельзя читать из своей beat-функции

Значение присваивается в `OnSync`, а штатный `_OnBeat` из `score.lua` регистрируется раньше функций мода и сбрасывает его в `false` сразу после отрисовки. К вызову beat-функции мода там уже пусто, поэтому данные берут через `AddOnSyncHashedCallback(cb, 'Score', id)`.

Источник: fa:lua/ui/game/score.lua#currentScores = false -- dont render score UI until next score update

### `Sync.Reclaim` передаёт только изменения пропов

В таблице только те пропы, что изменились за этот бит: симуляция пишет запись, когда проп создан, изменился или убран. Ключ это `EntityId` пропа, значение `{ mass, position }` или `false`, когда метку убрали. Числа реклейма на карте игра получает именно этим путём: `OnSync` передаёт таблицу в `UpdateReclaim`. Полный список пропов интерфейс накапливает сам, в локальной таблице `Reclaim` файла `ui/game/reclaim.lua`. Снимок `Sync.Reclaim` не отвечает на вопрос, сколько пропов на карте, а пустая таблица значит лишь, что в этом такте ничего не менялось. Ключи не идут подряд с 1, поэтому `table.getn` даёт 0 при любом наполнении, и записи считают обходом `pairs`.

Источник: fa:lua/UserSync.lua#Each sync, update the user-side data for any prop created, damaged, or destroyed
Источник: fa:lua/UserSync.lua#UpdateReclaim(Sync.Reclaim)
Источник: fa:lua/sim/Prop.lua#Sync.Reclaim[self.EntityId] = self.SyncData
Источник: fa:lua/sim/Prop.lua#Sync.Reclaim[self.EntityId] = data

### Запись `false` в `Sync.Reclaim` значит, что метка снята

`CleanupUILabel` ставит `false`, а в старой таблице стирает `mass` и `position`. Перед чтением запись проверяют через `type(rec) == 'table'`.

Источник: fa:lua/sim/Prop.lua#Sync.Reclaim[self.EntityId] = false

### Пропы дешевле 10 массы в `Sync.Reclaim` не попадают

Запись создаётся только от 10 массы и снимается при падении ниже 10, хотя проп ещё можно реклеймить. `PropInvulnerable` не публикует ничего.

Источник: fa:lua/sim/Prop.lua#if self.MaxMassReclaim * self.ReclaimLeft >= 10 then

### `ReclaimedMass` и `ReclaimedEnergy` обновляются только в конце реклейма

`OnStopReclaim` считает их по числу тактов от старта, поэтому время на паузе завышает результат. Как признак идущего реклейма эти счётчики не годятся.

Источник: fa:lua/sim/Unit.lua#self:UpdateStat('ReclaimedMass', self.ReclaimedMass)

### Тики и секунды

`GameTick()` считает тики симуляции и стоит, когда игра на паузе. Тик равен 0.1 секунды игрового времени: на обычной скорости 10 тиков это 1 секунда, при другой скорости множитель даёт `GetSimTicksPerSecond()`. В код лучше подставлять его, а не число. `WaitSeconds(n)` в симуляции ждёт `n * 10 + 1` тиков.

Источник: fa:engine/User.lua#--- Gets the current game time in ticks. The game time is the simulation time,
Источник: fa:lua/system/blueprints-ai.lua#Game logic rounds the timings to the nearest tick
Источник: fa:lua/simInit.lua#WaitTicks(n * 10 + 1)

### SimCallback вызывает функцию из таблицы Callbacks

Вызов: `SimCallback({ Func = 'Name', Args = {...} }, addUnitSelection)`. Вторым аргументом `true` добавляется текущее выделение: колбэк получает юнитов вторым параметром, поэтому перед вызовом они должны быть выделены. Обработчики получают `(data, units)` и обязаны сами проверять аргументы.

Источник: fa:engine/User.lua#function SimCallback(callback, addUnitSelection)
Источник: fa:engine/User.lua#--- Optionally appends the unit selection to the arguments.

### Таблица Callbacks локальна в SimCallbacks.lua

Добавить обработчик можно только хуком этого файла: `Callbacks.MyFunc = function(data, units) ... end`. Такой мод работает на стороне sim, у всех игроков партии.

Источник: fa:lua/SimCallbacks.lua#local Callbacks = {}

### В GiveResourcesToPlayer Mass и Energy это доли запаса

Значение 0.25 отдаёт четверть хранилища. `From` должен быть армией отправителя, а получатель союзником.

Источник: fa:lua/SimUtils.lua#local massTaken = fromBrain:TakeResource('MASS', data.Mass * fromBrain:GetEconomyStored('MASS'))

### ExecLuaInSim требует включённых читов

Источник: fa:engine/User.lua#--- Executes some Lua code in the sim. Requires cheats to be enabled

### `Sync` живёт один бит

Таблица копируется из симуляции в интерфейс на каждом бите. Бит похож на тик, но идёт даже на паузе. На стороне sim значение пишут в `Sync.MyData`, на стороне UI читают из глобальной `Sync` или из колбэка. После передачи движок вызывает `ResetSyncTable()`, поэтому ключи вроде `Score` есть только в тот бит, когда sim-код их записал.

Источник: fa:lua/SimSync.lua#function ResetSyncTable()
Источник: fa:lua/SimSync.lua#-- The global sync table is copied to the user layer every time the main and sim threads are
Источник: fa:lua/UserSync.lua#-- synchronized on the sim beat (which is like a tick but happens even when the game is paused)

### AddOnSyncCallback вызывает колбэк в pcall с одним аргументом

Колбэк получает только `Sync`. При ошибке он снимается с подписки, а сообщение уходит в `WARN`.

Источник: fa:lua/UserSync.lua#local ok, msg = pcall(callback, Sync)

### GetArmyStat это метод мозга армии

Он работает на стороне sim: `brain:GetArmyStat('Economy_TotalProduced_Energy', 0).Value`. UI видит те же данные только через `Sync`.

Источник: fa:engine/Sim/CAiBrain.lua#function CAiBrain:GetArmyStat(statName, defaultValue)

### GetListOfUnits работает на стороне sim

Сигнатура: `brain:GetListOfUnits(category, needToBeIdle, requireBuilt)`. Возвращает `Unit`, разведку не учитывает, а `requireBuilt` по аннотации не работает.

Источник: fa:engine/Sim/CAiBrain.lua#function CAiBrain:GetListOfUnits(category, needToBeIdle, requireBuilt)

### В sim-коде игры GetFocusArmy нужен только для вывода игроку

Игра применяет его для печати и наполнения `Sync`. Значение зависит от игрока, поэтому логику симуляции на него не завязывают.

Источник: fa:lua/sim/commands/abort-navigation.lua#if doPrint and (GetFocusArmy() == brain:GetArmyIndex()) then
