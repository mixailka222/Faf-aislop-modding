# Связь sim и UI

Как сторона симуляции и интерфейс обмениваются данными.

### `GetEconomyTotals().income` это величина за тик

Для значения в секунду её умножают на `GetSimTicksPerSecond()`.

Источник: fa:lua/ui/game/economy.lua#local incomeSec = math.max(0, incomeVal * simFrequency)

### `GetEconData()` отдаёт значения в секунду

`massProduced` и `energyProduced` сравниваются напрямую с `ProductionPerSecondMass`. Умножать их на частоту тиков не нужно.

Источник: fa:lua/ui/game/commandmode.lua#unitBlueprint.Economy.ProductionPerSecondMass < unit:GetEconData().massProduced

### `GetEconomyTotals().reclaimed` накопительный счётчик

Скорость получают разностью двух чтений.

Источник: fa:lua/ui/game/economy.lua#local thisTick = totalReclaimed - lastReclaimTotal

### Экономика союзников приходит в `Sync.Score`

Клиент получает данные своей армии и союзников, наблюдатель и реплей получают все армии. По врагу приходит только `{ general = {} }`, поэтому его экономика в UI недоступна.

Источник: fa:lua/sim/score.lua#if (myArmyIndex == index) or (alliesScore and IsAlly(myArmyIndex, index)) then

### Поля `Sync.Score[army].resources`

`energyin.total`, `energyin.reclaimed`, `energyin.rate`, `energyout.total`, `energyout.rate`, `energyout.excess`, `storage.storedEnergy`, `storage.maxEnergy`. Для массы то же в `massin`, `massout`, `storedMass`, `maxMass`. Поля `total`, `reclaimed`, `excess` накопительные.

Источник: fa:lua/sim/score.lua#Score.resources.energyin.total = brain:GetArmyStat("Economy_TotalProduced_Energy", 0).Value

### `energyin.total` включает перелив от союзников

Перелив считается доходом армии. Своё производство получают вычитанием, а складывать `energyin.total` с отдельно посчитанным входящим перелив нельзя.

Источник: fa:lua/aibrains/components/EnergyManagerBrainComponent.lua#as overflow counts as income for our brain.

### Прямого значения входящего перелива нет

Его можно только вычислить из других величин.

Источник: fa:lua/aibrains/components/EnergyManagerBrainComponent.lua#There is no way to see how much energy our brain gets as overflow.

### `energyout.excess` это потерянный ресурс

Игра называет это поле `Wasted`. Отданное союзникам в него не входит, несмотря на название `out`.

Источник: fa:lua/ui/dialogs/hotstats.lua#Total Energy Wasted

### Исходящий перелив считается по балансу

`отдано = dIn - dOut - dExcess - dStored` по разностям счётчиков армии за одно окно.

Наблюдение: матч с союзником. `excess` рос со скоростью производства, когда места не было ни у кого, и замирал, когда место появлялось у союзника. `dIn` вырос в момент начала передачи от союзника при неизменном своём производстве.

### Кому именно ушёл перелив, не видно

Счётчики в `Sync.Score` суммарные, поля с разбивкой по получателям нет.

Источник: fa:lua/sim/score.lua#energyout = {

### Счётчики `resources` обновляются примерно раз в секунду

Поток в sim снимает их в цикле с `WaitSeconds(1)`.

Источник: fa:lua/sim/score.lua#local function ScoreResourcesThread()

### `Sync.Score` приходит примерно раз в 2 секунды

Интервал `scoreInterval` делится на число армий, и один проход идёт по всем армиям.

Источник: fa:lua/sim/score.lua#scoreInterval = 2

### Короткое окно по счётчикам `Sync.Score` даёт скачки

Окно короче периода обновления попадает то на одну, то на две ступеньки счётчика, и усреднение внутри окна не помогает. Разности накопительных счётчиков складываются точно, поэтому окно удлиняют. Счётчики, которые растут вместе, в разности ступенек не дают.

Наблюдение: своё производство 20 E/с, окно 18 тиков: `dIn` чередуется между +20 и +40. Среднее за 16 окон 20.1 E/с.

