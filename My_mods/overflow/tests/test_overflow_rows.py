# -*- coding: utf-8 -*-
"""Тесты Overflow: выбор строк, страница UMT и раскладка панели.

МОД: My_mods\overflow\Overflow, версия 20.
Лежит рядом: папка tests\ в одной директории с папкой Overflow\.

ЧТО ПРОВЕРЯЕМ

1) rows.lua - какие строки показывать, что куда записывать, как готовые
   наборы разворачиваются и сворачиваются.

2) Options.lua - страница UMT. Главная проверка такая же, как была в
   ReclaimPause: OptionVar:Set держит значение В ПАМЯТИ и в профиль не пишет
   (mods/umt/modules/OptionVar.lua:24-30), а пишет только Save() при закрытии
   окна. Если страница читает профиль, игрок снимет галочку - мод её не
   увидит, - и страница доложит об успехе. На игре 2026-10-04 это стоило целого
   матча мод ReclaimPause (методичка 3.52). Проверка идёт через Set.

3) ui.lua - раскладка. Здесь она впервые СЧИТАЕТСЯ вместо того, чтобы
   браться из девяти констант, и ошибка выглядит как «панель с одной строкой
   наезжает сама на себя». Проверяем высоту панели и положение строк.

4) Отдельно - баг, найденный при переносе на v17: список BODY_KEYS не
   содержал eGo и mGo, поэтому строки "to allies" не прятались при
   сворачивании. Регрессия проверяется явно.

ГЛАВНОЕ ПРАВИЛО ЗАГЛУШЕК. Они гоняются по исходникам, а не по памяти, и
ошибки в них стоили отдельного цикла проверки (методичка 3.20). В частности:
Left - объект значения, его И вызывают, И ставят через :Set; PostDragger -
игровая глобальная функция; заглушка gamemain объявляется ДО загрузки ui.lua,
потому что import выполняется в момент загрузки модуля.

Запуск:  python test_overflow_rows.py
"""
import io
import os
import sys

from lupa import luajit21 as lupa

HERE = os.path.dirname(os.path.abspath(__file__))
MOD = os.path.join(os.path.dirname(HERE), "Overflow")
MOD = os.path.abspath(MOD)

# Проверяем, что читаем ИМЕННО тот мод. Один раз путь потерял уровень, тест
# продолжал работать и выглядел исправным - показывать путь дешевле, чем
# потом гадать, откуда взялись чужие числа.
if not os.path.exists(os.path.join(MOD, "modules", "ui.lua")):
    print("FAIL: mod ne nayden po puti: " + MOD)
    sys.exit(1)
print("Mod: " + MOD)


def rd(p):
    return io.open(p, encoding="utf-8").read()


rows_src = rd(os.path.join(MOD, "modules", "rows.lua"))
options_src = rd(os.path.join(MOD, "modules", "Options.lua"))
ui_src = rd(os.path.join(MOD, "modules", "ui.lua"))
# themes.lua нужен странице настроек: она читает из него названия тем. Без
# модуля Options.lua выходит из Main() досрочно (та же логика, что и для
# rows.lua), и страница не регистрируется вовсе.
themes_src = rd(os.path.join(MOD, "modules", "themes.lua"))

lua = lupa.LuaRuntime(unpack_returned_tuples=True)
make_env = lua.eval(
    "function() local t = {} setmetatable(t, {__index = _G}) return t end")
loader = lua.eval("""function(src, env)
  local f, err = loadstring(src)
  if not f then error(err) end
  setfenv(f, env)
  return f()
end""")

