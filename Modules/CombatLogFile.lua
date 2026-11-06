-- Combat log FILE (not the in-game combat log events, which this client
-- blocks for addons). WoW writes every fight to
--   _forever_\Logs\WoWCombatLog-<date>.txt
-- while logging is on. tools/analyze-combatlog.ps1 reads those files, writes
-- reports (dps/heal/tank) and feeds results back into Flow (Learned\CombatLog.lua).
--
--   /flow log         turn file logging on/off now (same as /combatlog)
--   /flow log auto    also turn it on automatically every time you log in

local _, ns = ...

local function isLogging()
    return LoggingCombat and LoggingCombat() and true or false
end

local function setLogging(on)
    if not LoggingCombat then
        ns:Print("this client has no combat logging function; type /combatlog instead.")
        return
    end
    LoggingCombat(on)
    ns:Print(on and "combat log is being written to Logs\\WoWCombatLog. Analyse it with tools\\analyze-combatlog.ps1"
        or "combat log file stopped.")
end

ns:OnLoad(function(saved)
    saved.log = saved.log or {}
end)

ns:On("PLAYER_ENTERING_WORLD", function()
    if ns.db.log.auto and not isLogging() then
        C_Timer.After(3, function() pcall(setLogging, true) end)
    end
end)

ns.commands.log = function(arg)
    arg = (arg or ""):lower()
    if arg == "auto" then
        ns.db.log.auto = not ns.db.log.auto
        ns:Print("auto combat logging at login: " .. (ns.db.log.auto and "on" or "off"))
        if ns.db.log.auto and not isLogging() then setLogging(true) end
    elseif arg == "on" or arg == "off" then
        setLogging(arg == "on")
    else
        setLogging(not isLogging())
    end
end
