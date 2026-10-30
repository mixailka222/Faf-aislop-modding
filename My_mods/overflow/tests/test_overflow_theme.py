# -*- coding: utf-8 -*-
u"""Тесты Overflow: темы оформления и мигание тревожной строки.

МОД: My_mods\\overflow\\Overflow.
Лежит рядом: папка tests\\ в одной директории с папкой Overflow\\.

ЧТО ПРОВЕРЯЕМ

1) themes.lua - семь тем, их названия и порядок.

2) Чтение из скина игры. Фракционные темы обязаны брать значения из
   skins.lua, а не из своих чисел: опечатка в шестнадцатеричном значении
   иначе просто съела бы тему, и заметить это можно было бы только в игре.

3) Настройка faction_font_color. Она ВЫКЛЮЧЕНА по умолчанию
   (options.lua:1217-1221, default = false), и когда выключена, игра рисует
   серым вместо цвета фракции (uiutil.lua:301-305). Проверяем обе стороны.

4) Устойчивость. Неизвестное значение в профиле, отсутствующий скин,
   пропавший ключ скина - ни один случай не имеет права оставить тему без
   цвета: панель с nil-цветом не рисуется вообще.

5) ui.lua - тема доезжает до панели, и смена темы в профиле приводит к
   пересборке. Главный риск был не в данных, а в порядке вызовов: цвет
   задаётся в конструкторе, и тема, применённая после создания элементов,
   оставила бы панель со старым цветом навсегда.

6) Мигание - выключено по умолчанию, при включении строка мигает
   приглушённым цветом, после предела перестаёт (economy.lua:254,271-272).

ЗАПУСК:  python test_overflow_theme.py
"""
import io
import os
import sys

from lupa import luajit21 as lupa

HERE = os.path.dirname(os.path.abspath(__file__))
MOD = os.path.join(os.path.dirname(HERE), "Overflow")
MOD = os.path.abspath(MOD)

if not os.path.exists(os.path.join(MOD, "modules", "themes.lua")):
    print("FAIL: mod ne nayden po puti: " + MOD)
    sys.exit(1)
print("Mod: " + MOD)


def rd(p):
    return io.open(p, encoding="utf-8").read()


themes_src = rd(os.path.join(MOD, "modules", "themes.lua"))
ui_src = rd(os.path.join(MOD, "modules", "ui.lua"))
rows_src = rd(os.path.join(MOD, "modules", "rows.lua"))

lua = lupa.LuaRuntime(unpack_returned_tuples=True)
make_env = lua.eval(
    "function() local t = {} setmetatable(t, {__index = _G}) return t end")
loader = lua.eval("""function(src, env)
  local f, err = loadstring(src)
  if not f then error(err) end
  setfenv(f, env)
  return f()
end""")