# ================================================================ окружение
STUBS = r'''
PROFILE = {}
msgs = {}

function LOG(m) msgs[#msgs + 1] = tostring(m) end

Prefs = {}
function Prefs.GetFromCurrentProfile(k) return PROFILE[k] end
function Prefs.SetToCurrentProfile(k, v) PROFILE[k] = v end
-- Настройка игры «цвет шрифта фракции» для themes.lua. По умолчанию она
-- выключена (options.lua:1221) - отдаём false, а не nil: настоящий
-- Prefs.GetOption возвращает значение по умолчанию (prefs.lua:116-132).
function Prefs.GetOption(k)
    if k == 'faction_font_color' then return false end
    return nil
end

-- Скины игры для themes.lua. Здесь важно только то, что модуль загружается:
-- проверку самих цветов ведёт test_overflow_theme.py, где скины описаны
-- полностью и по-настоящему.
SKINS = {
    default = {
        fontColor = 'FFbadbdb',
        bodyColor = 'FF6FAFAF',
        dialogCaptionColor = 'FFbadbdb',
        dialogButtonColor = 'FF69AB4D',
        highlightColor = 'FF7FA8A4',
        disabledColor = 'FF47555a',
        panelColor = 'FF4A5D6B',
        transparentPanelColor = 'AA4A5D6B',
    },
    uef = {}, aeon = {}, cybran = {}, seraphim = {},
}

function ForkThread(f) f() end
function WaitSeconds(n) end

-- ------------------------------------------------------- элементы интерфейса
MADE = {}

local function valueProp(getter, setter)
    -- Повторяет LazyVar игры: значение может быть задано числом, вычисляться
    -- функцией или быть связано с другим объектом значения.
    local p = {}
    p._get = getter
    p._set = setter
    p._link = nil
    setmetatable(p, {
        __call = function(self)
            if self._link then return self._link() end
            return self._get()
        end
    })
    function p:Set(v)
        if type(v) == 'function'
            or (type(v) == 'table' and getmetatable(v)) then
            self._link = v
        else
            self._link = nil
            self._set(v)
        end
    end
    return p
end

-- Предел размера, который мод отдал окну последним.
MINSIZE = nil

local function NewCtrl(kind, parent)
    local c = {}
    c._kind = kind
    c._parent = parent
    c._x, c._y, c._w, c._h = 0, 0, 0, 0
    c._hidden = false
    c._text = ''
    c._font = 0
    c._destroyed = false
    -- Depth - такой же объект значения, как Left: его умеют ЧИТАТЬ. Мод
    -- поднимает полосу заголовка над содержимым через client.Depth() + 1, а
    -- заглушка с одним Set() этот вызов не пережила бы.
    c.Depth = valueProp(function() return c._depth or 0 end,
                        function(v) c._depth = v end)
    function c:SetSolidColor(v) end
    function c:SetTexture(v) end
    -- SetUV зовётся сразу после SetTexture только в рамке Minimal. В остальных
    -- рамках подложки нет, но заглушка обязана уметь всё, что умеет игра.
    function c:SetUV(u0, v0, u1, v1) self._uv = { u0, v0, u1, v1 } end
    function c:SetAlpha(v) self._alpha = v end
    function c:SetColor(v) end
    function c:SetDropShadow(v) end
    function c:SetFont(f, s) self._font = s end
    function c:EnableHitTest(v) end
    function c:DisableHitTest(v) end
    function c:Hide() self._hidden = true end
    function c:Show() self._hidden = false end
    function c:Destroy() self._destroyed = true end
    function c:IsDestroyed() return self._destroyed end
    function c:GetRootFrame() return FRAME end
    function c:SetText(t) self._text = t end
    function c:GetText() return self._text end
    -- GetStringAdvance есть у текстового контрола (maui/text.lua; так же
    -- меряют в uiutil.lua:1054 и ui/dialogs/createunit.lua:2120). Мод меряет
    -- им ширину самой длинной строки. Без него проверка предела ширины
    -- проверяла бы заглушку, а не мод. Ширина растёт с длиной строки - как и
    -- настоящая, поэтому подмена короткой подписи на длинную видна.
    function c:GetStringAdvance(s)
        s = s or ''
        return #s * 6
    end
    function c:Left() return self._x end
    function c:Top() return self._y end
    c.Width = valueProp(function() return c._w end,
                        function(v) c._w = v end)
    c.Height = valueProp(function() return c._h end,
                         function(v) c._h = v end)
    -- Right и Bottom считаются из СОСЕДНИХ значений - ровно так их связывает
    -- ResetLayout в игре (control.lua:36-39). Читать поля _x/_w напрямую
    -- нельзя: когда Left и Width заданы ССЫЛКАМИ (крестик закрытия привязан к
    -- правому краю окна), поля остаются нулями и Right вышел бы нулевым.
    c.Right = valueProp(function() return c.Left() + c.Width() end,
                       function(v) c._w = v - c.Left() end)
    c.Bottom = valueProp(function() return c.Top() + c.Height() end,
                        function(v) c._h = v - c.Top() end)
    c.Left = valueProp(function() return c._x end,
                       function(v) c._x = v end)
    c.Top = valueProp(function() return c._y end,
                      function(v) c._y = v end)
    MADE[#MADE + 1] = c
    return c
end

UIUtil = {}
UIUtil.bodyFont = 'bodyFont'
function UIUtil.CreateText(parent, text, size, font)
    local c = NewCtrl('Text', parent)
    c._text = text or ''
    return c
end
function UIUtil.GetCursor(name)
    return { SetTexture = function() end, Reset = function() end }
end
-- UIFile ведёт путь в папку скина (uiutil.lua:423-487). В заглушке возвращаем
-- путь как есть: нас интересует сам вызов, а не разрешённый файл.
function UIUtil.UIFile(filespec) return filespec end

-- ------------------------------------------------------- класс Window (игры)
--
-- Настоящий класс лежит в lua/maui/window.lua. Мод вызывает из него:
-- конструктор, ClientGroup, Left/Top/Right/Bottom/Height как ОБЪЕКТЫ ЗНАЧЕНИЯ,
-- Depth:Set, DisableHitTest, SetMinimumResize, Hide, Show, Destroy.
-- Плюс присваивает OnClose и OnResize - тут это обычные поля.
local function NewWindow(parent)
    local w = NewCtrl('Window', parent)
    w._x, w._y, w._w, w._h = 8, 80, 340, 160
    w.ClientGroup = NewCtrl('ClientGroup', w)
    -- ГРАНИЦЫ КЛИЕНТСКОЙ ОБЛАСТИ. Класс Window отступает от краёв окна на
    -- рамку и на полосу заголовка (window.lua:287-293): слева и справа по 5,
    -- сверху 30, снизу 8. Заглушка обязана это повторить: без клиентской
    -- области не посчитать ни отступ строки под крестиком, ни проверку, что
    -- строки начинаются от верха окна.
    w.ClientGroup.Left:Set(function() return w.Left() + 5 end)
    w.ClientGroup.Right:Set(function() return w.Right() - 5 end)
    w.ClientGroup.Top:Set(function() return w.Top() + 30 end)
    w.ClientGroup.Bottom:Set(function() return w.Bottom() - 8 end)
    -- Предел размера запоминаем: без этого проверка "мод сообщил окну
    -- предел по содержимому" превратилась бы в проверку заглушки.
    function w:SetMinimumResize(a, b)
        MINSIZE = { a, b }
    end
    function w:DisableHitTest() end
    local function valueProp(getter, setter)
        local p = {}
        p._get = getter
        p._set = setter
        p._link = nil
        setmetatable(p, { __call = function(self)
            if self._link then return self._link() end
            return self._get()
        end })
        function p:Set(v)
            if type(v) == 'function'
                or (type(v) == 'table' and getmetatable(v)) then
                self._link = v
            else
                self._link = nil
                self._set(v)
            end
        end
        return p
    end
    w.Left   = valueProp(function() return w._x end, function(v) w._x = v end)
    w.Top    = valueProp(function() return w._y end, function(v) w._y = v end)
    -- Right и Bottom ЗАДАЮТ РАЗМЕР, как в MAUI: Right = Left + Width,
    -- Bottom = Top + Height. Класс Window задаёт размер именно так
    -- (window.lua:469-511) и Height не трогает вовсе. Заглушка с пустым
    -- setter не увидела бы этого и пропустила бы регресс.
    w.Right  = valueProp(function() return w._x + w._w end,
                         function(v) w._w = v - w._x end)
    w.Bottom = valueProp(function() return w._y + w._h end,
                         function(v) w._h = v - w._y end)
    w.Height = valueProp(function() return w._h end, function(v) w._h = v end)
    -- ПОЛОСА ЗАГОЛОВКА И КРЕСТИК. Класс Window заводит их ВСЕГДА
    -- (window.lua:219-251), даже когда название не передано: полоса высотой
    -- 30 px, крестик в её правом верхнем углу с отступом 10 по правому краю и
    -- 5 по верхнему. Мод растягивает полосу на всё окно, а строки под
    -- крестиком отступают вправо - значит заглушка обязана отдать и полосу, и
    -- крестик, и НАСТОЯЩИЕ границы крестика.
    w.TitleGroup = NewCtrl('TitleGroup', w)
    w.TitleGroup._h = 30
    w._closeBtn = NewCtrl('Button', w)
    w._closeBtn.Width:Set(function() return 20 end)
    w._closeBtn.Height:Set(function() return 20 end)
    w._closeBtn.Left:Set(function() return w.Right() - 30 end)
    w._closeBtn.Top:Set(function() return w.Top() + 5 end)

    -- ДЕВЯТЬ КУСКОВ РАМКИ. Класс создаёт их в ApplyWindowTextures
    -- (window.lua:176-184), и мод заливает их сплошным цветом в теме Minimal.
    -- Заглушка обязана их иметь, иначе поломка этой темы не видна.
    for _, part in ipairs({ 'window_tl', 'window_tr', 'window_tm',
                            'window_ml', 'window_m', 'window_mr',
                            'window_bl', 'window_bm', 'window_br' }) do
        w[part] = NewCtrl('Bitmap', w)
        w[part].solid = nil
    end
    w.Width  = valueProp(function() return w._w end, function(v) w._w = v end)
    return w
end

local Bitmap = function(parent) return NewCtrl('Bitmap', parent) end
local Group  = function(parent) return NewCtrl('Group', parent) end

LayoutHelpers = {}
function LayoutHelpers.SetDimensions(c, w, h) c._w = w c._h = h end
-- pixelScaleFactor - масштаб интерфейса игры. В заглушке единица: умножение
-- ничего не меняет, но проверка вызова и порядка вычислений сохраняется.
pixelScaleFactor = 1.0

-- Глобала MathFloor в ФАФ НЕТ. Каждый файл игры объявляет его сам:
-- local MathFloor = math.floor (maui/layouthelpers.lua:20 и другие).
-- Заглушка поэтому НЕ создаёт глобал, а берёт math.floor на месте вызова.
-- Если бы она объявила MathFloor как глобал, она бы скрыла ровно ту поломку,
-- из-за которой мод не грузился в версии 28.

-- Привязки повторяют layouthelpers.lua:384-420: отступ умножается на
-- pixelScaleFactor, результат берётся через MathFloor, а привязка ставится
-- SetFunction - то есть значение пересчитывается само.
function LayoutHelpers.AtLeftIn(c, p, leftOffset)
    if leftOffset and leftOffset ~= 0 then
        c.Left:Set(function() return math.floor(p.Left() + leftOffset * pixelScaleFactor) end)
    else
        c.Left:Set(function() return p.Left() end)
    end
end
function LayoutHelpers.AtTopIn(c, p, topOffset)
    if topOffset and topOffset ~= 0 then
        c.Top:Set(function() return math.floor(p.Top() + topOffset * pixelScaleFactor) end)
    else
        c.Top:Set(function() return p.Top() end)
    end
end
function LayoutHelpers.AtRightIn(c, p, rightOffset)
    if rightOffset and rightOffset ~= 0 then
        c.Right:Set(function() return math.floor(p.Right() - rightOffset * pixelScaleFactor) end)
    else
        c.Right:Set(function() return p.Right() end)
    end
end
function LayoutHelpers.AtLeftTopIn(c, p, x, y)
    LayoutHelpers.AtLeftIn(c, p, x)
    LayoutHelpers.AtTopIn(c, p, y)
end
function LayoutHelpers.AtHorizontalCenterIn(c, p) end
function LayoutHelpers.AtVerticalCenterIn(c, p) end
function LayoutHelpers.FillParent(c, p) end
function LayoutHelpers.InvScaleNumber(v) return v end
-- ScaleNumber есть в игре (layouthelpers.lua:57-59): им окно доращивается до
-- предела по содержимому (ui.lua, ApplyMinSize).
function LayoutHelpers.ScaleNumber(v) return math.floor(v * pixelScaleFactor) end

local Dragger = function()
    return { OnMove = nil, OnRelease = nil, Destroy = function() end }
end
-- Dragger запоминаем: иначе тест не может сдвинуть панель настоящим
-- движением мыши и проверить ресайз и ширину.
LAST_DRAG = nil
-- PostDragger - ИГРОВАЯ ГЛОБАЛЬНАЯ функция, ui.lua зовёт её без import.
function PostDragger(frame, key, drag) LAST_DRAG = drag end

FRAME = { Width = function() return 1920 end, Height = function() return 1080 end }
function GetFrame(i) return FRAME end
function GetCursor()
    return { SetTexture = function() end, Reset = function() end }
end

-- ------------------------------------------------------------- OptionVar.lua
--
-- Копия настоящего (mods/umt/modules/OptionVar.lua). Ключевое: Set меняет
-- значение В ПАМЯТИ и в профиль НЕ пишет.
local OptionVarMetaTable = {}
OptionVarMetaTable.__index = OptionVarMetaTable
function OptionVarMetaTable:__call() return self._v end
function OptionVarMetaTable:Set(v) self._v = v self:OnChange() end
function OptionVarMetaTable:Bind(fn) self.OnChange = fn self:OnChange() end
function OptionVarMetaTable:Option() return self._o end
function OptionVarMetaTable:Raw() return self end
function OptionVarMetaTable:Reset() end
function OptionVarMetaTable:OnChange() end
function OptionVarMetaTable:OnSave() end
function OptionVarMetaTable:Save()
    local t = PROFILE[self._m] or {}
    t[self._o] = self._v
    PROFILE[self._m] = t
    self:OnSave()
end
function OptionVar(modName, subOpt, default)
    if default == nil then
        error('Attempt to set option ' .. modName .. ':' .. subOpt ..
              ' to nil by default, dont do that!')
    end
    local t = PROFILE[modName] or {}
    local val = t[subOpt]
    if val == nil then
        t[subOpt] = default
        PROFILE[modName] = t
        val = default
    end
    return setmetatable({ _m = modName, _o = subOpt, _v = val },
                        OptionVarMetaTable)
end

-- --------------------------------------------------------------- Options.lua
PAGES = {}
BUILDS = {}

local OptValueMetaTable = {}
function OptValueMetaTable.IsInstance(v)
    return OptValueMetaTable == getmetatable(v)
end

local Option = {}
function Option.Opt(value)
    return setmetatable({ value = value }, OptValueMetaTable)
end
function Option.AddOptions(optName, title, buildTable)
    PAGES[optName] = { title = title }
    BUILDS[optName] = buildTable
end
function Option.Filter(name, optionVar, indent)
    return { type = 'filter', name = name, optionVar = optionVar,
             indent = indent }
end
function Option.Title(name, size, family, color, indent)
    return { type = 'title', name = name, indent = indent }
end
-- Options.Strings(name, items, optionVar, indent), Options.lua:111-119
function Option.Strings(name, items, optionVar, indent)
    return { type = 'strings', name = name, items = items,
             optionVar = optionVar, indent = indent }
end

local function LoadOptions(values, modName, prefix)
    local options = {}
    for optName, defaultValue in pairs(values) do
        local opt = prefix and (prefix .. '.' .. optName) or optName
        if OptValueMetaTable.IsInstance(defaultValue) then
            options[optName] = OptionVar(modName, opt, defaultValue.value)
        elseif type(defaultValue) == 'table' then
            options[optName] = LoadOptions(defaultValue, modName, opt)
        else
            options[optName] = OptionVar(modName, opt, defaultValue)
        end
    end
    return options
end

local OPTIONS_MAIN = nil
local function LoadOptionsFile(mods, key)
    OPTIONS_MAIN()
    return rawget(mods, key) ~= nil
end

local ModsMeta = {
    __newindex = function(self, key, value)
        rawset(self, key, LoadOptions(value, key))
    end,
    __index = function(self, key)
        if LoadOptionsFile(self, key) then return rawget(self, key) end
        error("No options for mod '" .. key .. "'")
    end,
}
Option.Mods = setmetatable({}, ModsMeta)
UMT = { Options = Option }

-- Ползунок UMT: OptionsWindow.lua:264-285. Целые числа, по умолчанию 1.
-- Подпись и границы сохраняем - по ним проверяется страница настроек.
function Option.Slider(name, lo, hi, inc, optionVar, indent)
    return { type = 'slider', name = name, optionVar = optionVar,
             min = lo, max = hi, inc = inc, indent = indent or 0 }
end

-- что и когда импортировали: страница настроек обязана НЕ трогать ui.lua
IMPORTED = {}

-- ------------------------------------------------------- ЦЕПОЧКА UMT ЦЕЛИКОМ
--
-- DiskFindFiles отдаёт то, что нашлось бы на диске. Сравнение
-- регистронезависимое, поэтому один и тот же ключ записан двумя
-- начертаниями папки: на диске папка лежит строчными, а UMT ищет по имени
-- мод-ключу. Именно так в игре нашлось '/mods/ase/modules/options.lua' по
-- запросу '/mods/ASE/'.
FOUND_ON_DISK = {
    ['/mods/overflow/|Main.lua']    = { '/mods/overflow/modules/main.lua' },
    ['/mods/overflow/|Options.lua'] = { '/mods/overflow/modules/Options.lua' },
    ['/mods/Overflow/|Options.lua'] = { '/mods/overflow/modules/Options.lua' },
}

function DiskFindFiles(dir, filename)
    local hit = FOUND_ON_DISK[dir .. '|' .. filename]
    if hit then return hit end
    return {}
end

-- UMT:Add - дословно mods/umt/modules/Mods.lua:16-18
UMT_MODS = {}
function UMT.Add(name) UMT_MODS[name] = true end

-- UMT:Load - дословно mods/umt/modules/Mods.lua:5-12
function UMT.Load(isReplay)
    for mod in pairs(UMT_MODS) do
        local files = DiskFindFiles('/mods/' .. mod .. '/', 'Main.lua')
        for _, file in pairs(files) do
            LOG('UMT: Loading file ' .. file)
            import(file).Main(isReplay)
        end
    end
end

-- Настоящий sync.lua нужен для проверки физического запрета. Он берёт эти
-- функции ГЛОБАЛАМИ при загрузке (sync.lua:79-86), поэтому объявления должны
-- существовать ДО загрузки модуля - иначе все они будут nil.
TICK = 0
INCOME_E = 0
INCOME_M = 0
function GameTick() return TICK end
function GetSimTicksPerSecond() return 10 end
function GetEconomyTotals()
    return { income = { ENERGY = INCOME_E, MASS = INCOME_M } }
end
function IsAlly(me, armyIdx) return armyIdx ~= me end

-- sync.lua зовёт GetFocusArmy на КАЖДОМ payload (sync.lua:508). Заглушки
-- не было: старая панель v3 брала армию сама, а v17 берёт готовый
-- результат и функции не знает. Без неё sync.lua набирал три ошибки
-- подряд и САМ снимал колбэк (sync.lua:527-531), после чего тест падал
-- с "attempt to call global 'SCORE_CB' (a nil value)". Виноват был не
-- мод, а заглушка - см. 3.20.
function GetFocusArmy() return 1 end

SCORE_CB = nil
function AddOnSyncHashedCallback(cb, event, id) SCORE_CB = cb end
function RemoveOnSyncHashedCallback(event, id) SCORE_CB = nil end

-- заглушка sync.lua. ui.lua читает её поля через rawget, поэтому это
-- именно таблица с полями, а не набор глобалов.
SYNCSTUB = {
    started = false,
    Start = function()
        SYNCSTUB.started = true
        return true
    end,
    GetResult = function()
        if SYNC_BROKEN then error('sync is broken') end
        return {
            ok = true,
            incoming = 100, outgoing = 20, own = 200,
            massIncoming = 0, massOutgoing = 30, massOwn = 300,
            reclaim = 5, massReclaim = 6,
        }
    end,
}

function import(p)
    IMPORTED[#IMPORTED + 1] = p
    if p == '/lua/user/prefs.lua' then return Prefs end
    if p == '/lua/ui/uiutil.lua' then return UIUtil end
    if p == '/lua/maui/bitmap.lua' then return { Bitmap = Bitmap } end
    if p == '/lua/maui/group.lua' then return { Group = Group } end
    if p == '/lua/maui/layouthelpers.lua' then return LayoutHelpers end
    if p == '/lua/maui/dragger.lua' then return { Dragger = Dragger } end
    if p == '/lua/maui/window.lua' then return { Window = NewWindow } end
    if p == '/lua/ui/game/gamemain.lua' then return GameMainStub end
    if p == '/mods/Overflow/modules/rows.lua' then return MODULES.rows end
    if p == '/mods/Overflow/modules/sync.lua' then return SYNCSTUB end
    if p == '/mods/Overflow/modules/themes.lua' then return MODULES.themes end
    if p == '/lua/skins/skins.lua' then return { skins = SKINS } end
    if p == '/mods/Overflow/modules/ui.lua' then return MODULES.ui end
    -- эти два пути приходят из DiskFindFiles, то есть от самой заглушки UMT
    if p == '/mods/overflow/modules/main.lua' then return MODULES.main end
    if p == '/mods/overflow/modules/Options.lua' then return MODULES.options end
    return {}
end

-- Факт сбора результата после последнего изменения набора строк.
ROWS_APPLIED = 0
'''

