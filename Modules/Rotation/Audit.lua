-- Press audit: does the key cast what the icon shows?
-- At every press of your Flow key, Flow notes what the big icon showed, what
-- the key was really set to cast at that instant, whether a fight was on
-- (and for how long), and which spell the game then sent. A press where the
-- icon and the key disagree is kept, with a screenshot taken at that moment,
-- so "it showed Moonfire and cast Wrath" can be looked at afterwards instead
-- of guessed at: /flow audit, and the diagnostics.
--
--   /flow audit            the tally and the last disagreements
--   /flow audit shots off  no screenshots (on by default: at most one every
--                          20 s, 8 a session; they go to the game's
--                          Screenshots folder)
--   /flow audit reset
--   /flow mark [note]      "it just happened": notes the moment with what the
--                          icon and the key are right now, and a screenshot

local _, ns = ...
local A, E = ns.api, ns.rotation
local Au = {}
ns.audit = Au

Au.WINDOW = 0.7       -- a cast sent this soon after a press belongs to it
Au.KEEP = 25          -- disagreements kept
Au.SHOT_EVERY = 20    -- seconds between screenshots
Au.SHOT_MAX = 8       -- per session

local function db() return ns.db.audit end

-------------------------------------------------------------------------------
-- Pure parts
-------------------------------------------------------------------------------

-- Do the icon and the key agree? icon / set: the spell (or item) the big
-- icon shows and the one the key is set to. nil on either side means there's
-- nothing to compare (a game command on the key, an action, nothing shown).
function Au.Agree(icon, set)
    if icon == nil or set == nil then return true end
    return icon == set
end

-- What a press came to: "ok" (the game sent what the icon showed), "key"
-- (it sent what the key was set to, which the icon didn't show), "other"
-- (something else), "nothing" (no cast followed: the game refused it, or you
-- were mid-cast).
function Au.Judge(press, cast)
    if not cast then return "nothing" end
    if press.icon == nil or cast == press.icon then return "ok" end
    if cast == press.set then return "key" end
    return "other"
end

-- One kept line: "00:12:31 icon Moonfire, key set to Wrath, cast Wrath; in a
-- fight for 0.3 s; advice Moonfire".
function Au.Line(r)
    local fight = r.combat and (r.sinceFight and string.format("in a fight for %.1f s", r.sinceFight) or "in a fight") or "not in a fight"
    return string.format("%s icon %s, key set to %s, cast %s; %s%s%s%s", r.at or "?", tostring(r.icon), tostring(r.set),
        tostring(r.cast or "nothing"), fight, r.advice and ("; advice " .. r.advice) or "",
        r.lockedTo and ("; locked to " .. r.lockedTo) or "", r.shot and "; screenshot" or "")
end

function Au.Report(data)
    local out = {}
    local n = data.counts or {}
    local total = (n.ok or 0) + (n.key or 0) + (n.other or 0) + (n.nothing or 0)
    if total == 0 then
        out[1] = "no key presses recorded yet."
        return out
    end
    out[1] = string.format("%d key presses: %d cast what the icon showed, %d cast the key's spell while the icon showed another, %d cast something else, %d cast nothing",
        total, n.ok or 0, n.key or 0, n.other or 0, n.nothing or 0)
    out[2] = string.format("the icon and the key disagreed at %d press(es)%s", data.disagreed or 0,
        (data.disagreed or 0) > 0 and ":" or " (the key casts what the icon shows).")
    for i = #(data.list or {}), math.max(1, #(data.list or {}) - 11), -1 do out[#out + 1] = "  " .. Au.Line(data.list[i]) end
    return out
end

-------------------------------------------------------------------------------
-- Recording
-------------------------------------------------------------------------------

local last          -- the press waiting for its cast
local shots, shotAt = 0, -math.huge

local function keep(r)
    local d = db()
    d.list[#d.list + 1] = r
    while #d.list > Au.KEEP do table.remove(d.list, 1) end
end

local function shoot()
    if db().shots == false or type(Screenshot) ~= "function" then return false end
    if shots >= Au.SHOT_MAX or GetTime() - shotAt < Au.SHOT_EVERY then return false end
    shots, shotAt = shots + 1, GetTime()
    return (pcall(Screenshot))
end

local function settle(cast)
    if not last then return end
    local d = db()
    local kind = Au.Judge(last, cast)
    d.counts[kind] = (d.counts[kind] or 0) + 1
    if last.kept then last.kept.cast = cast end
    last = nil
end

-- A press of the key itself (Cast.lua calls it; not Ctrl / Shift / Alt + key).
--   icon: what the big icon shows; set: what the key is set to cast now
function Au.Press(icon, set, inCombat, sinceFight, lockedTo)
    if last then settle(nil) end   -- the press before got no cast
    local advice = E.current and (E.current.spell or E.current.label) or nil
    last = { t = GetTime(), icon = icon, set = set, combat = inCombat, sinceFight = sinceFight }
    if not Au.Agree(icon, set) then
        local d = db()
        d.disagreed = (d.disagreed or 0) + 1
        local r = { at = date("%H:%M:%S"), icon = icon, set = set, combat = inCombat, sinceFight = sinceFight,
                    advice = advice, lockedTo = lockedTo }
        r.shot = shoot() or nil
        keep(r)
        last.kept = r
        ns:Log("press", "icon and key disagree: " .. Au.Line(r))
    end
end

ns:On("UNIT_SPELLCAST_SENT", function(unit, _, _, spellID)
    if unit ~= "player" or not last then return end
    if GetTime() - last.t > Au.WINDOW then settle(nil) return end
    settle((A.SpellInfo(A.Safe(spellID) or 0)))
end)

ns:OnLoad(function(saved)
    saved.audit = saved.audit or {}
    saved.audit.list = saved.audit.list or {}
    saved.audit.counts = saved.audit.counts or {}
end)
ns:PerCharacter("audit")

ns.commands.audit = function(arg)
    arg = (arg or ""):lower()
    local d = db()
    if arg == "reset" then
        wipe(d.list); wipe(d.counts); d.disagreed = nil
        ns:Print("press audit cleared")
        return
    end
    local shotsArg = arg:match("^shots%s+(o[nf]f?)$")
    if shotsArg then
        d.shots = (shotsArg == "on")
        ns:Print("press audit screenshots: " .. shotsArg)
        return
    end
    ns:Print("press audit (does the key cast what the icon shows?):")
    for _, line in ipairs(Au.Report(d)) do print("  " .. line) end
    print("  /flow audit reset   /flow audit shots on|off   /flow mark [note]")
end

-- "It just happened": the moment, as Flow sees it, and a screenshot.
ns.commands.mark = function(arg)
    local C = ns.cast
    local held = C and C.Held and C:Held()
    local shot = shoot()
    ns:Log("mark", string.format("%s | icon %s | key locked to %s | advice %s | in a fight %s%s",
        (arg and arg ~= "") and arg or "(no note)", tostring(E.iconShows), tostring(held and held.spell),
        tostring(E.current and (E.current.spell or E.current.label)), tostring(InCombatLockdown() and true or false),
        shot and " | screenshot" or ""))
    ns:Print("marked for the diagnostics" .. (shot and ", with a screenshot." or "."))
end

ns:Register("help", "audit", { order = 48, title = "Press audit", lines = {
    "/flow audit: how often your key cast what the icon showed, and each press where the two disagreed (a screenshot is taken then).",
    "/flow mark [note]: note the moment something looked wrong, with a screenshot, for the diagnostics.",
} })
