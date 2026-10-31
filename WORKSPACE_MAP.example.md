# Локальная карта

Скопируй файл в `WORKSPACE_MAP.md` и подставь свои пути. `WORKSPACE_MAP.md` в git не попадает.

| Назначение | Путь |
|---|---|
| Корень проекта | `D:\path\to\project` |
| Установка игры | `D:\games\SteamLibrary\steamapps\common\Supreme Commander Forged Alliance` |
| Данные FAF | `C:\ProgramData\FAForever\gamedata` |
| Установленные моды | `%USERPROFILE%\Documents\My Games\Gas Powered Games\Supreme Commander Forged Alliance\mods` |

## Установка мода

Команду запускает человек. Копируется только папка мода с `mod_info.lua`, без `tests`.

```powershell
$mods = "$env:USERPROFILE\Documents\My Games\Gas Powered Games\Supreme Commander Forged Alliance\mods"
Remove-Item -Recurse -Force "$mods\<Мод>" -ErrorAction SilentlyContinue
Copy-Item -Recurse -Force "<корень проекта>\My_mods\<проект>\<Мод>" "$mods\"
```