lua.execute(STUBS)
G = lua.globals()
G['MODULES'] = lua.eval('{}')

# ВАЖНО: заглушка gamemain обязана существовать ДО загрузки ui.lua.
# ui.lua делает `local GameMain = import('/lua/ui/game/gamemain.lua')` при
# загрузке. Объявленная позже, она дала бы nil, и OnCreateUI упал бы в pcall:
# панель создалась бы, но бит игры не подписался бы.
lua.execute(r"""
GameMainStub = {
    AddBeatFunction = function(f, throttle, id) BEAT = f end,
    RemoveBeatFunction = function(f, id)
        BEAT_REMOVED = f == BEAT
        BEAT = function() end
    end,
}
BEAT = nil
BEAT_REMOVED = false
""")

# ------------------------------------------------------------------ rows.lua
env_rows = make_env()
loader(rows_src, env_rows)
G['MODULES']['rows'] = env_rows
G['ROWS'] = env_rows

# --------------------------------------------------------------- themes.lua
# Загружаем ДО ui.lua и Options.lua: оба импортируют themes.lua, а при
# загрузке модуля import выполняется сразу. Если темы не loaded, ui.lua
# останется со встроенными цветами, а Options.lua выйдет из Main() досрочно.
env_themes = make_env()
loader(themes_src, env_themes)
G['MODULES']['themes'] = env_themes
G['THEMES'] = env_themes

# ------------------------------------------------------------------- ui.lua
env_ui = make_env()
loader(ui_src, env_ui)
G['MODULES']['ui'] = env_ui
G['U'] = env_ui

# --------------------------------------------------------------- Options.lua
env_opt = make_env()
loader(options_src, env_opt)
G['MODULES']['options'] = env_opt
G['OPTIONS_MAIN'] = env_opt['Main']

# ------------------------------------------- настоящий sync.lua (для теста)
sync_src = rd(os.path.join(MOD, "modules", "sync.lua"))
env_sync_real = make_env()
loader(sync_src, env_sync_real)
G['SYNC'] = env_sync_real

# ------------------------------------------------------- modules/main.lua (шим)
#
# Файл может отсутствовать - тогда это и есть провал, и тест обязан
# покраснеть с внятным текстом, а не упасть с FileNotFoundError.
shim_path = os.path.join(MOD, "modules", "main.lua")
shim_src = rd(shim_path) if os.path.exists(shim_path) else None

env_main = make_env()
if shim_src is not None:
    loader(shim_src, env_main)
G['MODULES']['main'] = env_main


def run(label, code):
    print(label)
    try:
        return lua.execute(code) or 0
    except Exception as e:
        print("  [FAIL] проверка упала: " + str(e))
        return 1


