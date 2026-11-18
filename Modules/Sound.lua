-- WoW's sound, restarted: /flow audioreset, and by itself when your speakers
-- change (0.35.308).
--
-- When the speakers WoW plays through go away and come back (a monitor's
-- speakers vanish whenever the screen sleeps, and while you're away on
-- Remote Desktop), WoW restarts its sound to follow them. Sometimes that
-- restart stops halfway: Logs\Sound.log ends with "Shutting Down SE3
-- COMPLETE" and nothing after, and the game stays silent while every other
-- program plays (seen 2026-11-17: the monitor's speakers came back at
-- 19:30:49, WoW shut its sound down a second later and never started it
-- again). The game's own Audio settings show only "System Default" then.
--
-- /flow audioreset runs the game's own restart (what its Audio settings do
-- when you pick another output). With "Restart WoW's sound when your
-- speakers change" on, Flow runs it by itself a few seconds after the game
-- says its list of speakers changed, once the changes stop, so a restart
-- the game left half done gets finished.

local _, ns = ...
local SND = {}
ns.sound = SND

SND.SETTLE = 3        -- seconds with no more changes before Flow restarts
SND.ECHO = 6          -- seconds after a restart of Flow's when changes are that restart's own
SND.MAX_AUTO = 3      -- automatic restarts a minute, at most

-- The ways this client has to restart its sound, best first: { name, fn }.
-- The console command only when you typed /flow audioreset: if this game
-- keeps the console for itself, that's one "blocked" message you asked for,
-- not one every time your screen sleeps. env: the tests' own.
function SND.Ways(env, byHand)
    env = env or _G
    local out = {}
    if type(env.Sound_GameSystem_RestartSoundSystem) == "function" then
        out[#out + 1] = { name = "Sound_GameSystem_RestartSoundSystem", fn = env.Sound_GameSystem_RestartSoundSystem }
    end
    if byHand and type(env.ConsoleExec) == "function" then
        local exec = env.ConsoleExec
        out[#out + 1] = { name = "the console's Sound_RestartSoundSystem", fn = function() return exec("Sound_RestartSoundSystem") end }
    end
    return out
end

-- Restart it now: true and how, or false and why not. byHand: you asked
-- (/flow audioreset). env: the tests' own (and then nothing is noted).
function SND.Restart(byHand, env)
    local tried = {}
    for _, w in ipairs(SND.Ways(env, byHand)) do
        local ok, err = pcall(w.fn)
        if ok then
            if not env then SND.last, SND.lastWay = GetTime(), w.name end
            return true, w.name
        end
        tried[#tried + 1] = w.name .. ": " .. tostring(err)
    end
    return false, #tried > 0 and table.concat(tried, "; ") or "this game gives add-ons no way to restart its sound"
end

function SND.AutoOn()
    return not (ns.db and ns.db.sound and ns.db.sound.auto == false)
end

-- Pure: restart after a change at `now`? on: the setting; last: when Flow
-- last restarted (its own restart changes the list too, and mustn't start
-- another); recent: when the automatic ones ran. -> yes, or false and why.
function SND.ShouldAuto(on, now, last, recent)
    if not on then return false, "the setting is off" end
    if last and now - last < SND.ECHO then return false, "that was Flow's own restart" end
    local n = 0
    for _, t in ipairs(recent or {}) do if now - t < 60 then n = n + 1 end end
    if n >= SND.MAX_AUTO then return false, string.format("already restarted %d times this minute", n) end
    return true
end

-- The game says when its list of speakers changes. Not every client has
-- that event: registered on a frame of its own, so Flow knows whether it does.
local watch = CreateFrame("Frame")
SND.eventOK = pcall(watch.RegisterEvent, watch, "SOUND_DEVICE_UPDATE") and true or false
local waiting = 0
watch:SetScript("OnEvent", function()
    SND.changes = (SND.changes or 0) + 1
    ns:Log("sound", "the game's list of speakers changed")
    waiting = waiting + 1
    local mine = waiting
    C_Timer.After(SND.SETTLE, function()
        if mine ~= waiting then return end   -- another change came: wait for that one
        local now = GetTime()
        local go, why = SND.ShouldAuto(SND.AutoOn(), now, SND.last, SND.recent)
        if not go then ns:Log("sound", "no restart: " .. why) return end
        SND.recent = SND.recent or {}
        table.insert(SND.recent, now)
        while #SND.recent > SND.MAX_AUTO do table.remove(SND.recent, 1) end
        local ok, how = SND.Restart()
        ns:Log("sound", ok and ("restarted WoW's sound after the speakers changed (" .. how .. ")") or ("couldn't restart WoW's sound: " .. how))
    end)
end)

-- /flow audioreset
function SND.Lines()
    local ways = {}
    for _, w in ipairs(SND.Ways(nil, true)) do ways[#ways + 1] = w.name end
    return {
        "ways to restart it here: " .. (#ways > 0 and table.concat(ways, ", ") or "none"),
        "by itself when your speakers change: " .. (SND.AutoOn() and "on" or "off")
            .. (SND.eventOK and "" or " (but this game doesn't say when they change)")
            .. string.format("; changes seen this session: %d", SND.changes or 0),
    }
end

ns.commands.audioreset = function()
    local ok, how = SND.Restart(true)
    if ok then
        ns:Print("restarted WoW's sound. Still nothing? Pick your speakers under Output Device in the game's Audio settings.")
    else
        ns:Print("couldn't restart WoW's sound (" .. how .. "). Type /console Sound_RestartSoundSystem instead.")
    end
    ns:Log("sound", ok and ("/flow audioreset: restarted (" .. how .. ")") or ("/flow audioreset: " .. how))
    for _, l in ipairs(SND.Lines()) do print("  " .. l) end
end

ns:OnLoad(function()
    ns:Log("sound", (SND.eventOK and "the game says when your speakers change" or "the game doesn't say when your speakers change")
        .. "; " .. SND.Lines()[1])
end)

if ns.settings and ns.settings.AddCheck then
    ns.settings:AddCheck{ group = "more", label = "Restart WoW's sound when your speakers change",
        note = "(/flow audioreset does it by hand)",
        tip = "Monitor speakers vanish while the screen sleeps or while you're on Remote Desktop, and when they come back WoW sometimes "
            .. "stays silent while everything else plays. With this on, Flow restarts the game's sound a few seconds after your "
            .. "speakers change. The sound may cut out for a moment when it does.",
        get = SND.AutoOn,
        set = function(on)
            ns.db.sound = ns.db.sound or {}
            ns.db.sound.auto = on and true or false
        end }
end

ns:Register("help", "audioreset", { order = 48, title = "WoW's sound", lines = {
    "/flow audioreset: restarts the game's sound, for when WoW is silent and everything else plays (after your speakers came back from a sleeping screen or Remote Desktop).",
    "\"Restart WoW's sound when your speakers change\" in Flow Settings (More) does it by itself.",
} })
