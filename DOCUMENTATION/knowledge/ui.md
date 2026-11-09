# Интерфейс

Контролы, раскладка, окна, обновление по кадрам, команды и выделение.

### Минимальная панель

```lua
local panel = Group(GetFrame(0))
panel:DisableHitTest(true)
LayoutHelpers.SetDimensions(panel, 240, 40)
LayoutHelpers.AtLeftTopIn(panel, GetFrame(0), 8, 80)
local label = UIUtil.CreateText(panel, 'text', 12, UIUtil.bodyFont)
LayoutHelpers.AtLeftTopIn(label, panel, 8, 6)
```

Источник: fa:lua/ui/uiutil.lua#function CreateText(parent, label, pointSize, font, dropshadow)

### `Left`, `Width` и другие размеры контрола это LazyVar

Читают их вызовом через точку: `c.Left()`. Задают через двоеточие: `c.Left:Set(v)`, значением или функцией. Методы вызывают через двоеточие: `c:Hide()`, `label:SetText('x')`. Функции модуля зовут точкой: `LayoutHelpers.SetDimensions(...)`.

Источник: fa:lua/maui/control.lua#self.Left:Set(function() return self.Right() - self.Width() end)
Источник: fa:lua/ui/game/massfabs.lua#self.Left:Set(math.min(math.max(x - offX, self._parent.Left()), self._parent.Right() - self.Width()))

### `AddBeatFunction(fn, throttle, key)`

`GameMain.AddBeatFunction(fn, throttle, key)` подписывает `fn` на sim beat: она вызывается на каждом бите симуляции. При `throttle = true` вызов пропускается, если с прошлого прошло меньше 0.1 реальной секунды, и только когда `GetSimRate()` больше нуля, поэтому вызовов не больше десяти в секунду. Снятие подписки делает `RemoveBeatFunction(fn, key)`.

Источник: fa:lua/ui/game/gamemain.lua#function AddBeatFunction(fn, throttle, key)

### Beat-функция идёт без потока и без `pcall`

Ждать в ней нельзя. Ошибка обрывает цикл, и остальные beat-функции этого бита не выполняются.

Источник: fa:lua/ui/game/gamemain.lua#if v.fn then v.fn() end

### Скрытая подмена выделения

Образец из самой игры. Режим приказов очищается до подмены и восстанавливается после неё, поэтому `RestoreCommandMode` безопасно вызывать после снятия флага.

```lua
commandMode.CacheAndClearCommandMode()
gameMain.SetIgnoreSelection(true)
local old = GetSelectedUnits()
SelectUnits(units)
-- работа
SelectUnits(old)
gameMain.SetIgnoreSelection(false)
commandMode.RestoreCommandMode(true)
```

Источник: fa:lua/userInit.lua#commandMode.CacheAndClearCommandMode()
Источник: fa:lua/ui/game/hotkeys/dock-damaged.lua#gameMain.SetIgnoreSelection(true)
Источник: ui-libs:mods/UMT/modules/units.lua#CommandMode.CacheAndClearCommandMode()

### `SetIgnoreSelection` это функция модуля `gamemain.lua`

Глобальной функции с таким именем нет, берут её через `import("/lua/ui/game/gamemain.lua")`. Она ставит два флага: флаг в `gamemain.lua` заставляет `OnSelectionChanged` выйти сразу, флаг в `commandmode.lua` заставляет сразу выйти `EndCommandMode`. Поэтому пока флаг стоит, смена выделения не закрывает режим команд.

Источник: fa:lua/ui/game/gamemain.lua#import("/lua/ui/game/commandmode.lua").SetIgnoreSelection(ignore)
Источник: fa:lua/userInit.lua#-- prevents losing command mode

### `SetIgnoreSelection` и `Selection.Hidden` одинаково глушат `OnSelectionChanged`

Обе проверки стоят в начале функции, поэтому `ObserveSelection` и хуки ниже них не срабатывают. Разница в режиме приказов: `SetIgnoreSelection` блокирует `EndCommandMode`, а флаг `Hidden` проверяет только `OnSelectionChanged`. `Hidden` запоминает режим и в конце вызывает `StartCommandMode`, а тот при активном режиме выполняет `EndCommandMode(true)` полностью, вместе с `ClearBuildTemplates`.

