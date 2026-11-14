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
function FP.Level() return UnitLevel and tonumber(UnitLevel("player")) or 0 end
-- Pure: is this "no flight path here" note still holding the stop back? rec:
-- { level = your level when they had none } (true: an older note, from before
-- Flow kept the level: it no longer holds, so they are asked once more).
function FP.Waits(rec, level)
    if not rec then return false end
    if type(rec) ~= "table" then return false end
    return (level or 0) <= (rec.level or 0)
end
function FP.Learned(fm, talked, known, same)
    if talked and talked[fm.name] then return true end
    -- ("Seikwa did not have a flight path for me, though you suggested
    -- learning it": you talked to them and no flight map came. Not again
    -- at this level: FP.Waits.)
    if ns.db and ns.db.flightNone and FP.Waits(ns.db.flightNone[fm.name], FP.Level()) then return true end
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
-- here: where you are ({ map, cont, wx, wy }); a flight master on your map
-- within FP.HERE yards is a stop in its own right, not only "when it's on
-- the way": "I'm in Orgrimmar and it isn't telling me to learn the flight
-- path while I'm here, and I think it should" (0.35.212; it stood 440 yd
-- off, past the 250 yd an optional stop may add).
FP.HERE = 800
function FP.IsHere(fm, here, reach)
    if not (here and fm.map and fm.map == here.map and fm.cont == here.cont and fm.wx and here.wx) then return false end
    local dx, dy = fm.wx - here.wx, fm.wy - here.wy
    return dx * dx + dy * dy <= (reach or FP.HERE) ^ 2
end
function FP.Goals(list, talked, known, here)
    local out, seen = {}, {}
    for _, fm in ipairs(list or {}) do
        if fm.name and not seen[fm.name] and not FP.Learned(fm, talked, known) then
            seen[fm.name] = true
            local close = FP.IsHere(fm, here)
            out[#out + 1] = {
                key = "flightpath:" .. fm.name, kind = "flight", optional = (not close) or nil, weight = close and 0.8 or 1,
                npcs = { fm.name }, points = { { map = fm.map, x = fm.x, y = fm.y } },
                title = "Flight path", text = "Learn the flight path: " .. fm.name,
                details = { "You don't have this flight path yet. Talk to " .. fm.name .. " once: it's free, and later trips through here are shorter for it.",
                            "Only on the route while it's close to the way you're going anyway." },
            }
        end
    end
    return out
end

-- Pure: the list without the NPCs who carry you somewhere themselves (the
-- "ride" registry, Rides.lua: Silva Fil'naveth and Bunthen Plainswind fly
-- druids out of Moonglade). They have no flight path to learn: "I cannot
-- learn the Silva flight path; can you stop telling people to learn it?"
-- (0.35.218). The quest data flags them as flight masters all the same.
function FP.NotRides(list, isRide)
    local out = {}
    for _, fm in ipairs(list or {}) do
        if not (fm.name and isRide and isRide(fm.name)) then out[#out + 1] = fm end
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
        -- (Without the druids' own flyers in Moonglade: FP.NotRides.)
        list = FP.NotRides(list, function(name) return ns:Get("ride", name) ~= nil end)
        cache.at, cache.goals = now, FP.Goals(list, ns.db.flightTalked, ns.db.flights, ns.nav and ns.nav:PlayerPos() or nil)
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
-- You talked to someone Flow took for a flight master and no flight map
-- opened within a few seconds: they have no flight path for you yet. Their
-- stop goes until you've gained a level, then it's offered again ("Seikwa
-- only becomes the flight master after some quests or events, so don't
-- remove her entirely": Flow can't see which quest opens her, so it asks
-- once per level; per character).
ns:OnLoad(function(saved)
    saved.flightNone = saved.flightNone or {}
    -- Notes from before 0.35.203 were for good: give them a level of 0, so
    -- they're asked about again.
    for name, rec in pairs(saved.flightNone) do
        if rec == true then saved.flightNone[name] = { level = 0 } end
    end
end)
ns:PerCharacter("flightNone")
FP.WAIT = 3
function FP.NoPath(name)
    if type(name) ~= "string" or name == "" or ns.db.flightTalked[name] then return false end
    ns.db.flightNone[name] = { level = FP.Level(), at = time() }
    cache.goals = nil
    ns:Print(name .. " has no flight path for you yet: Flow will try them again when you've gained a level.")
    if ns.nav and ns.nav.Collect then pcall(ns.nav.Collect, ns.nav) end
    return true
end
local function talkedTo()
    local who = ns.api.Safe(UnitName and UnitName("npc"))
    if not who or not cache.goals then return end
    local mine = false
    for _, g in ipairs(cache.goals) do if g.key == "flightpath:" .. who then mine = true end end
    if not mine then return end
    C_Timer.After(FP.WAIT, function()
        if not ns.db.flightTalked[who] then FP.NoPath(who) end
    end)
end
ns:On("GOSSIP_SHOW", talkedTo)
ns:On("MERCHANT_SHOW", talkedTo)
ns:On("QUEST_GREETING", talkedTo)

function FP._Forget() cache.goals = nil end   -- (tests)
