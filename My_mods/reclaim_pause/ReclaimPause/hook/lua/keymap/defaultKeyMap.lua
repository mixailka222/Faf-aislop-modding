-- ReclaimPause: клавиша переключения мода.
--
-- Клавиша выбрана редкая, чтобы не спорить с чужими модами. Если всё же
-- пересечётся, переназначить можно в настройках игры: Hotbuild / Hotkeys.

defaultKeyMap = defaultKeyMap or {}

defaultKeyMap['Ctrl-Alt-R'] = 'reclaimpause_toggle'
defaultKeyMap['Ctrl-Alt-Shift-C'] = 'reclaimpause_check'
defaultKeyMap['Ctrl-Alt-Shift-D'] = 'reclaimpause_defaults'