# ==================================================== 1. логика строк (rows.lua)
f1 = run("=== 1: rows.lua, выбор строк ===", r'''
local fails = 0
local function check(cond, label)
    if cond then
        print('  [OK  ] ' .. label)
    else
        fails = fails + 1
        print('  [FAIL] ' .. label)
    end
end

local BOXES = { 'eOverflow', 'eGo', 'eOwn', 'mOverflow', 'mGo', 'mOwn',
                'total' }

check(ROWS.HowManyRows() == 7, 'строк ровно семь (получено ' ..
      tostring(ROWS.HowManyRows()) .. ')')

local orderOk = true
for i = 1, #BOXES do
    if ROWS.RowKeyAt(i) ~= BOXES[i] then orderOk = false end
end
check(orderOk, 'порядок строк совпадает с порядком на панели')

-- Compatibility: there is no profile yet. The panel must show the default set
-- from the mod, otherwise it would disappear after a mod update for everyone
-- who never opened the settings.
PROFILE['Overflow'] = nil
local def = ROWS.RowDefaults()
local vis = ROWS.VisibleRows()
local asDefault = true
local anyOn = false
for i = 1, #BOXES do
    if vis[BOXES[i]] ~= def[BOXES[i]] then asDefault = false end
    if def[BOXES[i]] then anyOn = true end
end
check(asDefault, 'без настроек видны строки по умолчанию')
check(anyOn, 'по умолчанию видна хотя бы одна строка')

-- «Поля нет» и «поле = false» - РАЗНЫЕ вещи. Первое значит «как по умолчанию».
PROFILE['Overflow'] = { eOverflow = false }
vis = ROWS.VisibleRows()
check(vis.eOverflow == false, 'явно снятая строка скрыта')
check(vis.eGo == def.eGo and vis.mGo == def.mGo and vis.total == def.total,
      'отсутствующие поля читаются как значение по умолчанию, а не как «скрыть»')

-- Запись не должна затирать чужие поля того же профиля: им пользуется UMT.
PROFILE['Overflow'] = { preset = 'Все строки', eOverflow = true }
vis = {}
for i = 1, #BOXES do vis[BOXES[i]] = (BOXES[i] == 'eGo') end
check(ROWS.SaveRows(vis) == true, 'SaveRows сообщил об успехе')
check(PROFILE['Overflow'].preset == 'Все строки',
      'SaveRows не затёр поле preset, принадлежащее UMT')
check(PROFILE['Overflow'].eGo == true and PROFILE['Overflow'].eOverflow == false,
      'SaveRows записал именно переданные флаги')

-- Подпись набора: панель сравнивает её со своей и перекладывает геометрию
-- только при изменении. Подпись обязана различать разные наборы.
local sigAll = ROWS.RowsSignature({ eOverflow = true, eGo = true,
    eOwn = true, mOverflow = true, mGo = true, mOwn = true, total = true })
local sigOne = ROWS.RowsSignature({ eOverflow = true, eGo = false,
    eOwn = false, mOverflow = false, mGo = false, mOwn = false, total = false })
check(sigAll ~= sigOne, 'подпись набора различает два разных набора')
check(ROWS.RowsSignature({ eOverflow = true, eGo = true, eOwn = true,
    mOverflow = true, mGo = true, mOwn = true, total = true }) == sigAll,
      'подпись одного и того же набора стабильна')

-- Все готовые наборы обязаны разворачиваться и сворачиваться без потерь.
local names = ROWS.PresetNames()
local hasAllRows = false
for i = 1, #names do
    if names[i] == 'Все строки' then hasAllRows = true end
end
check(hasAllRows, 'в списке есть набор «Все строки»')
local bad = ''
for i = 1, #names do
    local label = names[i]
    if label ~= ROWS.PresetOther() then
        local flags = ROWS.PresetByName(label)
        if flags == nil then
            bad = bad .. label .. '(nil) '
        elseif ROWS.PresetFor(flags) ~= label then
            bad = bad .. label .. '(round-trip) '
        end
    end
end
check(bad == '', 'каждый набор разворачивается и сворачивается сам в себя' ..
      (bad == '' and '' or (' НАРУШЕНО: ' .. bad)))

-- Служебный элемент не набор: разворачивать его нельзя, иначе щелчок по
-- нему снёс бы все галочки.
check(ROWS.PresetByName(ROWS.PresetOther()) == nil,
      'служебный «Другой набор» не разворачивается в набор')

-- Пустой набор обязан совпасть с «Ничего не показывать», а не со служебным.
local empty = {}
for i = 1, #BOXES do empty[BOXES[i]] = false end
check(ROWS.PresetFor(empty) == 'Ничего не показывать',
      'пустой набор опознан как «Ничего не показывать», а не как служебный')

-- Набор, которого нет в списке, обязан давать nil.
local odd = { eOverflow = true, eGo = true, eOwn = false, mOverflow = false,
              mGo = false, mOwn = true, total = true }
check(ROWS.PresetFor(odd) == nil,
      'нестандартная комбинация не опознана ни за один набор (nil)')

-- ПРАВИЛО: первый набор обязан совпадать со значением по умолчанию, иначе
-- UMT молча перепишет его и сохранит.
local first = ROWS.PresetNames()[1]
local firstFlags = ROWS.PresetByName(first)
local defMatch = true
for i = 1, #BOXES do
    if (def[BOXES[i]] and true or false) ~= (firstFlags[BOXES[i]] and true or false) then
        defMatch = false
    end
end
check(defMatch, 'первый набор списка совпадает со значением по умолчанию')

-- Названия строк для окна настроек: у каждой строки должно быть своё,
-- иначе галочки окажутся безымянными или с чужой подписью.
local noTitle = ''
for i = 1, #BOXES do
    local t = ROWS.RowTitleOf(BOXES[i])
    if type(t) ~= 'string' or t == '' then noTitle = noTitle .. BOXES[i] .. ' ' end
end
check(noTitle == '', 'у каждой строки есть название для окна настроек' ..
      (noTitle == '' and '' or (' НЕТ: ' .. noTitle)))

return fails
''')

# ================================================== 2. страница настроек UMT
print("")
f2 = run("=== 2: Options.lua, страница настроек ===", r'''
local fails = 0
local function check(cond, label)
    if cond then
        print('  [OK  ] ' .. label)
    else
        fails = fails + 1
        print('  [FAIL] ' .. label)
    end
end

local BOXES = { 'eOverflow', 'eGo', 'eOwn', 'mOverflow', 'mGo', 'mOwn',
                'total' }

-- Чистый профиль. Обнулять через Mods[] нельзя: __newindex срабатывает и на
-- nil, а LoadOptions(nil) упал бы. Только rawset.
PROFILE['Overflow'] = nil
rawset(UMT.Options.Mods, 'Overflow', nil)
IMPORTED = {}

local okPage, errPage = pcall(OPTIONS_MAIN)
check(okPage, 'Main() страницы отработал без исключения' ..
      (okPage and '' or (': ' .. tostring(errPage))))
if not okPage then return fails end

-- ПОРЯДОК ЗАГРУЗКИ. Страница обязана НЕ импортировать ui.lua: неизвестно,
-- UMT ли загрузится раньше интерфейса игры или позже, и импорт поймал бы
-- ещё не до конца выполненный модуль - ровно случай из методички 3.23.
local touchedUi = false
for i = 1, #IMPORTED do
    if IMPORTED[i] == '/mods/Overflow/modules/ui.lua' then touchedUi = true end
end
check(not touchedUi, 'страница НЕ импортирует ui.lua (порядок загрузки)')

local opts = UMT.Options.Mods['Overflow']
check(opts ~= nil, 'страница зарегистрирована в UMT.Options.Mods')
check(BUILDS['Overflow'] ~= nil, 'окно создано через AddOptions')

local build = BUILDS['Overflow']
if build == nil then return fails + 1 end

local boxesOk = true
for i = 1, #BOXES do
    local v = opts[BOXES[i]]
    if v == nil or type(v.Bind) ~= 'function' then boxesOk = false end
end
check(boxesOk, 'все семь строк - OptionVar с методом Bind')
check(opts.preset ~= nil and type(opts.preset.Bind) == 'function',
      'выпадающий список - OptionVar с методом Bind')

-- Каждая галочка обязана быть привязана к СВОЕМУ полю, иначе щелчок по ней
-- менял бы чужое.
local mismatched = ''
local filters = 0
local stringsLine = nil
local themeLine = nil
for i = 1, #build do
    local line = build[i]
    if line.type == 'filter' then
        filters = filters + 1
        local nm = line.optionVar:Option()
        if line.optionVar ~= opts[nm] then mismatched = nm .. ' ' end
    elseif line.type == 'strings' then
        -- Списка теперь два: тема и наборы строк. Запоминаем ОБА, иначе
        -- проверка привязки темы молча проходила бы, ни на что не глядя.
        --
        -- Признак берём по themeLine, а не по stringsLine: в первую ветку мы
        -- попадаем раньше, чем stringsLine успевает что-то получить, и
        -- проверка `stringsLine == nil` оставалась бы верной навсегда.
        if themeLine == nil then themeLine = line else stringsLine = line end
    end
end
-- Галочек теперь ВОСЕМЬ, а не семь: семь строк панели плюс переключатель
-- мигания. Он сделан тем же типом Filter - это та же галочка, и проверка
-- привязки снизу автоматически накрывает и его.
-- Галочек теперь девять: семь строк, мигание и «только числа».
check(filters == 9, 'в окне девять галочек: семь строк, мигание и только числа (получено ' ..
      tostring(filters) .. ')')
check(mismatched == '', 'каждая галочка привязана к своему полю' ..
      (mismatched == '' and '' or (': ' .. mismatched)))
-- Проверяем не только равенство, но и ЧТО ОНО ЕСТЬ. Иначе проверка
-- проходит как nil == nil: стоит выбросить из объявления полей строку
-- `theme = Opt(looks[1])`, и страница соберётся как ни в чём не бывало -
-- ровно так это и выглядит у игрока.
check(stringsLine ~= nil and stringsLine.optionVar ~= nil
      and stringsLine.optionVar == opts.preset,
      'выпадающий список привязан к полю preset')
check(themeLine ~= nil and themeLine.optionVar ~= nil
      and opts.theme ~= nil and themeLine.optionVar == opts.theme,
      'выпадающий список оформления привязан к полю theme')
check(stringsLine ~= nil and stringsLine.items ~= nil and
      stringsLine.items[1] == opts.preset(),
      'текущее значение списка есть среди его пунктов - иначе UMT молча ' ..
      'перепишет его первым пунктом и сохранит')
check(opts.preset() == ROWS.PresetNames()[1],
      'значение списка по умолчанию - первый набор')

-- Имитируем игрока: выбираем «Только E ally overflow».
-- Set держит значение в памяти и в профиль НЕ пишет (OptionVar.lua:24-30),
-- поэтому если страница читает профиль - мод увидит старое.
opts.preset:Set('Только E ally overflow')

local prof = PROFILE['Overflow']
check(prof.eOverflow == true, 'после выбора набора видна E ally overflow')
check(prof.eGo == false and prof.eOwn == false and prof.mOverflow == false
      and prof.mGo == false and prof.mOwn == false and prof.total == false,
      'остальные шесть строк сняты, как просил игрок')

-- Мод читает профиль, а страница обязана записать туда же, что показала
-- галочкам. Любое расхождение - это ровно баг ReclaimPause v21.
local liveMismatch = ''
for i = 1, #BOXES do
    if (opts[BOXES[i]]() and true or false) ~= (prof[BOXES[i]] and true or false) then
        liveMismatch = liveMismatch .. BOXES[i] .. ' '
    end
end
check(liveMismatch == '',
      'профиль и живое значение OptionVar совпадают по всем семи строкам' ..
      (liveMismatch == '' and '' or (': расход ' .. liveMismatch)))

-- Теперь игрок ставит галочку руками. Список обязан перестать врать.
opts.mGo:Set(true)
check(opts.preset() == ROWS.PresetOther(),
      'после ручной правки список показывает «Другой набор», а не прежний')
check(PROFILE['Overflow'].mGo == true, 'ручная галочка дошла до профиля')

-- Возврат к готовому набору.
opts.preset:Set('Все строки')
local raised = true
for i = 1, #BOXES do
    if opts[BOXES[i]]() ~= true then raised = false end
end
check(raised, 'набор «Все строки» поднял обратно все семь галочек')
check(PROFILE['Overflow'].total == true, 'и записал это в профиль')

local joined = table.concat(msgs, ' | ')
check(string.find(joined, 'UMT options page registered') ~= nil,
      'страница отписалась в лог, что зарегистрирована')
check(string.find(joined, 'FAILED') == nil, 'в логе нет ни одной строки FAILED')

return fails
''')