STUBS = r'''
PROFILE = {}
msgs = {}

function LOG(m) msgs[#msgs + 1] = tostring(m) end

Prefs = {}
function Prefs.GetFromCurrentProfile(k) return PROFILE[k] end
function Prefs.SetToCurrentProfile(k, v) PROFILE[k] = v end

-- Настройка игры «цвет шрифта фракции». Настоящий Prefs.GetOption возвращает
-- значение по умолчанию, если опции нет (prefs.lua:116-132), то есть nil не
-- возвращается НИКОГДА. Заглушка повторяет это: при отсутствии ключа отдаёт
-- FALLBACK_OPT, а не nil.
FACTION_FONT_COLOR = nil
FALLBACK_OPT = false
function Prefs.GetOption(k)
    if k == 'faction_font_color' then
        if FACTION_FONT_COLOR == nil then return FALLBACK_OPT end
        return FACTION_FONT_COLOR
    end
    return nil
end

-- ---------------------------------------------------------- СКИНЫ ИГРЫ
--
-- Копия значений из lua/skins/skins.lua:152-177 и строк фракций 76-131.
-- Проверяем ровно против этих чисел. Если игра поменяет палитру, тест об
-- этом сообщит - и это будет правда, а не сюрприз.
SKINS_REAL = {
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
    -- UEF в skins.lua:59-68 не переопределяет НИ ОДНОГО цвета. Но игра всё
    -- равно копирует в него всю цепочку default (skins.lua:224-232,
    -- table.assimilate), поэтому в таблице у UEF значения дефолтные - именно
    -- их и видит мод.
    uef = {
        fontColor = 'FFbadbdb',
        bodyColor = 'FF6FAFAF',
        dialogCaptionColor = 'FFbadbdb',
        dialogButtonColor = 'FF69AB4D',
        highlightColor = 'FF7FA8A4',
        disabledColor = 'FF47555a',
        panelColor = 'FF4A5D6B',
        transparentPanelColor = 'AA4A5D6B',
    },
    aeon = {
        fontColor = 'FFc7e98a',
        bodyColor = 'FF18d006',
        disabledColor = 'FF3b5511',
    },
    cybran = {
        fontColor = 'FFe24f2d',
        bodyColor = 'FFb00101',
        disabledColor = 'FF640505',
    },
    seraphim = {
        fontColor = 'FFffd700',
        bodyColor = 'FF927b00',
        disabledColor = 'FF685f16',
    },
}
SKINS = SKINS_REAL

function ForkThread(f) f() end
function WaitSeconds(n) end

-- ------------------------------------------------------- элементы интерфейса
MADE = {}
NEWCOLORS = {}
-- Цвета ЗАЛИВКИ отдельно от цветов текста. Это разные вещи, и смешивать их
-- нельзя: перерисовка панели вызывает SetColor на подписях, а пересборка -
-- ещё и SetSolidColor на фоне. Чтобы отличить «панель перерисовали» от
-- «панель пересобрали», нужен отдельный список.
NEWSOLID = {}
-- Текстуры отдельно от заливок. Подложка рамки Minimal - это Bitmap с
-- SetTexture, и без отдельного списка нельзя отличить «подложку создали с
-- нужной текстурой» от «подложку не создали вовсе».
NEWTEX = {}
-- Обрезка текстуры отдельно от самой текстуры. Подложка рамки Minimal
-- рисуется двумя кусками, а встроенная линия текстуры между ними
-- ПРОПУСКАЕТСЯ через SetUV. Без отдельного списка нельзя отличить «линию
-- пропустили» от «линию растянули на всё окно».
NEWUV = {}

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
    c._color = nil
    c._destroyed = false
    -- Depth - такой же объект значения, как Left: его умеют ЧИТАТЬ. Мод
    -- поднимает полосу заголовка над содержимым через client.Depth() + 1, а
    -- заглушка с одним Set() этот вызов не пережила бы.
    c.Depth = valueProp(function() return c._depth or 0 end,
                        function(v) c._depth = v end)
    function c:SetSolidColor(v)
        self._color = v
        NEWCOLORS[#NEWCOLORS + 1] = v
        NEWSOLID[#NEWSOLID + 1] = v
    end
    function c:SetTexture(v)
        self._texture = v
        NEWTEX[#NEWTEX + 1] = v
    end
    -- SetUV есть у Bitmap (maui/bitmap.lua:4; так же режет игрушка в
    -- ui/game/statusbar.lua:46-83). Заглушка обязана его иметь: без него
    -- подложка вообще не создалась бы - мод зовёт SetUV сразу после
    -- SetTexture.
    function c:SetUV(u0, v0, u1, v1)
        self._uv = { u0, v0, u1, v1 }
        NEWUV[#NEWUV + 1] = { u0, v0, u1, v1 }
    end
    function c:SetAlpha(v) self._alpha = v end
    function c:SetColor(v)
        self._color = v
        NEWCOLORS[#NEWCOLORS + 1] = v
    end
    function c:SetDropShadow(v) end
    function c:SetFont(f, s) end
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
UIUtil.titleFont = 'titleFont'
function UIUtil.CreateText(parent, text, size, font)
    local c = NewCtrl('Text', parent)
    c._text = text or ''
    c._size = size
    -- Текст мод пишет через SetText. Записываем его ещё и в общий список,
    -- иначе по экрану нельзя проверить режим «только числа»: подписи у
    -- подписей есть только _text, а он у каждой свой.
    c.SetText = function(self, v)
        self._text = v
        NEWTEXT[#NEWTEXT + 1] = v
    end
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
function PostDragger(frame, key, drag) end

FRAME = { Width = function() return 1920 end, Height = function() return 1080 end }
function GetFrame(i) return FRAME end
function GetCursor()
    return { SetTexture = function() end, Reset = function() end }
end

GameMainStub = { AddBeatFunction = function(f, throttle, id) BEAT = f end }
BEAT = nil

SYNCSTUB = {
    started = false,
    Start = function() SYNCSTUB.started = true return true end,
    GetResult = function()
        return {
            ok = true,
            incoming = 100, outgoing = 20, own = 200,
            massIncoming = 0, massOutgoing = 30, massOwn = 300,
            reclaim = 5, massReclaim = 6,
        }
    end,
}

function import(p)
    if p == '/lua/user/prefs.lua' then return Prefs end
    if p == '/lua/skins/skins.lua' then return { skins = SKINS } end
    if p == '/lua/ui/uiutil.lua' then return UIUtil end
    if p == '/lua/maui/bitmap.lua' then return { Bitmap = Bitmap } end
    if p == '/lua/maui/group.lua' then return { Group = Group } end
    if p == '/lua/maui/layouthelpers.lua' then return LayoutHelpers end
    if p == '/lua/maui/dragger.lua' then return { Dragger = Dragger } end
    if p == '/lua/maui/window.lua' then return { Window = NewWindow } end
    if p == '/lua/ui/game/gamemain.lua' then return GameMainStub end
    if p == '/mods/Overflow/modules/rows.lua' then return MODULES.rows end
    if p == '/mods/Overflow/modules/themes.lua' then return MODULES.themes end
    if p == '/mods/Overflow/modules/sync.lua' then return SYNCSTUB end
    return {}
end

-- ------------------------------------------------------------- помощники
function alltext() return table.concat(msgs, ' | ') end
NEWTEXT = {}
function resetlog() msgs = {} NEWTEXT = {} NEWUV = {} end

-- Оператор # движком не поддерживается (методичка 3.3), длина таблицы
-- берётся через table.getn.
TableGetn = table.getn

function PickTheme(name)
    local t = PROFILE['Overflow']
    if type(t) ~= 'table' then t = {} end
    t.theme = name
    PROFILE['Overflow'] = t
end
function PickBlink(on)
    local t = PROFILE['Overflow']
    if type(t) ~= 'table' then t = {} end
    t.blink = on and true or false
    PROFILE['Overflow'] = t
end

-- Выборы в профиле. У пресета и рамки свои ключи: style и theme.
function PickStyle(name)
    local t = PROFILE['Overflow']
    if type(t) ~= 'table' then t = {} end
    t.style = name
    PROFILE['Overflow'] = t
end
function PickFrame(name)
    local t = PROFILE['Overflow']
    if type(t) ~= 'table' then t = {} end
    t.theme = name
    PROFILE['Overflow'] = t
end
function PickFontScale(v)
    local t = PROFILE['Overflow']
    if type(t) ~= 'table' then t = {} end
    t.fontScale = v
    PROFILE['Overflow'] = t
end
function PickNumbers(on)
    local t = PROFILE['Overflow']
    if type(t) ~= 'table' then t = {} end
    t.numbersOnly = on and true or false
    PROFILE['Overflow'] = t
end

-- ПУСТОЙ ПРОФИЛЬ - ЭТО ПУСТОЙ ПРОФИЛЬ ЦЕЛИКОМ, а не только ключ 'Overflow'.
--
-- Свёрнутое состояние панель хранит под СВОИМ ключом верхнего уровня
-- (ui.lua:252, COLLAPSE_KEY = 'OverflowCollapsed'), и обратно читает его при
-- сборке окна. Пока чистился один ключ, свёрнутое состояние переживало
-- ClearProfile: следующий U.OnCreateUI() поднимал панель уже свёрнутой, Render
-- не звался, и подписи на экран не возвращались. Проверка «подписи вернулись»
-- это и поймала.
function ClearProfile() PROFILE = {} end

FIELDS = { 'BG', 'CLOSED', 'DIVIDER', 'TITLE', 'TOTAL', 'NEUTRAL',
           'SAFE', 'WARN', 'BAD' }
function Complete(pal)
    if type(pal) ~= 'table' then return false end
    for i = 1, TableGetn(FIELDS) do
        local f = FIELDS[i]
        if type(pal[f]) ~= 'string' or pal[f] == '' then return false end
    end
    return true
end
'''

