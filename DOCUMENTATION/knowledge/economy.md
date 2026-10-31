# Экономика

Ресурсы, доход и данные экономики армии.

### Поля GetEconomyTotals

`income`, `lastUseActual`, `lastUseRequested`, `maxStorage`, `reclaimed`, `stored`. В каждом есть `MASS` и `ENERGY`.

Источник: fa:lua/ui/game/economy.lua#---@class EconomyTotals

### income и lastUse указаны за один тик

Панель экономики умножает их на `GetSimTicksPerSecond()`, чтобы получить значение в секунду.

Источник: fa:lua/ui/game/economy.lua#local incomeSec = math.max(0, incomeVal * simFrequency)

### Тик равен 0.1 секунды игрового времени

В код лучше подставлять `GetSimTicksPerSecond()`, а не число.

Источник: fa:lua/system/blueprints-ai.lua#Game logic rounds the timings to the nearest tick

### income включает реклейм

Чтобы получить доход без реклейма, его вычитают из `income`.

Источник: fa:lua/ui/game/economy.lua#local generatedIncome = incomeSec - lastReclaimRate

### Реклейм попадает в income на один тик позже

Поэтому игра вычитает скорость реклейма прошлого тика. При разовом всплеске реклейма соседние окна замера разойдутся на этот тик.

Источник: fa:lua/ui/game/economy.lua#-- incomeVal is delayed by 1 tick when it comes to accounting for reclaim.

### reclaimed это накопленный счётчик

Скорость получается как разность счётчика, делённая на прошедшие тики, умноженная на `GetSimTicksPerSecond()`.

Источник: fa:lua/ui/game/economy.lua#local thisTick = totalReclaimed - lastReclaimTotal

### Панель экономики считает разность между вызовами как один тик

Её функция добавлена с `throttle = true`. При скорости выше нормальной вызовы пропускаются, и такая формула завышает скорость. Для редкого обновления берут реальную разность `GameTick()`.

Источник: fa:lua/ui/game/economy.lua#GameMain.AddBeatFunction(_BeatFunction, true)

### Перелив от союзников входит в income

Поэтому `income` не равен собственной добыче, и входящий перелив вычитают отдельно.

Наблюдение: партия с союзником, сравнение `GetEconomyTotals().income` со счётчиками `Sync.Score`.

### Economy_TotalProduced включает реклейм

Счётчик `energyin.total` в `Sync.Score` берётся из этой статистики, и игра вычитает `reclaimRate`, чтобы получить чистую скорость.

Источник: fa:lua/sim/score.lua#Score.resources.energyin.rate = (Score.resources.energyin.total - lastTotalEnergy) / TicksSinceLastUpdate - Score.resources.energyin.reclaimRate