# ============================================ 3. раскладка панели (ui.lua)
print("")
f3 = run("=== 3: ui.lua, раскладка под выбранные строки ===", r'''
local fails = 0
local function check(cond, label)
    if cond then
        print('  [OK  ] ' .. label)
    else
        fails = fails + 1
        print('  [FAIL] ' .. label)
    end
end

-- Подписи, которые держит на экране Render: он зовётся из Update, то есть
-- из бита игры. Так мы узнаём, какие строки панель показывает.
local CAPTIONS = {
    eOverflow = 'E ally overflow: 100.0 E/s',
    eGo       = 'E to allies: 20.0 E/s',
    eOwn      = 'E own production: 200.0 E/s',
    mOverflow = 'M ally overflow: 0.0 M/s',
    mGo       = 'M to allies: 30.0 M/s',
    mOwn      = 'M own production: 300.0 M/s',
    total     = 'reclaim E 5.0 / M 6.0 /s',
}
local CHROME = { ['Overflow'] = 1, ['x'] = 1, ['-'] = 1, ['+'] = 1,
                 ['100%'] = 1 }

local function shownCaptions()
    local out = {}
    for i = 1, #MADE do
        local c = MADE[i]
        if c._kind == 'Text' and not c._hidden and c._text ~= '' then
            out[c._text] = c
        end
    end
    return out
end

-- Сколько строк данных на экране: подписи данных минус надписи шапки.
local function shownData()
    local n = 0
    for txt, _ in pairs(shownCaptions()) do
        if CHROME[txt] == nil then n = n + 1 end
    end
    return n
end

local function shownDividers()
    local n = 0
    for i = 1, #MADE do
        local c = MADE[i]
        if c._kind == 'Bitmap' and not c._hidden and c._h == 1 then
            n = n + 1
        end
    end
    return n
end

local function setRows(flags)
    local vis = {}
    for k, v in pairs(flags) do vis[k] = v end
    ROWS.SaveRows(vis)
    if BEAT then BEAT() end
end

-- The layout is checked on the full set, so the test enables all seven rows
-- itself: the default set of the mod is shorter.
PROFILE['Overflow'] = nil
local allRows = {}
for i = 1, ROWS.HowManyRows() do allRows[ROWS.RowKeyAt(i)] = true end
ROWS.SaveRows(allRows)
local okUi, errUi = pcall(U.OnCreateUI)
check(okUi, 'OnCreateUI отработал без исключения' ..
      (okUi and '' or (': ' .. tostring(errUi))))
if not okUi then return fails end
check(SYNCSTUB.started, 'sync.lua получил команду Start')

-- Ищем ОКНО, а не группу: после перехода на класс Window панель строится
-- контейнером 'Window', а обычных групп в modе больше нет.
local panel = nil
for i = 1, #MADE do
    if MADE[i]._kind == 'Window' then panel = MADE[i] end
end
check(panel ~= nil, 'окно создано')

if BEAT then BEAT() end

local t = shownCaptions()
check(t[CAPTIONS.eOverflow] ~= nil, 'на экране строка E ally overflow')
check(t[CAPTIONS.eGo] ~= nil, 'на экране строка E to allies')
check(t[CAPTIONS.total] ~= nil, 'на экране строка реклейма')
check(shownData() == 7, 'на экране все семь строк (строк данных: ' ..
      tostring(shownData()) .. ')')
local hSeven = panel and panel._h or -1
check(hSeven > 0, 'при семи строках высота окна положительная (получено ' ..
      tostring(hSeven) .. ')')
check(shownDividers() == 2, 'при всех строках на месте оба разделителя (' ..
      tostring(shownDividers()) .. ')')

-- ГЛАВНЫЙ СЛУЧАЙ ПОЖЕЛАНИЯ: оставлена одна строка.
setRows({ eOverflow = true })
t = shownCaptions()
check(t[CAPTIONS.eOverflow] ~= nil, 'при одной строке E ally overflow осталась')
check(shownData() == 1,
      'больше на экране ничего нет (строк данных: ' .. tostring(shownData()) .. ')')
local hOne = panel and panel._h or -1
check(hOne < hSeven,
      'с одной строкой окно должно быть ниже, чем с семью: ' ..
      tostring(hOne) .. ' против ' .. tostring(hSeven))
check(shownDividers() == 0,
      'над одиночной строкой не осталось разделителя (найдено: ' ..
      tostring(shownDividers()) .. ')')

-- Ничего не показывать: панель равна шапке.
setRows({})
check(shownData() == 0,
      'при пустом наборе строк данных на экране нет (строк: ' ..
      tostring(shownData()) .. ')')
local hNone = panel and panel._h or -1
check(hNone <= hOne,
      'при пустом наборе окно должно быть не выше окна с одной строкой: ' ..
      tostring(hNone) .. ' против ' .. tostring(hOne))

-- Возврат к полному набору и проверка координат.
setRows({ eOverflow = true, eGo = true, eOwn = true, mOverflow = true,
          mGo = true, mOwn = true, total = true })
t = shownCaptions()
local allSeven = true
for k, _ in pairs(CAPTIONS) do
    if t[CAPTIONS[k]] == nil then allSeven = false end
end
check(allSeven, 'после возврата все семь строк на месте')
check(panel._h == hSeven,
      'после возврата всех строк высота окна вернулась (' ..
      tostring(panel._h) .. ' против ' .. tostring(hSeven) .. ')')

-- Координата строки берётся ВЫЗОВОМ Top(): раскладка привязывает её
-- функцией к ClientGroup окна, поэтому за полем _y ничего не лежит.
local function y(cap)
    local c = t[cap]
    if not c then return -1 end
    if c.Top then return c.Top() end
    return c._y
end
local ys = { y(CAPTIONS.eOverflow), y(CAPTIONS.eGo), y(CAPTIONS.eOwn),
             y(CAPTIONS.mOverflow), y(CAPTIONS.mGo), y(CAPTIONS.mOwn),
             y(CAPTIONS.total) }
-- Проверяем ШАГ и ПОРЯДОК, а не абсолютные координаты. Строки привязаны к
-- ClientGroup окна функциями, поэтому их Y зависит от положения окна на
-- экране и меняется вместе с ресайзом. Неизменны только порядок сверху вниз
-- и шаг между соседними строками (L.ROW_STEP = 14).
--
-- Шаг проверяется внутри ресурса: перед разделителем он всегда 14, а после
-- разделителя добавляется DIV_POST, поэтому шаг 18 там - так и задумано.
local ROW_STEP = 14
local coordOk = true
local got = ''
for i = 1, 7 do
    got = got .. ys[i] .. ' '
    -- Порядок проверок важен: `ys[i] <= ys[i-1] and i > 1` упало бы на
    -- первом элементе, потому что Lua вычисляет ОПЕРАНДЫ слева направо и
    -- доходит до сравнения с nil раньше, чем до проверки i > 1.
    if i > 1 and ys[i] <= ys[i - 1] then coordOk = false end
end
check(coordOk, 'строки идут сверху вниз без наложений (' .. got .. ')')

local stepOk = true
for _, i in pairs({ 1, 2, 4, 5 }) do
    if ys[i + 1] - ys[i] ~= ROW_STEP then stepOk = false end
end
check(stepOk, 'шаг между строками внутри ресурса одинаковый (' ..
      (ys[2] - ys[1]) .. ', ' .. (ys[5] - ys[4]) .. ')')

-- Разделитель должен стоять между ресурсами и отодвигать вторую строку.
check(ys[4] - ys[3] > ROW_STEP,
      'разделитель раздвигает второй ресурс (' .. (ys[4] - ys[3]) .. ')')

-- ШИРИНА ЧЕРЕЗ НАСТОЯЩУЮ ПРОТЯЖКУ.
--
-- Прямая запись panel._w ничего бы не проверяла: G.width в моде остался бы
-- nil, и ApplyLayout честно вернул бы 340. Идём путём игрока: жмём невидимый
-- край, сдвигаем Dragger, отпускаем.
--
-- Край находится по SetAlpha(0): ровно так он сделан в моде, чтобы остаться
-- кликабельным, но незаметным.
-- РЕСАЙЗ ПЕРЕШЁЛ К КЛАССУ WINDOW. Нашей невидимой зоны захвата больше нет,
-- и искать её нечего. Вместо этого проверяем, что окно собрано нужным
-- способом и что у него есть минимальный размер: без него ресайз утащил бы
-- окно в ноль вместе с подписями.
check(panel ~= nil, 'окно на месте после всех проверок')
check(panel ~= nil and panel.OnResize ~= nil,
      'у окна есть обработчик ресайза')
check(panel ~= nil and panel.OnClose ~= nil,
      'у окна есть обработчик закрытия - он сворачивает панель')

-- ВЫСОТА, ПОДОБРАННАЯ ИГРОКОМ. Правило: потянул окно за край - высота
-- запомнилась и больше не срезается подгонкой под содержимое; перенос окна
-- высоту не меняет.
--
-- Проверяем ровно то, что произошло в игре: игрок растянул окно, затем что-то
-- сбило высоту, и после переноса она обязана вернуться.
if panel ~= nil and panel.OnResizeSet and panel.OnMoveSet then
    panel._h = 250
    panel.OnResizeSet(panel)
    check(panel._h == 250,
          'после ресайза высота игрока запомнена (' .. tostring(panel._h) .. ')')

    -- Имитируем то, что делал класс при переносе: сбросили высоту.
    panel._h = 90
    check(panel._h == 90, 'сброс высоты действительно произошёл (проверка замкнута)')

    panel.OnMoveSet(panel)
    check(panel._h == 250,
          'после переноса высота игрока вернулась, а не осталась сбитой (' ..
          tostring(panel._h) .. ')')
end

-- ПОЛОСА ЗАГОЛОВКА, КРЕСТИК И ПРЕДЕЛ РАЗМЕРА (версия 31)
--
-- Что было сломано и что здесь проверяется:
--
-- 1. Класс Window заводит ПУСТУЮ полосу заголовка в 30 px ВСЕГДА
--    (window.lua:219-226), даже когда название не передано. Строки же
--    начинались НИЖЕ неё (window.lua:288). На окне в 52 px тридцать
--    пикселей были пустыми, трём строкам нужно 40, и текст вылезал за рамку.
-- 2. Предел размера был жёстким числом 200 по ширине: панель не сжималась
--    дальше, хотя текст был заметно короче окна.
-- ============================================================================

check(panel.ClientGroup.Top() == panel.Top(),
      'строки начинаются от ВЕРХА окна, а не под пустой полосой заголовка (' ..
      'ClientGroup.Top = ' .. tostring(panel.ClientGroup.Top()) ..
      ', Top окна = ' .. tostring(panel.Top()) .. ')')

check(panel.TitleGroup ~= nil
      and panel.TitleGroup.Height() == panel.Bottom() - panel.Top(),
      'полоса заголовка растянута на всё окно, иначе окно не сдвинуть (' ..
      tostring(panel.TitleGroup and panel.TitleGroup.Height()) .. ')')

-- КРЕСТИК ЗАКРЫТИЯ. Он висит в правом верхнем углу окна и перекрывает
-- ВЕРХНИЕ строки: пустой полосы, которая раньше их разводила, больше нет.
-- Поэтому строка под ним отступает вправо сильнее, чем нижние.
local function ctrlFor(text)
    for i = 1, #MADE do
        local c = MADE[i]
        if c._kind == 'Text' and c._text == text then return c end
    end
    return nil
end

local function setAllSeven()
    setRows({ eOverflow = true, eGo = true, eOwn = true, mOverflow = true,
              mGo = true, mOwn = true, total = true })
end

setAllSeven()
local topRow = ctrlFor(CAPTIONS.eOverflow)
local lowRow = ctrlFor(CAPTIONS.eOwn)
check(topRow ~= nil and lowRow ~= nil and topRow.Right() < lowRow.Right(),
      'верхняя строка отступает под крестик сильнее нижних (верх ' ..
      tostring(topRow and topRow.Right()) .. ', низ ' ..
      tostring(lowRow and lowRow.Right()) .. ')')

-- ПРЕДЕЛ РАЗМЕРА. Мод обязан сообщить окну предел ПО СОДЕРЖИМОМУ: без него
-- окно сжимается до 52 px и текст уезжает за рамку.
--
-- MINSIZE сбрасываем перед каждым замером и МЕНЯЕМ НАБОР СТРОК между ними:
-- предел считается в LayoutRows при смене набора, поэтому замер после смены
-- честно показывает работу мода, а не оставшееся с прошлого раза значение.
MINSIZE = nil
setRows({ eGo = true })
local one = MINSIZE
MINSIZE = nil
setAllSeven()
local all = MINSIZE
check(all ~= nil and all[1] > 0 and all[2] > 0,
      'мод сообщил окну предел размера (' .. tostring(all and all[1]) ..
      ' x ' .. tostring(all and all[2]) .. ')')

-- Семь строк - это 8 + 7*14 - 14 + 4 = 96 px под текст плюс 8 px нижней
-- рамки. Предел меньше 96 означал бы, что текст не поместится.
check(all ~= nil and all[2] >= 96,
      'предел высоты не меньше, чем нужно семи строкам (' ..
      tostring(all and all[2]) .. ')')

check(one ~= nil and all ~= nil and one[2] < all[2],
      'предел ВЫСОТЫ считается по числу строк: с одной строкой он ниже (' ..
      tostring(one and one[2]) .. ' против ' .. tostring(all and all[2]) .. ')')
-- Подпись 'E to allies: 20.0 E/s' КОРОЧЕ, чем 'E own production: 200.0 E/s',
-- поэтому и предел ширины обязан быть меньше. Жёсткое число этого не покажет:
-- с ним оба замера совпали бы.
check(one ~= nil and all ~= nil and one[1] < all[1],
      'предел ШИРИНЫ считается ПО ТЕКСТУ, а не задан числом: с одной ' ..
      'короткой строкой он меньше (' .. tostring(one and one[1]) ..
      ' против ' .. tostring(all and all[1]) .. ')')

-- Возвращаем полный набор: за этим блоком идут проверки сворачивания.
setAllSeven()

-- СТРОКИ РАЗЪЕЗЖАЮТСЯ ПО ВЫСОТЕ ПАНЕЛИ (версия 33).
--
-- Игрок выбрал: больше панель - больше промежутки между строками. Промежутки
-- делят ОСТАТОК места поровну, поэтому нижняя строка всегда встаёт ровно по
-- нижнему полю, а верхняя остаётся у верхнего края.
--
-- Идём ПУТЁМ КЛАССА WINDOW: сначала задаётся новый размер, потом зовётся
-- OnResize (window.lua:324-326).
--
-- ВЫСОТУ ЗАДАЁМ ЧИСЛОМ, а не через подгонку: к этому месту теста G.wantH уже
-- выставлен проверкой переноса выше, и «естественная» высота тут не
-- естественная. С числом раскладка предсказуема.
setAllSeven()
local row1 = ctrlFor(CAPTIONS.eOverflow)
local rowN = ctrlFor(CAPTIONS.total)

-- Разделитель ищем по РОДИТЕЛЮ, а не по высоте: куски рамки окна - тоже
-- Bitmap, и по одному лишь Height их от разделителя не отличить.
local div1 = nil
for i = 1, #MADE do
    local c = MADE[i]
    if c._kind == 'Bitmap' and c._parent == panel.ClientGroup then
        if div1 == nil or c.Top() < div1.Top() then div1 = c end
    end
end

check(row1 ~= nil and rowN ~= nil,
      'строки нашлись для проверки растяжения')

if row1 ~= nil and rowN ~= nil then
    -- НИЖНЕЕ ПОЛЕ. Число своё у мода (PAD_BOTTOM), в тесте повторяется, чтобы
    -- проверка была о РАСПРЕДЕЛЕНИИ, а не о самой себе.
    local PAD_BOTTOM = 4

    local function bottomRow()
        return rowN.Top() + 14
    end

    local function byBottom()
        return panel.ClientGroup.Bottom() - PAD_BOTTOM
    end

    local function measure(h)
        panel._h = h
        panel.OnResize(panel)
        return row1.Top(), rowN.Top()
    end

    local r1a, rNa = measure(300)
    local d1a = -1
    if div1 ~= nil then d1a = div1.Top() end

    check(r1a == panel.ClientGroup.Top() + 8,
          'верхняя строка остаётся у верхнего края панели (' ..
          tostring(r1a) .. ' при крае ' .. tostring(panel.ClientGroup.Top()) .. ')')
    check(math.abs(bottomRow() - byBottom()) <= 1,
          'нижняя строка встаёт по нижнему полю панели (низ строки ' ..
          tostring(bottomRow()) .. ', поле ' .. tostring(byBottom()) .. ')')

    -- РАСТЯНУЛИ ЕЩЁ - промежутки обязаны вырасти, а низ строки снова лечь по
    -- полю. Это и отличает распределение от «сдвинуть весь блок вниз».
    local r1b, rNb = measure(400)
    local d1b = -1
    if div1 ~= nil then d1b = div1.Top() end

    check(r1b == r1a,
          'верхняя строка не съезжает и на большей высоте (' ..
          tostring(r1a) .. ' -> ' .. tostring(r1b) .. ')')
    check(rNb > rNa,
          'нижняя строка уезжает вниз вместе с растяжением панели (' ..
          tostring(rNa) .. ' -> ' .. tostring(rNb) .. ')')
    check(math.abs(bottomRow() - byBottom()) <= 1,
          'и на большей высоте низ строки ложится по нижнему полю (' ..
          tostring(bottomRow()) .. ' против ' .. tostring(byBottom()) .. ')')
    check(div1 ~= nil and d1b > d1a,
          'разделитель едет вместе со строками (' ..
          tostring(d1a) .. ' -> ' .. tostring(d1b) .. ')')

    -- И обратно: прежняя высота обязана дать прежнюю раскладку, иначе панель
    -- «помнит» растяжение и после того, как игрок её вернул.
    local r1c, rNc = measure(300)
    check(r1c == r1a and rNc == rNa,
          'при возврате прежней высоты раскладка возвращается (' ..
          tostring(rNc) .. ' против ' .. tostring(rNa) .. ')')

    -- СМЕНА НАБОРА СТРОК МЕНЯЕТ И ВЫСОТУ ПАНЕЛИ, и делает это ПОСЛЕ раскладки
    -- (FitHeight зовётся из ApplyLayout ниже). Позиции зависят от высоты,
    -- поэтому их надо пересчитать и после подгонки: без второго прохода
    -- короткий набор разъехался бы по прежней, большой высоте и строки уехали
    -- бы за край панели.
    setRows({ eOwn = true, mOverflow = true })
    local pair2 = ctrlFor(CAPTIONS.mOverflow)
    check(pair2 ~= nil,
          'вторая строка пары нашлась для проверки подгонки высоты')
    if pair2 ~= nil then
        check(pair2.Top() + 14 <= panel.ClientGroup.Bottom(),
              'после смены набора строк строки остаются ВНУТРИ панели (низ ' ..
              'строки ' .. tostring(pair2.Top() + 14) .. ', низ окна ' ..
              tostring(panel.ClientGroup.Bottom()) .. ')')
    end
    setAllSeven()
end

-- СВОРАЧИВАНИЕ. Здесь жил баг версии 17: список BODY_KEYS не содержал
-- eGo и mGo, поэтому строки "to allies" не получали Hide() и оставались
-- висеть под свёрнутой шапкой - Group в игре детей не обрезает.
--
-- Кнопки «-» больше нет: сворачивание стало закрытием окна, ровно как у
-- миникарты. Проверяем поэтому не кнопку, а РЕЗУЛЬТАТ - панель спряталась и
-- вернулась, и строки при этом убраны с экрана. Именно этот результат и
-- ловил баг версии 17.
if panel ~= nil and panel.OnClose then
    local hiddenBefore = panel._hidden
    panel.OnClose(panel)
    check(panel._hidden == true,
          'после закрытия окно спрятано, а не просто сжато')
    check(shownData() == 7,
          'строки продолжают обновляться и в свёрнутом виде, их ' ..
          tostring(shownData()) .. ' - их не должно быть видно, но Hide() ' ..
          'на самом окне скрывает всё дочернее')

    -- Возврат: как у миникарты, панель открывает кнопка «Overflow».
    local reopen = nil
    for i = 1, #MADE do
        if MADE[i]._kind == 'Bitmap' and MADE[i]._parent ~= panel
            and MADE[i]._parent ~= panel.ClientGroup then
            reopen = MADE[i]
        end
    end
    check(reopen ~= nil, 'кнопка возврата панели создана вне окна')
    if reopen ~= nil then
        reopen.HandleEvent(reopen, { Type = 'ButtonRelease' })
        check(panel._hidden == false,
              'после возврата окно снова показано (было скрыто: ' ..
              tostring(hiddenBefore) .. ')')
        check(shownData() == 7,
              'после возврата все семь строк на месте (' ..
              tostring(shownData()) .. ')')
    end
end

local joined = table.concat(msgs, ' | ')
check(string.find(joined, 'FAILED') == nil, 'в логе нет ни одной строки FAILED')

return fails
''')

