-- Chat timestamps, using the game's own setting (Options > Social >
-- Chat Timestamps), so it works for every chat window.
--   /flow chat stamps        turn on (HH:MM:SS)
--   /flow chat stamps short  HH:MM
--   /flow chat stamps off
-- Flow turns them on once by default; if you switch them off it leaves them off.

local _, ns = ...

local FORMATS = { long = "%H:%M:%S ", short = "%H:%M " }

local function set(fmt)
    if InCombatLockdown and InCombatLockdown() then
        ns:Print("can't change chat settings in combat; try after the fight")
        return false
    end
    SetCVar("showTimestamps", fmt or "none")
    return true
end

ns:OnLoad(function(saved)
    saved.chat = saved.chat or {}
end)

ns:On("PLAYER_LOGIN", function()
    local c = ns.db.chat
    if not c.stampsSetOnce then
        c.stampsSetOnce = true
        local now = GetCVar and GetCVar("showTimestamps")
        if now == nil or now == "none" or now == "" then set(FORMATS.long) end
    end
end)

ns.commands.chat = function(arg)
    local what, opt = (arg or ""):lower():match("^(%S*)%s*(%S*)")
    if what == "stamps" then
        if opt == "off" then
            if set(nil) then ns:Print("chat timestamps off") end
        else
            if set(FORMATS[opt] or FORMATS.long) then ns:Print("chat timestamps on (" .. (opt == "short" and "HH:MM" or "HH:MM:SS") .. ")") end
        end
        print("  If old messages don't show them, new ones will; /reload if none do.")
    else
        ns:Print("/flow chat stamps [short|off]")
    end
end

ns:Register("help", "chat", { order = 15, title = "Chat", lines = {
    "/flow chat stamps [short|off] - timestamps on chat lines (on by default)",
} })
