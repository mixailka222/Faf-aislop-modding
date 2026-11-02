-- ReclaimPause: hotkey actions, appended to /lua/keymap/keyactions.lua.

keyActions = keyActions or {}

keyActions['reclaimpause_toggle'] = {
    action = 'UI_Lua import("/mods/ReclaimPause/modules/watch.lua").ReclaimPauseToggle()',
    category = 'ReclaimPause',
    order = 9000,
}
-- Logs what the mod sees right now and why it did not act.
keyActions['reclaimpause_check'] = {
    action = 'UI_Lua import("/mods/ReclaimPause/modules/watch.lua").ReclaimPauseForceCheck()',
    category = 'ReclaimPause',
    order = 9001,
}
-- Resets the settings. It lives in settings.lua because watch.lua state stays untouched.
keyActions['reclaimpause_defaults'] = {
    action = 'UI_Lua import("/mods/ReclaimPause/modules/settings.lua").ReclaimPauseResetDefaults()',
    category = 'ReclaimPause',
    order = 9002,
}
