-- A player who touches nothing at the start of a match: the mod waits 5 seconds, watches the selection for about
-- a second, pauses the game and says so in the chat. The smoke run ends before that. The checks read the state
-- of the game itself, so a message counts only if it went through the chat of the game.
local Test = import("/mods/ModTest/modules/test.lua")
local ChatModel = import("/lua/ui/game/chat/ChatModel.lua")

local DEFAULT_TEXT = "plz hold pause im afk"
local SIGNATURE = 'message sent with "Pause Plz AFK" mod'
local PAUSE_SECONDS = 20
local CHAT_SECONDS = 5

local function InChat(text)
    for _, entry in ChatModel.GetSingleton().History() do
        if string.find(entry.Text, text, 1, true) then
            return true
        end
    end
    return false
end

function Run()
    Test.Check(not SessionIsPaused(), "the match starts without a pause")
    Test.Check(Test.WaitUntil(SessionIsPaused, PAUSE_SECONDS), "the game is paused")
    Test.Check(Test.WaitUntil(function() return InChat(DEFAULT_TEXT) end, CHAT_SECONDS), "the message is in the chat")
    Test.Check(Test.WaitUntil(function() return InChat(SIGNATURE) end, CHAT_SECONDS), "the signature is in the chat")
end
