-- Flight paths to learn as you pass.
--
-- tools\route-check.ps1 (0.35.198) on a level 13 druid's route: five flight
-- masters within 160 yards of a stop, none of them learned, and no stop for
-- any ("flight path not learned, 43 yd from a stop on your route"). A flight
-- path costs nothing but the few steps to its master, and every later trip
-- through that town is shorter for it.
--
-- So the route gets "Learn the flight path: <name>" for each flight master
-- Flow can find on your continent whose path you don't have. They're
-- optional stops: the planner takes one only when it's close to the way
-- you're going anyway (its usual detour limit), never as a trip of its own.
-- A path counts as learned once you've opened that master's flight map (Flow
-- remembers who you talked to, per character), or when one of the flight
-- points you know lies where they stand.
--
-- Its own kind of stop on the route ("Flight paths to learn"): untick it in
-- the Flow menu, Route includes.

local _, ns = ...
local FP = {}
ns.flightPaths = FP

FP.SAME = 250    -- yards: a flight point you know this close to a flight master is theirs
FP.MAX = 30      -- flight masters looked at (the nearest)
FP.KEEP = 5      -- seconds the list is kept (stops are collected often)

-- Pure: is this flight master's path one you have? talked: [name] = true for
-- the ones whose map you've opened; known: your flight points ({ cont, wx,
-- wy } each); fm: { name, cont, wx, wy }.
function FP.Learned(fm, talked, known, same)
    if talked and talked[fm.name] then return true end
    same = same or FP.SAME
    for _, k in pairs(known or {}) do
        if k.cont == fm.cont and k.wx and fm.wx then
            local dx, dy = k.wx - fm.wx, k.wy - fm.wy
            if dx * dx + dy * dy <= same * same then return true end
        end
    end
    return false
end

-- Pure: the stops for a list of flight masters (S:All: { name, map, x, y,
-- cont, wx, wy }): one for each not learned, a name once.
function FP.Goals(list, talked, known)
    local out, seen = {}, {}
    for _, fm in ipairs(list or {}) do
        if fm.name and not seen[fm.name] and not FP.Learned(fm, talked, known) then
            seen[fm.name] = true
            out[#out + 1] = {
                key = "flightpath:" .. fm.name, kind = "flight", optional = true, weight = 1,
                npcs = { fm.name }, points = { { map = fm.map, x = fm.x, y = fm.y } },
                title = "Flight path", text = "Learn the flight path: " .. fm.name,
                details = { "You don't have this flight path yet. Talk to " .. fm.name .. " once: it's free, and later trips through here are shorter for it.",
                            "Only on the route while it's close to the way you're going anyway." },
            }
        end
    end
    return out
end

local cache = { at = 0, goals = nil }
ns:Register("navGoal", "flightpath", {
    collect = function()
        local now = GetTime()
        if cache.goals and now - cache.at < FP.KEEP then return cache.goals end
        local S = ns.services
        if not (S and S.All) then return nil end
        local ok, list = pcall(S.All, S, "flight", FP.MAX)
        if not ok then return nil end
        cache.at, cache.goals = now, FP.Goals(list, ns.db.flightTalked, ns.db.flights)
        return cache.goals
    end,
})

ns:Register("routeKind", "flightpaths", { order = 65, default = true,
    label = "Flight paths to learn (when you pass one)", short = "flight paths",
    tip = "A stop at a flight master whose path you don't have, when it's close to the way you're going anyway. Free, and it shortens every later trip.",
    match = function(g) return g.provider == "flightpath" end })

-- You opened a flight master's map: you have their path now.
ns:OnLoad(function(saved) saved.flightTalked = saved.flightTalked or {} end)
ns:PerCharacter("flightTalked")
function FP.Talked(name)
    if type(name) ~= "string" or name == "" then return false end
    ns.db.flightTalked[name] = true
    cache.goals = nil
    if ns.nav and ns.nav.Collect then pcall(ns.nav.Collect, ns.nav) end
    return true
end
ns:On("TAXIMAP_OPENED", function()
    local who = UnitName and (UnitName("npc") or UnitName("target"))
    who = ns.api.Safe(who)
    if who then FP.Talked(who) end
end)
function FP._Forget() cache.goals = nil end   -- (tests)
