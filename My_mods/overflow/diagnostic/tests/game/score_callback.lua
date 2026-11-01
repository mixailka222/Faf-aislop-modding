-- stand: expect OverflowTest: registered AddOnSyncHashedCallback(key="Score", id="OverflowTest")

-- The diagnostic mod registers its callback at the start of a match and the callback gets Sync.Score.
local Test = import("/mods/ModTest/modules/test.lua")

local SAMPLES = 2

function Run()
    local Testing = import("/mods/overflow_testing/modules/main.lua")
    local Watchdog = Test.Upvalue(Testing.OnCreateUI, "Watchdog")
    local function Samples()
        return Test.Upvalue(Watchdog, "nSyncSamples")
    end
    Test.Check(Test.WaitUntil(function() return Samples() >= SAMPLES end, 15), "the callback got Sync.Score")
    Test.Step("samples: " .. tostring(Samples()) .. ", errors: " .. tostring(Test.Upvalue(Watchdog, "nErrors")))
    Test.Check(Test.Upvalue(Watchdog, "nErrors") == 0, "the callback had no errors")
end
