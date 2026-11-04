--  ReUI options page for ShiftZTransport.
--
--  Assigning ReUI.Options.Mods creates the option objects and reads their stored values
--  from the preference file. Main() runs when the options window is opened and only adds
--  the page to it.

local Opt = rawget(ReUI.Options, "OptionValue") or rawget(ReUI.Options, "Opt")
local Mods = rawget(ReUI.Options, "Mods")

Mods["ShiftZTransport"] = {
    enabled = Opt(true),
}

function Main()
    local builder = rawget(ReUI.Options, "Builder")
    local options = Mods["ShiftZTransport"]
    local AddOptions = builder.AddOptions
    local Title = builder.Title
    local Filter = builder.Filter

    AddOptions("ShiftZTransport", "Shift+Z Transport Unload", {
        Title("Shift+Z", 16),
        Filter("Transports unload; factories toggle repeat build", options.enabled, 0),
    })
end
