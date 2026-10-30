# WORKSPACE_MAP.md — локальная карта рабочей среды

> **Локальный файл для OpenCode. Не публиковать на GitHub.** Здесь находятся локальные каталоги и сведения о компьютере. Перед публикацией исключить файл через `.gitignore`.

Правила для агента — `AGENTS.md`. Проверенные технические знания — `DOCUMENTATION/documentation.md`. Публичное описание проекта — `README.md`. Этот файл отвечает только на вопрос «что где лежит».

## 1. Локальные пути

| Назначение | Путь |
|---|---|
| Корень рабочей среды | `D:\TEMP\TEST AI VS CODE\` |
| Установка игры | `D:\games\SteamLibrary\steamapps\common\Supreme Commander Forged Alliance\` |
| Распакованные данные FAF | `C:\ProgramData\faforever\gamedata\` |
| Установленные моды игры | `%USERPROFILE%\Documents\My Games\Gas Powered Games\Supreme Commander Forged Alliance\mods\` |
| Локальный клон реверса Moho | `%LOCALAPPDATA%\Temp\opencode\faf-re\faf-re-master\` |

Установленная игра, установленные копии модов и `references\` — только для чтения.

## 2. Структура рабочей директории

Сверено с диском. Показаны уровни, нужные для навигации; содержимое `tests\`, `logs\`, `research\` по файлам не раскрывается.

```text
D:\TEMP\TEST AI VS CODE\
├── AGENTS.md
├── README.md
├── WORKSPACE_MAP.md
├── DOCUMENTATION\
│   ├── documentation.md          основная техническая методичка
│   ├── tools\                    валидаторы и утилиты (список — раздел 4)
│   └── tests\                    только README.md
├── My_mods\                      проекты модов; у каждого свой tests\ и research\
│   ├── AttackMoveByClick\
│   │   ├── AMBC_Diag\            мод (есть mod_info.lua)
│   │   ├── AMBC_Diag_MiMo\       мод (есть mod_info.lua)
│   │   ├── research\
│   │   └── tests\
│   ├── AutoTransportation\
│   │   ├── AutoTransportation\   мод (есть mod_info.lua)
│   │   ├── experiment_a_click_mode\      мод (есть mod_info.lua)
│   │   ├── experiment_b_detach_test\     мод (есть mod_info.lua)
│   │   ├── experiment_A_click_mode.lua   отдельный файл в корне проекта
│   │   ├── experiment_B_detach_test.lua  отдельный файл в корне проекта
│   │   ├── research\
│   │   └── tests\
│   ├── Custom Hotkeys\           имя с пробелом и заглавной — существующее, не переименовывать
│   │   ├── customhotkeys\        мод (есть mod_info.lua)
│   │   ├── Log\
│   │   └── research\
│   ├── overflow\
│   │   ├── Overflow\             мод (есть mod_info.lua)
│   │   ├── diagnostic\
│   │   │   └── overflow_testing\ мод (есть mod_info.lua и README.md)
│   │   ├── logs\
│   │   ├── research\
│   │   └── tests\
│   ├── pause_plz_afk\
│   │   ├── PausePlzAfk\          мод (есть mod_info.lua)
│   │   ├── research\
│   │   └── tests\
│   ├── reclaim_pause\
│   │   ├── ReclaimPause\         мод (есть mod_info.lua)
│   │   ├── logs\
│   │   ├── research\
│   │   └── tests\
│   └── shift_z_transport\        здесь папка проекта И ЕСТЬ папка мода
│       ├── mod_info.lua
│       ├── Main.lua
│       ├── Options.lua
│       └── hook\lua\
├── gamefiles\                    распакованные игровые данные: lua\, units\
├── mods_stable_backup\           резервные копии: overflow\, ReclaimPause\,
│                                 Supreme Commander Forged Alliance\, TestGensVer2\
├── references\                   чужие моды и их разборы, только чтение
│   ├── AKA\
│   ├── ASE\
│   ├── Bi4UI.AutoInteruptPathfindig\
│   ├── Bi4UI.StrategicRings\
│   ├── PPA\
│   ├── ReUI\
│   ├── SupremeScoreBoard2\
│   ├── UMT\
│   └── aka_research.md, ppa_research_deepseek.md, reui_research.md,
│       umt_research.md, hotbuild.lua
└── research\                     общие сырые исследования
    ├── faf_basics\
    ├── ideas\
    ├── testmod\
    └── restructure_instructions.md