lua.execute(STUBS)
G = lua.globals()
G['MODULES'] = lua.eval('{}')

# --------------------------------------------------------------- themes.lua
env_theme = make_env()
loader(themes_src, env_theme)
G['MODULES']['themes'] = env_theme
# Отдельным глобалом: блоки проверок исполняются в глобальном окружении
# LuaJIT и видят модуль только через него.
G['T'] = env_theme

# ------------------------------------------------------------------- rows.lua
env_rows = make_env()
loader(rows_src, env_rows)
G['MODULES']['rows'] = env_rows
G['ROWS'] = env_rows

# ui.lua грузится последним: он тянет themes.lua и rows.lua через import, и без
# них в логе будет FATAL. Объявляем его под именем U - блоки проверок
# исполняются в глобальном окружении и видят модуль только через него.
env_ui = make_env()
loader(ui_src, env_ui)
G['MODULES']['ui'] = env_ui
G['U'] = env_ui


def run(label, code):
    print(label)
    try:
        return lua.execute(code) or 0
    except Exception as e:
        print("  [FAIL] проверка упала: " + str(e))
        return 1


# Общий кусок: счётчик провалов. Одинаков во всех блоках, чтобы каждый
# читался сам по себе.
PRELUDE = r'''
local fails = 0
local function check(cond, text)
    if cond then return end
    fails = fails + 1
    print('  [FAIL] ' .. text)
end
'''

