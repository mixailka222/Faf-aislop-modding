do
    local OldCreateUI = CreateUI

    function CreateUI(isReplay)
        OldCreateUI(isReplay)
        if HasCommandLineArg("/modtest") then
            local args = GetCommandLineArg("/modtest", 3)
            ForkThread(import("/mods/ModTest/modules/test.lua").Run, args[1], args[2], args[3])
        end
    end
end