```

Факты, важные для работы:

- Признак папки мода — `mod_info.lua` внутри неё. Все моды найдены по этому признаку.
- `My_mods\shift_z_transport` — исключение: `mod_info.lua` лежит прямо в папке проекта, отдельной вложенной папки мода нет. Копировать надо саму `shift_z_transport`.
- `DOCUMENTATION\tests` сейчас содержит только `README.md`, то есть общих тестов там нет; тесты лежат в `My_mods\<проект>\tests\`.
- `gamefiles\` — распакованные игровые данные (`lua\`, `units\`), подключены как reference-папка проекта. Назначение — чтение исходников игры.

## 3. Что где искать

| Что нужно | Где |
|---|---|
| Правила работы агента | `AGENTS.md` |
| Публичное описание проекта | `README.md` |
| Проверенные технические знания, «Ловушки, которые ломают игру» | `DOCUMENTATION\documentation.md` |
| Валидаторы Lua и структуры мода | `DOCUMENTATION\tools\` |
| Тесты конкретного мода | `My_mods\<проект>\tests\` |
| Сырые исследования конкретного мода | `My_mods\<проект>\research\` |
| Общие сырые исследования | `research\` |
| Чужие моды, библиотеки и их разборы | `references\` — только чтение |
| Распакованный игровой Lua и юниты | `gamefiles\lua\`, `gamefiles\units\` |
| Исходники, реально поставляемые клиентом FAF | `C:\ProgramData\faforever\gamedata\` после распаковки архивов |
| Резервные копии старых версий | `mods_stable_backup\` |

Конкретный мод определяется по `mod_info.lua`; не угадывай папку мода по названию проекта.

## 4. Инструменты `DOCUMENTATION\tools\`

- `validate_mod.py` — проверка мода (в т.ч. запрещённые имена переменных);
- `methodlint.py` — проверка Lua-файла;
- `upvaluecheck.py` — проверка ограничения в 32 upvalue;
- `importcheck.py` — проверка импортов мода (принимает каталог мода);
- `msgindex.py` — сверка/индекс сообщений логов;
- `extract_gamefiles.py` — распаковщик игровых архивов, **не** валидатор.

Аргументы и актуальные команды сверяй с самими файлами. Состав тестов не бери из документов: смотри фактическое содержимое `tests\`.

Распаковка Lua из локальных данных FAF:

```powershell
python DOCUMENTATION\tools\extract_gamefiles.py `
    "C:\ProgramData\faforever\gamedata\lua.nx2" <папка-назначения> .lua
```

## 5. Проекты в `My_mods\`

Колонка «что делает» перенесена из прежней карты; код в этой ревизии не перепроверялся. Отсутствие описания означает, что проверенного описания нет — не выдумывай его.

| Проект | Папка мода (для установки) | Что делает |
|---|---|---|
| `overflow` | `Overflow` | Перелив энергии и массы между союзниками и обратно |
| `overflow\diagnostic` | `overflow_testing` | Диагностическая запись в лог синхронизации экономики |
| `reclaim_pause` | `ReclaimPause` | Пауза реклеймящим инженерам при полном хранилище массы |
| `AttackMoveByClick` | `AMBC_Diag`, `AMBC_Diag_MiMo` | — |
| `AutoTransportation` | `AutoTransportation`, `experiment_a_click_mode`, `experiment_b_detach_test` | — |
| `Custom Hotkeys` | `customhotkeys` | — |
| `pause_plz_afk` | `PausePlzAfk` | — |
| `shift_z_transport` | `shift_z_transport` (папка проекта = папка мода) | — |

## 6. Внешние источники

- Официальная документация FAF: `https://wiki.faforever.com/`
- Исходный код FAF: `https://github.com/FAForever/fa`
- Реверс движка Moho: `https://github.com/Draiget/faf-re`
- Дополнительные справочники: `https://fafunits.com/`, `https://faforever.github.io/spooky-db`, `https://supcom.fandom.com/`
- Пример UI-модов ReUI: `https://github.com/4z0t/FAF-UI-Mods`

Реверс Moho — реконструкция движка по бинарнику, а не исходники игры. Сначала ищи подтверждение в Lua и файлах игры; выводы из реверса помечай как «из реверса».

## 7. Команда установки мода

Команду с удалением старой копии пользователь запускает сам; агент её не выполняет. Копируется только папка мода (та, где лежит `mod_info.lua`), без `research\`, `tests\`, `logs\`.

```powershell
$mods = "$env:USERPROFILE\Documents\My Games\Gas Powered Games\Supreme Commander Forged Alliance\mods"
Remove-Item -Recurse -Force "$mods\<Мод>" -ErrorAction SilentlyContinue
Copy-Item -Recurse -Force "D:\TEMP\TEST AI VS CODE\My_mods\<проект>\<Мод>" "$mods\"
```

Для `shift_z_transport` путь-источник — `My_mods\shift_z_transport` (без промежуточной папки).

## 8. Окружение

Историческая запись: 13.10.2026 окружение проверялось с Python 3.14.7 и `lupa` 2.8. Это не гарантия текущего состояния; при необходимости проверь `python --version` и `python -c "import lupa; print(lupa.__version__)"`.