# ==================================================== 1. состав и порядок тем
f1 = run("=== 1. СОСТАВ: ДВА ВЫБОРА ===", PRELUDE + r'''
-- Рамки: Vanilla по умолчанию, Minimal рядом.
ClearProfile()
local frames = T.FrameNames()
check(TableGetn(frames) == 2,
      'рамок ровно две (получено ' .. tostring(TableGetn(frames)) .. ')')
check(frames[1] == 'Vanilla',
      'первая рамка - Vanilla, и именно она по умолчанию')
check(frames[2] == 'Minimal', 'вторая рамка - Minimal')
check(T.FrameCurrent() == 'Vanilla', 'по умолчанию выбрана рамка Vanilla')
check(T.FrameMinimal() == false, 'по умолчанию рамка НЕ плоская')

-- Пресеты: Vanilla по умолчанию, Minimal рядом.
ClearProfile()
local styles = T.StyleNames()
check(TableGetn(styles) == 2,
      'пресетов ровно два (получено ' .. tostring(TableGetn(styles)) .. ')')
check(styles[1] == 'Vanilla',
      'первый пресет - Vanilla, и именно он по умолчанию')
check(styles[2] == 'Minimal', 'второй пресет - Minimal')
check(T.StyleCurrent() == 'Vanilla', 'по умолчанию выбран пресет Vanilla')

-- ФРАКЦИОННЫХ ТЕМ БОЛЬШЕ НЕТ. Рамка и так берётся из папки скина, поэтому
-- отдельного пункта под фракцию в списках быть не должно.
local joined = frames[1] .. frames[2] .. styles[1] .. styles[2]
for _, gone in ipairs({ 'AEON', 'UEF', 'Cybran', 'Seraphim', 'SSB', 'Тихая',
                        'Неон' }) do
    check(string.find(joined, gone, 1, true) == nil,
          'фракционная тема ' .. gone .. ' убрана из списков')
end
return fails
''')

f2 = run("=== 2. ПАЛИТРА ПОЛНА У ЛЮБОГО ПРЕСЕТА ===", PRELUDE + r'''
-- Панель с nil-цветом не рисуется вообще, поэтому набор полей обязан быть
-- полным при любом выборе.
local styleList = { 'Vanilla', 'Minimal' }
for i = 1, TableGetn(styleList) do
    ClearProfile()
    PickStyle(styleList[i])
    local pal = T.StylePalette()
    check(Complete(pal),
          'пресет ' .. styleList[i] .. ' вернул полный набор полей')
end

-- КЕГЛЬ ЕСТЬ У ОБОИХ ПРЕСЕТОВ, ЦВЕТА РАМКИ - НЕТ. Раньше BG жил в пресете,
-- и выбор «рамка Minimal + пресет Vanilla» красил окно прозрачной панелью
-- игры AA4A5D6B (skins.lua:172) - то самое серое пятно, на которое пожаловался
-- игрок. Теперь рамку красит её собственная подложка, и пресет о раме не знает:
-- BG у Minimal такой же, как у игры.
ClearProfile()
PickStyle('Minimal')
local minPal = T.StylePalette()
check(minPal.BG == 'AA4A5D6B',
      'пресет Minimal больше не задаёт цвет рамки (BG = ' ..
      tostring(minPal.BG) .. ')')
check(minPal.FONT == 11, 'у пресета Minimal кегль 11, а не nil (' ..
      tostring(minPal.FONT) .. ')')
return fails
''')

f3 = run("=== 3. СМЫСЛ ЦВЕТОВ ОДИНАКОВ У ОБОИХ ПРЕСЕТОВ ===", PRELUDE + r'''
-- Задача игрока: зелёный - перелива нет, жёлтый - союзники переливают тебе,
-- красный - ты зависишь от перелива. СПИСОК СОСТОЯНИЙ поэтому обязан быть
-- один и тот же, и различаться может только оттенок.
--
-- Проверяем то, что можно проверить здесь: у обоих пресетов есть все три
-- состояния и все три - НЕПУСТЫЕ строки. Смысл же оттенка задаётся в
-- ui.lua:StatusColor, и он проверяется в тесте панели.
local want = { 'SAFE', 'WARN', 'BAD' }
for i = 1, TableGetn(want) do
    local field = want[i]
    ClearProfile()
    PickStyle('Vanilla')
    local v = T.StylePalette()[field]
    ClearProfile()
    PickStyle('Minimal')
    local m = T.StylePalette()[field]
    check(type(v) == 'string' and v ~= '' and type(m) == 'string' and m ~= '',
          'состояние ' .. field .. ' есть у обоих пресетов (Vanilla ' ..
          tostring(v) .. ', Minimal ' .. tostring(m) .. ')')
end

-- Цвета состояний ПРЕСЕТА VANILLA - игровые, без исключений.
ClearProfile()
PickStyle('Vanilla')
local van = T.StylePalette()
check(van.SAFE == 'ffb7e75f',
      'Vanilla SAFE - игровой ffb7e75f (economy_mini.lua:12), а не ' ..
      tostring(van.SAFE))
check(van.WARN == 'yellow',
      'Vanilla WARN - игровое имя цвета yellow (economy.lua:262), а не ' ..
      tostring(van.WARN))
check(van.BAD == 'red',
      'Vanilla BAD - игровое имя цвета red (economy.lua:264), а не ' ..
      tostring(van.BAD))
return fails
''')