### Величины одной формулы берут за один интервал

Мгновенное значение нельзя вычитать из среднего за окно, разные единицы тоже нельзя смешивать.

Наблюдение: доход за один тик минус входящий перелив, усреднённый за 5 секунд: панель показала входящий перелив при полном хранилище.

### Подписка на данные синхронизации

`AddOnSyncHashedCallback(cb, 'Score', id)` вызывает `cb` с содержимым `Sync.Score` в момент прихода. `id` должен быть уникальным, иначе заменит чужой колбэк.

Источник: fa:lua/UserSync.lua#function AddOnSyncHashedCallback(cb, cat, id)

### Колбэк синхронизации идёт без `pcall`

Ошибка в нём вылетает в обработку синхронизации игры, поэтому тело колбэка оборачивают в `pcall`.

Источник: fa:lua/UserSync.lua#callback(data)

### `import('/lua/UserSync.lua')` не нужен и не создаёт глобалы

Глобальные функции этого файла уже есть: `SessionInit.lua` выполняет его через `doscript`. `import` запустил бы вторую копию файла в таблице модуля, со своей пустой таблицей колбэков.

Источник: fa:lua/SessionInit.lua#doscript '/lua/UserSync.lua'

### `currentScores` читать ненадёжно

Панель счёта обнуляет его сразу после отрисовки.

Источник: fa:lua/ui/game/score.lua#currentScores = false -- dont render score UI until next score update

### Ключи `Sync.Reclaim` это id сущностей

Таблица разреженная, поэтому `table.getn` даёт 0 при непустой таблице. Считать записи нужно через `pairs`.

Источник: fa:lua/sim/Prop.lua#Sync.Reclaim[self.EntityId] = self.SyncData

### `Sync.Reclaim` содержит только изменения последней синхронизации

Симуляция пишет запись, когда проп создан, изменился или убран. Полный список пропов интерфейс накапливает сам, в локальной таблице `Reclaim` файла `ui/game/reclaim.lua`. Снимок `Sync.Reclaim` не отвечает на вопрос, сколько пропов на карте, а пустая таблица значит лишь, что в этом такте ничего не менялось.

Источник: fa:lua/UserSync.lua#Each sync, update the user-side data for any prop created, damaged, or destroyed

### `Sync.Reclaim` доходит до интерфейса

Числа реклейма на карте игра получает именно этим путём: `OnSync` передаёт таблицу в `UpdateReclaim`. Ключи таблицы это EntityId, поэтому записи считают обходом `pairs`, а не через `table.getn`.

Источник: fa:lua/UserSync.lua#UpdateReclaim(Sync.Reclaim)

### Данные из `Sync` ловят колбэком, а не опросом по таймеру

Поток с `WaitSeconds` видит только таблицу последней синхронизации и пропускает всё, что было между замерами. `AddOnSyncHashedCallback(cb, 'Reclaim', 'ИмяМода')` получает каждое обновление. Колбэк вызывается без `pcall`, поэтому свои ошибки он ловит сам.

Источник: fa:lua/UserSync.lua#function AddOnSyncHashedCallback(cb, cat, id)

### Запись `false` в `Sync.Reclaim` значит, что метка снята

`CleanupUILabel` ставит `false`, а в старой таблице стирает `mass` и `position`. Перед чтением запись проверяют через `type(rec) == 'table'`.

Источник: fa:lua/sim/Prop.lua#Sync.Reclaim[self.EntityId] = false

### Пропы дешевле 10 массы в `Sync.Reclaim` не попадают

Запись создаётся только от 10 массы и снимается при падении ниже 10, хотя проп ещё можно реклеймить. `PropInvulnerable` не публикует ничего.

Источник: fa:lua/sim/Prop.lua#if self.MaxMassReclaim * self.ReclaimLeft >= 10 then

### Падение `mass` в `Sync.Reclaim` не доказывает, что реклейм идёт

В Lua масса пропа пересчитывается при нелетальном уроне в `OnDamage` и в `OnStopReclaim`. Вызывает ли движок `OnDamage` на каждом такте реклейма, из Lua не видно.

