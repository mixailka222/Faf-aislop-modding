--  ReUI options page for shift_z_transport.
--
--  Assigning ReUI.Options.Mods creates the option objects and reads their stored values
--  from the preference file. Main() runs when the options window is opened and only adds
--  the page to it.

local Opt = rawget(ReUI.Options, "OptionValue") or rawget(ReUI.Options, "Opt")
local Mods = rawget(ReUI.Options, "Mods")

Mods["shift_z_transport"] = {
    enabled = Opt(true),
}

function Main()
    local builder = rawget(ReUI.Options, "Builder")
    local options = Mods["shift_z_transport"]
    local AddOptions = builder.AddOptions
    local Title = builder.Title
    local Filter = builder.Filter

    AddOptions("shift_z_transport", "Shift+Z Transport Unload", {
        Title("Shift+Z", 16),
        Filter("Transports selected: unload order instead of spread move", options.enabled, 0),
    })
end