Источник: fa:lua/ui/game/gamemain.lua#if import("/lua/ui/game/selection.lua").IsHidden() then
Источник: fa:lua/ui/game/selection.lua#CM.StartCommandMode(current_command[1], current_command[2])

### Смена выделения завершает режим приказов

Поэтому подмена выделения без восстановления режима теряет приказ, который игрок сейчас отдаёт.

Источник: fa:lua/ui/game/commandmode.lua#usually changing selection ends the command mode

### `GetCommandMode()` возвращает одну и ту же таблицу

Значения `[1]` и `[2]` копируют сразу, иначе следующий вызов их перезапишет.

Источник: fa:lua/ui/game/commandmode.lua#local commandModeTable = {}

### `InCommandMode` не глобальная функция

Это функция модуля `commandmode.lua`, вызывать её надо через импорт: `import("/lua/ui/game/commandmode.lua").InCommandMode()`.

Источник: fa:lua/ui/game/commandmode.lua#function InCommandMode()

### На старте матча игра сама выделяет командира

Поток `StartupSequence` повторяет `SelectUnits` до успеха или до 50 тика. Подмена выделения в это время с ним сталкивается: примерно с 36 по 51 тик `UISelectionByCategory` оставляет выделение пустым, а выделение игрока после возврата теряется. С 60 тика такого не было.

Источник: fa:lua/ui/game/gamemain.lua#until not table.empty(selected) or GameTick() > 50
Наблюдение: матч через `/map`, опрос `UISelectionByCategory("COMMAND")` раз в 0.7 секунды: на тиках 36, 43, 50 и 51 выделено 0 юнитов, в остальные моменты 1. Подмена из мода на старте матча дала строку `was 1 unit(s), now 0`.

### В UI `WaitSeconds` считает реальное время, а `WaitTicks` игровые тики

`WaitTicks` не завершится, пока игра на паузе, потому что `GameTick()` стоит на месте. `WaitSeconds` на паузе продолжает идти.

Источник: fa:lua/userInit.lua#until (start + ticks) <= GameTick()

### `Selection.Hidden(callback)` это готовая обёртка скрытого выделения

Функция ставит `hidden_select = true`, запоминает выделение и режим команд, вызывает `callback()` без `pcall`, затем всё возвращает. `IsHidden()` сообщает обработчикам, что выделение временное. Защиты от ошибки нет: если `callback` упал, выделение не вернётся, `IsHidden()` останется `true`, и `OnSelectionChanged` будет выходить сразу до конца партии. Внешний `pcall` этого не чинит, ошибки ловят внутри `callback`.

Источник: fa:lua/ui/game/selection.lua#function Hidden(callback)
Источник: fa:lua/ui/game/selection.lua#hidden_select = true

### `CacheAndClearCommandMode` и `RestoreCommandMode` идут парой

`GetCommandMode` и `StartCommandMode` для этого не нужны: режим кэшируется и возвращается этими двумя функциями из `commandmode.lua`. Если режим был закэширован, `RestoreCommandMode` вызывает `StartCommandMode`, и его обработчики запуска выполняются заново. Поэтому скрытое выделение откладывают, пока `InCommandMode()` истинно. Аргумент `true` ещё сбрасывает `issuedOneCommand`: этот флаг закрывает режим на ближайшем бите, если не зажат Shift.

Источник: fa:lua/ui/game/commandmode.lua#function RestoreCommandMode(ignorePreviousCommands)
Источник: fa:lua/ui/game/commandmode.lua#function CacheAndClearCommandMode()

### Помощники LayoutHelpers сами умножают числа на масштаб интерфейса

`SetWidth`, `SetHeight`, `SetDimensions`, все `At*In`, `LeftOf`, `RightOf`, `Below` умножают число на `pixelScaleFactor` (настройка `ui_scale`). Делить на масштаб вручную не нужно. Значения `control.Left()` и `control.Width()` уже экранные: если передать их в такой помощник, масштаб применится дважды.

Источник: fa:lua/maui/layouthelpers.lua#control.Width:SetValue(MathFloor(width * pixelScaleFactor))

### InvScaleNumber переводит экранное число в базовые единицы

`ScaleNumber` делает из базовых единиц экранные, `InvScaleNumber` наоборот. Перед передачей экранного числа в `At*In` или записью в профиль его переводят через `InvScaleNumber`.

Источник: fa:lua/maui/layouthelpers.lua#return MathCeil(scaledNumber / pixelScaleFactor)

