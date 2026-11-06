-- Diagnostics Claude can read from disk. WoW only lets addons write their
-- saved data (WTF\Account\<name>\SavedVariables\Flow.lua), and only writes it
-- on /reload, logout or exit. So Flow keeps:
--   FlowDB.diag.log       recent Flow errors and notable events (newest last)
--   FlowDB.diag.snapshot  what /flow api, nav why, rot why and key test say,
--                         taken automatically on every /reload and logout
-- /flow dump takes a snapshot now (then /reload to write it to disk).
-- Read it with tools\read-diag.ps1.

local _, ns = ...
local D = {}
ns.diag = D

local MAX_LINES = 400

local function db() return ns.db and ns.db.diag end

function ns:Log(category, msg)
    local d = db()
    if not d then return end
    local line = string.format("%s [%s] %s", date("%H:%M:%S"), category or "?", tostring(msg))
    local log = d.log
    if log[#log] == line then return end  -- don't flood with repeats
    log[#log + 1] = line
    while #log > MAX_LINES do table.remove(log, 1) end
end

-- Runs Flow's check commands with chat output captured into a list.
-- Uses the game's print-handler hook (made for this), so nothing global is
-- replaced and the output doesn't appear in chat.
local function capture(fn)
    local lines = {}
    if not (getprinthandler and setprinthandler) then
        local ok, err = pcall(fn)
        if not ok then lines[#lines + 1] = "ERROR: " .. tostring(err) end
        lines[#lines + 1] = "(this client can't capture chat output)"
        return lines
    end
    local previous = getprinthandler()
    setprinthandler(function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
        -- Strip colour codes so the file is easy to read.
        lines[#lines + 1] = (table.concat(parts, " "):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
    end)
    local ok, err = pcall(fn)
    setprinthandler(previous)
    if not ok then lines[#lines + 1] = "ERROR: " .. tostring(err) end
    return lines
end

function D:Snapshot(reason)
    local d = db()
    if not d then return end
    local c = ns.commands
    local out = { "taken " .. date("%Y-%m-%d %H:%M:%S") .. " (" .. (reason or "?") .. ")",
                  "version " .. (ns.Version and ns.Version() or "?") .. ", level " .. tostring(UnitLevel("player"))
                      .. ", zone " .. tostring(GetZoneText and GetZoneText()) }
    local checks = {
        { "api", function() c.api("") end },
        { "nav why", function() c.nav("why") end },
        { "rot why", function() c.rot("why") end },
        { "key test", function() c.key("test") end },
        { "party", function() c.party("") end },
        { "gear why", function() c.gear("why") end },
        { "prof plan", function() c.professions("plan") end },
        { "tests", function() c.test("") end },
    }
    for _, chk in ipairs(checks) do
        if chk[2] then
            out[#out + 1] = "--- " .. chk[1]
            for _, l in ipairs(capture(chk[2])) do out[#out + 1] = l end
        end
    end
    d.snapshot = out
end

-- Lua errors from Flow's own files go into the log (and still show as usual).
local function hookErrors()
    if not (geterrorhandler and seterrorhandler) then return end
    local previous = geterrorhandler()
    seterrorhandler(function(err, ...)
        local s = tostring(err)
        if s:find("AddOns[/\\]Flow[/\\]") or s:find("Flow\\Modules") or s:find("Flow/Modules") then
            pcall(ns.Log, ns, "lua error", s)
        end
        if previous then return previous(err, ...) end
    end)
end

ns:OnLoad(function(saved)
    saved.diag = saved.diag or {}
    saved.diag.log = saved.diag.log or {}
    hookErrors()
    ns:Log("session", "loaded v" .. (ns.Version and ns.Version() or "?"))
end)

-- Fresh snapshot right before the game writes the saved data (reload/logout).
ns:On("PLAYER_LOGOUT", function() D:Snapshot("reload or logout") end)
ns:On("PLAYER_ENTERING_WORLD", function()
    C_Timer.After(10, function() pcall(D.Snapshot, D, "after login") end)
end)

ns.commands.dump = function()
    D:Snapshot("/flow dump")
    ns:Print("diagnostics captured. /reload (or log out) to write them to disk for Claude.")
end

ns:Register("help", "diag", { order = 90, title = "Diagnostics", lines = {
    "/flow dump - capture Flow's checks for Claude to read (then /reload). Also automatic on every /reload.",
} })