Не подтверждено: нужен замер в игре, меняется ли `mass` в колбэке `Sync.Reclaim`, пока инженер реклеймит один большой проп.

### Скорость реклейма берут из `GetEconomyTotals().reclaimed`

Это накопительный счётчик по ресурсам, на нём работает колонка реклейма в панели ресурсов. Разница двух замеров даёт скорость, и это доступно UI-моду.

Источник: fa:lua/ui/game/economy.lua#local totalReclaimed = econData.reclaimed[resourceType]

### `IsUnitState` и `AddUnitCallback` есть только в симуляции

У `UserUnit` этих методов нет, поэтому вызов из интерфейса падает с `attempt to call method`. Под `pcall` такая ошибка выглядит как ответ «нет», и проверка состояния всегда ложна.

Источник: fa:engine/Sim/Unit.lua#function Unit:IsUnitState(stateName)

### `ReclaimedMass` и `ReclaimedEnergy` обновляются только в конце реклейма

`OnStopReclaim` считает их по числу тактов от старта, поэтому время на паузе завышает результат. Как признак идущего реклейма эти счётчики не годятся.

Источник: fa:lua/sim/Unit.lua#self:UpdateStat('ReclaimedMass', self.ReclaimedMass)

### В секунде игрового времени 10 тактов симуляции

`WaitSeconds(n)` в симуляции ждёт `n * 10 + 1` тактов.

Источник: fa:lua/simInit.lua#WaitTicks(n * 10 + 1)

### SimCallback вызывает функцию из таблицы Callbacks

Вызов: `SimCallback({ Func = 'Name', Args = {...} }, addUnitSelection)`. Вторым аргументом `true` добавляется текущее выделение. Обработчики получают `(data, units)` и обязаны сами проверять аргументы.

Источник: fa:engine/User.lua#function SimCallback(callback, addUnitSelection)

### Таблица Callbacks локальна в SimCallbacks.lua

Добавить обработчик можно только хуком этого файла: `Callbacks.MyFunc = function(data, units) ... end`. Такой мод работает на стороне sim, у всех игроков партии.

Источник: fa:lua/SimCallbacks.lua#local Callbacks = {}

### В GiveResourcesToPlayer Mass и Energy это доли запаса

Значение 0.25 отдаёт четверть хранилища. `From` должен быть армией отправителя, а получатель союзником.

Источник: fa:lua/SimUtils.lua#local massTaken = fromBrain:TakeResource('MASS', data.Mass * fromBrain:GetEconomyStored('MASS'))

### ExecLuaInSim требует включённых читов

Источник: fa:engine/User.lua#--- Executes some Lua code in the sim. Requires cheats to be enabled

### Таблица Sync копируется в UI на каждом beat

Beat похож на тик, но происходит и на паузе. На стороне sim значение пишут в `Sync.MyData`, на стороне UI читают из глобальной `Sync` или из колбэка.

Источник: fa:lua/UserSync.lua#-- synchronized on the sim beat (which is like a tick but happens even when the game is paused)

### Функции подписки на Sync глобальные

`UserSync.lua` выполняется через `doscript`, поэтому `AddOnSyncCallback` и `AddOnSyncHashedCallback` доступны без импорта. `import('/lua/UserSync.lua')` только выполнит файл второй раз как отдельный модуль.

Источник: fa:lua/SessionInit.lua#doscript '/lua/UserSync.lua'

### AddOnSyncCallback вызывает колбэк в pcall с одним аргументом

Колбэк получает только `Sync`. При ошибке он снимается с подписки, а сообщение уходит в `WARN`.

Источник: fa:lua/UserSync.lua#local ok, msg = pcall(callback, Sync)

### AddOnSyncHashedCallback вызывает колбэк без защиты

Сигнатура: `AddOnSyncHashedCallback(cb, category, id)`. Колбэк получает `Sync[category]` и срабатывает только когда этот ключ пришёл. Ошибка внутри прерывает `OnSync`, поэтому тело колбэка защищают само.

Источник: fa:lua/UserSync.lua#function AddOnSyncHashedCallback(cb, cat, id)

### Sync.Score даёт UI данные своей армии и союзников

