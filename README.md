# Моды для Supreme Commander: Forged Alliance Forever

Модификации для **Supreme Commander: Forged Alliance Forever (FAF)**. Описание каждого мода, его зависимости и настройки лежат рядом с ним.

## Моды

| Мод | Что делает | Описание |
|---|---|---|
| Custom Hotkeys | Хоткеи, которые меняют действие в зависимости от выделения | [README](My_mods/Custom%20Hotkeys/README.md) |
| Overflow | Показывает перелив энергии и массы между союзниками | [README](My_mods/overflow/README.md) |
| ReclaimPause | Приостанавливает инженеров на реклейме при заполненном хранилище массы | [README](My_mods/reclaim_pause/README.md) |
| PausePlzAfk | Ставит игру на паузу, если вы пропустили старт матча | [README](My_mods/pause_plz_afk/README.md) |

Диагностический мод `overflow_testing` не предназначен для обычной игры: [описание](My_mods/overflow/diagnostic/overflow_testing/README.md).

## Установка

1. Скопируйте папку мода, в которой лежит `mod_info.lua`, в каталог модов игры.
2. Папки `tests/` и `README.md` проекта копировать не нужно.
3. Включите мод в клиенте FAF и проверьте его версию.

## Сообщить об ошибке

Укажите название и версию мода, шаги для воспроизведения и игровой лог. Не прикладывайте личные данные.

## Разработка

Правила работы описаны в [AGENTS.md](AGENTS.md), стиль кода в [DOCUMENTATION/code_style.md](DOCUMENTATION/code_style.md), проверенные факты о FAF в [DOCUMENTATION/knowledge/](DOCUMENTATION/knowledge/).

Подготовка и проверка мода:

```bash
python DOCUMENTATION/tools/bootstrap.py
python DOCUMENTATION/tools/check.py "My_mods/<проект>/<Мод>"
```

Для этого нужны только Python и Git.

## Лицензия

MIT, см. [LICENSE](LICENSE).
