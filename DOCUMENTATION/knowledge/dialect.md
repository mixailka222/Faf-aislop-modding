# Lua в игре

Игра работает на изменённом Lua 5.0. Здесь только отличия от обычного Lua, который описан в его документации. LuaLS считает код написанным на Lua 5.1, поэтому часть этих ошибок ловит только `luac`, а отсутствие функции из новых версий Lua видно только при выполнении: тесты модов запускает настоящий Lua игры.

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

### Чтение поля у `nil` не падает

`x.field` при `x == nil` возвращает `nil` без ошибки, в интерфейсе и в sim. Так же работает чтение поля у `boolean`. Цепочка `a.b.c` с отсутствующим `a.b` молча даёт `nil`, `pcall` здесь ловить нечего, а сбой проявится позже и в другом месте. Запись падает с ``Attempt to set attribute 'field' on nil``, вызов с ``attempt to call upval `x' (a nil value)``. Локальный `.tools/faf-lua/lua.exe` на таком чтении падает с `attempt to index a nil value`, поэтому тесты модов ведут себя здесь иначе, чем игра.

Наблюдение: `pcall` вокруг чтения, записи и вызова в матче, в интерфейсе и в sim-колбэке; тот же код в `.tools/faf-lua/lua.exe`.

## Ограничения

### Зарезервированные слова

Как имя нельзя использовать только `and`, `break`, `continue`, `do`, `else`, `elseif`, `end`, `false`, `for`, `function`, `if`, `in`, `local`, `nil`, `not`, `or`, `repeat`, `return`, `then`, `true`, `until`, `while`. Отличие от обычного Lua одно: `continue`. Остальные имена свободны, в том числе `name`, `count`, `index`, `value`, `line`, `key`, `mode`.

Источник: lua-lang:src/llex.c#"and", "break", "continue", "do", "else", "elseif",

### Подсказка размера таблицы `{&1 &8}`

Запись заранее выделяет таблице место: первое число для ключей, второе для списка. Игра её понимает и использует там, где таблицы создаются очень часто, например в `lua/system/class.lua`. Это рабочая оптимизация, а не ошибка. `luac` проекта её не понимает, поэтому мод с такой записью не пройдёт `check.py` и CI. Если запись понадобится, сначала нужно научить проверку её пропускать.

Источник: fa:lua/lazyvar.lua#preallocate table with hashsize=1, arraysize=8

### Числа одинарной точности

Числа хранятся как `float`. `0.1 + 0.2 == 0.3` даёт `true`, а `16777217` округляется до `16777216`.

Источник: lua-lang:config#-DUSE_FLOAT

### В функции не больше 32 upvalue

Upvalue это внешняя локальная переменная, которую использует функция. При превышении файл не компилируется с ошибкой `too many upvalues`.

Источник: lua-lang:src/llimits.h#define MAXUPVALUES
