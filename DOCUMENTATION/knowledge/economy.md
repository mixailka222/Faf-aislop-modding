# Экономика

Ресурсы, доход и данные экономики армии.

### Поля GetEconomyTotals

`GetEconomyTotals()` возвращает экономику своего игрока: `income`, `lastUseActual`, `lastUseRequested`, `maxStorage`, `reclaimed`, `stored`. В каждом есть `MASS` и `ENERGY`.

Источник: fa:lua/ui/game/economy.lua#---@class EconomyTotals

### income и lastUse указаны за один тик

Панель экономики умножает их на `GetSimTicksPerSecond()`, чтобы получить значение в секунду.

Источник: fa:lua/ui/game/economy.lua#local incomeSec = math.max(0, incomeVal * simFrequency)

### income включает реклейм

Чтобы получить доход без реклейма, его вычитают из `income`.

Источник: fa:lua/ui/game/economy.lua#local generatedIncome = incomeSec - lastReclaimRate

### Реклейм попадает в income на один тик позже

Поэтому игра вычитает скорость реклейма прошлого тика. При разовом всплеске реклейма соседние окна замера разойдутся на этот тик.

Источник: fa:lua/ui/game/economy.lua#-- incomeVal is delayed by 1 tick when it comes to accounting for reclaim.

### reclaimed это накопленный счётчик

Счётчик ведётся по ресурсам, на нём работает колонка реклейма в панели ресурсов, и он доступен UI-моду. Скорость получается как разность двух чтений, делённая на прошедшие тики, умноженная на `GetSimTicksPerSecond()`.

Источник: fa:lua/ui/game/economy.lua#local thisTick = totalReclaimed - lastReclaimTotal
Источник: fa:lua/ui/game/economy.lua#local totalReclaimed = econData.reclaimed[resourceType]

### Панель экономики считает разность между вызовами как один тик

Её функция добавлена с `throttle = true`. При скорости выше нормальной вызовы пропускаются, и такая формула завышает скорость. Для редкого обновления берут реальную разность `GameTick()`.

Источник: fa:lua/ui/game/economy.lua#GameMain.AddBeatFunction(_BeatFunction, true)

### `income` и `energyin.total` включают перелив от союзников

Перелив считается доходом армии, поэтому `income` не равен собственной добыче. Своё производство получают вычитанием: `income` минус входящий перелив. Свой перелив к `income` и `energyin.total` прибавлять нельзя, как и складывать `energyin.total` с отдельно посчитанным входящим переливом.

Источник: fa:lua/aibrains/components/EnergyManagerBrainComponent.lua#as overflow counts as income for our brain.
Наблюдение: партия с союзником, сравнение `GetEconomyTotals().income` со счётчиками `Sync.Score`.
Наблюдение: командная игра с союзником-игроком, сверка по логу в фазах, когда место есть у союзника, нет ни у кого и когда перелив идёт в нашу сторону.

### Прямого значения входящего перелива нет

Его можно только вычислить из других величин.

Источник: fa:lua/aibrains/components/EnergyManagerBrainComponent.lua#There is no way to see how much energy our brain gets as overflow.

### Перелив союзников считается только через баланс

Прямого поля нет: отдано = `dIn - dConsumed - dExcess - dStored` по разностям счётчиков армии за одно окно. Формула сходилась до нуля в матче. Кому ушёл ресурс, она не говорит: счётчики в `Sync.Score` суммарные, поля с разбивкой по получателям нет, а в команде из трёх и больше игроков сумма по союзникам не равна тому, что получил игрок.

Источник: fa:lua/sim/score.lua#energyout = {
Наблюдение: матч с союзником. `excess` рос со скоростью производства, когда места не было ни у кого, и замирал, когда место появлялось у союзника. `dIn` вырос в момент начала передачи от союзника при неизменном своём производстве.
Наблюдение: 69 окон диагностики по энергии и массе в матче с союзником; поведение в команде из трёх игроков выведено из формулы и в игре не измерялось.

### `energyout.excess` это потерянный ресурс