Для союзников копируется вся таблица, у врагов остаётся только `general`. Счётчики ресурсов обновляются раз в секунду, а `scoreInterval` равен 2 секундам. Наблюдатель и реплей получают все армии.

Источник: fa:lua/sim/score.lua#if (myArmyIndex == index) or (alliesScore and IsAlly(myArmyIndex, index)) then

### GetArmyStat это метод мозга армии

Он работает на стороне sim: `brain:GetArmyStat('Economy_TotalProduced_Energy', 0).Value`. UI видит те же данные только через `Sync`.

Источник: fa:engine/Sim/CAiBrain.lua#function CAiBrain:GetArmyStat(statName, defaultValue)

### GetListOfUnits работает на стороне sim

Сигнатура: `brain:GetListOfUnits(category, needToBeIdle, requireBuilt)`. Возвращает `Unit`, разведку не учитывает, а `requireBuilt` по аннотации не работает.

Источник: fa:engine/Sim/CAiBrain.lua#function CAiBrain:GetListOfUnits(category, needToBeIdle, requireBuilt)

### В sim-коде игры GetFocusArmy нужен только для вывода игроку

Игра применяет его для печати и наполнения `Sync`. Значение зависит от игрока, поэтому логику симуляции на него не завязывают.

Источник: fa:lua/sim/commands/abort-navigation.lua#if doPrint and (GetFocusArmy() == brain:GetArmyIndex()) then

### AddBeatFunction подписывает функцию на sim beat

Сигнатура: `GameMain.AddBeatFunction(fn, throttle, key)`. При `throttle = true` вызов пропускается, если с прошлого прошло меньше 0.1 реальной секунды, и только когда `GetSimRate()` больше нуля. Снятие подписки делает `RemoveBeatFunction(fn, key)`.

Источник: fa:lua/ui/game/gamemain.lua#function AddBeatFunction(fn, throttle, key)

### `Sync` живёт один бит

Таблица копируется из симуляции в интерфейс на каждом бите, а бит идёт даже на паузе. После передачи движок вызывает `ResetSyncTable()`, поэтому ключи вроде `Score` есть только в тот бит, когда sim-код их записал.

Источник: fa:lua/SimSync.lua#function ResetSyncTable()
Источник: fa:lua/SimSync.lua#-- The global sync table is copied to the user layer every time the main and sim threads are

### `Sync.Score` приходит примерно раз в 2 с, а не каждый бит

`ScoreThread` собирает очки всех армий за `scoreInterval = 2` секунды и только потом записывает `Sync.Score`. Колбэк на `'Score'` срабатывает лишь на такой записи.

Источник: fa:lua/sim/score.lua#scoreInterval = 2

### Счётчики ресурсов в `Sync.Score` меняются ступеньками

`ScoreResourcesThread` обновляет их примерно раз в секунду, а публикация идёт примерно раз в 2 с. Разность за одну публикацию поэтому прыгает: в окно попадает разное число ступенек. Счётчики накопительные, и окно в несколько публикаций даёт верное среднее.

Источник: fa:lua/sim/score.lua#local function ScoreResourcesThread()

### Что видно в `Sync.Score`

Наблюдатель и реплей получают все армии. Игрок получает полные данные своей армии и союзников, у остальных армий только `{ general = {} }`, а у побеждённых `Defeated = true`.

Источник: fa:lua/sim/score.lua#if (myArmyIndex == index) or (alliesScore and IsAlly(myArmyIndex, index)) then

### Поля экономики в `Sync.Score`

В `resources`: `energyin` и `massin` с полями `total`, `rate`, `reclaimed`, `reclaimRate`; `energyout` и `massout` с `total`, `rate`, `excess`; `storage` с `storedMass`, `storedEnergy`, `maxMass`, `maxEnergy`. `total` и `excess` это накопительные счётчики армии (`Economy_TotalProduced_*`, `Economy_TotalConsumed_*`, `Economy_AccumExcess_*`), `rate` считается за тик.

Источник: fa:lua/sim/score.lua#Score.resources.energyin.total = brain:GetArmyStat("Economy_TotalProduced_Energy", 0).Value