### Прямая запись в Left, Top, Width, Height не масштабируется

`control.Height:Set(14)` даёт 14 экранных пикселей при любом `ui_scale`. Игра в таких случаях сама вызывает `ScaleNumber`.

Источник: fa:lua/maui/window.lua#self.Left:Set(LayoutHelpers.ScaleNumber(defaultPosition.Left))

### Геометрия контрола круговая

По умолчанию `Left`, `Top`, `Right`, `Bottom`, `Width`, `Height` определены друг через друга. Чтобы круг разорвался, нужно задать минимум четыре из них.

Источник: fa:lua/maui/control.lua#makes a circular dependency where you must have at least 4 defined.

### Размер Bitmap по умолчанию берётся из текстуры

У `Bitmap` со сплошным цветом размер надо задать явно, например через `LayoutHelpers.SetDimensions` или `FillParent`.

Источник: fa:lua/maui/bitmap.lua#self.Width:SetFunction(function() return ScaleNumber(self.BitmapWidth()) end)

### Depth по умолчанию равен глубине родителя плюс 1

Больше значит выше. `control.Depth:Set(20)` фиксирует абсолютное число и перестаёт следовать за родителем. Относительная глубина задаётся через `LayoutHelpers.DepthOverParent(control, parent, depth)`.

Источник: fa:lua/maui/control.lua#self.Depth:Set(function() return self:GetParent().Depth() + 1 end)

### Событие мыши всплывает к родителю

`HandleEvent` вызывается только при включённом hit test. Если он вернул `false`, событие получает `HandleEvent` родителя, если `true`, дальше оно не идёт. Базовый `HandleEvent` возвращает `false`.

Источник: fa:lua/maui/control.lua#If it returns false then it calls parent HandleEvent.

### Игра явно выключает hit test у текста

Подпись, лежащая поверх чужой кнопки, может перехватить клик, поэтому для подписей вызывают `DisableHitTest()`. Аргумент `recursive` нужен только для контрола с детьми.

Источник: fa:lua/maui/multilinetext.lua#self._text[line]:DisableHitTest()

### Контрол с альфой 0 не виден, но ловит мышь

Так сделаны невидимые зоны захвата у окна игры: `control:SetAlpha(0)` и включённый hit test.

Источник: fa:lua/maui/window.lua#Set alpha of resize controls to 0 so that they still get resize events, but are not seen

### SetFont меняет шрифт существующей надписи

Пересоздавать `Text` ради смены размера не нужно. Кегль внутри `SetFont` проходит через `ScaleNumber`, поэтому домножать его на масштаб интерфейса нельзя.

Источник: fa:lua/maui/text.lua#self._font._pointsize:Set(ScaleNumber(pointsize))
Наблюдение: надпись с кеглем 13 при `ui_scale` 0.8, 1 и 1.5 получила размер 10, 13 и 19, одна и та же строка заняла 107, 132 и 191 пиксель.

### CreateText использует buttonFont, если шрифт не передан

Сигнатура: `UIUtil.CreateText(parent, label, pointSize, font, dropshadow)`. Для обычного текста передают `UIUtil.bodyFont`.

Источник: fa:lua/ui/uiutil.lua#font = font or buttonFont

### Цвет задаётся строкой RrGgBb, AaRrGgBb или именем

Альфа идёт первой: `'D0101418'` это полупрозрачный цвет.

Источник: fa:engine/Core.lua#---@alias Color string `EnumColor` or hexcode like `'RrGgBb'`, or `'AaRrGgBb'` with transparency

### `GetFrame(0)` и `GetFrame(1)`

`GetFrame(0)` это корневой кадр основного монитора, `GetFrame(1)` второго. Количество кадров даёт `GetNumRootFrames()`.

Источник: fa:engine/User.lua#Returns the root UI frame for a given adapter.

### controls.lua возвращает таблицу, а не контрол

`import('/lua/ui/controls.lua').Get()` даёт обычную таблицу, которая переживает перезагрузку файла. Родителем панели она быть не может.

Источник: fa:lua/ui/controls.lua#--- Returns a table that persists between file reloads.

### Группа панели экономики доступна как GUI.bg

`import('/lua/ui/game/economy.lua').GUI.bg` заполняется при создании панели.

Источник: fa:lua/ui/game/economy.lua#GUI.bg = Group(savedParent)