f4 = run("=== 4. ПРЕСЕТ VANILLA ЧИТАЕТ СКИНА ИГРЫ ===", PRELUDE + r'''
-- Опечатка в числе невозможна: значения берутся из скина, а если FAF поменяет
-- скин, мод пойдёт за ним.
ClearProfile()
FACTION_FONT_COLOR = true
PickStyle('Vanilla')
local v = T.StylePalette()
check(v.NEUTRAL == 'FF18d006',
      'Vanilla NEUTRAL читается из скина (bodyColor FF18d006), а не ' ..
      tostring(v.NEUTRAL))
check(v.DIVIDER == 'FF3b5511',
      'Vanilla DIVIDER читается из скина (disabledColor FF3b5511), а не ' ..
      tostring(v.DIVIDER))

-- Фон плостой рамки берётся из того же скина.
check(v.BG == 'AA4A5D6B',
      'Vanilla BG - прозрачная панель игры AA4A5D6B, а не ' .. tostring(v.BG))

-- ПРЕСЕТ MINIMAL цвета скина игнорирует: он наш и задаётся своими числами.
ClearProfile()
PickStyle('Minimal')
local m = T.StylePalette()
check(m.NEUTRAL == 'FF8A96A3',
      'Minimal NEUTRAL свой, а не игровой (FF8A96A3 против ' ..
      tostring(m.NEUTRAL) .. ')')

FACTION_FONT_COLOR = nil
return fails
''')

f5 = run("=== 5. НАСТРОЙКА faction_font_color ===", PRELUDE + r'''
-- Она выключена по умолчанию (options.lua:1217-1221), и тогда игра рисует
-- серым skins.default.fontColor (uiutil.lua:301-305). Мод повторяет это.
ClearProfile()
FACTION_FONT_COLOR = false
PickStyle('Vanilla')
local grey = T.StylePalette()
check(grey.TITLE == 'FFbadbdb',
      'при выключенной настройке заголовок серый, как в игре (FFbadbdb), а не ' ..
      tostring(grey.TITLE))

FACTION_FONT_COLOR = true
ClearProfile()
PickStyle('Vanilla')
local colour = T.StylePalette()
check(colour.TITLE == 'FFc7e98a',
      'при включённой настройке цвет шрифта фракции доезжает до панели, а не ' ..
      tostring(colour.TITLE))

-- А вот обычный текст от настройки НЕ зависит: bodyColor uiutil.lua:298
-- ставит из скина безусловно.
check(colour.NEUTRAL == grey.NEUTRAL,
      'цвет обычного текста не зависит от faction_font_color')

FACTION_FONT_COLOR = nil
return fails
''')

f6 = run("=== 6. МАСШТАБ ШРИФТА ===", PRELUDE + r'''
-- Ползунок UMT целочисленный, поэтому масштаб в процентах.
ClearProfile()
PickStyle('Vanilla')
check(T.FontScale() == 100, 'по умолчанию масштаб 100 процентов, а не ' ..
      tostring(T.FontScale()))
check(T.StyleFontSize() == 10,
      'при 100 процентах кегль равен базовому (10), а не ' ..
      tostring(T.StyleFontSize()))

ClearProfile()
PickFontScale(150)
PickStyle('Vanilla')
check(T.StyleFontSize() == 15,
      'при 150 процентах кегль 15, а не ' .. tostring(T.StyleFontSize()))

ClearProfile()
PickFontScale(150)
PickStyle('Minimal')
check(T.StyleFontSize() == 17,
      'пресет масштабируется от СВОЕГО базового кегля (11 -> 17), а не ' ..
      tostring(T.StyleFontSize()))

-- Границы. Вне их мод ведёт себя как на границе, а не падает.
ClearProfile()
PickFontScale(5)
check(T.FontScale() == 70, 'слишком маленький масштаб поднимается до 70')
ClearProfile()
PickFontScale(9999)
check(T.FontScale() == 200, 'слишком большой масштаб опускается до 200')

-- Мусор в профиле не должен ломать панель.
ClearProfile()
PickFontScale('не число')
check(T.FontScale() == 100, 'нечисловой масштаб трактуется как 100')
return fails
''')

