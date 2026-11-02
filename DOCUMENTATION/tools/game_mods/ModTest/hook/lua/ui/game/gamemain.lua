do
    local OldCreateUI = CreateUI

    function CreateUI(isReplay)
        OldCreateUI(isReplay)
        if HasCommandLineArg("/modtest") then
            local args = GetCommandLineArg("/modtest", 2)
            ForkThread(import("/mods/ModTest/modules/test.lua").Run, args[1], args[2])
        end
    end
end