# ============================================ 4. рассогласование имён модулей
print("")
f4 = run("=== 4: модули отдают всё, что мод вызывает ===", r'''
local fails = 0
local function check(cond, label)
    if cond then
        print('  [OK  ] ' .. label)
    else
        fails = fails + 1
        print('  [FAIL] ' .. label)
    end
end

-- Если у модуля переименовать функцию и забыть вызов, обращение даёт nil:
-- цикл `for i = 1, nil` не выполняется ни разу, таблица остаётся пустой, и
-- страница падает уже на Opt(nil). Именно так ломалось Rows.Count() ->
-- Rows.HowMany() на прошлом шаге.
local NEEDS = {
  ROWS = { 'HowManyRows', 'RowKeyAt', 'RowTitleOf', 'RowDefaults',
           'PresetNames', 'PresetFor', 'PresetOther', 'PresetByName',
           'VisibleRows', 'SaveRows', 'RowsSignature', 'DescribeRows' },
  SYNCSTUB = { 'Start', 'GetResult' },
}
local absent = ''
for modName, fns in pairs(NEEDS) do
    local mod = modName == 'ROWS' and ROWS or SYNCSTUB
    for i = 1, #fns do
        if type(mod[fns[i]]) ~= 'function' then
            absent = absent .. modName .. '.' .. fns[i] .. ' '
        end
    end
end
check(absent == '', 'у модулей есть все функции, которые мод вызывает' ..
      (absent == '' and '' or (' НЕТ: ' .. absent)))

-- ЭКСПОРТ ГЛОБАЛАМИ. Значение return движок отбрасывает (import.lua:61,171),
-- поэтому у rows.lua в файле-примере не должно быть таблицы возврата.
check(U.ReapplyRows == nil,
      'ui.lua никуда не экспортирует ReapplyRows: применение делает сам Update')

return fails
''')

