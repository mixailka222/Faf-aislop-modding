--  Shift+Z: transport unload instead of spread move
--
--  Shift+Z is bound to the built-in action 'shift_spreadattack'. ReUI's hotbuild modifiers
--  cannot give that combo to a contextual action because the combo is already taken, so
--  the only way to keep the binding is to replace the code behind that action.
--
--  The replacement itself is installed by hook/lua/keymap/keyactions.lua, which the hook
--  system appends to the game file, so nothing here runs on key press. This file only
--  keeps the ReUI options page alive (see Options.lua) and carries the module version.

Version = "1.1.0"

pcall(function()
    ReUI.Require
    {
        "ReUI.Options >= 1.0.0",
    }
end)

function Main(isReplay)
    --  Indexing the table loads Options.lua once and registers the page for the ReUI
    --  options window. The toggle itself is read on every key press from the hook file,
    --  so switching it works without reloading the UI.
    local mods = rawget(ReUI.Options, "Mods")
    pcall(function() return mods["shift_z_transport"] end)
end
