-- ReclaimPause: действие горячей клавиши.
-- Этот файл дописывается в конец /lua/keymap/keyactions.lua.

keyActions = keyActions or {}

-- Функция ReclaimPauseToggle объявлена глобальным именем в
-- modules/watch.lua. import() возвращает таблицу модуля, а обращение к
-- отсутствующему полю проваливается в глобальное окружение - так сделано и
-- в референс-моде Bi4UI.AutoInteruptPathfindig.
keyActions['reclaimpause_toggle'] = {
    action = 'UI_Lua import("/mods/ReclaimPause/modules/watch.lua").ReclaimPauseToggle()',
    category = 'ReclaimPause',
    order = 9000,
}
-- Ручная проверка: показывает состояние прямо сейчас и объясняет, почему мод
-- не сработал. Необходима, когда ждать достижения порога не хочется.
keyActions['reclaimpause_check'] = {
    action = 'UI_Lua import("/mods/ReclaimPause/modules/watch.lua").ReclaimPauseForceCheck()',
    category = 'ReclaimPause',
    order = 9001,
}
-- Сброс настроек к умолчаниям. Отдельный модуль settings, а не watch:
-- сброс не трогает состояние модов, только профиль.
-- Почему не кнопка в окне UMT: мод UMT умеет только восемь типов
-- элементов (OptionsWindow.lua:238-412) и кнопки среди них нет.
keyActions['reclaimpause_defaults'] = {
    action = 'UI_Lua import("/mods/ReclaimPause/modules/settings.lua").ReclaimPauseResetDefaults()',
    category = 'ReclaimPause',
    order = 9002,
}