### `energyin.total` включает реклейм

Сама игра вычитает `reclaimRate` из разности `total`, чтобы получить `rate`. Название `total` здесь означает всё полученное армией, а не только выработку.

Источник: fa:lua/sim/score.lua#Score.resources.energyin.rate = (Score.resources.energyin.total - lastTotalEnergy) / TicksSinceLastUpdate - Score.resources.energyin.reclaimRate

### `energyin.total` и `income` включают перелив от союзников

Поэтому свой перелив к ним прибавлять нельзя, а своё производство это `income` минус входящий перелив.

Наблюдение: командная игра с союзником-игроком, сверка по логу в фазах, когда место есть у союзника, нет ни у кого и когда перелив идёт в нашу сторону.

### Перелив союзников считается только через баланс

Прямого поля нет: отдано = `dIn − dConsumed − dExcess − dStored` по разностям счётчиков. Формула сходилась до нуля в матче, но не говорит, кому ушёл ресурс: в команде из трёх и больше игроков сумма по союзникам не равна тому, что получил игрок.

Наблюдение: 69 окон диагностики по энергии и массе в матче с союзником; поведение в команде из трёх игроков выведено из формулы и в игре не измерялось.

### `AddOnSyncHashedCallback(cb, cat, id)`

Колбэк вызывается внутри `OnSync` с `Sync[cat]` и раньше, чем игра разбирает остальные поля. Вызов идёт без `pcall`: ошибка прерывает `OnSync` на этом бите, поэтому тело колбэка оборачивают в `pcall` сами. `AddOnSyncCallback` защищён `pcall` и при ошибке снимает колбэк.

Источник: fa:lua/UserSync.lua#function AddOnSyncHashedCallback(cb, cat, id)

### `currentScores` нельзя читать из своей beat-функции

Значение присваивается в `OnSync`, а штатный `_OnBeat` из `score.lua` регистрируется раньше функций мода и сбрасывает его в `false`. К вызову beat-функции мода там уже пусто, поэтому данные берут через `AddOnSyncHashedCallback(cb, 'Score', id)`.

Источник: fa:lua/ui/game/score.lua#currentScores = false -- dont render score UI until next score update

### `UserSync.lua` загружен через `doscript`

Поэтому `AddOnSyncHashedCallback`, `OnSync` и `Sync` это настоящие глобалы. `import("/lua/UserSync.lua")` не нужен: он выполнит файл второй раз, и колбэки из этой копии движок вызывать не будет.

Источник: fa:lua/SessionInit.lua#doscript '/lua/UserSync.lua'

### `GetEconomyTotals()`

Возвращает экономику своего игрока: `income`, `lastUseActual`, `lastUseRequested`, `maxStorage`, `reclaimed`, `stored`, каждое с ключами `MASS` и `ENERGY`. `income` дан за тик: панель игры умножает его на `GetSimTicksPerSecond()`. `reclaimed` это накопительный счётчик, его разность за промежуток даёт скорость реклейма.

Источник: fa:lua/ui/game/economy.lua#---@class EconomyTotals
Источник: fa:lua/ui/game/economy.lua#local incomeSec = math.max(0, incomeVal * simFrequency)

### `Sync.Reclaim` передаёт только изменения пропов

Ключ это `EntityId` пропа, значение `{ mass, position }` или `false`, когда метку убрали. В таблице только те пропы, что изменились за этот бит, с массой не меньше 10. Сама игра читает её в `OnSync`. Длину через `table.getn` брать нельзя: ключи не идут подряд с 1, и результат будет 0 при любом наполнении.

Источник: fa:lua/sim/Prop.lua#Sync.Reclaim[self.EntityId] = data
Источник: fa:lua/UserSync.lua#UpdateReclaim(Sync.Reclaim)

### Тики и секунды

`GameTick()` считает тики симуляции и стоит, когда игра на паузе. На обычной скорости 10 тиков это 1 секунда, при другой скорости множитель даёт `GetSimTicksPerSecond()`.

Источник: fa:engine/User.lua#--- Gets the current game time in ticks. The game time is the simulation time,
