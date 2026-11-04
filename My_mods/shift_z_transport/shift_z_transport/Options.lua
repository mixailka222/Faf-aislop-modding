--  ReUI options page for shift_z_transport.
--
--  Assigning ReUI.Options.Mods creates the option objects and reads their stored values
--  from the preference file. Main() runs when the options window is opened and only adds
--  the page to it.

local Opt = rawget(ReUI.Options, "OptionValue") or rawget(ReUI.Options, "Opt")

ReUI.Options.Mods["shift_z_transport"] = {
    enabled = Opt(true),
}

function Main()
    local builder = ReUI.Options.Builder
    local options = ReUI.Options.Mods["shift_z_transport"]

    builder.AddOptions("shift_z_transport", "Shift+Z Transport Unload", {
        builder.Title("Shift+Z", 16),
        builder.Filter("Transports selected: unload order instead of spread move", options.enabled, 0),
    })
end
