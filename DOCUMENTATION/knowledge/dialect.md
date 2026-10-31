# Lua в игре

Игра работает на изменённом Lua 5.0. Здесь только отличия от обычного Lua, который описан в его документации. LuaLS считает код написанным на Lua 5.1, поэтому часть этих ошибок ловит только `luac`.

## Чего нет

### `#` начинает комментарий, оператора длины нет

Длина таблицы считается через `table.getn(t)`. Запись `local n = #t` не компилируется, и ошибка указывает на следующую строку, потому что остаток строки стал комментарием.

Источник: lua-lang:HISTORY#new single line comment: # ...

### Нет оператора `%`

Остаток от деления считается через `math.mod(a, b)`. В шаблонах строк `%` работает как обычно.

Источник: lua-lang:test/faf.lua#math.mod(i, 2)

### `^` означает xor, а не степень

`5 ^ 3` равно 6. Степень считается через `math.pow(a, b)`.

Источник: lua-lang:HISTORY#operator ^ means xor instead of pow

### `...` не является выражением

Аргументы функции с `...` лежат в таблице `arg`: количество в `arg.n`, передать дальше можно через `unpack(arg)`. Функции `select` нет.

Источник: lua-lang:src/lparser.c#create_local(ls, "arg")

### Нет `math.huge`

`math.huge` равно `nil`.

Источник: fa:lua/sim/Projectile.lua#Since `math.huge` does not exist

### `%d` в `string.format` отбрасывает дробную часть

`string.format("%d", 3.7)` даёт `3`.

Наблюдение: запуск `lua`, собранного из `references/lua-lang`.

### Нет длинных строк с уровнем

Работает только `[[текст]]`. Запись `[=[текст]=]` не компилируется.

Источник: lua-lang:src/llex.c#read_long_string(LS, seminfo)

## Что есть сверх обычного Lua

### Ключевое слово `continue`

Источник: lua-lang:HISTORY#new keyword `continue'

### Оператор `!=`

Работает так же, как `~=`.

Источник: lua-lang:HISTORY#new inequality operator: !=

### Побитовые операторы `&`, `|`, `<<`, `>>`

Источник: lua-lang:HISTORY#new binary operators &, |, << and >>

### Шестнадцатеричные числа

Источник: lua-lang:HISTORY#hexidecimal number literals

### Методы у строк

`("abc"):sub(2)` работает без `string.sub`.

Источник: lua-lang:HISTORY#metatable for strings pointing at `string' library

### Обход таблицы без `pairs`

`for k, v in t do` работает напрямую.

Источник: lua-lang:test/faf.lua#for i, v in array do

## Ограничения

### Запись `{&1 &8}` не используется в модах

Это подсказка игре, сколько места заранее выделить таблице: первое число для ключей, второе для списка. Игра её понимает, но `luac` проекта считает ошибкой, поэтому мод с такой записью не пройдёт проверку.

Источник: fa:lua/lazyvar.lua#preallocate table with hashsize=1, arraysize=8

### Числа одинарной точности

Числа хранятся как `float`. `0.1 + 0.2 == 0.3` даёт `true`, а `16777217` округляется до `16777216`.

Источник: lua-lang:config#-DUSE_FLOAT

### В функции не больше 32 upvalue

Upvalue это внешняя локальная переменная, которую использует функция. При превышении файл не компилируется с ошибкой `too many upvalues`.

Источник: lua-lang:src/llimits.h#define MAXUPVALUES
