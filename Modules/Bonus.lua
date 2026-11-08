-- Bonus mode: extras just for fun, off until you turn it on (/flow settings:
-- "Bonus mode", or /flow bonus on|off). Each extra has its own switch, on by
-- default once Bonus mode is on. To add one: a switch name in B.EXTRAS and
-- code that checks B:Extra(name).
--
--   Spoken  NPCs read their words aloud when you talk to them: the greeting,
--           a quest's story, "how's it going" and the thank-you at the end.
--           The game's own text-to-speech voices, a man's or a woman's voice
--           to match the NPC. Stops when you close the window.

local _, ns = ...
local B = {}
ns.bonus = B

B.EXTRAS = {
    { key = "spoken", label = "Spoken: NPCs read their words aloud", why = "When you talk to an NPC, the game's text-to-speech voice reads what they say (a man's or a woman's voice to match them). It stops when you close the window." },
}

function B:On() return ns.db.bonus.enabled == true end
function B:Extra(key) return self:On() and ns.db.bonus[key] ~= false end

function B:Set(on)
    ns.db.bonus.enabled = on and true or false
    if not on then B.Stop() end
    ns:Print("bonus mode " .. (on and "on" or "off") .. (on and " (/flow settings lists its extras)" or ""))
end

-------------------------------------------------------------------------------
-- Spoken
-------------------------------------------------------------------------------

-- Words only: no colour codes, links or textures, and "$B" line breaks as pauses.
function B.Clean(text)
    if type(text) ~= "string" then return nil end
    local s = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1")
                  :gsub("|T.-|t", ""):gsub("%$[Bb]", " "):gsub("\r?\n", " "):gsub("%s+", " ")
    s = s:match("^%s*(.-)%s*$")
    return s ~= "" and s or nil
end

-- A voice for the NPC: a woman's for sex 3, a man's for 2 (UnitSex), by the
-- voice's name (Windows: "Microsoft Zira", "Microsoft David", ...), else the first.
local FEMALE = { "zira", "hazel", "susan", "eva", "helena", "female", "samantha", "victoria", "karen" }
local MALE = { "david", "mark", "george", "james", "male", "alex", "daniel", "fred" }
function B.PickVoice(voices, sex)
    if type(voices) ~= "table" or #voices == 0 then return nil end
    local want = (sex == 3 and FEMALE) or (sex == 2 and MALE) or nil
    if want then
        for _, v in ipairs(voices) do
            local n = (v.name or ""):lower()
            for _, w in ipairs(want) do
                -- ("female" contains "male": check a woman's names first, then skip them for a man)
                if n:find(w, 1, true) and not (want == MALE and n:find("female", 1, true)) then return v end
            end
        end
    end
    return voices[1]
end

function B.Stop()
    if C_VoiceChat and C_VoiceChat.StopSpeakingText then pcall(C_VoiceChat.StopSpeakingText) end
end

-- Speak through the game's own helper when it has one (it knows this
-- client's way of calling text-to-speech), else straight to the API.
local function speak(text, voice)
    if TextToSpeech_Speak then
        return pcall(TextToSpeech_Speak, text, voice)
    end
    if not (C_VoiceChat and C_VoiceChat.SpeakText) then return false end
    local dest = Enum and Enum.VoiceTtsDestination and Enum.VoiceTtsDestination.LocalPlayback
    if dest then return pcall(C_VoiceChat.SpeakText, voice.voiceID, text, dest, 0, 100) end
    return pcall(C_VoiceChat.SpeakText, voice.voiceID, text, 0, 100)
end

local function say(text)
    if not B:Extra("spoken") then return end
    text = B.Clean(text)
    if not text then return end
    local voices = C_VoiceChat and C_VoiceChat.GetTtsVoices and C_VoiceChat.GetTtsVoices()
    local voice = B.PickVoice(voices, UnitSex and UnitSex("npc"))
    if not voice then
        if not B.warned then B.warned = true; ns:Print("Spoken: this computer has no text-to-speech voices.") end
        return
    end
    B.Stop()   -- one voice at a time: the new window's words replace the last
    local ok, err = speak(text, voice)
    if not ok then ns:Log("bonus", "spoken: " .. tostring(err)) end
end

local function gossipText()
    if C_GossipInfo and C_GossipInfo.GetText then return C_GossipInfo.GetText() end
    return GetGossipText and GetGossipText()
end

ns:On("GOSSIP_SHOW", function() say(gossipText()) end)
ns:On("QUEST_GREETING", function() say(GetGreetingText and GetGreetingText()) end)
ns:On("QUEST_DETAIL", function()
    local story = GetQuestText and GetQuestText() or ""
    local goal = GetObjectiveText and GetObjectiveText() or ""
    say(story .. (goal ~= "" and (" " .. goal) or ""))
end)
ns:On("QUEST_PROGRESS", function() say(GetProgressText and GetProgressText()) end)
ns:On("QUEST_COMPLETE", function() say(GetRewardText and GetRewardText()) end)
ns:On("GOSSIP_CLOSED", function() B.Stop() end)
ns:On("QUEST_FINISHED", function() B.Stop() end)

ns:OnLoad(function(saved) saved.bonus = saved.bonus or {} end)

ns.commands.bonus = function(arg)
    arg = (arg or ""):lower()
    if arg == "on" or arg == "off" then B:Set(arg == "on") return end
    if arg == "say" then say("Hello, traveller. Flow's Spoken extra is working.") return end
    ns:Print("bonus mode " .. (B:On() and "on" or "off") .. "  (/flow bonus on|off|say)")
end