# ================================== 5. полная цепочка UMT: Add -> Main -> страница
print("")
f5 = run("=== 5: цепочка UMT, от Add до появления страницы ===", r'''
local fails = 0
local function check(cond, label)
    if cond then
        print('  [OK  ] ' .. label)
    else
        fails = fails + 1
        print('  [FAIL] ' .. label)
    end
end

-- Настоящий порядок в игре: UML находит мод по флагу __umt и говорит UMT-у
-- Add, потом UMT ищет в папке мода Main.lua и зовёт его Main. Именно на этом
-- шаге всё и падало: без Main.lua до наших опций очередь не доходила.
UMT.Add('overflow')

local nBefore = #msgs
UMT.Load(nil)
local loaded = table.concat(msgs, ' | ')
local nAfter = #msgs

check(string.find(loaded, 'UMT: Loading file /mods/overflow/modules/main.lua') ~= nil,
      'UMT нашёл наш Main.lua в папке мода')
check(string.find(loaded, 'Loading options file') ~= nil
      or string.find(loaded, 'loading option') ~= nil
      or string.find(loaded, 'UMT options page') ~= nil,
      'наш Main дошёл до чтения UMT.Options.Mods и.options грузятся')

-- Главная проверка: страница РЕГИСТРИРУЕТСЯ. Всё остальное - детали.
check(BUILDS['Overflow'] ~= nil,
      'страница зарегистрирована: AddOptions отработал без ошибки')
-- 15 строк: рамка, пресет, масштаб шрифта, только числа, мигание, два
-- заголовка, список наборов и семь галочек строк.
check(BUILDS['Overflow'] ~= nil and table.getn(BUILDS['Overflow']) == 15,
      'в странице 15 строк: рамка, пресет, масштаб, два переключателя, два ' ..
      'заголовка, список наборов и семь галочек (получено ' ..
      tostring(BUILDS['Overflow'] and table.getn(BUILDS['Overflow']) or 0) .. ')')

-- ПОЛЗУНОК МАСШТАБА. Границы обязаны совпадать с themes.lua, иначе ползунок
-- даст значение, которое мод потом срежет по своим границам, и игрок будет
-- видеть ползунок на 200, а панель ведёт себя как на 200 ровно - или хуже,
-- если границы мод задаст уже.
local sliderFound = nil
if BUILDS['Overflow'] then
    for i = 1, table.getn(BUILDS['Overflow']) do
        local row = BUILDS['Overflow'][i]
        if row.type == 'slider' then sliderFound = row end
    end
end
check(sliderFound ~= nil, 'на странице есть ползунок масштаба шрифта')
check(sliderFound ~= nil and sliderFound.min == 70 and sliderFound.max == 200,
      'границы ползунка 70-200 совпадают с границами модуля оформления')
check(sliderFound ~= nil and sliderFound.inc == 5,
      'шаг ползунка 5 процентов')

-- Шим обязан быть безопасным и без UMT: страница не должна рушить игру,
-- если мода UMT нет.
local savedUMT = UMT
UMT = nil
local okNoUmt = pcall(MODULES.main.Main, nil)
UMT = savedUMT
check(okNoUmt, 'шим не падает, когда UMT нет')

-- И обязан писать в лог, если опции не зарегистрировались: молчать об
-- этом нельзя - игрок будет искать причину не там.
check(string.find(loaded, 'FAILED') == nil,
      'в логе загрузки цепочки нет ни одной строки FAILED')

return fails
''')