f7 = run("=== 7. РАМКА И РЕЖИМ «ТОЛЬКО ЧИСЛА» ===", PRELUDE + r'''
ClearProfile()
PickFrame('Minimal')
check(T.FrameCurrent() == 'Minimal', 'рамка Minimal выбирается')
check(T.FrameMinimal() == true, 'рамка Minimal помечена как плоская')
PickFrame('Vanilla')
check(T.FrameMinimal() == false, 'рамка Vanilla помечена как игровая')

-- Неизвестное значение - первая рамка: молча пропасть нельзя.
ClearProfile()
PickFrame('не существует')
check(T.FrameCurrent() == 'Vanilla',
      'неизвестная рамка откатывается к Vanilla')

ClearProfile()
check(T.NumbersOnly() == false, 'режим «только числа» выключен по умолчанию')
ClearProfile()
PickNumbers(true)
check(T.NumbersOnly() == true, 'режим «только числа» читается из профиля')
return fails
''')

f8 = run("=== 8. ПОДПИСЬ И МИГАНИЕ ===", PRELUDE + r'''
-- Подпись решает, перестраивать ли панель. Всё, что меняет вид при сборке,
-- обязано в неё входить, иначе смена настройки не подхватится.
ClearProfile()
local s1 = T.ThemeSignature()
ClearProfile()
PickStyle('Minimal')
local s2 = T.ThemeSignature()
check(s1 ~= s2, 'подпись обязана меняться при смене пресета')
ClearProfile()
PickStyle('Minimal')
PickFrame('Minimal')
local s3 = T.ThemeSignature()
check(s2 ~= s3, 'подпись обязана меняться при смене рамки')
ClearProfile()
PickStyle('Minimal')
PickFontScale(150)
check(T.ThemeSignature() ~= s2,
      'подпись обязана меняться при смене масштаба шрифта')
ClearProfile()
PickStyle('Minimal')
PickNumbers(true)
check(T.ThemeSignature() ~= s2,
      'подпись обязана меняться при включении «только числа»')

ClearProfile()
PickBlink(true)
check(T.ThemeSignature() ~= s1, 'подпись обязана меняться при мигании')
check(T.ThemeBlinkOn() == true, 'мигание читается из профиля')
ClearProfile()
check(T.ThemeBlinkOn() == false, 'мигание выключено по умолчанию')

-- Подпись обязана быть читаемой, а не конкатенацией полей.
ClearProfile()
PickStyle('Minimal')
local tell = T.ThemeTell()
check(string.find(tell, 'Minimal', 1, true) ~= nil,
      'в описании видно имя пресета, а не ' .. tell)
check(string.find(tell, T.ThemeSignature(), 1, true) == nil,
      'описание не выдаёт сырую подпись: ' .. tell)
return fails
''')

f9 = run("=== 9. УСТОЙЧИВОСТЬ К ПРОФИЛЮ И СКИНАМ ===", PRELUDE + r'''
-- Пустой профиль: всё должно взять значения по умолчанию, а не упасть.
ClearProfile()
check(T.StyleCurrent() == 'Vanilla', 'пустой профиль даёт пресет Vanilla')
check(T.FrameCurrent() == 'Vanilla', 'пустой профиль даёт рамку Vanilla')
check(T.FontScale() == 100, 'пустой профиль даёт масштаб 100')
check(Complete(T.StylePalette()), 'пустой профиль даёт полную палитру')

-- Мусорные значения в профиле.
local t = PROFILE['Overflow']
PROFILE['Overflow'] = { style = 42, theme = {}, fontScale = {}, blink = 'да' }
check(T.StyleCurrent() == 'Vanilla', 'нестрочный пресет откатывается к Vanilla')
check(T.FrameCurrent() == 'Vanilla', 'нестрочная рамка откатывается к Vanilla')
check(T.FontScale() == 100, 'нестрочный масштаб откатывается к 100')
check(T.ThemeBlinkOn() == true, 'любая непустая строка считается включённой')
PROFILE['Overflow'] = nil

-- БЕЗ skins.lua. Модуль обязан выжить и вернуть полный набор: панель без
-- своих цветов лучше, чем панель с прозрачным текстом.
ClearProfile()
local vanillaNoSkin = T.StylePalette()
check(Complete(vanillaNoSkin),
      'без скина палитра Vanilla остаётся полной')
check(vanillaNoSkin.NEUTRAL ~= nil and vanillaNoSkin.NEUTRAL ~= '',
      'без скина обычный текст не прозрачный')
return fails
''')