Игра называет это поле `Wasted`. Отданное союзникам в него не входит, несмотря на название `out`.

Источник: fa:lua/ui/dialogs/hotstats.lua#Total Energy Wasted

### `GiveStorage` в sim увеличивает хранилище энергии, но не массы

После `brain:GiveStorage("MASS", 100000)` потолок массы армии остаётся прежним. Тот же вызов с `"ENERGY"` работает. Запас места по массе в сценарии получают через `TakeResource`.

Источник: fa:engine/Sim/CAiBrain.lua#function CAiBrain:GiveStorage(type, amount)
Наблюдение: армия ИИ, после обоих вызовов `Sync.Score` показал массу 650 из 650, а запас энергии рос на 3240 за окно в 6 секунд дольше, чем позволял прежний потолок 4000.

### `GetResourceSharing()` не даёт объём перелива

В аннотациях функция возвращает `boolean`, а в Lua игры она не вызывается. Что именно она значит, не проверялось.

Источник: fa:engine/User.lua#function GetResourceSharing()

### Поля `Sync.Score[army].resources`

`energyin` и `massin` с полями `total`, `rate`, `reclaimed`, `reclaimRate`; `energyout` и `massout` с `total`, `rate`, `excess`; `storage` с `storedMass`, `storedEnergy`, `maxMass`, `maxEnergy`. Поля `total`, `reclaimed`, `excess` накопительные, `total` и `excess` это счётчики армии (`Economy_TotalProduced_*`, `Economy_TotalConsumed_*`, `Economy_AccumExcess_*`). `rate` считается за тик.

Источник: fa:lua/sim/score.lua#Score.resources.energyin.total = brain:GetArmyStat("Economy_TotalProduced_Energy", 0).Value

### Economy_TotalProduced и `energyin.total` включают реклейм

Счётчик `energyin.total` в `Sync.Score` берётся из этой статистики, поэтому название `total` здесь означает всё полученное армией, а не только выработку. Сама игра вычитает `reclaimRate` из разности `total`, чтобы получить чистую скорость `rate`.

Источник: fa:lua/sim/score.lua#Score.resources.energyin.rate = (Score.resources.energyin.total - lastTotalEnergy) / TicksSinceLastUpdate - Score.resources.energyin.reclaimRate

### Счётчики ресурсов в `Sync.Score` меняются ступеньками

Поток `ScoreResourcesThread` в sim снимает их в цикле с `WaitSeconds(1)`, примерно раз в секунду, а публикация идёт примерно раз в 2 с. Окно короче периода обновления попадает то на одну, то на две ступеньки счётчика, поэтому разность за одну публикацию прыгает, и усреднение внутри окна не помогает. Разности накопительных счётчиков складываются точно, поэтому окно удлиняют: окно в несколько публикаций даёт верное среднее. Счётчики, которые растут вместе, в разности ступенек не дают.

Источник: fa:lua/sim/score.lua#local function ScoreResourcesThread()
Наблюдение: своё производство 20 E/с, окно 18 тиков: `dIn` чередуется между +20 и +40. Среднее за 16 окон 20.1 E/с.

### Величины одной формулы берут за один интервал

Мгновенное значение нельзя вычитать из среднего за окно, разные единицы тоже нельзя смешивать.

Наблюдение: доход за один тик минус входящий перелив, усреднённый за 5 секунд: панель показала входящий перелив при полном хранилище.

### `GetEconData()` даёт экономику одного юнита

Поля: `energyConsumed`, `energyProduced`, `energyRequested`, `massConsumed`, `massProduced`, `massRequested`. Значения вещественные благодаря патчам движка и указаны в секунду: `massProduced` и `energyProduced` сравниваются напрямую с `ProductionPerSecondMass`, умножать их на частоту тиков не нужно.

Источник: fa:engine/User/UserUnit.lua#---@class EconData
Источник: fa:engine/User/UserUnit.lua#-- Thanks to the following engine patches this contains floats instead of ints:
Источник: fa:lua/ui/game/commandmode.lua#unitBlueprint.Economy.ProductionPerSecondMass < unit:GetEconData().massProduced