# ==================== 6. физический запрет: полное хранилище => входящий = 0
print("")
f6 = run("=== 6: запрет на входящий при полном хранилище ===", r'''
local fails = 0
local function check(cond, label)
    if cond then
        print('  [OK  ] ' .. label)
    else
        fails = fails + 1
        print('  [FAIL] ' .. label)
    end
end

-- Один отсчёт Sync.Score для армии. Порядок полей повторяет sim/score.lua.
local function Army(ein, eout, eexc, estore, emax,
                   emin, mout, mexc, mstore, mmax)
    return { resources = {
        energyin  = { total = ein, reclaimed = 0 },
        energyout = { total = eout, excess = eexc },
        massin    = { total = emin, reclaimed = 0 },
        massout   = { total = mout, excess = mexc },
        storage   = { storedEnergy = estore, maxEnergy = emax,
                      storedMass = mstore, maxMass = mmax },
    } }
end

local function Feed(myBase, myLater, allyBase, allyLater)
    -- Сброс счётчика ошибок ОБЯЗАТЕЛЕН перед каждым сценарием. Иначе
    -- ошибки предыдущего сценария накопятся, NERR_LIMIT = 3 перебьют, и
    -- sync.lua снимет колбэк - сценарий упадёт по причине, не связанной
    -- с проверяемым.
    SYNC.ResetCounters()
    local before = table.concat(msgs, ' | ')
    check(string.find(before, 'ERROR') == nil,
          'sync.lua не оставил ошибок от прошлого сценария')
    msgs = {}
    TICK = 100
    SCORE_CB({ [1] = myBase, [2] = allyBase })
    TICK = 200
    SCORE_CB({ [1] = myLater, [2] = allyLater })
    return SYNC.GetResult()
end

-- Start() сначала, потом проверка: до него колбэк и не должен существовать.
IMPORTED = {}
SYNC.Start()
check(SCORE_CB ~= nil, 'Start() зарегистрировал колбэк Sync.Score')
local reimported = false
for i = 1, #IMPORTED do
    if IMPORTED[i] == '/lua/UserSync.lua' then reimported = true end
end
check(not reimported, 'UserSync.lua не выполняется второй раз')

-- СЦЕНАРИЙ A. Мой запас стоит на потолке все окно, союзник отдаёт.
--
--   я:     запас 1000 из 1000, произвёл 100, ничего не потратил
--   союзник: произвёл 100, запас 0 из 2000, ничего не потратил
--
-- Мод без запрета показал бы входящий 10/с и исходящий 10/с одновременно.
-- Физически входящий невозможен: принимать некуда.
local rA = Feed(
    Army(0, 0, 0, 1000, 1000, 0, 0, 0, 500, 500),
    Army(100, 0, 0, 1000, 1000, 0, 0, 0, 500, 500),
    Army(0, 0, 0, 0, 2000, 0, 0, 0, 0, 2000),
    Army(100, 0, 0, 0, 2000, 0, 0, 0, 0, 2000))

check(rA ~= nil and rA.ok == true, 'окно опубликовано, сценарий A')
if rA ~= nil then
    check(rA.outgoing > 0,
          'исходящий ненулевой, как и должно быть при полном запасе (' ..
          tostring(rA.outgoing) .. ')')
    check(rA.incoming == 0,
          'входящий обнулён запретом: принимать некуда (было бы 10.0)')
    check(string.find(table.concat(msgs, ' | '), 'GUARD E') ~= nil,
          'в лог записана строка GUARD E с сырыми числами')
    check(string.find(table.concat(msgs, ' | '), 'полный: true') ~= nil,
          'в лог записано, что запас признан полным')
end

-- СЦЕНАРИЙ B. У меня есть место: 500 из 1000. Запрет неприменим.
local rB = Feed(
    Army(0, 0, 0, 500, 1000, 0, 0, 0, 500, 500),
    Army(100, 0, 0, 500, 1000, 0, 0, 0, 500, 500),
    Army(0, 0, 0, 0, 2000, 0, 0, 0, 0, 2000),
    Army(100, 0, 0, 0, 2000, 0, 0, 0, 0, 2000))

check(rB ~= nil and rB.ok == true, 'окно опубликовано, сценарий B')
if rB ~= nil then
    check(rB.incoming > 0,
          'входящий остался: место было, запрет не тронул (' ..
          tostring(rB.incoming) .. ')')
    check(string.find(table.concat(msgs, ' | '), 'GUARD') == nil,
          'GUARD не сработал там, где не должен')
end

-- СЦЕНАРИЙ C. Потолок ВЫРОС в середине окна: в начале места не было,
-- в конце потолок 2000 при запасе 1000, то есть место появилось.
--
-- Именно здесь грубая проверка «минимум запаса >= минимум потолка» ошибалась
-- и объявляла запас полным, обнуляя настоящий перелив.
local rC = Feed(
    Army(0, 0, 0, 1000, 1000, 0, 0, 0, 500, 500),
    Army(100, 0, 0, 1000, 2000, 0, 0, 0, 500, 500),
    Army(0, 0, 0, 0, 2000, 0, 0, 0, 0, 2000),
    Army(100, 0, 0, 0, 2000, 0, 0, 0, 0, 2000))

check(rC ~= nil and rC.ok == true, 'окно опубликовано, сценарий C')
if rC ~= nil then
    check(rC.incoming > 0,
          'выросший потолок НЕ считается полным: место было, входящий остался (' ..
          tostring(rC.incoming) .. ')')
    check(string.find(table.concat(msgs, ' | '), 'GUARD') == nil,
          'на растущем потолке GUARD не сработал')
end

-- СЦЕНАРИЙ D. Запас МАССЫ стоит на потолке всё окно, союзник отдаёт.
-- Принимать некуда, поэтому входящий обязан обнулиться.
local rD = Feed(
    Army(0, 0, 0, 500, 1000, 0, 0, 0, 500, 500),
    Army(100, 0, 0, 500, 1000, 100, 0, 0, 500, 500),
    Army(0, 0, 0, 0, 2000, 0, 0, 0, 0, 2000),
    Army(100, 0, 0, 0, 2000, 100, 0, 0, 0, 2000))

check(rD ~= nil and rD.ok == true, 'окно опубликовано, сценарий D')
if rD ~= nil then
    check(rD.massIncoming == 0,
          'входящая масса обнулена: хранилище массы полно (' ..
          tostring(rD.massIncoming) .. ')')
    check(string.find(table.concat(msgs, ' | '), 'GUARD M') ~= nil,
          'в лог записана строка GUARD M с сырыми числами')
end

-- СЦЕНАРИЙ E. Общий приход массы за матч намного больше ёмкости, но в
-- хранилище есть место. Свободное место считается по запасу, а не по приходу.
local rE = Feed(
    Army(0, 0, 0, 500, 1000, 5000, 0, 0, 100, 500),
    Army(100, 0, 0, 500, 1000, 5100, 0, 0, 100, 500),
    Army(0, 0, 0, 0, 2000, 0, 0, 0, 0, 2000),
    Army(100, 0, 0, 0, 2000, 100, 0, 0, 0, 2000))

check(rE ~= nil and rE.ok == true, 'окно опубликовано, сценарий E')
if rE ~= nil then
    check(rE.massIncoming > 0,
          'входящая масса осталась: место в хранилище было (' ..
          tostring(rE.massIncoming) .. ')')
    check(string.find(table.concat(msgs, ' | '), 'GUARD') == nil,
          'при свободном месте GUARD не сработал')
end

check(string.find(table.concat(msgs, ' | '), 'ERROR') == nil,
      'sync.lua не сыпал ошибок ни в одном сценарии')

return fails
''')

# =========================== 7. ошибка в функции бита не уходит в цикл игры
print("")
f7 = run("=== 7: ошибка в Update не уходит в цикл игры ===", r'''
local fails = 0
local function check(cond, label)
    if cond then
        print('  [OK  ] ' .. label)
    else
        fails = fails + 1
        print('  [FAIL] ' .. label)
    end
end

msgs = {}
SYNC_BROKEN = true
check(pcall(BEAT), 'первая ошибка Update поймана внутри мода')
check(not BEAT_REMOVED, 'после одной ошибки панель продолжает работать')

SYNC_BROKEN = false
check(pcall(BEAT), 'без ошибки Update работает как обычно')

SYNC_BROKEN = true
for _ = 1, 10 do pcall(BEAT) end
SYNC_BROKEN = false

local told = 0
for _ in string.gmatch(table.concat(msgs, ' | '), 'Update FAILED') do
    told = told + 1
end
check(told == 4, 'в лог попали только ошибки до предела (' .. tostring(told) .. ')')
check(BEAT_REMOVED, 'после трёх ошибок подряд функция бита снята')
return fails
''')

print("")
print("=== ИТОГ ===")
fails = f1 + f2 + f3 + f4 + f5 + f6 + f7
if fails:
    print("провалено проверок: %d" % fails)
    sys.exit(1)
print("все проверки пройдены")