### AddControlTooltip оборачивает текущий HandleEvent

Вызов запоминает обработчик, стоявший на этот момент. Обработчик, присвоенный позже, затирает подсказку, поэтому сначала задают `HandleEvent`, потом подсказку.

Источник: fa:lua/ui/game/tooltip.lua#control.oldHandleEvent = control.HandleEvent

### Подсказка принимает ключ или таблицу

Строка ищется в `/lua/ui/help/tooltips.lua`. Таблица `{text = ..., body = ...}` показывается как есть, поэтому мод может не трогать общий список.

Источник: fa:lua/ui/game/tooltip.lua#elseif type(ID) == 'table' then

### Перетаскивание делается через Dragger и PostDragger

`Dragger()` с `OnMove` и `OnRelease` запускается через глобальную функцию движка `PostDragger` из `HandleEvent`. Обработчики получают экранные координаты. Готовые образцы: `lua/ui/game/massfabs.lua` и `lua/maui/window.lua`.

```lua
if event.Type == 'ButtonPress' then
    local drag = Dragger()
    local offX = event.MouseX - self.Left()
    drag.OnMove = function(dragself, x, y) self.Left:Set(x - offX) end
    drag.OnRelease = function(dragself) GetCursor():Reset() drag:Destroy() end
    PostDragger(self:GetRootFrame(), event.KeyCode, drag)
    return true
end
```

Источник: fa:lua/ui/game/massfabs.lua#PostDragger(self:GetRootFrame(), event.KeyCode, drag)

### OnCancel переопределяют вместе с OnRelease

Базовый `OnCancel` только уничтожает dragger. Если `OnMove` менял курсор, вернуть его надо и здесь.

Источник: fa:lua/maui/window.lua#drag.OnCancel = function(dragself)

### Класс Window уже умеет перенос, ресайз и сохранение

Сигнатура: `Window(parent, title, icon, pin, config, lockSize, lockPosition, prefID, defaultPosition, textureTable)`. Перенос висит на `TitleGroup`, положение и размер пишутся в профиль под ключом `prefID`.

Источник: fa:lua/maui/window.lua#__init = function(self, parent, title, icon, pin, config, lockSize, lockPosition, prefID, defaultPosition, textureTable)

### Button рассчитан на текстуры

`HandleEvent` класса подставляет текстуру состояния при наведении и нажатии. Кнопка без файлов делается из `Bitmap` со `SetSolidColor`, своим `HandleEvent` и подписью с выключенным hit test.

Источник: fa:lua/maui/button.lua#self:SetTexture(self.mHighlight)

### Клик у Button проверяет, что курсор остался на кнопке

Класс ловит отпускание через `Dragger` и зовёт `OnClick` только при `mMouseOver`. Самодельная реакция на `ButtonRelease` такой проверки не имеет.

Источник: fa:lua/maui/button.lua#if self.mMouseOver and not self._isDisabled then

### Hide выключает отрисовку и hit test

После `Hide()` контрол не получает событий мыши.

Источник: fa:engine/User/CMauiControl.lua#--- Stops rendering and hit testing the control

### `Show()` родителя показывает и детей, скрытых по одному

`Show()` снова показывает всех детей контрола, в том числе тех, кого раньше скрыли их собственным `Hide()`. Ребёнок остаётся скрытым, только если его `OnHide(self, hidden)` при `hidden == false` вернул `true`. Поэтому после `Show()` окна выключенные дочерние контролы надо скрыть заново.

Источник: fa:lua/ui/game/multifunction.lua#if not hidden and not bg.checked then
Наблюдение: Overflow, сценарий стенда `scale_150`: панель с 2 видимыми строками из 7 свернули через `Hide()` окна и вернули через `Show()`. Без повторного скрытия снова видны 5 выключенных строк и 2 разделителя, а в логе предупреждения `circular dependency in lazy evaluation` от строк, которым не задали положение.

### `Group` не обрезает детей

`Group` это только `InternalCreateGroup`, средств обрезки у него нет; обрезка есть лишь у `Text` через `SetClipToWidth`. Если сжать панель, дочерние строки останутся на экране, поэтому их надо скрывать через `Hide()`.

Источник: fa:lua/maui/text.lua#SetClipToWidth = function(self, clipToWidth)

### Где лежат базовые элементы интерфейса