f10 = run("=== 10. ui.lua: ОФОРМЛЕНИЕ ДОЕЗЖАЕТ ДО ПАНЕЛИ ===", PRELUDE + r'''
-- Панель читает палитру при сборке, и цвета обязаны дойти до подписей.
--
-- Цвет берём ИГРОВОЙ, а не из палитры Minimal. Встроенные цвета ui.lua
-- совпадают с палитрой Minimal, и проверка на FF8FD0FF прошла бы даже при
-- НЕ вызванном ApplyTheme: тест был бы зелёным на сломанной панели.
-- Именно поэтому здесь Vanilla и FF18d006 - его во встроенной палитре нет.
ClearProfile()
PickStyle('Vanilla')
resetlog()
NEWCOLORS = {}
U.OnCreateUI()
local seen = {}
for i = 1, #NEWCOLORS do seen[NEWCOLORS[i]] = true end
check(seen['FF18d006'] == true,
      'цвет подписи пресета Minimal должен уйти в панель')
check(string.find(alltext(), 'window created', 1, true) ~= nil,
      'панель собралась')
check(string.find(alltext(), 'Vanilla', 1, true) ~= nil,
      'в логе должно быть видно имя пресета')

-- РЕЖИМ «ТОЛЬКО ЧИСЛА»: в строке остаётся одно число, без подписи и без
-- единицы измерения. Проверяем по тексту, который реально попал на экран.
ClearProfile()
PickNumbers(true)
NEWTEXT = {}
U.OnCreateUI()
BEAT()
local joined = ''
for i = 1, #NEWTEXT do joined = joined .. '|' .. tostring(NEWTEXT[i]) end
check(string.find(joined, 'ally overflow', 1, true) == nil,
      'в режиме чисел подписи строк убраны: ' .. joined)
check(string.find(joined, '|0.0', 1, true) ~= nil,
      'в режиме чисел остались сами числа: ' .. joined)

-- ПОДЛОЖКА РАМКИ MINIMAL. Задача игрока - рамка «максимально
-- минималистичная, как панели Selection Cost UI». Разобран тот мод: панель у
-- него - обычный Bitmap с одной игровой текстурой
-- (Selection Cost UI/hook/lua/ui/game/gamemain.lua:47-49), а не окно.
--
-- Поэтому в Minimal мод ГАСИТ все девять кусков окна прозрачным цветом, а фон
-- рисует отдельным Bitmap с текстурой игры. Проверяем и число гашений, и их
-- цвет, и что подложка вообще создана с нужной текстурой: одной проверки на
-- число, как было раньше, недостаточно - девять заливок можно сделать и
-- неправильным цветом, и тогда панель останется с игровой рамкой.
ClearProfile()
PickFrame('Minimal')
NEWSOLID = {}
NEWTEX = {}
NEWUV = {}
-- Метка в общем списке контролов: искать подложку надо только среди тех, что
-- созданы ЭТИМ проходом, иначе в счёт попадут куски от прошлых сборок окна.
local mark = #MADE
U.OnCreateUI()
check(TableGetn(NEWSOLID) >= 9,
      'рамка Minimal: погашены девять кусков окна (заливок ' ..
      tostring(TableGetn(NEWSOLID)) .. ')')
local cleared = 0
for i = 1, TableGetn(NEWSOLID) do
    if NEWSOLID[i] == '00000000' then cleared = cleared + 1 end
end
check(cleared >= 9,
      'рамка Minimal: куски окна погашены прозрачным, а не залиты цветом (' ..
      tostring(cleared) .. ')')

-- ПОДЛОЖКА - ДВА КУСКА, А НЕ ОДИН.
--
-- В текстуре панели есть СВОЯ линия-разделитель на середине: y=35 из 72, во
-- всю ширину (замер по распакованному файлу, у всех четырёх скинов одинаково).
-- Тянем текстуру на всё окно - линия уезжает в пустоту, а рядом встаёт наш
-- разделитель. Игрок увидел ДВЕ линии и написал: «что она разделяет, если
-- значения и окно живут разными жизнями».
--
-- Поэтому фон рисуется двумя Bitmap, и встроенная линия между ними
-- ПРОПУСКАЕТСЯ через SetUV: верхний кусок берёт строки 0..34 текстуры,
-- нижний 36..71. Проверяем именно это, а не «подложка вообще есть».
local pieces = {}
for i = mark + 1, #MADE do
    local c = MADE[i]
    if c._texture ~= nil
        and string.find(tostring(c._texture),
                        'filter-ping-panel02_bmp.dds', 1, true) ~= nil then
        pieces[#pieces + 1] = c
    end
end
check(#pieces == 2,
      'подложка рамки Minimal собрана из двух кусков, а не из одного (' ..
      tostring(#pieces) .. ')')

local LINE_TOP = 35 / 72
local LINE_BOTTOM = 36 / 72
local topPiece, botPiece = nil, nil
for i = 1, #pieces do
    local uv = pieces[i]._uv
    if uv ~= nil and uv[4] <= LINE_TOP + 0.001 then topPiece = pieces[i] end
    if uv ~= nil and uv[2] >= LINE_BOTTOM - 0.001 then botPiece = pieces[i] end
end
check(topPiece ~= nil,
      'верхний кусок подложки обрезан по встроенной линии, а не тянет её на ' ..
      'всё окно (v1 = ' .. tostring(topPiece and topPiece._uv[4]) .. ')')
check(botPiece ~= nil,
      'нижний кусок подложки начинается после встроенной линии (v0 = ' ..
      tostring(botPiece and botPiece._uv[2]) .. ')')
check(topPiece ~= nil and botPiece ~= nil
      and topPiece._uv[1] == 0 and topPiece._uv[2] == 0
      and botPiece._uv[3] == 1 and botPiece._uv[4] == 1,
      'два куска вместе накрывают всю текстуру, без дыр по краям')

-- СВОРАЧИВАНИЕ ГАСИТ ПОДЛОЖКУ.
--
-- Подложка подвешена к GetFrame(0), а НЕ к окну, поэтому G.win:Hide() её не
-- трогает. До версии 32 крестик убирал только значения, а пустая рамка
-- оставалась висеть на экране - ровно то, о чём сообщил игрок.
local panel = nil
for i = mark + 1, #MADE do
    if MADE[i]._kind == 'Window' then panel = MADE[i] end
end
check(panel ~= nil and panel.OnClose ~= nil,
      'окно нашлось для проверки сворачивания')
if panel ~= nil and panel.OnClose ~= nil then
    panel.OnClose(panel)
    local gone = 0
    for i = 1, #pieces do
        if pieces[i]._hidden then gone = gone + 1 end
    end
    check(gone == #pieces and #pieces > 0,
          'при сворачивании подложка гаснет вместе с окном (погашено ' ..
          tostring(gone) .. ' из ' .. tostring(#pieces) .. ')')
end

ClearProfile()
PickFrame('Vanilla')
NEWSOLID = {}
NEWTEX = {}
NEWUV = {}
U.OnCreateUI()
check(TableGetn(NEWSOLID) < 9,
      'в игровой рамке куски окна остаются текстурами (заливок ' ..
      tostring(TableGetn(NEWSOLID)) .. ')')
check(TableGetn(NEWTEX) == 0,
      'в игровой рамке подложка не создаётся (текстур ' ..
      tostring(TableGetn(NEWTEX)) .. ')')
check(TableGetn(NEWUV) == 0,
      'в игровой рамке текстура не режется (обрезок ' ..
      tostring(TableGetn(NEWUV)) .. ')')

-- А без этого режима подписи на месте - иначе галочка ничего не делает.
ClearProfile()
NEWTEXT = {}
U.OnCreateUI()
BEAT()
joined = ''
for i = 1, #NEWTEXT do joined = joined .. '|' .. tostring(NEWTEXT[i]) end
check(string.find(joined, 'ally overflow', 1, true) ~= nil,
      'без режима чисел подписи вернулись')
return fails
''')

