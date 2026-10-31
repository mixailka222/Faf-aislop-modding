# Тесты инструментов проекта

Здесь лежат тесты скриптов из `DOCUMENTATION/tools/`. Тесты модов лежат рядом с модами, в `My_mods/<проект>/tests/`.

Запуск из корня репозитория:

```bash
python -m unittest discover -s DOCUMENTATION/tests
```

Тесты собранного компилятора FAF Lua пропускаются, пока не запущен `DOCUMENTATION/tools/bootstrap.py`.