`CreateText`, `CreateBitmap`, `UIFile` находятся в `/lua/ui/uiutil.lua`, раскладка в `/lua/maui/layouthelpers.lua`, классы в `/lua/maui/group.lua`, `bitmap.lua`, `button.lua`, `dragger.lua`, `statusbar.lua`, `window.lua`. Реестр элементов игры это `Get(key)` в `/lua/ui/controls.lua`.

Источник: fa:lua/ui/uiutil.lua#function CreateText(parent, label, pointSize, font, dropshadow)

### Условия, при которых ReUI видит мод

Нужны поле `ReUI` и `ui_only = true`, а без `selectable = true` мод не загрузится и получит ошибку в чат. Запись `ReUI = "Имя=1.0.0"` ведёт на папку `/mods/Имя/`: в имени только буквы, цифры и точки, первой идёт буква. Uid найденного там `mod_info.lua` обязан совпасть с uid включённого мода.

Источник: ui-libs:mods/ReUI/Core/Modules/Loader.lua#if mod.ReUI and mod.ui_only then
Источник: ui-libs:mods/ReUI/Core/Modules/Loader.lua#local TAG_REGEX = '^(%a[%a%.%d]*)=(%d+%.%d+%.%d+)$'

### UMT и ReUI работают в одной партии

Наблюдение: сценарий `locked_unit` с активными ReUI v08, UMT v13 и ASE прошёл на стенде.

### Главный файл мода на ReUI

Загрузчик ищет `/mods/Имя/Имя.lua`, затем `/mods/Имя/Main.lua`. Версия берётся из глобала `Version` этого файла. Запись в `mod_info.lua` устарела и даёт `WARN`.

Источник: ui-libs:mods/ReUI/Core/Modules/Loader.lua#if moduleType ~= "file" and exists(path .. "/Main.lua") then

### `ReUI.Require` с недостижимой версией останавливает модуль до `Main`

Ошибка видна: она идёт в лог через `WARN`, а после создания интерфейса показывается в чате как `notify`. `Main` такого модуля не вызывается.

Источник: ui-libs:mods/ReUI/Core/Modules/Loader.lua#local msg = ("Module '%s' doesn't match required version: current: %s, required: %s%s")
Источник: ui-libs:mods/ReUI/Core/Modules/Loader.lua#to = 'notify',

### Чтение несуществующего имени в ReUI падает

Несуществующее поле корня и загруженного модуля бросает ошибку, запись в корень запрещена. Корень это прокси: модули лежат во внутренней таблице, поэтому `rawget(ReUI, "Units")` всегда даёт `nil`. Наличие проверяют так: `rawget(_G, "ReUI")`, затем `ReUI.Exists("ReUI.Units>=1.0.0")`.

Источник: ui-libs:mods/ReUI/Core/Modules/Loader.lua#error(("'ReUI.%s' doesn't exist"):format(k))
Источник: ui-libs:mods/ReUI/Core/Modules/Loader.lua#function __ReUI.Exists(tag)

### `ReUI.Core.Hook` надо вызвать из `Main`

Вызов только запоминает хук, а применяется он перед `CreateUI` заменой поля модуля. Хук, поставленный позже, уже не применится, а после `PostCreateUI` вызов бросает ошибку `Attempt to make hook after UI was created`. Ошибка при применении идёт в лог через `WARN`.

Источник: ui-libs:mods/ReUI/Core/Core.lua#error(("ReUI.Core.Hook: Attempt to make hook after UI was created. Hooks is '%s':%s")

### ReUI.Actions пересобирает карту клавиш

После создания интерфейса модуль вызывает `IN_ClearKeyMap()`, затем `IN_AddKeyMapTable(KeyMapper.GetKeyMappings())` и заново настраивает hotbuild. Клавиши, добавленные модом напрямую через `IN_AddKeyMapTable` раньше этого момента, будут сброшены.

Источник: ui-libs:mods/ReUI/Actions/Actions.lua#IN_AddKeyMapTable(KeyMapper.GetKeyMappings())

### `AddToMenu` и `IsIgnoredSelection` из ReUI лежат в модулях игры

ReUI добавляет их хуками в `tabs.lua` и `gamemain.lua`, поэтому это поля этих модулей, а не глобалы. Берут их через `import("/lua/ui/game/tabs.lua").AddToMenu`.

Источник: ui-libs:mods/ReUI/hook/lua/ui/game/tabs.lua#function AddToMenu(item)