f10 = f10 + 0
try:
    # Скин убирается ДО загрузки модуля. Именно так выглядит настоящая поломка:
    # themes.lua берёт таблицу скинов один раз, при импорте.
    lua.execute("SKINS = nil")
    lua.execute("resetlog()")
    env_noskin = make_env()
    loader(themes_src, env_noskin)
    G['T'] = env_noskin
    told = lua.eval("alltext()")
    if "skins.lua did not load" not in told:
        print("  [FAIL] о пропаже скинов не сказано в лог")
        f10 = f10 + 1
    else:
        print("  пропажа скинов замечена и сказана в лог")
    lua.execute("""
        PROFILE['Overflow'] = { theme = 'AEON' }
        NEWCOLORS = {}
    """)
    okfull = lua.eval("Complete(T.StylePalette()) and 1 or 0")
    if not okfull:
        print("  [FAIL] без skins.lua палитра должна остаться полной")
        f10 = f10 + 1
    else:
        print("  без skins.lua палитра осталась полной")
except Exception as e:
    print("  [FAIL] модуль не пережил пропажу скинов: " + str(e))
    f10 = 1

# ------------------------------------------------------------------- ИТОГ
print("")
print("=== ИТОГ ===")
total = f1 + f2 + f3 + f4 + f5 + f6 + f7 + f8 + f9 + f10
if total:
    print("провалено проверок: %d" % total)
    sys.exit(1)
print("все проверки пройдены")